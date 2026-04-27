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
import 'course_artifact_service.dart';
import 'llm_log_repository.dart';
import 'prompt_variable_registry.dart';
import 'session_upload_cache_service.dart';
import 'settings_repository.dart';

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
    required this.availableReviewDifficulties,
    this.reviewQuestionDifficulty,
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
  final Set<String> availableReviewDifficulties;
  final String? reviewQuestionDifficulty;
  final String? reviewPassedLevel;
}

class _ProgressPassSnapshot {
  const _ProgressPassSnapshot({
    required this.easyPassedCount,
    required this.mediumPassedCount,
    required this.hardPassedCount,
    required this.lit,
    required this.litPercent,
  });

  final int easyPassedCount;
  final int mediumPassedCount;
  final int hardPassedCount;
  final bool lit;
  final int litPercent;
}

class SessionService {
  SessionService(
    this._db,
    this._llmService,
    this._promptRepository,
    this._settingsRepository,
    this._llmLogRepository, {
    CourseArtifactService? courseArtifactService,
    SessionUploadCacheService? sessionUploadCacheService,
  })  : _courseArtifactService = courseArtifactService,
        _sessionUploadCacheService = sessionUploadCacheService;

  final AppDatabase _db;
  final LlmService _llmService;
  final PromptRepository _promptRepository;
  final SettingsRepository _settingsRepository;
  final LlmLogRepository _llmLogRepository;
  final CourseArtifactService? _courseArtifactService;
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

  Future<void> waitForInFlightTutorActions() async {
    while (_inflightTutorByKey.isNotEmpty) {
      final handles = _inflightTutorByKey.values.toList(growable: false);
      await Future.wait(handles.map(_waitForTutorHandleQuietly));
    }
  }

