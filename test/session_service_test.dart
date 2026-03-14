import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/db/app_database.dart';
import 'package:family_teacher/llm/llm_models.dart';
import 'package:family_teacher/llm/llm_service.dart';
import 'package:family_teacher/llm/prompt_repository.dart';
import 'package:family_teacher/models/tutor_contract.dart';
import 'package:family_teacher/services/llm_log_repository.dart' as llm_logs;
import 'package:family_teacher/services/session_service.dart';
import 'package:family_teacher/services/settings_repository.dart';

class _TutorFixture {
  _TutorFixture({
    required this.sessionId,
    required this.courseVersion,
    required this.node,
  });

  final int sessionId;
  final CourseVersion courseVersion;
  final CourseNode node;
}

class _LlmCallInvocation {
  _LlmCallInvocation({
    required this.promptName,
    required this.renderedPrompt,
    required this.schemaMap,
    required this.modelOverride,
    required this.context,
  });

  final String promptName;
  final String renderedPrompt;
  final Map<String, dynamic>? schemaMap;
  final String? modelOverride;
  final LlmCallContext? context;
}

class _PlannedLlmResponse {
  _PlannedLlmResponse({
    required this.future,
    this.streamChunks = const <String>[],
  });

  final Future<LlmCallResult> future;
  final List<String> streamChunks;
}

class _FakeLlmService implements LlmService {
  final List<_PlannedLlmResponse> _plannedCalls = <_PlannedLlmResponse>[];
  final List<_PlannedLlmResponse> _plannedStreams = <_PlannedLlmResponse>[];
  final List<_LlmCallInvocation> callInvocations = <_LlmCallInvocation>[];
  final List<_LlmCallInvocation> streamInvocations = <_LlmCallInvocation>[];

  void queueCall(Future<LlmCallResult> future) {
    _plannedCalls.add(_PlannedLlmResponse(future: future));
  }

  void queueStreamingCall(
    Future<LlmCallResult> future, {
    List<String> streamChunks = const <String>[],
  }) {
    _plannedStreams.add(
      _PlannedLlmResponse(
        future: future,
        streamChunks: streamChunks,
      ),
    );
  }

  @override
  LlmRequestHandle startCall({
    required String promptName,
    required String renderedPrompt,
    Map<String, dynamic>? schemaMap,
    String? conversationDigest,
    String? modelOverride,
    LlmCallContext? context,
  }) {
    if (_plannedCalls.isEmpty) {
      throw StateError('No planned startCall response for $promptName');
    }
    callInvocations.add(
      _LlmCallInvocation(
        promptName: promptName,
        renderedPrompt: renderedPrompt,
        schemaMap: schemaMap,
        modelOverride: modelOverride,
        context: context,
      ),
    );
    final planned = _plannedCalls.removeAt(0);
    return LlmRequestHandle(
      future: planned.future,
      cancel: () {},
    );
  }

