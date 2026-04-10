import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/services/exit_sync_service.dart';
import 'package:tutor1on1/services/session_sync_service.dart';
import 'package:tutor1on1/services/sync_log_repository.dart';
import 'package:tutor1on1/services/sync_progress.dart';

void main() {
  const service = ExitSyncService();

  test('skips final sync for unsupported roles', () async {
    var called = false;
    final user = User(
      id: 1,
      username: 'admin',
      pinHash: 'hash',
      role: 'admin',
      remoteUserId: 99,
      createdAt: DateTime.utc(2026, 4, 10),
    );

    await service.syncBeforeExit(
      user: user,
      runSessionSync: ({
        required User currentUser,
        SyncProgressCallback? onProgress,
        SessionSyncMode mode = SessionSyncMode.full,
      }) async {
        called = true;
        return SyncRunStats();
      },
    );

    expect(called, isFalse);
  });

  test('skips final sync for local-only users', () async {
    var called = false;
    final user = User(
      id: 1,
      username: 'student',
      pinHash: 'hash',
      role: 'student',
      remoteUserId: null,
      createdAt: DateTime.utc(2026, 4, 10),
    );

    await service.syncBeforeExit(
      user: user,
      runSessionSync: ({
        required User currentUser,
        SyncProgressCallback? onProgress,
        SessionSyncMode mode = SessionSyncMode.full,
      }) async {
        called = true;
        return SyncRunStats();
      },
    );

    expect(called, isFalse);
  });

  test('runs full final sync for synced student exit', () async {
    User? capturedUser;
    SessionSyncMode? capturedMode;

    final user = User(
      id: 7,
      username: 'student',
      pinHash: 'hash',
      role: 'student',
      remoteUserId: 3001,
      createdAt: DateTime.utc(2026, 4, 10),
    );

    await service.syncBeforeExit(
      user: user,
      runSessionSync: ({
        required User currentUser,
        SyncProgressCallback? onProgress,
        SessionSyncMode mode = SessionSyncMode.full,
      }) async {
        capturedUser = currentUser;
        capturedMode = mode;
        return SyncRunStats();
      },
    );

    expect(capturedUser, isNotNull);
    expect(capturedUser!.id, user.id);
    expect(capturedMode, SessionSyncMode.full);
  });
}
