import 'package:flutter_test/flutter_test.dart';
import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/services/student_server_copy_service.dart';
import 'package:tutor1on1/services/sync_log_repository.dart';
import 'package:tutor1on1/services/sync_progress.dart';

void main() {
  test('take server copy forces enrollment sync before wiping local sessions',
      () async {
    final progressEvents = <SyncProgress>[];
    final callOrder = <String>[];
    final service = StudentServerCopyService(
      forcePullEnrollments: ({required currentUser}) async {
        callOrder.add('enrollments:${currentUser.id}');
        return SyncRunStats(downloadedCount: 1, downloadedBytes: 200);
      },
      forcePullSessions: ({
        required currentUser,
        required wipeLocalStudentData,
        onProgress,
      }) async {
        callOrder.add('sessions:$wipeLocalStudentData');
        onProgress?.call(
          const SyncProgress(
            message: 'Importing synced sessions/progress...',
            completedBytes: 1048576,
            totalBytes: 2097152,
          ),
        );
        return SyncRunStats(downloadedCount: 2, downloadedBytes: 400);
      },
    );

    final stats = await service.takeServerCopy(
      currentUser: _studentUser(),
      onProgress: progressEvents.add,
    );

    expect(
      callOrder,
      equals(<String>['enrollments:11', 'sessions:true']),
    );
    expect(
      progressEvents.map((item) => item.message).toList(),
      equals(<String>[
        'Taking server copy: syncing enrollments...',
        'Taking server copy: downloading sessions/progress...',
        'Importing synced sessions/progress...',
      ]),
    );
    expect(progressEvents.last.detail, equals('1.0 MB / 2.0 MB'));
    expect(stats.downloadedCount, equals(3));
    expect(stats.downloadedBytes, equals(600));
  });

  test('take server copy rejects non-student users', () async {
    final service = StudentServerCopyService(
      forcePullEnrollments: ({required currentUser}) async => SyncRunStats(),
      forcePullSessions: ({
        required currentUser,
        required wipeLocalStudentData,
        onProgress,
      }) async =>
          SyncRunStats(),
    );

    await expectLater(
      service.takeServerCopy(currentUser: _teacherUser()),
      throwsA(isA<StateError>()),
    );
  });

  test('take server copy rejects students without remote sync identity',
      () async {
    var enrollmentCalled = false;
    var sessionCalled = false;
    final service = StudentServerCopyService(
      forcePullEnrollments: ({required currentUser}) async {
        enrollmentCalled = true;
        return SyncRunStats();
      },
      forcePullSessions: ({
        required currentUser,
        required wipeLocalStudentData,
        onProgress,
      }) async {
        sessionCalled = true;
        return SyncRunStats();
      },
    );

    await expectLater(
      service.takeServerCopy(currentUser: _studentUser(remoteUserId: null)),
      throwsA(isA<StateError>()),
    );
    expect(enrollmentCalled, isFalse);
    expect(sessionCalled, isFalse);
  });
}

User _studentUser({int? remoteUserId = 301}) {
  return User(
    id: 11,
    username: 'student_a',
    pinHash: 'hash',
    role: 'student',
    teacherId: null,
    remoteUserId: remoteUserId,
    createdAt: DateTime.utc(2026, 3, 30),
  );
}

User _teacherUser() {
  return User(
    id: 12,
    username: 'teacher_a',
    pinHash: 'hash',
    role: 'teacher',
    teacherId: null,
    remoteUserId: 401,
    createdAt: DateTime.utc(2026, 3, 30),
  );
}
