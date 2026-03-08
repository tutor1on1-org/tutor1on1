import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../llm/llm_hash.dart';
import '../llm/llm_models.dart';
import '../llm/llm_providers.dart';
import '../llm/llm_service.dart';
import '../llm/prompt_renderer.dart';
import '../llm/prompt_repository.dart';
import 'llm_log_repository.dart';
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

class _TutorRequestContext {
  _TutorRequestContext({
    required this.sessionId,
    required this.courseVersionId,
    required this.kpKey,
    required this.actionMode,
    required this.promptName,
    required this.resolvedStudentIntent,
    required this.renderedPrompt,
    required this.schemaMap,
    required this.llmContext,
    required this.dedupeKey,
    required this.isStructuredPrompt,
  });

  final int sessionId;
  final int courseVersionId;
  final String kpKey;
  final String actionMode;
  final String promptName;
  final String resolvedStudentIntent;
  final String renderedPrompt;
  final Map<String, dynamic>? schemaMap;
  final LlmCallContext llmContext;
  final String dedupeKey;
  final bool isStructuredPrompt;
}

class SessionService {
  SessionService(
    this._db,
    this._llmService,
    this._promptRepository,
    this._settingsRepository,
    this._llmLogRepository,
  );

  final AppDatabase _db;
  final LlmService _llmService;
  final PromptRepository _promptRepository;
  final SettingsRepository _settingsRepository;
  final LlmLogRepository _llmLogRepository;
  final PromptRenderer _renderer = PromptRenderer();
  final Map<String, LlmRequestHandle> _inflightTutorByKey = {};
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
    String? studentIntent,
    String? helpBias,
    String? modelOverride,
    bool stream = false,
    void Function(String chunk)? onChunk,
    void Function()? onPromptWarning,
    bool streamToDatabase = true,
    void Function(int assistantMessageId)? onAssistantMessageCreated,
    void Function(int studentMessageId)? onStudentMessageCreated,
  }) async {
    if (studentInput.trim().isNotEmpty) {
      final actionMode = _resolveActionMode(mode);
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

    final request = await _prepareTutorRequestContext(
      sessionId: sessionId,
      mode: mode,
      studentInput: studentInput,
      courseVersion: courseVersion,
      node: node,
      studentIntent: studentIntent,
      helpBias: helpBias,
      modelOverride: modelOverride,
      onPromptWarning: onPromptWarning,
    );
    final inflight = _inflightTutorByKey[request.dedupeKey];
    if (inflight != null) {
      return inflight;
    }

    if (!stream) {
      final handle = _createTutorNonStreamingHandle(
        request: request,
        modelOverride: modelOverride,
      );
      return _registerInflightTutorHandle(
        dedupeKey: request.dedupeKey,
        handle: handle,
      );
    }

    final handle = await _createTutorStreamingHandle(
      request: request,
      modelOverride: modelOverride,
      streamToDatabase: streamToDatabase,
      onChunk: onChunk,
      onAssistantMessageCreated: onAssistantMessageCreated,
    );
    return _registerInflightTutorHandle(
      dedupeKey: request.dedupeKey,
      handle: handle,
    );
  }

  Future<_TutorRequestContext> _prepareTutorRequestContext({
    required int sessionId,
    required String mode,
    required String studentInput,
    required CourseVersion courseVersion,
    required CourseNode node,
    required String? studentIntent,
    required String? helpBias,
    required String? modelOverride,
    required void Function()? onPromptWarning,
  }) async {
    final actionMode = _resolveActionMode(mode);
    final session = await _db.getSession(sessionId);
    final progress = session == null
        ? null
        : await _db.getProgress(
            studentId: session.studentId,
            courseVersionId: courseVersion.id,
            kpKey: node.kpKey,
          );
    final messages = await _db.getMessagesForSession(sessionId);
    final resolvedStudentIntent = _resolveStudentIntent(
      requestedIntent: studentIntent,
      studentInput: studentInput,
    );
    final resolvedHelpBias = _normalizeHelpBias(helpBias);
    final promptResolution = _resolveTutorPrompt(
      mode: mode,
      messages: messages,
      studentInput: studentInput,
      studentIntent: resolvedStudentIntent,
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
    final currentDifficultyLevel = _normalizeLevel(progress?.questionLevel) ??
        _masteryLevelToQuestionLevel(masteryFromPrev) ??
        'easy';
    final currentMasteryLevel =
        masteryFromProgress ?? masteryFromPrev ?? 'NOT_PASS';
    final practiceHistorySummary = _buildPracticeHistorySummary(messages);
    final errorBookSummary = _buildErrorBookSummary(
      messages: messages,
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
      'student_intent': resolvedStudentIntent,
      'help_bias': resolvedHelpBias,
      'current_difficulty_level': currentDifficultyLevel,
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
    final needsLessonContent = promptName == 'learn_init';
    if (needsLessonContent) {
      values['lesson_content'] = await _loadLectureTextIfPresent(
        courseVersion: courseVersion,
        kpKey: node.kpKey,
      );
    }
    if (actionMode == 'review') {
      final questionLevel = _normalizeLevel(progress?.questionLevel) ?? 'easy';
      values['presented_questions'] = await _loadQuestionsText(
        courseVersion: courseVersion,
        kpKey: node.kpKey,
        level: questionLevel,
      );
    }
    final renderResult = _renderWithHistoryLimit(
      template: template,
      values: values,
      maxTokens: settings.maxTokens,
    );
    if (renderResult.maxTokensTooSmall && onPromptWarning != null) {
      onPromptWarning();
    }
    final renderedPrompt = renderResult.rendered;
    final schemaMap = await _loadStructuredSchema(promptName);
    final llmContext = _buildTutorLlmContext(
      courseVersion: courseVersion,
      node: node,
      sessionId: sessionId,
      studentId: session?.studentId,
      actionMode: actionMode,
    );
    final dedupeKey = await _buildTutorDedupeKey(
      sessionId: sessionId,
      promptName: promptName,
      renderedPrompt: renderedPrompt,
      modelOverride: modelOverride,
    );
    return _TutorRequestContext(
      sessionId: sessionId,
      courseVersionId: courseVersion.id,
      kpKey: node.kpKey,
      actionMode: actionMode,
      promptName: promptName,
      resolvedStudentIntent: resolvedStudentIntent,
      renderedPrompt: renderedPrompt,
      schemaMap: schemaMap,
      llmContext: llmContext,
      dedupeKey: dedupeKey,
      isStructuredPrompt: _isStructuredPrompt(promptName),
    );
  }

  LlmCallContext _buildTutorLlmContext({
    required CourseVersion courseVersion,
    required CourseNode node,
    required int sessionId,
    required int? studentId,
    required String actionMode,
  }) {
    return LlmCallContext(
      teacherId: courseVersion.teacherId,
      studentId: studentId,
      courseVersionId: courseVersion.id,
      sessionId: sessionId,
      kpKey: node.kpKey,
      action: actionMode,
    );
  }

  LlmRequestHandle _createTutorNonStreamingHandle({
    required _TutorRequestContext request,
    required String? modelOverride,
  }) {
    final handle = _llmService.startCall(
      promptName: request.promptName,
      renderedPrompt: request.renderedPrompt,
      schemaMap: request.schemaMap,
      modelOverride: modelOverride,
      context: request.llmContext,
    );
    final future = handle.future.then((result) async {
      final resolution = await _resolveTutorPayload(
        request: request,
        modelOverride: modelOverride,
        result: result,
        responseText: result.responseText,
      );
      await _persistTutorAssistantPayload(
        request: request,
        resolution: resolution,
      );
      return resolution.result;
    });
    return LlmRequestHandle(future: future, cancel: handle.cancel);
  }

  Future<LlmRequestHandle> _createTutorStreamingHandle({
    required _TutorRequestContext request,
    required String? modelOverride,
    required bool streamToDatabase,
    required void Function(String chunk)? onChunk,
    required void Function(int assistantMessageId)? onAssistantMessageCreated,
  }) async {
    final assistantId = await _db.into(_db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: request.sessionId,
            role: 'assistant',
            content: '',
            action: Value(request.actionMode),
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
      if (!streamToDatabase || flushTimer?.isActive == true) {
        return;
      }
      flushTimer = Timer(const Duration(milliseconds: 80), () async {
        await flush();
      });
    }

    void handleChunk(String chunk) {
      buffer.write(chunk);
      if (request.isStructuredPrompt) {
        return;
      }
      scheduleFlush();
      if (onChunk != null) {
        onChunk(chunk);
      }
    }

    final handle = _llmService.startStreamingCall(
      promptName: request.promptName,
      renderedPrompt: request.renderedPrompt,
      modelOverride: modelOverride,
      onChunk: handleChunk,
      schemaMap: request.schemaMap,
      context: request.llmContext,
    );
    final future = handle.future.then((result) async {
      final finalText = result.responseText.trim().isNotEmpty
          ? result.responseText
          : buffer.toString();
      final resolution = await _resolveTutorPayload(
        request: request,
        modelOverride: modelOverride,
        result: result,
        responseText: finalText,
      );
      if (request.isStructuredPrompt && onChunk != null) {
        onChunk(resolution.payload.displayText);
      }
      final writeDirectly = streamToDatabase ||
          onAssistantMessageCreated == null ||
          request.isStructuredPrompt;
      if (writeDirectly) {
        await _persistTutorAssistantPayload(
          request: request,
          resolution: resolution,
          assistantMessageId: assistantId,
        );
      }
      return resolution.result;
    }).whenComplete(() {
      flushTimer?.cancel();
    });
    return LlmRequestHandle(future: future, cancel: handle.cancel);
  }

  Future<_StructuredPayloadResolution> _resolveTutorPayload({
    required _TutorRequestContext request,
    required String? modelOverride,
    required LlmCallResult result,
    required String responseText,
  }) async {
    if (responseText.trim().isEmpty) {
      throw StateError('LLM returned an empty response.');
    }
    return _resolveStructuredPayload(
      promptName: request.promptName,
      renderedPrompt: request.renderedPrompt,
      modelOverride: modelOverride,
      context: request.llmContext,
      schemaMap: request.schemaMap,
      responseText: responseText,
      result: result,
    );
  }

  Future<void> _persistTutorAssistantPayload({
    required _TutorRequestContext request,
    required _StructuredPayloadResolution resolution,
    int? assistantMessageId,
  }) async {
    if (assistantMessageId == null) {
      await _db.into(_db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: request.sessionId,
              role: 'assistant',
              content: resolution.payload.displayText,
              rawContent: Value(resolution.payload.rawText),
              parsedJson: Value(resolution.payload.parsedJson),
              action: Value(request.actionMode),
            ),
          );
    } else {
      await _db.updateChatMessageAssistantPayload(
        messageId: assistantMessageId,
        content: resolution.payload.displayText,
        rawContent: resolution.payload.rawText,
        parsedJson: resolution.payload.parsedJson,
      );
    }
    await _updateReviewDifficultyIfNeeded(
      actionMode: request.actionMode,
      studentId: request.llmContext.studentId,
      courseVersionId: request.courseVersionId,
      kpKey: request.kpKey,
      studentIntent: request.resolvedStudentIntent,
      parsedJsonText: resolution.payload.parsedJson,
    );
    await _appendTutorPersistLog(
      request: request,
      resolution: resolution,
    );
    await _touchSessionSync(request.sessionId);
  }

  Future<void> _appendTutorPersistLog({
    required _TutorRequestContext request,
    required _StructuredPayloadResolution resolution,
  }) {
    final context = request.llmContext;
    return _llmLogRepository.appendEntry(
      promptName: request.promptName,
      model: resolution.result.model ?? '',
      baseUrl: resolution.result.baseUrl ?? '',
      mode: 'APP',
      status: 'persist',
      callHash: resolution.result.callHash,
      responseChars: resolution.payload.displayText.length,
      dbWriteOk: true,
      teacherId: context.teacherId,
      studentId: context.studentId,
      courseVersionId: context.courseVersionId,
      sessionId: context.sessionId,
      kpKey: context.kpKey,
      action: context.action,
    );
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
    final cachedSummary = _buildCachedSummaryResult(
      messages: messages,
      session: session,
      progress: progress,
    );
    if (cachedSummary != null) {
      await _llmLogRepository.appendEntry(
        promptName: 'summary',
        model: '',
        baseUrl: await _resolveCurrentBaseUrl(),
        mode: 'APP',
        status: 'cache_hit',
        responseChars: (cachedSummary.summaryText ?? '').length,
        teacherId: courseVersion.teacherId,
        studentId: session?.studentId,
        courseVersionId: courseVersion.id,
        sessionId: sessionId,
        kpKey: node.kpKey,
        action: 'summary',
      );
      return RequestHandle<SummarizeResult>(
        future: Future<SummarizeResult>.value(cachedSummary),
        cancel: () {},
      );
    }
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
      'student_intent': 'AUTO',
      'student_summary': progress?.summaryText ?? session?.summaryText ?? '',
      'student_profile': studentPromptContext.profileText,
      'student_preferences': studentPromptContext.preferencesText,
      'practice_history_summary': _buildPracticeHistorySummary(
        messages,
        reviewOnly: true,
        maxMessages: 20,
      ),
      'error_book_summary': _buildErrorBookSummary(
        messages: messages,
        progress: progress,
      ),
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
      final currentMasteryLevel =
          _questionLevelToMasteryLevel(progress?.questionLevel);
      final stabilizedMasteryLevel = _stabilizeSummaryMastery(
        parsedMasteryLevel: masteryLevel,
        currentMasteryLevel: currentMasteryLevel,
        lastEvidence: lastEvidence,
      );
      final litPercent = _masteryLevelToPercent(stabilizedMasteryLevel) ??
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
              stabilizedMasteryLevel != null);
      final rawResponse = summaryValid ? null : result.responseText;
      final questionLevel =
          _masteryLevelToQuestionLevel(stabilizedMasteryLevel) ??
              masterLevel ??
              _masteryLevelToQuestionLevel(masteryLevel);

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
        masteryLevel: stabilizedMasteryLevel,
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
  }) {
    final historyValue = (values['conversation_history'] ?? '').toString();
    final usesHistory = _hasVariable(template, 'conversation_history') ||
        _hasVariable(template, 'session_history');
    String renderWithHistory(String history) {
      final updated = Map<String, Object?>.from(values);
      updated['conversation_history'] = history;
      updated['session_history'] = history;
      return _renderer.render(template, updated);
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
      final difficultyLevel = _normalizeLevel(parsed['difficulty_level']);
      if (difficultyLevel == null) {
        throw StateError(
          'LLM response for "$promptName" has invalid "difficulty_level". '
          'Response preview: ${_summarizeResponseForError(responseText)}',
        );
      }
    }
    if (promptName == 'review_cont') {
      final answerState = (parsed['answer_state'] as String?)?.trim() ?? '';
      const validAnswerStates = {
        'HELP_REQUEST',
        'PARTIAL_ATTEMPT',
        'FINAL_ANSWER',
      };
      if (!validAnswerStates.contains(answerState)) {
        throw StateError(
          'LLM response for "$promptName" has invalid "answer_state". '
          'Response preview: ${_summarizeResponseForError(responseText)}',
        );
      }
      final difficultyAction =
          (parsed['difficulty_action'] as String?)?.trim().toUpperCase() ?? '';
      const validActions = {'DOWN', 'HOLD', 'UP'};
      if (!validActions.contains(difficultyAction)) {
        throw StateError(
          'LLM response for "$promptName" has invalid "difficulty_action". '
          'Response preview: ${_summarizeResponseForError(responseText)}',
        );
      }
      final recommendedLevel = _normalizeLevel(parsed['recommended_level']);
      if (recommendedLevel == null) {
        throw StateError(
          'LLM response for "$promptName" has invalid "recommended_level". '
          'Response preview: ${_summarizeResponseForError(responseText)}',
        );
      }
      final question = parsed['question'];
      if (question is! Map) {
        throw StateError(
          'LLM response for "$promptName" has invalid "question". '
          'Response preview: ${_summarizeResponseForError(responseText)}',
        );
      }
      final turnState = _normalizeTurnState(parsed['turn_state']);
      if (answerState == 'FINAL_ANSWER' && turnState != 'FINISHED') {
        throw StateError(
          'LLM response for "$promptName" requires turn_state=FINISHED when answer_state=FINAL_ANSWER. '
          'Response preview: ${_summarizeResponseForError(responseText)}',
        );
      }
      final nextAction =
          (parsed['next_action'] as String?)?.trim().toUpperCase();
      if (nextAction != null &&
          nextAction.isNotEmpty &&
          nextAction != 'NONE' &&
          nextAction != 'SUMMARY') {
        throw StateError(
          'LLM response for "$promptName" has invalid "next_action". '
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
          'difficulty_level',
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
          'answer_state',
          'difficulty_action',
          'recommended_level',
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

  String? _stabilizeSummaryMastery({
    required String? parsedMasteryLevel,
    required String? currentMasteryLevel,
    required Map<String, dynamic>? lastEvidence,
  }) {
    if (currentMasteryLevel == null) {
      return parsedMasteryLevel;
    }
    if (parsedMasteryLevel == null) {
      return currentMasteryLevel;
    }
    final attempts = _nonNegativeInt(lastEvidence?['a']);
    if (attempts <= 0) {
      return currentMasteryLevel;
    }
    final currentRank = _masteryRank(currentMasteryLevel);
    final parsedRank = _masteryRank(parsedMasteryLevel);
    if (currentRank == null || parsedRank == null) {
      return parsedMasteryLevel;
    }
    if (attempts <= 1) {
      return currentMasteryLevel;
    }
    if (attempts <= 3 && parsedRank < currentRank - 1) {
      return _masteryFromRank(currentRank - 1) ?? parsedMasteryLevel;
    }
    return parsedMasteryLevel;
  }

  int _nonNegativeInt(Object? value) {
    if (value is int) {
      return value < 0 ? 0 : value;
    }
    if (value is num) {
      final asInt = value.toInt();
      return asInt < 0 ? 0 : asInt;
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim()) ?? 0;
      return parsed < 0 ? 0 : parsed;
    }
    return 0;
  }

  int? _masteryRank(String masteryLevel) {
    switch (masteryLevel) {
      case 'NOT_PASS':
        return 0;
      case 'PASS_EASY':
        return 1;
      case 'PASS_MEDIUM':
        return 2;
      case 'PASS_HARD':
        return 3;
      default:
        return null;
    }
  }

  String? _masteryFromRank(int rank) {
    switch (rank) {
      case 0:
        return 'NOT_PASS';
      case 1:
        return 'PASS_EASY';
      case 2:
        return 'PASS_MEDIUM';
      case 3:
        return 'PASS_HARD';
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
    required String studentInput,
    required String studentIntent,
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
      String promptName;
      if (actionMode == 'learn') {
        promptName =
            previousTurnState == 'UNFINISHED' ? 'learn_cont' : 'learn_init';
      } else {
        promptName =
            previousTurnState == 'UNFINISHED' ? 'review_cont' : 'review_init';
      }
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

  String _buildPracticeHistorySummary(
    List<ChatMessage> messages, {
    bool reviewOnly = false,
    int maxMessages = 6,
  }) {
    final source = reviewOnly
        ? messages
            .where((message) =>
                _resolveActionMode(message.action ?? '') == 'review')
            .toList(growable: false)
        : messages;
    final tail = source.length > maxMessages
        ? source.sublist(source.length - maxMessages)
        : source;
    if (tail.isEmpty) {
      return 'No practice history yet.';
    }
    return _buildHistory(tail);
  }

  String _buildErrorBookSummary({
    required List<ChatMessage> messages,
    ProgressEntry? progress,
    Map<String, dynamic>? previousJson,
  }) {
    final aggregated = _aggregateErrorBook(messages);
    if (aggregated != null && aggregated.isNotEmpty) {
      return jsonEncode(aggregated);
    }
    final errorBookUpdate = previousJson?['error_book_update'];
    if (errorBookUpdate is Map<String, dynamic> && errorBookUpdate.isNotEmpty) {
      return jsonEncode(errorBookUpdate);
    }
    if ((progress?.summaryText ?? '').trim().isNotEmpty) {
      return progress!.summaryText!.trim();
    }
    return 'No error book records yet.';
  }

  Map<String, dynamic>? _aggregateErrorBook(List<ChatMessage> messages) {
    final counts = <String, _ErrorBookAggregate>{};
    var totalUpdates = 0;
    for (final message in messages) {
      if (message.role != 'assistant') {
        continue;
      }
      final action = _resolveActionMode(message.action ?? '');
      if (action != 'review') {
        continue;
      }
      final parsed = _extractMessageJson(message);
      final update = parsed?['error_book_update'];
      if (update is! Map<String, dynamic>) {
        continue;
      }
      final mistakeTag = (update['mistake_tag'] as String?)?.trim() ?? '';
      if (mistakeTag.isEmpty) {
        continue;
      }
      final typeId = _resolveErrorBookTypeId(
        parsed: parsed,
        update: update,
      );
      final key = '$typeId::$mistakeTag';
      final note = (update['mistake_note'] as String?)?.trim() ?? '';
      final existing = counts[key];
      if (existing == null) {
        counts[key] = _ErrorBookAggregate(
          typeId: typeId,
          mistakeTag: mistakeTag,
          count: 1,
          lastNote: note,
        );
      } else {
        existing.count += 1;
        if (note.isNotEmpty) {
          existing.lastNote = note;
        }
      }
      totalUpdates += 1;
    }
    if (counts.isEmpty) {
      return null;
    }
    final sorted = counts.values.toList()
      ..sort((left, right) => right.count.compareTo(left.count));
    final top = sorted
        .take(5)
        .map((item) => <String, dynamic>{
              'type_id': item.typeId,
              'mistake_tag': item.mistakeTag,
              'count': item.count,
              'last_note': item.lastNote,
            })
        .toList(growable: false);
    return <String, dynamic>{
      'source': 'review_history',
      'total_updates': totalUpdates,
      'top_mistakes': top,
    };
  }

  String _resolveErrorBookTypeId({
    required Map<String, dynamic>? parsed,
    required Map<String, dynamic> update,
  }) {
    final updateType = (update['type_id'] as String?)?.trim() ?? '';
    if (updateType.isNotEmpty) {
      return updateType;
    }
    final question = parsed?['question'];
    if (question is Map<String, dynamic>) {
      final questionType = (question['type_id'] as String?)?.trim() ?? '';
      if (questionType.isNotEmpty) {
        return questionType;
      }
    }
    return 'OTHER';
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

  String _resolveStudentIntent({
    required String? requestedIntent,
    required String studentInput,
  }) {
    final normalized = (requestedIntent ?? '').trim().toUpperCase();
    if (normalized == 'HELP_REQUEST' ||
        normalized == 'PARTIAL_ATTEMPT' ||
        normalized == 'FINAL_ANSWER' ||
        normalized == 'TOO_EASY' ||
        normalized == 'BORED') {
      return normalized;
    }
    final input = studentInput.trim();
    if (input.isEmpty) {
      return 'AUTO';
    }
    final lowered = input.toLowerCase();
    if (lowered.contains('hint') ||
        lowered.contains('help') ||
        lowered.contains("don't know") ||
        lowered.contains('dont know') ||
        lowered.contains('stuck')) {
      return 'HELP_REQUEST';
    }
    if (lowered.contains('final answer') ||
        lowered.contains('my answer is') ||
        lowered.startsWith('answer:')) {
      return 'FINAL_ANSWER';
    }
    if (lowered.contains('too easy') ||
        lowered.contains('easy for me') ||
        lowered.contains('too simple')) {
      return 'TOO_EASY';
    }
    if (lowered.contains('boring') ||
        lowered.contains('bored') ||
        lowered.contains('not interesting')) {
      return 'BORED';
    }
    return 'PARTIAL_ATTEMPT';
  }

  String _normalizeHelpBias(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    if (normalized == 'EASIER' ||
        normalized == 'HARDER' ||
        normalized == 'UNCHANGED') {
      return normalized;
    }
    return 'UNCHANGED';
  }

  Future<void> _updateReviewDifficultyIfNeeded({
    required String actionMode,
    required int? studentId,
    required int courseVersionId,
    required String kpKey,
    required String studentIntent,
    required String? parsedJsonText,
  }) async {
    if (actionMode != 'review' || studentId == null || studentId <= 0) {
      return;
    }
    final parsed =
        parsedJsonText == null ? null : _tryDecodeJsonObject(parsedJsonText);
    if (parsed == null) {
      return;
    }
    final progress = await _db.getProgress(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: kpKey,
    );
    final currentLevel = _normalizeLevel(progress?.questionLevel) ?? 'easy';
    final turnState = _normalizeTurnState(parsed['turn_state']);
    final grading = parsed['grading'];
    final isCorrect = grading is Map<String, dynamic> &&
        grading['is_correct'] is bool &&
        grading['is_correct'] == true;
    final recommendedLevel = _normalizeLevel(parsed['recommended_level']);
    final difficultyAction =
        (parsed['difficulty_action'] as String?)?.trim().toUpperCase() ?? '';

    var nextLevel = currentLevel;
    final studentWantsHarder =
        studentIntent == 'TOO_EASY' || studentIntent == 'BORED';
    if (studentWantsHarder) {
      nextLevel = _nextDifficultyLevel(currentLevel);
    } else if (turnState == 'FINISHED' && isCorrect) {
      nextLevel = _nextDifficultyLevel(currentLevel);
    } else if (difficultyAction == 'DOWN') {
      nextLevel = _previousDifficultyLevel(currentLevel);
    } else if (recommendedLevel != null) {
      nextLevel = recommendedLevel;
    }
    if (nextLevel == currentLevel) {
      return;
    }
    await _db.upsertProgressDifficulty(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: kpKey,
      questionLevel: nextLevel,
    );
  }

  String _nextDifficultyLevel(String currentLevel) {
    switch (_normalizeLevel(currentLevel) ?? 'easy') {
      case 'easy':
        return 'medium';
      case 'medium':
        return 'hard';
      case 'hard':
        return 'hard';
      default:
        return 'medium';
    }
  }

  String _previousDifficultyLevel(String currentLevel) {
    switch (_normalizeLevel(currentLevel) ?? 'easy') {
      case 'hard':
        return 'medium';
      case 'medium':
        return 'easy';
      case 'easy':
        return 'easy';
      default:
        return 'easy';
    }
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
    required Map<String, dynamic>? schemaMap,
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
        final retryAttempt = attempt + 1;
        final retryModelOverride = await _resolveRetryModelOverride(
          retryAttempt: retryAttempt,
          currentModel: currentResult.model,
          originalModelOverride: modelOverride,
        );
        final retryModel = await _resolveModelForOverride(retryModelOverride);
        final retryReason =
            'structured_parse_retry: ${_summarizeResponseForError(error.toString())}';
        await _llmLogRepository.appendEntry(
          promptName: promptName,
          model: retryModel,
          baseUrl: currentResult.baseUrl ?? await _resolveCurrentBaseUrl(),
          mode: 'APP',
          status: 'retry',
          callHash: currentResult.callHash,
          attempt: retryAttempt,
          retryReason: retryReason,
          backoffMs: _structuredRetryDelay.inMilliseconds,
          renderedChars: renderedPrompt.length,
          teacherId: context.teacherId,
          studentId: context.studentId,
          courseVersionId: context.courseVersionId,
          sessionId: context.sessionId,
          kpKey: context.kpKey,
          action: context.action,
        );
        if (_structuredRetryDelay.inMilliseconds > 0) {
          await Future<void>.delayed(_structuredRetryDelay);
        }
        final retryHandle = _llmService.startCall(
          promptName: promptName,
          renderedPrompt: renderedPrompt,
          schemaMap: schemaMap,
          modelOverride: retryModelOverride,
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

  SummarizeResult? _buildCachedSummaryResult({
    required List<ChatMessage> messages,
    required ChatSession? session,
    required ProgressEntry? progress,
  }) {
    if (messages.isEmpty || session == null) {
      return null;
    }
    final lastSummaryIndex = _findLastSummaryAssistantIndex(messages);
    if (lastSummaryIndex == null) {
      return null;
    }
    if (_hasGradedReviewAfter(
      messages: messages,
      summaryIndex: lastSummaryIndex,
    )) {
      return null;
    }
    final summaryText =
        (progress?.summaryText ?? session.summaryText ?? '').trim();
    if (summaryText.isEmpty) {
      return null;
    }
    final masteryLevel = _questionLevelToMasteryLevel(progress?.questionLevel);
    final litPercent = _masteryLevelToPercent(masteryLevel);
    final lit = litPercent == null ? null : litPercent >= 100;
    return SummarizeResult(
      success: true,
      message: 'Summary unchanged. Reused cached result.',
      lit: lit,
      litPercent: litPercent,
      summaryText: summaryText,
      masteryLevel: masteryLevel,
      masterLevel: _normalizeLevel(progress?.questionLevel),
      nextStep: lit == true ? 'MOVE_ON' : 'CONTINUE_REVIEW',
    );
  }

  int? _findLastSummaryAssistantIndex(List<ChatMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.role != 'assistant') {
        continue;
      }
      if (_resolveActionMode(message.action ?? '') == 'summary') {
        return i;
      }
    }
    return null;
  }

  bool _hasGradedReviewAfter({
    required List<ChatMessage> messages,
    required int summaryIndex,
  }) {
    if (summaryIndex >= messages.length - 1) {
      return false;
    }
    for (var i = summaryIndex + 1; i < messages.length; i++) {
      final message = messages[i];
      if (message.role != 'assistant') {
        continue;
      }
      if (_resolveActionMode(message.action ?? '') != 'review') {
        continue;
      }
      final parsed = _extractMessageJson(message);
      if (parsed == null) {
        continue;
      }
      final turnState = _normalizeTurnState(parsed['turn_state']);
      final grading = parsed['grading'];
      if (turnState == 'FINISHED' && grading is Map<String, dynamic>) {
        return true;
      }
    }
    return false;
  }

  Future<Map<String, dynamic>?> _loadStructuredSchema(String promptName) async {
    switch (promptName) {
      case 'learn_init':
        return _promptRepository.loadSchema('learn_init');
      case 'learn_cont':
        return _promptRepository.loadSchema('learn_cont');
      case 'review_init':
        return _promptRepository.loadSchema('review_init');
      case 'review_cont':
        return _promptRepository.loadSchema('review_cont');
      case 'summary':
        return _promptRepository.loadSchema('summarize');
      default:
        return null;
    }
  }

  Future<String> _resolveCurrentBaseUrl() async {
    final settings = await _settingsRepository.load();
    return settings.baseUrl.trim();
  }

  Future<String> _resolveModelForOverride(String? modelOverride) async {
    final settings = await _settingsRepository.load();
    final override = modelOverride?.trim() ?? '';
    if (override.isNotEmpty) {
      return override;
    }
    return settings.model.trim();
  }

  Future<String?> _resolveRetryModelOverride({
    required int retryAttempt,
    required String? currentModel,
    required String? originalModelOverride,
  }) async {
    if (retryAttempt <= 1) {
      return originalModelOverride;
    }
    final fallbackModel = await _resolveFallbackModel(currentModel);
    if (fallbackModel == null || fallbackModel.trim().isEmpty) {
      return originalModelOverride;
    }
    return fallbackModel.trim();
  }

  Future<String?> _resolveFallbackModel(String? currentModel) async {
    final settings = await _settingsRepository.load();
    final providers = LlmProviders.defaultProviders(
      envBaseUrl: Platform.environment['OPENAI_BASE_URL'],
      envModel: Platform.environment['OPENAI_MODEL'],
    );
    final provider = LlmProviders.findById(providers, settings.providerId) ??
        LlmProviders.findByBaseUrl(providers, settings.baseUrl);
    if (provider == null || provider.models.isEmpty) {
      return null;
    }
    final current = (currentModel ?? '').trim().isNotEmpty
        ? currentModel!.trim()
        : settings.model.trim();
    for (final candidate in provider.models) {
      if (candidate.trim().isEmpty) {
        continue;
      }
      if (candidate.trim() != current) {
        return candidate.trim();
      }
    }
    return null;
  }

  Future<String> _buildTutorDedupeKey({
    required int sessionId,
    required String promptName,
    required String renderedPrompt,
    required String? modelOverride,
  }) async {
    final settings = await _settingsRepository.load();
    final activeModel = (modelOverride ?? '').trim().isNotEmpty
        ? modelOverride!.trim()
        : settings.model.trim();
    final callHash = LlmHash.compute(
      baseUrl: settings.baseUrl,
      model: activeModel,
      promptName: promptName,
      renderedPrompt: renderedPrompt,
      conversationDigest: null,
    );
    return '$sessionId|$promptName|$callHash';
  }

  LlmRequestHandle _registerInflightTutorHandle({
    required String dedupeKey,
    required LlmRequestHandle handle,
  }) {
    final wrapped = LlmRequestHandle(
      future: handle.future.whenComplete(() {
        _inflightTutorByKey.remove(dedupeKey);
      }),
      cancel: () {
        _inflightTutorByKey.remove(dedupeKey);
        handle.cancel();
      },
    );
    _inflightTutorByKey[dedupeKey] = wrapped;
    return wrapped;
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

class _ErrorBookAggregate {
  _ErrorBookAggregate({
    required this.typeId,
    required this.mistakeTag,
    required this.count,
    required this.lastNote,
  });

  final String typeId;
  final String mistakeTag;
  int count;
  String lastNote;
}
