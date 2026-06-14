import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutor1on1/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('mistake evidence dedupes by normalized tag key', () async {
    final teacherId = await db.createUser(
      username: 'teacher',
      pinHash: 'hash',
      role: 'teacher',
    );
    final studentId = await db.createUser(
      username: 'student',
      pinHash: 'hash',
      role: 'student',
      teacherId: teacherId,
    );
    final courseVersionId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Math',
      granularity: 1,
      textbookText: '',
    );
    await db.assignStudent(
      studentId: studentId,
      courseVersionId: courseVersionId,
    );
    await db.into(db.courseNodes).insert(
          CourseNodesCompanion.insert(
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            title: 'Linear equations',
            description: '',
            orderIndex: 1,
          ),
        );
    final sessionId = await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            syncId: const Value('session-1'),
          ),
        );
    final messageId = await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: sessionId,
            role: 'assistant',
            content: 'review result',
            action: const Value('review'),
          ),
        );

    await db.upsertMistakeEvidence(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
      sessionId: sessionId,
      messageId: messageId,
      mistakeTag: ' Sign Error ',
      mistakeNote: 'First note',
      questionExcerpt: 'Solve -x = 2',
      difficulty: 'easy',
      evidenceJson: '{"attempt":1}',
    );
    await db.upsertMistakeEvidence(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
      sessionId: sessionId,
      messageId: messageId,
      mistakeTag: 'sign error',
      mistakeNote: 'Latest note',
      questionExcerpt: 'Solve -x = 2',
      difficulty: 'easy',
      evidenceJson: '{"attempt":2}',
    );

    final rows = await db.getMistakeEntriesForScope(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
    );
    expect(rows, hasLength(1));
    expect(rows.single.mistakeTagKey, 'sign error');
    expect(rows.single.occurrences, 2);
    expect(rows.single.mistakeNote, 'Latest note');
  });

  test('backfill creates durable mistakes from existing review messages once',
      () async {
    final teacherId = await db.createUser(
      username: 'teacher',
      pinHash: 'hash',
      role: 'teacher',
    );
    final studentId = await db.createUser(
      username: 'student',
      pinHash: 'hash',
      role: 'student',
      teacherId: teacherId,
    );
    final courseVersionId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Math',
      granularity: 1,
      textbookText: '',
    );
    final sessionId = await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            syncId: const Value('session-1'),
          ),
        );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: sessionId,
            role: 'assistant',
            content: 'mid-question hint',
            action: const Value('review'),
            parsedJson: const Value(
              '{"finished":false,"mistakes":["sign error"]}',
            ),
          ),
        );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: sessionId,
            role: 'assistant',
            content: 'review result',
            action: const Value('review'),
            parsedJson: const Value(
              '{"finished":true,"mistakes":["sign error","off by one"]}',
            ),
          ),
        );

    await db.backfillMistakeEntriesFromMessages();
    await db.backfillMistakeEntriesFromMessages();

    final rows = await db.getMistakeEntriesForScope(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
    );
    expect(rows, hasLength(2));
    final byKey = {for (final row in rows) row.mistakeTagKey: row};
    // 'sign error' appears in two turns of the same session: counted once.
    expect(byKey['sign error']?.occurrences, 1);
    expect(byKey['off by one']?.occurrences, 1);
  });

  test('artifact import preserves local queue state on scope replace',
      () async {
    const studentId = 1;
    const courseVersionId = 2;
    await db.importMistakeEntriesFromArtifact(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
      entries: <Map<String, dynamic>>[
        <String, dynamic>{
          'mistake_tag': 'sign error',
          'mistake_tag_key': 'sign error',
          'evidence_json': '{"source":"remote"}',
          'occurrences': 1,
          'first_seen_at': '2026-04-01T08:01:00Z',
          'last_seen_at': '2026-04-01T08:04:00Z',
        },
      ],
    );
    final initial = await db.getMistakeEntriesForScope(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
    );
    await db.setMistakeEntryStatus(
      id: initial.single.id,
      status: 'dismissed',
      dismissed: true,
    );

    await db.importMistakeEntriesFromArtifact(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
      entries: <Map<String, dynamic>>[
        <String, dynamic>{
          'mistake_tag': 'sign error',
          'mistake_tag_key': 'sign error',
          'evidence_json': '{"source":"remote2"}',
          'occurrences': 3,
          'first_seen_at': '2026-04-01T08:01:00Z',
          'last_seen_at': '2026-04-01T09:00:00Z',
        },
      ],
    );

    final replaced = await db.getMistakeEntriesForScope(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
    );
    expect(replaced, hasLength(1));
    expect(replaced.single.dismissed, isTrue);
    expect(replaced.single.status, 'dismissed');
    expect(replaced.single.occurrences, 3);
  });

  test('crediting a reviewed KP pushes out due, non-reflagged mistakes',
      () async {
    final teacherId = await db.createUser(
        username: 'teacher', pinHash: 'hash', role: 'teacher');
    final studentId = await db.createUser(
        username: 'student', pinHash: 'hash', role: 'student', teacherId: teacherId);
    final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId, subject: 'Math', granularity: 1, textbookText: '');
    final sessionId = await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            syncId: const Value('session-1'),
          ),
        );
    for (final tag in const ['sign error', 'off by one']) {
      await db.upsertMistakeEvidence(
        studentId: studentId,
        courseVersionId: courseVersionId,
        kpKey: '1.1',
        sessionId: sessionId,
        messageId: 1,
        mistakeTag: tag,
        evidenceJson: '{}',
      );
    }
    // Both start due now.
    expect(
      await db.getDueMistakeEntriesForCourse(
          studentId: studentId, courseVersionId: courseVersionId, kpKey: '1.1'),
      hasLength(2),
    );

    // Reviewed the KP; only 'sign error' was re-flagged this turn.
    await db.creditReviewedDueMistakes(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
      reflaggedTagKeys: {'sign error'},
    );

    final rows = await db.getMistakeEntriesForScope(
        studentId: studentId, courseVersionId: courseVersionId, kpKey: '1.1');
    final byKey = {for (final r in rows) r.mistakeTagKey: r};
    // 'off by one' was not re-flagged: streak bumped and pushed into the future.
    expect(byKey['off by one']!.reviewStreak, 1);
    expect(byKey['off by one']!.nextReviewAt!.isAfter(DateTime.now().toUtc()),
        isTrue);
    // 'sign error' was re-flagged: still due, streak unchanged.
    expect(byKey['sign error']!.reviewStreak, 0);

    final stillDue = await db.getDueMistakeEntriesForCourse(
        studentId: studentId, courseVersionId: courseVersionId, kpKey: '1.1');
    expect(stillDue.map((e) => e.mistakeTagKey), ['sign error']);
  });

  test('due query is snooze-aware', () async {
    final teacherId = await db.createUser(
        username: 'teacher', pinHash: 'hash', role: 'teacher');
    final studentId = await db.createUser(
        username: 'student', pinHash: 'hash', role: 'student', teacherId: teacherId);
    final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId, subject: 'Math', granularity: 1, textbookText: '');
    final sessionId = await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            syncId: const Value('session-1'),
          ),
        );
    await db.upsertMistakeEvidence(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
      sessionId: sessionId,
      messageId: 1,
      mistakeTag: 'snoozed tag',
      evidenceJson: '{}',
    );
    final entry = (await db.getMistakeEntriesForScope(
            studentId: studentId, courseVersionId: courseVersionId, kpKey: '1.1'))
        .single;
    await (db.update(db.mistakeEntries)..where((t) => t.id.equals(entry.id)))
        .write(MistakeEntriesCompanion(
      snoozedUntil: Value(DateTime.now().toUtc().add(const Duration(days: 2))),
    ));

    expect(
      await db.getDueMistakeEntriesForCourse(
          studentId: studentId, courseVersionId: courseVersionId, kpKey: '1.1'),
      isEmpty,
    );
    expect(
      await db.getDueMistakeEntriesForStudent(studentId: studentId),
      isEmpty,
    );
  });
}