  @override
  LlmRequestHandle startStreamingCall({
    required String promptName,
    required String renderedPrompt,
    required void Function(String p1) onChunk,
    Map<String, dynamic>? schemaMap,
    String? conversationDigest,
    String? modelOverride,
    LlmCallContext? context,
  }) {
    if (_plannedStreams.isEmpty) {
      throw StateError(
          'No planned startStreamingCall response for $promptName');
    }
    streamInvocations.add(
      _LlmCallInvocation(
        promptName: promptName,
        renderedPrompt: renderedPrompt,
        schemaMap: schemaMap,
        modelOverride: modelOverride,
        context: context,
      ),
    );
    final planned = _plannedStreams.removeAt(0);
    for (final chunk in planned.streamChunks) {
      onChunk(chunk);
    }
    return LlmRequestHandle(
      future: planned.future,
      cancel: () {},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePromptRepository extends PromptRepository {
  _FakePromptRepository();

  @override
  Future<String> loadPrompt(
    String name, {
    int? teacherId,
    String? courseKey,
    int? studentId,
  }) async {
    switch (name) {
      case 'summary':
        return 'Summary prompt {{conversation_history}} {{student_summary}}';
      default:
        return 'Tutor prompt intent={{student_intent}} error_book={{error_book_summary}} input={{student_input}} history={{conversation_history}} recent={{recent_dialogue}} prev={{prev_json}}';
    }
  }

  @override
  Future<void> ensureAssignmentPrompts({
    required int teacherId,
    required int studentId,
    required int courseVersionId,
  }) async {}

  @override
  Future<Map<String, dynamic>> loadSchema(String name) async {
    return <String, dynamic>{
      'type': 'object',
    };
  }
}

class _LoggedEntry {
  _LoggedEntry({
    required this.promptName,
    required this.model,
    required this.baseUrl,
    required this.mode,
    required this.status,
    this.callHash,
    this.latencyMs,
    this.parseValid,
    this.parseError,
    this.teacherId,
    this.studentId,
    this.courseVersionId,
    this.sessionId,
    this.kpKey,
    this.action,
    this.attempt,
    this.retryReason,
    this.backoffMs,
    this.renderedChars,
    this.responseChars,
    this.dbWriteOk,
    this.uiCommitOk,
  });

  final String promptName;
  final String model;
  final String baseUrl;
  final String mode;
  final String status;
  final String? callHash;
  final int? latencyMs;
  final bool? parseValid;
  final String? parseError;
  final int? teacherId;
  final int? studentId;
  final int? courseVersionId;
  final int? sessionId;
  final String? kpKey;
  final String? action;
  final int? attempt;
  final String? retryReason;
  final int? backoffMs;
  final int? renderedChars;
  final int? responseChars;
  final bool? dbWriteOk;
  final bool? uiCommitOk;
}

class _FakeLlmLogRepository implements llm_logs.LlmLogRepository {
  final List<_LoggedEntry> entries = <_LoggedEntry>[];

  @override
  Future<void> appendEntry({
    required String promptName,
    required String model,
    required String baseUrl,
    required String mode,
    required String status,
    String? callHash,
    int? latencyMs,
    bool? parseValid,
    String? parseError,
    int? teacherId,
    int? studentId,
    int? courseVersionId,
    int? sessionId,
    String? kpKey,
    String? action,
    int? attempt,
    String? retryReason,
    int? backoffMs,
    int? renderedChars,
    int? responseChars,
    String? reasoningText,
    bool? dbWriteOk,
    bool? uiCommitOk,
  }) async {
    entries.add(
      _LoggedEntry(
        promptName: promptName,
        model: model,
        baseUrl: baseUrl,
        mode: mode,
        status: status,
        callHash: callHash,
        latencyMs: latencyMs,
        parseValid: parseValid,
        parseError: parseError,
        teacherId: teacherId,
        studentId: studentId,
        courseVersionId: courseVersionId,
        sessionId: sessionId,
        kpKey: kpKey,
        action: action,
        attempt: attempt,
        retryReason: retryReason,
        backoffMs: backoffMs,
        renderedChars: renderedChars,
        responseChars: responseChars,
        dbWriteOk: dbWriteOk,
        uiCommitOk: uiCommitOk,
      ),
    );
  }

  @override
  Future<List<llm_logs.LlmLogEntry>> loadEntries() async {
    return <llm_logs.LlmLogEntry>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _seedSettings(AppDatabase db) async {
  await db.into(db.appSettings).insert(
        AppSettingsCompanion.insert(
          baseUrl: 'https://api.openai.com/v1',
          providerId: const Value('openai'),
          model: 'gpt-4o-mini',
          timeoutSeconds: 30,
          maxTokens: 4000,
          ttsInitialDelayMs: const Value(1000),
          ttsTextLeadMs: const Value(1000),
          ttsAudioPath: const Value(r'C:\family_teacher\logs'),
          sttAutoSend: const Value(false),
          enterToSend: const Value(true),
          studyModeEnabled: const Value(false),
          logDirectory: const Value(r'C:\family_teacher\logs'),
          llmLogPath: const Value(r'C:\family_teacher\logs\llm_logs.jsonl'),
          ttsLogPath: const Value(r'C:\family_teacher\logs\tts_logs.jsonl'),
          llmMode: 'LIVE',
          locale: const Value('en'),
        ),
      );
}

Future<_TutorFixture> _createTutorFixture({
  required AppDatabase db,
  required SessionService service,
}) async {
  final teacherId = await db.createUser(
    username: 'teacher_session',
    pinHash: 'hash',
    role: 'teacher',
    remoteUserId: 1001,
  );
  final studentId = await db.createUser(
    username: 'student_session',
    pinHash: 'hash',
    role: 'student',
    teacherId: teacherId,
    remoteUserId: 1002,
  );
  final courseVersionId = await db.createCourseVersion(
    teacherId: teacherId,
    subject: 'Math',
    granularity: 1,
    textbookText: 'textbook',
    sourcePath: Directory.systemTemp.path,
  );
  await db.into(db.courseNodes).insert(
        CourseNodesCompanion.insert(
          courseVersionId: courseVersionId,
          kpKey: '1.1',
          title: 'Integers',
          description: 'Integers intro',
          orderIndex: 0,
        ),
      );
  await db.assignStudent(
    studentId: studentId,
    courseVersionId: courseVersionId,
  );
  final sessionId = await service.startSession(
    studentId: studentId,
    courseVersionId: courseVersionId,
    kpKey: '1.1',
  );
  final courseVersion = await db.getCourseVersionById(courseVersionId);
  final node = await db.getCourseNodeByKey(courseVersionId, '1.1');
  if (courseVersion == null || node == null) {
    throw StateError('Failed to create tutor fixture.');
  }
  return _TutorFixture(
    sessionId: sessionId,
    courseVersion: courseVersion,
    node: node,
  );
}

LlmCallResult _llmOk({
  required String responseText,
  String model = 'gpt-4o-mini',
  String baseUrl = 'https://api.openai.com/v1',
  String callHash = 'hash',
}) {
  return LlmCallResult(
    responseText: responseText,
    latencyMs: 12,
    fromReplay: false,
    callHash: callHash,
    model: model,
    baseUrl: baseUrl,
  );
}

Map<String, Object?> _control({
  required String mode,
  required String step,
  required bool turnFinished,
  String helpBias = 'UNCHANGED',
  List<String> allowedActions = const <String>[],
  String? recommendedAction,
}) {
  return <String, Object?>{
    'version': 1,
    'mode': mode,
    'step': step,
    'turn_finished': turnFinished,
    'help_bias': helpBias,
    'allowed_actions': allowedActions,
    'recommended_action': recommendedAction,
  };
}

Map<String, Object?> _learnUnfinishedControl({
  String helpBias = 'UNCHANGED',
}) {
  return _control(
    mode: 'LEARN',
    step: 'CONTINUE',
    turnFinished: false,
    helpBias: helpBias,
  );
}

Map<String, Object?> _reviewUnfinishedControl({
  String helpBias = 'UNCHANGED',
}) {
  return _control(
    mode: 'REVIEW',
    step: 'CONTINUE',
    turnFinished: false,
    helpBias: helpBias,
  );
}

Map<String, Object?> _reviewFinishedControl({
  String mode = 'REVIEW',
  String helpBias = 'UNCHANGED',
  List<String> allowedActions = const <String>[
    'NEXT_QUESTION',
    'LEARN',
    'SUMMARIZE',
    'PAUSE',
  ],
  String recommendedAction = 'NEXT_QUESTION',
}) {
  return _control(
    mode: mode,
    step: 'NEW',
    turnFinished: true,
    helpBias: helpBias,
    allowedActions: allowedActions,
    recommendedAction: recommendedAction,
  );
}

Map<String, Object?> _learnFinishedControl({
  String mode = 'LEARN',
  String helpBias = 'UNCHANGED',
  List<String> allowedActions = const <String>[
    'CONTINUE_LEARNING',
    'TRY_QUESTION',
    'SUMMARIZE',
    'PAUSE',
  ],
  String recommendedAction = 'CONTINUE_LEARNING',
}) {
  return _control(
    mode: mode,
    step: 'NEW',
    turnFinished: true,
    helpBias: helpBias,
    allowedActions: allowedActions,
    recommendedAction: recommendedAction,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FakeLlmService llmService;
  late _FakePromptRepository promptRepository;
  late SettingsRepository settingsRepository;
  late _FakeLlmLogRepository llmLogRepository;
  late SessionService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await _seedSettings(db);
    llmService = _FakeLlmService();
    promptRepository = _FakePromptRepository();
    settingsRepository = SettingsRepository(db);
    llmLogRepository = _FakeLlmLogRepository();
    service = SessionService(
      db,
      llmService,
      promptRepository,
      settingsRepository,
      llmLogRepository,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('startTutorAction persists structured assistant payload', () async {
    final fixture = await _createTutorFixture(
      db: db,
      service: service,
    );
    final response = jsonEncode(<String, Object?>{
      'teacher_message': 'Great start. Let us continue.',
      'understanding': 'PARTIAL',
      'control': _learnUnfinishedControl(),
    });
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: response,
          callHash: 'call_learn_1',
        ),
      ),
    );

    final handle = await service.startTutorAction(
      sessionId: fixture.sessionId,
      mode: 'learn',
      studentInput: 'I need help with integers.',
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );
    await handle.future;

    expect(llmService.callInvocations.length, equals(1));
    expect(llmService.callInvocations.single.promptName, equals('learn_init'));

    final messages = await db.getMessagesForSession(fixture.sessionId);
    expect(messages.length, equals(2));
    expect(messages.first.role, equals('user'));
    expect(messages.first.content, equals('I need help with integers.'));
    expect(messages.last.role, equals('assistant'));
    expect(messages.last.content, equals('Great start. Let us continue.'));
    expect(messages.last.rawContent, equals(response));
    expect(messages.last.parsedJson, isNotNull);

    final persistLogs = llmLogRepository.entries
        .where((entry) => entry.status == 'persist')
        .toList();
    expect(persistLogs.length, equals(1));
    expect(persistLogs.single.dbWriteOk, isTrue);
    expect(persistLogs.single.callHash, equals('call_learn_1'));
  });

  test(
    'startTutorAction injects student_intent and aggregated error book summary',
    () async {
      final fixture = await _createTutorFixture(
        db: db,
        service: service,
      );
      final session = await db.getSession(fixture.sessionId);
      if (session == null) {
        throw StateError('Missing session fixture.');
      }
      await db.into(db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: fixture.sessionId,
              role: 'assistant',
              content: 'Review feedback',
              parsedJson: Value(
                jsonEncode(<String, Object?>{
                  'teacher_message': 'Check your sign handling.',
                  'control': _reviewFinishedControl(),
                  'answer_state': 'FINAL_ANSWER',
                  'grading': {
                    'is_correct': false,
                    'mistake_summary': 'Sign error',
                    'hint_level': 1,
                  },
                  'error_book_update': {
                    'type_id': 'ALGEBRA',
                    'delta_wrong': 1,
                    'mistake_tag': 'sign_error',
                    'mistake_note': 'Moved term to wrong side.',
                  },
                  'evidence': {
                    'a': 1,
                    'c': 0,
                    'h': 1,
                    't': 'ALGEBRA',
                    'mt': <String>['sign_error'],
                  },
                  'mastery_level': 'NOT_PASS',
                }),
              ),
              action: const Value('review'),
            ),
          );
      await db.upsertProgressSummary(
        studentId: session.studentId,
        courseVersionId: fixture.courseVersion.id,
        kpKey: fixture.node.kpKey,
        summaryText: 'Prior summary',
        summaryRawResponse: null,
        summaryValid: true,
      );
      llmService.queueCall(
        Future<LlmCallResult>.value(
          _llmOk(
            responseText: jsonEncode(<String, Object?>{
              'teacher_message': 'Let us fix the sign rule together.',
              'understanding': 'PARTIAL',
              'control': _learnUnfinishedControl(),
            }),
            callHash: 'intent_error_book_call',
          ),
        ),
      );

      final handle = await service.startTutorAction(
        sessionId: fixture.sessionId,
        mode: 'learn_init',
        studentInput: 'hint please',
        studentIntent: 'HELP_REQUEST',
        courseVersion: fixture.courseVersion,
        node: fixture.node,
      );
      await handle.future;

      expect(llmService.callInvocations.length, equals(1));
      final rendered = llmService.callInvocations.single.renderedPrompt;
      expect(rendered, contains('intent=HELP_REQUEST'));
      expect(rendered, contains('sign_error'));
      expect(rendered, contains('ALGEBRA'));
    },
  );

  test(
    'repeated learn_init includes prior conversation and prior assistant payload',
    () async {
      final fixture = await _createTutorFixture(
        db: db,
        service: service,
      );
      await db.into(db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: fixture.sessionId,
              role: 'user',
              content: 'Teach me regression basics.',
              action: const Value('learn'),
            ),
          );
      await db.into(db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: fixture.sessionId,
              role: 'assistant',
              content: 'Regression predicts y from x.',
              parsedJson: Value(
                jsonEncode(<String, Object?>{
                  'teacher_message': 'Regression predicts y from x.',
                  'understanding': 'PARTIAL',
                  'control': _learnUnfinishedControl(),
                }),
              ),
              action: const Value('learn'),
            ),
          );
      llmService.queueCall(
        Future<LlmCallResult>.value(
          _llmOk(
            responseText: jsonEncode(<String, Object?>{
              'teacher_message': 'Let us add a new angle.',
              'understanding': 'PARTIAL',
              'control': _learnUnfinishedControl(),
            }),
            callHash: 'repeat_learn_init',
          ),
        ),
      );

      final handle = await service.startTutorAction(
        sessionId: fixture.sessionId,
        mode: 'learn_init',
        studentInput: '',
        courseVersion: fixture.courseVersion,
        node: fixture.node,
      );
      await handle.future;

      final rendered = llmService.callInvocations.single.renderedPrompt;
      expect(rendered, contains('Teach me regression basics.'));
      expect(rendered, contains('Regression predicts y from x.'));
      expect(
        rendered,
        contains('"teacher_message":"Regression predicts y from x."'),
      );
    },
  );

  test('startTutorAction dedupes identical in-flight calls', () async {
    final fixture = await _createTutorFixture(
      db: db,
      service: service,
    );
    final pending = Completer<LlmCallResult>();
    llmService.queueCall(pending.future);
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: jsonEncode(<String, Object?>{
            'teacher_message': 'Second pass.',
            'understanding': 'PARTIAL',
            'control': _learnUnfinishedControl(),
          }),
          callHash: 'call_learn_2',
        ),
      ),
    );

