import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../llm/llm_models.dart';
import '../llm/llm_service.dart';
import '../llm/prompt_renderer.dart';
import '../llm/prompt_repository.dart';
import 'settings_repository.dart';

class SummarizeResult {
  SummarizeResult({
    required this.success,
    required this.message,
    this.lit,
    this.litPercent,
    this.summaryText,
    this.masterLevel,
    this.masteryLevel,
    this.nextStep,
  });

  final bool success;
  final String message;
  final bool? lit;
  final int? litPercent;
  final String? summaryText;
  final String? masterLevel;
  final String? masteryLevel;
  final String? nextStep;
}

class _RenderResult {
  _RenderResult({
    required this.rendered,
    required this.maxTokensTooSmall,
  });

  final String rendered;
  final bool maxTokensTooSmall;
}

class _TutorPromptResolution {
  _TutorPromptResolution({
    required this.promptName,
    required this.lastAssistantIndex,
    required this.prevJson,
  });

  final String promptName;
  final int? lastAssistantIndex;
  final Map<String, dynamic>? prevJson;
}

class _AssistantPayload {
  _AssistantPayload({
    required this.displayText,
    required this.rawText,
    required this.parsedJson,
  });

  final String displayText;
  final String rawText;
  final String? parsedJson;
}

class _StructuredPayloadResolution {
  _StructuredPayloadResolution({
    required this.payload,
    required this.result,
    required this.didRetry,
  });

  final _AssistantPayload payload;
  final LlmCallResult result;
  final bool didRetry;
}

class SessionService {
  SessionService(
    this._db,
    this._llmService,
    this._promptRepository,
    this._settingsRepository,
  );

