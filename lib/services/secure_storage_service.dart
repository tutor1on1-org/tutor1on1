import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../security/hash_utils.dart';

class SyncItemState {
  SyncItemState({
    required this.contentHash,
    required this.lastChangedAt,
    required this.lastSyncedAt,
  });

  final String contentHash;
  final DateTime lastChangedAt;
  final DateTime lastSyncedAt;
}

class SecureStorageService {
  SecureStorageService() : _storage = const FlutterSecureStorage();

  static const _apiKeyKey = 'openai_api_key';
  static const _apiKeyPrefix = 'openai_api_key:';
  static const _apiKeyBasePrefix = 'api_key_base:';
  static const _authAccessTokenKey = 'auth_access_token';
  static const _authRefreshTokenKey = 'auth_refresh_token';
  static const _userPrivateKeyPrefix = 'user_private_key:';
  static const _userPublicKeyPrefix = 'user_public_key:';
  static const _sessionSyncCursorPrefix = 'session_sync_cursor:';
  static const _progressSyncCursorPrefix = 'progress_sync_cursor:';
  static const _enrollmentDeletionCursorPrefix = 'enrollment_deletion_cursor:';
  static const _coursePromptBundleVersionPrefix =
      'course_prompt_bundle_version:';
  static const _installedCourseBundleVersionPrefix =
      'installed_course_bundle_version:';
  static const _promptMetadataAppliedAtPrefix = 'prompt_metadata_applied_at:';
  static const _syncItemStatePrefix = 'sync_item_state:';
  static const _syncListEtagPrefix = 'sync_list_etag:';
  static const _syncRunAtPrefix = 'sync_run_at:';
  static final String _syncRunDeviceHash = _buildSyncRunDeviceHash();
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

  Future<String?> readAuthAccessToken() =>
      _storage.read(key: _authAccessTokenKey);

  Future<String?> readAuthRefreshToken() =>
      _storage.read(key: _authRefreshTokenKey);

