import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../constants.dart';
import '../db/app_database.dart';
import 'artifact_sync_api_service.dart';
import 'remote_student_identity_service.dart';
import 'student_kp_artifact_store_service.dart';
import 'sync_log_repository.dart';
import 'sync_progress.dart';

enum SessionSyncMode {
  full,
  downloadOnly,
  uploadOnly,
}

class SessionSyncService {
  SessionSyncService({
    required AppDatabase db,
    required ArtifactSyncApiService api,
    StudentKpArtifactStoreService? artifactStore,
  })  : _db = db,
        _api = api,
        _artifactStore = artifactStore ?? StudentKpArtifactStoreService();

  final AppDatabase _db;
  final ArtifactSyncApiService _api;
  final StudentKpArtifactStoreService _artifactStore;
  final RemoteStudentIdentityService _remoteStudentIdentity =
      const RemoteStudentIdentityService();

  bool _syncing = false;
  bool _cutoverInitialized = false;
  int _localMutationSuppressionDepth = 0;
  final Set<int> _pendingRefreshLocalUserIds = <int>{};

  static const String _artifactClass = 'student_kp';
  static const String _artifactSchema = 'student_kp_artifact_v1';
  static const int _batchDownloadThreshold = 3;
  static const int _batchUploadThreshold = 3;
  static const int _batchUploadChunkSize = 16;
  static const int _downloadApplyCheckpointInterval = 64;

  bool get _localMutationSuppressed => _localMutationSuppressionDepth > 0;

  Future<T> _runWithLocalMutationSuppressed<T>(
    Future<T> Function() action,
  ) async {
    _localMutationSuppressionDepth++;
    try {
      return await action();
    } finally {
      _localMutationSuppressionDepth--;
    }
  }

  Future<void> ensureLocalCutoverInitialized() async {
    if (_cutoverInitialized) {
      return;
    }
    final initialized = await _artifactStore.isCutoverInitialized();
    if (!initialized) {
      await _runWithLocalMutationSuppressed(() async {
        await _clearLegacyLocalState();
        await _artifactStore.clearAllArtifacts();
        await _artifactStore.markCutoverInitialized();
      });
    }
    _cutoverInitialized = true;
  }

  Future<void> handleLocalSyncRelevantChange(SyncRelevantChange change) async {
    if (_localMutationSuppressed ||
        change.isEmpty ||
        !change.refreshSessionArtifacts) {
      return;
    }
    await ensureLocalCutoverInitialized();
    final pendingStudents = <User>[];
    final seenRemoteUserIds = <int>{};
    for (final localUserId in change.localUserIds) {
      final user = await _db.getUserById(localUserId);
      final remoteUserId = user?.remoteUserId;
      if (user == null ||
          user.role != 'student' ||
          remoteUserId == null ||
          remoteUserId <= 0) {
        continue;
      }
      if (!seenRemoteUserIds.add(remoteUserId)) {
        continue;
      }
      pendingStudents.add(user);
    }
    if (_syncing) {
      for (final student in pendingStudents) {
        _pendingRefreshLocalUserIds.add(student.id);
      }
      return;
    }
    for (final student in pendingStudents) {
      await _refreshLocalArtifactsForStudent(student);
    }
  }

  Future<void> prepareForAutoSync({
    required User currentUser,
    required String password,
  }) async {
    await ensureLocalCutoverInitialized();
  }

  Future<SyncRunStats> syncNow({
    required User currentUser,
    required String password,
    SyncProgressCallback? onProgress,
    SessionSyncMode mode = SessionSyncMode.full,
  }) {
    return _syncInternal(
      currentUser: currentUser,
      force: true,
      onProgress: onProgress,
      mode: mode,
    );
  }

  Future<SyncRunStats> syncIfReady({
    required User currentUser,
    SyncProgressCallback? onProgress,
    SessionSyncMode mode = SessionSyncMode.full,
  }) {
    return _syncInternal(
      currentUser: currentUser,
      force: false,
      onProgress: onProgress,
      mode: mode,
    );
  }

  Future<SyncRunStats> forcePullFromServer({
    required User currentUser,
    bool wipeLocalStudentData = true,
    SyncProgressCallback? onProgress,
    SessionSyncMode mode = SessionSyncMode.full,
  }) async {
    await ensureLocalCutoverInitialized();
    final remoteUserId = _requireRemoteUserId(currentUser);
    if (currentUser.role == 'student' && wipeLocalStudentData) {
      await _runWithLocalMutationSuppressed(() async {
        await _clearLocalStudentSessionAndProgressData(
          studentId: currentUser.id,
        );
      });
    }
    await _artifactStore.clearUserArtifacts(remoteUserId);
    return _syncInternal(
      currentUser: currentUser,
      force: true,
      onProgress: onProgress,
      mode: mode,
    );
  }

  Future<Map<String, String>> buildCanonicalVisibleArtifactHashes({
    required User currentUser,
  }) async {
    final remoteUserId = currentUser.remoteUserId;
    if (remoteUserId == null || remoteUserId <= 0) {
      return const <String, String>{};
    }
    await ensureLocalCutoverInitialized();
    final manifest = await _artifactStore.loadManifest(remoteUserId);
    final artifactHashesById = <String, String>{};
    for (final item in manifest.items.values) {
      if (item.deleted) {
        continue;
      }
      final artifactId = item.artifactId.trim();
      final sha256 = item.sha256.trim();
      if (artifactId.isEmpty || sha256.isEmpty) {
        continue;
      }
      artifactHashesById[artifactId] = sha256;
    }
    return artifactHashesById;
  }

  Future<SyncRunStats> syncFromCanonicalState1({
    required User currentUser,
    required List<ArtifactState1Item> visibleItems,
    SyncProgressCallback? onProgress,
    SessionSyncMode mode = SessionSyncMode.downloadOnly,
  }) async {
    final stats = SyncRunStats();
    if (_syncing) {
      return stats;
    }
    final remoteUserId = currentUser.remoteUserId;
    if (remoteUserId == null || remoteUserId <= 0) {
      return stats;
    }
    await ensureLocalCutoverInitialized();
    _syncing = true;
    try {
      final serverItems = visibleItems
          .where((item) => item.artifactClass == _artifactClass)
          .toList(growable: false)
        ..sort((left, right) => left.artifactId.compareTo(right.artifactId));
      var manifest = await _artifactStore.loadManifest(remoteUserId);
      manifest = await _removeResolvedDeletedEntries(
        currentUser: currentUser,
        manifest: manifest,
        serverItems: serverItems,
      );
      if (currentUser.role == 'teacher') {
        await _reportProgress(
          onProgress,
          const SyncProgress(
            message: 'Refreshing teacher student artifact metadata...',
            forcePaint: true,
          ),
        );
        manifest = await _reconcileTeacherManifestMetadata(
          currentUser: currentUser,
          remoteUserId: remoteUserId,
          manifest: manifest,
          serverItems: serverItems,
        );
      } else {
        await _reportProgress(
          onProgress,
          const SyncProgress(
            message: 'Syncing student per-KP artifacts...',
            forcePaint: true,
          ),
        );
        manifest = await _applyServerDownloads(
          currentUser: currentUser,
          remoteUserId: remoteUserId,
          manifest: manifest,
          serverItems: serverItems,
          stats: stats,
          onProgress: onProgress,
        );
        if (mode == SessionSyncMode.full) {
          manifest = await _uploadLocalChanges(
            currentUser: currentUser,
            remoteUserId: remoteUserId,
            manifest: manifest,
            serverItems: serverItems,
            stats: stats,
            onProgress: onProgress,
          );
          final refreshedState1 = await _api.getState1(
            artifactClass: _artifactClass,
          );
          manifest = await _applyServerDownloads(
            currentUser: currentUser,
            remoteUserId: remoteUserId,
            manifest: manifest,
            serverItems: refreshedState1.items,
            stats: stats,
            onProgress: onProgress,
          );
          await _assertNoPendingArtifactConflicts(
            currentUser: currentUser,
            manifest: manifest,
            serverItems: refreshedState1.items,
          );
        }
      }
      await _artifactStore.saveManifest(manifest);
      return stats;
    } finally {
      _syncing = false;
      await _drainPendingRefreshes();
    }
  }

  Future<void> materializeTeacherArtifactsForView({
    required User currentUser,
    required int localStudentId,
    int? courseVersionId,
  }) async {
    if (currentUser.role != 'teacher') {
      return;
    }
    final remoteTeacherUserId = _requireRemoteUserId(currentUser);
    final student = await _db.getUserById(localStudentId);
    final remoteStudentUserId = student?.remoteUserId;
    if (student == null ||
        student.role != 'student' ||
        remoteStudentUserId == null ||
        remoteStudentUserId <= 0) {
      throw StateError(
        'Teacher artifact materialization requires a synced local student.',
      );
    }
    int? remoteCourseId;
    if (courseVersionId != null) {
      remoteCourseId =
          await _db.getRemoteCourseIdForCourseVersion(courseVersionId);
      if (remoteCourseId == null || remoteCourseId <= 0) {
        throw StateError(
          'Course version $courseVersionId is missing its remote course link.',
        );
      }
    }
    await _syncTeacherArtifactsForView(
      currentUser: currentUser,
      remoteTeacherUserId: remoteTeacherUserId,
      remoteStudentUserId: remoteStudentUserId,
      remoteCourseId: remoteCourseId,
    );
    final manifest = await _artifactStore.loadManifest(remoteTeacherUserId);
    final matchingItems = manifest.items.values.where((item) {
      if (item.deleted) {
        return false;
      }
      final identity = _parseArtifactIdentity(item.artifactId, null);
      if (identity.remoteStudentUserId != remoteStudentUserId) {
        return false;
      }
      if (remoteCourseId != null && identity.remoteCourseId != remoteCourseId) {
        return false;
      }
      return true;
    }).toList(growable: false)
      ..sort((left, right) => left.artifactId.compareTo(right.artifactId));
    if (matchingItems.isEmpty) {
      return;
    }
    final bytesByArtifactId = await _ensureTeacherArtifactBytesAvailable(
      currentUser: currentUser,
      remoteTeacherUserId: remoteTeacherUserId,
      manifest: manifest,
      items: matchingItems,
    );
    final applyContext = _ArtifactApplyContext(
      initialManifest: manifest,
    );
    await _runWithLocalMutationSuppressed(() async {
      await _db.transaction(() async {
        for (final item in matchingItems) {
          final bytes = bytesByArtifactId[item.artifactId];
          if (bytes == null) {
            throw StateError(
              'Stored teacher artifact bytes missing for ${item.artifactId}.',
            );
          }
          final payload = _artifactStore.readPayload(bytes);
          await _applyRemoteArtifactPayload(
            currentUser: currentUser,
            artifactId: item.artifactId,
            payload: payload,
            applyContext: applyContext,
            replaceExistingLocalScope: true,
            wrapReplaceTransaction: false,
          );
        }
      });
    });
  }

