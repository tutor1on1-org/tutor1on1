import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class EncryptedPrivateKey {
  EncryptedPrivateKey({
    required this.encryptedKey,
    required this.salt,
    required this.iterations,
    required this.kdf,
    required this.nonce,
    required this.mac,
  });

  final String encryptedKey;
  final String salt;
  final int iterations;
  final String kdf;
  final String nonce;
  final String mac;

  Map<String, dynamic> toJson() => {
        'encrypted_key': encryptedKey,
        'salt': salt,
        'iterations': iterations,
        'kdf': kdf,
        'nonce': nonce,
        'mac': mac,
      };

  factory EncryptedPrivateKey.fromJson(Map<String, dynamic> json) {
    return EncryptedPrivateKey(
      encryptedKey: (json['encrypted_key'] as String?) ?? '',
      salt: (json['salt'] as String?) ?? '',
      iterations: (json['iterations'] as num?)?.toInt() ?? 0,
      kdf: (json['kdf'] as String?) ?? '',
      nonce: (json['nonce'] as String?) ?? '',
      mac: (json['mac'] as String?) ?? '',
    );
  }
}

class EnvelopeRecipient {
  EnvelopeRecipient({
    required this.userId,
    required this.ephemeralPublicKey,
    required this.wrapNonce,
    required this.wrapCiphertext,
    required this.wrapMac,
  });

  final int userId;
  final String ephemeralPublicKey;
  final String wrapNonce;
  final String wrapCiphertext;
  final String wrapMac;

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'ephemeral_public_key': ephemeralPublicKey,
        'wrap_nonce': wrapNonce,
        'wrap_ciphertext': wrapCiphertext,
        'wrap_mac': wrapMac,
      };

  factory EnvelopeRecipient.fromJson(Map<String, dynamic> json) {
    return EnvelopeRecipient(
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      ephemeralPublicKey: (json['ephemeral_public_key'] as String?) ?? '',
      wrapNonce: (json['wrap_nonce'] as String?) ?? '',
      wrapCiphertext: (json['wrap_ciphertext'] as String?) ?? '',
      wrapMac: (json['wrap_mac'] as String?) ?? '',
    );
  }
}

class EncryptedEnvelope {
  EncryptedEnvelope({
    required this.version,
    required this.payloadNonce,
    required this.payloadCiphertext,
    required this.payloadMac,
    required this.recipients,
  });

  final int version;
  final String payloadNonce;
  final String payloadCiphertext;
  final String payloadMac;
  final List<EnvelopeRecipient> recipients;

  Map<String, dynamic> toJson() => {
        'version': version,
        'payload_nonce': payloadNonce,
        'payload_ciphertext': payloadCiphertext,
        'payload_mac': payloadMac,
        'recipients': recipients.map((e) => e.toJson()).toList(),
      };

  factory EncryptedEnvelope.fromJson(Map<String, dynamic> json) {
    final rawRecipients = json['recipients'];
    final recipients = <EnvelopeRecipient>[];
    if (rawRecipients is List) {
      for (final item in rawRecipients) {
        if (item is Map<String, dynamic>) {
          recipients.add(EnvelopeRecipient.fromJson(item));
        }
      }
    }
    return EncryptedEnvelope(
      version: (json['version'] as num?)?.toInt() ?? 1,
      payloadNonce: (json['payload_nonce'] as String?) ?? '',
      payloadCiphertext: (json['payload_ciphertext'] as String?) ?? '',
      payloadMac: (json['payload_mac'] as String?) ?? '',
      recipients: recipients,
    );
  }
}

class RecipientPublicKey {
  RecipientPublicKey({
    required this.userId,
    required this.publicKey,
  });

  final int userId;
  final SimplePublicKey publicKey;
}

