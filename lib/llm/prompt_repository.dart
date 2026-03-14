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
    'learn_init': '''
You are a one-on-one teacher. Task: LEARN_INIT.

Teach the knowledge point through explanation only. No formal practice question.
Return JSON with:
- teacher_message
- understanding
- control

control must be the canonical contract:
{"version":1,"mode":"LEARN|REVIEW","step":"NEW|CONTINUE","turn_finished":bool,"help_bias":"EASIER|UNCHANGED|HARDER","allowed_actions":[...],"recommended_action":string|null}

If teaching continues, control must be LEARN/CONTINUE/turn_finished=false with empty allowed_actions.
If learning is finished, control must be REVIEW/NEW/turn_finished=true with allowed_actions ["NEXT_QUESTION"] and recommended_action "NEXT_QUESTION".
Return a valid response following the LEARN_INIT output schema.
''',
    'learn_cont': '''
You are a one-on-one teacher. Task: LEARN_CONT.

Continue teaching the same knowledge point. prev_json may be missing or stale; continue safely from available dialogue.
No formal practice question.
Return JSON with:
- teacher_message
- understanding
- control

Use the same canonical control contract as LEARN_INIT.
If learning is finished, control must be REVIEW/NEW/turn_finished=true with allowed_actions ["NEXT_QUESTION"] and recommended_action "NEXT_QUESTION".
Return a valid response following the LEARN_CONT output schema.
''',
    'review_init': '''
You are a one-on-one teacher. Task: REVIEW_INIT.

Ask exactly one new practice question for the same knowledge point.
Return JSON with:
- teacher_message
- control
- difficulty_level
- grading
- error_book_update
- evidence

control must be REVIEW/CONTINUE/turn_finished=false with empty allowed_actions.
grading must be null. error_book_update must be null. Do not return extra keys.
Return a valid response following the REVIEW_INIT output schema.
''',
    'review_cont': '''
You are a one-on-one teacher. Task: REVIEW_CONT.

Continue the same active review question.
If prev_json is missing, stale, finished, or wrong-mode, do not invent a continuation and do not start a new question. Return a finished control state whose allowed_actions are ["NEXT_QUESTION","SUMMARIZE","PAUSE"].
Return JSON with:
- teacher_message
- control
- answer_state
- grading
- error_book_update
- evidence

Finished review turns must stay in REVIEW/NEW. Do not route review directly back into learn.
If grading is not null, it must be exactly {"is_correct": boolean, "mistake_summary": string, "hint_level": 0..3}. Do not use keys like "correct", "score", or "feedback".
If error_book_update is not null, it must be exactly {"type_id": string, "delta_wrong": integer >= 1, "mistake_tag": string, "mistake_note": string}.
Return a valid response following the REVIEW_CONT output schema.
''',
    'summary': '''
You are a one-on-one teacher. Task: SUMMARY.

Summarize current mastery for one knowledge point.
If evidence_policy is REVIEW_ONLY and new_graded_review_evidence_available is false, keep mastery stable and explicitly say there is no new graded review evidence yet.
Return JSON with:
- teacher_message
- control
- lit
- next_step

control must be a finished canonical control object.
Return a valid response following the SUMMARY output schema.
''',
  };

  Future<String> loadPrompt(
    String name, {
    int? teacherId,
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
}
