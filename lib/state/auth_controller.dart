import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../db/app_database.dart';
import '../security/pin_hasher.dart';
import '../services/auth_api_service.dart';
import '../services/secure_storage_service.dart';

class AuthController extends ChangeNotifier {
  AuthController(this._db, this._secureStorage)
      : _authApi = AuthApiService(
          baseUrl: kAuthBaseUrl,
          allowInsecureTls: kAuthAllowInsecureTls,
        );

  final AppDatabase _db;
  final SecureStorageService _secureStorage;
  final AuthApiService _authApi;
  User? _currentUser;
  String? _lastError;

  User? get currentUser => _currentUser;
  String? get lastError => _lastError;

  Future<bool> login(String username, String password) async {
    _lastError = null;
    try {
      final response = await _authApi.login(
        username: username,
        password: password,
      );
      await _persistAuth(response, username, password);
      return true;
    } on AuthApiException catch (error) {
      _lastError = error.message;
      return false;
    }
  }

  Future<User?> registerTeacher({
    required String username,
    required String email,
    required String password,
    required String displayName,
    String? bio,
    String? avatarUrl,
    String? contact,
    required bool contactPublished,
  }) async {
    _lastError = null;
    try {
      final response = await _authApi.registerTeacher(
        username: username,
        email: email,
        password: password,
        displayName: displayName,
        bio: bio,
        avatarUrl: avatarUrl,
        contact: contact,
        contactPublished: contactPublished,
      );
      return await _persistAuth(response, username, password);
    } on AuthApiException catch (error) {
      _lastError = error.message;
      return null;
    }
  }

  Future<User?> registerStudent({
    required String username,
    required String email,
    required String password,
  }) async {
    _lastError = null;
    try {
      final response = await _authApi.registerStudent(
        username: username,
        email: email,
        password: password,
      );
      return await _persistAuth(response, username, password);
    } on AuthApiException catch (error) {
      _lastError = error.message;
      return null;
    }
  }

  Future<User?> _persistAuth(
    AuthResponse response,
    String username,
    String password,
  ) async {
    await _secureStorage.writeAuthTokens(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
    );
    final normalizedUsername = username.trim().toLowerCase();
    final existing = await _db.findUserByUsername(normalizedUsername);
    final hashed = PinHasher.hash(password);
    if (existing == null) {
      final userId = await _db.createUser(
        username: normalizedUsername,
        pinHash: hashed,
        role: response.role,
        teacherId: null,
        remoteUserId: response.userId > 0 ? response.userId : null,
      );
      _currentUser = await _db.getUserById(userId);
    } else {
      await _db.updateUserAuth(
        userId: existing.id,
        pinHash: hashed,
        role: response.role,
        remoteUserId: response.userId > 0 ? response.userId : null,
      );
      _currentUser = await _db.getUserById(existing.id);
    }
    notifyListeners();
    return _currentUser;
  }

  Future<void> logout() async {
    _currentUser = null;
    _lastError = null;
    await _secureStorage.deleteAuthTokens();
    notifyListeners();
  }

  Future<void> refreshCurrentUser() async {
    final current = _currentUser;
    if (current == null) {
      return;
    }
    _currentUser = await _db.getUserById(current.id);
    notifyListeners();
  }
}
