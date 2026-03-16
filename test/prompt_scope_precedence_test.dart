import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/db/app_database.dart';
import 'package:family_teacher/llm/prompt_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'loadPrompt ignores prompt template scopes for bundled tutor prompts',
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
        promptName: 'learn',
        content: 'SYSTEM override',
      );
      await db.insertPromptTemplate(
        teacherId: teacherId,
        promptName: 'learn',
        courseKey: 'course_math',
        content: 'COURSE append',
      );
      await db.insertPromptTemplate(
        teacherId: teacherId,
        promptName: 'learn',
        courseKey: 'course_math',
        studentId: studentId,
        content: 'STUDENT append',
      );

      final repo = PromptRepository(db: db);
      final bundled = await repo.loadBundledSystemPrompt('learn');
      final combined = await repo.loadPrompt(
        'learn',
        teacherId: teacherId,
        courseKey: 'course_math',
        studentId: studentId,
      );
      expect(combined, equals(bundled));

      final noStudent = await repo.loadPrompt(
        'learn',
        teacherId: teacherId,
        courseKey: 'course_math',
      );
      expect(noStudent, equals(bundled));

      final systemOnly = await repo.loadPrompt(
        'learn',
        teacherId: teacherId,
      );
      expect(systemOnly, equals(bundled));
    },
  );

  test('loadAppendPrompt returns empty for bundled tutor prompts', () async {
    final teacherId = await db.createUser(
      username: 'teacher_prompt_normalize',
      pinHash: 'hash',
      role: 'teacher',
    );
    await db.insertPromptTemplate(
      teacherId: teacherId,
      promptName: 'learn',
      content: 'SYSTEM override',
    );
    await db.insertPromptTemplate(
      teacherId: teacherId,
      promptName: 'learn',
      courseKey: '  course_math  ',
      content: 'COURSE append',
    );

    final repo = PromptRepository(db: db);
    final combined = await repo.loadAppendPrompt(
      'learn',
      teacherId: teacherId,
      courseKey: 'course_math',
    );
    expect(combined, isEmpty);
  });
}
