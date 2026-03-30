import '../db/app_database.dart';
import 'app_services.dart';
import 'sync_log_repository.dart';
import 'sync_progress.dart';

typedef EnrollmentForcePull = Future<SyncRunStats> Function(
    {required User currentUser});

typedef SessionForcePull = Future<SyncRunStats> Function({
  required User currentUser,
  required bool wipeLocalStudentData,
  SyncProgressCallback? onProgress,
});

class StudentServerCopyService {
  StudentServerCopyService({
    required EnrollmentForcePull forcePullEnrollments,
    required SessionForcePull forcePullSessions,
  })  : _forcePullEnrollments = forcePullEnrollments,
        _forcePullSessions = forcePullSessions;

  factory StudentServerCopyService.fromAppServices(AppServices services) {
    return StudentServerCopyService(
      forcePullEnrollments: ({required currentUser}) =>
          services.enrollmentSyncService.forcePullFromServer(
        currentUser: currentUser,
      ),
      forcePullSessions: ({
        required currentUser,
        required wipeLocalStudentData,
        onProgress,
      }) =>
          services.sessionSyncService.forcePullFromServer(
        currentUser: currentUser,
        wipeLocalStudentData: wipeLocalStudentData,
        onProgress: onProgress,
      ),
    );
  }

  final EnrollmentForcePull _forcePullEnrollments;
  final SessionForcePull _forcePullSessions;

  Future<SyncRunStats> takeServerCopy({
    required User currentUser,
    SyncProgressCallback? onProgress,
  }) async {
    if (currentUser.role != 'student') {
      throw StateError('Take server copy requires a student user.');
    }
    if ((currentUser.remoteUserId ?? 0) <= 0) {
      throw StateError('Take server copy requires a synced student account.');
    }

    final stats = SyncRunStats();
    onProgress?.call(
      const SyncProgress(
        message: 'Taking server copy: syncing enrollments...',
        forcePaint: true,
      ),
    );
    stats.absorb(
      await _forcePullEnrollments(currentUser: currentUser),
    );
    onProgress?.call(
      const SyncProgress(
        message: 'Taking server copy: downloading sessions/progress...',
        forcePaint: true,
      ),
    );
    stats.absorb(
      await _forcePullSessions(
        currentUser: currentUser,
        wipeLocalStudentData: true,
        onProgress: onProgress,
      ),
    );
    return stats;
  }
}