    final handleA = await service.startTutorAction(
      sessionId: fixture.sessionId,
      mode: 'learn_init',
      studentInput: '',
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );
    final handleB = await service.startTutorAction(
      sessionId: fixture.sessionId,
      mode: 'learn_init',
      studentInput: '',
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );

    expect(identical(handleA, handleB), isTrue);
    expect(llmService.callInvocations.length, equals(1));

    pending.complete(
      _llmOk(
        responseText: jsonEncode(<String, Object?>{
          'teacher_message': 'Single flight response.',
          'understanding': 'PARTIAL',
          'control': _learnUnfinishedControl(),
        }),
        callHash: 'call_learn_pending',
      ),
    );
    await Future.wait(<Future<LlmCallResult>>[handleA.future, handleB.future]);

    final handleC = await service.startTutorAction(
      sessionId: fixture.sessionId,
      mode: 'learn_init',
      studentInput: '',
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );
    await handleC.future;

    expect(llmService.callInvocations.length, equals(2));
  });

  test(
    'review mode starts review_init after finished turn',
    () async {
      final fixture = await _createTutorFixture(
        db: db,
        service: service,
      );
      await db.into(db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: fixture.sessionId,
              role: 'assistant',
              content: 'Completed question feedback.',
              parsedJson: Value(
                jsonEncode(<String, Object?>{
                  'teacher_message': 'Completed question feedback.',
                  'control': _reviewFinishedControl(),
                  'answer_state': 'FINAL_ANSWER',
                  'difficulty_action': 'HOLD',
                  'recommended_level': 'medium',
                  'grading': {
                    'is_correct': true,
                    'mistake_summary': 'Good',
                    'hint_level': 0,
                  },
                  'error_book_update': null,
                  'evidence': {
                    'a': 2,
                    'c': 2,
                    'h': 0,
                    't': 'OTHER',
                    'mt': <String>[],
                  },
                  'mastery_level': 'PASS_MEDIUM',
                }),
              ),
              action: const Value('review'),
            ),
          );

      llmService.queueCall(
        Future<LlmCallResult>.value(
          _llmOk(
            responseText: jsonEncode(<String, Object?>{
              'teacher_message': 'Solve 2x + 1 = 9.',
              'control': _reviewUnfinishedControl(),
              'difficulty_level': 'medium',
              'grading': null,
              'error_book_update': null,
              'evidence': {
                'a': 2,
                'c': 2,
                'h': 0,
                't': 'ALGEBRA',
                'mt': <String>[],
              },
              'mastery_level': 'PASS_MEDIUM',
            }),
            callHash: 'review_init_after_finish',
          ),
        ),
      );
      final handle = await service.startTutorAction(
        sessionId: fixture.sessionId,
        mode: 'review',
        studentInput: 'ok',
        courseVersion: fixture.courseVersion,
        node: fixture.node,
      );
      await handle.future;

      expect(llmService.callInvocations.length, equals(1));
      expect(
          llmService.callInvocations.single.promptName, equals('review_init'));
    },
  );

  test('learn_init rejects finished control that stays in LEARN', () async {
    final fixture = await _createTutorFixture(
      db: db,
      service: service,
    );
    for (var i = 0; i < 3; i++) {
      llmService.queueCall(
        Future<LlmCallResult>.value(
          _llmOk(
            responseText: jsonEncode(<String, Object?>{
              'teacher_message': 'You are ready.',
              'understanding': 'READY',
              'control': _learnFinishedControl(
                mode: 'LEARN',
                recommendedAction: 'CONTINUE_LEARNING',
              ),
            }),
            callHash: 'invalid_learn_finish_mode_$i',
          ),
        ),
      );
    }

    final handle = await service.startTutorAction(
      sessionId: fixture.sessionId,
      mode: 'learn_init',
      studentInput: '',
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );

    await expectLater(
      handle.future,
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('must finish into REVIEW/NEW'),
        ),
      ),
    );
  });

  test(
    'finished review uses control.turn_finished to record graded evidence and trigger summarize LLM call',
    () async {
      final fixture = await _createTutorFixture(
        db: db,
        service: service,
      );
      llmService.queueCall(
        Future<LlmCallResult>.value(
          _llmOk(
            responseText: jsonEncode(<String, Object?>{
              'teacher_message': 'Correct. Nice work.',
              'control': _reviewFinishedControl(
                recommendedAction: 'SUMMARIZE',
              ),
              'answer_state': 'FINAL_ANSWER',
              'difficulty_action': 'HOLD',
              'recommended_level': 'easy',
              'grading': {
                'is_correct': true,
                'mistake_summary': '',
                'hint_level': 0,
              },
              'error_book_update': null,
              'evidence': {
                'a': 1,
                'c': 1,
                'h': 0,
                't': 'OTHER',
                'mt': <String>[],
              },
              'mastery_level': 'PASS_EASY',
            }),
            callHash: 'review_finish_for_summary',
          ),
        ),
      );

      final reviewHandle = await service.startTutorAction(
        sessionId: fixture.sessionId,
        mode: 'review_cont',
        studentInput: '7',
        courseVersion: fixture.courseVersion,
        node: fixture.node,
      );
      await reviewHandle.future;

      final refreshedSession = await db.getSession(fixture.sessionId);
      final evidenceState = TutorEvidenceState.fromJsonText(
        refreshedSession?.evidenceStateJson,
      );
      expect(evidenceState, isNotNull);
      expect(evidenceState!.gradedReviewCount, equals(1));
      expect(evidenceState.hasNewGradedReviewEvidence, isTrue);

      llmService.queueCall(
        Future<LlmCallResult>.value(
          _llmOk(
            responseText: jsonEncode(<String, Object?>{
              'teacher_message': 'Ready for another review question.',
              'control': _control(
                mode: 'REVIEW',
                step: 'NEW',
                turnFinished: true,
                allowedActions: const <String>[
                  'NEXT_QUESTION',
                  'LEARN',
                  'PAUSE',
                ],
                recommendedAction: 'NEXT_QUESTION',
              ),
              'lit': false,
              'next_step': 'CONTINUE_REVIEW',
            }),
            callHash: 'summarize_after_review_finish',
          ),
        ),
      );

      final summarizeHandle = await service.startSummarize(
        sessionId: fixture.sessionId,
        courseVersion: fixture.courseVersion,
        node: fixture.node,
      );
      final summarizeResult = await summarizeHandle.future;

      expect(summarizeResult.success, isTrue);
      expect(llmService.callInvocations.length, equals(2));
      expect(llmService.callInvocations.last.promptName, equals('summarize'));
    },
  );

  test('review_cont rejects finished control that routes back into LEARN',
      () async {
    final fixture = await _createTutorFixture(
      db: db,
      service: service,
    );
    for (var i = 0; i < 3; i++) {
      llmService.queueCall(
        Future<LlmCallResult>.value(
          _llmOk(
            responseText: jsonEncode(<String, Object?>{
              'teacher_message': 'That answer shows a gap.',
              'control': _reviewFinishedControl(
                mode: 'LEARN',
                allowedActions: const <String>['LEARN', 'SUMMARIZE', 'PAUSE'],
                recommendedAction: 'LEARN',
              ),
              'answer_state': 'FINAL_ANSWER',
              'difficulty_action': 'DOWN',
              'recommended_level': 'easy',
              'grading': {
                'is_correct': false,
                'mistake_summary': 'Concept gap',
                'hint_level': 1,
              },
              'error_book_update': null,
              'evidence': {
                'a': 1,
                'c': 0,
                'h': 1,
                't': 'OTHER',
                'mt': <String>[],
              },
              'mastery_level': 'NOT_PASS',
            }),
            callHash: 'invalid_review_finish_mode_$i',
          ),
        ),
      );
    }

    final handle = await service.startTutorAction(
      sessionId: fixture.sessionId,
      mode: 'review_cont',
      studentInput: '7',
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );

    await expectLater(
      handle.future,
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('must finish into REVIEW/NEW'),
        ),
      ),
    );
  });

  test('startTutorAction retries structured parse failure and logs retry',
      () async {
    final fixture = await _createTutorFixture(
      db: db,
      service: service,
    );
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: 'not valid json',
          callHash: 'bad_call',
        ),
      ),
    );
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: jsonEncode(<String, Object?>{
            'teacher_message': 'Recovered after retry.',
            'understanding': 'PARTIAL',
            'control': _learnUnfinishedControl(),
          }),
          callHash: 'good_call',
        ),
      ),
    );

    final handle = await service.startTutorAction(
      sessionId: fixture.sessionId,
      mode: 'learn_init',
      studentInput: '',
      modelOverride: 'gpt-4o-mini',
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );
    await handle.future;

    expect(llmService.callInvocations.length, equals(2));
    expect(llmService.callInvocations[1].modelOverride, equals('gpt-4o-mini'));

    final retryLogs = llmLogRepository.entries
        .where((entry) => entry.status == 'retry')
        .toList();
    expect(retryLogs.length, equals(1));
    expect(retryLogs.single.attempt, equals(1));
    expect(retryLogs.single.backoffMs, equals(250));
    expect(retryLogs.single.retryReason, contains('structured_parse_retry'));
  });

  test('second retry attempt switches to fallback model override', () async {
    final fixture = await _createTutorFixture(
      db: db,
      service: service,
    );
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: 'first invalid',
          model: 'gpt-4o-mini',
          callHash: 'retry_1',
        ),
      ),
    );
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: 'second invalid',
          model: 'gpt-4o-mini',
          callHash: 'retry_2',
        ),
      ),
    );
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: jsonEncode(<String, Object?>{
            'teacher_message': 'Fallback model succeeded.',
            'understanding': 'READY',
            'control': _learnFinishedControl(
              mode: 'REVIEW',
              recommendedAction: 'TRY_QUESTION',
            ),
          }),
          model: 'gpt-5.2-2025-12-11',
          callHash: 'retry_3',
        ),
      ),
    );

    final handle = await service.startTutorAction(
      sessionId: fixture.sessionId,
      mode: 'learn_init',
      studentInput: '',
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );
    await handle.future;

    expect(llmService.callInvocations.length, equals(3));
    expect(llmService.callInvocations[2].modelOverride, isNotNull);
    expect(llmService.callInvocations[2].modelOverride, isNot('gpt-4o-mini'));

    final retryLogs = llmLogRepository.entries
        .where((entry) => entry.status == 'retry')
        .toList();
    expect(retryLogs.length, equals(2));
    expect(retryLogs.last.attempt, equals(2));
  });

  test(
    'startSummarize retries structured parse failure instead of saving unparsed summary',
    () async {
      final fixture = await _createTutorFixture(
        db: db,
        service: service,
      );
      llmService.queueCall(
        Future<LlmCallResult>.value(
          _llmOk(
            responseText: 'not valid json',
            callHash: 'summary_retry_bad',
          ),
        ),
      );
      llmService.queueCall(
        Future<LlmCallResult>.value(
          _llmOk(
            responseText: jsonEncode(<String, Object?>{
              'teacher_message':
                  'Keep relearning this skill before more review.',
              'control': _control(
                mode: 'REVIEW',
                step: 'NEW',
                turnFinished: true,
                allowedActions: const <String>[
                  'NEXT_QUESTION',
                  'LEARN',
                  'PAUSE',
                ],
                recommendedAction: 'NEXT_QUESTION',
              ),
              'lit': false,
              'next_step': 'CONTINUE_REVIEW',
            }),
            callHash: 'summary_retry_good',
          ),
        ),
      );

      final handle = await service.startSummarize(
        sessionId: fixture.sessionId,
        courseVersion: fixture.courseVersion,
        node: fixture.node,
      );
      final result = await handle.future;

      expect(result.success, isTrue);
      expect(
        result.summaryText,
        equals('Keep relearning this skill before more review.'),
      );
      expect(result.litPercent, equals(0));
      expect(llmService.callInvocations.length, equals(2));

      final retryLogs = llmLogRepository.entries
          .where((entry) => entry.status == 'retry')
          .toList();
      expect(retryLogs, isNotEmpty);

      final session = await db.getSession(fixture.sessionId);
      expect(session, isNotNull);
      expect(session!.summaryValid, isTrue);
      expect(session.summaryRawResponse, isNull);

      final summaryMessages = await db.getMessagesForSession(fixture.sessionId);
      final summary = summaryMessages.last;
      expect(summary.action, equals('summary'));
      expect(summary.rawContent, isNotNull);
      expect(summary.parsedJson, isNotNull);
    },
  );

  test('startSummarize returns cached summary without LLM call', () async {
    final fixture = await _createTutorFixture(
      db: db,
      service: service,
    );
    final session = await db.getSession(fixture.sessionId);
    if (session == null) {
      throw StateError('Session not found for cache test.');
    }
    await db.upsertProgressSummary(
      studentId: session.studentId,
      courseVersionId: fixture.courseVersion.id,
      kpKey: fixture.node.kpKey,
      summaryText: 'Existing summary',
      summaryRawResponse: null,
      summaryValid: true,
      summaryLit: false,
    );
    await db.incrementProgressPassedCount(
      studentId: session.studentId,
      courseVersionId: fixture.courseVersion.id,
      kpKey: fixture.node.kpKey,
      passedLevel: 'medium',
    );
    await (db.update(db.chatSessions)
          ..where((tbl) => tbl.id.equals(fixture.sessionId)))
        .write(
      const ChatSessionsCompanion(
        summaryText: Value('Existing summary'),
        summaryLit: Value(false),
        summaryLitPercent: Value(66),
      ),
    );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: fixture.sessionId,
            role: 'assistant',
            content: 'Existing summary',
            action: const Value('summary'),
          ),
        );

    final handle = await service.startSummarize(
      sessionId: fixture.sessionId,
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );
    final result = await handle.future;

    expect(result.success, isTrue);
    expect(result.message, equals('Summary unchanged. Reused cached result.'));
    expect(llmService.callInvocations, isEmpty);

    final cacheLogs = llmLogRepository.entries
        .where((entry) => entry.status == 'cache_hit')
        .toList();
    expect(cacheLogs.length, equals(1));
    expect(cacheLogs.single.promptName, equals('summarize'));
  });

  test(
    'startSummarize bypasses cache when cached summary has no mastery result',
    () async {
      final fixture = await _createTutorFixture(
        db: db,
        service: service,
      );
      await (db.update(db.chatSessions)
            ..where((tbl) => tbl.id.equals(fixture.sessionId)))
          .write(
        const ChatSessionsCompanion(
          summaryText: Value('Old summary without mastery'),
          summaryLit: Value(null),
          summaryLitPercent: Value(null),
        ),
      );

      llmService.queueCall(
        Future<LlmCallResult>.value(
          _llmOk(
            responseText: jsonEncode(<String, Object?>{
              'teacher_message': 'Student is not yet secure on this skill.',
              'control': _control(
                mode: 'REVIEW',
                step: 'NEW',
                turnFinished: true,
                allowedActions: const <String>[
                  'NEXT_QUESTION',
                  'PAUSE',
                ],
                recommendedAction: 'NEXT_QUESTION',
              ),
              'lit': false,
              'next_step': 'CONTINUE_REVIEW',
            }),
            callHash: 'summary_cache_fallback',
          ),
        ),
      );

      final handle = await service.startSummarize(
        sessionId: fixture.sessionId,
        courseVersion: fixture.courseVersion,
        node: fixture.node,
      );
      final result = await handle.future;

      expect(result.success, isTrue);
      expect(result.litPercent, equals(0));
      expect(result.message, equals('Summary stored.'));
      expect(llmService.callInvocations.length, equals(1));
    },
  );

  test(
    'startSummarize reuses cached session summary percent when progress row is absent',
    () async {
      final fixture = await _createTutorFixture(
        db: db,
        service: service,
      );
      await (db.update(db.chatSessions)
            ..where((tbl) => tbl.id.equals(fixture.sessionId)))
          .write(
        const ChatSessionsCompanion(
          summaryText: Value('Session cached summary'),
          summaryLit: Value(true),
          summaryLitPercent: Value(100),
        ),
      );

      final handle = await service.startSummarize(
        sessionId: fixture.sessionId,
        courseVersion: fixture.courseVersion,
        node: fixture.node,
      );
      final result = await handle.future;

      expect(result.success, isTrue);
      expect(
          result.message, equals('Summary unchanged. Reused cached result.'));
      expect(result.litPercent, equals(100));
      expect(llmService.callInvocations, isEmpty);
    },
  );

  test(
    'startSummarize reuses cache when no graded review happened after last summary',
    () async {
      final fixture = await _createTutorFixture(
        db: db,
        service: service,
      );
      final session = await db.getSession(fixture.sessionId);
      if (session == null) {
        throw StateError('Session not found for cache stability test.');
      }
      await db.upsertProgressSummary(
        studentId: session.studentId,
        courseVersionId: fixture.courseVersion.id,
        kpKey: fixture.node.kpKey,
        summaryText: 'Stable summary',
        summaryRawResponse: null,
        summaryValid: true,
        summaryLit: true,
      );
      await db.incrementProgressPassedCount(
        studentId: session.studentId,
        courseVersionId: fixture.courseVersion.id,
        kpKey: fixture.node.kpKey,
        passedLevel: 'hard',
      );
      await (db.update(db.chatSessions)
            ..where((tbl) => tbl.id.equals(fixture.sessionId)))
          .write(
        const ChatSessionsCompanion(
          summaryText: Value('Stable summary'),
          summaryLit: Value(true),
          summaryLitPercent: Value(100),
        ),
      );
      await db.into(db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: fixture.sessionId,
              role: 'assistant',
              content: 'Stable summary',
              action: const Value('summary'),
            ),
          );
      await db.into(db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: fixture.sessionId,
              role: 'assistant',
              content: 'Do you want another question or summarize?',
              parsedJson: Value(
                jsonEncode(<String, Object?>{
                  'teacher_message':
                      'Do you want another question or summarize?',
                  'control': _reviewFinishedControl(
                    recommendedAction: 'SUMMARIZE',
                  ),
                  'answer_state': 'FINAL_ANSWER',
                  'difficulty_action': 'HOLD',
                  'recommended_level': 'hard',
                  'grading': null,
                  'error_book_update': null,
                  'evidence': {
                    'a': 3,
                    'c': 3,
                    'h': 0,
                    't': 'OTHER',
                    'mt': <String>[],
                  },
                  'mastery_level': 'PASS_HARD',
                }),
              ),
              action: const Value('review'),
            ),
          );

      final handle = await service.startSummarize(
        sessionId: fixture.sessionId,
        courseVersion: fixture.courseVersion,
        node: fixture.node,
      );
      final result = await handle.future;

      expect(result.success, isTrue);
      expect(
          result.message, equals('Summary unchanged. Reused cached result.'));
      expect(result.litPercent, equals(100));
      expect(llmService.callInvocations, isEmpty);
    },
  );

  test(
    'startSummarize does not downgrade sharply on weak evidence',
    () async {
      final fixture = await _createTutorFixture(
        db: db,
        service: service,
      );
      final session = await db.getSession(fixture.sessionId);
      if (session == null) {
        throw StateError('Session not found for summary stabilization test.');
      }
      await db.incrementProgressPassedCount(
        studentId: session.studentId,
        courseVersionId: fixture.courseVersion.id,
        kpKey: fixture.node.kpKey,
        passedLevel: 'hard',
      );
      await db.into(db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: fixture.sessionId,
              role: 'assistant',
              content: 'Recent review result',
              parsedJson: Value(
                jsonEncode(<String, Object?>{
                  'teacher_message': 'Recent review result',
                  'control': _reviewFinishedControl(),
                  'answer_state': 'FINAL_ANSWER',
                  'difficulty_action': 'HOLD',
                  'recommended_level': 'hard',
                  'grading': {
                    'is_correct': false,
                    'mistake_summary': 'minor miss',
                    'hint_level': 1,
                  },
                  'error_book_update': null,
                  'evidence': {
                    'a': 1,
                    'c': 0,
                    'h': 1,
                    't': 'OTHER',
                    'mt': <String>[],
                  },
                  'mastery_level': 'PASS_HARD',
                }),
              ),
              action: const Value('review'),
            ),
          );
      llmService.queueCall(
        Future<LlmCallResult>.value(
          _llmOk(
            responseText: jsonEncode(<String, Object?>{
              'teacher_message': 'Need major relearn.',
              'control': _control(
                mode: 'REVIEW',
                step: 'NEW',
                turnFinished: true,
                allowedActions: const <String>[
                  'NEXT_QUESTION',
                  'LEARN',
                  'PAUSE',
                ],
                recommendedAction: 'NEXT_QUESTION',
              ),
              'lit': false,
              'next_step': 'CONTINUE_REVIEW',
            }),
            callHash: 'summary_stabilize_1',
          ),
        ),
      );

      final handle = await service.startSummarize(
        sessionId: fixture.sessionId,
        courseVersion: fixture.courseVersion,
        node: fixture.node,
      );
      final result = await handle.future;

      expect(result.success, isTrue);
      expect(result.litPercent, equals(100));
      final refreshed = await db.getProgress(
        studentId: session.studentId,
        courseVersionId: fixture.courseVersion.id,
        kpKey: fixture.node.kpKey,
      );
      expect(refreshed, isNotNull);
      expect(refreshed!.hardPassedCount, equals(1));
    },
  );

  test('startSummarize stores parsed summary and lit fields', () async {
    final fixture = await _createTutorFixture(
      db: db,
      service: service,
    );
    final sessionBeforeSummary = await db.getSession(fixture.sessionId);
    if (sessionBeforeSummary == null) {
      throw StateError('Session not found for summary store test.');
    }
    await db.incrementProgressPassedCount(
      studentId: sessionBeforeSummary.studentId,
      courseVersionId: fixture.courseVersion.id,
      kpKey: fixture.node.kpKey,
      passedLevel: 'hard',
    );
    final summaryPayload = jsonEncode(<String, Object?>{
      'teacher_message': 'Student can move to next topic.',
      'control': _control(
        mode: 'REVIEW',
        step: 'NEW',
        turnFinished: true,
        allowedActions: const <String>['PAUSE'],
        recommendedAction: 'PAUSE',
      ),
      'lit': true,
      'next_step': 'MOVE_ON',
    });
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: summaryPayload,
          callHash: 'summary_call_1',
        ),
      ),
    );

    final handle = await service.startSummarize(
      sessionId: fixture.sessionId,
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );
    final result = await handle.future;

    expect(result.success, isTrue);
    expect(result.summaryText, equals('Student can move to next topic.'));
    expect(result.litPercent, equals(100));
    expect(result.nextStep, equals('MOVE_ON'));

    final session = await db.getSession(fixture.sessionId);
    expect(session, isNotNull);
    expect(session!.summaryText, equals('Student can move to next topic.'));
    expect(session.summaryLit, isTrue);

    final progress = await db.getProgress(
      studentId: session.studentId,
      courseVersionId: fixture.courseVersion.id,
      kpKey: fixture.node.kpKey,
    );
    expect(progress, isNotNull);
    expect(progress!.summaryText, equals('Student can move to next topic.'));
    expect(progress.hardPassedCount, equals(1));
  });
}
