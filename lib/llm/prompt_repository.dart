import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../db/app_database.dart';

class PromptRepository {
  PromptRepository({AppDatabase? db}) : _db = db;

  final AppDatabase? _db;
  final Map<String, String> _promptCache = {};
  final Map<String, Map<String, dynamic>> _schemaCache = {};
  final Map<String, String> _textbookCache = {};

  Future<String> loadPrompt(
    String name, {
    int? teacherId,
    String? courseKey,
    int? studentId,
  }) async {
    final db = _db;
    final normalizedCourseKey = _normalizeCourseKey(courseKey);
    if (teacherId != null &&
        db != null &&
        normalizedCourseKey != null &&
        studentId != null) {
      final override = await db.getActivePromptTemplate(
        teacherId: teacherId,
        promptName: name,
        courseKey: normalizedCourseKey,
        studentId: studentId,
      );
      if (override != null) {
        return override.content;
      }
    }
    if (teacherId != null && db != null) {
      final teacherDefault = await db.getActivePromptTemplate(
        teacherId: teacherId,
        promptName: name,
      );
      if (teacherDefault != null) {
        return teacherDefault.content;
      }
    }
    final cacheKey = [
      teacherId?.toString() ?? 'default',
      normalizedCourseKey ?? 'default',
      studentId?.toString() ?? 'default',
      name,
    ].join('::');
    if (_promptCache.containsKey(cacheKey)) {
      return _promptCache[cacheKey]!;
    }
    final teacherDefault = await _loadTeacherDefaultPrompt(
      name,
      teacherId: teacherId,
    );
    _promptCache[cacheKey] = teacherDefault;
    return teacherDefault;
  }

  Future<void> ensureAssignmentPrompts({
    required int teacherId,
    required int studentId,
    required int courseVersionId,
  }) async {
    final db = _db;
    if (db == null) {
      return;
    }
    final course = await db.getCourseVersionById(courseVersionId);
    final courseKey = _normalizeCourseKey(course?.sourcePath);
    if (courseKey == null) {
      return;
    }
    for (final promptName in const ['learn', 'review', 'summarize']) {
      final existing = await db.getActivePromptTemplate(
        teacherId: teacherId,
        promptName: promptName,
        courseKey: courseKey,
        studentId: studentId,
      );
      if (existing != null) {
        continue;
      }
      try {
        final defaultContent = await loadPrompt(
          promptName,
          teacherId: teacherId,
        );
        await db.insertPromptTemplate(
          teacherId: teacherId,
          promptName: promptName,
          content: defaultContent,
          courseKey: courseKey,
          studentId: studentId,
        );
      } catch (_) {
        // Ignore missing defaults to avoid blocking course assignment.
      }
    }
  }

  Future<void> backfillAssignmentPrompts() async {
    final db = _db;
    if (db == null) {
      return;
    }
    final assignments = await db.select(db.studentCourseAssignments).get();
    for (final assignment in assignments) {
      final course = await db.getCourseVersionById(assignment.courseVersionId);
      if (course == null) {
        continue;
      }
      try {
        await ensureAssignmentPrompts(
          teacherId: course.teacherId,
          studentId: assignment.studentId,
          courseVersionId: assignment.courseVersionId,
        );
      } catch (_) {
        // Best-effort backfill.
      }
    }
  }

  Future<String> _loadTeacherDefaultPrompt(
    String name, {
    int? teacherId,
  }) async {
    if (teacherId != null && _db != null) {
      final teacher = await _db!.getUserById(teacherId);
      final teacherName = teacher?.username;
      if (teacherName != null && teacherName.trim().isNotEmpty) {
        final teacherPath =
            'assets/teachers/$teacherName/prompts/$name.txt';
        try {
          return await rootBundle.loadString(teacherPath);
        } catch (_) {
          // Try shared defaults.
        }
      }
    }
    return rootBundle.loadString('assets/prompts/$name.txt');
  }

  String? _normalizeCourseKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return p.normalize(trimmed);
  }

  Future<Map<String, dynamic>> loadSchema(String name) async {
    if (_schemaCache.containsKey(name)) {
      return _schemaCache[name]!;
    }
    final content =
        await rootBundle.loadString('assets/schemas/$name.schema.json');
    final jsonMap = jsonDecode(content) as Map<String, dynamic>;
    _schemaCache[name] = jsonMap;
    return jsonMap;
  }

  Future<String> loadTextbook(String filename) async {
    if (_textbookCache.containsKey(filename)) {
      return _textbookCache[filename]!;
    }
    final content = await rootBundle.loadString('assets/textbooks/$filename');
    _textbookCache[filename] = content;
    return content;
  }
}
