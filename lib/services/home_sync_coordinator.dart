import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../db/app_database.dart';
import 'enrollment_sync_service.dart';
import 'session_sync_service.dart';
import 'artifact_sync_api_service.dart';
import 'sync_log_repository.dart';
import 'sync_progress.dart';

class HomeSyncCoordinator {
  HomeSyncCoordinator({
    required EnrollmentSyncService enrollmentSyncService,
    required SessionSyncService sessionSyncService,
    required SyncLogRepository syncLogRepository,
  })  : _enrollmentSyncService = enrollmentSyncService,
        _sessionSyncService = sessionSyncService,
        _syncLogRepository = syncLogRepository;

  final EnrollmentSyncService _enrollmentSyncService;
  final SessionSyncService _sessionSyncService;
  final SyncLogRepository _syncLogRepository;

  Future<SyncRunStats> runLoginSync({
    required User user,
    required String trigger,
    required SyncProgressCallback? onProgress,
    bool includeEnrollmentSync = true,
    bool includeSessionSync = true,
    SessionSyncMode sessionSyncMode = SessionSyncMode.downloadOnly,
  }) async {
    final stats = SyncRunStats();
    try {
      onProgress?.call(
        const SyncProgress(
          message: 'Checking server sync state...',
          forcePaint: true,
        ),
      );
      final localArtifactHashes = <String, String>{}
        ..addAll(
          await _enrollmentSyncService.buildCanonicalVisibleArtifactHashes(
            currentUser: user,
          ),
        )
        ..addAll(
          await _sessionSyncService.buildCanonicalVisibleArtifactHashes(
            currentUser: user,
          ),
        );
      final localState2 = _buildState2FromArtifactHashes(localArtifactHashes);
      final remoteState2 = await _enrollmentSyncService.readCanonicalRemoteState2();
      if (remoteState2.trim().isNotEmpty && remoteState2.trim() == localState2) {
        await _enrollmentSyncService.refreshStoredLocalState2(currentUser: user);
      } else {
        onProgress?.call(
          const SyncProgress(
            message: 'Fetching server artifact list...',
            forcePaint: true,
          ),
        );
        final remoteState1 =
            await _enrollmentSyncService.readCanonicalRemoteState1();
        if (includeEnrollmentSync) {
          onProgress?.call(
            const SyncProgress(
              message: 'Syncing enrollments from server...',
              forcePaint: true,
            ),
          );
          try {
            stats.absorb(
              await _enrollmentSyncService.syncFromCanonicalState1(
                currentUser: user,
                visibleItems: remoteState1.items,
              ),
            );
          } catch (error) {
            final failure = describeSyncFailure(
              stage: 'Enrollment sync',
              error: error,
            );
            await _recordFailure(
              trigger: trigger,
              user: user,
              stats: stats,
              failure: failure,
            );
            throw HomeSyncException(
              failure.userMessage,
              logMessage: failure.logMessage,
            );
          }
        }
        if (includeSessionSync) {
          onProgress?.call(
            const SyncProgress(
              message: 'Syncing sessions/progress from server...',
              forcePaint: true,
            ),
          );
          try {
            stats.absorb(
              await _sessionSyncService.syncFromCanonicalState1(
                currentUser: user,
                visibleItems: remoteState1.items,
                onProgress: onProgress,
                mode: sessionSyncMode,
              ),
            );
          } catch (error) {
            final failure = describeSyncFailure(
              stage: 'Session sync',
              error: error,
            );
            await _recordFailure(
              trigger: trigger,
              user: user,
              stats: stats,
              failure: failure,
            );
            throw HomeSyncException(
              failure.userMessage,
              logMessage: failure.logMessage,
            );
          }
        }
      }
    } on HomeSyncException {
      rethrow;
    }

    try {
      await _syncLogRepository.appendRunEvent(
        trigger: trigger,
        actorRole: user.role,
        actorUserId: user.id,
        stats: stats,
        success: true,
      );
    } catch (logError) {
      throw HomeSyncException('Sync log write failed: $logError');
    }
    return stats;
  }

  Future<SyncRunStats> runCoreSync({
    required User user,
    required String trigger,
    required SyncProgressCallback? onProgress,
    bool includeEnrollmentSync = true,
    bool includeSessionSync = true,
    SessionSyncMode sessionSyncMode = SessionSyncMode.full,
  }) async {
    final stats = SyncRunStats();
    try {
      if (includeEnrollmentSync) {
        onProgress?.call(
          const SyncProgress(
            message: 'Syncing enrollments from server...',
            forcePaint: true,
          ),
        );
        try {
          stats.absorb(
            await _enrollmentSyncService.syncIfReady(currentUser: user),
          );
        } catch (error) {
          final failure = describeSyncFailure(
            stage: 'Enrollment sync',
            error: error,
          );
          await _recordFailure(
            trigger: trigger,
            user: user,
            stats: stats,
            failure: failure,
          );
          throw HomeSyncException(
            failure.userMessage,
            logMessage: failure.logMessage,
          );
        }
      }

      if (includeSessionSync) {
        onProgress?.call(
          const SyncProgress(
            message: 'Syncing sessions/progress from server...',
            forcePaint: true,
          ),
        );
        try {
          stats.absorb(
            await _sessionSyncService.syncIfReady(
              currentUser: user,
              onProgress: onProgress,
              mode: sessionSyncMode,
            ),
          );
        } catch (error) {
          final failure = describeSyncFailure(
            stage: 'Session sync',
            error: error,
          );
          await _recordFailure(
            trigger: trigger,
            user: user,
            stats: stats,
            failure: failure,
          );
          throw HomeSyncException(
            failure.userMessage,
            logMessage: failure.logMessage,
          );
        }
      }
    } on HomeSyncException {
      rethrow;
    }

    try {
      await _syncLogRepository.appendRunEvent(
        trigger: trigger,
        actorRole: user.role,
        actorUserId: user.id,
        stats: stats,
        success: true,
      );
    } catch (logError) {
      throw HomeSyncException('Sync log write failed: $logError');
    }
    return stats;
  }

