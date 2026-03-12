import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../constants.dart';
import '../db/app_database.dart';
import '../security/pin_hasher.dart';
import 'remote_teacher_identity_service.dart';
import 'session_crypto_service.dart';
import 'session_sync_api_service.dart';
import 'session_upload_cache_service.dart';
import 'sync_state_repository.dart';
import 'user_key_service.dart';

class SessionSyncService {
  SessionSyncService({
    required AppDatabase db,
    required SyncStateRepository secureStorage,
    required SessionSyncApiService api,
    required UserKeyService userKeyService,
    SessionCryptoService? crypto,
    SessionUploadCacheService? sessionUploadCacheService,
  })  : _db = db,
        _secureStorage = secureStorage,
        _api = api,
        _userKeyService = userKeyService,
        _crypto = crypto ?? SessionCryptoService(),
        _sessionUploadCacheService = sessionUploadCacheService;

  final AppDatabase _db;
  final SyncStateRepository _secureStorage;
  final SessionSyncApiService _api;
  final UserKeyService _userKeyService;
  final SessionCryptoService _crypto;
  final SessionUploadCacheService? _sessionUploadCacheService;
  final RemoteTeacherIdentityService _remoteTeacherIdentity =
      const RemoteTeacherIdentityService();
  static final Uuid _uuid = Uuid();
  static final RegExp _versionSuffixPattern = RegExp(r'_(\d{10,})$');
  static final RegExp _secondLevelChapterPattern = RegExp(r'^(\d+\.\d+)');
  static const Duration _syncMinInterval = Duration(seconds: 60);
  static const String _syncDomainSessionUpload = 'session_upload';
  static const String _syncDomainSessionGroupUpload = 'session_group_upload';
  static const String _syncDomainProgressUpload = 'progress_upload';
  static const String _syncDomainProgressChunkUpload = 'progress_chunk_upload';
  static const String _syncDomainSessionDownload = 'session_download';
  static const String _syncDomainProgressDownload = 'progress_download';
  static const String _syncDomainProgressChunkDownload =
      'progress_chunk_download';
  static const String _syncDomainDownloadManifest = 'download_manifest';
  static const String _syncRunDomainProgressUpload =
      'session_sync_run_progress_upload';
  static const String _syncRunDomainSessionUpload =
      'session_sync_run_session_upload';
  static const String _syncRunDomainSessionDownload =
      'session_sync_run_download';
  static const int _progressUploadBatchSize = 200;
  static const int _progressChunkUploadBatchSize = 24;
  static const int _progressUploadIsolationMaxSplits = 24;
  bool _syncing = false;

  Future<void> prepareForAutoSync({
    required User currentUser,
    required String password,
  }) async {
    final remoteUserId = _requireRemoteUserId(currentUser);
    await _ensureKeyPairWithPassword(
      remoteUserId: remoteUserId,
      password: password,
    );
  }

  Future<void> syncNow({
    required User currentUser,
    required String password,
  }) async {
    if (_syncing) {
      return;
    }
    _syncing = true;
    try {
      final remoteUserId = _requireRemoteUserId(currentUser);
      final keyPair = await _ensureKeyPairWithPassword(
        remoteUserId: remoteUserId,
        password: password,
      );
      await _syncInternal(
        currentUser,
        remoteUserId,
        keyPair,
        force: true,
      );
    } finally {
      _syncing = false;
    }
  }

  Future<void> syncIfReady({required User currentUser}) async {
    if (_syncing) {
      return;
    }
    final remoteUserId = currentUser.remoteUserId;
    if (remoteUserId == null || remoteUserId <= 0) {
      return;
    }
    final keyPair = await _userKeyService.tryLoadLocalKeyPair(remoteUserId);
    if (keyPair == null) {
      return;
    }
    _syncing = true;
    try {
      await _syncInternal(
        currentUser,
        remoteUserId,
        keyPair,
      );
    } finally {
      _syncing = false;
    }
  }