  Future<void> _syncTeacherArtifactsForView({
    required User currentUser,
    required int remoteTeacherUserId,
    required int remoteStudentUserId,
    required int? remoteCourseId,
  }) async {
    final manifest = await _artifactStore.loadManifest(remoteTeacherUserId);
    final matchingLocalItems = manifest.items.values.where((item) {
      return _artifactMatchesTeacherViewScope(
        item.artifactId,
        remoteStudentUserId: remoteStudentUserId,
        remoteCourseId: remoteCourseId,
      );
    }).toList(growable: false)
      ..sort((left, right) => left.artifactId.compareTo(right.artifactId));
    final serverState1 = await _api.getState1(
      artifactClass: _artifactClass,
      studentUserId: remoteStudentUserId,
      courseId: remoteCourseId,
    );
    final serverArtifactIds = serverState1.items
        .map((item) => item.artifactId.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (matchingLocalItems.isNotEmpty) {
      final staleLocalItems = matchingLocalItems
          .where((item) => !serverArtifactIds.contains(item.artifactId))
          .toList(growable: false);
      if (staleLocalItems.isNotEmpty) {
        await _runWithLocalMutationSuppressed(() async {
          await _db.transaction(() async {
            for (final item in staleLocalItems) {
              await _deleteLocalArtifactScopeById(
                currentUser: currentUser,
                artifactId: item.artifactId,
              );
            }
          });
        });
        final updatedItems =
            Map<String, StudentKpArtifactManifestItem>.from(manifest.items);
        for (final item in staleLocalItems) {
          await _artifactStore.deleteArtifactFile(
            remoteUserId: remoteTeacherUserId,
            storageFile: item.storageFile,
          );
          updatedItems.remove(item.artifactId);
        }
        await _artifactStore
            .saveManifest(manifest.copyWith(items: updatedItems));
      }
    }
    if (serverState1.items.isEmpty) {
      return;
    }
    await _applyServerDownloads(
      currentUser: currentUser,
      remoteUserId: remoteTeacherUserId,
      manifest: await _artifactStore.loadManifest(remoteTeacherUserId),
      serverItems: serverState1.items,
      stats: SyncRunStats(),
      onProgress: null,
      removeMissingLocalArtifacts: false,
    );
  }

  bool _artifactMatchesTeacherViewScope(
    String artifactId, {
    required int remoteStudentUserId,
    required int? remoteCourseId,
  }) {
    final identity = _parseArtifactIdentity(artifactId, null);
    if (identity.remoteStudentUserId != remoteStudentUserId) {
      return false;
    }
    if (remoteCourseId != null && identity.remoteCourseId != remoteCourseId) {
      return false;
    }
    return true;
  }

  Future<Map<String, Uint8List>> _ensureTeacherArtifactBytesAvailable({
    required User currentUser,
    required int remoteTeacherUserId,
    required StudentKpArtifactManifest manifest,
    required List<StudentKpArtifactManifestItem> items,
  }) async {
    var bytesByArtifactId = await _artifactStore.readPackedArtifactBytes(
      remoteUserId: remoteTeacherUserId,
      items: items.where((item) => item.storageFile.trim().isNotEmpty),
    );
    final missingItems = items.where((item) {
      return item.storageFile.trim().isEmpty ||
          !bytesByArtifactId.containsKey(item.artifactId);
    }).toList(growable: false);
    if (missingItems.isEmpty) {
      return bytesByArtifactId;
    }

    final downloadedItems = missingItems.length > _batchDownloadThreshold
        ? await _api.downloadArtifactBatch(
            missingItems.map((item) => item.artifactId).toList(growable: false),
          )
        : <DownloadedArtifact>[
            for (final item in missingItems)
              await _api.downloadArtifact(item.artifactId),
          ];
    final downloadedByArtifactId = <String, DownloadedArtifact>{
      for (final item in downloadedItems) item.artifactId.trim(): item,
    };
    Map<String, String> storageRefs = const <String, String>{};
    if (downloadedItems.length > _batchDownloadThreshold) {
      storageRefs = await _artifactStore.writeArtifactPack(
        remoteUserId: remoteTeacherUserId,
        bytesByArtifactId: <String, Uint8List>{
          for (final item in downloadedItems)
            item.artifactId.trim(): item.bytes,
        },
      );
    }
    final nextItems =
        Map<String, StudentKpArtifactManifestItem>.from(manifest.items);
    for (final item in missingItems) {
      final downloaded = downloadedByArtifactId[item.artifactId];
      if (downloaded == null) {
        throw StateError(
          'Teacher artifact materialization download missing ${item.artifactId}.',
        );
      }
      final storageFile = downloadedItems.length > _batchDownloadThreshold
          ? storageRefs[item.artifactId]
          : _artifactStore.storageFileNameForArtifact(item.artifactId);
      if ((storageFile ?? '').trim().isEmpty) {
        throw StateError(
          'Teacher artifact storage reference missing for ${item.artifactId}.',
        );
      }
      if (downloadedItems.length <= _batchDownloadThreshold) {
        await _artifactStore.writeArtifactBytes(
          remoteUserId: remoteTeacherUserId,
          storageFile: storageFile!,
          bytes: downloaded.bytes,
        );
      }
      nextItems[item.artifactId] = item.copyWith(
        storageFile: storageFile,
      );
      bytesByArtifactId[item.artifactId] = downloaded.bytes;
    }
    await _artifactStore.saveManifest(
      manifest.copyWith(items: nextItems),
    );
    return bytesByArtifactId;
  }

  Future<SyncRunStats> _syncInternal({
    required User currentUser,
    required bool force,
    required SyncProgressCallback? onProgress,
    SessionSyncMode mode = SessionSyncMode.full,
  }) async {
    final stats = SyncRunStats();
    if (_syncing) {
      return stats;
    }
    final remoteUserId = currentUser.remoteUserId;
    if (remoteUserId == null || remoteUserId <= 0) {
      return stats;
    }
    await ensureLocalCutoverInitialized();
    _syncing = true;
    Object? syncError;
    StackTrace? syncStackTrace;
    try {
      final initialManifest = await _artifactStore.loadManifest(remoteUserId);
      if (mode == SessionSyncMode.uploadOnly) {
        if (currentUser.role == 'student') {
          await _reportProgress(
            onProgress,
            const SyncProgress(
              message: 'Syncing student artifacts (upload only)...',
              forcePaint: true,
            ),
          );
          final serverState1 = await _api.getState1(
            artifactClass: _artifactClass,
          );
          await _uploadLocalChanges(
            currentUser: currentUser,
            remoteUserId: remoteUserId,
            manifest: initialManifest,
            serverItems: serverState1.items,
            stats: stats,
            onProgress: onProgress,
          );
        }
        return stats;
      }

      if (!force) {
        await _reportProgress(
          onProgress,
          const SyncProgress(
            message: 'Checking student artifacts...',
            forcePaint: true,
          ),
        );
        final remoteState2 =
            await _api.getState2(artifactClass: _artifactClass);
        if (remoteState2.trim().isNotEmpty &&
            remoteState2.trim() == initialManifest.state2.trim()) {
          return stats;
        }
      }

      await _reportProgress(
        onProgress,
        const SyncProgress(
          message: 'Syncing student per-KP artifacts...',
          forcePaint: true,
        ),
      );

      var manifest = initialManifest;
      var serverState1 = await _api.getState1(artifactClass: _artifactClass);

      manifest = await _removeResolvedDeletedEntries(
        currentUser: currentUser,
        manifest: manifest,
        serverItems: serverState1.items,
      );
      manifest = await _applyServerDownloads(
        currentUser: currentUser,
        remoteUserId: remoteUserId,
        manifest: manifest,
        serverItems: serverState1.items,
        stats: stats,
        onProgress: onProgress,
      );

      if (currentUser.role == 'student' && mode == SessionSyncMode.full) {
        manifest = await _uploadLocalChanges(
          currentUser: currentUser,
          remoteUserId: remoteUserId,
          manifest: manifest,
          serverItems: serverState1.items,
          stats: stats,
          onProgress: onProgress,
        );
      }

      if (currentUser.role == 'student' && mode == SessionSyncMode.full) {
        serverState1 = await _api.getState1(artifactClass: _artifactClass);
        manifest = await _applyServerDownloads(
          currentUser: currentUser,
          remoteUserId: remoteUserId,
          manifest: manifest,
          serverItems: serverState1.items,
          stats: stats,
          onProgress: onProgress,
        );
      }

      if (currentUser.role == 'teacher' || mode == SessionSyncMode.full) {
        await _assertNoPendingArtifactConflicts(
          currentUser: currentUser,
          manifest: manifest,
          serverItems: serverState1.items,
        );
      }
      await _artifactStore.saveManifest(manifest);
    } catch (error, stackTrace) {
      syncError = error;
      syncStackTrace = stackTrace;
    } finally {
      _syncing = false;
      await _drainPendingRefreshes();
    }
    if (syncError != null) {
      Error.throwWithStackTrace(syncError, syncStackTrace!);
    }
    return stats;
  }

  Future<void> _drainPendingRefreshes() async {
    while (_pendingRefreshLocalUserIds.isNotEmpty) {
      final pendingIds = _pendingRefreshLocalUserIds.toList(growable: false);
      _pendingRefreshLocalUserIds.clear();
      final seenRemoteUserIds = <int>{};
      for (final localUserId in pendingIds) {
        final user = await _db.getUserById(localUserId);
        final remoteUserId = user?.remoteUserId;
        if (user == null ||
            user.role != 'student' ||
            remoteUserId == null ||
            remoteUserId <= 0) {
          continue;
        }
        if (!seenRemoteUserIds.add(remoteUserId)) {
          continue;
        }
        await _refreshLocalArtifactsForStudent(user);
      }
    }
  }

  Future<StudentKpArtifactManifest> _removeResolvedDeletedEntries({
    required User currentUser,
    required StudentKpArtifactManifest manifest,
    required List<ArtifactState1Item> serverItems,
  }) async {
    final serverIds = serverItems
        .map((item) => item.artifactId.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    var changed = false;
    final nextItems = <String, StudentKpArtifactManifestItem>{};
    for (final entry in manifest.items.entries) {
      final item = entry.value;
      if (item.deleted && !serverIds.contains(entry.key)) {
        changed = true;
        continue;
      }
      nextItems[entry.key] = item;
    }
    if (!changed) {
      return manifest;
    }
    final updated = manifest.copyWith(items: nextItems);
    await _artifactStore.saveManifest(updated);
    return await _artifactStore.loadManifest(manifest.remoteUserId);
  }

  Future<StudentKpArtifactManifest> _applyServerDownloads({
    required User currentUser,
    required int remoteUserId,
    required StudentKpArtifactManifest manifest,
    required List<ArtifactState1Item> serverItems,
    required SyncRunStats stats,
    required SyncProgressCallback? onProgress,
    bool removeMissingLocalArtifacts = true,
  }) async {
    final serverById = <String, ArtifactState1Item>{
      for (final item in serverItems)
        if (item.artifactId.trim().isNotEmpty) item.artifactId.trim(): item,
    };
    final downloadCandidates = <ArtifactState1Item>[];
    for (final serverItem in serverItems) {
      final localItem = manifest.items[serverItem.artifactId];
      if (_shouldDownloadServerArtifact(
        currentUser: currentUser,
        localItem: localItem,
        serverItem: serverItem,
      )) {
        downloadCandidates.add(serverItem);
      }
    }
    if (downloadCandidates.isEmpty) {
      return manifest;
    }

    var currentManifest = manifest;
    var completedCount = 0;
    var completedBytes = 0;
    if (downloadCandidates.length > _batchDownloadThreshold) {
      final downloadedItems = await _api.downloadArtifactBatch(
        downloadCandidates
            .map((candidate) => candidate.artifactId)
            .toList(growable: false),
      );
      final downloadedById = <String, DownloadedArtifact>{
        for (final item in downloadedItems) item.artifactId.trim(): item,
      };
      final downloads = downloadCandidates.map((candidate) {
        final downloaded = downloadedById[candidate.artifactId];
        if (downloaded == null) {
          throw StateError(
            'Downloaded artifact batch is missing ${candidate.artifactId}.',
          );
        }
        return _DownloadedArtifactCandidate(
          candidate: candidate,
          downloaded: downloaded,
        );
      }).toList(growable: false);
      final storageFileOverrides =
          currentUser.role == 'teacher' || currentUser.role == 'student'
              ? await _artifactStore.writeArtifactPack(
                  remoteUserId: remoteUserId,
                  bytesByArtifactId: <String, Uint8List>{
                    for (final entry in downloads)
                      entry.candidate.artifactId: entry.downloaded.bytes,
                  },
                )
              : null;
      currentManifest = await _applyDownloadedArtifactInChunks(
        currentUser: currentUser,
        remoteUserId: remoteUserId,
        manifest: currentManifest,
        downloads: downloads,
        storageFileOverrides: storageFileOverrides,
        onAppliedChunk: (downloadedItems) async {
          var chunkBytes = 0;
          for (final downloaded in downloadedItems) {
            chunkBytes += downloaded.bytes.length;
          }
          completedCount += downloadedItems.length;
          completedBytes += chunkBytes;
          stats.addDownloaded(count: downloadedItems.length, bytes: chunkBytes);
          await _reportProgress(
            onProgress,
            SyncProgress(
              message: 'Downloading student artifacts...',
              completed: completedCount,
              total: downloadCandidates.length,
              completedBytes: completedBytes,
            ),
          );
        },
      );
    } else {
      final downloads = <_DownloadedArtifactCandidate>[];
      final storageFileOverrides = <String, String>{};
      for (final candidate in downloadCandidates) {
        if (currentUser.role == 'student') {
          storageFileOverrides[candidate.artifactId] =
              _artifactStore.storageFileNameForArtifact(candidate.artifactId);
        }
        downloads.add(
          _DownloadedArtifactCandidate(
            candidate: candidate,
            downloaded: await _api.downloadArtifact(candidate.artifactId),
          ),
        );
      }
      currentManifest = await _applyDownloadedArtifactInChunks(
        currentUser: currentUser,
        remoteUserId: remoteUserId,
        manifest: currentManifest,
        downloads: downloads,
        storageFileOverrides:
            storageFileOverrides.isEmpty ? null : storageFileOverrides,
        onAppliedChunk: (downloadedItems) async {
          var chunkBytes = 0;
          for (final downloaded in downloadedItems) {
            chunkBytes += downloaded.bytes.length;
          }
          completedCount += downloadedItems.length;
          completedBytes += chunkBytes;
          stats.addDownloaded(count: downloadedItems.length, bytes: chunkBytes);
          await _reportProgress(
            onProgress,
            SyncProgress(
              message: 'Downloading student artifacts...',
              completed: completedCount,
              total: downloadCandidates.length,
              completedBytes: completedBytes,
            ),
          );
        },
      );
    }

    if (removeMissingLocalArtifacts) {
      final localOnlyIds = currentManifest.items.keys
          .where((artifactId) => !serverById.containsKey(artifactId))
          .toList(growable: false)
        ..sort();
      for (final artifactId in localOnlyIds) {
        final localItem = currentManifest.items[artifactId];
        if (localItem == null || localItem.deleted) {
          continue;
        }
        if (currentUser.role == 'teacher') {
          await _runWithLocalMutationSuppressed(() async {
            await _deleteLocalArtifactScopeById(
              currentUser: currentUser,
              artifactId: artifactId,
            );
          });
          await _artifactStore.deleteArtifactFile(
            remoteUserId: remoteUserId,
            storageFile: localItem.storageFile,
          );
          final updatedItems = Map<String, StudentKpArtifactManifestItem>.from(
              currentManifest.items)
            ..remove(artifactId);
          currentManifest = currentManifest.copyWith(items: updatedItems);
          await _artifactStore.saveManifest(currentManifest);
        }
      }
    }
    return await _artifactStore.loadManifest(remoteUserId);
  }

  Future<StudentKpArtifactManifest> _reconcileTeacherManifestMetadata({
    required User currentUser,
    required int remoteUserId,
    required StudentKpArtifactManifest manifest,
    required List<ArtifactState1Item> serverItems,
  }) async {
    final serverById = <String, ArtifactState1Item>{
      for (final item in serverItems)
        if (item.artifactId.trim().isNotEmpty) item.artifactId.trim(): item,
    };
    var currentManifest = manifest;
    final localOnlyIds = currentManifest.items.keys
        .where((artifactId) => !serverById.containsKey(artifactId))
        .toList(growable: false)
      ..sort();
    for (final artifactId in localOnlyIds) {
      final localItem = currentManifest.items[artifactId];
      if (localItem == null) {
        continue;
      }
      if (!localItem.deleted) {
        await _runWithLocalMutationSuppressed(() async {
          await _deleteLocalArtifactScopeById(
            currentUser: currentUser,
            artifactId: artifactId,
          );
        });
      }
      await _artifactStore.deleteArtifactFile(
        remoteUserId: remoteUserId,
        storageFile: localItem.storageFile,
      );
      final updatedItems = Map<String, StudentKpArtifactManifestItem>.from(
        currentManifest.items,
      )..remove(artifactId);
      currentManifest = currentManifest.copyWith(items: updatedItems);
    }

    final nextItems = Map<String, StudentKpArtifactManifestItem>.from(
      currentManifest.items,
    );
    for (final serverItem in serverItems) {
      final localItem = nextItems[serverItem.artifactId];
      if (localItem != null &&
          localItem.sha256.trim() != serverItem.sha256.trim() &&
          !localItem.deleted) {
        await _runWithLocalMutationSuppressed(() async {
          await _deleteLocalArtifactScopeById(
            currentUser: currentUser,
            artifactId: serverItem.artifactId,
          );
        });
        await _artifactStore.deleteArtifactFile(
          remoteUserId: remoteUserId,
          storageFile: localItem.storageFile,
        );
      }
      nextItems[serverItem.artifactId] = StudentKpArtifactManifestItem(
        artifactId: serverItem.artifactId,
        sha256: serverItem.sha256.trim(),
        baseSha256: serverItem.sha256.trim(),
        lastModified: serverItem.lastModified.trim(),
        storageFile: localItem != null &&
                localItem.sha256.trim() == serverItem.sha256.trim()
            ? localItem.storageFile
            : '',
        deleted: false,
      );
    }
    return currentManifest.copyWith(items: nextItems);
  }

  Future<StudentKpArtifactManifest> _applyDownloadedArtifactInChunks({
    required User currentUser,
    required int remoteUserId,
    required StudentKpArtifactManifest manifest,
    required List<_DownloadedArtifactCandidate> downloads,
    Map<String, String>? storageFileOverrides,
    required Future<void> Function(List<DownloadedArtifact> downloaded)
        onAppliedChunk,
    bool preferFreshStudentImportFastPath = true,
  }) async {
    var currentManifest = manifest;
    final applyContext = _ArtifactApplyContext(
      initialManifest: manifest,
    );
    final useFreshStudentImportFastPath = preferFreshStudentImportFastPath &&
        currentUser.role == 'student' &&
        manifest.items.isEmpty;
    final deferManifestCheckpoint =
        storageFileOverrides != null &&
        (currentUser.role == 'teacher' || useFreshStudentImportFastPath);
    final checkpointInterval =
        currentUser.role == 'teacher' || useFreshStudentImportFastPath
            ? downloads.length
            : _downloadApplyCheckpointInterval;
    for (var start = 0; start < downloads.length; start += checkpointInterval) {
      final end = (start + checkpointInterval < downloads.length)
          ? start + checkpointInterval
          : downloads.length;
      final chunk = downloads.sublist(start, end);
      final nextItems = Map<String, StudentKpArtifactManifestItem>.from(
        currentManifest.items,
      );
      await _runWithLocalMutationSuppressed(() async {
        await _db.transaction(() async {
          if (useFreshStudentImportFastPath) {
            await _applyDownloadedStudentFreshImportChunk(
              currentUser: currentUser,
              remoteUserId: remoteUserId,
              manifest: currentManifest,
              chunk: chunk,
              applyContext: applyContext,
              nextItems: nextItems,
              storageFileOverrides: storageFileOverrides,
            );
          } else {
            for (final entry in chunk) {
              await _applyDownloadedArtifact(
                currentUser: currentUser,
                remoteUserId: remoteUserId,
                manifest: currentManifest,
                candidate: entry.candidate,
                downloaded: entry.downloaded,
                applyContext: applyContext,
                storageFileOverride:
                    storageFileOverrides?[entry.candidate.artifactId],
                nextItems: nextItems,
                persistManifest: false,
                wrapLocalMutationSuppression: false,
                wrapLocalScopeTransaction: false,
              );
            }
          }
        });
      });
      currentManifest = currentManifest.copyWith(items: nextItems);
      if (!deferManifestCheckpoint) {
        await _artifactStore.saveManifest(currentManifest);
      }
      await onAppliedChunk(
        chunk.map((entry) => entry.downloaded).toList(growable: false),
      );
    }
    if (deferManifestCheckpoint) {
      await _artifactStore.saveManifest(currentManifest);
    }
    return currentManifest;
  }

  bool _shouldDownloadServerArtifact({
    required User currentUser,
    required StudentKpArtifactManifestItem? localItem,
    required ArtifactState1Item serverItem,
  }) {
    if (localItem == null) {
      return true;
    }
    if (localItem.deleted) {
      return false;
    }
    final localSha = localItem.sha256.trim();
    final baseSha = localItem.baseSha256.trim();
    final serverSha = serverItem.sha256.trim();
    if (localSha == serverSha) {
      return false;
    }
    if (currentUser.role != 'student') {
      return true;
    }
    if (baseSha.isNotEmpty && baseSha == localSha) {
      return true;
    }
    return false;
  }

  Future<StudentKpArtifactManifest> _uploadLocalChanges({
    required User currentUser,
    required int remoteUserId,
    required StudentKpArtifactManifest manifest,
    required List<ArtifactState1Item> serverItems,
    required SyncRunStats stats,
    required SyncProgressCallback? onProgress,
  }) async {
    final serverById = <String, ArtifactState1Item>{
      for (final item in serverItems)
        if (item.artifactId.trim().isNotEmpty) item.artifactId.trim(): item,
    };
    final uploadCandidates = <StudentKpArtifactManifestItem>[];
    for (final item in manifest.items.values) {
      if (item.deleted) {
        continue;
      }
      final serverItem = serverById[item.artifactId];
      if (_shouldUploadLocalArtifact(item: item, serverItem: serverItem)) {
        uploadCandidates.add(item);
      }
    }
    if (uploadCandidates.isEmpty) {
      return manifest;
    }

    var currentManifest = manifest;
    var completedCount = 0;
    var completedBytes = 0;
    if (uploadCandidates.length > _batchUploadThreshold) {
      for (var start = 0;
          start < uploadCandidates.length;
          start += _batchUploadChunkSize) {
        final end = (start + _batchUploadChunkSize < uploadCandidates.length)
            ? start + _batchUploadChunkSize
            : uploadCandidates.length;
        final chunk = uploadCandidates.sublist(start, end);
        final pendingUploads = <PendingArtifactUpload>[];
        final bytesByArtifactId = <String, Uint8List>{};
        for (final candidate in chunk) {
          final bytes = await _artifactStore.readArtifactBytes(
            remoteUserId: remoteUserId,
            item: candidate,
          );
          if (bytes == null) {
            throw StateError(
              'Local artifact bytes missing for ${candidate.artifactId}.',
            );
          }
          final computedSha = sha256.convert(bytes).toString();
          if (computedSha != candidate.sha256.trim()) {
            throw StateError(
              'Local artifact sha256 mismatch for ${candidate.artifactId}.',
            );
          }
          pendingUploads.add(
            PendingArtifactUpload(
              artifactId: candidate.artifactId,
              sha256: candidate.sha256.trim(),
              bytes: bytes,
              baseSha256: candidate.baseSha256.trim(),
              overwriteServer: false,
            ),
          );
          bytesByArtifactId[candidate.artifactId] = bytes;
        }
        await _api.uploadArtifactBatch(pendingUploads);
        final updatedItems = Map<String, StudentKpArtifactManifestItem>.from(
          currentManifest.items,
        );
        for (final candidate in chunk) {
          updatedItems[candidate.artifactId] = candidate.copyWith(
            baseSha256: candidate.sha256.trim(),
          );
          final bytes = bytesByArtifactId[candidate.artifactId]!;
          completedCount++;
          completedBytes += bytes.length;
          stats.addUploaded(count: 1, bytes: bytes.length);
        }
        currentManifest = currentManifest.copyWith(items: updatedItems);
        await _artifactStore.saveManifest(currentManifest);
        await _reportProgress(
          onProgress,
          SyncProgress(
            message: 'Uploading student artifacts...',
            completed: completedCount,
            total: uploadCandidates.length,
            completedBytes: completedBytes,
          ),
        );
      }
    } else {
      for (final candidate in uploadCandidates) {
        final bytes = await _artifactStore.readArtifactBytes(
          remoteUserId: remoteUserId,
          item: candidate,
        );
        if (bytes == null) {
          throw StateError(
            'Local artifact bytes missing for ${candidate.artifactId}.',
          );
        }
        final computedSha = sha256.convert(bytes).toString();
        if (computedSha != candidate.sha256.trim()) {
          throw StateError(
            'Local artifact sha256 mismatch for ${candidate.artifactId}.',
          );
        }
        await _api.uploadArtifact(
          artifactId: candidate.artifactId,
          sha256: candidate.sha256.trim(),
          bytes: bytes,
          baseSha256: candidate.baseSha256.trim(),
          overwriteServer: false,
        );
        final updatedItems = Map<String, StudentKpArtifactManifestItem>.from(
            currentManifest.items);
        updatedItems[candidate.artifactId] = candidate.copyWith(
          baseSha256: candidate.sha256.trim(),
        );
        currentManifest = currentManifest.copyWith(items: updatedItems);
        await _artifactStore.saveManifest(currentManifest);
        completedCount++;
        completedBytes += bytes.length;
        stats.addUploaded(count: 1, bytes: bytes.length);
        await _reportProgress(
          onProgress,
          SyncProgress(
            message: 'Uploading student artifacts...',
            completed: completedCount,
            total: uploadCandidates.length,
            completedBytes: completedBytes,
          ),
        );
      }
    }
    return await _artifactStore.loadManifest(remoteUserId);
  }

  Future<StudentKpArtifactManifest> _applyDownloadedArtifact({
    required User currentUser,
    required int remoteUserId,
    required StudentKpArtifactManifest manifest,
    required ArtifactState1Item candidate,
    required DownloadedArtifact downloaded,
    required _ArtifactApplyContext applyContext,
    String? storageFileOverride,
    Map<String, StudentKpArtifactManifestItem>? nextItems,
    bool persistManifest = true,
    bool wrapLocalMutationSuppression = true,
    bool wrapLocalScopeTransaction = true,
  }) async {
    final computedSha = sha256.convert(downloaded.bytes).toString();
    if (computedSha != candidate.sha256.trim()) {
      throw StateError(
        'Downloaded artifact sha256 mismatch for ${candidate.artifactId}.',
      );
    }
    if (currentUser.role == 'teacher') {
      await _ensureTeacherArtifactScaffold(
        currentUser: currentUser,
        candidate: candidate,
        downloaded: downloaded,
        applyContext: applyContext,
      );
    } else {
      final payload = _artifactStore.readPayload(downloaded.bytes);
      if (wrapLocalMutationSuppression) {
        await _runWithLocalMutationSuppressed(() async {
          await _applyRemoteArtifactPayload(
            currentUser: currentUser,
            artifactId: candidate.artifactId,
            payload: payload,
            applyContext: applyContext,
            replaceExistingLocalScope:
                applyContext.hasExistingArtifact(candidate.artifactId),
            wrapReplaceTransaction: wrapLocalScopeTransaction,
          );
        });
      } else {
        await _applyRemoteArtifactPayload(
          currentUser: currentUser,
          artifactId: candidate.artifactId,
          payload: payload,
          applyContext: applyContext,
          replaceExistingLocalScope:
              applyContext.hasExistingArtifact(candidate.artifactId),
          wrapReplaceTransaction: wrapLocalScopeTransaction,
        );
      }
    }
    final shouldPersistDownloadedBytes = currentUser.role == 'teacher' ||
        (storageFileOverride ?? '').trim().isNotEmpty;
    final storageFile = shouldPersistDownloadedBytes
        ? (storageFileOverride ?? '').trim().isNotEmpty
            ? storageFileOverride!.trim()
            : _artifactStore.storageFileNameForArtifact(
                candidate.artifactId,
              )
        : '';
    if (shouldPersistDownloadedBytes &&
        (storageFileOverride ?? '').trim().isEmpty) {
      await _artifactStore.writeArtifactBytes(
        remoteUserId: remoteUserId,
        storageFile: storageFile,
        bytes: downloaded.bytes,
      );
    }
    final updatedItems = nextItems ??
        Map<String, StudentKpArtifactManifestItem>.from(manifest.items);
    updatedItems[candidate.artifactId] = StudentKpArtifactManifestItem(
      artifactId: candidate.artifactId,
      sha256: candidate.sha256.trim(),
      baseSha256: candidate.sha256.trim(),
      lastModified: candidate.lastModified.trim(),
      storageFile: storageFile,
      deleted: false,
    );
    final updatedManifest = manifest.copyWith(items: updatedItems);
    if (persistManifest) {
      await _artifactStore.saveManifest(updatedManifest);
    }
    return updatedManifest;
  }

  Future<void> _ensureTeacherArtifactScaffold({
    required User currentUser,
    required ArtifactState1Item candidate,
    required DownloadedArtifact downloaded,
    required _ArtifactApplyContext applyContext,
  }) async {
    final localCourseVersionId = await _resolveCourseVersionId(
      candidate.courseId,
      applyContext: applyContext,
    );
    String? usernameHint;
    if (!applyContext.localStudentIdByRemoteStudentId
        .containsKey(candidate.studentUserId)) {
      final payload = _artifactStore.readPayload(downloaded.bytes);
      usernameHint = (payload['student_username'] as String?)?.trim();
    }
    await _resolveLocalStudentId(
      currentUser: currentUser,
      remoteStudentUserId: candidate.studentUserId,
      usernameHint: usernameHint,
      courseVersionId: localCourseVersionId,
      applyContext: applyContext,
    );
  }

  bool _shouldUploadLocalArtifact({
    required StudentKpArtifactManifestItem item,
    required ArtifactState1Item? serverItem,
  }) {
    final localSha = item.sha256.trim();
    final baseSha = item.baseSha256.trim();
    final serverSha = serverItem?.sha256.trim() ?? '';
    if (localSha.isEmpty) {
      return false;
    }
    if (serverItem == null) {
      return baseSha.isEmpty;
    }
    if (localSha == serverSha) {
      return false;
    }
    return baseSha.isNotEmpty && baseSha == serverSha;
  }

  Future<void> _assertNoPendingArtifactConflicts({
    required User currentUser,
    required StudentKpArtifactManifest manifest,
    required List<ArtifactState1Item> serverItems,
  }) async {
    final serverById = <String, ArtifactState1Item>{
      for (final item in serverItems)
        if (item.artifactId.trim().isNotEmpty) item.artifactId.trim(): item,
    };
    final allArtifactIds = <String>{
      ...manifest.items.keys,
      ...serverById.keys,
    }.toList(growable: false)
      ..sort();
    for (final artifactId in allArtifactIds) {
      final localItem = manifest.items[artifactId];
      final serverItem = serverById[artifactId];
      if (localItem == null) {
        continue;
      }
      if (localItem.deleted) {
        if (serverItem != null) {
          throw StateError(
            'Artifact conflict requires explicit delete resolution for '
            '$artifactId.',
          );
        }
        continue;
      }
      if (serverItem == null) {
        if (currentUser.role == 'teacher') {
          continue;
        }
        if (localItem.baseSha256.trim().isEmpty) {
          continue;
        }
        throw StateError(
          'Artifact conflict requires explicit delete resolution for '
          '$artifactId.',
        );
      }
      final localSha = localItem.sha256.trim();
      final baseSha = localItem.baseSha256.trim();
      final serverSha = serverItem.sha256.trim();
      if (localSha == serverSha) {
        continue;
      }
      final canDownload = _shouldDownloadServerArtifact(
        currentUser: currentUser,
        localItem: localItem,
        serverItem: serverItem,
      );
      if (canDownload) {
        continue;
      }
      final canUpload = currentUser.role == 'student' &&
          _shouldUploadLocalArtifact(
            item: localItem,
            serverItem: serverItem,
          );
      if (canUpload) {
        continue;
      }
      throw StateError(
        'Artifact conflict requires explicit user choice for $artifactId '
        '(local=$localSha base=$baseSha server=$serverSha).',
      );
    }
  }

  Future<StudentKpArtifactManifest> _refreshLocalArtifactsForStudent(
    User student,
  ) async {
    final remoteUserId = _requireRemoteUserId(student);
    final manifest = await _artifactStore.loadManifest(remoteUserId);
    final scopes = await _listLocalStudentKpScopes(student);
    final nextItems = Map<String, StudentKpArtifactManifestItem>.from(
      manifest.items,
    );
    final liveArtifactIds = <String>{};
    for (final scope in scopes) {
      final artifact = await _buildLocalArtifact(scope);
      liveArtifactIds.add(artifact.artifactId);
      final existing = nextItems[artifact.artifactId];
      final storageFile = _artifactStore.storageFileNameForArtifact(
        artifact.artifactId,
      );
      await _artifactStore.writeArtifactBytes(
        remoteUserId: remoteUserId,
        storageFile: storageFile,
        bytes: artifact.bytes,
      );
      nextItems[artifact.artifactId] = StudentKpArtifactManifestItem(
        artifactId: artifact.artifactId,
        sha256: artifact.sha256,
        baseSha256: existing?.baseSha256.trim() ?? '',
        lastModified: artifact.lastModified,
        storageFile: storageFile,
        deleted: false,
      );
    }

    final staleArtifactIds = nextItems.keys
        .where((artifactId) => !liveArtifactIds.contains(artifactId))
        .toList(growable: false)
      ..sort();
    for (final artifactId in staleArtifactIds) {
      final existing = nextItems[artifactId];
      if (existing == null) {
        continue;
      }
      await _artifactStore.deleteArtifactFile(
        remoteUserId: remoteUserId,
        storageFile: existing.storageFile,
      );
      if (existing.baseSha256.trim().isEmpty) {
        nextItems.remove(artifactId);
        continue;
      }
      nextItems[artifactId] = existing.copyWith(
        deleted: true,
        storageFile: '',
      );
    }

    final updated = manifest.copyWith(items: nextItems);
    await _artifactStore.saveManifest(updated);
    return await _artifactStore.loadManifest(remoteUserId);
  }

  Future<List<_LocalStudentKpScope>> _listLocalStudentKpScopes(
    User student,
  ) async {
    if (student.role != 'student') {
      return const <_LocalStudentKpScope>[];
    }
    final remoteStudentUserId = _requireRemoteUserId(student);
    final sessions = await _db.getSessionsForStudent(student.id);
    final sessionsByCourse = <int, Set<String>>{};
    for (final session in sessions) {
      final kpKey = session.kpKey.trim();
      if (kpKey.isEmpty || kpKey == kTreeViewStateKpKey) {
        continue;
      }
      sessionsByCourse
          .putIfAbsent(session.courseVersionId, () => <String>{})
          .add(kpKey);
    }

    final assignedCourses = await _db.getAssignedCoursesForStudent(student.id);
    final scopes = <_LocalStudentKpScope>[];
    for (final course in assignedCourses) {
      final remoteCourseId = await _db.getRemoteCourseId(course.id);
      if (remoteCourseId == null || remoteCourseId <= 0) {
        continue;
      }
      final teacher = await _db.getUserById(course.teacherId);
      if (teacher == null) {
        throw StateError(
            'Teacher ${course.teacherId} missing for course ${course.id}.');
      }
      final teacherRemoteUserId = _requireRemoteUserId(teacher);
      final kpKeys = <String>{
        ...(sessionsByCourse[course.id] ?? const <String>{}),
      };
      final progressRows = await _db.getProgressForCourse(
        studentId: student.id,
        courseVersionId: course.id,
      );
      for (final progress in progressRows) {
        final kpKey = progress.kpKey.trim();
        if (kpKey.isEmpty || kpKey == kTreeViewStateKpKey) {
          continue;
        }
        kpKeys.add(kpKey);
      }
      final sortedKpKeys = kpKeys.toList(growable: false)..sort();
      for (final kpKey in sortedKpKeys) {
        scopes.add(
          _LocalStudentKpScope(
            localStudentId: student.id,
            remoteStudentUserId: remoteStudentUserId,
            studentUsername: student.username.trim(),
            courseVersionId: course.id,
            remoteCourseId: remoteCourseId,
            courseSubject: course.subject.trim(),
            teacherRemoteUserId: teacherRemoteUserId,
            kpKey: kpKey,
          ),
        );
      }
    }
    scopes.sort((left, right) {
      final courseCompare = left.remoteCourseId.compareTo(right.remoteCourseId);
      if (courseCompare != 0) {
        return courseCompare;
      }
      return left.kpKey.compareTo(right.kpKey);
    });
    return scopes;
  }

  Future<LocalArtifactBuildResult> _buildLocalArtifact(
    _LocalStudentKpScope scope,
  ) async {
    final course = await _db.getCourseVersionById(scope.courseVersionId);
    if (course == null) {
      throw StateError('Course version ${scope.courseVersionId} missing.');
    }
    final node =
        await _db.getCourseNodeByKey(scope.courseVersionId, scope.kpKey);
    final sessions = await _db.getSessionsForNode(
      studentId: scope.localStudentId,
      courseVersionId: scope.courseVersionId,
      kpKey: scope.kpKey,
    );
    final progress = await _db.getProgress(
      studentId: scope.localStudentId,
      courseVersionId: scope.courseVersionId,
      kpKey: scope.kpKey,
    );
    if (sessions.isEmpty && progress == null) {
      throw StateError(
        'Cannot build empty artifact for ${scope.remoteCourseId}:${scope.kpKey}.',
      );
    }

    final sessionPayloads = <Map<String, dynamic>>[];
    final updatedAtValues = <DateTime>[];
    final sortedSessions = List<ChatSession>.from(sessions)
      ..sort((left, right) {
        final leftSyncId = (left.syncId ?? '').trim();
        final rightSyncId = (right.syncId ?? '').trim();
        if (leftSyncId != rightSyncId) {
          return leftSyncId.compareTo(rightSyncId);
        }
        final leftUpdatedAt = _resolveSessionUpdatedAt(left);
        final rightUpdatedAt = _resolveSessionUpdatedAt(right);
        final updatedCompare = leftUpdatedAt.compareTo(rightUpdatedAt);
        if (updatedCompare != 0) {
          return updatedCompare;
        }
        return left.id.compareTo(right.id);
      });
    for (final session in sortedSessions) {
      final syncId = (session.syncId ?? '').trim();
      if (syncId.isEmpty) {
        throw StateError('Session ${session.id} is missing syncId.');
      }
      final sessionUpdatedAt = _resolveSessionUpdatedAt(session);
      updatedAtValues.add(sessionUpdatedAt);
      final messages = await _db.getMessagesForSession(session.id);
      final messagePayloads = messages
          .map(
            (message) => <String, dynamic>{
              'role': message.role.trim(),
              'content': message.content,
              if ((message.rawContent ?? '').trim().isNotEmpty)
                'raw_content': message.rawContent,
              if ((message.parsedJson ?? '').trim().isNotEmpty)
                'parsed_json': message.parsedJson!.trim(),
              if ((message.action ?? '').trim().isNotEmpty)
                'action': message.action!.trim(),
              'created_at': message.createdAt.toUtc().toIso8601String(),
            },
          )
          .toList(growable: false);
      sessionPayloads.add(<String, dynamic>{
        'session_sync_id': syncId,
        'course_id': scope.remoteCourseId,
        if (scope.courseSubject.isNotEmpty)
          'course_subject': scope.courseSubject,
        'kp_key': scope.kpKey,
        if ((node?.title ?? '').trim().isNotEmpty)
          'kp_title': node!.title.trim(),
        if ((session.title ?? '').trim().isNotEmpty)
          'session_title': session.title!.trim(),
        'started_at': session.startedAt.toUtc().toIso8601String(),
        if (session.endedAt != null)
          'ended_at': session.endedAt!.toUtc().toIso8601String(),
        if ((session.summaryText ?? '').trim().isNotEmpty)
          'summary_text': session.summaryText!.trim(),
        if ((session.controlStateJson ?? '').trim().isNotEmpty)
          'control_state_json': session.controlStateJson!.trim(),
        if (session.controlStateUpdatedAt != null)
          'control_state_updated_at':
              session.controlStateUpdatedAt!.toUtc().toIso8601String(),
        if ((session.evidenceStateJson ?? '').trim().isNotEmpty)
          'evidence_state_json': session.evidenceStateJson!.trim(),
        if (session.evidenceStateUpdatedAt != null)
          'evidence_state_updated_at':
              session.evidenceStateUpdatedAt!.toUtc().toIso8601String(),
        'student_remote_user_id': scope.remoteStudentUserId,
        if (scope.studentUsername.isNotEmpty)
          'student_username': scope.studentUsername,
        'teacher_remote_user_id': scope.teacherRemoteUserId,
        'updated_at': sessionUpdatedAt.toUtc().toIso8601String(),
        'messages': messagePayloads,
      });
    }

    sessionPayloads.sort((left, right) {
      final idCompare = ((left['session_sync_id'] as String?) ?? '')
          .compareTo((right['session_sync_id'] as String?) ?? '');
      if (idCompare != 0) {
        return idCompare;
      }
      return ((left['updated_at'] as String?) ?? '')
          .compareTo((right['updated_at'] as String?) ?? '');
    });

    Map<String, dynamic>? progressPayload;
    if (progress != null) {
      updatedAtValues.add(progress.updatedAt.toUtc());
      progressPayload = <String, dynamic>{
        'course_id': scope.remoteCourseId,
        if (scope.courseSubject.isNotEmpty)
          'course_subject': scope.courseSubject,
        'kp_key': scope.kpKey,
        'lit': progress.lit,
        'lit_percent': progress.litPercent,
        if ((progress.questionLevel ?? '').trim().isNotEmpty)
          'question_level': progress.questionLevel!.trim(),
        'easy_passed_count': progress.easyPassedCount,
        'medium_passed_count': progress.mediumPassedCount,
        'hard_passed_count': progress.hardPassedCount,
        if ((progress.summaryText ?? '').trim().isNotEmpty)
          'summary_text': progress.summaryText!.trim(),
        if ((progress.summaryRawResponse ?? '').trim().isNotEmpty)
          'summary_raw_response': progress.summaryRawResponse!.trim(),
        if (progress.summaryValid != null)
          'summary_valid': progress.summaryValid,
        'teacher_remote_user_id': scope.teacherRemoteUserId,
        'student_remote_user_id': scope.remoteStudentUserId,
        'updated_at': progress.updatedAt.toUtc().toIso8601String(),
      };
    }

    if (updatedAtValues.isEmpty) {
      throw StateError(
        'Artifact updated_at cannot be resolved for ${scope.remoteCourseId}:${scope.kpKey}.',
      );
    }
    var artifactUpdatedAt = updatedAtValues.first;
    for (final value in updatedAtValues.skip(1)) {
      if (value.isAfter(artifactUpdatedAt)) {
        artifactUpdatedAt = value;
      }
    }

    return _artifactStore.buildArtifact(
      LocalArtifactBuildInput(
        artifactId: _artifactIdForScope(scope),
        lastModified: artifactUpdatedAt,
        payload: <String, dynamic>{
          'schema': _artifactSchema,
          'course_id': scope.remoteCourseId,
          if (scope.courseSubject.isNotEmpty)
            'course_subject': course.subject.trim(),
          'kp_key': scope.kpKey,
          'teacher_remote_user_id': scope.teacherRemoteUserId,
          'student_remote_user_id': scope.remoteStudentUserId,
          if (scope.studentUsername.isNotEmpty)
            'student_username': scope.studentUsername,
          'updated_at': artifactUpdatedAt.toUtc().toIso8601String(),
          if (progressPayload != null) 'progress': progressPayload,
          'sessions': sessionPayloads,
        },
      ),
    );
  }

  Future<void> _applyRemoteArtifactPayload({
    required User currentUser,
    required String artifactId,
    required Map<String, dynamic> payload,
    required _ArtifactApplyContext applyContext,
    required bool replaceExistingLocalScope,
    bool wrapReplaceTransaction = true,
  }) async {
    final identity = _parseArtifactIdentity(artifactId, payload);
    final localCourseVersionId = await _resolveCourseVersionId(
      identity.remoteCourseId,
      applyContext: applyContext,
    );
    final localStudentId = await _resolveLocalStudentId(
      currentUser: currentUser,
      remoteStudentUserId: identity.remoteStudentUserId,
      usernameHint: (payload['student_username'] as String?)?.trim(),
      courseVersionId: localCourseVersionId,
      applyContext: applyContext,
    );
    await _replaceLocalArtifactScope(
      localStudentId: localStudentId,
      localCourseVersionId: localCourseVersionId,
      kpKey: identity.kpKey,
      payload: payload,
      applyContext: applyContext,
      replaceExistingLocalScope: replaceExistingLocalScope,
      wrapTransaction: wrapReplaceTransaction,
    );
  }

  Future<int> _resolveLocalStudentId({
    required User currentUser,
    required int remoteStudentUserId,
    required String? usernameHint,
    required int courseVersionId,
    required _ArtifactApplyContext applyContext,
  }) async {
    if (currentUser.role == 'student') {
      if (_requireRemoteUserId(currentUser) != remoteStudentUserId) {
        throw StateError(
          'Student artifact $remoteStudentUserId does not belong to current user '
          '${currentUser.remoteUserId}.',
        );
      }
      return currentUser.id;
    }
    final cachedLocalStudentId =
        applyContext.localStudentIdByRemoteStudentId[remoteStudentUserId];
    if (cachedLocalStudentId != null && cachedLocalStudentId > 0) {
      return cachedLocalStudentId;
    }
    final localCourse = await _db.getCourseVersionById(courseVersionId);
    if (localCourse == null) {
      throw StateError('Course version $courseVersionId missing.');
    }
    final studentId =
        await _remoteStudentIdentity.resolveOrCreateLocalStudentId(
      db: _db,
      remoteStudentId: remoteStudentUserId,
      usernameHint: usernameHint,
      teacherId: localCourse.teacherId,
    );
    applyContext.localStudentIdByRemoteStudentId[remoteStudentUserId] =
        studentId;
    await _db.assignStudent(
      studentId: studentId,
      courseVersionId: courseVersionId,
      notifySyncUsers: false,
    );
    applyContext.assignedStudentCoursePairs.add(
      '$studentId:$courseVersionId',
    );
    return studentId;
  }

  Future<int> _resolveCourseVersionId(
    int remoteCourseId, {
    required _ArtifactApplyContext applyContext,
  }) async {
    final cachedCourseVersionId =
        applyContext.localCourseVersionIdByRemoteCourseId[remoteCourseId];
    if (cachedCourseVersionId != null && cachedCourseVersionId > 0) {
      return cachedCourseVersionId;
    }
    final courseVersionId =
        await _db.getCourseVersionIdForRemoteCourse(remoteCourseId);
    if (courseVersionId == null || courseVersionId <= 0) {
      throw StateError(
          'Remote course $remoteCourseId is not installed locally.');
    }
    applyContext.localCourseVersionIdByRemoteCourseId[remoteCourseId] =
        courseVersionId;
    return courseVersionId;
  }

  Future<void> _replaceLocalArtifactScope({
    required int localStudentId,
    required int localCourseVersionId,
    required String kpKey,
    required Map<String, dynamic> payload,
    required _ArtifactApplyContext applyContext,
    required bool replaceExistingLocalScope,
    bool wrapTransaction = true,
  }) async {
    final assignmentKey = '$localStudentId:$localCourseVersionId';
    if (!applyContext.assignedStudentCoursePairs.contains(assignmentKey)) {
      await _db.assignStudent(
        studentId: localStudentId,
        courseVersionId: localCourseVersionId,
        notifySyncUsers: false,
      );
      applyContext.assignedStudentCoursePairs.add(assignmentKey);
    }
    if (wrapTransaction) {
      await _db.transaction(() async {
        await _replaceLocalArtifactScopeBody(
          localStudentId: localStudentId,
          localCourseVersionId: localCourseVersionId,
          kpKey: kpKey,
          payload: payload,
          replaceExistingLocalScope: replaceExistingLocalScope,
        );
      });
      return;
    }
    await _replaceLocalArtifactScopeBody(
      localStudentId: localStudentId,
      localCourseVersionId: localCourseVersionId,
      kpKey: kpKey,
      payload: payload,
      replaceExistingLocalScope: replaceExistingLocalScope,
    );
  }

  Future<void> _replaceLocalArtifactScopeBody({
    required int localStudentId,
    required int localCourseVersionId,
    required String kpKey,
    required Map<String, dynamic> payload,
    required bool replaceExistingLocalScope,
  }) async {
    if (replaceExistingLocalScope) {
      await _deleteLocalArtifactScope(
        localStudentId: localStudentId,
        localCourseVersionId: localCourseVersionId,
        kpKey: kpKey,
      );
    }

    final progressPayload = payload['progress'];
    if (progressPayload is Map<String, dynamic>) {
      await _db.upsertProgressFromSync(
        studentId: localStudentId,
        courseVersionId: localCourseVersionId,
        kpKey: kpKey,
        lit: progressPayload['lit'] == true,
        litPercent: (progressPayload['lit_percent'] as num?)?.toInt() ?? 0,
        questionLevel: (progressPayload['question_level'] as String?)?.trim(),
        easyPassedCount:
            (progressPayload['easy_passed_count'] as num?)?.toInt() ?? 0,
        mediumPassedCount:
            (progressPayload['medium_passed_count'] as num?)?.toInt() ?? 0,
        hardPassedCount:
            (progressPayload['hard_passed_count'] as num?)?.toInt() ?? 0,
        summaryText: (progressPayload['summary_text'] as String?)?.trim(),
        summaryRawResponse:
            (progressPayload['summary_raw_response'] as String?)?.trim(),
        summaryValid: progressPayload['summary_valid'] as bool?,
        updatedAt: _parseIsoTime(progressPayload['updated_at']) ??
            DateTime.now().toUtc(),
        mergeWithLocal: false,
      );
    }

    final sessions = payload['sessions'];
    if (sessions is! List) {
      return;
    }
    await _insertArtifactSessions(
      localStudentId: localStudentId,
      localCourseVersionId: localCourseVersionId,
      kpKey: kpKey,
      sessions: sessions,
    );
  }

  Future<void> _insertArtifactSessions({
    required int localStudentId,
    required int localCourseVersionId,
    required String kpKey,
    required List sessions,
  }) async {
    for (final rawSession in sessions) {
      if (rawSession is! Map<String, dynamic>) {
        throw StateError('Student artifact session entry must be an object.');
      }
      final syncId = (rawSession['session_sync_id'] as String?)?.trim() ?? '';
      if (syncId.isEmpty) {
        throw StateError('Student artifact session_sync_id missing.');
      }
      final startedAt =
          _parseIsoTime(rawSession['started_at']) ?? DateTime.now().toUtc();
      final updatedAt = _parseIsoTime(rawSession['updated_at']) ?? startedAt;
      final sessionId = await _db.into(_db.chatSessions).insert(
            ChatSessionsCompanion.insert(
              studentId: localStudentId,
              courseVersionId: localCourseVersionId,
              kpKey: kpKey,
              title: Value(
                ((rawSession['session_title'] as String?)?.trim() ?? '').isEmpty
                    ? null
                    : (rawSession['session_title'] as String).trim(),
              ),
              startedAt: Value(startedAt),
              endedAt: Value(_parseIsoTime(rawSession['ended_at'])),
              status: const Value('active'),
              summaryText: Value(
                ((rawSession['summary_text'] as String?)?.trim() ?? '').isEmpty
                    ? null
                    : (rawSession['summary_text'] as String).trim(),
              ),
              controlStateJson: Value(
                _encodeCanonicalJson(rawSession['control_state_json']),
              ),
              controlStateUpdatedAt:
                  Value(_parseIsoTime(rawSession['control_state_updated_at'])),
              evidenceStateJson: Value(
                _encodeCanonicalJson(rawSession['evidence_state_json']),
              ),
              evidenceStateUpdatedAt:
                  Value(_parseIsoTime(rawSession['evidence_state_updated_at'])),
              syncId: Value(syncId),
              syncUpdatedAt: Value(updatedAt),
              syncUploadedAt: Value(updatedAt),
            ),
          );
      final rawMessages = rawSession['messages'];
      if (rawMessages is! List) {
        continue;
      }
      for (final rawMessage in rawMessages) {
        if (rawMessage is! Map<String, dynamic>) {
          throw StateError('Student artifact message entry must be an object.');
        }
        final role = (rawMessage['role'] as String?)?.trim() ?? '';
        final content = (rawMessage['content'] as String?) ?? '';
        if (role.isEmpty) {
          throw StateError('Student artifact message role missing.');
        }
        await _db.into(_db.chatMessages).insert(
              ChatMessagesCompanion.insert(
                sessionId: sessionId,
                role: role,
                content: content,
                rawContent: Value(
                  ((rawMessage['raw_content'] as String?)?.trim() ?? '').isEmpty
                      ? null
                      : (rawMessage['raw_content'] as String),
                ),
                parsedJson: Value(
                  _encodeCanonicalJson(rawMessage['parsed_json']),
                ),
                action: Value(
                  ((rawMessage['action'] as String?)?.trim() ?? '').isEmpty
                      ? null
                      : (rawMessage['action'] as String).trim(),
                ),
                createdAt: Value(
                  _parseIsoTime(rawMessage['created_at']) ?? updatedAt,
                ),
              ),
            );
      }
    }
  }

  Future<void> _applyDownloadedStudentFreshImportChunk({
    required User currentUser,
    required int remoteUserId,
    required StudentKpArtifactManifest manifest,
    required List<_DownloadedArtifactCandidate> chunk,
    required _ArtifactApplyContext applyContext,
    required Map<String, StudentKpArtifactManifestItem> nextItems,
    Map<String, String>? storageFileOverrides,
  }) async {
    final progressRows = <SyncedProgressUpsert>[];
    final sessionImports = <_PendingArtifactSessionImport>[];
    for (final entry in chunk) {
      final candidate = entry.candidate;
      final downloaded = entry.downloaded;
      final computedSha = sha256.convert(downloaded.bytes).toString();
      if (computedSha != candidate.sha256.trim()) {
        throw StateError(
          'Downloaded artifact sha256 mismatch for ${candidate.artifactId}.',
        );
      }
      final payload = _artifactStore.readPayload(downloaded.bytes);
      final identity = _parseArtifactIdentity(candidate.artifactId, payload);
      final localCourseVersionId = await _resolveCourseVersionId(
        identity.remoteCourseId,
        applyContext: applyContext,
      );
      final assignmentKey = '${currentUser.id}:$localCourseVersionId';
      if (!applyContext.assignedStudentCoursePairs.contains(assignmentKey)) {
        await _db.assignStudent(
          studentId: currentUser.id,
          courseVersionId: localCourseVersionId,
          notifySyncUsers: false,
        );
        applyContext.assignedStudentCoursePairs.add(assignmentKey);
      }

      final progressPayload = payload['progress'];
      if (progressPayload is Map<String, dynamic>) {
        progressRows.add(
          SyncedProgressUpsert(
            studentId: currentUser.id,
            courseVersionId: localCourseVersionId,
            kpKey: identity.kpKey,
            lit: progressPayload['lit'] == true,
            litPercent: (progressPayload['lit_percent'] as num?)?.toInt() ?? 0,
            questionLevel:
                (progressPayload['question_level'] as String?)?.trim(),
            easyPassedCount:
                (progressPayload['easy_passed_count'] as num?)?.toInt() ?? 0,
            mediumPassedCount:
                (progressPayload['medium_passed_count'] as num?)?.toInt() ?? 0,
            hardPassedCount:
                (progressPayload['hard_passed_count'] as num?)?.toInt() ?? 0,
            summaryText: (progressPayload['summary_text'] as String?)?.trim(),
            summaryRawResponse:
                (progressPayload['summary_raw_response'] as String?)?.trim(),
            summaryValid: progressPayload['summary_valid'] as bool?,
            updatedAt: _parseIsoTime(progressPayload['updated_at']) ??
                DateTime.now().toUtc(),
          ),
        );
      }

      final sessions = payload['sessions'];
      if (sessions is List && sessions.isNotEmpty) {
        sessionImports.add(
          _PendingArtifactSessionImport(
            localStudentId: currentUser.id,
            localCourseVersionId: localCourseVersionId,
            kpKey: identity.kpKey,
            sessions: sessions,
          ),
        );
      }

      final storageFile =
          (storageFileOverrides?[candidate.artifactId] ?? '').trim();
      if (storageFile.isNotEmpty && !storageFile.startsWith('@pack:')) {
        await _artifactStore.writeArtifactBytes(
          remoteUserId: remoteUserId,
          storageFile: storageFile,
          bytes: downloaded.bytes,
        );
      }

      nextItems[candidate.artifactId] = StudentKpArtifactManifestItem(
        artifactId: candidate.artifactId,
        sha256: candidate.sha256.trim(),
        baseSha256: candidate.sha256.trim(),
        lastModified: candidate.lastModified.trim(),
        storageFile: storageFile,
        deleted: false,
      );
      applyContext.markArtifactApplied(candidate.artifactId);
    }

    await _db.upsertProgressBatchFromSync(rows: progressRows);
    for (final sessionImport in sessionImports) {
      await _insertArtifactSessions(
        localStudentId: sessionImport.localStudentId,
        localCourseVersionId: sessionImport.localCourseVersionId,
        kpKey: sessionImport.kpKey,
        sessions: sessionImport.sessions,
      );
    }
  }

  Future<void> _deleteLocalArtifactScopeById({
    required User currentUser,
    required String artifactId,
  }) async {
    final identity = _parseArtifactIdentity(artifactId, null);
    final localCourseVersionId = await _db.getCourseVersionIdForRemoteCourse(
      identity.remoteCourseId,
    );
    if (localCourseVersionId == null || localCourseVersionId <= 0) {
      return;
    }
    int? localStudentId;
    if (currentUser.role == 'student') {
      if (_requireRemoteUserId(currentUser) != identity.remoteStudentUserId) {
        return;
      }
      localStudentId = currentUser.id;
    } else {
      final student =
          await _db.findUserByRemoteId(identity.remoteStudentUserId);
      localStudentId = student?.id;
    }
    if (localStudentId == null || localStudentId <= 0) {
      return;
    }
    await _deleteLocalArtifactScope(
      localStudentId: localStudentId,
      localCourseVersionId: localCourseVersionId,
      kpKey: identity.kpKey,
    );
  }

  Future<void> _deleteLocalArtifactScope({
    required int localStudentId,
    required int localCourseVersionId,
    required String kpKey,
  }) async {
    final sessions = await (_db.select(_db.chatSessions)
          ..where(
            (tbl) =>
                tbl.studentId.equals(localStudentId) &
                tbl.courseVersionId.equals(localCourseVersionId) &
                tbl.kpKey.equals(kpKey),
          ))
        .get();
    final sessionIds =
        sessions.map((session) => session.id).toList(growable: false);
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
          ..where(
            (tbl) =>
                tbl.studentId.equals(localStudentId) &
                tbl.courseVersionId.equals(localCourseVersionId) &
                tbl.kpKey.equals(kpKey),
          ))
        .go();
  }

  Future<void> _clearLegacyLocalState() async {
    await _db.transaction(() async {
      final sessions = await _db.select(_db.chatSessions).get();
      final sessionIds =
          sessions.map((session) => session.id).toList(growable: false);
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
      await _db.delete(_db.progressEntries).go();
      await _db.delete(_db.syncItemStates).go();
      await _db.delete(_db.syncMetadataEntries).go();
    });
  }

  Future<void> _clearLocalStudentSessionAndProgressData({
    required int studentId,
  }) async {
    await _db.transaction(() async {
      final sessions = await (_db.select(_db.chatSessions)
            ..where((tbl) => tbl.studentId.equals(studentId)))
          .get();
      final sessionIds =
          sessions.map((session) => session.id).toList(growable: false);
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
    });
  }

  DateTime _resolveSessionUpdatedAt(ChatSession session) {
    return (session.syncUpdatedAt ?? session.startedAt).toUtc();
  }

  _ArtifactIdentity _parseArtifactIdentity(
    String artifactId,
    Map<String, dynamic>? payload,
  ) {
    final parts = artifactId.trim().split(':');
    if (parts.length != 4 || parts.first != _artifactClass) {
      throw StateError('Unsupported student artifact id: $artifactId');
    }
    final remoteStudentUserId = int.tryParse(parts[1]) ?? 0;
    final remoteCourseId = int.tryParse(parts[2]) ?? 0;
    final kpKey = parts[3].trim();
    if (remoteStudentUserId <= 0 || remoteCourseId <= 0 || kpKey.isEmpty) {
      throw StateError('Student artifact id is invalid: $artifactId');
    }
    if (payload != null) {
      final payloadStudentId =
          (payload['student_remote_user_id'] as num?)?.toInt() ?? 0;
      final payloadCourseId = (payload['course_id'] as num?)?.toInt() ?? 0;
      final payloadKpKey = (payload['kp_key'] as String?)?.trim() ?? '';
      if (payloadStudentId != remoteStudentUserId ||
          payloadCourseId != remoteCourseId ||
          payloadKpKey != kpKey) {
        throw StateError(
          'Student artifact payload identity mismatch for $artifactId.',
        );
      }
      final schema = (payload['schema'] as String?)?.trim() ?? '';
      if (schema != _artifactSchema) {
        throw StateError('Unsupported student artifact schema: $schema');
      }
    }
    return _ArtifactIdentity(
      remoteStudentUserId: remoteStudentUserId,
      remoteCourseId: remoteCourseId,
      kpKey: kpKey,
    );
  }

  String _artifactIdForScope(_LocalStudentKpScope scope) {
    return '$_artifactClass:${scope.remoteStudentUserId}:${scope.remoteCourseId}:${scope.kpKey}';
  }

  int _requireRemoteUserId(User user) {
    final remoteUserId = user.remoteUserId;
    if (remoteUserId == null || remoteUserId <= 0) {
      throw StateError(
          'User ${user.id} (${user.username}) is missing remoteUserId.');
    }
    return remoteUserId;
  }

  DateTime? _parseIsoTime(dynamic raw) {
    if (raw == null) {
      return null;
    }
    if (raw is DateTime) {
      return raw.toUtc();
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      final parsed = DateTime.tryParse(trimmed);
      if (parsed == null) {
        throw StateError('Invalid RFC3339 timestamp: $trimmed');
      }
      return parsed.toUtc();
    }
    throw StateError('Unsupported timestamp value: $raw');
  }

  String? _encodeCanonicalJson(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return jsonEncode(_canonicalizeJson(value));
  }

  dynamic _canonicalizeJson(dynamic value) {
    if (value is Map) {
      final entries = value.entries
          .where((entry) => entry.key is String && entry.value != null)
          .map(
            (entry) => MapEntry(
              entry.key as String,
              _canonicalizeJson(entry.value),
            ),
          )
          .toList(growable: false)
        ..sort((left, right) => left.key.compareTo(right.key));
      return <String, dynamic>{
        for (final entry in entries)
          if (entry.value != null) entry.key: entry.value,
      };
    }
    if (value is List) {
      return value
          .map(_canonicalizeJson)
          .where((item) => item != null)
          .toList(growable: false);
    }
    return value;
  }

  Future<void> _reportProgress(
    SyncProgressCallback? onProgress,
    SyncProgress progress,
  ) async {
    onProgress?.call(progress);
  }
}

class _LocalStudentKpScope {
  const _LocalStudentKpScope({
    required this.localStudentId,
    required this.remoteStudentUserId,
    required this.studentUsername,
    required this.courseVersionId,
    required this.remoteCourseId,
    required this.courseSubject,
    required this.teacherRemoteUserId,
    required this.kpKey,
  });

