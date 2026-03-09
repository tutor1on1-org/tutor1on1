import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/db/app_database.dart';
import 'package:family_teacher/security/pin_hasher.dart';
import 'package:family_teacher/state/auth_controller.dart';
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
}
