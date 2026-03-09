import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../db/app_database.dart';
import '../security/pin_hasher.dart';
import '../services/auth_api_service.dart';
import '../services/log_crypto_service.dart';
import '../services/secure_storage_service.dart';

class AuthController extends ChangeNotifier {
  AuthController(
    this._db,
    this._secureStorage, {
    AuthApiService? authApi,
  }) : _authApi = authApi ??
            AuthApiService(
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
    final normalizedUsername = username.trim().toLowerCase();
    final localAdmin = await _db.findUserByUsername(normalizedUsername);
    if (localAdmin != null &&
        localAdmin.role == 'admin' &&
        localAdmin.pinHash == PinHasher.hash(password)) {
      _currentUser = localAdmin;
      await activateLogAccess(password);
      notifyListeners();
      return true;
    }
    try {
      final response = await _authApi.login(
        username: normalizedUsername,
        password: password,
      );
      await _persistAuth(response, normalizedUsername, password);
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
    final hashed = PinHasher.hash(password);
    _currentUser = await _db.upsertAuthenticatedUser(
      username: normalizedUsername,
      pinHash: hashed,
      role: response.role,
      remoteUserId: response.userId > 0 ? response.userId : null,
    );
    await activateLogAccess(password);
    notifyListeners();
    return _currentUser;
  }

  Future<void> activateLogAccess(String password) async {
    final current = _currentUser;
    if (current == null) {
      throw StateError('Cannot activate log access without a signed-in user.');
    }
    await LogCryptoService.instance.activate(
      userId: current.id,
      role: current.role,
      password: password,
    );
  }

  Future<void> logout() async {
    LogCryptoService.instance.clear();
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
