import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../db/app_database.dart';
import '../security/pin_hasher.dart';
import '../services/auth_api_service.dart';
import '../services/device_identity_service.dart';
import '../services/log_crypto_service.dart';
import '../services/secure_storage_service.dart';
import 'study_mode_controller.dart';

class AuthController extends ChangeNotifier {
  AuthController(
    AppDatabase db,
    SecureStorageService secureStorage, {
    AuthApiService? authApi,
    DeviceIdentityService? deviceIdentityService,
    StudyModeController? studyModeController,
  })  : _authApi = authApi ??
            AuthApiService(
              baseUrl: kAuthBaseUrl,
              allowInsecureTls: kAuthAllowInsecureTls,
            ),
        _db = db,
        _secureStorage = secureStorage,
        _studyModeController = studyModeController,
        _deviceIdentityService =
            deviceIdentityService ?? DeviceIdentityService(secureStorage);

  final AppDatabase _db;
  final SecureStorageService _secureStorage;
  final AuthApiService _authApi;
  final DeviceIdentityService _deviceIdentityService;
  final StudyModeController? _studyModeController;
  User? _currentUser;
  String? _lastError;

  User? get currentUser => _currentUser;
  String? get lastError => _lastError;

  Future<bool> login(String username, String password) async {
    _lastError = null;
    final normalizedUsername = username.trim().toLowerCase();
    try {
      final device = await _deviceIdentityService.snapshot();
      final response = await _authApi.login(
        username: normalizedUsername,
        password: password,
        deviceKey: device.deviceKey,
        deviceName: device.deviceName,
        platform: device.platform,
        timezoneName: device.timezoneName,
        timezoneOffsetMinutes: device.timezoneOffsetMinutes,
        appVersion: device.appVersion,
      );
      await _persistAuth(response, normalizedUsername, password);
      return true;
    } on AuthApiException catch (error) {
      _lastError = error.message;
      return false;
    } on Object catch (error) {
      _lastError = 'Login failed: $error';
      return false;
    }
  }

  Future<User?> registerTeacher({
    required String username,
    required String email,
    required String password,
    required String displayName,
    List<int> subjectLabelIds = const <int>[],
    String? bio,
    String? avatarUrl,
    String? contact,
    required bool contactPublished,
  }) async {
    _lastError = null;
    try {
      final device = await _deviceIdentityService.snapshot();
      final response = await _authApi.registerTeacher(
        username: username,
        email: email,
        password: password,
        displayName: displayName,
        subjectLabelIds: subjectLabelIds,
        bio: bio,
        avatarUrl: avatarUrl,
        contact: contact,
        contactPublished: contactPublished,
        deviceKey: device.deviceKey,
        deviceName: device.deviceName,
        platform: device.platform,
        timezoneName: device.timezoneName,
        timezoneOffsetMinutes: device.timezoneOffsetMinutes,
        appVersion: device.appVersion,
      );
      return await _persistAuth(response, username, password);
    } on AuthApiException catch (error) {
      _lastError = error.message;
      return null;
    } on Object catch (error) {
      _lastError = 'Registration failed: $error';
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
      final device = await _deviceIdentityService.snapshot();
      final response = await _authApi.registerStudent(
        username: username,
        email: email,
        password: password,
        deviceKey: device.deviceKey,
        deviceName: device.deviceName,
        platform: device.platform,
        timezoneName: device.timezoneName,
        timezoneOffsetMinutes: device.timezoneOffsetMinutes,
        appVersion: device.appVersion,
      );
      return await _persistAuth(response, username, password);
    } on AuthApiException catch (error) {
      _lastError = error.message;
      return null;
    } on Object catch (error) {
      _lastError = 'Registration failed: $error';
      return null;
    }
  }

  Future<bool> requestRecovery(String email) async {
    _lastError = null;
    try {
      final response = await _authApi.requestRecovery(
        email: email,
      );
      if (response.status != 'ok') {
        _lastError = 'Recovery request failed.';
        return false;
      }
      return true;
    } on AuthApiException catch (error) {
      _lastError = error.message;
      return false;
    } on Object catch (error) {
      _lastError = 'Recovery request failed: $error';
      return false;
    }
  }

  Future<bool> resetPassword({
    required String email,
    required String recoveryToken,
    required String newPassword,
  }) async {
    _lastError = null;
    try {
      final response = await _authApi.resetPassword(
        email: email,
        recoveryToken: recoveryToken,
        newPassword: newPassword,
      );
      if (response.status != 'ok') {
        _lastError = 'Password reset failed.';
        return false;
      }
      return true;
    } on AuthApiException catch (error) {
      _lastError = error.message;
      return false;
    } on Object catch (error) {
      _lastError = 'Password reset failed: $error';
      return false;
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
    await _secureStorage.deleteRemoteStudyModePinHash();
    final normalizedUsername = username.trim().toLowerCase();
    final hashed = PinHasher.hash(password);
    _currentUser = await _db.upsertAuthenticatedUser(
      username: normalizedUsername,
      pinHash: hashed,
      role: response.role,
      remoteUserId: response.userId > 0 ? response.userId : null,
    );
    await _studyModeController?.syncAuthUser(_currentUser);
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
    await _studyModeController?.clear();
    await _secureStorage.deleteAuthTokens();
    await _secureStorage.deleteRemoteStudyModePinHash();
    notifyListeners();
  }

  Future<void> refreshCurrentUser() async {
    final current = _currentUser;
    if (current == null) {
      return;
    }
    _currentUser = await _db.getUserById(current.id);
    await _studyModeController?.syncAuthUser(_currentUser);
    notifyListeners();
  }
}
