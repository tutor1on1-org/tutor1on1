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
  static const Map<String, String> _emergencyPromptFallbacks = <String, String>{
    'learn': '''
You are a one-on-one teacher. Task: LEARN.

Use conversation_history to decide what the student needs now.
Explain the current knowledge point, answer the student's latest need, or briefly correct/explain if the student seems confused.

Inputs:
- kp_title: {{kp_title}}
- kp_description: {{kp_description}}
- lesson_content: {{lesson_content}}
- conversation_history: {{conversation_history}}
- student_context: {{student_context}}
- error_book_summary: {{error_book_summary}}

Output only the student-visible text.

Rules:
- Keep it concise and plain. Usually less than 200 words unless necessary.
- Use lesson_content if available; otherwise use kp_description.
- Do not repeat what was already clearly understood.
- If the student made a mistake, explain the issue briefly, then continue with a simpler explanation or one concrete example.
- Only ask a clarification question if the student's need cannot be understood from conversation_history.
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
    return loadResolvedScopedPrompt(
      name,
      teacherId: teacherId,
      courseKey: courseKey,
      studentId: studentId,
    );
  }

  Future<String> loadResolvedScopedPrompt(
    String name, {
    required int? teacherId,
    String? courseKey,
    int? studentId,
  }) async {
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

    final db = _db;
    if (db != null && teacherId != null) {
      final scopes = _promptOverrideLookupScopes(
        courseKey: normalizedCourseKey,
        studentId: studentId,
      );
      for (final scope in scopes) {
        final override = await _loadPromptOverride(
          name,
          teacherId: teacherId,
          courseKey: scope.courseKey,
          studentId: scope.studentId,
        );
        if (override != null) {
          _promptCache[cacheKey] = override;
          return override;
        }
      }
    }

    final bundled = await _loadBundledSystemPrompt(name);
    _promptCache[cacheKey] = bundled;
    return bundled;
  }

  Future<void> ensureAssignmentPrompts({
    required int teacherId,
    required int studentId,
    required int courseVersionId,
  }) async {
    // Prompt scopes inherit from their nearest active parent override.
    return;
  }

  Future<void> backfillAssignmentPrompts() async {
    // Prompt scopes inherit from their nearest active parent override.
    return;
  }

  Future<String> loadBundledSystemPrompt(String name) async {
    return _loadBundledSystemPrompt(name);
  }

  Future<String> loadResolvedSystemPrompt(
    String name, {
    required int? teacherId,
  }) async {
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

  List<_PromptOverrideScope> _promptOverrideLookupScopes({
    required String? courseKey,
    required int? studentId,
  }) {
    final scopes = <_PromptOverrideScope>[];
    void add(String? scopeCourseKey, int? scopeStudentId) {
      final scope = _PromptOverrideScope(scopeCourseKey, scopeStudentId);
      if (!scopes.contains(scope)) {
        scopes.add(scope);
      }
    }

    add(courseKey, studentId);
    if (studentId != null) {
      add(null, studentId);
    }
    if (courseKey != null) {
      add(courseKey, null);
    }
    add(null, null);
    return scopes;
  }

  String? _normalizeCourseKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return p.normalize(trimmed);
  }

  Future<String?> _loadPromptOverride(
    String name, {
    required int? teacherId,
    required String? courseKey,
    int? studentId,
  }) async {
    final db = _db;
    if (db == null || teacherId == null) {
      return '';
    }
    final override = await db.getActivePromptTemplate(
      teacherId: teacherId,
      promptName: name,
      courseKey: courseKey,
      studentId: studentId,
    );
    return override?.content.trim();
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
}

class _PromptOverrideScope {
  const _PromptOverrideScope(this.courseKey, this.studentId);

  final String? courseKey;
  final int? studentId;

  @override
  bool operator ==(Object other) {
    return other is _PromptOverrideScope &&
        other.courseKey == courseKey &&
        other.studentId == studentId;
  }

  @override
  int get hashCode => Object.hash(courseKey, studentId);
}
