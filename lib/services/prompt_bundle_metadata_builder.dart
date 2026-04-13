import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'prompt_bundle_compat.dart';
import 'prompt_template_validator.dart';

class PromptBundleTimestampMetadata {
  const PromptBundleTimestampMetadata._();

  static DateTime? parseTimestamp(Object? value) {
    final raw = value is String ? value.trim() : '';
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }

  static String resolveTimestampString({
    required String? raw,
    required DateTime actual,
  }) {
    final parsed = parseTimestamp(raw);
    if (parsed != null && parsed.isAtSameMomentAs(actual.toUtc())) {
      return raw!.trim();
    }
    return actual.toUtc().toIso8601String();
  }

  static String promptTemplateKey({
    required String promptName,
    required String scope,
    required int? studentRemoteUserId,
  }) {
    return [
      'prompt',
      promptName.trim(),
      scope.trim(),
      studentRemoteUserId?.toString() ?? '',
    ].join('::');
  }

  static String profileKey({
    required String scope,
    required int? studentRemoteUserId,
  }) {
    return [
      'profile',
      scope.trim(),
      studentRemoteUserId?.toString() ?? '',
    ].join('::');
  }

  static String passConfigKey({
    required int? studentRemoteUserId,
  }) {
    return [
      'pass_config',
      studentRemoteUserId?.toString() ?? '',
    ].join('::');
  }
}

class PromptBundleMetadataBuilder {
  PromptBundleMetadataBuilder({
    required AppDatabase db,
    PromptTemplateValidator? promptValidator,
  })  : _db = db,
        _promptValidator = promptValidator ?? PromptTemplateValidator();

  final AppDatabase _db;
  final PromptTemplateValidator _promptValidator;

  Future<Map<String, dynamic>> build({
    required User teacher,
    required CourseVersion course,
    required int remoteCourseId,
    Map<String, Map<String, String>> timestampMetadata =
        const <String, Map<String, String>>{},
  }) async {
    final courseKey = (course.sourcePath ?? '').trim();
    if (courseKey.isEmpty) {
      return <String, dynamic>{
        'schema': kCurrentPromptBundleSchema,
        'remote_course_id': remoteCourseId,
        'teacher_username': teacher.username,
        'prompt_templates': const <Map<String, dynamic>>[],
        'student_prompt_profiles': const <Map<String, dynamic>>[],
        'student_pass_configs': const <Map<String, dynamic>>[],
      };
    }

    final assignments = await _db.getAssignmentsForCourse(course.id);
    final assignedStudentIds =
        assignments.map((assignment) => assignment.studentId).toSet();
    final studentCache = <int, User?>{};

    return <String, dynamic>{
      'schema': kCurrentPromptBundleSchema,
      'remote_course_id': remoteCourseId,
      'teacher_username': teacher.username,
      'prompt_templates': await _buildPromptTemplatesPayload(
        teacher: teacher,
        courseKey: courseKey,
        assignedStudentIds: assignedStudentIds,
        studentCache: studentCache,
        timestampMetadata: timestampMetadata,
      ),
      'student_prompt_profiles': await _buildProfilesPayload(
        teacher: teacher,
        courseKey: courseKey,
        assignedStudentIds: assignedStudentIds,
        studentCache: studentCache,
        timestampMetadata: timestampMetadata,
      ),
      'student_pass_configs': await _buildPassConfigsPayload(
        courseVersionId: course.id,
        assignedStudentIds: assignedStudentIds,
        studentCache: studentCache,
        timestampMetadata: timestampMetadata,
      ),
    };
  }

