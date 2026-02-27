import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/db/app_database.dart';
import 'package:family_teacher/llm/prompt_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'loadPrompt combines system, course, and student scopes in precedence order',
    () async {
      final teacherId = await db.createUser(
        username: 'teacher_prompt_scope',
        pinHash: 'hash',
        role: 'teacher',
      );
      final studentId = await db.createUser(
        username: 'student_prompt_scope',
        pinHash: 'hash',
        role: 'student',
        teacherId: teacherId,
      );
      await db.insertPromptTemplate(
        teacherId: teacherId,
        promptName: 'learn_init',
        content: 'SYSTEM override',
      );
      await db.insertPromptTemplate(
        teacherId: teacherId,
        promptName: 'learn_init',
        courseKey: 'course_math',
        content: 'COURSE append',
      );
      await db.insertPromptTemplate(
        teacherId: teacherId,
        promptName: 'learn_init',
        courseKey: 'course_math',
        studentId: studentId,
        content: 'STUDENT append',
      );

      final repo = PromptRepository(db: db);
      final combined = await repo.loadPrompt(
        'learn_init',
        teacherId: teacherId,
        courseKey: 'course_math',
        studentId: studentId,
      );
      expect(
        combined,
        equals('SYSTEM override\n\nCOURSE append\n\nSTUDENT append'),
      );

      final noStudent = await repo.loadPrompt(
        'learn_init',
        teacherId: teacherId,
        courseKey: 'course_math',
      );
      expect(noStudent, equals('SYSTEM override\n\nCOURSE append'));

      final systemOnly = await repo.loadPrompt(
        'learn_init',
        teacherId: teacherId,
      );
      expect(systemOnly, equals('SYSTEM override'));
    },
  );

  test('loadPrompt normalizes scoped course keys before lookup', () async {
    final teacherId = await db.createUser(
      username: 'teacher_prompt_normalize',
      pinHash: 'hash',
      role: 'teacher',
    );
    await db.insertPromptTemplate(
      teacherId: teacherId,
      promptName: 'learn_cont',
      content: 'SYSTEM override',
    );
    await db.insertPromptTemplate(
      teacherId: teacherId,
      promptName: 'learn_cont',
      courseKey: '  course_math  ',
      content: 'COURSE append',
    );

    final repo = PromptRepository(db: db);
    final combined = await repo.loadPrompt(
      'learn_cont',
      teacherId: teacherId,
      courseKey: 'course_math',
    );
    expect(combined, equals('SYSTEM override\n\nCOURSE append'));
  });
}
