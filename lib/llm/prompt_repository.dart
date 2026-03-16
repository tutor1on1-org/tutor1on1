import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../db/app_database.dart';

class PromptRepository {
  PromptRepository({AppDatabase? db, AssetBundle? assetBundle})
      : _db = db,
        _assetBundle = assetBundle ?? rootBundle;

  final AppDatabase? _db;
  final AssetBundle _assetBundle;
  final Map<String, String> _promptCache = {};
  final Map<String, String> _systemPromptCache = {};
  final Map<String, Map<String, dynamic>> _schemaCache = {};
  final Map<String, String> _textbookCache = {};
  static const Set<String> _bundledOnlyPromptNames = <String>{
    'learn',
    'review',
  };
  static const Map<String, String> _emergencyPromptFallbacks = <String, String>{
    'learn': '''
You are a one-on-one teacher. Task: LEARN.

Teach the knowledge point through explanation only. No formal practice question.
Return JSON with:
- text
- difficulty
- mistakes
- next_action

Return a valid response following the LEARN output schema.
''',
    'review': '''
You are a one-on-one teacher. Task: REVIEW.

Keep one active review question at a time.
Return JSON with:
- text
- difficulty
- mistakes
- next_action
- finished

Return a valid response following the REVIEW output schema.
''',
  };

  Future<String> loadPrompt(
    String name, {
    int? teacherId,
    String? courseKey,
    int? studentId,
  }) async {
    if (_usesBundledOnlyPrompt(name)) {
      return _loadBundledSystemPrompt(name);
    }
    final normalizedCourseKey = _normalizeCourseKey(courseKey);
    final cacheKey = [
      teacherId?.toString() ?? 'default',
      normalizedCourseKey ?? 'default',
      studentId?.toString() ?? 'default',
      name,
    ].join('::');
    if (_promptCache.containsKey(cacheKey)) {
      return _promptCache[cacheKey]!;
    }

    final systemPrompt = await loadResolvedSystemPrompt(
      name,
      teacherId: teacherId,
    );
    final courseAppend = await _loadAppendPrompt(
      name,
      teacherId: teacherId,
      courseKey: normalizedCourseKey,
    );
    final studentAppend = studentId == null
        ? ''
        : await _loadAppendPrompt(
            name,
            teacherId: teacherId,
            courseKey: normalizedCourseKey,
            studentId: studentId,
          );
    final combined = _combinePrompts([
      systemPrompt,
      courseAppend,
      studentAppend,
    ]);
    _promptCache[cacheKey] = combined;
    return combined;
  }

  Future<String> loadAppendPrompt(
    String name, {
    required int teacherId,
    String? courseKey,
    int? studentId,
  }) async {
    if (_usesBundledOnlyPrompt(name)) {
      return '';
    }
    final normalizedCourseKey = _normalizeCourseKey(courseKey);
    return _loadAppendPrompt(
      name,
      teacherId: teacherId,
      courseKey: normalizedCourseKey,
      studentId: studentId,
    );
  }

  Future<String> buildPromptPreview({
    required String name,
    required int teacherId,
    String? courseKey,
    int? studentId,
    String? courseAppendOverride,
    String? studentAppendOverride,
    bool includeSystem = true,
  }) async {
    if (_usesBundledOnlyPrompt(name)) {
      return includeSystem ? _loadBundledSystemPrompt(name) : '';
    }
    final normalizedCourseKey = _normalizeCourseKey(courseKey);
    final systemPrompt = includeSystem
        ? await loadResolvedSystemPrompt(name, teacherId: teacherId)
        : '';
    final courseAppend = courseAppendOverride ??
        await _loadAppendPrompt(
          name,
          teacherId: teacherId,
          courseKey: normalizedCourseKey,
        );
    String studentAppend = '';
    if (studentId != null) {
      studentAppend = studentAppendOverride ??
          await _loadAppendPrompt(
            name,
            teacherId: teacherId,
            courseKey: normalizedCourseKey,
            studentId: studentId,
          );
    }
    return _combinePrompts([systemPrompt, courseAppend, studentAppend]);
  }