  Future<List<Map<String, dynamic>>> _buildPromptTemplatesPayload({
    required User teacher,
    required String courseKey,
    required Set<int> assignedStudentIds,
    required Map<int, User?> studentCache,
    required Map<String, Map<String, String>> timestampMetadata,
  }) async {
    final scopeTemplates = <PromptTemplate>[];
    final systemTemplates = await (_db.select(_db.promptTemplates)
          ..where((tbl) =>
              tbl.teacherId.equals(teacher.id) &
              tbl.isActive.equals(true) &
              tbl.courseKey.isNull() &
              tbl.studentId.isNull())
          ..orderBy([
            (tbl) =>
                OrderingTerm(expression: tbl.createdAt, mode: OrderingMode.desc)
          ]))
        .get();
    scopeTemplates.addAll(systemTemplates);

    if (assignedStudentIds.isNotEmpty) {
      final studentGlobalTemplates = await (_db.select(_db.promptTemplates)
            ..where((tbl) =>
                tbl.teacherId.equals(teacher.id) &
                tbl.isActive.equals(true) &
                tbl.courseKey.isNull() &
                tbl.studentId.isIn(assignedStudentIds))
            ..orderBy([
              (tbl) => OrderingTerm(
                    expression: tbl.createdAt,
                    mode: OrderingMode.desc,
                  )
            ]))
          .get();
      scopeTemplates.addAll(studentGlobalTemplates);
    }

    final courseTemplates = await (_db.select(_db.promptTemplates)
          ..where((tbl) =>
              tbl.teacherId.equals(teacher.id) &
              tbl.isActive.equals(true) &
              tbl.courseKey.equals(courseKey) &
              tbl.studentId.isNull())
          ..orderBy([
            (tbl) =>
                OrderingTerm(expression: tbl.createdAt, mode: OrderingMode.desc)
          ]))
        .get();
    scopeTemplates.addAll(courseTemplates);

    if (assignedStudentIds.isNotEmpty) {
      final studentCourseTemplates = await (_db.select(_db.promptTemplates)
            ..where((tbl) =>
                tbl.teacherId.equals(teacher.id) &
                tbl.isActive.equals(true) &
                tbl.courseKey.equals(courseKey) &
                tbl.studentId.isIn(assignedStudentIds))
            ..orderBy([
              (tbl) => OrderingTerm(
                    expression: tbl.createdAt,
                    mode: OrderingMode.desc,
                  )
            ]))
          .get();
      scopeTemplates.addAll(studentCourseTemplates);
    }

    final dedupedByScope = <String, PromptTemplate>{};
    for (final template in scopeTemplates) {
      final key = [
        template.promptName,
        template.courseKey ?? '',
        template.studentId?.toString() ?? '',
      ].join('::');
      dedupedByScope.putIfAbsent(key, () => template);
    }

    final payload = <Map<String, dynamic>>[];
    for (final template in dedupedByScope.values) {
      final scope = _promptTemplateScope(template);
      final student = await _studentForScope(
        studentId: template.studentId,
        scope: scope,
        studentCache: studentCache,
      );
      _requireValidPromptTemplate(
        promptName: template.promptName,
        content: template.content,
        scope: scope,
        source: 'upload',
      );
      final timestampStrings =
          timestampMetadata[PromptBundleTimestampMetadata.promptTemplateKey(
        promptName: template.promptName,
        scope: scope,
        studentRemoteUserId: student?.remoteUserId,
      )];
      payload.add({
        'prompt_name': template.promptName,
        'scope': scope,
        'content': template.content,
        'student_remote_user_id': student?.remoteUserId,
        'student_username': student?.username,
        'created_at': PromptBundleTimestampMetadata.resolveTimestampString(
          raw: timestampStrings?['created_at'],
          actual: template.createdAt.toUtc(),
        ),
      });
    }
    return payload;
  }

  Future<List<Map<String, dynamic>>> _buildProfilesPayload({
    required User teacher,
    required String courseKey,
    required Set<int> assignedStudentIds,
    required Map<int, User?> studentCache,
    required Map<String, Map<String, String>> timestampMetadata,
  }) async {
    final payload = <Map<String, dynamic>>[];
    final systemProfile = await _db.getStudentPromptProfile(
      teacherId: teacher.id,
      courseKey: null,
      studentId: null,
    );
    if (systemProfile != null) {
      payload.add(
        _profileToJson(
          systemProfile,
          scope: 'teacher',
          timestampStrings:
              timestampMetadata[PromptBundleTimestampMetadata.profileKey(
            scope: 'teacher',
            studentRemoteUserId: null,
          )],
        ),
      );
    }

    for (final studentId in assignedStudentIds) {
      final profile = await _db.getStudentPromptProfile(
        teacherId: teacher.id,
        courseKey: null,
        studentId: studentId,
      );
      if (profile == null) {
        continue;
      }
      final student = await _requireStudentForMetadata(
        studentId: studentId,
        scope: 'student_global',
        studentCache: studentCache,
      );
      payload.add(
        _profileToJson(
          profile,
          scope: 'student_global',
          studentRemoteUserId: student.remoteUserId,
          studentUsername: student.username,
          timestampStrings:
              timestampMetadata[PromptBundleTimestampMetadata.profileKey(
            scope: 'student_global',
            studentRemoteUserId: student.remoteUserId,
          )],
        ),
      );
    }

    final courseProfile = await _db.getStudentPromptProfile(
      teacherId: teacher.id,
      courseKey: courseKey,
      studentId: null,
    );
    if (courseProfile != null) {
      payload.add(
        _profileToJson(
          courseProfile,
          scope: 'course',
          timestampStrings:
              timestampMetadata[PromptBundleTimestampMetadata.profileKey(
            scope: 'course',
            studentRemoteUserId: null,
          )],
        ),
      );
    }

    for (final studentId in assignedStudentIds) {
      final profile = await _db.getStudentPromptProfile(
        teacherId: teacher.id,
        courseKey: courseKey,
        studentId: studentId,
      );
      if (profile == null) {
        continue;
      }
      final student = await _requireStudentForMetadata(
        studentId: studentId,
        scope: 'student_course',
        studentCache: studentCache,
      );
      payload.add(
        _profileToJson(
          profile,
          scope: 'student_course',
          studentRemoteUserId: student.remoteUserId,
          studentUsername: student.username,
          timestampStrings:
              timestampMetadata[PromptBundleTimestampMetadata.profileKey(
            scope: 'student_course',
            studentRemoteUserId: student.remoteUserId,
          )],
        ),
      );
    }
    return payload;
  }

