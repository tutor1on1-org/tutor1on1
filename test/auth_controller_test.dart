import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/db/app_database.dart';
import 'package:family_teacher/security/pin_hasher.dart';
import 'package:family_teacher/state/auth_controller.dart';
import 'package:family_teacher/services/auth_api_service.dart';
import 'package:family_teacher/services/device_identity_service.dart';
import 'package:family_teacher/services/log_crypto_service.dart';
import 'package:family_teacher/services/secure_storage_service.dart';

class _MemorySecureStorage extends SecureStorageService {
  String? _accessToken;
  String? _refreshToken;

  @override
  Future<String?> readAuthAccessToken() async => _accessToken;

  @override
  Future<String?> readAuthRefreshToken() async => _refreshToken;

  @override
  Future<void> writeAuthTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<void> deleteAuthTokens() async {
    _accessToken = null;
    _refreshToken = null;
  }

  @override
  Future<void> deleteRemoteStudyModePinHash() async {}
}

class _FakeDeviceIdentityService extends DeviceIdentityService {
  _FakeDeviceIdentityService() : super(_MemorySecureStorage());

  @override
  Future<DeviceIdentitySnapshot> snapshot() async {
    return const DeviceIdentitySnapshot(
      deviceKey: 'test-device',
      deviceName: 'Test Device',
      platform: 'windows',
      timezoneName: 'UTC',
      timezoneOffsetMinutes: 0,
      localWeekday: 1,
      localMinuteOfDay: 0,
      appVersion: 'test',
    );
  }
}

class _ThrowingDeviceIdentityService extends DeviceIdentityService {
  _ThrowingDeviceIdentityService() : super(_MemorySecureStorage());

  @override
  Future<DeviceIdentitySnapshot> snapshot() async {
    throw StateError('device identity unavailable');
  }
}

class _FailingAuthApiService extends AuthApiService {
  _FailingAuthApiService()
      : super(
          baseUrl: 'https://example.com',
          allowInsecureTls: false,
        );

  @override
  Future<AuthResponse> login({
    required String username,
    required String password,
    required String deviceKey,
    required String deviceName,
    required String platform,
    required String timezoneName,
    required int timezoneOffsetMinutes,
    String appVersion = '',
  }) async {
    throw AuthApiException(
      'invalid credentials',
      statusCode: 401,
    );
  }
}

class _FakeAuthApiService extends AuthApiService {
  _FakeAuthApiService(this._response)
      : super(
          baseUrl: 'https://example.com',
          allowInsecureTls: false,
        );

  final AuthResponse _response;

  @override
  Future<AuthResponse> login({
    required String username,
    required String password,
    required String deviceKey,
    required String deviceName,
    required String platform,
    required String timezoneName,
    required int timezoneOffsetMinutes,
    String appVersion = '',
  }) async {
    return _response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('login uses local admin account without remote auth', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      LogCryptoService.instance.clear();
      await db.close();
    });

    await db.ensureAdminUser(
      username: 'admin',
      pinHash: PinHasher.hash('dennis_yang_edu'),
    );

    final auth = AuthController(
      db,
      _MemorySecureStorage(),
      authApi: _FailingAuthApiService(),
      deviceIdentityService: _FakeDeviceIdentityService(),
    );
    final ok = await auth.login('admin', 'dennis_yang_edu');

    expect(ok, isTrue);
    expect(auth.currentUser, isNotNull);
    expect(auth.currentUser!.role, equals('admin'));
    expect(auth.currentUser!.username, equals('admin'));
  });

  test('login reuses placeholder user by remoteUserId', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      LogCryptoService.instance.clear();
      await db.close();
    });

    final placeholderId = await db.createUser(
      username: 'remote_student_3001',
      pinHash: PinHasher.hash('remote_student_placeholder'),
      role: 'student',
      remoteUserId: 3001,
    );
    final auth = AuthController(
      db,
      _MemorySecureStorage(),
      authApi: _FakeAuthApiService(
        AuthResponse(
          accessToken: 'token',
          refreshToken: 'refresh',
          tokenType: 'bearer',
          expiresIn: 3600,
          userId: 3001,
          role: 'student',
          teacherId: null,
        ),
      ),
      deviceIdentityService: _FakeDeviceIdentityService(),
    );

    final ok = await auth.login('alice', 'pw123456');

    expect(ok, isTrue);
    expect(auth.currentUser, isNotNull);
    expect(auth.currentUser!.id, equals(placeholderId));
    expect(auth.currentUser!.username, equals('alice'));
    expect(auth.currentUser!.remoteUserId, equals(3001));
  });

  test('login surfaces device identity failures instead of throwing', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      LogCryptoService.instance.clear();
      await db.close();
    });

    final auth = AuthController(
      db,
      _MemorySecureStorage(),
      authApi: _FailingAuthApiService(),
      deviceIdentityService: _ThrowingDeviceIdentityService(),
    );

    final ok = await auth.login('teacher1', 'pw123456');

    expect(ok, isFalse);
    expect(
      auth.lastError,
      equals('Login failed: Bad state: device identity unavailable'),
    );
  });
}
