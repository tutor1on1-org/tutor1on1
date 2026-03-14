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
import '../models/tutor_action.dart';
import '../models/tutor_contract.dart';
import '../llm/prompt_repository.dart';
import 'llm_log_repository.dart';
import 'session_upload_cache_service.dart';
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

class _JsonStringPrefixResult {
  _JsonStringPrefixResult({
    required this.value,
  });

  final String value;
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
    this.reviewPassedLevel,
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
  final String? reviewPassedLevel;
}

class SessionService {
  SessionService(
    this._db,
    this._llmService,
    this._promptRepository,
    this._settingsRepository,
    this._llmLogRepository, {
    SessionUploadCacheService? sessionUploadCacheService,
  }) : _sessionUploadCacheService = sessionUploadCacheService;

  final AppDatabase _db;
  final LlmService _llmService;
  final PromptRepository _promptRepository;
  final SettingsRepository _settingsRepository;
  final LlmLogRepository _llmLogRepository;
  final SessionUploadCacheService? _sessionUploadCacheService;
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
    final sessionId = await _db.into(_db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: kpKey,
            title: Value(resolvedTitle),
            status: const Value('active'),
            controlStateJson: Value(
              TutorControlState.defaultForMode(TutorMode.learn).toJsonText(),
            ),
            controlStateUpdatedAt: Value(DateTime.now()),
            evidenceStateJson: Value(TutorEvidenceState.initial().toJsonText()),
            evidenceStateUpdatedAt: Value(DateTime.now()),
            syncId: Value(_uuid.v4()),
            syncUpdatedAt: Value(DateTime.now()),
          ),
        );
    if (_sessionUploadCacheService != null) {
      await _sessionUploadCacheService.captureSession(sessionId);
    }
    return sessionId;
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
    if (_sessionUploadCacheService != null) {
      await _sessionUploadCacheService.captureSession(sessionId);
    }
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
    final controlState = _loadSessionControlState(
      session,
      fallbackMode: actionMode == 'review' ? TutorMode.review : TutorMode.learn,
    );
    final evidenceState = _loadSessionEvidenceState(session);
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
      sessionControl: controlState,
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
    final lastEvidence = evidenceState.lastEvidence;
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
    final passedCounts = _resolvePassedCounts(
      progress: progress,
      evidenceState: evidenceState,
    );
    final masteryFromCounts = _masteryLevelFromPassedCounts(passedCounts);
    final masteryFromPrev =
        _normalizeMasteryLevel(promptResolution.prevJson?['mastery_level']);
    final currentDifficultyLevel =
        _reviewDifficultyLevelFromPassedCounts(passedCounts);
    final currentMasteryLevel =
        masteryFromCounts ?? masteryFromPrev ?? 'NOT_PASS';
    final bestPassedLevel = _bestPassedLevelFromCounts(passedCounts) ?? 'none';
    final totalPassedCount = _totalPassedCount(passedCounts);
    final practiceHistorySummary = _buildPracticeHistorySummary(
      messages,
      evidenceState: evidenceState,
    );
    final errorBookSummary = _buildErrorBookSummary(
      messages: messages,
      progress: progress,
      previousJson: promptResolution.prevJson,
      evidenceState: evidenceState,
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
      'control_state_json': controlState.toJsonText(),
      'evidence_state_json': evidenceState.toJsonText(),
      'evidence_policy': evidenceState.policy,
      'new_graded_review_evidence_available':
          evidenceState.hasNewGradedReviewEvidence ? 'true' : 'false',
      'student_input': studentInput.trim(),
      'student_intent': resolvedStudentIntent,
      'help_bias': resolvedHelpBias,
      'current_difficulty_level': currentDifficultyLevel,
      'student_summary': progress?.summaryText ?? session?.summaryText ?? '',
      'student_profile': studentPromptContext.profileText,
      'student_preferences': studentPromptContext.preferencesText,
      'passed_counts_json': jsonEncode(passedCounts),
      'best_passed_level': bestPassedLevel,
      'total_passed_count': totalPassedCount.toString(),
      'current_lit': progress?.lit == true ? 'true' : 'false',
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
      values['presented_questions'] = await _loadQuestionsText(
        courseVersion: courseVersion,
        kpKey: node.kpKey,
        level: currentDifficultyLevel,
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
      reviewPassedLevel: _reviewPassedLevelForPrompt(
        promptName: promptName,
        currentDifficultyLevel: currentDifficultyLevel,
        previousAssistantJson: promptResolution.prevJson,
      ),
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
    var streamedDisplayText = '';
    Timer? flushTimer;

    Future<void> flush() async {
      if (!streamToDatabase) {
        return;
      }
      await _db.updateChatMessageContent(
        messageId: assistantId,
        content: request.isStructuredPrompt
            ? streamedDisplayText
            : buffer.toString(),
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
        final nextDisplayText = _extractStreamingDisplayText(
          promptName: request.promptName,
          responseText: buffer.toString(),
        );
        if (nextDisplayText == null ||
            nextDisplayText.length <= streamedDisplayText.length) {
          return;
        }
        final delta = nextDisplayText.substring(streamedDisplayText.length);
        streamedDisplayText = nextDisplayText;
        scheduleFlush();
        if (onChunk != null && delta.isNotEmpty) {
          onChunk(delta);
        }
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
        final displayText = resolution.payload.displayText;
        final delta = displayText.startsWith(streamedDisplayText)
            ? displayText.substring(streamedDisplayText.length)
            : displayText;
        if (delta.isNotEmpty) {
          onChunk(delta);
        }
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
    final parsed = resolution.payload.parsedJson == null
        ? null
        : _tryDecodeJsonObject(resolution.payload.parsedJson!);
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
    final session = await _db.getSession(request.sessionId);
    final currentControl = _loadSessionControlState(
      session,
      fallbackMode:
          request.actionMode == 'review' ? TutorMode.review : TutorMode.learn,
    );
    final nextControl =
        TutorControlState.fromAssistantPayload(parsed) ?? currentControl;
    final currentEvidence = _loadSessionEvidenceState(session);
    final nextEvidence = TutorEvidenceState.updateFromAssistantPayload(
      current: currentEvidence,
      actionMode: request.actionMode,
      parsed: parsed,
      passedLevel: request.reviewPassedLevel,
    );
    await _db.updateSessionContracts(
      sessionId: request.sessionId,
      controlStateJson: nextControl.toJsonText(),
      controlStateUpdatedAt: DateTime.now(),
      evidenceStateJson: nextEvidence.toJsonText(),
      evidenceStateUpdatedAt: DateTime.now(),
    );
    await _updateReviewProgressIfNeeded(
      actionMode: request.actionMode,
      studentId: request.llmContext.studentId,
      courseVersionId: request.courseVersionId,
      kpKey: request.kpKey,
      studentIntent: request.resolvedStudentIntent,
      parsedJsonText: resolution.payload.parsedJson,
      passedLevel: request.reviewPassedLevel,
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
    const llmPromptName = 'summarize';
    final session = await _db.getSession(sessionId);
    final currentControl = _loadSessionControlState(
      session,
      fallbackMode: TutorMode.learn,
    );
    final evidenceState = _loadSessionEvidenceState(session);
    final progress = session == null
        ? null
        : await _db.getProgress(
            studentId: session.studentId,
            courseVersionId: courseVersion.id,
            kpKey: node.kpKey,
          );
    final messages = await _db.getMessagesForSession(sessionId);
    final cachedSummary = _buildCachedSummaryResult(
      session: session,
      progress: progress,
      evidenceState: evidenceState,
    );
    if (cachedSummary != null) {
      await _llmLogRepository.appendEntry(
        promptName: llmPromptName,
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
    final lastEvidence = evidenceState.lastEvidence;
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
    final passedCounts = _resolvePassedCounts(
      progress: progress,
      evidenceState: evidenceState,
    );
    final bestPassedLevel = _bestPassedLevelFromCounts(passedCounts);
    final totalPassedCount = _totalPassedCount(passedCounts);
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
      'passed_counts_json': jsonEncode(passedCounts),
      'best_passed_level': bestPassedLevel ?? 'none',
      'total_passed_count': totalPassedCount.toString(),
      'current_lit': progress?.lit == true ? 'true' : 'false',
      'control_state_json': currentControl.toJsonText(),
      'evidence_state_json': evidenceState.toJsonText(),
      'evidence_policy': evidenceState.policy,
      'new_graded_review_evidence_available':
          evidenceState.hasNewGradedReviewEvidence ? 'true' : 'false',
      'practice_history_summary': _buildPracticeHistorySummary(
        messages,
        evidenceState: evidenceState,
        reviewOnly: true,
        maxMessages: 20,
      ),
      'error_book_summary': _buildErrorBookSummary(
        messages: messages,
        progress: progress,
        evidenceState: evidenceState,
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
          _masteryLevelFromPassedCounts(passedCounts) ?? 'NOT_PASS',
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

    final context = LlmCallContext(
      teacherId: courseVersion.teacherId,
      studentId: session?.studentId,
      courseVersionId: courseVersion.id,
      sessionId: sessionId,
      kpKey: node.kpKey,
      action: 'summary',
    );
    final handle = _llmService.startCall(
      promptName: llmPromptName,
      renderedPrompt: rendered,
      schemaMap: schema,
      modelOverride: modelOverride,
      context: context,
    );
    final future = handle.future.then((result) async {
      if (result.responseText.trim().isEmpty) {
        throw StateError('LLM returned an empty response.');
      }
      final resolution = await _resolveStructuredPayload(
        promptName: llmPromptName,
        renderedPrompt: rendered,
        modelOverride: modelOverride,
        context: context,
        schemaMap: schema,
        responseText: result.responseText,
        result: result,
      );
      final parsedJsonText = resolution.payload.parsedJson;
      final parsed =
          parsedJsonText == null ? null : _tryDecodeJsonObject(parsedJsonText);
      if (parsed == null) {
        throw StateError('Structured summary payload is missing parsed JSON.');
      }
      final litValue = parsed['lit'];
      if (litValue is! bool) {
        throw StateError(
          'Structured summary payload is missing a valid lit boolean.',
        );
      }
      final nextStep = _normalizeNextStep(parsed['next_step']);
      final litPercent = _litPercentFromBestPassedLevel(bestPassedLevel);
      final resolvedLit = litValue;
      final summary = resolution.payload.displayText;
      final summaryValid = true;
      final rawResponse = null;
      final nextControl =
          TutorControlState.fromAssistantPayload(parsed) ?? currentControl;
      final nextEvidence = TutorEvidenceState.updateFromAssistantPayload(
        current: evidenceState,
        actionMode: 'summary',
        parsed: parsed,
      );

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
          );
        }

        await (_db.update(_db.chatSessions)
              ..where((tbl) => tbl.id.equals(sessionId)))
            .write(
          ChatSessionsCompanion(
            summaryText: Value(summary),
            summaryLit: Value(resolvedLit),
            summaryRawResponse: Value(rawResponse),
            summaryValid: Value(summaryValid),
            status: const Value('active'),
            controlStateJson: Value(nextControl.toJsonText()),
            controlStateUpdatedAt: Value(DateTime.now()),
            evidenceStateJson: Value(nextEvidence.toJsonText()),
            evidenceStateUpdatedAt: Value(DateTime.now()),
          ),
        );

        await _db.into(_db.chatMessages).insert(
              ChatMessagesCompanion.insert(
                sessionId: sessionId,
                role: 'assistant',
                content: summary,
                rawContent: Value(resolution.payload.rawText),
                parsedJson: Value(resolution.payload.parsedJson),
                action: const Value('summary'),
              ),
            );
      });
      await _touchSessionSync(sessionId);

      return SummarizeResult(
        success: true,
        message: 'Summary stored.',
        lit: resolvedLit,
        litPercent: litPercent,
        summaryText: summary,
        masterLevel: bestPassedLevel,
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
    final control = parsed['control'];
    if (control is! Map<String, dynamic>) {
      throw StateError(
        'LLM response for "$promptName" is missing "control". '
        'Response preview: ${_summarizeResponseForError(responseText)}',
      );
    }
    final controlState = TutorControlState.fromJson(control);
    if (controlState == null) {
      throw StateError(
        'LLM response for "$promptName" has invalid "control". '
        'Response preview: ${_summarizeResponseForError(responseText)}',
      );
    }
    if (!controlState.turnFinished &&
        (controlState.allowedActions.isNotEmpty ||
            controlState.recommendedAction != null)) {
      throw StateError(
        'LLM response for "$promptName" cannot expose finished actions while turn_finished=false. '
        'Response preview: ${_summarizeResponseForError(responseText)}',
      );
    }
    if (controlState.recommendedAction != null &&
        !controlState.allowedActions.contains(controlState.recommendedAction)) {
      throw StateError(
        'LLM response for "$promptName" has recommended_action outside allowed_actions. '
        'Response preview: ${_summarizeResponseForError(responseText)}',
      );
    }
    if (promptName == 'review_init') {
      if (controlState.mode != TutorMode.review ||
          controlState.step != TutorTurnStep.continueTurn ||
          controlState.turnFinished) {
        throw StateError(
          'LLM response for "$promptName" has invalid review-init control state. '
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
    if (promptName == 'learn_init' || promptName == 'learn_cont') {
      if (!controlState.turnFinished) {
        if (controlState.mode != TutorMode.learn ||
            controlState.step != TutorTurnStep.continueTurn) {
          throw StateError(
            'LLM response for "$promptName" has invalid active learn control state. '
            'Response preview: ${_summarizeResponseForError(responseText)}',
          );
        }
      } else {
        if (controlState.mode != TutorMode.review ||
            controlState.step != TutorTurnStep.newTurn) {
          throw StateError(
            'LLM response for "$promptName" must finish into REVIEW/NEW. '
            'Response preview: ${_summarizeResponseForError(responseText)}',
          );
        }
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
      if (answerState == 'FINAL_ANSWER' && !controlState.turnFinished) {
        throw StateError(
          'LLM response for "$promptName" requires turn_state=FINISHED when answer_state=FINAL_ANSWER. '
          'Response preview: ${_summarizeResponseForError(responseText)}',
        );
      }
      if (controlState.turnFinished &&
          (controlState.mode != TutorMode.review ||
              controlState.step != TutorTurnStep.newTurn)) {
        throw StateError(
          'LLM response for "$promptName" must finish into REVIEW/NEW. '
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
    if ((promptName == 'summary' || promptName == 'summarize') &&
        !controlState.turnFinished) {
      throw StateError(
        'LLM response for "$promptName" must be a finished control state. '
        'Response preview: ${_summarizeResponseForError(responseText)}',
      );
    }
  }

  Set<String> _requiredStructuredKeys(String promptName) {
    switch (promptName) {
      case 'learn_init':
      case 'learn_cont':
        return {
          'teacher_message',
          'understanding',
          'control',
        };
      case 'review_init':
        return {
          'teacher_message',
          'control',
          'difficulty_level',
          'grading',
          'error_book_update',
          'evidence',
        };
      case 'review_cont':
        return {
          'teacher_message',
          'control',
          'answer_state',
          'grading',
          'error_book_update',
          'evidence',
        };
      case 'summary':
      case 'summarize':
        return {
          'teacher_message',
          'control',
          'lit',
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

  Map<String, int> _resolvePassedCounts({
    required ProgressEntry? progress,
    required TutorEvidenceState evidenceState,
  }) {
    final easy = progress?.easyPassedCount ?? 0;
    final medium = progress?.mediumPassedCount ?? 0;
    final hard = progress?.hardPassedCount ?? 0;
    return <String, int>{
      'easy': easy >= evidenceState.easyPassedCount
          ? easy
          : evidenceState.easyPassedCount,
      'medium': medium >= evidenceState.mediumPassedCount
          ? medium
          : evidenceState.mediumPassedCount,
      'hard': hard >= evidenceState.hardPassedCount
          ? hard
          : evidenceState.hardPassedCount,
    };
  }

  String? _bestPassedLevelFromCounts(Map<String, int> counts) {
    if ((counts['hard'] ?? 0) > 0) {
      return 'hard';
    }
    if ((counts['medium'] ?? 0) > 0) {
      return 'medium';
    }
    if ((counts['easy'] ?? 0) > 0) {
      return 'easy';
    }
    return null;
  }

  int _litPercentFromBestPassedLevel(String? level) {
    switch (level) {
      case 'easy':
        return 33;
      case 'medium':
        return 66;
      case 'hard':
        return 100;
      default:
        return 0;
    }
  }

  int _totalPassedCount(Map<String, int> counts) {
    return (counts['easy'] ?? 0) +
        (counts['medium'] ?? 0) +
        (counts['hard'] ?? 0);
  }

  String? _reviewPassedLevelForPrompt({
    required String promptName,
    required String currentDifficultyLevel,
    required Map<String, dynamic>? previousAssistantJson,
  }) {
    if (promptName == 'review_init') {
      final level =
          _normalizeLevel(previousAssistantJson?['difficulty_level']) ??
              _normalizeLevel(currentDifficultyLevel);
      return level;
    }
    if (promptName == 'review_cont') {
      final level =
          _normalizeLevel(previousAssistantJson?['difficulty_level']) ??
              _normalizeLevel(currentDifficultyLevel);
      return level;
    }
    return null;
  }

  String? _masteryLevelFromPassedCounts(Map<String, int> counts) {
    final bestPassedLevel = _bestPassedLevelFromCounts(counts);
    if (bestPassedLevel == null) {
      return null;
    }
    switch (bestPassedLevel) {
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

  String _reviewDifficultyLevelFromPassedCounts(Map<String, int> counts) {
    if ((counts['medium'] ?? 0) > 0 || (counts['hard'] ?? 0) > 0) {
      return 'hard';
    }
    if ((counts['easy'] ?? 0) > 0) {
      return 'medium';
    }
    return 'easy';
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
    required TutorControlState sessionControl,
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
      String promptName;
      final continueRequested =
          sessionControl.step == TutorTurnStep.continueTurn;
      if (actionMode == 'learn') {
        promptName = continueRequested ? 'learn_cont' : 'learn_init';
      } else {
        promptName = continueRequested ? 'review_cont' : 'review_init';
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

  TutorControlState _loadSessionControlState(
    ChatSession? session, {
    required TutorMode fallbackMode,
  }) {
    final stored = TutorControlState.fromJsonText(session?.controlStateJson);
    if (stored != null) {
      return stored;
    }
    return TutorControlState.defaultForMode(fallbackMode);
  }

  TutorEvidenceState _loadSessionEvidenceState(ChatSession? session) {
    return TutorEvidenceState.fromJsonText(session?.evidenceStateJson) ??
        TutorEvidenceState.initial();
  }

  String _buildPracticeHistorySummary(
    List<ChatMessage> messages, {
    TutorEvidenceState? evidenceState,
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
      if (reviewOnly && evidenceState?.hasNewGradedReviewEvidence == true) {
        return 'A graded review happened recently, but the raw review history is unavailable on this device.';
      }
      return 'No practice history yet.';
    }
    return _buildHistory(tail);
  }

  String _buildErrorBookSummary({
    required List<ChatMessage> messages,
    ProgressEntry? progress,
    Map<String, dynamic>? previousJson,
    TutorEvidenceState? evidenceState,
  }) {
    final aggregated = _aggregateErrorBook(messages);
    if (aggregated != null && aggregated.isNotEmpty) {
      return jsonEncode(aggregated);
    }
    final errorBookUpdate = previousJson?['error_book_update'];
    if (errorBookUpdate is Map<String, dynamic> && errorBookUpdate.isNotEmpty) {
      return jsonEncode(errorBookUpdate);
    }
    if (evidenceState?.lastEvidence != null) {
      return jsonEncode(
        <String, dynamic>{
          'source': 'evidence_state',
          'last_evidence': evidenceState!.lastEvidence,
        },
      );
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

  Future<void> _updateReviewProgressIfNeeded({
    required String actionMode,
    required int? studentId,
    required int courseVersionId,
    required String kpKey,
    required String studentIntent,
    required String? parsedJsonText,
    required String? passedLevel,
  }) async {
    if (actionMode != 'review' || studentId == null || studentId <= 0) {
      return;
    }
    final parsed =
        parsedJsonText == null ? null : _tryDecodeJsonObject(parsedJsonText);
    if (parsed == null) {
      return;
    }
    final controlState = TutorControlState.fromAssistantPayload(parsed);
    final turnFinished = controlState?.turnFinished ?? false;
    final grading = parsed['grading'];
    final isCorrect = grading is Map<String, dynamic> &&
        grading['is_correct'] is bool &&
        grading['is_correct'] == true;
    if (turnFinished && isCorrect && passedLevel != null) {
      await _db.incrementProgressPassedCount(
        studentId: studentId,
        courseVersionId: courseVersionId,
        kpKey: kpKey,
        passedLevel: passedLevel,
      );
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
    if (promptName == 'summary' || promptName == 'summarize') {
      final summaryText = parsed['summary_text'];
      if (summaryText is String && summaryText.trim().isNotEmpty) {
        return summaryText.trim();
      }
    }
    return fallback;
  }

  String? _extractStreamingDisplayText({
    required String promptName,
    required String responseText,
  }) {
    final fieldNames = promptName == 'summary' || promptName == 'summarize'
        ? const <String>['teacher_message', 'summary_text']
        : const <String>['teacher_message'];
    for (final fieldName in fieldNames) {
      final extracted = _extractJsonStringFieldPrefix(
        responseText: responseText,
        fieldName: fieldName,
      );
      if (extracted != null) {
        return extracted;
      }
    }
    return null;
  }

  String? _extractJsonStringFieldPrefix({
    required String responseText,
    required String fieldName,
  }) {
    final keyToken = '"$fieldName"';
    final keyIndex = responseText.indexOf(keyToken);
    if (keyIndex < 0) {
      return null;
    }
    var index = keyIndex + keyToken.length;
    while (index < responseText.length &&
        _isJsonWhitespace(responseText.codeUnitAt(index))) {
      index += 1;
    }
    if (index >= responseText.length || responseText[index] != ':') {
      return null;
    }
    index += 1;
    while (index < responseText.length &&
        _isJsonWhitespace(responseText.codeUnitAt(index))) {
      index += 1;
    }
    if (index >= responseText.length || responseText[index] != '"') {
      return null;
    }
    return _readJsonStringPrefix(
      responseText: responseText,
      startIndex: index + 1,
    ).value;
  }

  bool _isJsonWhitespace(int codeUnit) {
    return codeUnit == 0x20 ||
        codeUnit == 0x09 ||
        codeUnit == 0x0A ||
        codeUnit == 0x0D;
  }

  _JsonStringPrefixResult _readJsonStringPrefix({
    required String responseText,
    required int startIndex,
  }) {
    final buffer = StringBuffer();
    var index = startIndex;
    while (index < responseText.length) {
      final char = responseText[index];
      if (char == '"') {
        return _JsonStringPrefixResult(
          value: buffer.toString(),
        );
      }
      if (char != r'\') {
        buffer.write(char);
        index += 1;
        continue;
      }
      if (index + 1 >= responseText.length) {
        return _JsonStringPrefixResult(
          value: buffer.toString(),
        );
      }
      final escaped = responseText[index + 1];
      switch (escaped) {
        case '"':
        case r'\':
        case '/':
          buffer.write(escaped);
          index += 2;
          break;
        case 'b':
          buffer.write('\b');
          index += 2;
          break;
        case 'f':
          buffer.write('\f');
          index += 2;
          break;
        case 'n':
          buffer.write('\n');
          index += 2;
          break;
        case 'r':
          buffer.write('\r');
          index += 2;
          break;
        case 't':
          buffer.write('\t');
          index += 2;
          break;
        case 'u':
          if (index + 5 >= responseText.length) {
            return _JsonStringPrefixResult(
              value: buffer.toString(),
            );
          }
          final hexDigits = responseText.substring(index + 2, index + 6);
          final codePoint = int.tryParse(hexDigits, radix: 16);
          if (codePoint == null) {
            return _JsonStringPrefixResult(
              value: buffer.toString(),
            );
          }
          buffer.write(String.fromCharCode(codePoint));
          index += 6;
          break;
        default:
          return _JsonStringPrefixResult(
            value: buffer.toString(),
          );
      }
    }
    return _JsonStringPrefixResult(
      value: buffer.toString(),
    );
  }

  bool _isStructuredPrompt(String promptName) {
    return promptName == 'learn_init' ||
        promptName == 'learn_cont' ||
        promptName == 'review_init' ||
        promptName == 'review_cont' ||
        promptName == 'summary' ||
        promptName == 'summarize';
  }

  SummarizeResult? _buildCachedSummaryResult({
    required ChatSession? session,
    required ProgressEntry? progress,
    required TutorEvidenceState evidenceState,
  }) {
    if (session == null) {
      return null;
    }
    if (evidenceState.hasNewGradedReviewEvidence) {
      return null;
    }
    final summaryText =
        (progress?.summaryText ?? session.summaryText ?? '').trim();
    if (summaryText.isEmpty) {
      return null;
    }
    if (progress == null && session.summaryLit == null) {
      return null;
    }
    final passedCounts = _resolvePassedCounts(
      progress: progress,
      evidenceState: evidenceState,
    );
    final lit = progress?.lit ?? session.summaryLit ?? false;
    final litPercent = _litPercentFromBestPassedLevel(
      _bestPassedLevelFromCounts(passedCounts),
    );
    final bestPassedLevel = _bestPassedLevelFromCounts(passedCounts);
    return SummarizeResult(
      success: true,
      message: 'Summary unchanged. Reused cached result.',
      lit: lit,
      litPercent: litPercent > 0 ? litPercent : (lit ? 100 : 0),
      summaryText: summaryText,
      masterLevel: bestPassedLevel,
      nextStep: lit ? 'MOVE_ON' : 'CONTINUE_REVIEW',
    );
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
      case 'summarize':
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
    final reasoningEffort = ReasoningEffort.normalize(settings.reasoningEffort);
    final callHash = LlmHash.compute(
      baseUrl: settings.baseUrl,
      model: activeModel,
      reasoningEffort: reasoningEffort,
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
    )
        .then((_) async {
      if (_sessionUploadCacheService != null) {
        await _sessionUploadCacheService.captureSession(sessionId);
      }
    });
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