  Future<void> ensureAssignmentPrompts({
    required int teacherId,
    required int studentId,
    required int courseVersionId,
  }) async {
    // Append prompts default to empty; no need to pre-seed per-assignment rows.
    return;
  }

  Future<void> backfillAssignmentPrompts() async {
    // Append prompts default to empty; no backfill required.
    return;
  }

  Future<String> loadBundledSystemPrompt(String name) async {
    return _loadBundledSystemPrompt(name);
  }

  Future<String> loadResolvedSystemPrompt(
    String name, {
    required int? teacherId,
  }) async {
    if (_usesBundledOnlyPrompt(name)) {
      return _loadBundledSystemPrompt(name);
    }
    final override = await _loadSystemPromptOverride(
      name,
      teacherId: teacherId,
    );
    if (override != null) {
      return override;
    }
    return _loadBundledSystemPrompt(name);
  }

  void invalidatePromptCache({String? promptName}) {
    if (promptName == null) {
      _promptCache.clear();
      return;
    }
    _promptCache.removeWhere((key, _) => key.endsWith('::$promptName'));
  }

  Future<String> _loadBundledSystemPrompt(String name) async {
    if (_systemPromptCache.containsKey(name)) {
      return _systemPromptCache[name]!;
    }
    final candidates = [
      'assets/prompts/$name.prompt.txt',
      'assets/prompts/$name.txt',
    ];
    Object? lastError;
    for (final path in candidates) {
      try {
        final content = await _assetBundle.loadString(path);
        _systemPromptCache[name] = content;
        return content;
      } catch (error) {
        lastError = error;
      }
    }
    final fallback = _emergencyPromptFallbacks[name];
    if (fallback != null) {
      debugPrint(
        'PromptRepository: missing bundled asset for "$name". '
        'Using emergency fallback prompt. lastError=$lastError',
      );
      _systemPromptCache[name] = fallback;
      return fallback;
    }
    throw StateError(
      'Prompt not found for "$name". Last error: $lastError',
    );
  }

  Future<String?> _loadSystemPromptOverride(
    String name, {
    required int? teacherId,
  }) async {
    final db = _db;
    if (db == null || teacherId == null) {
      return null;
    }
    final override = await db.getActivePromptTemplate(
      teacherId: teacherId,
      promptName: name,
      courseKey: null,
      studentId: null,
    );
    return override?.content;
  }

  String? _normalizeCourseKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return p.normalize(trimmed);
  }

  Future<String> _loadAppendPrompt(
    String name, {
    required int? teacherId,
    required String? courseKey,
    int? studentId,
  }) async {
    if (_usesBundledOnlyPrompt(name)) {
      return '';
    }
    final db = _db;
    if (db == null || teacherId == null || courseKey == null) {
      return '';
    }
    final append = await db.getActivePromptTemplate(
      teacherId: teacherId,
      promptName: name,
      courseKey: courseKey,
      studentId: studentId,
    );
    return (append?.content ?? '').trim();
  }

  String _combinePrompts(List<String?> parts) {
    final cleaned = parts
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (cleaned.isEmpty) {
      return '';
    }
    return cleaned.join('\n\n');
  }

  Future<Map<String, dynamic>> loadSchema(String name) async {
    if (_schemaCache.containsKey(name)) {
      return _schemaCache[name]!;
    }
    final content =
        await _assetBundle.loadString('assets/schemas/$name.schema.json');
    final jsonMap = jsonDecode(content) as Map<String, dynamic>;
    _schemaCache[name] = jsonMap;
    return jsonMap;
  }

  Future<String> loadTextbook(String filename) async {
    if (_textbookCache.containsKey(filename)) {
      return _textbookCache[filename]!;
    }
    final content = await _assetBundle.loadString('assets/textbooks/$filename');
    _textbookCache[filename] = content;
    return content;
  }

  bool _usesBundledOnlyPrompt(String name) {
    return _bundledOnlyPromptNames.contains(name.trim());
  }
}