class SessionCryptoService {
  SessionCryptoService()
      : _aead = AesGcm.with256bits(),
        _x25519 = X25519(),
        _defaultKdf = Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: 120000,
          bits: 256,
        );

  final AesGcm _aead;
  final X25519 _x25519;
  final Pbkdf2 _defaultKdf;

  Future<SimpleKeyPair> generateKeyPair() => _x25519.newKeyPair();

  Future<SimplePublicKey> extractPublicKey(SimpleKeyPair keyPair) {
    return keyPair.extractPublicKey();
  }

  String encodePublicKey(SimplePublicKey key) {
    return base64Encode(key.bytes);
  }

  SimplePublicKey decodePublicKey(String value) {
    final bytes = base64Decode(value);
    return SimplePublicKey(bytes, type: KeyPairType.x25519);
  }

  Future<String> encodePrivateKey(SimpleKeyPair keyPair) async {
    final bytes = await keyPair.extractPrivateKeyBytes();
    return base64Encode(bytes);
  }

  Future<SimpleKeyPair> decodePrivateKey({
    required String value,
    required String publicKey,
  }) async {
    final privateBytes = base64Decode(value);
    final publicBytes = base64Decode(publicKey);
    return SimpleKeyPairData(
      privateBytes,
      publicKey: SimplePublicKey(publicBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  Future<EncryptedPrivateKey> encryptPrivateKey({
    required SimpleKeyPair keyPair,
    required String password,
  }) async {
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final secretKey = await _defaultKdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final box = await _aead.encrypt(
      privateBytes,
      secretKey: secretKey,
      nonce: nonce,
    );
    return EncryptedPrivateKey(
      encryptedKey: base64Encode(box.cipherText),
      salt: base64Encode(salt),
      iterations: _defaultKdf.iterations,
      kdf: 'PBKDF2-HMAC-SHA256',
      nonce: base64Encode(nonce),
      mac: base64Encode(box.mac.bytes),
    );
  }

  Future<SimpleKeyPair> decryptPrivateKey({
    required EncryptedPrivateKey encrypted,
    required String password,
    required String publicKey,
  }) async {
    if (encrypted.iterations <= 0) {
      throw StateError('Encrypted key missing iterations.');
    }
    final salt = base64Decode(encrypted.salt);
    final nonce = base64Decode(encrypted.nonce);
    final cipherText = base64Decode(encrypted.encryptedKey);
    final macBytes = base64Decode(encrypted.mac);
    final secretKey = await _buildKdf(encrypted.iterations).deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final clear = await _aead.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
      secretKey: secretKey,
    );
    return decodePrivateKey(
      value: base64Encode(clear),
      publicKey: publicKey,
    );
  }

  Future<EncryptedEnvelope> encryptPayload({
    required Map<String, dynamic> payload,
    required List<RecipientPublicKey> recipients,
  }) async {
    if (recipients.isEmpty) {
      throw StateError('Recipients required.');
    }
    final payloadBytes = utf8.encode(jsonEncode(payload));
    final dataKeyBytes = _randomBytes(32);
    final payloadNonce = _randomBytes(12);
    final payloadBox = await _aead.encrypt(
      payloadBytes,
      secretKey: SecretKey(dataKeyBytes),
      nonce: payloadNonce,
    );
    final envelopeRecipients = <EnvelopeRecipient>[];
    for (final recipient in recipients) {
      if (recipient.userId <= 0) {
        throw StateError('Recipient user id invalid.');
      }
      final ephemeral = await _x25519.newKeyPair();
      final ephemeralPublicKey = await ephemeral.extractPublicKey();
      final sharedSecret = await _x25519.sharedSecretKey(
        keyPair: ephemeral,
        remotePublicKey: recipient.publicKey,
      );
      final wrapNonce = _randomBytes(12);
      final wrapBox = await _aead.encrypt(
        dataKeyBytes,
        secretKey: sharedSecret,
        nonce: wrapNonce,
      );
      envelopeRecipients.add(
        EnvelopeRecipient(
          userId: recipient.userId,
          ephemeralPublicKey: encodePublicKey(ephemeralPublicKey),
          wrapNonce: base64Encode(wrapNonce),
          wrapCiphertext: base64Encode(wrapBox.cipherText),
          wrapMac: base64Encode(wrapBox.mac.bytes),
        ),
      );
    }
    return EncryptedEnvelope(
      version: 1,
      payloadNonce: base64Encode(payloadNonce),
      payloadCiphertext: base64Encode(payloadBox.cipherText),
      payloadMac: base64Encode(payloadBox.mac.bytes),
      recipients: envelopeRecipients,
    );
  }

  Future<Map<String, dynamic>> decryptEnvelope({
    required EncryptedEnvelope envelope,
    required SimpleKeyPair userKeyPair,
    required int userId,
  }) async {
    final recipient = envelope.recipients.firstWhere(
      (entry) => entry.userId == userId,
      orElse: () => throw StateError('Recipient entry not found.'),
    );
    final epk = decodePublicKey(recipient.ephemeralPublicKey);
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: userKeyPair,
      remotePublicKey: epk,
    );
    final wrapNonce = base64Decode(recipient.wrapNonce);
    final wrapCipher = base64Decode(recipient.wrapCiphertext);
    final wrapMac = base64Decode(recipient.wrapMac);
    final dataKeyBytes = await _aead.decrypt(
      SecretBox(wrapCipher, nonce: wrapNonce, mac: Mac(wrapMac)),
      secretKey: sharedSecret,
    );
    final payloadNonce = base64Decode(envelope.payloadNonce);
    final payloadCipher = base64Decode(envelope.payloadCiphertext);
    final payloadMac = base64Decode(envelope.payloadMac);
    final clear = await _aead.decrypt(
      SecretBox(payloadCipher, nonce: payloadNonce, mac: Mac(payloadMac)),
      secretKey: SecretKey(dataKeyBytes),
    );
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Payload is not a JSON object.');
    }
    return decoded;
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    final values = Uint8List(length);
    for (var i = 0; i < length; i++) {
      values[i] = random.nextInt(256);
    }
    return values;
  }

  Pbkdf2 _buildKdf(int iterations) {
    return Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
  }
}
