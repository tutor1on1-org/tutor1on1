import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'legacy_brand_compat.dart';

class LogCryptoService {
  LogCryptoService._()
      : _aead = AesGcm.with256bits(),
        _kdf = Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: 120000,
          bits: 256,
        );

  static final LogCryptoService instance = LogCryptoService._();
  static const String _prefix = 'enc:v1:';

  final AesGcm _aead;
  final Pbkdf2 _kdf;

  SecretKey? _activeKey;
  int? _activeUserId;
  String? _activeRole;

  int? get activeUserId => _activeUserId;
  String? get activeRole => _activeRole;
  bool get hasActiveKey =>
      _activeKey != null && _activeUserId != null && _activeRole != null;

  Future<void> activate({
    required int userId,
    required String role,
    required String password,
  }) async {
    final normalizedRole = role.trim().toLowerCase();
    if (userId <= 0) {
      throw StateError('Log crypto activation requires a positive user id.');
    }
    if (normalizedRole.isEmpty) {
      throw StateError('Log crypto activation requires a user role.');
    }
    if (password.trim().isEmpty) {
      throw StateError(
        'Log crypto activation requires non-empty user credentials.',
      );
    }
    final saltBytes = Uint8List.fromList(
      utf8.encode('${buildLegacyLogSaltPrefix()}:$userId:$normalizedRole'),
    );
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: saltBytes,
    );
    _activeKey = key;
    _activeUserId = userId;
    _activeRole = normalizedRole;
  }

  void clear() {
    _activeKey = null;
    _activeUserId = null;
    _activeRole = null;
  }

  Future<String> encryptForCurrentUser(String value) async {
    if (value.isEmpty) {
      return value;
    }
    final key = _requireActiveKey();
    final nonce = _randomBytes(12);
    final box = await _aead.encrypt(
      utf8.encode(value),
      secretKey: key,
      nonce: nonce,
    );
    final payload = <String, dynamic>{
      'user_id': _activeUserId,
      'role': _activeRole,
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
    final encoded = base64Encode(utf8.encode(jsonEncode(payload)));
    return '$_prefix$encoded';
  }

  Future<String?> decryptForCurrentUser(String? value) async {
    if (value == null) {
      return null;
    }
    if (value.isEmpty) {
      return '';
    }
    if (!value.startsWith(_prefix)) {
      return value;
    }
    final payload = _decodePayload(value);
    final ownerId = (payload['user_id'] as num?)?.toInt();
    final ownerRole = (payload['role'] as String?)?.trim().toLowerCase() ?? '';
    if (ownerId == null || ownerId <= 0 || ownerRole.isEmpty) {
      throw StateError('Encrypted log payload is missing ownership metadata.');
    }
    if (!hasActiveKey) {
      throw StateError(
        'Encrypted log access requested without active user credentials.',
      );
    }
    if (ownerId != _activeUserId || ownerRole != _activeRole) {
      return null;
    }

    final nonceText = (payload['nonce'] as String?) ?? '';
    final cipherText = (payload['ciphertext'] as String?) ?? '';
    final macText = (payload['mac'] as String?) ?? '';
    if (nonceText.isEmpty || cipherText.isEmpty || macText.isEmpty) {
      throw StateError('Encrypted log payload is incomplete.');
    }

    final clear = await _aead.decrypt(
      SecretBox(
        base64Decode(cipherText),
        nonce: base64Decode(nonceText),
        mac: Mac(base64Decode(macText)),
      ),
      secretKey: _requireActiveKey(),
    );
    return utf8.decode(clear);
  }

  Map<String, dynamic> _decodePayload(String value) {
    final encoded = value.substring(_prefix.length);
    if (encoded.trim().isEmpty) {
      throw StateError('Encrypted log payload is empty.');
    }
    final decoded = jsonDecode(utf8.decode(base64Decode(encoded)));
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Encrypted log payload has invalid format.');
    }
    return decoded;
  }

  SecretKey _requireActiveKey() {
    final key = _activeKey;
    if (key == null || _activeUserId == null || _activeRole == null) {
      throw StateError(
        'Encrypted logging requires an authenticated user session.',
      );
    }
    return key;
  }

  Uint8List _randomBytes(int length) {
    final values = Uint8List(length);
    final random = Random.secure();
    for (var i = 0; i < length; i++) {
      values[i] = random.nextInt(256);
    }
    return values;
  }
}
