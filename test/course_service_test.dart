import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/services/course_service.dart';

void main() {
  late AppDatabase db;
  late CourseService service;
  late Directory tempRoot;
  late int teacherId;
  late int studentId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = CourseService(db);
    tempRoot = await Directory.systemTemp.createTemp('course_service_test_');
    teacherId = await db.createUser(
      username: 'teacher_course_test',
      pinHash: 'hash',
      role: 'teacher',
    );
    studentId = await db.createUser(
      username: 'student_course_test',
      pinHash: 'hash',
      role: 'student',
      teacherId: teacherId,
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('preview blocks in-place node name changes for existing IDs', () async {
    final base = await _createCourseFolder(
      root: tempRoot,
      folderName: 'immutable_name_base',
      contents: '''
1 Unit
1.1 (Add numbers, Y1)
''',
      lectureIds: <String>['1', '1.1'],
    );
    final loaded = await service.loadCourseFromFolder(
      teacherId: teacherId,
      folderPath: base.path,
    );
    expect(loaded.success, isTrue);
    final courseId = loaded.course!.id;

    final renamed = await _createCourseFolder(
      root: tempRoot,
      folderName: 'immutable_name_renamed',
      contents: '''
1 Renamed Unit
1.1 (Add numbers, Y1)
''',
      lectureIds: <String>['1', '1.1'],
    );
    final preview = await service.previewCourseLoad(
      folderPath: renamed.path,
      courseVersionId: courseId,
    );
    expect(preview.success, isFalse);
    expect(preview.message, contains('Node names are immutable'));
    expect(preview.message, contains('1: "Unit" -> "Renamed Unit"'));
  });

  test('preview reports deleted node session counts', () async {
    final base = await _createCourseFolder(
      root: tempRoot,
      folderName: 'session_count_base',
      contents: '''
1 Unit
1.1 (Add numbers, Y1)
''',
      lectureIds: <String>['1', '1.1'],
    );
    final loaded = await service.loadCourseFromFolder(
      teacherId: teacherId,
      folderPath: base.path,
    );
    expect(loaded.success, isTrue);
    final courseId = loaded.course!.id;

    final sessionId = await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseId,
            kpKey: '1.1',
          ),
        );
    expect(sessionId, greaterThan(0));

    final reduced = await _createCourseFolder(
      root: tempRoot,
      folderName: 'session_count_reduced',
      contents: '''
1 Unit
''',
      lectureIds: <String>['1'],
    );
    final preview = await service.previewCourseLoad(
      folderPath: reduced.path,
      courseVersionId: courseId,
    );
    expect(preview.success, isTrue);
    final deleted = preview.deletedEntries
        .where((entry) => entry.id == '1.1')
        .toList(growable: false);
    expect(deleted.length, 1);
    expect(deleted.first.sessionCount, 1);
  });

  test('previewCourseLoadFromContents skips lecture file checks for bundle scaffolds',
      () async {
    final scaffoldDir = Directory(p.join(tempRoot.path, 'bundle_scaffold'));
    await scaffoldDir.create(recursive: true);
    await File(p.join(scaffoldDir.path, 'contents.txt')).writeAsString('''
1 Unit
1.1 (Add numbers, Y1)
''');

    final preview = await service.previewCourseLoadFromContents(
      sourcePath: scaffoldDir.path,
      contents: '''
1 Unit
1.1 (Add numbers, Y1)
''',
      courseNameOverride: 'Scaffold Course',
    );

    expect(preview.success, isTrue);
    expect(preview.courseName, 'Scaffold Course');
    expect(preview.normalizedPath, scaffoldDir.path);
  });

  test('previewCourseLoad reports a synced scaffold as one concise reload error',
      () async {
    final scaffoldDir = Directory(
      p.join(tempRoot.path, 'downloaded_courses', 'bundle_scaffold'),
    );
    await scaffoldDir.create(recursive: true);
    await File(p.join(scaffoldDir.path, 'contents.txt')).writeAsString('''
1 Unit
1.1 (Add numbers, Y1)
''');

    final preview = await service.previewCourseLoad(
      folderPath: scaffoldDir.path,
    );

    expect(preview.success, isFalse);
    expect(preview.message, contains('not a reloadable source folder'));
    expect(preview.message, contains('Choose the original local course folder'));
    expect(preview.message, isNot(contains('Missing file:')));
  });

  test('override reload deletes sessions for removed nodes and keeps subject',
      () async {
    final base = await _createCourseFolder(
      root: tempRoot,
      folderName: 'original_subject_course',
      contents: '''
1 Unit
1.1 (Add numbers, Y1)
''',
      lectureIds: <String>['1', '1.1'],
    );
    final loaded = await service.loadCourseFromFolder(
      teacherId: teacherId,
      folderPath: base.path,
    );
    expect(loaded.success, isTrue);
    final courseId = loaded.course!.id;
    final originalSubject = loaded.course!.subject;

    final sessionId = await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseId,
            kpKey: '1.1',
          ),
        );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: sessionId,
            role: 'assistant',
            content: 'hello',
          ),
        );
    await db.into(db.llmCalls).insert(
          LlmCallsCompanion.insert(
            callHash: 'course-service-test-call-hash',
            promptName: 'summary',
            renderedPrompt: 'prompt',
            model: 'model',
            baseUrl: 'https://example.com',
            responseText: const Value('response'),
            mode: 'LIVE',
            sessionId: Value(sessionId),
            courseVersionId: Value(courseId),
            studentId: Value(studentId),
            teacherId: Value(teacherId),
            kpKey: const Value('1.1'),
          ),
        );

    final reloaded = await _createCourseFolder(
      root: tempRoot,
      folderName: 'renamed_subject_folder',
      contents: '''
1 Unit
''',
      lectureIds: <String>['1'],
    );
    final preview = await service.previewCourseLoad(
      folderPath: reloaded.path,
      courseVersionId: courseId,
    );
    expect(preview.success, isTrue);
    expect(preview.courseName, originalSubject);

    final result = await service.applyCourseLoad(
      teacherId: teacherId,
      preview: preview,
      mode: CourseReloadMode.override,
    );
    expect(result.success, isTrue);

    final session = await db.getSession(sessionId);
    expect(session, isNull);
    final messages = await db.getMessagesForSession(sessionId);
    expect(messages, isEmpty);
    final llmRows = await (db.select(db.llmCalls)
          ..where((tbl) => tbl.sessionId.equals(sessionId)))
        .get();
    expect(llmRows, isEmpty);

    final updatedCourse = await db.getCourseVersionById(courseId);
    expect(updatedCourse, isNotNull);
    expect(updatedCourse!.subject, originalSubject);
  });
}

Future<Directory> _createCourseFolder({
  required Directory root,
  required String folderName,
  required String contents,
  required List<String> lectureIds,
}) async {
  final dir = Directory(p.join(root.path, folderName));
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
  await dir.create(recursive: true);
  await File(p.join(dir.path, 'contents.txt')).writeAsString(contents.trim());
  for (final id in lectureIds) {
    await File(p.join(dir.path, '${id}_lecture.txt'))
        .writeAsString('Lecture $id');
  }
  return dir;
}
