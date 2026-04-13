import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/llm/prompt_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('loadPrompt resolves the nearest full prompt override', () async {
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
      content: 'TEACHER full prompt',
    );
    await db.insertPromptTemplate(
      teacherId: teacherId,
      promptName: 'learn',
      courseKey: 'course_math',
      content: 'COURSE full prompt',
    );
    await db.insertPromptTemplate(
      teacherId: teacherId,
      promptName: 'learn',
      studentId: studentId,
      content: 'STUDENT GLOBAL full prompt',
    );
    await db.insertPromptTemplate(
      teacherId: teacherId,
      promptName: 'learn',
      courseKey: 'course_math',
      studentId: studentId,
      content: 'STUDENT COURSE full prompt',
    );

    final repo = PromptRepository(db: db);
    final combined = await repo.loadPrompt(
      'learn',
      teacherId: teacherId,
      courseKey: 'course_math',
      studentId: studentId,
    );
    expect(combined, equals('STUDENT COURSE full prompt'));

    await db.clearActivePromptTemplates(
      teacherId: teacherId,
      promptName: 'learn',
      courseKey: 'course_math',
      studentId: studentId,
    );
    repo.invalidatePromptCache(promptName: 'learn');
    final withoutStudentCourse = await repo.loadPrompt(
      'learn',
      teacherId: teacherId,
      courseKey: 'course_math',
      studentId: studentId,
    );
    expect(withoutStudentCourse, equals('STUDENT GLOBAL full prompt'));

    await db.clearActivePromptTemplates(
      teacherId: teacherId,
      promptName: 'learn',
      studentId: studentId,
    );
    repo.invalidatePromptCache(promptName: 'learn');
    final withoutStudentGlobal = await repo.loadPrompt(
      'learn',
      teacherId: teacherId,
      courseKey: 'course_math',
      studentId: studentId,
    );
    expect(withoutStudentGlobal, equals('COURSE full prompt'));

    final noStudent = await repo.loadPrompt(
      'learn',
      teacherId: teacherId,
      courseKey: 'course_math',
    );
    expect(noStudent, equals('COURSE full prompt'));

    final systemOnly = await repo.loadPrompt(
      'learn',
      teacherId: teacherId,
    );
    expect(systemOnly, equals('TEACHER full prompt'));
  });
}
