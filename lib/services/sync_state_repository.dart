import 'package:drift/drift.dart';

import '../db/app_database.dart' hide SyncItemState;
import 'secure_storage_service.dart';

abstract class SyncStateRepository {
  Future<String?> readLocalSyncState2({
    required int remoteUserId,
    required String domain,
  });
  Future<void> writeLocalSyncState2({
    required int remoteUserId,
    required String domain,
    required String state2,
  });
  Future<void> deleteLocalSyncState2({
    required int remoteUserId,
    required String domain,
  });
  Future<String?> readSessionSyncCursor(int remoteUserId);
  Future<void> writeSessionSyncCursor(int remoteUserId, String value);
  Future<void> deleteSessionSyncCursor(int remoteUserId);
  Future<String?> readProgressSyncCursor(int remoteUserId);
  Future<void> writeProgressSyncCursor(int remoteUserId, String value);
  Future<void> deleteProgressSyncCursor(int remoteUserId);
  Future<String?> readSyncListEtag({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  });
  Future<void> writeSyncListEtag({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
    required String etag,
  });
  Future<DateTime?> readSyncRunAt({
    required int remoteUserId,
    required String domain,
  });
  Future<void> writeSyncRunAt({
    required int remoteUserId,
    required String domain,
    required DateTime runAt,
  });
  Future<SyncItemState?> readSyncItemState({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  });
  Future<void> writeSyncItemState({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
    required String contentHash,
    required DateTime lastChangedAt,
    required DateTime lastSyncedAt,
  });
  Future<void> clearSyncDomainState({
    required int remoteUserId,
    required String domain,
    bool clearItemStates = true,
    bool clearListEtags = true,
    bool clearRunAt = true,
    bool clearCursors = false,
  });
}

class LegacyBackfillSyncStateRepository implements SyncStateRepository {
  LegacyBackfillSyncStateRepository({
    required SyncStateRepository primary,
    required SecureStorageService legacy,
  })  : _primary = primary,
        _legacy = legacy;

  final SyncStateRepository _primary;
  final SecureStorageService _legacy;

  @override
  Future<String?> readLocalSyncState2({
    required int remoteUserId,
    required String domain,
  }) async {
    final primaryValue = await _primary.readLocalSyncState2(
      remoteUserId: remoteUserId,
      domain: domain,
    );
    if ((primaryValue ?? '').trim().isNotEmpty) {
      return primaryValue;
    }
    final legacyValue = await _legacy.readLocalSyncState2(
      remoteUserId: remoteUserId,
      domain: domain,
    );
    if ((legacyValue ?? '').trim().isEmpty) {
      return null;
    }
    await _primary.writeLocalSyncState2(
      remoteUserId: remoteUserId,
      domain: domain,
      state2: legacyValue!.trim(),
    );
    return legacyValue.trim();
  }

  @override
  Future<void> writeLocalSyncState2({
    required int remoteUserId,
    required String domain,
    required String state2,
  }) {
    return _primary.writeLocalSyncState2(
      remoteUserId: remoteUserId,
      domain: domain,
      state2: state2,
    );
  }

  @override
  Future<void> deleteLocalSyncState2({
    required int remoteUserId,
    required String domain,
  }) async {
    await _primary.deleteLocalSyncState2(
      remoteUserId: remoteUserId,
      domain: domain,
    );
    await _legacy.deleteLocalSyncState2(
      remoteUserId: remoteUserId,
      domain: domain,
    );
  }

  @override
  Future<String?> readSessionSyncCursor(int remoteUserId) async {
    final primaryValue = await _primary.readSessionSyncCursor(remoteUserId);
    if ((primaryValue ?? '').trim().isNotEmpty) {
      return primaryValue;
    }
    final legacyValue = await _legacy.readSessionSyncCursor(remoteUserId);
    if ((legacyValue ?? '').trim().isEmpty) {
      return null;
    }
    await _primary.writeSessionSyncCursor(remoteUserId, legacyValue!.trim());
    return legacyValue.trim();
  }

  @override
  Future<void> writeSessionSyncCursor(int remoteUserId, String value) {
    return _primary.writeSessionSyncCursor(remoteUserId, value);
  }

  @override
  Future<void> deleteSessionSyncCursor(int remoteUserId) async {
    await _primary.deleteSessionSyncCursor(remoteUserId);
    await _legacy.deleteSessionSyncCursor(remoteUserId);
  }

  @override
  Future<String?> readProgressSyncCursor(int remoteUserId) async {
    final primaryValue = await _primary.readProgressSyncCursor(remoteUserId);
    if ((primaryValue ?? '').trim().isNotEmpty) {
      return primaryValue;
    }
    final legacyValue = await _legacy.readProgressSyncCursor(remoteUserId);
    if ((legacyValue ?? '').trim().isEmpty) {
      return null;
    }
    await _primary.writeProgressSyncCursor(remoteUserId, legacyValue!.trim());
    return legacyValue.trim();
  }

