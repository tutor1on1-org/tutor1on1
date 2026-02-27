import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'secure_storage_service.dart';
import 'session_crypto_service.dart';
import 'session_sync_api_service.dart';

class UserKeyService {
  UserKeyService({
    required SecureStorageService secureStorage,
    required SessionSyncApiService api,
    SessionCryptoService? crypto,
  })  : _secureStorage = secureStorage,
        _api = api,
        _crypto = crypto ?? SessionCryptoService();

  final SecureStorageService _secureStorage;
  final SessionSyncApiService _api;
  final SessionCryptoService _crypto;

  Future<SimpleKeyPair> ensureUserKeyPair({
    required int remoteUserId,
    required String password,
  }) async {
    final local = await _loadLocalKeyPair(remoteUserId);
    if (local != null) {
      await _upsertServerKey(
        keyPair: local,
        password: password,
      );
      return local;
    }
    final serverKey = await _api.getUserKey();
    if (serverKey != null &&
        serverKey.publicKey.trim().isNotEmpty &&
        serverKey.encryptedPrivateKey.trim().isNotEmpty) {
      final encryptedMap = _decodeJsonMap(serverKey.encryptedPrivateKey);
      final encrypted = EncryptedPrivateKey.fromJson(encryptedMap);
      final keyPair = await _crypto.decryptPrivateKey(
        encrypted: encrypted,
        password: password,
        publicKey: serverKey.publicKey,
      );
      await _upsertServerKey(
        keyPair: keyPair,
        password: password,
      );
      await _storeKeyPair(remoteUserId, keyPair);
      return keyPair;
    }

    final keyPair = await _crypto.generateKeyPair();
    await _upsertServerKey(
      keyPair: keyPair,
      password: password,
    );
    await _storeKeyPair(remoteUserId, keyPair);
    return keyPair;
  }

  Future<SimpleKeyPair?> tryLoadLocalKeyPair(int remoteUserId) {
    return _loadLocalKeyPair(remoteUserId);
  }

  Future<SimpleKeyPair?> _loadLocalKeyPair(int remoteUserId) async {
    final privateKey = await _secureStorage.readUserPrivateKey(remoteUserId);
    final publicKey = await _secureStorage.readUserPublicKey(remoteUserId);
    if (privateKey == null ||
        privateKey.trim().isEmpty ||
        publicKey == null ||
        publicKey.trim().isEmpty) {
      return null;
    }
    return _crypto.decodePrivateKey(
      value: privateKey,
      publicKey: publicKey,
    );
  }

  Future<void> _storeKeyPair(int remoteUserId, SimpleKeyPair keyPair) async {
    final publicKey = await _crypto.extractPublicKey(keyPair);
    final privateKey = await _crypto.encodePrivateKey(keyPair);
    await _secureStorage.writeUserPrivateKey(remoteUserId, privateKey);
    await _secureStorage.writeUserPublicKey(
      remoteUserId,
      _crypto.encodePublicKey(publicKey),
    );
  }

  Future<void> _upsertServerKey({
    required SimpleKeyPair keyPair,
    required String password,
  }) async {
    final publicKey = await _crypto.extractPublicKey(keyPair);
    final encrypted = await _crypto.encryptPrivateKey(
      keyPair: keyPair,
      password: password,
    );
    await _api.upsertUserKey(
      UserKeyRecord(
        publicKey: _crypto.encodePublicKey(publicKey),
        encryptedPrivateKey: jsonEncode(encrypted.toJson()),
        kdfSalt: encrypted.salt,
        kdfIterations: encrypted.iterations,
        kdfAlgorithm: encrypted.kdf,
      ),
    );
  }

  Map<String, dynamic> _decodeJsonMap(String input) {
    final text = input.trim();
    if (text.isEmpty) {
      throw StateError('Encrypted private key payload missing.');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Encrypted private key payload invalid.');
    }
    return decoded;
  }
}
