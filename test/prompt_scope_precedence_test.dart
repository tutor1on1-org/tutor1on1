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

  test('loadPrompt applies teacher, course, student-global, and student-course scopes', () async {
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
      studentId: studentId,
      content: 'STUDENT GLOBAL append',
    );
    await db.insertPromptTemplate(
      teacherId: teacherId,
      promptName: 'learn',
      courseKey: 'course_math',
      studentId: studentId,
      content: 'STUDENT COURSE append',
    );

    final repo = PromptRepository(db: db);
    final combined = await repo.loadPrompt(
      'learn',
      teacherId: teacherId,
      courseKey: 'course_math',
      studentId: studentId,
    );
    expect(
      combined,
      equals(
        'SYSTEM override\n\n'
        'COURSE append\n\n'
        'STUDENT GLOBAL append\n\n'
        'STUDENT COURSE append',
      ),
    );

    final noStudent = await repo.loadPrompt(
      'learn',
      teacherId: teacherId,
      courseKey: 'course_math',
    );
    expect(noStudent, equals('SYSTEM override\n\nCOURSE append'));

    final systemOnly = await repo.loadPrompt(
      'learn',
      teacherId: teacherId,
    );
    expect(systemOnly, equals('SYSTEM override'));
  });

  test('loadAppendPrompt resolves course and student-global scopes', () async {
    final teacherId = await db.createUser(
      username: 'teacher_prompt_normalize',
      pinHash: 'hash',
      role: 'teacher',
    );
    final studentId = await db.createUser(
      username: 'student_prompt_normalize',
      pinHash: 'hash',
      role: 'student',
      teacherId: teacherId,
    );
    await db.insertPromptTemplate(
      teacherId: teacherId,
      promptName: 'learn',
      courseKey: '  course_math  ',
      content: 'COURSE append',
    );
    await db.insertPromptTemplate(
      teacherId: teacherId,
      promptName: 'learn',
      studentId: studentId,
      content: 'STUDENT GLOBAL append',
    );

    final repo = PromptRepository(db: db);
    final courseAppend = await repo.loadAppendPrompt(
      'learn',
      teacherId: teacherId,
      courseKey: 'course_math',
    );
    expect(courseAppend, equals('COURSE append'));

    final studentGlobalAppend = await repo.loadAppendPrompt(
      'learn',
      teacherId: teacherId,
      studentId: studentId,
    );
    expect(studentGlobalAppend, equals('STUDENT GLOBAL append'));
  });
}
