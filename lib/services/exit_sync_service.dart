import '../db/app_database.dart';
import 'session_sync_service.dart';
import 'sync_log_repository.dart';
import 'sync_progress.dart';

typedef ExitSessionSyncRunner = Future<SyncRunStats> Function({
  required User currentUser,
  SyncProgressCallback? onProgress,
  SessionSyncMode mode,
});

class ExitSyncService {
  const ExitSyncService();

  Future<void> syncBeforeExit({
    required User user,
    required ExitSessionSyncRunner runSessionSync,
    SyncProgressCallback? onProgress,
  }) async {
    final remoteUserId = user.remoteUserId;
    if (remoteUserId == null || remoteUserId <= 0) {
      return;
    }
    if (user.role != 'student' && user.role != 'teacher') {
      return;
    }
    await runSessionSync(
      currentUser: user,
      onProgress: onProgress,
      mode: SessionSyncMode.full,
    );
  }
}
