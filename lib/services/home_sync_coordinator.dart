import '../db/app_database.dart';
import 'enrollment_sync_service.dart';
import 'session_sync_service.dart';
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
  }) async {
    final stats = SyncRunStats();
    Object? syncError;
    try {
      onProgress?.call(
        const SyncProgress(
          message: 'Syncing enrollments from server...',
          forcePaint: true,
        ),
      );
      stats.absorb(
        await _enrollmentSyncService.syncIfReady(currentUser: user),
      );
      onProgress?.call(
        const SyncProgress(
          message: 'Syncing sessions/progress from server...',
          forcePaint: true,
        ),
      );
      stats.absorb(
        await _sessionSyncService.syncIfReady(
          currentUser: user,
          onProgress: onProgress,
        ),
      );
    } catch (error) {
      syncError = error;
    }

    if (syncError != null) {
      var reportedError = '$syncError';
      try {
        await _syncLogRepository.appendRunEvent(
          trigger: trigger,
          actorRole: user.role,
          actorUserId: user.id,
          stats: stats,
          success: false,
          error: reportedError,
        );
      } catch (logError) {
        reportedError = '$reportedError; sync log write failed: $logError';
      }
      throw HomeSyncException(reportedError);
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
}

class HomeSyncException implements Exception {
  HomeSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}
