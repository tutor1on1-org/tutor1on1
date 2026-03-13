import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:family_teacher/db/app_database.dart';
import 'package:family_teacher/services/session_upload_cache_service.dart';

void main() {
  late AppDatabase db;
  late Directory tempRoot;
  late SessionUploadCacheService cacheService;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tempRoot = await Directory.systemTemp.createTemp('session_cache_test_');
    cacheService = SessionUploadCacheService(
      db: db,
      cacheRootProvider: () async => Directory(p.join(tempRoot.path, 'cache')),
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('cached session snapshot keeps upload data after live messages change',
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
    final courseId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'UK_MATH_7-13',
      granularity: 2,
      textbookText: 'contents',
      sourcePath: 'C:\\temp\\course',
    );
    await db.into(db.courseNodes).insert(
          CourseNodesCompanion.insert(
            courseVersionId: courseId,
            kpKey: '1.1',
            title: 'Integers',
            description: '1.1 Integers',
            orderIndex: 0,
          ),
        );
    final syncUpdatedAt = DateTime.utc(2026, 3, 12, 9, 45, 0);
    final sessionId = await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseId,
            kpKey: '1.1',
            title: const Value('Integers session'),
            syncId: const Value('sync-session-1'),
            syncUpdatedAt: Value(syncUpdatedAt),
          ),
        );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: sessionId,
            role: 'user',
            content: 'hello',
          ),
        );

    await cacheService.captureSession(sessionId);

    await (db.delete(db.chatMessages)
          ..where((tbl) => tbl.sessionId.equals(sessionId)))
        .go();

    final snapshot = await cacheService.readSession(
      sessionId: sessionId,
      syncUpdatedAt: syncUpdatedAt,
    );
    expect(snapshot, isNotNull);
    expect(snapshot!.courseSubject, 'UK_MATH_7-13');
    expect(snapshot.kpTitle, 'Integers');
    expect(snapshot.messages.length, 1);
    expect(snapshot.messages.single.content, 'hello');
  });

  test('chapter snapshot tracks members and hash updates at capture time',
      () async {
    final teacherId = await db.createUser(
      username: 'teacher_chapter',
      pinHash: 'hash',
      role: 'teacher',
    );
    final studentId = await db.createUser(
      username: 'student_chapter',
      pinHash: 'hash',
      role: 'student',
      teacherId: teacherId,
    );
    final courseId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'UK_MATH_7-13',
      granularity: 2,
      textbookText: 'contents',
      sourcePath: 'C:\\temp\\course',
    );
    await db.into(db.courseNodes).insert(
          CourseNodesCompanion.insert(
            courseVersionId: courseId,
            kpKey: '2.4.1',
            title: 'Equivalent forms',
            description: 'desc',
            orderIndex: 0,
          ),
        );
    await db.into(db.courseNodes).insert(
          CourseNodesCompanion.insert(
            courseVersionId: courseId,
            kpKey: '2.4.2',
            title: 'Another node',
            description: 'desc',
            orderIndex: 1,
          ),
        );

    final firstId = await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseId,
            kpKey: '2.4.1.5.2',
            title: const Value('First'),
            syncId: const Value('sync-first'),
            syncUpdatedAt: Value(DateTime.utc(2026, 3, 13, 8)),
          ),
        );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: firstId,
            role: 'assistant',
            content: 'first payload',
          ),
        );

    final secondId = await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseId,
            kpKey: '2.4.1.5.3',
            title: const Value('Second'),
            syncId: const Value('sync-second'),
            syncUpdatedAt: Value(DateTime.utc(2026, 3, 13, 9)),
          ),
        );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: secondId,
            role: 'assistant',
            content: 'second payload',
          ),
        );

    await cacheService.captureSession(firstId);
    final firstChapter = await cacheService.readChapter(
      courseVersionId: courseId,
      chapterKey: '2.4',
    );
    expect(firstChapter, isNotNull);
    expect(firstChapter!.members.map((item) => item.sessionId), [firstId]);

    await cacheService.captureSession(secondId);
    final secondChapter = await cacheService.readChapter(
      courseVersionId: courseId,
      chapterKey: '2.4',
    );
    expect(secondChapter, isNotNull);
    expect(
      secondChapter!.members.map((item) => item.sessionId).toList(),
      [firstId, secondId],
    );
    final originalHash = secondChapter.contentHash;

    await (db.update(db.chatSessions)..where((tbl) => tbl.id.equals(secondId)))
        .write(
      ChatSessionsCompanion(
        syncUpdatedAt: Value(DateTime.utc(2026, 3, 13, 10)),
      ),
    );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: secondId,
            role: 'user',
            content: 'changed payload',
          ),
        );
    await cacheService.captureSession(secondId);

    final updatedChapter = await cacheService.readChapter(
      courseVersionId: courseId,
      chapterKey: '2.4',
    );
    expect(updatedChapter, isNotNull);
    expect(updatedChapter!.contentHash, isNot(originalHash));
    expect(updatedChapter.updatedAt, DateTime.utc(2026, 3, 13, 10));
  });
}
