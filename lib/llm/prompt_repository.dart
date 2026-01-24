import 'dart:convert';

import 'package:flutter/services.dart';

import '../db/app_database.dart';

class PromptRepository {
  PromptRepository({AppDatabase? db}) : _db = db;

  final AppDatabase? _db;
  final Map<String, String> _promptCache = {};
  final Map<String, Map<String, dynamic>> _schemaCache = {};
  final Map<String, String> _textbookCache = {};

  Future<String> loadPrompt(String name, {int? teacherId}) async {
    final db = _db;
    if (teacherId != null && db != null) {
      final override = await db.getActivePromptTemplate(
        teacherId: teacherId,
        promptName: name,
      );
      if (override != null) {
        return override.content;
      }
    }
    final cacheKey = teacherId == null ? name : '$teacherId::$name';
    if (_promptCache.containsKey(cacheKey)) {
      return _promptCache[cacheKey]!;
    }
    if (teacherId != null && db != null) {
      final teacher = await db.getUserById(teacherId);
      final teacherName = teacher?.username;
      if (teacherName != null && teacherName.trim().isNotEmpty) {
        final teacherPath =
            'assets/teachers/$teacherName/prompts/$name.txt';
        try {
          final content = await rootBundle.loadString(teacherPath);
          _promptCache[cacheKey] = content;
          return content;
        } catch (_) {
          // Fall back to default prompts.
        }
      }
    }
    final content = await rootBundle.loadString('assets/prompts/$name.txt');
    _promptCache[cacheKey] = content;
    return content;
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
