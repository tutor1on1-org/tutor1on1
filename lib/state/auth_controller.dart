import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../db/app_database.dart';
import '../security/pin_hasher.dart';
import '../services/auth_api_service.dart';
import '../services/browser_auth_session.dart' as browser_auth;
import '../services/browser_exclusive_lock.dart';
import '../services/device_identity_service.dart';
import '../services/log_crypto_service.dart';
import '../services/secure_storage_service.dart';
import 'study_mode_controller.dart';

typedef AuthSessionValidator = Future<void> Function();
typedef BrowserAuthUserReader = int? Function();
typedef BrowserAuthUserWriter = void Function(int? remoteUserId);

class AuthController extends ChangeNotifier {
  AuthController(
    AppDatabase db,
    SecureStorageService secureStorage, {
    AuthApiService? authApi,
    DeviceIdentityService? deviceIdentityService,
    StudyModeController? studyModeController,
    AuthSessionValidator? authSessionValidator,
    Stream<int?>? browserAuthUserChanges,
    BrowserAuthUserReader? browserAuthUserReader,
    BrowserAuthUserWriter? browserAuthUserWriter,
  })  : _authApi = authApi ??
            AuthApiService(
              baseUrl: kAuthBaseUrl,
              allowInsecureTls: kAuthAllowInsecureTls,
            ),
        _db = db,
        _secureStorage = secureStorage,
        _studyModeController = studyModeController,
        _authSessionValidator = authSessionValidator,
        _browserAuthUserReader =
            browserAuthUserReader ?? browser_auth.readBrowserAuthUser,
        _browserAuthUserWriter =
            browserAuthUserWriter ?? browser_auth.writeBrowserAuthUser,
        _deviceIdentityService =
            deviceIdentityService ?? DeviceIdentityService(secureStorage) {
    _authSessionInvalidatedSubscription =
        _secureStorage.authSessionInvalidated.listen((_) {
      _handleAuthSessionInvalidated();
    });
    _browserAuthUserSubscription =
        (browserAuthUserChanges ?? browser_auth.browserAuthUserChanges)
            .listen(_handleBrowserAuthUserChanged);
  }

  final AppDatabase _db;
  final SecureStorageService _secureStorage;
  final AuthApiService _authApi;
  final DeviceIdentityService _deviceIdentityService;
  final StudyModeController? _studyModeController;
  final AuthSessionValidator? _authSessionValidator;
  final BrowserAuthUserReader _browserAuthUserReader;
  final BrowserAuthUserWriter _browserAuthUserWriter;
  late final StreamSubscription<void> _authSessionInvalidatedSubscription;
  late final StreamSubscription<int?> _browserAuthUserSubscription;
  User? _currentUser;
  String? _lastError;
  bool _remoteSessionInvalidated = false;

  User? get currentUser => _currentUser;
  String? get lastError => _lastError;
  bool get remoteSessionInvalidated => _remoteSessionInvalidated;

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
    return _runWithAuthSessionLocks<User>(
      response.userId,
      () async {
        await _secureStorage.writeAuthTokens(
          accessToken: response.accessToken,
          refreshToken: response.refreshToken,
        );
        _remoteSessionInvalidated = false;
        await _secureStorage.deleteRemoteStudyModePinHash();
        final normalizedUsername = username.trim().toLowerCase();
        final hashed = PinHasher.hash(password);
        final user = await _db.upsertAuthenticatedUser(
          username: normalizedUsername,
          pinHash: hashed,
          role: response.role,
          remoteUserId: response.userId > 0 ? response.userId : null,
        );
        _currentUser = user;
        await _studyModeController?.syncAuthUser(user);
        await activateLogAccess(password);
        _browserAuthUserWriter(user.remoteUserId);
        _secureStorage.bindAuthRemoteUser(user.remoteUserId);
        notifyListeners();
        return user;
      },
    );
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
    final remoteUserId = _currentUser?.remoteUserId ?? 0;
    await _runWithAuthSessionLocks<bool>(
      remoteUserId,
      () async {
        final activeBrowserUserId = _browserAuthUserReader();
        final sharedSessionChanged = activeBrowserUserId != null &&
            (remoteUserId <= 0 || activeBrowserUserId != remoteUserId);
        LogCryptoService.instance.clear();
        _currentUser = null;
        _lastError = null;
        _remoteSessionInvalidated = false;
        _secureStorage.bindAuthRemoteUser(null);
        await _studyModeController?.clear();
        if (!sharedSessionChanged) {
          await _secureStorage.deleteAuthTokens();
          await _secureStorage.deleteRemoteStudyModePinHash();
          _browserAuthUserWriter(null);
        }
        notifyListeners();
        return true;
      },
    );
  }

  Future<T> _runWithAuthSessionLocks<T>(
    int remoteUserId,
    Future<T> Function() action,
  ) async {
    final result = await runWithBrowserExclusiveLock<T>(
      browserSyncLockName(remoteUserId),
      () async {
        final authResult = await runWithBrowserExclusiveLock<T>(
          browserAuthRefreshLockName,
          action,
        );
        if (authResult == null) {
          throw StateError('Could not acquire the browser auth-token lock.');
        }
        return authResult;
      },
    );
    if (result == null) {
      throw StateError('Could not acquire the browser auth-session lock.');
    }
    return result;
  }

  Future<bool> validateCurrentSession() async {
    final current = currentUser;
    if (current == null) {
      return false;
    }
    final remoteUserId = current.remoteUserId;
    final validator = _authSessionValidator;
    if (remoteUserId == null || remoteUserId <= 0 || validator == null) {
      return true;
    }
    try {
      await validator();
      return currentUser != null;
    } on Object {
      if (currentUser == null) {
        return false;
      }
      rethrow;
    }
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

  void _handleAuthSessionInvalidated() {
    if (_currentUser == null) {
      return;
    }
    LogCryptoService.instance.clear();
    _currentUser = null;
    _lastError = null;
    _remoteSessionInvalidated = true;
    _secureStorage.bindAuthRemoteUser(null);
    _browserAuthUserWriter(null);
    notifyListeners();
    unawaited(_finishInvalidatedSessionCleanup());
  }

  void _handleBrowserAuthUserChanged(int? remoteUserId) {
    final current = _currentUser;
    if (current == null ||
        (remoteUserId != null && current.remoteUserId == remoteUserId)) {
      return;
    }
    LogCryptoService.instance.clear();
    _currentUser = null;
    _lastError = null;
    _remoteSessionInvalidated = false;
    _secureStorage.bindAuthRemoteUser(null);
    notifyListeners();
    unawaited(_finishBrowserAuthUserChange());
  }

  Future<void> _finishBrowserAuthUserChange() async {
    try {
      await _studyModeController?.clear();
    } on Object catch (error) {
      debugPrint('Cross-tab auth-session cleanup failed: $error');
    }
  }

  Future<void> _finishInvalidatedSessionCleanup() async {
    try {
      await _studyModeController?.clear();
      await _secureStorage.deleteRemoteStudyModePinHash();
    } on Object catch (error) {
      debugPrint('Revoked-session cleanup failed: $error');
    }
  }

  @override
  void dispose() {
    unawaited(_authSessionInvalidatedSubscription.cancel());
    unawaited(_browserAuthUserSubscription.cancel());
    super.dispose();
  }
}
