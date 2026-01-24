import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../db/app_database.dart';
import '../llm/llm_models.dart';
import '../llm/llm_service.dart';
import '../llm/prompt_renderer.dart';
import '../llm/prompt_repository.dart';

class SummarizeResult {
  SummarizeResult({
    required this.success,
    required this.message,
    this.lit,
    this.summaryText,
    this.masterLevel,
  });

  final bool success;
  final String message;
  final bool? lit;
  final String? summaryText;
  final String? masterLevel;
}

class SessionService {
  SessionService(
    this._db,
    this._llmService,
    this._promptRepository,
  );

  final AppDatabase _db;
  final LlmService _llmService;
  final PromptRepository _promptRepository;
  final PromptRenderer _renderer = PromptRenderer();

  Future<int> startSession({
    required int studentId,
    required int courseVersionId,
    required String kpKey,
    String? title,
  }) {
    return _createSession(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: kpKey,
      title: title,
    );
  }

  Future<int> _createSession({
    required int studentId,
    required int courseVersionId,
    required String kpKey,
    String? title,
  }) async {
    final resolvedTitle = await _resolveSessionTitle(
      kpKey: kpKey,
      title: title,
      courseVersionId: courseVersionId,
    );
    return _db.into(_db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: kpKey,
            title: Value(resolvedTitle),
            status: const Value('active'),
          ),
        );
  }

  Future<String> _resolveSessionTitle({
    required String kpKey,
    required int courseVersionId,
    String? title,
  }) async {
    final provided = title?.trim();
    if (provided != null && provided.isNotEmpty) {
      return provided;
    }
    final node = await _db.getCourseNodeByKey(courseVersionId, kpKey);
    final nodeName = node?.title.trim();
    if (nodeName != null && nodeName.isNotEmpty) {
      return '$kpKey: $nodeName';
    }
    return kpKey;
  }

  Future<void> closeSession(int sessionId) async {
    await (_db.update(_db.chatSessions)..where((tbl) => tbl.id.equals(sessionId)))
        .write(
      ChatSessionsCompanion(
        endedAt: Value(DateTime.now()),
        status: const Value('active'),
      ),
    );
  }

  Future<LlmRequestHandle> startTutorAction({
    required int sessionId,
    required String mode,
    required String studentInput,
    required CourseVersion courseVersion,
    required CourseNode node,
    String? modelOverride,
  }) async {
    if (studentInput.trim().isNotEmpty) {
      await _db.into(_db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: sessionId,
              role: 'user',
              content: studentInput.trim(),
              action: Value(mode),
            ),
          );
    }

    final session = await _db.getSession(sessionId);
    final progress = session == null
        ? null
        : await _db.getProgress(
            studentId: session.studentId,
            courseVersionId: courseVersion.id,
            kpKey: node.kpKey,
          );
    final messages = await _db.getMessagesForSession(sessionId);
    final history = _buildHistory(messages);

    final template = await _promptRepository.loadPrompt(
      mode,
      teacherId: courseVersion.teacherId,
    );
    var rendered = _renderer.render(template, {
      'subject': courseVersion.subject,
      'course_version_id': courseVersion.id,
      'kp_key': node.kpKey,
      'kp_title': node.title,
      'kp_description': node.description,
      'conversation_history': history,
      'student_input': studentInput.trim(),
      'student_summary': progress?.summaryText ?? session?.summaryText ?? '',
    });
    final hasAssistant = messages.any((message) => message.role == 'assistant');
    if (mode == 'learn' && !hasAssistant) {
      final lectureText = await _loadLectureText(
        courseVersion: courseVersion,
        kpKey: node.kpKey,
      );
      rendered = _appendLecture(rendered, lectureText);
    } else if (mode == 'review') {
      final level = _normalizeLevel(progress?.questionLevel) ?? 'easy';
      final questionsText = await _loadQuestionsText(
        courseVersion: courseVersion,
        kpKey: node.kpKey,
        level: level,
      );
      rendered = _appendQuestionBank(rendered, questionsText, level);
    }

    final handle = _llmService.startCall(
      promptName: mode,
      renderedPrompt: rendered,
      modelOverride: modelOverride,
      context: LlmCallContext(
        teacherId: courseVersion.teacherId,
        studentId: session?.studentId,
        courseVersionId: courseVersion.id,
        sessionId: sessionId,
        kpKey: node.kpKey,
        action: mode,
      ),
    );
    final future = handle.future.then((result) async {
      if (result.responseText.trim().isEmpty) {
        throw StateError('LLM returned an empty response.');
      }
      await _db.into(_db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: sessionId,
              role: 'assistant',
              content: result.responseText,
              action: Value(mode),
            ),
          );
      return result;
    });
    return LlmRequestHandle(future: future, cancel: handle.cancel);
  }

  Future<RequestHandle<SummarizeResult>> startSummarize({
    required int sessionId,
    required CourseVersion courseVersion,
    required CourseNode node,
    String? modelOverride,
  }) async {
    final session = await _db.getSession(sessionId);
    final progress = session == null
        ? null
        : await _db.getProgress(
            studentId: session.studentId,
            courseVersionId: courseVersion.id,
            kpKey: node.kpKey,
          );
    final messages = await _db.getMessagesForSession(sessionId);
    final history = _buildHistory(messages);
    final template = await _promptRepository.loadPrompt(
      'summarize',
      teacherId: courseVersion.teacherId,
    );
    final schema = await _promptRepository.loadSchema('summarize');
    final rendered = _renderer.render(template, {
      'subject': courseVersion.subject,
      'course_version_id': courseVersion.id,
      'kp_key': node.kpKey,
      'kp_title': node.title,
      'kp_description': node.description,
      'conversation_history': history,
      'student_summary': progress?.summaryText ?? session?.summaryText ?? '',
    });

    final handle = _llmService.startCall(
      promptName: 'summarize',
      renderedPrompt: rendered,
      schemaMap: schema,
      modelOverride: modelOverride,
      context: LlmCallContext(
        teacherId: courseVersion.teacherId,
        studentId: session?.studentId,
        courseVersionId: courseVersion.id,
        sessionId: sessionId,
        kpKey: node.kpKey,
        action: 'summarize',
      ),
    );
    final future = handle.future.then((result) async {
      if (result.responseText.trim().isEmpty) {
        throw StateError('LLM returned an empty response.');
      }

    final parsed = _tryDecodeJsonObject(result.responseText);
    final summaryText = parsed?['summary_text'];
    final lit = parsed?['lit'];
    final masterLevel = _normalizeLevel(parsed?['master_level']);
    final summary = summaryText is String && summaryText.trim().isNotEmpty
        ? summaryText
        : result.responseText;
    final summaryValid =
        summaryText is String && lit is bool && masterLevel != null;
    final rawResponse = summaryValid ? null : result.responseText;

    await _db.transaction(() async {
      final studentId = session?.studentId;
      if (studentId != null) {
        await _db.upsertProgressSummary(
          studentId: studentId,
          courseVersionId: courseVersion.id,
          kpKey: node.kpKey,
          summaryText: summary,
          summaryRawResponse: rawResponse,
          summaryValid: summaryValid,
          summaryLit: lit is bool ? lit : null,
          questionLevel: masterLevel,
        );
      }

        await (_db.update(_db.chatSessions)
              ..where((tbl) => tbl.id.equals(sessionId)))
            .write(
          ChatSessionsCompanion(
            summaryText: Value(summary),
            summaryLit: Value(lit is bool ? lit : null),
            summaryRawResponse: Value(rawResponse),
            summaryValid: Value(summaryValid),
            status: const Value('active'),
          ),
        );

        await _db.into(_db.chatMessages).insert(
              ChatMessagesCompanion.insert(
                sessionId: sessionId,
                role: 'assistant',
                content: summary,
                action: const Value('summary'),
              ),
            );
      });

      return SummarizeResult(
        success: true,
        message: summaryValid ? 'Summary stored.' : 'Summary saved (unparsed).',
        lit: lit is bool ? lit : null,
        summaryText: summary,
        masterLevel: masterLevel,
      );
    });

    return RequestHandle<SummarizeResult>(
      future: future,
      cancel: handle.cancel,
    );
  }

  String _buildHistory(List<ChatMessage> messages) {
    final buffer = StringBuffer();
    for (final message in messages) {
      buffer.writeln(
        '[${message.createdAt.toIso8601String()}] ${message.role}: ${message.content}',
      );
    }
    return buffer.toString().trim();
  }

  Map<String, dynamic>? _tryDecodeJsonObject(String input) {
    final start = input.indexOf('{');
    final end = input.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      return null;
    }
    try {
      final decoded = jsonDecode(input.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _normalizeLevel(Object? value) {
    if (value is! String) {
      return null;
    }
    final normalized = value.trim().toLowerCase();
    if (normalized == 'easy' || normalized == 'medium' || normalized == 'hard') {
      return normalized;
    }
    return null;
  }

  Future<String> _loadLectureText({
    required CourseVersion courseVersion,
    required String kpKey,
  }) async {
    final basePath = _requireCourseBasePath(courseVersion);
    final path = p.join(basePath, '${kpKey}_lecture.txt');
    final legacy = p.join(basePath, kpKey, 'lecture.txt');
    final file = File(path).existsSync() ? File(path) : File(legacy);
    if (!file.existsSync()) {
      throw StateError('Missing lecture file: $path');
    }
    return file.readAsString(encoding: utf8);
  }

  Future<String> _loadQuestionsText({
    required CourseVersion courseVersion,
    required String kpKey,
    required String level,
  }) async {
    final basePath = _requireCourseBasePath(courseVersion);
    final path = p.join(basePath, '${kpKey}_$level.txt');
    final legacy = p.join(basePath, kpKey, level, 'questions.txt');
    final file = File(path).existsSync() ? File(path) : File(legacy);
    if (!file.existsSync()) {
      return '';
    }
    return file.readAsString(encoding: utf8);
  }

  String _requireCourseBasePath(CourseVersion courseVersion) {
    final basePath = courseVersion.sourcePath;
    if (basePath == null || basePath.trim().isEmpty) {
      throw StateError('Course not loaded. Load the folder first.');
    }
    return basePath;
  }

  String _appendLecture(String rendered, String lectureText) {
    final trimmed = lectureText.trim();
    if (trimmed.isEmpty) {
      return rendered;
    }
    return '$rendered\n\nLecture content (use once):\n$trimmed';
  }

  String _appendQuestionBank(
    String rendered,
    String questionsText,
    String level,
  ) {
    final trimmed = questionsText.trim();
    if (trimmed.isEmpty) {
      return rendered;
    }
    return '$rendered\n\nQuestion bank ($level):\n$trimmed';
  }
}