  Future<List<Map<String, dynamic>>> _buildPassConfigsPayload({
    required int courseVersionId,
    required Set<int> assignedStudentIds,
    required Map<int, User?> studentCache,
    required Map<String, Map<String, String>> timestampMetadata,
  }) async {
    if (assignedStudentIds.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final passConfigs = await (_db.select(_db.studentPassConfigs)
          ..where((tbl) =>
              tbl.courseVersionId.equals(courseVersionId) &
              tbl.studentId.isIn(assignedStudentIds))
          ..orderBy([
            (tbl) => OrderingTerm(
                  expression: tbl.updatedAt,
                  mode: OrderingMode.desc,
                ),
            (tbl) => OrderingTerm(
                  expression: tbl.createdAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();
    final payload = <Map<String, dynamic>>[];
    for (final config in passConfigs) {
      final student = await _requireStudentForMetadata(
        studentId: config.studentId,
        scope: 'pass_config',
        studentCache: studentCache,
      );
      payload.add({
        'student_remote_user_id': student.remoteUserId,
        'student_username': student.username,
        'easy_weight': config.easyWeight,
        'medium_weight': config.mediumWeight,
        'hard_weight': config.hardWeight,
        'pass_threshold': config.passThreshold,
        'created_at': PromptBundleTimestampMetadata.resolveTimestampString(
          raw: timestampMetadata[PromptBundleTimestampMetadata.passConfigKey(
            studentRemoteUserId: student.remoteUserId,
          )]?['created_at'],
          actual: config.createdAt.toUtc(),
        ),
        'updated_at': PromptBundleTimestampMetadata.resolveTimestampString(
          raw: timestampMetadata[PromptBundleTimestampMetadata.passConfigKey(
            studentRemoteUserId: student.remoteUserId,
          )]?['updated_at'],
          actual: (config.updatedAt ?? config.createdAt).toUtc(),
        ),
      });
    }
    return payload;
  }

  String _promptTemplateScope(PromptTemplate template) {
    if (template.courseKey == null && template.studentId != null) {
      return 'student_global';
    }
    if (template.courseKey != null && template.studentId == null) {
      return 'course';
    }
    if (template.courseKey != null && template.studentId != null) {
      return 'student_course';
    }
    return 'teacher';
  }

  Future<User?> _studentForScope({
    required int? studentId,
    required String scope,
    required Map<int, User?> studentCache,
  }) async {
    if (studentId == null) {
      return null;
    }
    return _requireStudentForMetadata(
      studentId: studentId,
      scope: scope,
      studentCache: studentCache,
    );
  }

  Future<User> _requireStudentForMetadata({
    required int studentId,
    required String scope,
    required Map<int, User?> studentCache,
  }) async {
    var student = studentCache[studentId];
    if (!studentCache.containsKey(studentId)) {
      student = await _db.getUserById(studentId);
      studentCache[studentId] = student;
    }
    final remoteUserId = student?.remoteUserId;
    if (student == null || remoteUserId == null || remoteUserId <= 0) {
      throw StateError(
        'Cannot upload $scope prompt metadata for local student $studentId '
        'without a synced remote student id.',
      );
    }
    return student;
  }

  void _requireValidPromptTemplate({
    required String promptName,
    required String content,
    required String scope,
    required String source,
  }) {
    final validation = _promptValidator.validate(
      promptName: promptName,
      content: content,
      allowMissingRequired: false,
    );
    if (validation.isValid) {
      return;
    }
    throw StateError(
      'Invalid $source prompt metadata for "$promptName" scope '
      '"$scope". missing=${validation.missingVariables.join(',')} '
      'unknown=${validation.unknownVariables.join(',')} '
      'invalid=${validation.invalidVariables.join(',')}',
    );
  }

  Map<String, dynamic> _profileToJson(
    StudentPromptProfile profile, {
    required String scope,
    int? studentRemoteUserId,
    String? studentUsername,
    Map<String, String>? timestampStrings,
  }) {
    return {
      'scope': scope,
      'student_remote_user_id': studentRemoteUserId,
      'student_username': studentUsername,
      'grade_level': profile.gradeLevel,
      'reading_level': profile.readingLevel,
      'preferred_language': profile.preferredLanguage,
      'interests': profile.interests,
      'preferred_tone': profile.preferredTone,
      'preferred_pace': profile.preferredPace,
      'preferred_format': profile.preferredFormat,
      'support_notes': profile.supportNotes,
      'created_at': PromptBundleTimestampMetadata.resolveTimestampString(
        raw: timestampStrings?['created_at'],
        actual: profile.createdAt.toUtc(),
      ),
      'updated_at': PromptBundleTimestampMetadata.resolveTimestampString(
        raw: timestampStrings?['updated_at'],
        actual: (profile.updatedAt ?? profile.createdAt).toUtc(),
      ),
    };
  }
}