  Future<void> forcePullFromServer({
    required User currentUser,
    bool wipeLocalStudentData = true,
  }) async {
    if (_syncing) {
      return;
    }
    final remoteUserId = _requireRemoteUserId(currentUser);
    final keyPair = await _userKeyService.tryLoadLocalKeyPair(remoteUserId);
    if (keyPair == null) {
      throw StateError(
        'Session sync key is not ready. Log out and log in again first.',
      );
    }
    _syncing = true;
    try {
      if (currentUser.role == 'student' && wipeLocalStudentData) {
        await _clearLocalStudentSessionAndProgressData(
          studentId: currentUser.id,
        );
      }
      await _resetDownloadSyncState(remoteUserId: remoteUserId);
      await _runCategoryIfDue(
        remoteUserId: remoteUserId,
        runDomain: _syncRunDomainSessionDownload,
        force: true,
        action: () => _downloadRemoteData(currentUser, remoteUserId, keyPair),
      );
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncInternal(
      User currentUser, int remoteUserId, SimpleKeyPair keyPair,
      {bool force = false}) async {
    await _runCategoryIfDue(
      remoteUserId: remoteUserId,
      runDomain: _syncRunDomainSessionDownload,
      force: force,
      action: () => _downloadRemoteData(currentUser, remoteUserId, keyPair),
    );
    await _runCategoryIfDue(
      remoteUserId: remoteUserId,
      runDomain: _syncRunDomainProgressUpload,
      force: force,
      action: () => _uploadPendingProgress(currentUser, remoteUserId),
    );
    await _runCategoryIfDue(
      remoteUserId: remoteUserId,
      runDomain: _syncRunDomainSessionUpload,
      force: force,
      action: () => _uploadPendingSessions(currentUser, remoteUserId),
    );
  }

  Future<void> _resetDownloadSyncState({required int remoteUserId}) async {
    await _secureStorage.deleteSessionSyncCursor(remoteUserId);
    await _secureStorage.deleteProgressSyncCursor(remoteUserId);
    await _secureStorage.clearSyncDomainState(
      remoteUserId: remoteUserId,
      domain: _syncDomainDownloadManifest,
    );
    await _secureStorage.clearSyncDomainState(
      remoteUserId: remoteUserId,
      domain: _syncDomainSessionDownload,
    );
    await _secureStorage.clearSyncDomainState(
      remoteUserId: remoteUserId,
      domain: _syncDomainProgressDownload,
    );
    await _secureStorage.clearSyncDomainState(
      remoteUserId: remoteUserId,
      domain: _syncDomainProgressChunkDownload,
    );
    await _secureStorage.clearSyncDomainState(
      remoteUserId: remoteUserId,
      domain: _syncRunDomainSessionDownload,
      clearItemStates: false,
      clearListEtags: false,
    );
  }

  Future<void> _clearLocalStudentSessionAndProgressData({
    required int studentId,
  }) async {
    await _db.transaction(() async {
      final sessions = await (_db.select(_db.chatSessions)
            ..where((tbl) => tbl.studentId.equals(studentId)))
          .get();
      final sessionIds = sessions.map((session) => session.id).toList();
      if (sessionIds.isNotEmpty) {
        await (_db.delete(_db.chatMessages)
              ..where((tbl) => tbl.sessionId.isIn(sessionIds)))
            .go();
        await (_db.delete(_db.llmCalls)
              ..where((tbl) => tbl.sessionId.isIn(sessionIds)))
            .go();
        await (_db.delete(_db.chatSessions)
              ..where((tbl) => tbl.id.isIn(sessionIds)))
            .go();
      }
      await (_db.delete(_db.progressEntries)
            ..where((tbl) => tbl.studentId.equals(studentId)))
          .go();
      await (_db.delete(_db.llmCalls)
            ..where((tbl) => tbl.studentId.equals(studentId)))
          .go();
    });
  }

  Future<SimpleKeyPair> _ensureKeyPairWithPassword({
    required int remoteUserId,
    required String password,
  }) {
    return _userKeyService.ensureUserKeyPair(
      remoteUserId: remoteUserId,
      password: password,
    );
  }

  Future<void> _runCategoryIfDue({
    required int remoteUserId,
    required String runDomain,
    required Future<void> Function() action,
    required bool force,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    if (!force) {
      final lastRun = await _secureStorage.readSyncRunAt(
        remoteUserId: remoteUserId,
        domain: runDomain,
      );
      if (lastRun != null &&
          nowUtc.difference(lastRun.toUtc()) < _syncMinInterval) {
        return;
      }
    }
    await action();
    await _secureStorage.writeSyncRunAt(
      remoteUserId: remoteUserId,
      domain: runDomain,
      runAt: nowUtc,
    );
  }

  Future<void> _uploadPendingProgress(
    User currentUser,
    int remoteUserId,
  ) async {
    if (currentUser.role != 'student') {
      return;
    }
    final latestLocalProgressUpdatedAt =
        await _db.getLatestProgressUpdatedAtForSync(studentId: currentUser.id);
    if (latestLocalProgressUpdatedAt == null) {
      return;
    }
    final lastUploadRunAt = await _secureStorage.readSyncRunAt(
      remoteUserId: remoteUserId,
      domain: _syncRunDomainProgressUpload,
    );
    if (lastUploadRunAt != null &&
        !latestLocalProgressUpdatedAt.isAfter(lastUploadRunAt.toUtc())) {
      return;
    }
    final entries = await _db.listProgressEntriesForSyncUpload(
      studentId: currentUser.id,
      updatedAtOrAfter: lastUploadRunAt?.toUtc(),
    );
    if (entries.isEmpty) {
      return;
    }
    try {
      await _uploadPendingProgressChunks(
        remoteUserId: remoteUserId,
        entries: entries,
      );
    } on SessionSyncApiException catch (error) {
      if (error.statusCode != 404) {
        rethrow;
      }
      await _uploadPendingProgressLegacy(
        remoteUserId: remoteUserId,
        entries: entries,
      );
    }
  }

  Future<void> _uploadPendingProgressChunks({
    required int remoteUserId,
    required List<ProgressEntry> entries,
  }) async {
    final chapterGroups = <String, _ProgressChunkGroup>{};
    for (final entry in entries) {
      if (entry.kpKey == kTreeViewStateKpKey) {
        continue;
      }
      final remoteCourseId = await _db.getRemoteCourseId(entry.courseVersionId);
      if (remoteCourseId == null || remoteCourseId <= 0) {
        continue;
      }
      final entryUpdatedAt = entry.updatedAt.toUtc();
      final chapterKey = _extractSecondLevelChapter(entry.kpKey);
      final groupScopeKey = '$remoteCourseId:$chapterKey';
      final scopeKey = '$remoteCourseId:${entry.kpKey.trim()}';
      final payloadHash = _hashProgressPayloadCore(
        entry: entry,
        remoteCourseId: remoteCourseId,
        remoteUserId: remoteUserId,
      );
      final group = chapterGroups.putIfAbsent(
        groupScopeKey,
        () => _ProgressChunkGroup(
          scopeKey: groupScopeKey,
          remoteCourseId: remoteCourseId,
          chapterKey: chapterKey,
          courseVersionId: entry.courseVersionId,
          studentId: entry.studentId,
        ),
      );
      final member = _ProgressChunkMember(
        entry: entry,
        scopeKey: scopeKey,
        updatedAt: entryUpdatedAt,
        payloadHash: payloadHash,
      );
      group.members.add(member);
      final syncState = await _secureStorage.readSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainProgressUpload,
        scopeKey: scopeKey,
      );
      final downloadedState = await _secureStorage.readSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainProgressDownload,
        scopeKey: scopeKey,
      );
      if (downloadedState != null &&
          downloadedState.lastChangedAt.toUtc().isAfter(entryUpdatedAt)) {
        group.blockedByRemoteNewer = true;
        continue;
      }
      if (!_isTimestampNewer(entryUpdatedAt, syncState?.lastSyncedAt)) {
        continue;
      }
      if (syncState != null && syncState.contentHash == payloadHash) {
        await _secureStorage.writeSyncItemState(
          remoteUserId: remoteUserId,
          domain: _syncDomainProgressUpload,
          scopeKey: scopeKey,
          contentHash: payloadHash,
          lastChangedAt: entryUpdatedAt,
          lastSyncedAt: entryUpdatedAt,
        );
        continue;
      }
      group.hasPendingChanges = true;
    }
    final groupsToUpload = chapterGroups.values
        .where(
            (group) => group.hasPendingChanges && !group.blockedByRemoteNewer)
        .toList(growable: false);
    if (groupsToUpload.isEmpty) {
      return;
    }

    final keysByCourse = <int, CourseKeyBundle>{};
    final courseSubjectsByVersion = <int, String>{};
    final preparedUploads = <_PreparedProgressChunkUpload>[];
    for (final group in groupsToUpload) {
      var resolvedKeys = keysByCourse[group.remoteCourseId];
      resolvedKeys ??= await _api.getCourseKeys(
        courseId: group.remoteCourseId,
        studentUserId: remoteUserId,
      );
      keysByCourse[group.remoteCourseId] = resolvedKeys;

      final chunkItems = <Map<String, dynamic>>[];
      final itemStateWrites = <_SyncStateWrite>[];
      var groupUpdatedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      var courseSubject = '';
      final chapterEntries = await _db.listProgressEntriesForChapterSyncUpload(
        studentId: group.studentId,
        courseVersionId: group.courseVersionId,
        chapterKey: group.chapterKey,
      );
      final fullMembers = chapterEntries
          .map(
            (entry) => _ProgressChunkMember(
              entry: entry,
              scopeKey: '${group.remoteCourseId}:${entry.kpKey.trim()}',
              updatedAt: entry.updatedAt.toUtc(),
              payloadHash: _hashProgressPayloadCore(
                entry: entry,
                remoteCourseId: group.remoteCourseId,
                remoteUserId: remoteUserId,
              ),
            ),
          )
          .toList(growable: false);
      for (final member in fullMembers) {
        final entry = member.entry;
        var resolvedSubject = courseSubjectsByVersion[entry.courseVersionId];
        if (resolvedSubject == null) {
          resolvedSubject = await _resolveCourseSubject(entry.courseVersionId);
          courseSubjectsByVersion[entry.courseVersionId] = resolvedSubject;
        }
        if (courseSubject.isEmpty) {
          courseSubject = resolvedSubject;
        }
        final payload = _buildProgressPayload(
          entry: entry,
          courseSubject: resolvedSubject,
          remoteCourseId: group.remoteCourseId,
          teacherUserId: resolvedKeys.teacherUserId,
          studentUserId: resolvedKeys.studentUserId,
        );
        chunkItems.add(payload);
        itemStateWrites.add(
          _SyncStateWrite(
            domain: _syncDomainProgressUpload,
            scopeKey: member.scopeKey,
            contentHash: member.payloadHash,
            lastChangedAt: member.updatedAt,
            lastSyncedAt: member.updatedAt,
          ),
        );
        groupUpdatedAt = _latestTimestamp(groupUpdatedAt, member.updatedAt);
      }
      chunkItems.sort((left, right) {
        final leftKp = (left['kp_key'] as String? ?? '').trim();
        final rightKp = (right['kp_key'] as String? ?? '').trim();
        if (leftKp == rightKp) {
          final leftUpdated = (left['updated_at'] as String? ?? '').trim();
          final rightUpdated = (right['updated_at'] as String? ?? '').trim();
          return leftUpdated.compareTo(rightUpdated);
        }
        return leftKp.compareTo(rightKp);
      });
      final chunkPayload = <String, dynamic>{
        'version': 1,
        'course_id': group.remoteCourseId,
        'course_subject': courseSubject,
        'chapter_key': group.chapterKey,
        'teacher_remote_user_id': resolvedKeys.teacherUserId,
        'student_remote_user_id': resolvedKeys.studentUserId,
        'updated_at': groupUpdatedAt.toUtc().toIso8601String(),
        'items': chunkItems,
      };
      final chunkHash = _hashCanonicalJson(chunkPayload);
      final groupState = await _secureStorage.readSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainProgressChunkUpload,
        scopeKey: group.scopeKey,
      );
      if (!_isTimestampNewer(groupUpdatedAt, groupState?.lastSyncedAt)) {
        continue;
      }
      if (groupState != null && groupState.contentHash == chunkHash) {
        for (final stateWrite in itemStateWrites) {
          await _secureStorage.writeSyncItemState(
            remoteUserId: remoteUserId,
            domain: stateWrite.domain,
            scopeKey: stateWrite.scopeKey,
            contentHash: stateWrite.contentHash,
            lastChangedAt: stateWrite.lastChangedAt,
            lastSyncedAt: stateWrite.lastSyncedAt,
          );
        }
        await _secureStorage.writeSyncItemState(
          remoteUserId: remoteUserId,
          domain: _syncDomainProgressChunkUpload,
          scopeKey: group.scopeKey,
          contentHash: chunkHash,
          lastChangedAt: groupUpdatedAt,
          lastSyncedAt: groupUpdatedAt,
        );
        continue;
      }
      final envelope = await _crypto.encryptPayload(
        payload: chunkPayload,
        recipients: [
          RecipientPublicKey(
            userId: resolvedKeys.teacherUserId,
            publicKey: _crypto.decodePublicKey(resolvedKeys.teacherPublicKey),
          ),
          RecipientPublicKey(
            userId: resolvedKeys.studentUserId,
            publicKey: _crypto.decodePublicKey(resolvedKeys.studentPublicKey),
          ),
        ],
      );
      final envelopeJson = jsonEncode(envelope.toJson());
      preparedUploads.add(
        _PreparedProgressChunkUpload(
          upload: ProgressChunkUploadEntry(
            courseId: group.remoteCourseId,
            chapterKey: group.chapterKey,
            itemCount: chunkItems.length,
            updatedAt: groupUpdatedAt.toUtc().toIso8601String(),
            envelope: base64Encode(utf8.encode(envelopeJson)),
            envelopeHash: _hashEnvelope(envelopeJson),
          ),
          itemStateWrites: itemStateWrites,
          groupStateWrite: _SyncStateWrite(
            domain: _syncDomainProgressChunkUpload,
            scopeKey: group.scopeKey,
            contentHash: chunkHash,
            lastChangedAt: groupUpdatedAt,
            lastSyncedAt: groupUpdatedAt,
          ),
        ),
      );
    }
    if (preparedUploads.isEmpty) {
      return;
    }
    for (var index = 0;
        index < preparedUploads.length;
        index += _progressChunkUploadBatchSize) {
      final endExclusive = index + _progressChunkUploadBatchSize;
      final chunk = preparedUploads.sublist(
        index,
        endExclusive > preparedUploads.length
            ? preparedUploads.length
            : endExclusive,
      );
      await _api.uploadProgressChunkBatch(
        chunk.map((item) => item.upload).toList(growable: false),
      );
      for (final prepared in chunk) {
        for (final stateWrite in prepared.itemStateWrites) {
          await _secureStorage.writeSyncItemState(
            remoteUserId: remoteUserId,
            domain: stateWrite.domain,
            scopeKey: stateWrite.scopeKey,
            contentHash: stateWrite.contentHash,
            lastChangedAt: stateWrite.lastChangedAt,
            lastSyncedAt: stateWrite.lastSyncedAt,
          );
        }
        final groupStateWrite = prepared.groupStateWrite;
        await _secureStorage.writeSyncItemState(
          remoteUserId: remoteUserId,
          domain: groupStateWrite.domain,
          scopeKey: groupStateWrite.scopeKey,
          contentHash: groupStateWrite.contentHash,
          lastChangedAt: groupStateWrite.lastChangedAt,
          lastSyncedAt: groupStateWrite.lastSyncedAt,
        );
      }
    }
  }