  final int localStudentId;
  final int remoteStudentUserId;
  final String studentUsername;
  final int courseVersionId;
  final int remoteCourseId;
  final String courseSubject;
  final int teacherRemoteUserId;
  final String kpKey;
}

class _PendingArtifactSessionImport {
  const _PendingArtifactSessionImport({
    required this.localStudentId,
    required this.localCourseVersionId,
    required this.kpKey,
    required this.sessions,
  });

  final int localStudentId;
  final int localCourseVersionId;
  final String kpKey;
  final List sessions;
}

class _ArtifactIdentity {
  const _ArtifactIdentity({
    required this.remoteStudentUserId,
    required this.remoteCourseId,
    required this.kpKey,
  });

  final int remoteStudentUserId;
  final int remoteCourseId;
  final String kpKey;
}

class _DownloadedArtifactCandidate {
  const _DownloadedArtifactCandidate({
    required this.candidate,
    required this.downloaded,
  });

  final ArtifactState1Item candidate;
  final DownloadedArtifact downloaded;
}

class _ArtifactApplyContext {
  _ArtifactApplyContext({
    required StudentKpArtifactManifest initialManifest,
  }) : _existingArtifactIds = initialManifest.items.keys.toSet();

  final Set<String> _existingArtifactIds;
  final Map<int, int> localCourseVersionIdByRemoteCourseId = <int, int>{};
  final Map<int, int> localStudentIdByRemoteStudentId = <int, int>{};
  final Set<String> assignedStudentCoursePairs = <String>{};

  bool hasExistingArtifact(String artifactId) {
    if (artifactId.trim().isEmpty) {
      return false;
    }
    return _existingArtifactIds.contains(artifactId);
  }

  void markArtifactApplied(String artifactId) {
    if (artifactId.trim().isEmpty) {
      return;
    }
    _existingArtifactIds.add(artifactId);
  }
}
