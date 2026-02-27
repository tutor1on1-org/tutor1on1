import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/services/secure_storage_service.dart';
import 'package:family_teacher/services/session_crypto_service.dart';
import 'package:family_teacher/services/session_sync_api_service.dart';
import 'package:family_teacher/services/user_key_service.dart';

class _NoopSecureStorageService extends SecureStorageService {
  @override
  Future<String?> readAuthAccessToken() async => 'token';
}

class _MemorySecureStorageService extends SecureStorageService {
  final Map<int, String> _privateKeys = <int, String>{};
  final Map<int, String> _publicKeys = <int, String>{};

  @override
  Future<String?> readUserPrivateKey(int remoteUserId) async =>
      _privateKeys[remoteUserId];

  @override
  Future<void> writeUserPrivateKey(int remoteUserId, String value) async {
    _privateKeys[remoteUserId] = value.trim();
  }

  @override
  Future<String?> readUserPublicKey(int remoteUserId) async =>
      _publicKeys[remoteUserId];

  @override
  Future<void> writeUserPublicKey(int remoteUserId, String value) async {
    _publicKeys[remoteUserId] = value.trim();
  }
}

class _FakeSessionSyncApiService extends SessionSyncApiService {
  _FakeSessionSyncApiService({UserKeyRecord? stored})
      : _stored = stored,
        super(
          secureStorage: _NoopSecureStorageService(),
          baseUrl: 'https://example.com',
        );

  UserKeyRecord? _stored;
  int upsertCount = 0;
  UserKeyRecord? lastUpsert;

  @override
  Future<UserKeyRecord?> getUserKey() async => _stored;

  @override
  Future<void> upsertUserKey(UserKeyRecord record) async {
    upsertCount += 1;
    lastUpsert = record;
    _stored = record;
  }
}

void main() {
  test('ensureUserKeyPair re-uploads local key pair with login password',
      () async {
    final crypto = SessionCryptoService();
    final storage = _MemorySecureStorageService();
    final api = _FakeSessionSyncApiService();
    final service = UserKeyService(
      secureStorage: storage,
      api: api,
      crypto: crypto,
    );
    const remoteUserId = 1001;
    const password = 'pw-local';
    final localKey = await crypto.generateKeyPair();
    final localPublic = await _publicKeyString(crypto, localKey);
    await storage.writeUserPrivateKey(
      remoteUserId,
      await crypto.encodePrivateKey(localKey),
    );
    await storage.writeUserPublicKey(remoteUserId, localPublic);

    final result = await service.ensureUserKeyPair(
      remoteUserId: remoteUserId,
      password: password,
    );

    expect(await _publicKeyString(crypto, result), equals(localPublic));
    expect(api.upsertCount, equals(1));
    final uploaded = api.lastUpsert;
    expect(uploaded, isNotNull);
    expect(uploaded!.publicKey, equals(localPublic));
    final encrypted = _parseEncrypted(uploaded.encryptedPrivateKey);
    final decrypted = await crypto.decryptPrivateKey(
      encrypted: encrypted,
      password: password,
      publicKey: localPublic,
    );
    expect(await _publicKeyString(crypto, decrypted), equals(localPublic));
  });

  test(
      'ensureUserKeyPair decrypts server key, stores locally, and re-seals on upload',
      () async {
    final crypto = SessionCryptoService();
    final storage = _MemorySecureStorageService();
    const password = 'pw-server';
    final serverKeyPair = await crypto.generateKeyPair();
    final serverPublic = await _publicKeyString(crypto, serverKeyPair);
    final encrypted = await crypto.encryptPrivateKey(
      keyPair: serverKeyPair,
      password: password,
    );
    final api = _FakeSessionSyncApiService(
      stored: UserKeyRecord(
        publicKey: serverPublic,
        encryptedPrivateKey: jsonEncode(encrypted.toJson()),
        kdfSalt: encrypted.salt,
        kdfIterations: encrypted.iterations,
        kdfAlgorithm: encrypted.kdf,
      ),
    );
    final service = UserKeyService(
      secureStorage: storage,
      api: api,
      crypto: crypto,
    );
    const remoteUserId = 1002;

    final result = await service.ensureUserKeyPair(
      remoteUserId: remoteUserId,
      password: password,
    );

    expect(await _publicKeyString(crypto, result), equals(serverPublic));
    expect(await storage.readUserPublicKey(remoteUserId), equals(serverPublic));
    expect(await storage.readUserPrivateKey(remoteUserId), isNotNull);
    expect(api.upsertCount, equals(1));
  });

  test('ensureUserKeyPair creates and stores key when no local/server key',
      () async {
    final crypto = SessionCryptoService();
    final storage = _MemorySecureStorageService();
    final api = _FakeSessionSyncApiService();
    final service = UserKeyService(
      secureStorage: storage,
      api: api,
      crypto: crypto,
    );
    const remoteUserId = 1003;
    const password = 'pw-new';

    final result = await service.ensureUserKeyPair(
      remoteUserId: remoteUserId,
      password: password,
    );

    final publicKey = await _publicKeyString(crypto, result);
    expect(await storage.readUserPublicKey(remoteUserId), equals(publicKey));
    expect(await storage.readUserPrivateKey(remoteUserId), isNotNull);
    expect(api.upsertCount, equals(1));
    expect(api.lastUpsert, isNotNull);
    expect(api.lastUpsert!.publicKey, equals(publicKey));
  });
}

EncryptedPrivateKey _parseEncrypted(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw StateError('Encrypted private key JSON invalid in test.');
  }
  return EncryptedPrivateKey.fromJson(decoded);
}

Future<String> _publicKeyString(
  SessionCryptoService crypto,
  SimpleKeyPair keyPair,
) async {
  final publicKey = await crypto.extractPublicKey(keyPair);
  return crypto.encodePublicKey(publicKey);
}