  Future<SyncRunStats> forcePullFromServer({
    required User user,
    required String trigger,
    required SyncProgressCallback? onProgress,
    bool includeEnrollmentSync = true,
    bool includeSessionSync = true,
    SessionSyncMode sessionSyncMode = SessionSyncMode.downloadOnly,
    bool wipeLocalStudentData = true,
  }) async {
    final stats = SyncRunStats();
    try {
      if (includeEnrollmentSync) {
        onProgress?.call(
          const SyncProgress(
            message: 'Syncing enrollments from server...',
            forcePaint: true,
          ),
        );
        try {
          stats.absorb(
            await _enrollmentSyncService.forcePullFromServer(currentUser: user),
          );
        } catch (error) {
          final failure = describeSyncFailure(
            stage: 'Enrollment sync',
            error: error,
          );
          await _recordFailure(
            trigger: trigger,
            user: user,
            stats: stats,
            failure: failure,
          );
          throw HomeSyncException(
            failure.userMessage,
            logMessage: failure.logMessage,
          );
        }
      }

      if (includeSessionSync) {
        onProgress?.call(
          const SyncProgress(
            message: 'Syncing sessions/progress from server...',
            forcePaint: true,
          ),
        );
        try {
          stats.absorb(
            await _sessionSyncService.forcePullFromServer(
              currentUser: user,
              wipeLocalStudentData: wipeLocalStudentData,
              onProgress: onProgress,
              mode: sessionSyncMode,
            ),
          );
        } catch (error) {
          final failure = describeSyncFailure(
            stage: 'Session sync',
            error: error,
          );
          await _recordFailure(
            trigger: trigger,
            user: user,
            stats: stats,
            failure: failure,
          );
          throw HomeSyncException(
            failure.userMessage,
            logMessage: failure.logMessage,
          );
        }
      }
    } on HomeSyncException {
      rethrow;
    }

    try {
      await _syncLogRepository.appendRunEvent(
        trigger: trigger,
        actorRole: user.role,
        actorUserId: user.id,
        stats: stats,
        success: true,
      );
    } catch (logError) {
      throw HomeSyncException('Sync log write failed: $logError');
    }
    return stats;
  }

  Future<void> _recordFailure({
    required String trigger,
    required User user,
    required SyncRunStats stats,
    required SyncFailurePresentation failure,
  }) async {
    try {
      await _syncLogRepository.appendRunEvent(
        trigger: trigger,
        actorRole: user.role,
        actorUserId: user.id,
        stats: stats,
        success: false,
        error: failure.logMessage,
      );
    } catch (logError) {
      throw HomeSyncException(
        failure.userMessage,
        logMessage: '${failure.logMessage}; sync log write failed: $logError',
      );
    }
  }

  String _buildState2FromArtifactHashes(Map<String, String> artifactHashesById) {
    final canonical = artifactHashesById.entries
        .where(
          (entry) =>
              entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty,
        )
        .toList(growable: false)
      ..sort((left, right) {
        final artifactCompare = left.key.compareTo(right.key);
        if (artifactCompare != 0) {
          return artifactCompare;
        }
        return left.value.compareTo(right.value);
      });
    final builder = StringBuffer();
    for (final entry in canonical) {
      builder
        ..write(entry.key.trim())
        ..write('|')
        ..write(entry.value.trim())
        ..write('\n');
    }
    return 'artifact_state2_v1:${sha256.convert(utf8.encode(builder.toString()))}';
  }
}

class HomeSyncException implements Exception {
  HomeSyncException(this.message, {String? logMessage})
      : logMessage = (logMessage ?? message).trim();

  final String message;
  final String logMessage;

  @override
  String toString() => message;
}

class SyncFailurePresentation {
  const SyncFailurePresentation({
    required this.userMessage,
    required this.logMessage,
  });

  final String userMessage;
  final String logMessage;
}

SyncFailurePresentation describeSyncFailure({
  required String stage,
  required Object error,
}) {
  final normalizedStage = stage.trim().isEmpty ? 'Sync' : stage.trim();
  return SyncFailurePresentation(
    userMessage: '$normalizedStage failed: ${_describeSyncErrorForUser(error)}',
    logMessage: '$normalizedStage failed: ${_describeSyncErrorForLog(error)}',
  );
}

String _describeSyncErrorForUser(Object error) {
  if (error is HomeSyncException) {
    return error.message;
  }
  if (error is ArtifactSyncApiException) {
    return error.message;
  }
  final message = '$error'.trim();
  if (message.isNotEmpty) {
    return message;
  }
  return 'Unexpected error.';
}

String _describeSyncErrorForLog(Object error) {
  if (error is HomeSyncException) {
    return error.logMessage;
  }
  if (error is ArtifactSyncApiException) {
    return error.debugMessage;
  }
  final message = '$error'.trim();
  if (message.isNotEmpty) {
    return '${error.runtimeType}: $message';
  }
  return error.runtimeType.toString();
}
