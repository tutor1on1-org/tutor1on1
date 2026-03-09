import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/db/app_database.dart';
import 'package:family_teacher/security/pin_hasher.dart';
import 'package:family_teacher/state/auth_controller.dart';
import 'package:family_teacher/services/auth_api_service.dart';
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

    final auth = AuthController(db, _MemorySecureStorage());
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
    );

    final ok = await auth.login('alice', 'pw123456');

    expect(ok, isTrue);
    expect(auth.currentUser, isNotNull);
    expect(auth.currentUser!.id, equals(placeholderId));
    expect(auth.currentUser!.username, equals('alice'));
    expect(auth.currentUser!.remoteUserId, equals(3001));
  });
}
