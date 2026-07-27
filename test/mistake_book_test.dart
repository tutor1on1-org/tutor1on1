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

  test(
      'deleting a session resets its KP progress without removing sibling data',
      () async {
    final teacherId = await db.createUser(
      username: 'teacher_delete',
      pinHash: 'hash',
      role: 'teacher',
    );
    final studentId = await db.createUser(
      username: 'student_delete',
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
    final targetSessionId = await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            syncId: const Value('target-session'),
          ),
        );
    final siblingSessionId = await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            syncId: const Value('sibling-session'),
          ),
        );
    final targetMessageId = await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: targetSessionId,
            role: 'assistant',
            content: 'target',
          ),
        );
    final siblingMessageId = await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: siblingSessionId,
            role: 'assistant',
            content: 'sibling',
          ),
        );
    await db.into(db.llmCalls).insert(
          LlmCallsCompanion.insert(
            callHash: 'target-call',
            promptName: 'review',
            renderedPrompt: 'target prompt',
            model: 'model',
            baseUrl: 'https://example.com',
            mode: 'LIVE',
            sessionId: Value(targetSessionId),
          ),
        );
    await db.into(db.llmCalls).insert(
          LlmCallsCompanion.insert(
            callHash: 'sibling-call',
            promptName: 'review',
            renderedPrompt: 'sibling prompt',
            model: 'model',
            baseUrl: 'https://example.com',
            mode: 'LIVE',
            sessionId: Value(siblingSessionId),
          ),
        );
    await db.into(db.progressEntries).insert(
          ProgressEntriesCompanion.insert(
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            lit: const Value(true),
            litPercent: const Value(100),
            easyPassedCount: const Value(1),
            mediumPassedCount: const Value(1),
            hardPassedCount: const Value(1),
          ),
        );
    await db.into(db.progressEntries).insert(
          ProgressEntriesCompanion.insert(
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: '1.2',
            lit: const Value(true),
            litPercent: const Value(100),
          ),
        );
    await db.upsertMistakeEvidence(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
      sessionId: targetSessionId,
      messageId: targetMessageId,
      mistakeTag: 'target mistake',
      evidenceJson: '{}',
    );
    await db.upsertMistakeEvidence(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
      sessionId: siblingSessionId,
      messageId: siblingMessageId,
      mistakeTag: 'sibling mistake',
      evidenceJson: '{}',
    );
    var callbackCount = 0;
    SyncRelevantChange? capturedChange;
    db.setSyncRelevantChangeCallback((change) async {
      callbackCount++;
      capturedChange = change;
    });

    await db.deleteSession(targetSessionId);

    expect(await db.getSession(targetSessionId), isNull);
    expect(await db.getMessagesForSession(targetSessionId), isEmpty);
    expect(
      await (db.select(db.llmCalls)
            ..where((row) => row.sessionId.equals(targetSessionId)))
          .get(),
      isEmpty,
    );
    expect(await db.getSession(siblingSessionId), isNotNull);
    expect(await db.getMessagesForSession(siblingSessionId), hasLength(1));
    expect(
      await (db.select(db.llmCalls)
            ..where((row) => row.sessionId.equals(siblingSessionId)))
          .get(),
      hasLength(1),
    );
    expect(
      await db.getProgress(
        studentId: studentId,
        courseVersionId: courseVersionId,
        kpKey: '1.1',
      ),
      isNull,
    );
    final otherProgress = await db.getProgress(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.2',
    );
    expect(otherProgress, isNotNull);
    expect(otherProgress!.lit, isTrue);
    final mistakes = await db.getMistakeEntriesForScope(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
    );
    final mistakesByKey = {
      for (final mistake in mistakes) mistake.mistakeTagKey: mistake,
    };
    expect(
        mistakesByKey.keys,
        containsAll(<String>[
          'target mistake',
          'sibling mistake',
        ]));
    expect(mistakesByKey['target mistake']!.sessionId, 0);
    expect(mistakesByKey['target mistake']!.messageId, 0);
    expect(
      mistakesByKey['sibling mistake']!.sessionId,
      siblingSessionId,
    );
    expect(callbackCount, 1);
    expect(capturedChange, isNotNull);
    expect(capturedChange!.localUserIds, <int>{studentId});
    expect(capturedChange!.refreshSessionArtifacts, isTrue);
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
        username: 'student',
        pinHash: 'hash',
        role: 'student',
        teacherId: teacherId);
    final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Math',
        granularity: 1,
        textbookText: '');
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
        username: 'student',
        pinHash: 'hash',
        role: 'student',
        teacherId: teacherId);
    final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Math',
        granularity: 1,
        textbookText: '');
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
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: '1.1'))
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