  @override
  Future<void> writeProgressSyncCursor(int remoteUserId, String value) {
    return _primary.writeProgressSyncCursor(remoteUserId, value);
  }

  @override
  Future<void> deleteProgressSyncCursor(int remoteUserId) async {
    await _primary.deleteProgressSyncCursor(remoteUserId);
    await _legacy.deleteProgressSyncCursor(remoteUserId);
  }

  @override
  Future<String?> readSyncListEtag({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) async {
    final primaryValue = await _primary.readSyncListEtag(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
    );
    if ((primaryValue ?? '').trim().isNotEmpty) {
      return primaryValue;
    }
    final legacyValue = await _legacy.readSyncListEtag(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
    );
    if ((legacyValue ?? '').trim().isEmpty) {
      return null;
    }
    await _primary.writeSyncListEtag(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
      etag: legacyValue!.trim(),
    );
    return legacyValue.trim();
  }

  @override
  Future<void> writeSyncListEtag({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
    required String etag,
  }) {
    return _primary.writeSyncListEtag(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
      etag: etag,
    );
  }

  @override
  Future<DateTime?> readSyncRunAt({
    required int remoteUserId,
    required String domain,
  }) async {
    final primaryValue = await _primary.readSyncRunAt(
      remoteUserId: remoteUserId,
      domain: domain,
    );
    if (primaryValue != null) {
      return primaryValue.toUtc();
    }
    final legacyValue = await _legacy.readSyncRunAt(
      remoteUserId: remoteUserId,
      domain: domain,
    );
    if (legacyValue == null) {
      return null;
    }
    final normalized = legacyValue.toUtc();
    await _primary.writeSyncRunAt(
      remoteUserId: remoteUserId,
      domain: domain,
      runAt: normalized,
    );
    return normalized;
  }

  @override
  Future<void> writeSyncRunAt({
    required int remoteUserId,
    required String domain,
    required DateTime runAt,
  }) {
    return _primary.writeSyncRunAt(
      remoteUserId: remoteUserId,
      domain: domain,
      runAt: runAt,
    );
  }

  @override
  Future<SyncItemState?> readSyncItemState({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) async {
    final primaryValue = await _primary.readSyncItemState(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
    );
    if (primaryValue != null) {
      return primaryValue;
    }
    final legacyValue = await _legacy.readSyncItemState(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
    );
    if (legacyValue == null) {
      return null;
    }
    final normalized = SyncItemState(
      contentHash: legacyValue.contentHash.trim(),
      lastChangedAt: legacyValue.lastChangedAt.toUtc(),
      lastSyncedAt: legacyValue.lastSyncedAt.toUtc(),
    );
    await _primary.writeSyncItemState(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
      contentHash: normalized.contentHash,
      lastChangedAt: normalized.lastChangedAt,
      lastSyncedAt: normalized.lastSyncedAt,
    );
    return normalized;
  }

  @override
  Future<void> writeSyncItemState({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
    required String contentHash,
    required DateTime lastChangedAt,
    required DateTime lastSyncedAt,
  }) {
    return _primary.writeSyncItemState(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
      contentHash: contentHash,
      lastChangedAt: lastChangedAt,
      lastSyncedAt: lastSyncedAt,
    );
  }

  @override
  Future<void> clearSyncDomainState({
    required int remoteUserId,
    required String domain,
    bool clearItemStates = true,
    bool clearListEtags = true,
    bool clearRunAt = true,
    bool clearCursors = false,
  }) async {
    await _primary.clearSyncDomainState(
      remoteUserId: remoteUserId,
      domain: domain,
      clearItemStates: clearItemStates,
      clearListEtags: clearListEtags,
      clearRunAt: clearRunAt,
      clearCursors: clearCursors,
    );
    await _legacy.clearSyncDomainState(
      remoteUserId: remoteUserId,
      domain: domain,
      clearItemStates: clearItemStates,
      clearListEtags: clearListEtags,
      clearRunAt: clearRunAt,
    );
  }
}

class DatabaseSyncStateRepository implements SyncStateRepository {
  DatabaseSyncStateRepository(this._db);

  final AppDatabase _db;

  static const String metadataKindCursor = 'cursor';
  static const String metadataKindListEtag = 'list_etag';
  static const String metadataKindLocalState2 = 'local_state2';
  static const String metadataKindRunAt = 'run_at';
  static const String domainSessionCursor = 'session_sync_cursor';
  static const String domainProgressCursor = 'progress_sync_cursor';
  static const String defaultScopeKey = '__default__';

  @override
  Future<String?> readLocalSyncState2({
    required int remoteUserId,
    required String domain,
  }) {
    return _readMetadataValue(
      remoteUserId: remoteUserId,
      kind: metadataKindLocalState2,
      domain: domain,
      scopeKey: defaultScopeKey,
    );
  }

  @override
  Future<void> writeLocalSyncState2({
    required int remoteUserId,
    required String domain,
    required String state2,
  }) {
    return _upsertMetadata(
      remoteUserId: remoteUserId,
      kind: metadataKindLocalState2,
      domain: domain,
      scopeKey: defaultScopeKey,
      value: state2.trim(),
    );
  }

  @override
  Future<void> deleteLocalSyncState2({
    required int remoteUserId,
    required String domain,
  }) {
    return (_db.delete(_db.syncMetadataEntries)
          ..where((tbl) =>
              tbl.remoteUserId.equals(remoteUserId) &
              tbl.kind.equals(metadataKindLocalState2) &
              tbl.domain.equals(_normalizeDomain(domain)) &
              tbl.scopeKey.equals(defaultScopeKey)))
        .go();
  }

  Future<String?> readSessionSyncCursor(int remoteUserId) {
    return _readMetadataValue(
      remoteUserId: remoteUserId,
      kind: metadataKindCursor,
      domain: domainSessionCursor,
      scopeKey: defaultScopeKey,
    );
  }

  Future<void> writeSessionSyncCursor(int remoteUserId, String value) {
    return _upsertMetadata(
      remoteUserId: remoteUserId,
      kind: metadataKindCursor,
      domain: domainSessionCursor,
      scopeKey: defaultScopeKey,
      value: value.trim(),
    );
  }

  Future<void> deleteSessionSyncCursor(int remoteUserId) {
    return (_db.delete(_db.syncMetadataEntries)
          ..where((tbl) =>
              tbl.remoteUserId.equals(remoteUserId) &
              tbl.kind.equals(metadataKindCursor) &
              tbl.domain.equals(domainSessionCursor) &
              tbl.scopeKey.equals(defaultScopeKey)))
        .go();
  }

  Future<String?> readProgressSyncCursor(int remoteUserId) {
    return _readMetadataValue(
      remoteUserId: remoteUserId,
      kind: metadataKindCursor,
      domain: domainProgressCursor,
      scopeKey: defaultScopeKey,
    );
  }

  Future<void> writeProgressSyncCursor(int remoteUserId, String value) {
    return _upsertMetadata(
      remoteUserId: remoteUserId,
      kind: metadataKindCursor,
      domain: domainProgressCursor,
      scopeKey: defaultScopeKey,
      value: value.trim(),
    );
  }

  Future<void> deleteProgressSyncCursor(int remoteUserId) {
    return (_db.delete(_db.syncMetadataEntries)
          ..where((tbl) =>
              tbl.remoteUserId.equals(remoteUserId) &
              tbl.kind.equals(metadataKindCursor) &
              tbl.domain.equals(domainProgressCursor) &
              tbl.scopeKey.equals(defaultScopeKey)))
        .go();
  }

  Future<String?> readListEtag({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) {
    return _readMetadataValue(
      remoteUserId: remoteUserId,
      kind: metadataKindListEtag,
      domain: domain,
      scopeKey: scopeKey,
    );
  }

  Future<void> writeListEtag({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
    required String etag,
  }) {
    return _upsertMetadata(
      remoteUserId: remoteUserId,
      kind: metadataKindListEtag,
      domain: domain,
      scopeKey: scopeKey,
      value: etag.trim(),
    );
  }

  Future<DateTime?> readRunAt({
    required int remoteUserId,
    required String domain,
  }) async {
    final raw = await _readMetadataValue(
      remoteUserId: remoteUserId,
      kind: metadataKindRunAt,
      domain: domain,
      scopeKey: defaultScopeKey,
    );
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw.trim());
  }

  Future<void> writeRunAt({
    required int remoteUserId,
    required String domain,
    required DateTime runAt,
  }) {
    return _upsertMetadata(
      remoteUserId: remoteUserId,
      kind: metadataKindRunAt,
      domain: domain,
      scopeKey: defaultScopeKey,
      value: runAt.toUtc().toIso8601String(),
    );
  }

  Future<String?> readSyncListEtag({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) {
    return readListEtag(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
    );
  }

  Future<void> writeSyncListEtag({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
    required String etag,
  }) {
    return writeListEtag(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
      etag: etag,
    );
  }

  Future<SyncItemState?> readItemState({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) async {
    final row = await (_db.select(_db.syncItemStates)
          ..where((tbl) =>
              tbl.remoteUserId.equals(remoteUserId) &
              tbl.domain.equals(_normalizeDomain(domain)) &
              tbl.scopeKey.equals(scopeKey.trim())))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return SyncItemState(
      contentHash: row.contentHash,
      lastChangedAt: row.lastChangedAt,
      lastSyncedAt: row.lastSyncedAt,
    );
  }

  Future<void> writeItemState({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
    required String contentHash,
    required DateTime lastChangedAt,
    required DateTime lastSyncedAt,
  }) {
    return _db.into(_db.syncItemStates).insertOnConflictUpdate(
          SyncItemStatesCompanion.insert(
            remoteUserId: remoteUserId,
            domain: _normalizeDomain(domain),
            scopeKey: scopeKey.trim(),
            contentHash: contentHash.trim(),
            lastChangedAt: lastChangedAt.toUtc(),
            lastSyncedAt: lastSyncedAt.toUtc(),
          ),
        );
  }

  Future<void> clearDomainState({
    required int remoteUserId,
    required String domain,
    bool clearItemStates = true,
    bool clearListEtags = true,
    bool clearRunAt = true,
    bool clearCursors = false,
  }) async {
    final normalizedDomain = _normalizeDomain(domain);
    await _db.transaction(() async {
      if (clearItemStates) {
        await (_db.delete(_db.syncItemStates)
              ..where((tbl) =>
                  tbl.remoteUserId.equals(remoteUserId) &
                  tbl.domain.equals(normalizedDomain)))
            .go();
      }
      if (clearListEtags) {
        await (_db.delete(_db.syncMetadataEntries)
              ..where((tbl) =>
                  tbl.remoteUserId.equals(remoteUserId) &
                  tbl.kind.equals(metadataKindListEtag) &
                  tbl.domain.equals(normalizedDomain)))
            .go();
      }
      if (clearRunAt) {
        await (_db.delete(_db.syncMetadataEntries)
              ..where((tbl) =>
                  tbl.remoteUserId.equals(remoteUserId) &
                  tbl.kind.equals(metadataKindRunAt) &
                  tbl.domain.equals(normalizedDomain)))
            .go();
      }
      if (clearCursors) {
        await (_db.delete(_db.syncMetadataEntries)
              ..where((tbl) =>
                  tbl.remoteUserId.equals(remoteUserId) &
                  tbl.kind.equals(metadataKindCursor) &
                  tbl.domain.equals(normalizedDomain)))
            .go();
      }
    });
  }

  Future<DateTime?> readSyncRunAt({
    required int remoteUserId,
    required String domain,
  }) {
    return readRunAt(remoteUserId: remoteUserId, domain: domain);
  }

  Future<void> writeSyncRunAt({
    required int remoteUserId,
    required String domain,
    required DateTime runAt,
  }) {
    return writeRunAt(
      remoteUserId: remoteUserId,
      domain: domain,
      runAt: runAt,
    );
  }

  Future<SyncItemState?> readSyncItemState({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) {
    return readItemState(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
    );
  }

  Future<void> writeSyncItemState({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
    required String contentHash,
    required DateTime lastChangedAt,
    required DateTime lastSyncedAt,
  }) {
    return writeItemState(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
      contentHash: contentHash,
      lastChangedAt: lastChangedAt,
      lastSyncedAt: lastSyncedAt,
    );
  }

  Future<void> clearSyncDomainState({
    required int remoteUserId,
    required String domain,
    bool clearItemStates = true,
    bool clearListEtags = true,
    bool clearRunAt = true,
    bool clearCursors = false,
  }) {
    return clearDomainState(
      remoteUserId: remoteUserId,
      domain: domain,
      clearItemStates: clearItemStates,
      clearListEtags: clearListEtags,
      clearRunAt: clearRunAt,
      clearCursors: clearCursors,
    );
  }

  Future<String?> _readMetadataValue({
    required int remoteUserId,
    required String kind,
    required String domain,
    required String scopeKey,
  }) async {
    final row = await (_db.select(_db.syncMetadataEntries)
          ..where((tbl) =>
              tbl.remoteUserId.equals(remoteUserId) &
              tbl.kind.equals(kind) &
              tbl.domain.equals(_normalizeDomain(domain)) &
              tbl.scopeKey.equals(scopeKey.trim())))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    final normalized = row.value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> _upsertMetadata({
    required int remoteUserId,
    required String kind,
    required String domain,
    required String scopeKey,
    required String value,
  }) {
    return _db.into(_db.syncMetadataEntries).insertOnConflictUpdate(
          SyncMetadataEntriesCompanion.insert(
            remoteUserId: remoteUserId,
            kind: kind,
            domain: _normalizeDomain(domain),
            scopeKey: scopeKey.trim(),
            value: value,
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  String _normalizeDomain(String value) {
    return value.trim().toLowerCase();
  }
}
