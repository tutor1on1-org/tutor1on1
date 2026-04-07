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

  Future<SyncRunStats> runCoreSync({
    required User user,
    required String trigger,
    required SyncProgressCallback? onProgress,
    bool includeEnrollmentSync = true,
    bool includeSessionSync = true,
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
