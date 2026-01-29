import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../security/hash_utils.dart';

class SecureStorageService {
  SecureStorageService() : _storage = const FlutterSecureStorage();

  static const _apiKeyKey = 'openai_api_key';
  static const _apiKeyPrefix = 'openai_api_key:';
  static const _apiKeyBasePrefix = 'api_key_base:';
  final FlutterSecureStorage _storage;

  Future<String?> readApiKey() => _storage.read(key: _apiKeyKey);

  Future<void> writeApiKey(String value) =>
      _storage.write(key: _apiKeyKey, value: value.trim());

  Future<void> deleteApiKey() => _storage.delete(key: _apiKeyKey);

  Future<String?> readApiKeyForBaseUrl(String baseUrl) {
    return _storage.read(key: _baseUrlKey(baseUrl));
  }

  Future<void> writeApiKeyForBaseUrl(String baseUrl, String value) {
    return _storage.write(
      key: _baseUrlKey(baseUrl),
      value: value.trim(),
    );
  }

  Future<void> deleteApiKeyForBaseUrl(String baseUrl) {
    return _storage.delete(key: _baseUrlKey(baseUrl));
  }

  Future<String?> readApiKeyForHash(String hash) {
    return _storage.read(key: '$_apiKeyPrefix$hash');
  }

  Future<void> writeApiKeyForHash(String hash, String value) {
    return _storage.write(
      key: '$_apiKeyPrefix$hash',
      value: value.trim(),
    );
  }

  Future<void> deleteApiKeyForHash(String hash) {
    return _storage.delete(key: '$_apiKeyPrefix$hash');
  }

  String _baseUrlKey(String baseUrl) {
    final normalized = baseUrl.trim().toLowerCase();
    return '$_apiKeyBasePrefix${sha256Hex(normalized)}';
  }
}