  Future<void> _waitForTutorHandleQuietly(LlmRequestHandle handle) async {
    try {
      await handle.future;
    } catch (_) {
      // The final sync should still upload the saved user message/error state.
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
    var questionTextsByLevel = const <String, String>{};
    var availableReviewDifficulties = const <String>{};
    String? reviewQuestionDifficulty;
    if (actionMode == 'review') {
      questionTextsByLevel = await _loadQuestionTextsByLevel(
        courseVersion: courseVersion,
        kpKey: node.kpKey,
      );
      availableReviewDifficulties =
          _availableReviewDifficulties(questionTextsByLevel);
      reviewQuestionDifficulty = _resolveReviewQuestionDifficulty(
        promptName: promptName,
        controlState: controlState,
        progress: progress,
        helpBias: resolvedHelpBias,
        availableLevels: availableReviewDifficulties,
      );
    }
    final history = _buildHistory(messages);
    final recentChat = _buildRecentChat(messages);
    final passedCounts = _resolvePassedCounts(
      progress: progress,
      evidenceState: evidenceState,
    );
    final failedCounts = _resolveFailedCounts(
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
    final values = PromptVariableRegistry.buildTutorPromptValues(
      kpTitle: node.title,
      kpDescription: node.description,
      studentInput: studentInput.trim(),
      recentChat: recentChat,
      conversationHistory: history,
      helpBias: resolvedHelpBias,
      studentSummary: progress?.summaryText ?? session?.summaryText ?? '',
      studentContext: _buildStudentContext(
        helpBias: resolvedHelpBias,
        studentProfile: studentPromptContext.profileText,
        studentPreferences: studentPromptContext.preferencesText,
      ),
      studentProfile: studentPromptContext.profileText,
      studentPreferences: studentPromptContext.preferencesText,
      lessonContent: '',
      errorBookSummary: errorBookSummary,
      presentedQuestions: '',
      activeReviewQuestionJson: controlState.activeReviewQuestion == null
          ? 'null'
          : jsonEncode(controlState.activeReviewQuestion),
      reviewPassCounts: jsonEncode(passedCounts),
      reviewFailCounts: jsonEncode(failedCounts),
      reviewCorrectTotal: evidenceState.reviewCorrectTotal.toString(),
      reviewAttemptTotal: evidenceState.reviewAttemptTotal.toString(),
    );
    final needsLessonContent = promptName == 'learn';
    if (needsLessonContent) {
      final lessonContent = await _loadLectureTextIfPresent(
        courseVersion: courseVersion,
        kpKey: node.kpKey,
      );
      values[PromptVariableRegistry.lessonContent] = lessonContent;
    }
    if (actionMode == 'review') {
      if (promptName == PromptVariableRegistry.reviewInitPrompt) {
        values[PromptVariableRegistry.presentedQuestions] =
            _questionsTextForDifficulty(
          questionTextsByLevel: questionTextsByLevel,
          difficulty: reviewQuestionDifficulty,
        );
      }
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
      availableReviewDifficulties: availableReviewDifficulties,
      reviewQuestionDifficulty: reviewQuestionDifficulty,
      reviewPassedLevel: _reviewPassedLevelForPrompt(
        promptName: promptName,
        controlState: controlState,
        reviewQuestionDifficulty: reviewQuestionDifficulty,
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
    final decodedParsed = resolution.payload.parsedJson == null
        ? null
        : _tryDecodeJsonObject(resolution.payload.parsedJson!);
    final parsed = _augmentReviewParsedJsonForPersistence(
      request: request,
      parsed: decodedParsed,
    );
    final parsedJsonText = parsed == null ? null : jsonEncode(parsed);
    if (assistantMessageId == null) {
      await _db.into(_db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: request.sessionId,
              role: 'assistant',
              content: resolution.payload.displayText,
              rawContent: Value(resolution.payload.rawText),
              parsedJson: Value(parsedJsonText),
              action: Value(request.actionMode),
            ),
          );
    } else {
      await _db.updateChatMessageAssistantPayload(
        messageId: assistantMessageId,
        content: resolution.payload.displayText,
        rawContent: resolution.payload.rawText,
        parsedJson: parsedJsonText,
      );
    }
    final session = await _db.getSession(request.sessionId);
    final currentControl = _loadSessionControlState(
      session,
      fallbackMode:
          request.actionMode == 'review' ? TutorMode.review : TutorMode.learn,
    );
    final currentEvidence = _loadSessionEvidenceState(session);
    final shouldCountReviewAttempt = request.actionMode == 'review' &&
        currentControl.hasActiveReviewQuestion;
    final nextEvidence = TutorEvidenceState.updateFromAssistantPayload(
      current: currentEvidence,
      actionMode: request.actionMode,
      parsed: parsed,
      hadActiveReviewQuestion: shouldCountReviewAttempt,
      passedLevel: request.reviewPassedLevel,
    );
    final studentId = request.llmContext.studentId;
    TutorJustPassedKpEvent? nextJustPassedKpEvent =
        currentControl.justPassedKpEvent;
    _ProgressPassSnapshot? previousProgressSnapshot;
    ResolvedStudentPassRule? passRule;
    if (request.actionMode == 'review' && studentId != null && studentId > 0) {
      passRule = await _db.resolveStudentPassRule(
        courseVersionId: request.courseVersionId,
        studentId: studentId,
      );
      previousProgressSnapshot = _resolveProgressPassSnapshot(
        progress: await _db.getProgress(
          studentId: studentId,
          courseVersionId: request.courseVersionId,
          kpKey: request.kpKey,
        ),
        passRule: passRule,
      );
    }
    await _updateReviewProgressIfNeeded(
      actionMode: request.actionMode,
      studentId: studentId,
      courseVersionId: request.courseVersionId,
      kpKey: request.kpKey,
      studentIntent: request.resolvedStudentIntent,
      parsedJsonText: parsedJsonText,
      passedLevel: request.reviewPassedLevel,
      shouldCountReviewAttempt: shouldCountReviewAttempt,
    );
    if (request.actionMode == 'review' && studentId != null && studentId > 0) {
      final progress = await _db.getProgress(
        studentId: studentId,
        courseVersionId: request.courseVersionId,
        kpKey: request.kpKey,
      );
      final resolvedSnapshot = _resolveProgressPassSnapshot(
        progress: progress,
        passRule: passRule!,
      );
      if (previousProgressSnapshot != null &&
          !previousProgressSnapshot.lit &&
          resolvedSnapshot.lit) {
        nextJustPassedKpEvent = TutorJustPassedKpEvent(
          easyPassedCount: resolvedSnapshot.easyPassedCount,
          mediumPassedCount: resolvedSnapshot.mediumPassedCount,
          hardPassedCount: resolvedSnapshot.hardPassedCount,
        );
      }
      await (_db.update(_db.chatSessions)
            ..where((tbl) => tbl.id.equals(request.sessionId)))
          .write(
        ChatSessionsCompanion(
          summaryLit: Value(resolvedSnapshot.lit),
          summaryLitPercent: Value(resolvedSnapshot.litPercent),
        ),
      );
      await _db.setProgressLit(
        studentId: studentId,
        courseVersionId: request.courseVersionId,
        kpKey: request.kpKey,
        lit: resolvedSnapshot.lit,
        litPercent: resolvedSnapshot.litPercent,
      );
    }
    final nextControl = _deriveNextControlState(
      current: currentControl,
      actionMode: request.actionMode,
      promptName: request.promptName,
      parsed: parsed,
      displayText: resolution.payload.displayText,
      reviewQuestionDifficulty: request.reviewQuestionDifficulty,
      availableReviewDifficulties: request.availableReviewDifficulties,
      helpBias: _normalizeHelpBias(parsed?['next_help_bias'] as String?),
    ).copyWith(
      justPassedKpEvent: nextJustPassedKpEvent,
    );
    final nextQuestionLevel = _normalizeLevel(
      nextControl.currentReviewDifficulty,
    );
    if (request.actionMode == 'review' &&
        studentId != null &&
        studentId > 0 &&
        nextQuestionLevel != null) {
      await _db.setProgressQuestionLevel(
        studentId: studentId,
        courseVersionId: request.courseVersionId,
        kpKey: request.kpKey,
        questionLevel: nextQuestionLevel,
      );
    }
    await _db.updateSessionContracts(
      sessionId: request.sessionId,
      controlStateJson: nextControl.toJsonText(),
      controlStateUpdatedAt: DateTime.now(),
      evidenceStateJson: nextEvidence.toJsonText(),
      evidenceStateUpdatedAt: DateTime.now(),
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
    final historyValue =
        (values[PromptVariableRegistry.conversationHistory] ?? '').toString();
    final usesHistory =
        _hasVariable(template, PromptVariableRegistry.conversationHistory) ||
            _hasVariable(template, PromptVariableRegistry.sessionHistory);
    String renderWithHistory(String history) {
      final updated = Map<String, Object?>.from(values);
      updated[PromptVariableRegistry.conversationHistory] = history;
      updated[PromptVariableRegistry.sessionHistory] = history;
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
    final teacherMessage = parsed['text'];
    if (teacherMessage is! String || teacherMessage.trim().isEmpty) {
      throw StateError(
        'LLM response for "$promptName" is missing visible text. '
        'Response preview: ${_summarizeResponseForError(responseText)}',
      );
    }
    if (promptName == PromptVariableRegistry.reviewContPrompt) {
      final finished = parsed['finished'];
      if (finished is! bool) {
        throw StateError(
          'LLM response for "$promptName" is missing boolean "finished". '
          'Response preview: ${_summarizeResponseForError(responseText)}',
        );
      }
      final mistakeTags = parsed['mistakes'];
      if (mistakeTags is! List ||
          mistakeTags.any(
            (item) => item is! String || item.trim().isEmpty,
          )) {
        throw StateError(
          'LLM response for "$promptName" has invalid "mistakes". '
          'Response preview: ${_summarizeResponseForError(responseText)}',
        );
      }
      final difficultyAdjustment =
          _normalizeDifficultyAdjustment(parsed['difficulty_adjustment']);
      if (difficultyAdjustment == null) {
        throw StateError(
          'LLM response for "$promptName" has invalid "difficulty_adjustment". '
          'Response preview: ${_summarizeResponseForError(responseText)}',
        );
      }
    }
  }

  Set<String> _requiredStructuredKeys(String promptName) {
    switch (promptName) {
      case PromptVariableRegistry.reviewContPrompt:
        return {
          'text',
          'mistakes',
          'finished',
          'difficulty_adjustment',
        };
      default:
        return {'text'};
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

  String _resolveReviewQuestionDifficulty({
    required String promptName,
    required TutorControlState controlState,
    required ProgressEntry? progress,
    required String helpBias,
    required Set<String> availableLevels,
  }) {
    if (promptName == PromptVariableRegistry.reviewContPrompt) {
      final activeDifficulty =
          _normalizeLevel(controlState.activeReviewQuestion?['difficulty']);
      if (activeDifficulty != null) {
        return _clampReviewDifficulty(
          activeDifficulty,
          availableLevels: availableLevels,
        );
      }
    }
    final bias = helpBias.trim().toUpperCase();
    final target = bias == TutorHelpBias.harder.wireValue
        ? 'hard'
        : bias == TutorHelpBias.easier.wireValue
            ? 'easy'
            : _normalizeLevel(controlState.currentReviewDifficulty) ??
                _normalizeLevel(progress?.questionLevel) ??
                'medium';
    return _clampReviewDifficulty(
      target,
      availableLevels: availableLevels,
    );
  }

  String _applyReviewDifficultyAdjustment({
    required String? currentDifficulty,
    required Object? adjustment,
    required Set<String> availableLevels,
  }) {
    final normalizedAdjustment = _normalizeDifficultyAdjustment(adjustment);
    final current = _clampReviewDifficulty(
      _normalizeLevel(currentDifficulty) ?? 'medium',
      availableLevels: availableLevels,
    );
    if (normalizedAdjustment == null || normalizedAdjustment == 'same') {
      return current;
    }
    const order = <String>['easy', 'medium', 'hard'];
    final currentIndex = order.indexOf(current);
    final rawTargetIndex =
        normalizedAdjustment == 'harder' ? currentIndex + 1 : currentIndex - 1;
    final targetIndex = rawTargetIndex < 0
        ? 0
        : rawTargetIndex >= order.length
            ? order.length - 1
            : rawTargetIndex;
    return _clampReviewDifficulty(
      order[targetIndex],
      availableLevels: availableLevels,
      tieBias: normalizedAdjustment,
    );
  }

  String _clampReviewDifficulty(
    String target, {
    required Set<String> availableLevels,
    String tieBias = 'harder',
  }) {
    final normalizedTarget = _normalizeLevel(target) ?? 'medium';
    final normalizedAvailable =
        availableLevels.map(_normalizeLevel).whereType<String>().toSet();
    if (normalizedAvailable.isEmpty ||
        normalizedAvailable.contains(normalizedTarget)) {
      return normalizedTarget;
    }
    const order = <String>['easy', 'medium', 'hard'];
    final targetIndex = order.indexOf(normalizedTarget);
    var best = normalizedAvailable.first;
    var bestIndex = order.indexOf(best);
    var bestDistance = (bestIndex - targetIndex).abs();
    for (final candidate in normalizedAvailable.skip(1)) {
      final candidateIndex = order.indexOf(candidate);
      final distance = (candidateIndex - targetIndex).abs();
      final shouldPreferTie = tieBias == 'easier'
          ? candidateIndex < bestIndex
          : candidateIndex > bestIndex;
      if (distance < bestDistance ||
          (distance == bestDistance && shouldPreferTie)) {
        best = candidate;
        bestIndex = candidateIndex;
        bestDistance = distance;
      }
    }
    return best;
  }

  String? _normalizeDifficultyAdjustment(Object? value) {
    if (value is! String) {
      return null;
    }
    final normalized = value.trim().toLowerCase();
    if (normalized == 'easier' ||
        normalized == 'same' ||
        normalized == 'harder') {
      return normalized;
    }
    return null;
  }

  String? _normalizeNextAction(Object? value) {
    if (value is! String) {
      return null;
    }
    final normalized = value.trim().toLowerCase();
    if (normalized == 'learn' || normalized == 'review') {
      return normalized;
    }
    return null;
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

  Map<String, int> _resolveFailedCounts({
    required TutorEvidenceState evidenceState,
  }) {
    return <String, int>{
      'easy': evidenceState.easyFailedCount,
      'medium': evidenceState.mediumFailedCount,
      'hard': evidenceState.hardFailedCount,
    };
  }

  String _buildStudentContext({
    required String helpBias,
    required String studentProfile,
    required String studentPreferences,
  }) {
    final lines = <String>[];
    final normalizedHelpBias = helpBias.trim();
    if (normalizedHelpBias.isNotEmpty &&
        normalizedHelpBias != TutorHelpBias.unchanged.wireValue) {
      lines.add('Help bias: $normalizedHelpBias');
    }
    final profile = studentProfile.trim();
    if (profile.isNotEmpty) {
      lines.add('Profile: $profile');
    }
    final preferences = studentPreferences.trim();
    if (preferences.isNotEmpty) {
      lines.add('Preferences: $preferences');
    }
    return lines.join('\n');
  }

  String? _reviewPassedLevelForPrompt({
    required String promptName,
    required TutorControlState controlState,
    required String? reviewQuestionDifficulty,
  }) {
    if (promptName == PromptVariableRegistry.reviewContPrompt) {
      return _normalizeLevel(
              controlState.activeReviewQuestion?['difficulty']) ??
          reviewQuestionDifficulty;
    }
    return null;
  }

  Future<String> _loadLectureText({
    required CourseVersion courseVersion,
    required String kpKey,
  }) async {
    final basePath = courseVersion.sourcePath?.trim() ?? '';
    if (basePath.isNotEmpty) {
      final path = p.join(basePath, '${kpKey}_lecture.txt');
      final legacy = p.join(basePath, kpKey, 'lecture.txt');
      final file = File(path).existsSync() ? File(path) : File(legacy);
      if (file.existsSync()) {
        return file.readAsString(encoding: utf8);
      }
    }
    final fallback = await _readTextFromStoredBundle(
      courseVersionId: courseVersion.id,
      candidateRelativePaths: <String>[
        '${kpKey}_lecture.txt',
        p.join(kpKey, 'lecture.txt'),
      ],
    );
    if (fallback != null) {
      return fallback;
    }
    throw StateError(
        'Missing lecture file for course ${courseVersion.id}: $kpKey');
  }

  Future<Map<String, String>> _loadQuestionTextsByLevel({
    required CourseVersion courseVersion,
    required String kpKey,
  }) async {
    final result = <String, String>{};
    for (final level in const <String>['easy', 'medium', 'hard']) {
      final text = await _loadQuestionTextForLevel(
        courseVersion: courseVersion,
        kpKey: kpKey,
        level: level,
      );
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      result[level] = trimmed;
    }
    return result;
  }

  Set<String> _availableReviewDifficulties(Map<String, String> textsByLevel) {
    return textsByLevel.entries
        .where((entry) => entry.value.trim().isNotEmpty)
        .map((entry) => entry.key)
        .where((level) => _normalizeLevel(level) != null)
        .toSet();
  }

  String _questionsTextForDifficulty({
    required Map<String, String> questionTextsByLevel,
    required String? difficulty,
  }) {
    final normalized = _normalizeLevel(difficulty);
    if (normalized == null) {
      return '';
    }
    return questionTextsByLevel[normalized]?.trim() ?? '';
  }

  Future<String> _loadQuestionTextForLevel({
    required CourseVersion courseVersion,
    required String kpKey,
    required String level,
  }) async {
    final basePath = courseVersion.sourcePath?.trim() ?? '';
    if (basePath.isNotEmpty) {
      final path = p.join(basePath, '${kpKey}_$level.txt');
      final legacy = p.join(basePath, kpKey, level, 'questions.txt');
      final file = File(path).existsSync() ? File(path) : File(legacy);
      if (file.existsSync()) {
        return file.readAsString(encoding: utf8);
      }
    }
    return await _readTextFromStoredBundle(
          courseVersionId: courseVersion.id,
          candidateRelativePaths: <String>[
            '${kpKey}_$level.txt',
            p.join(kpKey, level, 'questions.txt'),
          ],
        ) ??
        '';
  }

  Future<String?> _readTextFromStoredBundle({
    required int courseVersionId,
    required List<String> candidateRelativePaths,
  }) async {
    final artifactService = _courseArtifactService;
    if (artifactService == null) {
      return null;
    }
    return artifactService.readStoredTextEntry(
      courseVersionId: courseVersionId,
      candidateRelativePaths: candidateRelativePaths,
    );
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
    final actionMode = _resolveActionMode(normalized);
    if (actionMode == 'learn') {
      final previous = _findLastAssistantForActionMode(
        messages: messages,
        actionMode: actionMode,
      );
      return _TutorPromptResolution(
        promptName: PromptVariableRegistry.learnPrompt,
        lastAssistantIndex: previous?.index,
        prevJson: previous?.json,
      );
    }
    if (actionMode == 'review') {
      final previous = _findLastAssistantForActionMode(
        messages: messages,
        actionMode: actionMode,
      );
      final explicitReviewPrompt =
          normalized == PromptVariableRegistry.reviewInitPrompt ||
              normalized == PromptVariableRegistry.reviewContPrompt;
      final promptName = explicitReviewPrompt
          ? normalized
          : (sessionControl.hasActiveReviewQuestion ||
                  studentInput.trim().isNotEmpty
              ? PromptVariableRegistry.reviewContPrompt
              : PromptVariableRegistry.reviewInitPrompt);
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

  String _buildRecentChat(
    List<ChatMessage> messages, {
    int maxMessages = 8,
  }) {
    if (messages.isEmpty) {
      return '';
    }
    final start =
        messages.length > maxMessages ? messages.length - maxMessages : 0;
    return _buildHistory(messages.sublist(start));
  }

  TutorControlState _deriveNextControlState({
    required TutorControlState current,
    required String actionMode,
    required String promptName,
    required Map<String, dynamic>? parsed,
    required String displayText,
    required String? reviewQuestionDifficulty,
    required Set<String> availableReviewDifficulties,
    required String helpBias,
  }) {
    final resolvedHelpBias =
        TutorHelpBias.fromWire(helpBias) ?? current.helpBias;
    if (actionMode == 'review' &&
        promptName == PromptVariableRegistry.reviewInitPrompt) {
      final difficulty = _clampReviewDifficulty(
        reviewQuestionDifficulty ??
            _normalizeLevel(current.currentReviewDifficulty) ??
            'medium',
        availableLevels: availableReviewDifficulties,
      );
      return current.copyWith(
        mode: TutorMode.review,
        step: TutorTurnStep.continueTurn,
        turnFinished: false,
        helpBias: resolvedHelpBias,
        recommendedAction: null,
        activeReviewQuestion: _buildInitialActiveReviewQuestion(
          text: displayText,
          difficulty: difficulty,
        ),
        currentReviewDifficulty: difficulty,
      );
    }
    if (parsed == null) {
      if (actionMode == 'learn') {
        return current.copyWith(
          mode: TutorMode.learn,
          step: TutorTurnStep.newTurn,
          turnFinished: true,
          helpBias: resolvedHelpBias,
          recommendedAction: null,
          activeReviewQuestion: null,
        );
      }
      return current.copyWith(helpBias: resolvedHelpBias);
    }
    if (actionMode == 'review' &&
        promptName == PromptVariableRegistry.reviewContPrompt) {
      final finished = parsed['finished'];
      if (finished is bool) {
        final currentQuestionDifficulty =
            _normalizeLevel(current.activeReviewQuestion?['difficulty']) ??
                _normalizeLevel(reviewQuestionDifficulty) ??
                _normalizeLevel(current.currentReviewDifficulty) ??
                'medium';
        final nextDifficulty = _applyReviewDifficultyAdjustment(
          currentDifficulty: currentQuestionDifficulty,
          adjustment: parsed['difficulty_adjustment'],
          availableLevels: availableReviewDifficulties,
        );
        final nextQuestion = finished
            ? null
            : _buildActiveReviewQuestion(
                currentQuestion: current.activeReviewQuestion,
                parsed: parsed,
                fallbackDifficulty: currentQuestionDifficulty,
              );
        return current.copyWith(
          mode: TutorMode.review,
          step: finished ? TutorTurnStep.newTurn : TutorTurnStep.continueTurn,
          turnFinished: finished,
          helpBias: resolvedHelpBias,
          recommendedAction: null,
          activeReviewQuestion: nextQuestion,
          currentReviewDifficulty: nextDifficulty,
        );
      }
    }
    if (actionMode == 'learn') {
      final nextAction = TutorFinishedAction.fromWire(
        _normalizeNextAction(parsed['next_action'])?.toUpperCase(),
      );
      return current.copyWith(
        mode: TutorMode.learn,
        step: TutorTurnStep.newTurn,
        turnFinished: true,
        helpBias: resolvedHelpBias,
        recommendedAction: nextAction,
        activeReviewQuestion: null,
      );
    }
    final fallback = TutorControlState.fromAssistantPayload(parsed);
    if (fallback != null) {
      return fallback.copyWith(helpBias: resolvedHelpBias);
    }
    return current.copyWith(helpBias: resolvedHelpBias);
  }

  Map<String, dynamic>? _buildActiveReviewQuestion({
    required Map<String, dynamic>? currentQuestion,
    required Map<String, dynamic> parsed,
    required String fallbackDifficulty,
  }) {
    final next = <String, dynamic>{};
    if (currentQuestion != null) {
      next.addAll(currentQuestion);
    }
    final difficultyLevel = _normalizeLevel(next['difficulty']) ??
        _normalizeLevel(parsed['difficulty']) ??
        _normalizeLevel(fallbackDifficulty);
    if (difficultyLevel != null) {
      next['difficulty'] = difficultyLevel;
    }
    final mistakeTags = parsed['mistakes'];
    if (mistakeTags is List) {
      next['mistakes'] = mistakeTags
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return next.isEmpty ? null : next;
  }

  Map<String, dynamic> _buildInitialActiveReviewQuestion({
    required String text,
    required String difficulty,
  }) {
    final trimmedText = text.trim();
    return <String, dynamic>{
      if (trimmedText.isNotEmpty) 'text': trimmedText,
      'difficulty': difficulty,
    };
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

  _ProgressPassSnapshot _resolveProgressPassSnapshot({
    required ProgressEntry? progress,
    required ResolvedStudentPassRule passRule,
  }) {
    final easyPassedCount = progress?.easyPassedCount ?? 0;
    final mediumPassedCount = progress?.mediumPassedCount ?? 0;
    final hardPassedCount = progress?.hardPassedCount ?? 0;
    return _ProgressPassSnapshot(
      easyPassedCount: easyPassedCount,
      mediumPassedCount: mediumPassedCount,
      hardPassedCount: hardPassedCount,
      lit: passRule.litForCounts(
        easyCount: easyPassedCount,
        mediumCount: mediumPassedCount,
        hardCount: hardPassedCount,
      ),
      litPercent: passRule.litPercentForCounts(
        easyCount: easyPassedCount,
        mediumCount: mediumPassedCount,
        hardCount: hardPassedCount,
      ),
    );
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
      if (update is Map<String, dynamic>) {
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
        continue;
      }
      final mistakeTags = parsed?['mistake_tags'];
      final modernMistakes = parsed?['mistakes'];
      final source = modernMistakes ?? mistakeTags;
      if (source is! List) {
        continue;
      }
      for (final entry in source) {
        if (entry is! String || entry.trim().isEmpty) {
          continue;
        }
        final mistakeTag = entry.trim();
        final key = 'OTHER::$mistakeTag';
        final existing = counts[key];
        if (existing == null) {
          counts[key] = _ErrorBookAggregate(
            typeId: 'OTHER',
            mistakeTag: mistakeTag,
            count: 1,
            lastNote: '',
          );
        } else {
          existing.count += 1;
        }
        totalUpdates += 1;
      }
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

  Map<String, dynamic>? _augmentReviewParsedJsonForPersistence({
    required _TutorRequestContext request,
    required Map<String, dynamic>? parsed,
  }) {
    if (parsed == null ||
        request.promptName != PromptVariableRegistry.reviewContPrompt) {
      return parsed;
    }
    final passedLevel =
        _normalizeLevel(parsed['difficulty']) ?? request.reviewPassedLevel;
    if (passedLevel == null) {
      return parsed;
    }
    return <String, dynamic>{
      ...parsed,
      'difficulty': passedLevel,
    };
  }

  Future<void> _updateReviewProgressIfNeeded({
    required String actionMode,
    required int? studentId,
    required int courseVersionId,
    required String kpKey,
    required String studentIntent,
    required String? parsedJsonText,
    required String? passedLevel,
    required bool shouldCountReviewAttempt,
  }) async {
    if (actionMode != 'review' ||
        studentId == null ||
        studentId <= 0 ||
        !shouldCountReviewAttempt) {
      return;
    }
    final parsed =
        parsedJsonText == null ? null : _tryDecodeJsonObject(parsedJsonText);
    if (parsed == null) {
      return;
    }
    final finished = parsed['finished'] == true;
    final resolvedPassedLevel =
        _normalizeLevel(parsed['difficulty']) ?? passedLevel;
    if (finished && resolvedPassedLevel != null) {
      await _db.incrementProgressPassedCount(
        studentId: studentId,
        courseVersionId: courseVersionId,
        kpKey: kpKey,
        passedLevel: resolvedPassedLevel,
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
      return _sanitizeVisibleTutorText(fallback).trim();
    }
    final teacherMessage = parsed['text'] ?? parsed['teacher_message'];
    if (teacherMessage is String && teacherMessage.trim().isNotEmpty) {
      return _sanitizeVisibleTutorText(teacherMessage).trim();
    }
    return _sanitizeVisibleTutorText(fallback).trim();
  }

  String? _extractStreamingDisplayText({
    required String promptName,
    required String responseText,
  }) {
    final fieldNames = const <String>['text', 'teacher_message'];
    for (final fieldName in fieldNames) {
      final extracted = _extractJsonStringFieldPrefix(
        responseText: responseText,
        fieldName: fieldName,
      );
      if (extracted != null) {
        return _sanitizeVisibleTutorText(extracted);
      }
    }
    return null;
  }

  String _sanitizeVisibleTutorText(String value) {
    if (value.isEmpty) {
      return value;
    }
    final lower = value.toLowerCase();
    const openTag = '<think>';
    const closeTag = '</think>';
    final buffer = StringBuffer();
    var index = 0;
    while (index < value.length) {
      final openIndex = lower.indexOf(openTag, index);
      if (openIndex < 0) {
        buffer.write(value.substring(index));
        break;
      }
      if (openIndex > index) {
        buffer.write(value.substring(index, openIndex));
      }
      final contentStart = openIndex + openTag.length;
      final closeIndex = lower.indexOf(closeTag, contentStart);
      if (closeIndex < 0) {
        break;
      }
      index = closeIndex + closeTag.length;
    }
    return buffer.toString();
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
    return promptName == PromptVariableRegistry.reviewContPrompt;
  }

  Future<Map<String, dynamic>?> _loadStructuredSchema(String promptName) async {
    switch (promptName) {
      case PromptVariableRegistry.reviewContPrompt:
        return _promptRepository.loadSchema('review_cont');
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