  final AppDatabase _db;
  final LlmService _llmService;
  final PromptRepository _promptRepository;
  final SettingsRepository _settingsRepository;
  final PromptRenderer _renderer = PromptRenderer();
  static final Uuid _uuid = Uuid();
  static const int _structuredRetryLimit = 2;
  static const Duration _structuredRetryDelay = Duration(
    milliseconds: 250,
  );

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
            syncId: Value(_uuid.v4()),
            syncUpdatedAt: Value(DateTime.now()),
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
    final dateSuffix = _formatSessionDate(DateTime.now());
    final node = await _db.getCourseNodeByKey(courseVersionId, kpKey);
    final nodeName = node?.title.trim();
    if (nodeName != null && nodeName.isNotEmpty) {
      return '$kpKey: $nodeName $dateSuffix';
    }
    return '$kpKey $dateSuffix';
  }

  String? _normalizeCourseKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return p.normalize(trimmed);
  }

  String _formatSessionDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year$month$day';
  }

  Future<void> closeSession(int sessionId) async {
    await (_db.update(_db.chatSessions)
          ..where((tbl) => tbl.id.equals(sessionId)))
        .write(
      ChatSessionsCompanion(
        endedAt: Value(DateTime.now()),
        status: const Value('active'),
        syncUpdatedAt: Value(DateTime.now()),
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
    bool stream = false,
    void Function(String chunk)? onChunk,
    void Function()? onPromptWarning,
    bool streamToDatabase = true,
    void Function(int assistantMessageId)? onAssistantMessageCreated,
    void Function(int studentMessageId)? onStudentMessageCreated,
  }) async {
    final actionMode = _resolveActionMode(mode);
    if (studentInput.trim().isNotEmpty) {
      final studentMessageId = await _db.into(_db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: sessionId,
              role: 'user',
              content: studentInput.trim(),
              action: Value(actionMode),
            ),
          );
      await _touchSessionSync(sessionId);
      if (onStudentMessageCreated != null) {
        onStudentMessageCreated(studentMessageId);
      }
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
    final promptResolution = _resolveTutorPrompt(
      mode: mode,
      messages: messages,
    );
    final promptName = promptResolution.promptName;
    final history = _buildHistory(messages);
    final recentDialogue = _buildRecentDialogue(
      messages,
      lastAssistantIndex: promptResolution.lastAssistantIndex,
    );
    final prevJsonText = promptResolution.prevJson == null
        ? '{}'
        : jsonEncode(promptResolution.prevJson);
    final lastEvidence = _extractLatestEvidence(messages);
    final lastEvidenceText = jsonEncode(
      lastEvidence ??
          {
            'a': 0,
            'c': 0,
            'h': 0,
            't': '',
            'mt': <String>[],
          },
    );
    final masteryFromProgress =
        _questionLevelToMasteryLevel(progress?.questionLevel);
    final masteryFromPrev = _normalizeMasteryLevel(
      promptResolution.prevJson?['mastery_level'],
    );
    final currentMasteryLevel =
        masteryFromProgress ?? masteryFromPrev ?? 'NOT_PASS';
    final practiceHistorySummary = _buildPracticeHistorySummary(messages);
    final errorBookSummary = _buildErrorBookSummary(
      progress: progress,
      previousJson: promptResolution.prevJson,
    );
    final courseKey = _normalizeCourseKey(courseVersion.sourcePath);
    final studentPromptContext = await _db.resolveStudentPromptContext(
      teacherId: courseVersion.teacherId,
      courseKey: courseKey,
      studentId: session?.studentId,
    );
    if (session != null) {
      await _promptRepository.ensureAssignmentPrompts(
        teacherId: courseVersion.teacherId,
        studentId: session.studentId,
        courseVersionId: courseVersion.id,
      );
    }

    final template = await _promptRepository.loadPrompt(
      promptName,
      teacherId: courseVersion.teacherId,
      courseKey: courseKey,
      studentId: session?.studentId,
    );
    final settings = await _settingsRepository.load();
    final values = {
      'subject': courseVersion.subject,
      'course_version_id': courseVersion.id,
      'kp_key': node.kpKey,
      'kp_title': node.title,
      'kp_description': node.description,
      'conversation_history': history,
      'session_history': history,
      'student_input': studentInput.trim(),
      'student_summary': progress?.summaryText ?? session?.summaryText ?? '',
      'student_profile': studentPromptContext.profileText,
      'student_preferences': studentPromptContext.preferencesText,
      'lesson_content': '',
      'types': '[{"type_id":"OTHER","name":"General"}]',
      'error_book_summary': errorBookSummary,
      'practice_history_summary': practiceHistorySummary,
      'presented_questions': '',
      'recent_dialogue': recentDialogue,
      'prev_json': prevJsonText,
      'last_evidence': lastEvidenceText,
      'current_mastery_level': currentMasteryLevel,
    };
    String? lectureText;
    String? questionsText;
    String? questionLevel;
    final needsLessonContent =
        promptName == 'learn_init' || promptName == 'review_init';
    if (needsLessonContent) {
      lectureText = await _loadLectureTextIfPresent(
        courseVersion: courseVersion,
        kpKey: node.kpKey,
      );
      values['lesson_content'] = lectureText;
    }
    final usesReviewQuestionBank = actionMode == 'review';
    if (usesReviewQuestionBank) {
      questionLevel = _normalizeLevel(progress?.questionLevel) ?? 'easy';
      questionsText = await _loadQuestionsText(
        courseVersion: courseVersion,
        kpKey: node.kpKey,
        level: questionLevel,
      );
      values['presented_questions'] = questionsText;
    }
    final useLegacyPrompt = promptName == 'learn' || promptName == 'review';
    final renderResult = _renderWithHistoryLimit(
      template: template,
      values: values,
      maxTokens: settings.maxTokens,
      applyExtras: (rendered) {
        if (!useLegacyPrompt) {
          return rendered;
        }
        final resolvedLecture = lectureText;
        if (resolvedLecture != null) {
          return _appendLecture(rendered, resolvedLecture);
        }
        final resolvedQuestions = questionsText;
        final resolvedLevel = questionLevel;
        if (resolvedQuestions != null && resolvedLevel != null) {
          return _appendQuestionBank(
            rendered,
            resolvedQuestions,
            resolvedLevel,
          );
        }
        return rendered;
      },
    );
    if (renderResult.maxTokensTooSmall && onPromptWarning != null) {
      onPromptWarning();
    }
    final rendered = renderResult.rendered;

    if (!stream) {
      final handle = _llmService.startCall(
        promptName: promptName,
        renderedPrompt: rendered,
        modelOverride: modelOverride,
        context: LlmCallContext(
          teacherId: courseVersion.teacherId,
          studentId: session?.studentId,
          courseVersionId: courseVersion.id,
          sessionId: sessionId,
          kpKey: node.kpKey,
          action: actionMode,
        ),
      );
      final future = handle.future.then((result) async {
        if (result.responseText.trim().isEmpty) {
          throw StateError('LLM returned an empty response.');
        }
        final resolution = await _resolveStructuredPayload(
          promptName: promptName,
          renderedPrompt: rendered,
          modelOverride: modelOverride,
          context: LlmCallContext(
            teacherId: courseVersion.teacherId,
            studentId: session?.studentId,
            courseVersionId: courseVersion.id,
            sessionId: sessionId,
            kpKey: node.kpKey,
            action: actionMode,
          ),
          responseText: result.responseText,
          result: result,
        );
        await _db.into(_db.chatMessages).insert(
              ChatMessagesCompanion.insert(
                sessionId: sessionId,
                role: 'assistant',
                content: resolution.payload.displayText,
                rawContent: Value(resolution.payload.rawText),
                parsedJson: Value(resolution.payload.parsedJson),
                action: Value(actionMode),
              ),
            );
        await _touchSessionSync(sessionId);
        return resolution.result;
      });
      return LlmRequestHandle(future: future, cancel: handle.cancel);
    }

    final assistantId = await _db.into(_db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: sessionId,
            role: 'assistant',
            content: '',
            action: Value(actionMode),
          ),
        );
    if (onAssistantMessageCreated != null) {
      onAssistantMessageCreated(assistantId);
    }
    final buffer = StringBuffer();
    Timer? flushTimer;

    Future<void> flush() async {
      if (!streamToDatabase) {
        return;
      }
      await _db.updateChatMessageContent(
        messageId: assistantId,
        content: buffer.toString(),
      );
    }

    void scheduleFlush() {
      if (!streamToDatabase) {
        return;
      }
      if (flushTimer?.isActive == true) {
        return;
      }
      flushTimer = Timer(const Duration(milliseconds: 80), () async {
        await flush();
      });
    }

    void handleChunk(String chunk) {
      buffer.write(chunk);
      if (_isStructuredPrompt(promptName)) {
        return;
      }
      scheduleFlush();
      if (onChunk != null) {
        onChunk(chunk);
      }
    }

    final handle = _llmService.startStreamingCall(
      promptName: promptName,
      renderedPrompt: rendered,
      modelOverride: modelOverride,
      onChunk: handleChunk,
      context: LlmCallContext(
        teacherId: courseVersion.teacherId,
        studentId: session?.studentId,
        courseVersionId: courseVersion.id,
        sessionId: sessionId,
        kpKey: node.kpKey,
        action: actionMode,
      ),
    );
    final future = handle.future.then((result) async {
      flushTimer?.cancel();
      final finalText = result.responseText.trim().isNotEmpty
          ? result.responseText
          : buffer.toString();
      if (finalText.trim().isEmpty) {
        throw StateError('LLM returned an empty response.');
      }
      final resolution = await _resolveStructuredPayload(
        promptName: promptName,
        renderedPrompt: rendered,
        modelOverride: modelOverride,
        context: LlmCallContext(
          teacherId: courseVersion.teacherId,
          studentId: session?.studentId,
          courseVersionId: courseVersion.id,
          sessionId: sessionId,
          kpKey: node.kpKey,
          action: actionMode,
        ),
        responseText: finalText,
        result: result,
      );
      if (_isStructuredPrompt(promptName) && onChunk != null) {
        onChunk(resolution.payload.displayText);
      }
      final writeDirectly = streamToDatabase ||
          onAssistantMessageCreated == null ||
          _isStructuredPrompt(promptName);
      if (writeDirectly) {
        await _db.updateChatMessageAssistantPayload(
          messageId: assistantId,
          content: resolution.payload.displayText,
          rawContent: resolution.payload.rawText,
          parsedJson: resolution.payload.parsedJson,
        );
        await _touchSessionSync(sessionId);
      }
      return resolution.result;
    });
    return LlmRequestHandle(future: future, cancel: handle.cancel);
  }

  Future<RequestHandle<SummarizeResult>> startSummarize({
    required int sessionId,
    required CourseVersion courseVersion,
    required CourseNode node,
    String? modelOverride,
    void Function()? onPromptWarning,
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
    final lastEvidence = _extractLatestEvidence(messages);
    final courseKey = _normalizeCourseKey(courseVersion.sourcePath);
    final studentPromptContext = await _db.resolveStudentPromptContext(
      teacherId: courseVersion.teacherId,
      courseKey: courseKey,
      studentId: session?.studentId,
    );
    if (session != null) {
      await _promptRepository.ensureAssignmentPrompts(
        teacherId: courseVersion.teacherId,
        studentId: session.studentId,
        courseVersionId: courseVersion.id,
      );
    }
    final template = await _promptRepository.loadPrompt(
      'summary',
      teacherId: courseVersion.teacherId,
      courseKey: courseKey,
      studentId: session?.studentId,
    );
    final schema = await _promptRepository.loadSchema('summarize');
    final settings = await _settingsRepository.load();
    final values = {
      'subject': courseVersion.subject,
      'course_version_id': courseVersion.id,
      'kp_key': node.kpKey,
      'kp_title': node.title,
      'kp_description': node.description,
      'conversation_history': history,
      'session_history': history,
      'student_summary': progress?.summaryText ?? session?.summaryText ?? '',
      'student_profile': studentPromptContext.profileText,
      'student_preferences': studentPromptContext.preferencesText,
      'practice_history_summary': _buildPracticeHistorySummary(messages),
      'error_book_summary': _buildErrorBookSummary(progress: progress),
      'last_evidence': jsonEncode(
        lastEvidence ??
            {
              'a': 0,
              'c': 0,
              'h': 0,
              't': '',
              'mt': <String>[],
            },
      ),
      'current_mastery_level':
          _questionLevelToMasteryLevel(progress?.questionLevel) ?? 'NOT_PASS',
    };
    final renderResult = _renderWithHistoryLimit(
      template: template,
      values: values,
      maxTokens: settings.maxTokens,
      applyExtras: (rendered) => rendered,
    );
    if (renderResult.maxTokensTooSmall && onPromptWarning != null) {
      onPromptWarning();
    }
    final rendered = renderResult.rendered;

    final handle = _llmService.startCall(
      promptName: 'summary',
      renderedPrompt: rendered,
      schemaMap: schema,
      modelOverride: modelOverride,
      context: LlmCallContext(
        teacherId: courseVersion.teacherId,
        studentId: session?.studentId,
        courseVersionId: courseVersion.id,
        sessionId: sessionId,
        kpKey: node.kpKey,
        action: 'summary',
      ),
    );
    final future = handle.future.then((result) async {
      if (result.responseText.trim().isEmpty) {
        throw StateError('LLM returned an empty response.');
      }

      final parsed = _tryDecodeJsonObject(result.responseText);
      final summaryText = parsed?['summary_text'];
      final teacherMessage = parsed?['teacher_message'];
      final lit = parsed?['lit'];
      final masteryLevel = _normalizeMasteryLevel(parsed?['mastery_level']);
      final masterLevel = _normalizeLevel(parsed?['master_level']);
      final nextStep = _normalizeNextStep(parsed?['next_step']);
      final litPercent = _masteryLevelToPercent(masteryLevel) ??
          _masterLevelToPercent(masterLevel);
      final resolvedLit =
          lit is bool ? lit : (litPercent == null ? null : litPercent >= 100);
      final summaryValue =
          summaryText is String && summaryText.trim().isNotEmpty
              ? summaryText
              : (teacherMessage is String && teacherMessage.trim().isNotEmpty
                  ? teacherMessage
                  : null);
      final summary = summaryValue ?? result.responseText;
      final parsedJson = parsed == null ? null : jsonEncode(parsed);
      final summaryValid = (summaryText is String &&
              summaryText.trim().isNotEmpty &&
              lit is bool &&
              masterLevel != null) ||
          (teacherMessage is String &&
              teacherMessage.trim().isNotEmpty &&
              masteryLevel != null);
      final rawResponse = summaryValid ? null : result.responseText;
      final questionLevel =
          masterLevel ?? _masteryLevelToQuestionLevel(masteryLevel);

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
            summaryLit: resolvedLit,
            litPercent: litPercent,
            questionLevel: questionLevel,
          );
        }

        await (_db.update(_db.chatSessions)
              ..where((tbl) => tbl.id.equals(sessionId)))
            .write(
          ChatSessionsCompanion(
            summaryText: Value(summary),
            summaryLit: Value(resolvedLit),
            summaryLitPercent: Value(litPercent),
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
                rawContent: Value(result.responseText),
                parsedJson: Value(parsedJson),
                action: const Value('summary'),
              ),
            );
      });
      await _touchSessionSync(sessionId);

      return SummarizeResult(
        success: true,
        message: summaryValid ? 'Summary stored.' : 'Summary saved (unparsed).',
        lit: resolvedLit,
        litPercent: litPercent,
        summaryText: summary,
        masterLevel: masterLevel ?? questionLevel,
        masteryLevel: masteryLevel,
        nextStep: nextStep,
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

  _RenderResult _renderWithHistoryLimit({
    required String template,
    required Map<String, Object?> values,
    required int maxTokens,
    required String Function(String rendered) applyExtras,
  }) {
    final historyValue = (values['conversation_history'] ?? '').toString();
    final usesHistory = _hasVariable(template, 'conversation_history') ||
        _hasVariable(template, 'session_history');
    String renderWithHistory(String history) {
      final updated = Map<String, Object?>.from(values);
      updated['conversation_history'] = history;
      updated['session_history'] = history;
      return applyExtras(_renderer.render(template, updated));
    }

    final full = renderWithHistory(historyValue);
    if (!usesHistory || maxTokens <= 0 || full.length <= maxTokens) {
      return _RenderResult(
        rendered: full,
        maxTokensTooSmall: false,
      );
    }

    final target = (maxTokens * 0.8).floor();
    final baseWithoutHistory = renderWithHistory('');
    if (baseWithoutHistory.length > target) {
      return _RenderResult(
        rendered: baseWithoutHistory,
        maxTokensTooSmall: true,
      );
    }

    final overflow = full.length - target;
    if (overflow <= 0) {
      return _RenderResult(
        rendered: full,
        maxTokensTooSmall: false,
      );
    }

    final historyLength = historyValue.length;
    final availableHistoryLength = historyLength - overflow;
    if (availableHistoryLength <= 0) {
      return _RenderResult(
        rendered: baseWithoutHistory,
        maxTokensTooSmall: true,
      );
    }

    final keepFirst = (availableHistoryLength / 3).floor();
    final keepLast = availableHistoryLength - keepFirst;
    if (keepFirst > historyLength || keepLast > historyLength) {
      return _RenderResult(
        rendered: baseWithoutHistory,
        maxTokensTooSmall: true,
      );
    }

    final trimmedHistory = historyValue.substring(0, keepFirst) +
        historyValue.substring(historyLength - keepLast);
    return _RenderResult(
      rendered: renderWithHistory(trimmedHistory),
      maxTokensTooSmall: false,
    );
  }

  bool _hasVariable(String template, String name) {
    return RegExp('{{\\s*$name\\s*}}').hasMatch(template);
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

  void _validateStructuredResponse({
    required String promptName,
    required String responseText,
    required Map<String, dynamic>? parsed,
  }) {
    if (!_isStructuredPrompt(promptName)) {
      return;
    }
    if (parsed == null) {
      throw StateError(
        'LLM response for "$promptName" is not valid JSON. '
        'Response preview: ${_summarizeResponseForError(responseText)}',
      );
    }
    final required = _requiredStructuredKeys(promptName);
    final missing = required.where((key) => !parsed.containsKey(key)).toList();
    if (missing.isNotEmpty) {
      throw StateError(
        'LLM response for "$promptName" is missing keys: ${missing.join(', ')}. '
        'Response preview: ${_summarizeResponseForError(responseText)}',
      );
    }
    final teacherMessage = parsed['teacher_message'];
    if (teacherMessage is! String || teacherMessage.trim().isEmpty) {
      throw StateError(
        'LLM response for "$promptName" is missing "teacher_message". '
        'Response preview: ${_summarizeResponseForError(responseText)}',
      );
    }
    if (promptName == 'review_init') {
      final question = parsed['question'];
      if (question is! Map) {
        throw StateError(
          'LLM response for "$promptName" has invalid "question". '
          'Response preview: ${_summarizeResponseForError(responseText)}',
        );
      }
      final questionText = question['text'];
      final questionType = question['type_id'];
      if (questionText is! String || questionText.trim().isEmpty) {
        throw StateError(
          'LLM response for "$promptName" is missing question.text. '
          'Response preview: ${_summarizeResponseForError(responseText)}',
        );
      }
      if (questionType is! String || questionType.trim().isEmpty) {
        throw StateError(
          'LLM response for "$promptName" is missing question.type_id. '
          'Response preview: ${_summarizeResponseForError(responseText)}',
        );
      }
    }
    if (promptName == 'review_cont') {
      final question = parsed['question'];
      if (question != null && question is! Map) {
        throw StateError(
          'LLM response for "$promptName" has invalid "question". '
          'Response preview: ${_summarizeResponseForError(responseText)}',
        );
      }
    }
  }

  Set<String> _requiredStructuredKeys(String promptName) {
    switch (promptName) {
      case 'learn_init':
      case 'learn_cont':
        return {
          'teacher_message',
          'understanding',
          'next_mode',
          'turn_state',
        };
      case 'review_init':
        return {
          'teacher_message',
          'turn_state',
          'question',
          'grading',
          'error_book_update',
          'evidence',
          'mastery_level',
          'next_mode',
        };
      case 'review_cont':
        return {
          'teacher_message',
          'turn_state',
          'question',
          'grading',
          'error_book_update',
          'evidence',
          'mastery_level',
          'next_mode',
        };
      case 'summary':
        return {
          'teacher_message',
          'mastery_level',
          'next_step',
        };
      default:
        return {'teacher_message'};
    }
  }

  String _summarizeResponseForError(String responseText) {
    final trimmed = responseText.trim();
    if (trimmed.isEmpty) {
      return '<empty>';
    }
    if (trimmed.length <= 240) {
      return trimmed;
    }
    return '${trimmed.substring(0, 240)}...';
  }

  String? _normalizeLevel(Object? value) {
    if (value is! String) {
      return null;
    }
    final normalized = value.trim().toLowerCase();
    if (normalized == 'easy' ||
        normalized == 'medium' ||
        normalized == 'hard') {
      return normalized;
    }
    return null;
  }

  String? _normalizeMasteryLevel(Object? value) {
    if (value is! String) {
      return null;
    }
    final normalized = value.trim().toUpperCase().replaceAll('-', '_');
    switch (normalized) {
      case 'NOT_PASS':
      case 'PASS_EASY':
      case 'PASS_MEDIUM':
      case 'PASS_HARD':
        return normalized;
      default:
        return null;
    }
  }

  String? _normalizeNextStep(Object? value) {
    if (value is! String) {
      return null;
    }
    final normalized = value.trim().toUpperCase().replaceAll('-', '_');
    switch (normalized) {
      case 'RELEARN':
      case 'CONTINUE_REVIEW':
      case 'MOVE_ON':
        return normalized;
      default:
        return null;
    }
  }

  int? _masteryLevelToPercent(String? masteryLevel) {
    switch (masteryLevel) {
      case 'NOT_PASS':
        return 0;
      case 'PASS_EASY':
        return 33;
      case 'PASS_MEDIUM':
        return 66;
      case 'PASS_HARD':
        return 100;
      default:
        return null;
    }
  }

  int? _masterLevelToPercent(String? masterLevel) {
    switch (masterLevel) {
      case 'easy':
        return 33;
      case 'medium':
        return 66;
      case 'hard':
        return 100;
      default:
        return null;
    }
  }

  String? _masteryLevelToQuestionLevel(String? masteryLevel) {
    switch (masteryLevel) {
      case 'PASS_EASY':
        return 'easy';
      case 'PASS_MEDIUM':
        return 'medium';
      case 'PASS_HARD':
        return 'hard';
      default:
        return null;
    }
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

  String _resolveActionMode(String mode) {
    final normalized = mode.trim().toLowerCase();
    if (normalized == 'learn' ||
        normalized == 'learn_init' ||
        normalized == 'learn_cont') {
      return 'learn';
    }
    if (normalized == 'review' ||
        normalized == 'review_init' ||
        normalized == 'review_cont') {
      return 'review';
    }
    if (normalized == 'summary' || normalized == 'summarize') {
      return 'summary';
    }
    return normalized;
  }

  _TutorPromptResolution _resolveTutorPrompt({
    required String mode,
    required List<ChatMessage> messages,
  }) {
    final normalized = mode.trim().toLowerCase();
    if (normalized == 'learn_init' ||
        normalized == 'learn_cont' ||
        normalized == 'review_init' ||
        normalized == 'review_cont') {
      final actionMode = _resolveActionMode(normalized);
      final previous = _findLastAssistantForActionMode(
        messages: messages,
        actionMode: actionMode,
      );
      return _TutorPromptResolution(
        promptName: normalized,
        lastAssistantIndex: previous?.index,
        prevJson: previous?.json,
      );
    }

    final actionMode = _resolveActionMode(normalized);
    if (actionMode == 'learn' || actionMode == 'review') {
      final previous = _findLastAssistantForActionMode(
        messages: messages,
        actionMode: actionMode,
      );
      final previousTurnState =
          _normalizeTurnState(previous?.json?['turn_state']);
      final promptName = actionMode == 'learn'
          ? (previousTurnState == 'UNFINISHED' ? 'learn_cont' : 'learn_init')
          : (previousTurnState == 'UNFINISHED' ? 'review_cont' : 'review_init');
      return _TutorPromptResolution(
        promptName: promptName,
        lastAssistantIndex: previous?.index,
        prevJson: previous?.json,
      );
    }

    return _TutorPromptResolution(
      promptName: normalized,
      lastAssistantIndex: null,
      prevJson: null,
    );
  }

  _AssistantJsonRef? _findLastAssistantForActionMode({
    required List<ChatMessage> messages,
    required String actionMode,
  }) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.role != 'assistant') {
        continue;
      }
      final messageAction = _resolveActionMode(message.action ?? '');
      if (messageAction != actionMode) {
        continue;
      }
      return _AssistantJsonRef(
        index: i,
        json: _extractMessageJson(message),
      );
    }
    return null;
  }

  String _buildRecentDialogue(
    List<ChatMessage> messages, {
    required int? lastAssistantIndex,
  }) {
    if (lastAssistantIndex == null) {
      return '';
    }
    final from = lastAssistantIndex + 1;
    if (from >= messages.length) {
      return '';
    }
    return _buildHistory(messages.sublist(from));
  }

  String _buildPracticeHistorySummary(List<ChatMessage> messages) {
    final tail =
        messages.length > 6 ? messages.sublist(messages.length - 6) : messages;
    if (tail.isEmpty) {
      return 'No practice history yet.';
    }
    return _buildHistory(tail);
  }

  String _buildErrorBookSummary({
    ProgressEntry? progress,
    Map<String, dynamic>? previousJson,
  }) {
    final errorBookUpdate = previousJson?['error_book_update'];
    if (errorBookUpdate is Map<String, dynamic> && errorBookUpdate.isNotEmpty) {
      return jsonEncode(errorBookUpdate);
    }
    if ((progress?.summaryText ?? '').trim().isNotEmpty) {
      return progress!.summaryText!.trim();
    }
    return 'No error book records yet.';
  }

  Map<String, dynamic>? _extractLatestEvidence(List<ChatMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.role != 'assistant') {
        continue;
      }
      final parsed = _extractMessageJson(message);
      final evidence = parsed?['evidence'];
      if (evidence is Map<String, dynamic>) {
        return evidence;
      }
    }
    return null;
  }

  String? _normalizeTurnState(Object? value) {
    if (value is! String) {
      return null;
    }
    final normalized = value.trim().toUpperCase();
    if (normalized == 'UNFINISHED' || normalized == 'FINISHED') {
      return normalized;
    }
    return null;
  }

  String? _questionLevelToMasteryLevel(String? questionLevel) {
    final normalized = _normalizeLevel(questionLevel);
    switch (normalized) {
      case 'easy':
        return 'PASS_EASY';
      case 'medium':
        return 'PASS_MEDIUM';
      case 'hard':
        return 'PASS_HARD';
      default:
        return null;
    }
  }

  Future<String> _loadLectureTextIfPresent({
    required CourseVersion courseVersion,
    required String kpKey,
  }) async {
    try {
      return await _loadLectureText(
        courseVersion: courseVersion,
        kpKey: kpKey,
      );
    } catch (_) {
      return '';
    }
  }

  Map<String, dynamic>? _extractMessageJson(ChatMessage message) {
    final stored = message.parsedJson;
    if (stored != null && stored.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(stored);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (_) {
        // Fall through to raw/content parsing.
      }
    }
    final raw = message.rawContent;
    if (raw != null && raw.trim().isNotEmpty) {
      final parsed = _tryDecodeJsonObject(raw);
      if (parsed != null) {
        return parsed;
      }
    }
    return _tryDecodeJsonObject(message.content);
  }

  _AssistantPayload _buildAssistantPayload({
    required String promptName,
    required String responseText,
  }) {
    final parsed = _tryDecodeJsonObject(responseText);
    _validateStructuredResponse(
      promptName: promptName,
      responseText: responseText,
      parsed: parsed,
    );
    final parsedJson = parsed == null ? null : jsonEncode(parsed);
    final display = _resolveTeacherDisplayText(
      promptName: promptName,
      parsed: parsed,
      fallback: responseText,
    );
    return _AssistantPayload(
      displayText: display,
      rawText: responseText,
      parsedJson: parsedJson,
    );
  }

  Future<_StructuredPayloadResolution> _resolveStructuredPayload({
    required String promptName,
    required String renderedPrompt,
    required String? modelOverride,
    required LlmCallContext context,
    required String responseText,
    required LlmCallResult result,
  }) async {
    var currentResult = result;
    var currentText = responseText;
    var didRetry = false;
    for (var attempt = 0; attempt <= _structuredRetryLimit; attempt++) {
      try {
        final payload = _buildAssistantPayload(
          promptName: promptName,
          responseText: currentText,
        );
        return _StructuredPayloadResolution(
          payload: payload,
          result: currentResult,
          didRetry: didRetry,
        );
      } catch (error) {
        final shouldRetry = _isStructuredPrompt(promptName) &&
            attempt < _structuredRetryLimit &&
            !_isCancellationError(error);
        if (!shouldRetry) {
          rethrow;
        }
        didRetry = true;
        if (_structuredRetryDelay.inMilliseconds > 0) {
          await Future<void>.delayed(_structuredRetryDelay);
        }
        final retryHandle = _llmService.startCall(
          promptName: promptName,
          renderedPrompt: renderedPrompt,
          modelOverride: modelOverride,
          context: context,
        );
        currentResult = await retryHandle.future;
        currentText = currentResult.responseText;
        if (currentText.trim().isEmpty) {
          throw StateError('LLM returned an empty response.');
        }
      }
    }
    throw StateError('Failed to resolve structured response.');
  }

  bool _isCancellationError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('request cancelled') || text.contains('cancelled');
  }

  String _resolveTeacherDisplayText({
    required String promptName,
    required Map<String, dynamic>? parsed,
    required String fallback,
  }) {
    if (parsed == null) {
      return fallback;
    }
    final teacherMessage = parsed['teacher_message'];
    if (teacherMessage is String && teacherMessage.trim().isNotEmpty) {
      return teacherMessage.trim();
    }
    if (promptName == 'summary') {
      final summaryText = parsed['summary_text'];
      if (summaryText is String && summaryText.trim().isNotEmpty) {
        return summaryText.trim();
      }
    }
    return fallback;
  }

  bool _isStructuredPrompt(String promptName) {
    return promptName == 'learn_init' ||
        promptName == 'learn_cont' ||
        promptName == 'review_init' ||
        promptName == 'review_cont' ||
        promptName == 'summary';
  }

  Future<void> _touchSessionSync(int sessionId) {
    return (_db.update(_db.chatSessions)
          ..where((tbl) => tbl.id.equals(sessionId)))
        .write(
      ChatSessionsCompanion(syncUpdatedAt: Value(DateTime.now())),
    );
  }
}

class _AssistantJsonRef {
  _AssistantJsonRef({
    required this.index,
    required this.json,
  });

  final int index;
  final Map<String, dynamic>? json;
}
