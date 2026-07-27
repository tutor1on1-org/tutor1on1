import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/services/prompt_bundle_compat.dart';
import 'package:tutor1on1/services/prompt_bundle_metadata_builder.dart';

const String _validReviewPrompt =
    'Review {{kp_description}} with {{student_input}}.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('default prompts are omitted from prompt bundle metadata', () async {
    final teacherId = await db.createUser(
      username: 'dennis',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 9001,
    );
    final teacher = (await db.getUserById(teacherId))!;
    final courseId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Default Course',
      granularity: 1,
      textbookText: '',
      sourcePath: 'course_default',
    );
    final course = (await db.getCourseVersionById(courseId))!;

    final metadata = await PromptBundleMetadataBuilder(db: db).build(
      teacher: teacher,
      course: course,
      remoteCourseId: 501,
    );

    expect(metadata['schema'], kCurrentPromptBundleSchema);
    expect(metadata['prompt_templates'], isEmpty);
    expect(metadata['student_prompt_profiles'], isEmpty);
    expect(metadata['student_pass_configs'], isEmpty);
  });

  test('metadata includes only overrides effective for the course', () async {
    final teacherId = await db.createUser(
      username: 'dennis',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 9001,
    );
    final assignedStudentId = await db.createUser(
      username: 'albert',
      pinHash: 'hash',
      role: 'student',
      teacherId: teacherId,
      remoteUserId: 3001,
    );
    final unassignedStudentId = await db.createUser(
      username: 'brenda',
      pinHash: 'hash',
      role: 'student',
      teacherId: teacherId,
      remoteUserId: 3002,
    );
    final teacher = (await db.getUserById(teacherId))!;
    final courseId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'HKSI Paper 2',
      granularity: 1,
      textbookText: '',
      sourcePath: 'course_hksi_paper2',
    );
    final course = (await db.getCourseVersionById(courseId))!;
    await db.assignStudent(
      studentId: assignedStudentId,
      courseVersionId: courseId,
    );

    await db.insertPromptTemplate(
      teacherId: teacherId,
      promptName: 'review',
      content: 'teacher $_validReviewPrompt',
    );
    await db.insertPromptTemplate(
      teacherId: teacherId,
      promptName: 'review',
      courseKey: 'course_hksi_paper2',
      content: 'course $_validReviewPrompt',
    );
    await db.insertPromptTemplate(
      teacherId: teacherId,
      promptName: 'review',
      studentId: assignedStudentId,
      content: 'assigned global $_validReviewPrompt',
    );
    await db.insertPromptTemplate(
      teacherId: teacherId,
      promptName: 'review',
      studentId: unassignedStudentId,
      content: 'unassigned global $_validReviewPrompt',
    );
    await db.insertPromptTemplate(
      teacherId: teacherId,
      promptName: 'review',
      courseKey: 'course_hksi_paper2',
      studentId: assignedStudentId,
      content: 'assigned course $_validReviewPrompt',
    );
    await db.insertPromptTemplate(
      teacherId: teacherId,
      promptName: 'review',
      courseKey: 'course_hksi_paper2',
      studentId: unassignedStudentId,
      content: 'unassigned course $_validReviewPrompt',
    );
    await db.insertPromptTemplate(
      teacherId: teacherId,
      promptName: 'review',
      courseKey: 'other_course',
      studentId: assignedStudentId,
      content: 'other course $_validReviewPrompt',
    );

    await db.upsertStudentPromptProfile(
      teacherId: teacherId,
      courseKey: 'course_hksi_paper2',
      studentId: assignedStudentId,
      gradeLevel: 'assigned profile',
    );
    await db.upsertStudentPromptProfile(
      teacherId: teacherId,
      courseKey: 'course_hksi_paper2',
      studentId: unassignedStudentId,
      gradeLevel: 'unassigned profile',
    );
    await db.upsertStudentPassConfig(
      courseVersionId: courseId,
      studentId: assignedStudentId,
      easyWeight: 0.2,
      mediumWeight: 0.4,
      hardWeight: 0.8,
      passThreshold: 0.7,
    );
    await db.upsertStudentPassConfig(
      courseVersionId: courseId,
      studentId: unassignedStudentId,
      easyWeight: 0.3,
      mediumWeight: 0.5,
      hardWeight: 0.9,
      passThreshold: 0.8,
    );

    final metadata = await PromptBundleMetadataBuilder(db: db).build(
      teacher: teacher,
      course: course,
      remoteCourseId: 501,
    );

    final promptTemplates =
        (metadata['prompt_templates'] as List).cast<Map<String, dynamic>>();
    expect(
      promptTemplates.map((item) => item['content']).toSet(),
      equals(<String>{
        'teacher $_validReviewPrompt',
        'course $_validReviewPrompt',
        'assigned global $_validReviewPrompt',
        'assigned course $_validReviewPrompt',
      }),
    );
    expect(
      promptTemplates.map((item) => item['scope']).toSet(),
      equals(<String>{
        'teacher',
        'course',
        'student_global',
        'student_course',
      }),
    );
    expect(
      promptTemplates
          .where((item) => item['scope'] == 'student_course')
          .single['student_remote_user_id'],
      3001,
    );

    final profiles = (metadata['student_prompt_profiles'] as List)
        .cast<Map<String, dynamic>>();
    expect(profiles, hasLength(1));
    expect(profiles.single['scope'], 'student_course');
    expect(profiles.single['grade_level'], 'assigned profile');
    expect(profiles.single['student_remote_user_id'], 3001);

    final passConfigs =
        (metadata['student_pass_configs'] as List).cast<Map<String, dynamic>>();
    expect(passConfigs, hasLength(1));
    expect(passConfigs.single['student_remote_user_id'], 3001);
    expect(passConfigs.single['pass_threshold'], 0.7);
  });
}