  Future<void> _uploadPendingProgressLegacy({
    required int remoteUserId,
    required List<ProgressEntry> entries,
  }) async {
    final keysByCourse = <int, CourseKeyBundle>{};
    final courseSubjectsByVersion = <int, String>{};
    final pendingUploads = <_PendingProgressUpload>[];
    for (final entry in entries) {
      if (entry.kpKey == kTreeViewStateKpKey) {
        continue;
      }
      final remoteCourseId = await _db.getRemoteCourseId(entry.courseVersionId);
      if (remoteCourseId == null || remoteCourseId <= 0) {
        continue;
      }
      final entryUpdatedAt = entry.updatedAt.toUtc();
      final scopeKey = '$remoteCourseId:${entry.kpKey}';
      final syncState = await _secureStorage.readSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainProgressUpload,
        scopeKey: scopeKey,
      );
      final downloadedState = await _secureStorage.readSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainProgressDownload,
        scopeKey: scopeKey,
      );
      if (downloadedState != null &&
          downloadedState.lastChangedAt.toUtc().isAfter(entryUpdatedAt)) {
        continue;
      }
      if (!_isTimestampNewer(entryUpdatedAt, syncState?.lastSyncedAt)) {
        continue;
      }
      final payloadHash = _hashProgressPayloadCore(
        entry: entry,
        remoteCourseId: remoteCourseId,
        remoteUserId: remoteUserId,
      );
      if (syncState != null && syncState.contentHash == payloadHash) {
        await _secureStorage.writeSyncItemState(
          remoteUserId: remoteUserId,
          domain: _syncDomainProgressUpload,
          scopeKey: scopeKey,
          contentHash: payloadHash,
          lastChangedAt: entryUpdatedAt,
          lastSyncedAt: entryUpdatedAt,
        );
        continue;
      }
      var resolvedKeys = keysByCourse[remoteCourseId];
      resolvedKeys ??= await _api.getCourseKeys(
        courseId: remoteCourseId,
        studentUserId: remoteUserId,
      );
      keysByCourse[remoteCourseId] = resolvedKeys;
      var courseSubject = courseSubjectsByVersion[entry.courseVersionId];
      if (courseSubject == null) {
        courseSubject = await _resolveCourseSubject(entry.courseVersionId);
        courseSubjectsByVersion[entry.courseVersionId] = courseSubject;
      }
      final payload = _buildProgressPayload(
        entry: entry,
        courseSubject: courseSubject,
        remoteCourseId: remoteCourseId,
        teacherUserId: resolvedKeys.teacherUserId,
        studentUserId: resolvedKeys.studentUserId,
      );
      final envelope = await _crypto.encryptPayload(
        payload: payload,
        recipients: [
          RecipientPublicKey(
            userId: resolvedKeys.teacherUserId,
            publicKey: _crypto.decodePublicKey(resolvedKeys.teacherPublicKey),
          ),
          RecipientPublicKey(
            userId: resolvedKeys.studentUserId,
            publicKey: _crypto.decodePublicKey(resolvedKeys.studentPublicKey),
          ),
        ],
      );
      final envelopeJson = jsonEncode(envelope.toJson());
      pendingUploads.add(
        _PendingProgressUpload(
          upload: ProgressUploadEntry(
            courseId: remoteCourseId,
            kpKey: entry.kpKey,
            updatedAt: entry.updatedAt.toUtc().toIso8601String(),
            envelope: base64Encode(utf8.encode(envelopeJson)),
            envelopeHash: _hashEnvelope(envelopeJson),
          ),
          stateWrite: _SyncStateWrite(
            domain: _syncDomainProgressUpload,
            scopeKey: scopeKey,
            contentHash: payloadHash,
            lastChangedAt: entryUpdatedAt,
            lastSyncedAt: entryUpdatedAt,
          ),
        ),
      );
    }
    if (pendingUploads.isEmpty) {
      return;
    }
    await _uploadProgressInChunksWithIsolation(
      remoteUserId: remoteUserId,
      pendingUploads: pendingUploads,
    );
  }

  Future<void> _uploadProgressInChunksWithIsolation({
    required int remoteUserId,
    required List<_PendingProgressUpload> pendingUploads,
  }) async {
    final failures = <_FailedProgressUpload>[];
    final splitBudget = _ProgressIsolationBudget(
      remaining: _progressUploadIsolationMaxSplits,
    );
    for (var index = 0;
        index < pendingUploads.length;
        index += _progressUploadBatchSize) {
      final endExclusive = index + _progressUploadBatchSize;
      final chunk = pendingUploads.sublist(
        index,
        endExclusive > pendingUploads.length
            ? pendingUploads.length
            : endExclusive,
      );
      await _uploadProgressChunkWithIsolation(
        remoteUserId: remoteUserId,
        chunk: chunk,
        splitBudget: splitBudget,
        failures: failures,
      );
    }
    if (failures.isEmpty) {
      return;
    }
    final firstFailure = failures.first;
    final status = firstFailure.error.statusCode;
    final statusSuffix = status == null ? '' : ' (status $status)';
    throw SessionSyncApiException(
      'Progress sync failed for ${failures.length} item(s). '
      'First failure: course_id=${firstFailure.upload.courseId}, '
      'kp_key=${firstFailure.upload.kpKey}$statusSuffix: '
      '${firstFailure.error.message}',
      statusCode: status,
    );
  }

  Future<void> _uploadProgressChunkWithIsolation({
    required int remoteUserId,
    required List<_PendingProgressUpload> chunk,
    required _ProgressIsolationBudget splitBudget,
    required List<_FailedProgressUpload> failures,
  }) async {
    if (chunk.isEmpty) {
      return;
    }
    try {
      await _api.uploadProgressBatch(
        chunk.map((pending) => pending.upload).toList(growable: false),
      );
      for (final pending in chunk) {
        final stateWrite = pending.stateWrite;
        await _secureStorage.writeSyncItemState(
          remoteUserId: remoteUserId,
          domain: stateWrite.domain,
          scopeKey: stateWrite.scopeKey,
          contentHash: stateWrite.contentHash,
          lastChangedAt: stateWrite.lastChangedAt,
          lastSyncedAt: stateWrite.lastSyncedAt,
        );
      }
      return;
    } on SessionSyncApiException catch (error) {
      if (!_shouldIsolateProgressUploadError(error)) {
        rethrow;
      }
      if (chunk.length == 1) {
        failures.add(
          _FailedProgressUpload(
            upload: chunk.single.upload,
            error: error,
          ),
        );
        return;
      }
      if (splitBudget.remaining <= 0) {
        throw SessionSyncApiException(
          'Progress sync isolation budget exhausted. '
          'Remaining failures=${failures.length}. Last error: ${error.message}',
          statusCode: error.statusCode,
        );
      }
      splitBudget.remaining--;
      final mid = chunk.length ~/ 2;
      await _uploadProgressChunkWithIsolation(
        remoteUserId: remoteUserId,
        chunk: chunk.sublist(0, mid),
        splitBudget: splitBudget,
        failures: failures,
      );
      await _uploadProgressChunkWithIsolation(
        remoteUserId: remoteUserId,
        chunk: chunk.sublist(mid),
        splitBudget: splitBudget,
        failures: failures,
      );
    }
  }

  bool _shouldIsolateProgressUploadError(SessionSyncApiException error) {
    final status = error.statusCode ?? 0;
    if (status == 400) {
      return true;
    }
    if (status != 500) {
      return false;
    }
    final message = error.message.toLowerCase();
    return message.contains('progress sync save failed') ||
        message.contains('progress sync payload');
  }

  Future<void> _uploadPendingSessions(
    User currentUser,
    int remoteUserId,
  ) async {
    final sessions = await (_db.select(_db.chatSessions)
          ..where((tbl) =>
              tbl.syncUpdatedAt.isNotNull() &
              (tbl.syncUploadedAt.isNull() |
                  tbl.syncUploadedAt.isSmallerThan(tbl.syncUpdatedAt))))
        .get();
    if (sessions.isEmpty) {
      return;
    }
    final groupedSessions = <String, List<_PendingSessionUpload>>{};
    for (final session in sessions) {
      if (session.studentId != currentUser.id) {
        continue;
      }
      final syncSession = await _ensureSessionSyncMeta(session);
      final syncId = (syncSession.syncId ?? '').trim();
      if (syncId.isEmpty) {
        continue;
      }
      final remoteCourseId =
          await _db.getRemoteCourseId(syncSession.courseVersionId);
      if (remoteCourseId == null || remoteCourseId <= 0) {
        continue;
      }
      final syncUpdatedAt =
          (syncSession.syncUpdatedAt ?? DateTime.now()).toUtc();
      final chapterKey = _extractSecondLevelChapter(syncSession.kpKey);
      final groupScopeKey = '$remoteCourseId:$chapterKey';
      groupedSessions
          .putIfAbsent(groupScopeKey, () => <_PendingSessionUpload>[])
          .add(
            _PendingSessionUpload(
              session: syncSession,
              syncId: syncId,
              syncUpdatedAt: syncUpdatedAt,
              remoteCourseId: remoteCourseId,
            ),
          );
    }
    if (groupedSessions.isEmpty) {
      return;
    }
    final keysByCourse = <int, CourseKeyBundle>{};
    for (final groupEntry in groupedSessions.entries) {
      final groupScopeKey = groupEntry.key;
      final groupItems = groupEntry.value;
      if (groupItems.isEmpty) {
        continue;
      }
      final groupUpdatedAt = groupItems
          .map((item) => item.syncUpdatedAt)
          .reduce((left, right) => _latestTimestamp(left, right));
      final groupHash = _hashSessionUploadGroup(groupItems);
      final groupState = await _secureStorage.readSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainSessionGroupUpload,
        scopeKey: groupScopeKey,
      );
      if (!_isTimestampNewer(groupUpdatedAt, groupState?.lastSyncedAt)) {
        for (final item in groupItems) {
          await _markSessionUploaded(
            sessionId: item.session.id,
            uploadedAt: item.syncUpdatedAt,
          );
        }
        continue;
      }
      if (groupState != null && groupState.contentHash == groupHash) {
        for (final item in groupItems) {
          await _markSessionUploaded(
            sessionId: item.session.id,
            uploadedAt: item.syncUpdatedAt,
          );
        }
        await _secureStorage.writeSyncItemState(
          remoteUserId: remoteUserId,
          domain: _syncDomainSessionGroupUpload,
          scopeKey: groupScopeKey,
          contentHash: groupHash,
          lastChangedAt: groupUpdatedAt,
          lastSyncedAt: groupUpdatedAt,
        );
        continue;
      }
      await _uploadSessionGroup(
        currentUser: currentUser,
        remoteUserId: remoteUserId,
        keysByCourse: keysByCourse,
        groupItems: groupItems,
      );
      await _secureStorage.writeSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainSessionGroupUpload,
        scopeKey: groupScopeKey,
        contentHash: groupHash,
        lastChangedAt: groupUpdatedAt,
        lastSyncedAt: groupUpdatedAt,
      );
    }
  }

  Future<void> _uploadSessionGroup({
    required User currentUser,
    required int remoteUserId,
    required Map<int, CourseKeyBundle> keysByCourse,
    required List<_PendingSessionUpload> groupItems,
  }) async {
    final preparedUploads = <_PreparedSessionUpload>[];
    final batchEntries = <SessionUploadEntry>[];
    for (final pending in groupItems) {
      final syncSession = pending.session;
      final syncId = pending.syncId;
      final syncUpdatedAt = pending.syncUpdatedAt;
      final syncState = await _secureStorage.readSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainSessionUpload,
        scopeKey: syncId,
      );
      final downloadedState = await _secureStorage.readSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainSessionDownload,
        scopeKey: syncId,
      );
      if (downloadedState != null &&
          downloadedState.lastChangedAt.toUtc().isAfter(syncUpdatedAt)) {
        continue;
      }
      if (!_isTimestampNewer(syncUpdatedAt, syncState?.lastSyncedAt)) {
        await _markSessionUploaded(
          sessionId: syncSession.id,
          uploadedAt: syncUpdatedAt,
        );
        continue;
      }
      final remoteCourseId = pending.remoteCourseId;
      var resolvedKeys = keysByCourse[remoteCourseId];
      resolvedKeys ??= await _api.getCourseKeys(
        courseId: remoteCourseId,
        studentUserId: remoteUserId,
      );
      keysByCourse[remoteCourseId] = resolvedKeys;
      final payload = await _prepareSessionUploadPayload(
        currentUser: currentUser,
        syncSession: syncSession,
        remoteCourseId: remoteCourseId,
        resolvedKeys: resolvedKeys,
        syncUpdatedAt: syncUpdatedAt,
      );
      final payloadHash = _hashCanonicalJson(payload);
      if (syncState != null && syncState.contentHash == payloadHash) {
        await _markSessionUploaded(
          sessionId: syncSession.id,
          uploadedAt: syncUpdatedAt,
        );
        await _secureStorage.writeSyncItemState(
          remoteUserId: remoteUserId,
          domain: _syncDomainSessionUpload,
          scopeKey: syncId,
          contentHash: payloadHash,
          lastChangedAt: syncUpdatedAt,
          lastSyncedAt: syncUpdatedAt,
        );
        continue;
      }
      final envelope = await _crypto.encryptPayload(
        payload: payload,
        recipients: [
          RecipientPublicKey(
            userId: resolvedKeys.teacherUserId,
            publicKey: _crypto.decodePublicKey(resolvedKeys.teacherPublicKey),
          ),
          RecipientPublicKey(
            userId: resolvedKeys.studentUserId,
            publicKey: _crypto.decodePublicKey(resolvedKeys.studentPublicKey),
          ),
        ],
      );
      final envelopeJson = jsonEncode(envelope.toJson());
      final envelopeBase64 = base64Encode(utf8.encode(envelopeJson));
      final envelopeHash = _hashEnvelope(envelopeJson);
      batchEntries.add(
        SessionUploadEntry(
          sessionSyncId: payload['session_sync_id'] as String,
          courseId: remoteCourseId,
          studentUserId: resolvedKeys.studentUserId,
          chapterKey: _extractSecondLevelChapter(syncSession.kpKey),
          updatedAt: (payload['updated_at'] as String?) ??
              DateTime.now().toUtc().toIso8601String(),
          envelope: envelopeBase64,
          envelopeHash: envelopeHash,
        ),
      );
      preparedUploads.add(
        _PreparedSessionUpload(
          sessionId: syncSession.id,
          syncUpdatedAt: syncUpdatedAt,
          syncStateWrite: _SyncStateWrite(
            domain: _syncDomainSessionUpload,
            scopeKey: syncId,
            contentHash: payloadHash,
            lastChangedAt: syncUpdatedAt,
            lastSyncedAt: syncUpdatedAt,
          ),
        ),
      );
    }
    if (batchEntries.isEmpty) {
      return;
    }
    try {
      await _api.uploadSessionBatch(batchEntries);
    } on SessionSyncApiException catch (error) {
      if (error.statusCode != 404) {
        rethrow;
      }
      for (final entry in batchEntries) {
        await _api.uploadSession(
          sessionSyncId: entry.sessionSyncId,
          courseId: entry.courseId,
          studentUserId: entry.studentUserId,
          chapterKey: entry.chapterKey,
          updatedAt: entry.updatedAt,
          envelope: entry.envelope,
          envelopeHash: entry.envelopeHash,
        );
      }
    }
    for (final prepared in preparedUploads) {
      await _markSessionUploaded(
        sessionId: prepared.sessionId,
        uploadedAt: prepared.syncUpdatedAt,
      );
      final syncStateWrite = prepared.syncStateWrite;
      await _secureStorage.writeSyncItemState(
        remoteUserId: remoteUserId,
        domain: syncStateWrite.domain,
        scopeKey: syncStateWrite.scopeKey,
        contentHash: syncStateWrite.contentHash,
        lastChangedAt: syncStateWrite.lastChangedAt,
        lastSyncedAt: syncStateWrite.lastSyncedAt,
      );
    }
  }

  Future<void> _downloadRemoteData(
    User currentUser,
    int remoteUserId,
    SimpleKeyPair keyPair,
  ) async {
    final includeProgress =
        currentUser.role == 'student' || currentUser.role == 'teacher';
    final manifestScopeKey = _downloadManifestScopeKey(currentUser);
    final manifestEtag = await _secureStorage.readSyncListEtag(
      remoteUserId: remoteUserId,
      domain: _syncDomainDownloadManifest,
      scopeKey: manifestScopeKey,
    );
    final manifest = await _api.getDownloadManifest(
      includeProgress: includeProgress,
      ifNoneMatch: manifestEtag,
    );
    await _writeSyncListEtag(
      remoteUserId: remoteUserId,
      domain: _syncDomainDownloadManifest,
      scopeKey: manifestScopeKey,
      etag: manifest.etag,
    );
    if (manifest.notModified) {
      return;
    }

    final localProgressUpdatedAtByRemoteScope =
        includeProgress && currentUser.role == 'student'
            ? _scopeProgressUpdatedAtByStudentRemoteId(
                await _db.getProgressUpdatedAtByRemoteCourseAndKp(
                  studentId: currentUser.id,
                ),
                currentUser.remoteUserId ?? remoteUserId,
              )
            : <String, DateTime>{};
    final sessionFetchIds = <String>[];
    final progressChunkFetchKeys = <ProgressChunkFetchKey>[];
    final progressRowFetchKeys = <ProgressRowFetchKey>[];

    for (final item in manifest.sessions) {
      if (await _shouldFetchSessionManifestItem(
        remoteUserId: remoteUserId,
        item: item,
      )) {
        sessionFetchIds.add(item.sessionSyncId.trim());
      }
    }
    if (includeProgress) {
      for (final item in manifest.progressChunks) {
        if (await _shouldFetchProgressChunkManifestItem(
          remoteUserId: remoteUserId,
          item: item,
        )) {
          progressChunkFetchKeys.add(
            ProgressChunkFetchKey(
              studentUserId: item.studentUserId,
              courseId: item.courseId,
              chapterKey: item.chapterKey.trim(),
            ),
          );
        }
      }
      for (final item in manifest.progressRows) {
        if (await _shouldFetchProgressRowManifestItem(
          remoteUserId: remoteUserId,
          item: item,
          localProgressUpdatedAtByRemoteScope:
              localProgressUpdatedAtByRemoteScope,
        )) {
          progressRowFetchKeys.add(
            ProgressRowFetchKey(
              studentUserId: item.studentUserId,
              courseId: item.courseId,
              kpKey: item.kpKey.trim(),
            ),
          );
        }
      }
    }

    if (sessionFetchIds.isEmpty &&
        progressChunkFetchKeys.isEmpty &&
        progressRowFetchKeys.isEmpty) {
      return;
    }

    final payload = await _api.fetchDownloadPayload(
      request: SyncDownloadFetchRequest(
        sessionSyncIds: sessionFetchIds,
        progressChunks: progressChunkFetchKeys,
        progressRows: progressRowFetchKeys,
      ),
    );

    for (final item in payload.sessions) {
      await _applyDownloadedSessionItem(
        currentUser: currentUser,
        remoteUserId: remoteUserId,
        keyPair: keyPair,
        item: item,
      );
    }
    for (final chunkItem in payload.progressChunks) {
      final progressItems = await _resolveProgressChunkItems(
        chunkItem: chunkItem,
        remoteUserId: remoteUserId,
        keyPair: keyPair,
      );
      for (final progressItem in progressItems) {
        await _applyDownloadedProgressItem(
          currentUser: currentUser,
          remoteUserId: remoteUserId,
          keyPair: keyPair,
          item: progressItem,
          localProgressUpdatedAtByRemoteScope:
              localProgressUpdatedAtByRemoteScope,
        );
      }
      final chunkScopeKey = _progressChunkDownloadScopeKey(
        studentRemoteId: chunkItem.studentUserId,
        courseId: chunkItem.courseId,
        chapterKey: chunkItem.chapterKey,
      );
      final itemUpdatedAt = DateTime.tryParse(chunkItem.updatedAt)?.toUtc() ??
          DateTime.now().toUtc();
      final resolvedChunkHash = _resolveSyncHash(
        primaryHash: chunkItem.envelopeHash,
        fallbackValue: chunkItem.envelope,
      );
      await _secureStorage.writeSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainProgressChunkDownload,
        scopeKey: chunkScopeKey,
        contentHash: resolvedChunkHash,
        lastChangedAt: itemUpdatedAt,
        lastSyncedAt: itemUpdatedAt,
      );
    }
    for (final item in payload.progressRows) {
      await _applyDownloadedProgressItem(
        currentUser: currentUser,
        remoteUserId: remoteUserId,
        keyPair: keyPair,
        item: item,
        localProgressUpdatedAtByRemoteScope:
            localProgressUpdatedAtByRemoteScope,
      );
    }
  }

  Future<bool> _shouldFetchSessionManifestItem({
    required int remoteUserId,
    required SessionSyncManifestItem item,
  }) async {
    final sessionSyncId = item.sessionSyncId.trim();
    if (sessionSyncId.isEmpty) {
      return false;
    }
    final itemUpdatedAt =
        DateTime.tryParse(item.updatedAt)?.toUtc() ?? DateTime.now().toUtc();
    final syncState = await _secureStorage.readSyncItemState(
      remoteUserId: remoteUserId,
      domain: _syncDomainSessionDownload,
      scopeKey: sessionSyncId,
    );
    final remoteHash = _resolveSyncHash(
      primaryHash: item.envelopeHash,
      fallbackValue: sessionSyncId,
    );
    if (syncState != null &&
        !_isTimestampNewer(itemUpdatedAt, syncState.lastChangedAt) &&
        (remoteHash.isEmpty || syncState.contentHash == remoteHash)) {
      return false;
    }
    if (syncState != null &&
        remoteHash.isNotEmpty &&
        syncState.contentHash == remoteHash &&
        !itemUpdatedAt.isAfter(syncState.lastChangedAt.toUtc())) {
      return false;
    }
    final existingLocalSession = await (_db.select(_db.chatSessions)
          ..where((tbl) => tbl.syncId.equals(sessionSyncId))
          ..limit(1))
        .getSingleOrNull();
    if (existingLocalSession != null) {
      final localUpdatedAt =
          (existingLocalSession.syncUpdatedAt ?? existingLocalSession.startedAt)
              .toUtc();
      if (localUpdatedAt.isAfter(itemUpdatedAt)) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _shouldFetchProgressChunkManifestItem({
    required int remoteUserId,
    required ProgressSyncChunkManifestItem item,
  }) async {
    final scopeKey = _progressChunkDownloadScopeKey(
      studentRemoteId: item.studentUserId,
      courseId: item.courseId,
      chapterKey: item.chapterKey,
    );
    final itemUpdatedAt =
        DateTime.tryParse(item.updatedAt)?.toUtc() ?? DateTime.now().toUtc();
    final syncState = await _secureStorage.readSyncItemState(
      remoteUserId: remoteUserId,
      domain: _syncDomainProgressChunkDownload,
      scopeKey: scopeKey,
    );
    final remoteHash = _resolveSyncHash(
      primaryHash: item.envelopeHash,
      fallbackValue: scopeKey,
    );
    if (syncState != null &&
        remoteHash.isNotEmpty &&
        syncState.contentHash == remoteHash &&
        !itemUpdatedAt.isAfter(syncState.lastChangedAt.toUtc())) {
      return false;
    }
    return true;
  }

  Future<bool> _shouldFetchProgressRowManifestItem({
    required int remoteUserId,
    required ProgressSyncManifestItem item,
    required Map<String, DateTime> localProgressUpdatedAtByRemoteScope,
  }) async {
    final kpKey = item.kpKey.trim();
    if (item.courseId <= 0 || kpKey.isEmpty) {
      return false;
    }
    final scopeKey = _progressDownloadScopeKey(
      studentRemoteId: item.studentUserId,
      courseId: item.courseId,
      kpKey: kpKey,
    );
    final itemUpdatedAt =
        DateTime.tryParse(item.updatedAt)?.toUtc() ?? DateTime.now().toUtc();
    final indexedLocalUpdatedAt = localProgressUpdatedAtByRemoteScope[scopeKey];
    if (indexedLocalUpdatedAt != null &&
        !itemUpdatedAt.isAfter(indexedLocalUpdatedAt.toUtc())) {
      return false;
    }
    final syncState = await _secureStorage.readSyncItemState(
      remoteUserId: remoteUserId,
      domain: _syncDomainProgressDownload,
      scopeKey: scopeKey,
    );
    final remoteHash = _resolveSyncHash(
      primaryHash: item.envelopeHash,
      fallbackValue: scopeKey,
    );
    if (syncState != null &&
        remoteHash.isNotEmpty &&
        syncState.contentHash == remoteHash &&
        !itemUpdatedAt.isAfter(syncState.lastChangedAt.toUtc())) {
      return false;
    }
    return true;
  }

  Future<void> _applyDownloadedSessionItem({
    required User currentUser,
    required int remoteUserId,
    required SimpleKeyPair keyPair,
    required SessionSyncItem item,
  }) async {
    final itemUpdatedAt =
        DateTime.tryParse(item.updatedAt)?.toUtc() ?? DateTime.now().toUtc();
    final sessionSyncId = item.sessionSyncId.trim();
    if (sessionSyncId.isEmpty) {
      return;
    }
    final remoteHash = _resolveSyncHash(
      primaryHash: item.envelopeHash,
      fallbackValue: item.envelope,
    );
    final payload = await _decryptItem(item, remoteUserId, keyPair);
    await _importPayload(
      currentUser,
      payload,
      teacherRemoteIdHint: item.teacherUserId,
    );
    final updatedAt =
        DateTime.tryParse(payload['updated_at'] as String? ?? '')?.toUtc() ??
            itemUpdatedAt;
    final resolvedHash =
        remoteHash.isNotEmpty ? remoteHash : _hashCanonicalJson(payload);
    await _secureStorage.writeSyncItemState(
      remoteUserId: remoteUserId,
      domain: _syncDomainSessionDownload,
      scopeKey: sessionSyncId,
      contentHash: resolvedHash,
      lastChangedAt: updatedAt,
      lastSyncedAt: updatedAt,
    );
  }

  String _downloadManifestScopeKey(User currentUser) {
    return currentUser.role == 'student' ? 'student' : 'teacher';
  }

  Future<void> _applyDownloadedProgressItem({
    required User currentUser,
    required int remoteUserId,
    required SimpleKeyPair keyPair,
    required ProgressSyncItem item,
    required Map<String, DateTime> localProgressUpdatedAtByRemoteScope,
  }) async {
    final itemUpdatedAt =
        DateTime.tryParse(item.updatedAt)?.toUtc() ?? DateTime.now().toUtc();
    final kpKey = item.kpKey.trim();
    if (item.courseId <= 0 || kpKey.isEmpty) {
      return;
    }
    final scopeKey = _progressDownloadScopeKey(
      studentRemoteId: item.studentUserId,
      courseId: item.courseId,
      kpKey: kpKey,
    );
    final indexedLocalUpdatedAt = localProgressUpdatedAtByRemoteScope[scopeKey];
    if (indexedLocalUpdatedAt != null &&
        !itemUpdatedAt.isAfter(indexedLocalUpdatedAt.toUtc())) {
      return;
    }
    final syncState = await _secureStorage.readSyncItemState(
      remoteUserId: remoteUserId,
      domain: _syncDomainProgressDownload,
      scopeKey: scopeKey,
    );
    if (!_isTimestampNewer(itemUpdatedAt, syncState?.lastChangedAt)) {
      return;
    }
    final fallbackHash = _hashProgressSyncItem(item);
    final remoteHash = _resolveSyncHash(
      primaryHash: item.envelopeHash,
      fallbackValue:
          item.envelope.trim().isNotEmpty ? item.envelope : fallbackHash,
    );
    if (syncState != null &&
        remoteHash.isNotEmpty &&
        syncState.contentHash == remoteHash) {
      await _secureStorage.writeSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainProgressDownload,
        scopeKey: scopeKey,
        contentHash: remoteHash,
        lastChangedAt: itemUpdatedAt,
        lastSyncedAt: itemUpdatedAt,
      );
      return;
    }
    final resolved = await _resolveProgressPayload(
      item: item,
      remoteUserId: remoteUserId,
      keyPair: keyPair,
    );
    final localTeacherId = await _resolveLocalTeacherId(
      currentUser: currentUser,
      teacherRemoteId: item.teacherUserId,
    );
    var courseVersionId = await _db.getCourseVersionIdForRemoteCourse(
      resolved.courseId,
    );
    if (courseVersionId == null && localTeacherId != null) {
      courseVersionId = await _findLocalCourseVersionBySubject(
        teacherId: localTeacherId,
        subject: resolved.courseSubject,
      );
    }
    if (courseVersionId == null && currentUser.role == 'student') {
      courseVersionId = await _findAssignedCourseVersionBySubject(
        studentId: currentUser.id,
        subject: resolved.courseSubject,
      );
    }
    if (courseVersionId == null) {
      courseVersionId = await _db.createCourseVersion(
        teacherId: localTeacherId ?? currentUser.id,
        subject: resolved.courseSubject.trim().isEmpty
            ? 'Course'
            : resolved.courseSubject.trim(),
        granularity: 1,
        textbookText: '',
        sourcePath: null,
      );
    }
    if (localTeacherId != null) {
      await _ensureCourseTeacher(
        courseVersionId: courseVersionId,
        expectedTeacherId: localTeacherId,
      );
    }
    await _bindRemoteCourseLinkIfNeeded(
      courseVersionId: courseVersionId,
      remoteCourseId: resolved.courseId,
    );
    final localStudentId = await _resolveLocalStudentId(
      currentUser: currentUser,
      studentRemoteId: item.studentUserId,
      studentUsername: null,
    );
    await _db.assignStudent(
      studentId: localStudentId,
      courseVersionId: courseVersionId,
    );
    final updatedAt =
        DateTime.tryParse(resolved.updatedAt)?.toUtc() ?? itemUpdatedAt;
    final existingLocalProgress = await _db.getProgress(
      studentId: localStudentId,
      courseVersionId: courseVersionId,
      kpKey: resolved.kpKey,
    );
    if (existingLocalProgress != null &&
        existingLocalProgress.updatedAt.toUtc().isAfter(updatedAt)) {
      final resolvedHash =
          remoteHash.isNotEmpty ? remoteHash : _hashResolvedProgress(resolved);
      await _secureStorage.writeSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainProgressDownload,
        scopeKey: scopeKey,
        contentHash: resolvedHash,
        lastChangedAt: itemUpdatedAt,
        lastSyncedAt: itemUpdatedAt,
      );
      localProgressUpdatedAtByRemoteScope[scopeKey] =
          existingLocalProgress.updatedAt.toUtc();
      return;
    }
    await _db.upsertProgressFromSync(
      studentId: localStudentId,
      courseVersionId: courseVersionId,
      kpKey: resolved.kpKey,
      lit: resolved.lit,
      litPercent: resolved.litPercent,
      questionLevel:
          resolved.questionLevel.isEmpty ? null : resolved.questionLevel,
      summaryText: resolved.summaryText.isEmpty ? null : resolved.summaryText,
      summaryRawResponse: resolved.summaryRawResponse.isEmpty
          ? null
          : resolved.summaryRawResponse,
      summaryValid: resolved.summaryValid,
      updatedAt: updatedAt,
    );
    final updatedAtUtc = updatedAt.toUtc();
    final resolvedHash =
        remoteHash.isNotEmpty ? remoteHash : _hashResolvedProgress(resolved);
    await _secureStorage.writeSyncItemState(
      remoteUserId: remoteUserId,
      domain: _syncDomainProgressDownload,
      scopeKey: scopeKey,
      contentHash: resolvedHash,
      lastChangedAt: updatedAtUtc,
      lastSyncedAt: updatedAtUtc,
    );
    localProgressUpdatedAtByRemoteScope[scopeKey] = updatedAtUtc;
  }

  Future<List<ProgressSyncItem>> _resolveProgressChunkItems({
    required ProgressSyncChunkItem chunkItem,
    required int remoteUserId,
    required SimpleKeyPair keyPair,
  }) async {
    if (chunkItem.envelope.trim().isEmpty) {
      throw StateError('Progress chunk sync envelope missing.');
    }
    final envelopeJson = utf8.decode(base64Decode(chunkItem.envelope));
    if (chunkItem.envelopeHash.trim().isNotEmpty) {
      final computed = _hashEnvelope(envelopeJson);
      if (computed != chunkItem.envelopeHash.trim()) {
        throw StateError('Progress chunk sync envelope hash mismatch.');
      }
    }
    final decoded = jsonDecode(envelopeJson);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Progress chunk sync envelope invalid.');
    }
    final envelope = EncryptedEnvelope.fromJson(decoded);
    final payload = await _crypto.decryptEnvelope(
      envelope: envelope,
      userKeyPair: keyPair,
      userId: remoteUserId,
    );

    final payloadStudentID = _parsePayloadInt(
      payload['student_remote_user_id'],
      field: 'student_remote_user_id',
    );
    if (payloadStudentID != chunkItem.studentUserId) {
      throw StateError('Progress chunk payload student mismatch.');
    }
    final payloadCourseID = _parsePayloadInt(
      payload['course_id'],
      field: 'course_id',
    );
    if (payloadCourseID != chunkItem.courseId) {
      throw StateError('Progress chunk payload course mismatch.');
    }
    final payloadTeacherID = _parsePayloadInt(
      payload['teacher_remote_user_id'],
      field: 'teacher_remote_user_id',
    );
    final payloadCourseSubject = _parsePayloadString(
      payload['course_subject'],
      field: 'course_subject',
      isRequired: false,
    ).trim();
    final itemList = payload['items'];
    if (itemList is! List) {
      throw StateError('Progress chunk payload items invalid.');
    }
    final results = <ProgressSyncItem>[];
    for (final rawItem in itemList) {
      if (rawItem is! Map<String, dynamic>) {
        continue;
      }
      final kpKey =
          _parsePayloadString(rawItem['kp_key'], field: 'kp_key').trim();
      if (kpKey.isEmpty) {
        continue;
      }
      final updatedAt = _parsePayloadString(
        rawItem['updated_at'],
        field: 'updated_at',
      );
      final litPercentRaw = _parsePayloadInt(
        rawItem['lit_percent'],
        field: 'lit_percent',
      );
      results.add(
        ProgressSyncItem(
          cursorId: 0,
          courseId: payloadCourseID,
          courseSubject: payloadCourseSubject.isNotEmpty
              ? payloadCourseSubject
              : chunkItem.courseSubject,
          teacherUserId: payloadTeacherID,
          studentUserId: payloadStudentID,
          kpKey: kpKey,
          lit: _parsePayloadBool(rawItem['lit'], field: 'lit'),
          litPercent: litPercentRaw.clamp(0, 100).toInt(),
          questionLevel: _parsePayloadString(
            rawItem['question_level'],
            field: 'question_level',
            isRequired: false,
          ),
          summaryText: _parsePayloadString(
            rawItem['summary_text'],
            field: 'summary_text',
            isRequired: false,
          ),
          summaryRawResponse: _parsePayloadString(
            rawItem['summary_raw_response'],
            field: 'summary_raw_response',
            isRequired: false,
          ),
          summaryValid: _parsePayloadNullableBool(
            rawItem['summary_valid'],
            field: 'summary_valid',
          ),
          updatedAt: updatedAt,
          envelope: '',
          envelopeHash: '',
        ),
      );
    }
    return results;
  }

  Future<Map<String, dynamic>> _decryptItem(
    SessionSyncItem item,
    int remoteUserId,
    SimpleKeyPair keyPair,
  ) async {
    if (item.envelope.trim().isEmpty) {
      throw StateError('Session sync envelope missing.');
    }
    final envelopeJson = utf8.decode(base64Decode(item.envelope));
    if (item.envelopeHash.trim().isNotEmpty) {
      final computed = _hashEnvelope(envelopeJson);
      if (computed != item.envelopeHash.trim()) {
        throw StateError('Session sync envelope hash mismatch.');
      }
    }
    final decoded = jsonDecode(envelopeJson);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Session sync envelope invalid.');
    }
    final envelope = EncryptedEnvelope.fromJson(decoded);
    return _crypto.decryptEnvelope(
      envelope: envelope,
      userKeyPair: keyPair,
      userId: remoteUserId,
    );
  }

  Future<void> _importPayload(
    User currentUser,
    Map<String, dynamic> payload, {
    required int teacherRemoteIdHint,
  }) async {
    final sessionSyncId = (payload['session_sync_id'] as String?) ?? '';
    if (sessionSyncId.trim().isEmpty) {
      throw StateError('Session sync id missing.');
    }
    final courseId = (payload['course_id'] as num?)?.toInt() ?? 0;
    final studentRemoteId =
        (payload['student_remote_user_id'] as num?)?.toInt() ?? 0;
    final teacherRemoteId =
        (payload['teacher_remote_user_id'] as num?)?.toInt() ??
            teacherRemoteIdHint;
    final studentUsername = (payload['student_username'] as String?)?.trim();
    final courseSubject = (payload['course_subject'] as String?)?.trim() ?? '';
    final kpKey = (payload['kp_key'] as String?)?.trim() ?? '';
    final kpTitle = (payload['kp_title'] as String?)?.trim();
    final title = (payload['session_title'] as String?)?.trim();
    final summary = (payload['summary_text'] as String?)?.trim();
    final startedAt = DateTime.tryParse(payload['started_at'] as String? ?? '');
    final endedAt = DateTime.tryParse(payload['ended_at'] as String? ?? '');
    final updatedAt =
        DateTime.tryParse(payload['updated_at'] as String? ?? '') ??
            DateTime.now();
    final messages = _parseMessages(payload['messages']);
    if (courseId <= 0 || studentRemoteId <= 0) {
      throw StateError('Session payload missing course or student id.');
    }

    final localStudentId = await _resolveLocalStudentId(
      currentUser: currentUser,
      studentRemoteId: studentRemoteId,
      studentUsername: studentUsername,
    );
    final localTeacherId = await _resolveLocalTeacherId(
      currentUser: currentUser,
      teacherRemoteId: teacherRemoteId,
    );

    var courseVersionId = await _db.getCourseVersionIdForRemoteCourse(courseId);
    if (courseVersionId == null && localTeacherId != null) {
      courseVersionId = await _findLocalCourseVersionBySubject(
        teacherId: localTeacherId,
        subject: courseSubject,
      );
    }
    if (courseVersionId == null && currentUser.role == 'student') {
      courseVersionId = await _findAssignedCourseVersionBySubject(
        studentId: currentUser.id,
        subject: courseSubject,
      );
    }
    if (courseVersionId == null) {
      courseVersionId = await _db.createCourseVersion(
        teacherId: localTeacherId ?? currentUser.id,
        subject: courseSubject.isNotEmpty ? courseSubject : 'Course',
        granularity: 1,
        textbookText: '',
        sourcePath: null,
      );
    }
    if (localTeacherId != null) {
      await _ensureCourseTeacher(
        courseVersionId: courseVersionId,
        expectedTeacherId: localTeacherId,
      );
    }
    await _bindRemoteCourseLinkIfNeeded(
      courseVersionId: courseVersionId,
      remoteCourseId: courseId,
    );
    if (courseSubject.isNotEmpty) {
      await _ensureCourseSubject(
        courseVersionId: courseVersionId,
        expectedSubject: courseSubject,
      );
    }
    if (kpKey.isNotEmpty) {
      final existingNode = await _db.getCourseNodeByKey(courseVersionId, kpKey);
      if (existingNode == null) {
        await _db.into(_db.courseNodes).insert(
              CourseNodesCompanion.insert(
                courseVersionId: courseVersionId,
                kpKey: kpKey,
                title: kpTitle ?? kpKey,
                description: kpTitle ?? kpKey,
                orderIndex: 0,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    }

    await _db.assignStudent(
      studentId: localStudentId,
      courseVersionId: courseVersionId,
    );

    final existing = await (_db.select(_db.chatSessions)
          ..where((tbl) => tbl.syncId.equals(sessionSyncId)))
        .getSingleOrNull();
    if (existing != null) {
      final localUpdatedAt =
          (existing.syncUpdatedAt ?? existing.startedAt).toUtc();
      if (localUpdatedAt.isAfter(updatedAt.toUtc())) {
        return;
      }
    }
    await _db.transaction(() async {
      int sessionId;
      if (existing == null) {
        sessionId = await _db.into(_db.chatSessions).insert(
              ChatSessionsCompanion.insert(
                studentId: localStudentId,
                courseVersionId: courseVersionId!,
                kpKey: kpKey.isNotEmpty ? kpKey : 'session',
                title: Value(title),
                status: const Value('active'),
                startedAt: Value(startedAt ?? updatedAt),
                endedAt: Value(endedAt),
                summaryText: Value(summary),
                controlStateJson: Value(
                  (payload['control_state_json'] as String?)?.trim().isEmpty ==
                          false
                      ? (payload['control_state_json'] as String).trim()
                      : null,
                ),
                controlStateUpdatedAt: Value(
                  DateTime.tryParse(
                    (payload['control_state_updated_at'] as String?) ?? '',
                  ),
                ),
                evidenceStateJson: Value(
                  (payload['evidence_state_json'] as String?)?.trim().isEmpty ==
                          false
                      ? (payload['evidence_state_json'] as String).trim()
                      : null,
                ),
                evidenceStateUpdatedAt: Value(
                  DateTime.tryParse(
                    (payload['evidence_state_updated_at'] as String?) ?? '',
                  ),
                ),
                syncId: Value(sessionSyncId),
                syncUpdatedAt: Value(updatedAt),
                syncUploadedAt: Value(updatedAt),
              ),
            );
      } else {
        sessionId = existing.id;
        await (_db.update(_db.chatSessions)
              ..where((tbl) => tbl.id.equals(existing.id)))
            .write(
          ChatSessionsCompanion(
            studentId: Value(localStudentId),
            courseVersionId: Value(courseVersionId!),
            kpKey: Value(kpKey.isNotEmpty ? kpKey : existing.kpKey),
            title: Value(title),
            startedAt: Value(startedAt ?? existing.startedAt),
            endedAt: Value(endedAt),
            summaryText: Value(summary),
            controlStateJson: Value(
              (payload['control_state_json'] as String?)?.trim().isEmpty ==
                      false
                  ? (payload['control_state_json'] as String).trim()
                  : existing.controlStateJson,
            ),
            controlStateUpdatedAt: Value(
              DateTime.tryParse(
                    (payload['control_state_updated_at'] as String?) ?? '',
                  ) ??
                  existing.controlStateUpdatedAt,
            ),
            evidenceStateJson: Value(
              (payload['evidence_state_json'] as String?)?.trim().isEmpty ==
                      false
                  ? (payload['evidence_state_json'] as String).trim()
                  : existing.evidenceStateJson,
            ),
            evidenceStateUpdatedAt: Value(
              DateTime.tryParse(
                    (payload['evidence_state_updated_at'] as String?) ?? '',
                  ) ??
                  existing.evidenceStateUpdatedAt,
            ),
            syncUpdatedAt: Value(updatedAt),
            syncUploadedAt: Value(updatedAt),
          ),
        );
        await (_db.delete(_db.chatMessages)
              ..where((tbl) => tbl.sessionId.equals(existing.id)))
            .go();
      }

      for (final message in messages) {
        await _db.into(_db.chatMessages).insert(
              ChatMessagesCompanion.insert(
                sessionId: sessionId,
                role: message.role,
                content: message.content,
                rawContent: Value(message.rawContent),
                parsedJson: Value(message.parsedJson),
                action: Value(message.action),
                createdAt: Value(message.createdAt),
              ),
            );
      }
    });
  }

  Future<int> _resolveLocalStudentId({
    required User currentUser,
    required int studentRemoteId,
    required String? studentUsername,
  }) async {
    if (currentUser.remoteUserId == studentRemoteId) {
      return currentUser.id;
    }
    final existing = await _db.findUserByRemoteId(studentRemoteId);
    if (existing != null) {
      if (currentUser.role == 'teacher' &&
          existing.teacherId != currentUser.id) {
        await _db.updateStudentTeacherId(
          studentId: existing.id,
          teacherId: currentUser.id,
        );
      }
      return existing.id;
    }
    final username = (studentUsername ?? '').trim();
    final resolvedUsername =
        username.isNotEmpty ? username : 'student_$studentRemoteId';
    return _db.createUser(
      username: resolvedUsername,
      pinHash: PinHasher.hash('remote_user_placeholder'),
      role: 'student',
      teacherId: currentUser.role == 'teacher' ? currentUser.id : null,
      remoteUserId: studentRemoteId,
    );
  }

  Map<String, DateTime> _scopeProgressUpdatedAtByStudentRemoteId(
    Map<String, DateTime> updatedAtByRemoteCourseAndKp,
    int studentRemoteId,
  ) {
    final result = <String, DateTime>{};
    for (final entry in updatedAtByRemoteCourseAndKp.entries) {
      result['$studentRemoteId:${entry.key}'] = entry.value.toUtc();
    }
    return result;
  }

  String _progressChunkDownloadScopeKey({
    required int studentRemoteId,
    required int courseId,
    required String chapterKey,
  }) {
    final normalizedChapterKey =
        chapterKey.trim().isEmpty ? 'ungrouped' : chapterKey.trim();
    return '${studentRemoteId > 0 ? studentRemoteId : 0}:$courseId:$normalizedChapterKey';
  }

  String _progressDownloadScopeKey({
    required int studentRemoteId,
    required int courseId,
    required String kpKey,
  }) {
    return '${studentRemoteId > 0 ? studentRemoteId : 0}:$courseId:${kpKey.trim()}';
  }

  Future<int?> _resolveLocalTeacherId({
    required User currentUser,
    required int teacherRemoteId,
  }) async {
    if (teacherRemoteId <= 0) {
      return null;
    }
    if (currentUser.remoteUserId == teacherRemoteId) {
      if (currentUser.role != 'teacher') {
        throw StateError('Teacher remote id maps to non-teacher current user.');
      }
      return currentUser.id;
    }
    return _remoteTeacherIdentity.resolveOrCreateLocalTeacherId(
      db: _db,
      remoteTeacherId: teacherRemoteId,
    );
  }

  List<_SyncMessage> _parseMessages(Object? raw) {
    if (raw is! List) {
      return [];
    }
    final messages = <_SyncMessage>[];
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final role = (entry['role'] as String?)?.trim();
      final content = (entry['content'] as String?)?.trim();
      if (role == null || role.isEmpty || content == null || content.isEmpty) {
        continue;
      }
      final rawContent = (entry['raw_content'] as String?)?.trim();
      final parsedJson = (entry['parsed_json'] as String?)?.trim();
      final action = (entry['action'] as String?)?.trim();
      final createdAt =
          DateTime.tryParse(entry['created_at'] as String? ?? '') ??
              DateTime.now();
      messages.add(
        _SyncMessage(
          role: role,
          content: content,
          rawContent:
              rawContent == null || rawContent.isEmpty ? null : rawContent,
          parsedJson:
              parsedJson == null || parsedJson.isEmpty ? null : parsedJson,
          action: action == null || action.isEmpty ? null : action,
          createdAt: createdAt,
        ),
      );
    }
    return messages;
  }

  Map<String, dynamic> _buildPayload({
    required ChatSession session,
    required CourseVersion courseVersion,
    required CourseNode? node,
    required List<ChatMessage> messages,
    required int remoteCourseId,
    required int teacherUserId,
    required int studentUserId,
    required String studentUsername,
    required DateTime updatedAt,
  }) {
    final syncId = session.syncId ?? _uuid.v4();
    return {
      'version': 1,
      'session_sync_id': syncId,
      'course_id': remoteCourseId,
      'course_subject': courseVersion.subject,
      'kp_key': session.kpKey,
      'kp_title': node?.title ?? '',
      'session_title': session.title ?? '',
      'started_at': session.startedAt.toUtc().toIso8601String(),
      'ended_at': session.endedAt?.toUtc().toIso8601String(),
      'summary_text': session.summaryText ?? '',
      'control_state_json': session.controlStateJson ?? '',
      'control_state_updated_at':
          session.controlStateUpdatedAt?.toUtc().toIso8601String(),
      'evidence_state_json': session.evidenceStateJson ?? '',
      'evidence_state_updated_at':
          session.evidenceStateUpdatedAt?.toUtc().toIso8601String(),
      'student_remote_user_id': studentUserId,
      'student_username': studentUsername,
      'teacher_remote_user_id': teacherUserId,
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'messages': messages
          .map(
            (message) => {
              'role': message.role,
              'content': message.content,
              'raw_content': message.rawContent ?? '',
              'parsed_json': message.parsedJson ?? '',
              'action': message.action ?? '',
              'created_at': message.createdAt.toUtc().toIso8601String(),
            },
          )
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _prepareSessionUploadPayload({
    required User currentUser,
    required ChatSession syncSession,
    required int remoteCourseId,
    required CourseKeyBundle resolvedKeys,
    required DateTime syncUpdatedAt,
  }) async {
    if (_sessionUploadCacheService != null) {
      var cachedSnapshot = await _sessionUploadCacheService.readSession(
        sessionId: syncSession.id,
        syncUpdatedAt: syncUpdatedAt,
      );
      if (cachedSnapshot == null) {
        await _sessionUploadCacheService.captureSession(syncSession.id);
        cachedSnapshot = await _sessionUploadCacheService.readSession(
          sessionId: syncSession.id,
          syncUpdatedAt: syncUpdatedAt,
        );
      }
      if (cachedSnapshot == null) {
        throw StateError(
          'Session upload cache is missing for session ${syncSession.id}.',
        );
      }
      return _buildPayloadFromCache(
        snapshot: cachedSnapshot,
        remoteCourseId: remoteCourseId,
        teacherUserId: resolvedKeys.teacherUserId,
        studentUserId: resolvedKeys.studentUserId,
        studentUsername: currentUser.username,
      );
    }
    return _buildLiveSessionPayload(
      session: syncSession,
      remoteCourseId: remoteCourseId,
      teacherUserId: resolvedKeys.teacherUserId,
      studentUserId: resolvedKeys.studentUserId,
      studentUsername: currentUser.username,
      updatedAt: syncUpdatedAt,
    );
  }

  Future<Map<String, dynamic>> _buildLiveSessionPayload({
    required ChatSession session,
    required int remoteCourseId,
    required int teacherUserId,
    required int studentUserId,
    required String studentUsername,
    required DateTime updatedAt,
  }) async {
    final courseVersion =
        await _db.getCourseVersionById(session.courseVersionId);
    if (courseVersion == null) {
      throw StateError(
        'Course version ${session.courseVersionId} is missing for session '
        '${session.id}.',
      );
    }
    final node =
        await _db.getCourseNodeByKey(session.courseVersionId, session.kpKey);
    final messages = await _db.getMessagesForSession(session.id);
    return _buildPayload(
      session: session,
      courseVersion: courseVersion,
      node: node,
      messages: messages,
      remoteCourseId: remoteCourseId,
      teacherUserId: teacherUserId,
      studentUserId: studentUserId,
      studentUsername: studentUsername,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> _buildPayloadFromCache({
    required SessionUploadCacheSnapshot snapshot,
    required int remoteCourseId,
    required int teacherUserId,
    required int studentUserId,
    required String studentUsername,
  }) {
    return {
      'version': 1,
      'session_sync_id': snapshot.syncId,
      'course_id': remoteCourseId,
      'course_subject': snapshot.courseSubject,
      'kp_key': snapshot.kpKey,
      'kp_title': snapshot.kpTitle,
      'session_title': snapshot.sessionTitle,
      'started_at': snapshot.startedAt.toUtc().toIso8601String(),
      'ended_at': snapshot.endedAt?.toUtc().toIso8601String(),
      'summary_text': snapshot.summaryText,
      'control_state_json': snapshot.controlStateJson,
      'control_state_updated_at':
          snapshot.controlStateUpdatedAt?.toUtc().toIso8601String(),
      'evidence_state_json': snapshot.evidenceStateJson,
      'evidence_state_updated_at':
          snapshot.evidenceStateUpdatedAt?.toUtc().toIso8601String(),
      'student_remote_user_id': studentUserId,
      'student_username': studentUsername,
      'teacher_remote_user_id': teacherUserId,
      'updated_at': snapshot.syncUpdatedAt.toUtc().toIso8601String(),
      'messages': snapshot.messages
          .map(
            (message) => {
              'role': message.role,
              'content': message.content,
              'raw_content': message.rawContent ?? '',
              'parsed_json': message.parsedJson ?? '',
              'action': message.action ?? '',
              'created_at': message.createdAt.toUtc().toIso8601String(),
            },
          )
          .toList(growable: false),
    };
  }

  Map<String, dynamic> _buildProgressPayload({
    required ProgressEntry entry,
    required String courseSubject,
    required int remoteCourseId,
    required int teacherUserId,
    required int studentUserId,
  }) {
    return {
      'version': 1,
      'course_id': remoteCourseId,
      'course_subject': courseSubject,
      'kp_key': entry.kpKey,
      'lit': entry.lit,
      'lit_percent': entry.litPercent,
      'question_level': entry.questionLevel ?? '',
      'summary_text': entry.summaryText ?? '',
      'summary_raw_response': entry.summaryRawResponse ?? '',
      'summary_valid': entry.summaryValid,
      'teacher_remote_user_id': teacherUserId,
      'student_remote_user_id': studentUserId,
      'updated_at': entry.updatedAt.toUtc().toIso8601String(),
    };
  }

  String _hashProgressPayloadCore({
    required ProgressEntry entry,
    required int remoteCourseId,
    required int remoteUserId,
  }) {
    return _hashCanonicalJson(
      <String, Object?>{
        'course_id': remoteCourseId,
        'student_remote_user_id': remoteUserId,
        'kp_key': entry.kpKey,
        'lit': entry.lit,
        'lit_percent': entry.litPercent,
        'question_level': entry.questionLevel ?? '',
        'summary_text': entry.summaryText ?? '',
        'summary_raw_response': entry.summaryRawResponse ?? '',
        'summary_valid': entry.summaryValid,
        'updated_at': entry.updatedAt.toUtc().toIso8601String(),
      },
    );
  }

  String _hashProgressSyncItem(ProgressSyncItem item) {
    return _hashCanonicalJson(
      <String, Object?>{
        'course_id': item.courseId,
        'course_subject': item.courseSubject,
        'teacher_user_id': item.teacherUserId,
        'student_user_id': item.studentUserId,
        'kp_key': item.kpKey,
        'lit': item.lit,
        'lit_percent': item.litPercent,
        'question_level': item.questionLevel,
        'summary_text': item.summaryText,
        'summary_raw_response': item.summaryRawResponse,
        'summary_valid': item.summaryValid,
        'updated_at': item.updatedAt,
      },
    );
  }

  String _hashResolvedProgress(_ResolvedProgressPayload payload) {
    return _hashCanonicalJson(
      <String, Object?>{
        'course_id': payload.courseId,
        'course_subject': payload.courseSubject,
        'kp_key': payload.kpKey,
        'lit': payload.lit,
        'lit_percent': payload.litPercent,
        'question_level': payload.questionLevel,
        'summary_text': payload.summaryText,
        'summary_raw_response': payload.summaryRawResponse,
        'summary_valid': payload.summaryValid,
        'updated_at': payload.updatedAt,
      },
    );
  }

  String _hashSessionUploadGroup(List<_PendingSessionUpload> groupItems) {
    final fingerprints = groupItems
        .map(
          (item) =>
              '${item.syncId}|${item.syncUpdatedAt.toUtc().toIso8601String()}',
        )
        .toList()
      ..sort();
    return _hashEnvelope(fingerprints.join('\n'));
  }

  String _extractSecondLevelChapter(String kpKey) {
    final trimmed = kpKey.trim();
    if (trimmed.isEmpty || trimmed == kTreeViewStateKpKey) {
      return 'ungrouped';
    }
    final match = _secondLevelChapterPattern.firstMatch(trimmed);
    if (match != null) {
      final value = match.group(1);
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    final parts = trimmed.split('.');
    if (parts.length >= 2) {
      final first = parts[0].trim();
      final second = parts[1].trim();
      if (int.tryParse(first) != null && int.tryParse(second) != null) {
        return '$first.$second';
      }
    }
    return trimmed;
  }

  String _hashCanonicalJson(Map<String, Object?> payload) {
    return _hashEnvelope(jsonEncode(payload));
  }

  Future<void> _writeSyncListEtag({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
    required String? etag,
  }) async {
    final normalized = (etag ?? '').trim();
    if (normalized.isEmpty) {
      return;
    }
    await _secureStorage.writeSyncListEtag(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
      etag: normalized,
    );
  }

  String _resolveSyncHash({
    required String primaryHash,
    required String fallbackValue,
  }) {
    final trimmedPrimary = primaryHash.trim();
    if (trimmedPrimary.isNotEmpty) {
      return trimmedPrimary;
    }
    final trimmedFallback = fallbackValue.trim();
    if (trimmedFallback.isEmpty) {
      return '';
    }
    return _hashEnvelope(trimmedFallback);
  }

  bool _isTimestampNewer(DateTime candidate, DateTime? baseline) {
    if (baseline == null) {
      return true;
    }
    return candidate.isAfter(baseline.toUtc());
  }

  DateTime _latestTimestamp(DateTime? current, DateTime candidate) {
    if (current == null) {
      return candidate;
    }
    return candidate.isAfter(current) ? candidate : current;
  }

  Future<_ResolvedProgressPayload> _resolveProgressPayload({
    required ProgressSyncItem item,
    required int remoteUserId,
    required SimpleKeyPair keyPair,
  }) async {
    if (item.studentUserId <= 0) {
      throw StateError('Progress payload student mismatch.');
    }
    if (item.envelope.trim().isEmpty) {
      final kpKey = item.kpKey.trim();
      if (item.courseId <= 0 || kpKey.isEmpty) {
        throw StateError('Progress payload missing course_id or kp_key.');
      }
      return _ResolvedProgressPayload(
        courseId: item.courseId,
        courseSubject: item.courseSubject,
        kpKey: kpKey,
        lit: item.lit,
        litPercent: item.litPercent.clamp(0, 100).toInt(),
        questionLevel: item.questionLevel,
        summaryText: item.summaryText,
        summaryRawResponse: item.summaryRawResponse,
        summaryValid: item.summaryValid,
        updatedAt: item.updatedAt,
      );
    }

    final envelopeJson = utf8.decode(base64Decode(item.envelope));
    if (item.envelopeHash.trim().isNotEmpty) {
      final computed = _hashEnvelope(envelopeJson);
      if (computed != item.envelopeHash.trim()) {
        throw StateError('Progress sync envelope hash mismatch.');
      }
    }
    final decoded = jsonDecode(envelopeJson);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Progress sync envelope invalid.');
    }
    final envelope = EncryptedEnvelope.fromJson(decoded);
    final payload = await _crypto.decryptEnvelope(
      envelope: envelope,
      userKeyPair: keyPair,
      userId: remoteUserId,
    );

    final payloadStudentID = _parsePayloadInt(
      payload['student_remote_user_id'],
      field: 'student_remote_user_id',
    );
    if (payloadStudentID != item.studentUserId) {
      throw StateError('Progress payload student mismatch.');
    }
    final litPercentRaw = _parsePayloadInt(
      payload['lit_percent'],
      field: 'lit_percent',
    );
    final payloadCourseSubject = _parsePayloadString(
      payload['course_subject'],
      field: 'course_subject',
      isRequired: false,
    ).trim();
    return _ResolvedProgressPayload(
      courseId: _parsePayloadInt(payload['course_id'], field: 'course_id'),
      courseSubject: payloadCourseSubject.isNotEmpty
          ? payloadCourseSubject
          : item.courseSubject.trim(),
      kpKey: _parsePayloadString(payload['kp_key'], field: 'kp_key').trim(),
      lit: _parsePayloadBool(payload['lit'], field: 'lit'),
      litPercent: litPercentRaw.clamp(0, 100).toInt(),
      questionLevel: _parsePayloadString(payload['question_level'],
          field: 'question_level'),
      summaryText:
          _parsePayloadString(payload['summary_text'], field: 'summary_text'),
      summaryRawResponse: _parsePayloadString(
        payload['summary_raw_response'],
        field: 'summary_raw_response',
      ),
      summaryValid: _parsePayloadNullableBool(
        payload['summary_valid'],
        field: 'summary_valid',
      ),
      updatedAt:
          _parsePayloadString(payload['updated_at'], field: 'updated_at'),
    );
  }

  Future<ChatSession> _ensureSessionSyncMeta(ChatSession session) async {
    var syncId = session.syncId;
    var updatedAt = session.syncUpdatedAt;
    if (syncId == null || syncId.trim().isEmpty) {
      syncId = _uuid.v4();
    }
    if (updatedAt == null) {
      updatedAt = session.startedAt;
    }
    if (syncId != session.syncId || updatedAt != session.syncUpdatedAt) {
      await (_db.update(_db.chatSessions)
            ..where((tbl) => tbl.id.equals(session.id)))
          .write(
        ChatSessionsCompanion(
          syncId: Value(syncId),
          syncUpdatedAt: Value(updatedAt),
        ),
      );
      final refreshed = await _db.getSession(session.id);
      if (refreshed != null) {
        return refreshed;
      }
    }
    return session;
  }

  Future<void> _markSessionUploaded({
    required int sessionId,
    required DateTime uploadedAt,
  }) {
    final normalized = uploadedAt.toUtc();
    return (_db.update(_db.chatSessions)
          ..where((tbl) => tbl.id.equals(sessionId)))
        .write(
      ChatSessionsCompanion(
        syncUploadedAt: Value(normalized),
      ),
    );
  }

  int _requireRemoteUserId(User user) {
    final remoteId = user.remoteUserId;
    if (remoteId == null || remoteId <= 0) {
      throw StateError('Remote user id missing.');
    }
    return remoteId;
  }

  String _hashEnvelope(String json) {
    final sum = sha256.convert(utf8.encode(json));
    return sum.toString();
  }

  int _parsePayloadInt(
    Object? value, {
    required String field,
  }) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
    throw StateError('Progress payload field "$field" invalid.');
  }

  bool _parsePayloadBool(
    Object? value, {
    required String field,
  }) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      if (value == 1) {
        return true;
      }
      if (value == 0) {
        return false;
      }
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    throw StateError('Progress payload field "$field" invalid.');
  }

  bool? _parsePayloadNullableBool(
    Object? value, {
    required String field,
  }) {
    if (value == null) {
      return null;
    }
    return _parsePayloadBool(value, field: field);
  }

  String _parsePayloadString(
    Object? value, {
    required String field,
    bool isRequired = true,
  }) {
    if (value is String) {
      return value;
    }
    if (!isRequired && value == null) {
      return '';
    }
    throw StateError('Progress payload field "$field" invalid.');
  }

  Future<String> _resolveCourseSubject(int courseVersionId) async {
    final course = await (_db.select(_db.courseVersions)
          ..where((tbl) => tbl.id.equals(courseVersionId)))
        .getSingleOrNull();
    if (course == null) {
      return '';
    }
    return course.subject.trim();
  }

  Future<int?> _findLocalCourseVersionBySubject({
    required int teacherId,
    required String subject,
  }) async {
    final normalizedTarget = _normalizeCourseName(_stripVersionSuffix(subject));
    if (normalizedTarget.isEmpty) {
      return null;
    }
    final courses = await _db.getCourseVersionsForTeacher(teacherId);
    for (final course in courses) {
      final normalizedCourse =
          _normalizeCourseName(_stripVersionSuffix(course.subject));
      if (normalizedCourse == normalizedTarget) {
        return course.id;
      }
    }
    return null;
  }

  Future<int?> _findAssignedCourseVersionBySubject({
    required int studentId,
    required String subject,
  }) async {
    final normalizedTarget = _normalizeCourseName(_stripVersionSuffix(subject));
    if (normalizedTarget.isEmpty) {
      return null;
    }
    final assignedCourses = await _db.getAssignedCoursesForStudent(studentId);
    for (final course in assignedCourses) {
      final normalizedCourse =
          _normalizeCourseName(_stripVersionSuffix(course.subject));
      if (normalizedCourse == normalizedTarget) {
        return course.id;
      }
    }
    return null;
  }

  Future<void> _ensureCourseTeacher({
    required int courseVersionId,
    required int expectedTeacherId,
  }) async {
    final existing = await _db.getCourseVersionById(courseVersionId);
    if (existing == null || existing.teacherId == expectedTeacherId) {
      return;
    }
    await _db.updateCourseVersionTeacherId(
      id: courseVersionId,
      teacherId: expectedTeacherId,
    );
  }

  Future<void> _bindRemoteCourseLinkIfNeeded({
    required int courseVersionId,
    required int remoteCourseId,
  }) async {
    final existingRemoteCourseId = await _db.getRemoteCourseId(courseVersionId);
    if (existingRemoteCourseId == null ||
        existingRemoteCourseId <= 0 ||
        existingRemoteCourseId == remoteCourseId) {
      await _db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: remoteCourseId,
      );
    }
  }

  Future<void> _ensureCourseSubject({
    required int courseVersionId,
    required String expectedSubject,
  }) async {
    final normalizedExpected = expectedSubject.trim();
    if (normalizedExpected.isEmpty) {
      return;
    }
    final course = await _db.getCourseVersionById(courseVersionId);
    if (course == null) {
      return;
    }
    if (course.subject.trim() == normalizedExpected) {
      return;
    }
    await _db.updateCourseVersionSubject(
      id: courseVersionId,
      subject: normalizedExpected,
    );
  }

  String _normalizeCourseName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _stripVersionSuffix(String value) {
    return value.trim().replaceFirst(_versionSuffixPattern, '');
  }
}

class _SyncMessage {
  _SyncMessage({
    required this.role,
    required this.content,
    required this.rawContent,
    required this.parsedJson,
    required this.action,
    required this.createdAt,
  });

  final String role;
  final String content;
  final String? rawContent;
  final String? parsedJson;
  final String? action;
  final DateTime createdAt;
}

class _ResolvedProgressPayload {
  _ResolvedProgressPayload({
    required this.courseId,
    required this.courseSubject,
    required this.kpKey,
    required this.lit,
    required this.litPercent,
    required this.questionLevel,
    required this.summaryText,
    required this.summaryRawResponse,
    required this.summaryValid,
    required this.updatedAt,
  });

  final int courseId;
  final String courseSubject;
  final String kpKey;
  final bool lit;
  final int litPercent;
  final String questionLevel;
  final String summaryText;
  final String summaryRawResponse;
  final bool? summaryValid;
  final String updatedAt;
}

class _PendingSessionUpload {
  _PendingSessionUpload({
    required this.session,
    required this.syncId,
    required this.syncUpdatedAt,
    required this.remoteCourseId,
  });

  final ChatSession session;
  final String syncId;
  final DateTime syncUpdatedAt;
  final int remoteCourseId;
}

class _ProgressChunkGroup {
  _ProgressChunkGroup({
    required this.scopeKey,
    required this.remoteCourseId,
    required this.chapterKey,
    required this.courseVersionId,
    required this.studentId,
  });

  final String scopeKey;
  final int remoteCourseId;
  final String chapterKey;
  final int courseVersionId;
  final int studentId;
  final List<_ProgressChunkMember> members = <_ProgressChunkMember>[];
  bool hasPendingChanges = false;
  bool blockedByRemoteNewer = false;
}

class _ProgressChunkMember {
  _ProgressChunkMember({
    required this.entry,
    required this.scopeKey,
    required this.updatedAt,
    required this.payloadHash,
  });

  final ProgressEntry entry;
  final String scopeKey;
  final DateTime updatedAt;
  final String payloadHash;
}

class _PendingProgressUpload {
  _PendingProgressUpload({
    required this.upload,
    required this.stateWrite,
  });

  final ProgressUploadEntry upload;
  final _SyncStateWrite stateWrite;
}

class _PreparedProgressChunkUpload {
  _PreparedProgressChunkUpload({
    required this.upload,
    required this.itemStateWrites,
    required this.groupStateWrite,
  });

  final ProgressChunkUploadEntry upload;
  final List<_SyncStateWrite> itemStateWrites;
  final _SyncStateWrite groupStateWrite;
}

class _PreparedSessionUpload {
  _PreparedSessionUpload({
    required this.sessionId,
    required this.syncUpdatedAt,
    required this.syncStateWrite,
  });

  final int sessionId;
  final DateTime syncUpdatedAt;
  final _SyncStateWrite syncStateWrite;
}

class _FailedProgressUpload {
  _FailedProgressUpload({
    required this.upload,
    required this.error,
  });

  final ProgressUploadEntry upload;
  final SessionSyncApiException error;
}

class _ProgressIsolationBudget {
  _ProgressIsolationBudget({
    required this.remaining,
  });

  int remaining;
}

class _SyncStateWrite {
  _SyncStateWrite({
    required this.domain,
    required this.scopeKey,
    required this.contentHash,
    required this.lastChangedAt,
    required this.lastSyncedAt,
  });

  final String domain;
  final String scopeKey;
  final String contentHash;
  final DateTime lastChangedAt;
  final DateTime lastSyncedAt;
}