  Future<void> writeAuthTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _authAccessTokenKey, value: accessToken.trim());
    await _storage.write(key: _authRefreshTokenKey, value: refreshToken.trim());
  }

  Future<void> deleteAuthTokens() async {
    await _storage.delete(key: _authAccessTokenKey);
    await _storage.delete(key: _authRefreshTokenKey);
  }

  Future<String?> readUserPrivateKey(int remoteUserId) {
    return _storage.read(key: '$_userPrivateKeyPrefix$remoteUserId');
  }

  Future<void> writeUserPrivateKey(int remoteUserId, String value) {
    return _storage.write(
      key: '$_userPrivateKeyPrefix$remoteUserId',
      value: value.trim(),
    );
  }

  Future<void> deleteUserPrivateKey(int remoteUserId) {
    return _storage.delete(key: '$_userPrivateKeyPrefix$remoteUserId');
  }

  Future<String?> readUserPublicKey(int remoteUserId) {
    return _storage.read(key: '$_userPublicKeyPrefix$remoteUserId');
  }

  Future<void> writeUserPublicKey(int remoteUserId, String value) {
    return _storage.write(
      key: '$_userPublicKeyPrefix$remoteUserId',
      value: value.trim(),
    );
  }

  Future<String?> readSessionSyncCursor(int remoteUserId) {
    return _storage.read(key: '$_sessionSyncCursorPrefix$remoteUserId');
  }

  Future<void> writeSessionSyncCursor(int remoteUserId, String value) {
    return _storage.write(
      key: '$_sessionSyncCursorPrefix$remoteUserId',
      value: value.trim(),
    );
  }

  Future<String?> readProgressSyncCursor(int remoteUserId) {
    return _storage.read(key: '$_progressSyncCursorPrefix$remoteUserId');
  }

  Future<void> writeProgressSyncCursor(int remoteUserId, String value) {
    return _storage.write(
      key: '$_progressSyncCursorPrefix$remoteUserId',
      value: value.trim(),
    );
  }

  Future<int?> readEnrollmentDeletionCursor(int remoteUserId) async {
    final value = await _storage.read(
      key: '$_enrollmentDeletionCursorPrefix$remoteUserId',
    );
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return int.tryParse(value.trim());
  }

  Future<void> writeEnrollmentDeletionCursor(int remoteUserId, int eventId) {
    return _storage.write(
      key: '$_enrollmentDeletionCursorPrefix$remoteUserId',
      value: eventId.toString(),
    );
  }

  Future<int?> readInstalledCourseBundleVersion({
    required int remoteUserId,
    required int remoteCourseId,
  }) async {
    final value = await _storage.read(
      key: '$_installedCourseBundleVersionPrefix$remoteUserId:$remoteCourseId',
    );
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return int.tryParse(value.trim());
  }

  Future<void> writeInstalledCourseBundleVersion({
    required int remoteUserId,
    required int remoteCourseId,
    required int versionId,
  }) {
    return _storage.write(
      key: '$_installedCourseBundleVersionPrefix$remoteUserId:$remoteCourseId',
      value: versionId.toString(),
    );
  }

  Future<SyncItemState?> readSyncItemState({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) async {
    final value = await _storage.read(
      key: _syncItemStateKey(
        remoteUserId: remoteUserId,
        domain: domain,
        scopeKey: scopeKey,
      ),
    );
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final hash = (decoded['hash'] as String?)?.trim() ?? '';
      final changedAtRaw =
          (decoded['last_changed_at'] as String?)?.trim() ?? '';
      final syncedAtRaw = (decoded['last_synced_at'] as String?)?.trim() ?? '';
      final changedAt = DateTime.tryParse(changedAtRaw);
      final syncedAt = DateTime.tryParse(syncedAtRaw);
      if (hash.isEmpty || changedAt == null || syncedAt == null) {
        return null;
      }
      return SyncItemState(
        contentHash: hash,
        lastChangedAt: changedAt,
        lastSyncedAt: syncedAt,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSyncItemState({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
    required String contentHash,
    required DateTime lastChangedAt,
    required DateTime lastSyncedAt,
  }) async {
    final payload = jsonEncode(
      <String, String>{
        'hash': contentHash.trim(),
        'last_changed_at': lastChangedAt.toUtc().toIso8601String(),
        'last_synced_at': lastSyncedAt.toUtc().toIso8601String(),
      },
    );
    await _storage.write(
      key: _syncItemStateKey(
        remoteUserId: remoteUserId,
        domain: domain,
        scopeKey: scopeKey,
      ),
      value: payload,
    );
  }

  Future<String?> readSyncListEtag({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) {
    return _storage.read(
      key: _syncListEtagKey(
        remoteUserId: remoteUserId,
        domain: domain,
        scopeKey: scopeKey,
      ),
    );
  }

  Future<void> writeSyncListEtag({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
    required String etag,
  }) {
    return _storage.write(
      key: _syncListEtagKey(
        remoteUserId: remoteUserId,
        domain: domain,
        scopeKey: scopeKey,
      ),
      value: etag.trim(),
    );
  }

  Future<DateTime?> readSyncRunAt({
    required int remoteUserId,
    required String domain,
  }) async {
    final raw = await _storage.read(
      key: _syncRunAtKey(
        remoteUserId: remoteUserId,
        domain: domain,
      ),
    );
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw.trim());
  }

  Future<void> writeSyncRunAt({
    required int remoteUserId,
    required String domain,
    required DateTime runAt,
  }) {
    return _storage.write(
      key: _syncRunAtKey(
        remoteUserId: remoteUserId,
        domain: domain,
      ),
      value: runAt.toUtc().toIso8601String(),
    );
  }

  Future<DateTime?> readPromptMetadataAppliedAt({
    required int remoteUserId,
    required int remoteCourseId,
  }) async {
    final value = await _storage.read(
      key: '$_promptMetadataAppliedAtPrefix$remoteUserId:$remoteCourseId',
    );
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final millis = int.tryParse(value.trim());
    if (millis == null || millis <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> writePromptMetadataAppliedAt({
    required int remoteUserId,
    required int remoteCourseId,
    required DateTime appliedAt,
  }) {
    return _storage.write(
      key: '$_promptMetadataAppliedAtPrefix$remoteUserId:$remoteCourseId',
      value: appliedAt.millisecondsSinceEpoch.toString(),
    );
  }

  Future<int?> readCoursePromptBundleVersion({
    required int remoteUserId,
    required int remoteCourseId,
  }) async {
    final installed = await readInstalledCourseBundleVersion(
      remoteUserId: remoteUserId,
      remoteCourseId: remoteCourseId,
    );
    if (installed != null) {
      return installed;
    }
    final legacy = await _storage.read(
      key: '$_coursePromptBundleVersionPrefix$remoteUserId:$remoteCourseId',
    );
    if (legacy == null || legacy.trim().isEmpty) {
      return null;
    }
    return int.tryParse(legacy.trim());
  }

  Future<void> writeCoursePromptBundleVersion({
    required int remoteUserId,
    required int remoteCourseId,
    required int versionId,
  }) async {
    await writeInstalledCourseBundleVersion(
      remoteUserId: remoteUserId,
      remoteCourseId: remoteCourseId,
      versionId: versionId,
    );
    await _storage.write(
      key: '$_coursePromptBundleVersionPrefix$remoteUserId:$remoteCourseId',
      value: versionId.toString(),
    );
  }

  String _baseUrlKey(String baseUrl) {
    final normalized = baseUrl.trim().toLowerCase();
    return '$_apiKeyBasePrefix${sha256Hex(normalized)}';
  }

  String _syncItemStateKey({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) {
    final normalizedDomain = domain.trim().toLowerCase();
    final normalizedScope = scopeKey.trim();
    final scopeHash = sha256Hex(normalizedScope);
    return '$_syncItemStatePrefix$remoteUserId:$normalizedDomain:$scopeHash';
  }

  String _syncListEtagKey({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) {
    final normalizedDomain = domain.trim().toLowerCase();
    final normalizedScope = scopeKey.trim();
    final scopeHash = sha256Hex(normalizedScope);
    return '$_syncListEtagPrefix$remoteUserId:$normalizedDomain:$scopeHash';
  }

  String _syncRunAtKey({
    required int remoteUserId,
    required String domain,
  }) {
    final normalizedDomain = domain.trim().toLowerCase();
    return '$_syncRunAtPrefix$remoteUserId:$normalizedDomain:$_syncRunDeviceHash';
  }

  static String _buildSyncRunDeviceHash() {
    final seed = [
      Platform.operatingSystem,
      Platform.operatingSystemVersion,
      Platform.localHostname,
      Platform.numberOfProcessors.toString(),
      Platform.pathSeparator,
    ].join('|');
    return sha256Hex(seed);
  }
}
