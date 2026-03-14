import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/db/app_database.dart';
import 'package:family_teacher/security/pin_hasher.dart';

void main() {
  test('ensureRemoteUserUniqueness merges duplicate remote users', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async => db.close());

    await db.customStatement('DROP INDEX uq_users_remote_user_id');

    final canonicalId = await db.createUser(
      username: 'alice',
      pinHash: PinHasher.hash('real_password'),
      role: 'student',
      remoteUserId: 3001,
    );
    final duplicateId = await db.createUser(
      username: 'remote_student_3001',
      pinHash: PinHasher.hash('remote_student_placeholder'),
      role: 'student',
      remoteUserId: 3001,
    );

    final courseId = await db.createCourseVersion(
      teacherId: canonicalId,
      subject: 'Algebra',
      granularity: 1,
      textbookText: '',
    );
    await db.assignStudent(
      studentId: duplicateId,
      courseVersionId: courseId,
    );
    await db.upsertProgressFromSync(
      studentId: duplicateId,
      courseVersionId: courseId,
      kpKey: '1.1',
      lit: true,
      litPercent: 85,
      questionLevel: 'medium',
      summaryText: 'duplicate progress',
      summaryRawResponse: 'raw',
      summaryValid: true,
      updatedAt: DateTime.parse('2026-03-09T10:00:00Z'),
    );
    await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: duplicateId,
            courseVersionId: courseId,
            kpKey: '1.1',
            syncId: const Value('sync-session-1'),
          ),
        );

    await db.ensureRemoteUserUniqueness();

    final dedupedUser = await db.findUserByRemoteId(3001);
    expect(dedupedUser, isNotNull);
    expect(dedupedUser!.id, equals(canonicalId));

    final duplicateRow = await db.getUserById(duplicateId);
    expect(duplicateRow, isNull);

    final assignments = await db.getAssignmentsForCourse(courseId);
    expect(assignments, hasLength(1));
    expect(assignments.single.studentId, equals(canonicalId));

    final progress = await db.getProgress(
      studentId: canonicalId,
      courseVersionId: courseId,
      kpKey: '1.1',
    );
    expect(progress, isNotNull);
    expect(progress!.litPercent, equals(66));

    final sessions = await db.getSessionsForStudent(canonicalId);
    expect(sessions, hasLength(1));
  });
}
