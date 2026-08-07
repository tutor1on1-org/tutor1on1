import 'dart:async';
import 'dart:convert';

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
  static const _oauthCredentialsPrefix = 'oauth_credentials:';
  static const _authAccessTokenKey = 'auth_access_token';
  static const _authRefreshTokenKey = 'auth_refresh_token';
  static const _authDeviceKey = 'auth_device_key';
  static const _authDeviceNameKey = 'auth_device_name';
  static const _remoteStudyModePinHashKey = 'remote_study_mode_pin_hash';
  static const _agentTutorModelKey = 'agent_tutor_model';
  static const _agentTutorReasoningEffortKey = 'agent_tutor_reasoning_effort';
  static const _installedCourseBundleVersionPrefix =
      'installed_course_bundle_version:';
  static const _promptMetadataAppliedAtPrefix = 'prompt_metadata_applied_at:';
  static const _syncItemStatePrefix = 'sync_item_state:';
  static const _localSyncState2Prefix = 'local_sync_state2:';
  static const _syncListEtagPrefix = 'sync_list_etag:';
  static const _syncRunAtPrefix = 'sync_run_at:';
  static final String _syncRunDeviceHash = _buildSyncRunDeviceHash();
  final FlutterSecureStorage _storage;
  int? _boundAuthRemoteUserId;
  final StreamController<void> _authSessionInvalidatedController =
      StreamController<void>.broadcast(sync: true);

  static String get syncRunDeviceHash => _syncRunDeviceHash;
  Stream<void> get authSessionInvalidated =>
      _authSessionInvalidatedController.stream;
  int? get boundAuthRemoteUserId => _boundAuthRemoteUserId;

  void bindAuthRemoteUser(int? remoteUserId) {
    _boundAuthRemoteUserId =
        remoteUserId != null && remoteUserId > 0 ? remoteUserId : null;
  }

  Future<void> ensureReadableOrReset() async {
    await _storage.readAll();
  }

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

  Future<String?> readOAuthCredentials(String providerId) {
    return _storage.read(key: _oauthCredentialsKey(providerId));
  }

  Future<void> writeOAuthCredentials(String providerId, String value) {
    return _storage.write(
      key: _oauthCredentialsKey(providerId),
      value: value.trim(),
    );
  }

  Future<void> deleteOAuthCredentials(String providerId) {
    return _storage.delete(key: _oauthCredentialsKey(providerId));
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

  Future<void> invalidateAuthSession() async {
    await deleteAuthTokens();
    if (!_authSessionInvalidatedController.isClosed) {
      _authSessionInvalidatedController.add(null);
    }
  }

  Future<String?> readAuthDeviceKey() => _storage.read(key: _authDeviceKey);

  Future<void> writeAuthDeviceKey(String value) {
    return _storage.write(
      key: _authDeviceKey,
      value: value.trim(),
    );
  }

  Future<String?> readAuthDeviceName() =>
      _storage.read(key: _authDeviceNameKey);

  Future<void> writeAuthDeviceName(String value) {
    return _storage.write(
      key: _authDeviceNameKey,
      value: value.trim(),
    );
  }

  Future<String?> readRemoteStudyModePinHash() {
    return _storage.read(key: _remoteStudyModePinHashKey);
  }

  Future<void> writeRemoteStudyModePinHash(String value) {
    return _storage.write(
      key: _remoteStudyModePinHashKey,
      value: value.trim(),
    );
  }

  Future<void> deleteRemoteStudyModePinHash() {
    return _storage.delete(key: _remoteStudyModePinHashKey);
  }

  Future<String?> readAgentTutorModel() {
    return _storage.read(key: _agentTutorModelKey);
  }

  Future<void> writeAgentTutorModel(String value) {
    return _storage.write(
      key: _agentTutorModelKey,
      value: value.trim(),
    );
  }

  Future<String?> readAgentTutorReasoningEffort() {
    return _storage.read(key: _agentTutorReasoningEffortKey);
  }

  Future<void> writeAgentTutorReasoningEffort(String value) {
    return _storage.write(
      key: _agentTutorReasoningEffortKey,
      value: value.trim().toLowerCase(),
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

  Future<String?> readLocalSyncState2({
    required int remoteUserId,
    required String domain,
  }) {
    return _storage.read(
      key: _localSyncState2Key(
        remoteUserId: remoteUserId,
        domain: domain,
      ),
    );
  }

  Future<void> writeLocalSyncState2({
    required int remoteUserId,
    required String domain,
    required String state2,
  }) {
    return _storage.write(
      key: _localSyncState2Key(
        remoteUserId: remoteUserId,
        domain: domain,
      ),
      value: state2.trim(),
    );
  }

  Future<void> deleteLocalSyncState2({
    required int remoteUserId,
    required String domain,
  }) {
    return _storage.delete(
      key: _localSyncState2Key(
        remoteUserId: remoteUserId,
        domain: domain,
      ),
    );
  }

  Future<void> clearAllLocalSyncState2() async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(_localSyncState2Prefix)) {
        await _storage.delete(key: key);
      }
    }
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

  Future<void> clearSyncDomainState({
    required int remoteUserId,
    required String domain,
    bool clearItemStates = true,
    bool clearListEtags = true,
    bool clearRunAt = true,
  }) async {
    final normalizedDomain = domain.trim().toLowerCase();
    final all = await _storage.readAll();
    final itemStatePrefix =
        '$_syncItemStatePrefix$remoteUserId:$normalizedDomain:';
    final etagPrefix = '$_syncListEtagPrefix$remoteUserId:$normalizedDomain:';
    final runAtPrefix = '$_syncRunAtPrefix$remoteUserId:$normalizedDomain:';

    for (final key in all.keys) {
      if (clearItemStates && key.startsWith(itemStatePrefix)) {
        await _storage.delete(key: key);
      } else if (clearListEtags && key.startsWith(etagPrefix)) {
        await _storage.delete(key: key);
      } else if (clearRunAt && key.startsWith(runAtPrefix)) {
        await _storage.delete(key: key);
      }
    }
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

  Future<void> clearLegacySyncCompatibilityState() async {
    const obsoletePrefixes = <String>[
      'user_private_key:',
      'user_public_key:',
      'session_sync_cursor:',
      'progress_sync_cursor:',
      'enrollment_deletion_cursor:',
      'course_prompt_bundle_version:',
    ];
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (obsoletePrefixes.any(key.startsWith)) {
        await _storage.delete(key: key);
      }
    }
  }

  String _baseUrlKey(String baseUrl) {
    final normalized = baseUrl.trim().toLowerCase();
    return '$_apiKeyBasePrefix${sha256Hex(normalized)}';
  }

  String _oauthCredentialsKey(String providerId) {
    return '$_oauthCredentialsPrefix${providerId.trim().toLowerCase()}';
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

  String _localSyncState2Key({
    required int remoteUserId,
    required String domain,
  }) {
    final normalizedDomain = domain.trim().toLowerCase();
    return '$_localSyncState2Prefix$remoteUserId:$normalizedDomain';
  }

  String _syncRunAtKey({
    required int remoteUserId,
    required String domain,
  }) {
    final normalizedDomain = domain.trim().toLowerCase();
    return '$_syncRunAtPrefix$remoteUserId:$normalizedDomain:$_syncRunDeviceHash';
  }

  static String _buildSyncRunDeviceHash() {
    return sha256Hex('tutor1on1:web');
  }
}
