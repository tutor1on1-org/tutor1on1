import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/llm/llm_models.dart';
import 'package:tutor1on1/llm/llm_service.dart';
import 'package:tutor1on1/llm/prompt_repository.dart';
import 'package:tutor1on1/models/tutor_contract.dart';
import 'package:tutor1on1/services/course_artifact_service.dart';
import 'package:tutor1on1/services/llm_log_repository.dart' as llm_logs;
import 'package:tutor1on1/services/session_service.dart';
import 'package:tutor1on1/services/settings_repository.dart';

class _TutorFixture {
  _TutorFixture({
    required this.sessionId,
    required this.courseVersion,
    required this.node,
    required this.studentId,
  });

  final int sessionId;
  final CourseVersion courseVersion;
  final CourseNode node;
  final int studentId;
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
  });

  final Future<LlmCallResult> future;
}

class _FakeLlmService implements LlmService {
  final List<_PlannedLlmResponse> _plannedCalls = <_PlannedLlmResponse>[];
  final List<_PlannedLlmResponse> _plannedStreams = <_PlannedLlmResponse>[];
  final List<_LlmCallInvocation> callInvocations = <_LlmCallInvocation>[];
  final List<_LlmCallInvocation> streamInvocations = <_LlmCallInvocation>[];

  void queueCall(Future<LlmCallResult> future) {
    _plannedCalls.add(_PlannedLlmResponse(future: future));
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
    return LlmRequestHandle(future: planned.future, cancel: () {});
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
        'No planned startStreamingCall response for $promptName',
      );
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
    return LlmRequestHandle(future: planned.future, cancel: () {});
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
    return '''
Prompt=$name
student={{student_input}}
lesson={{lesson_content}}
recent={{recent_chat}}
active={{active_review_question_json}}
questions={{presented_questions}}
errors={{error_book_summary}}
''';
  }

  @override
  Future<void> ensureAssignmentPrompts({
    required int teacherId,
    required int studentId,
    required int courseVersionId,
  }) async {}

  @override
  Future<Map<String, dynamic>> loadSchema(String name) async {
    return <String, dynamic>{'type': 'object'};
  }
}

class _LoggedEntry {
  _LoggedEntry({
    required this.promptName,
    required this.status,
    this.callHash,
    this.retryReason,
    this.responseChars,
    this.dbWriteOk,
  });

  final String promptName;
  final String status;
  final String? callHash;
  final String? retryReason;
  final int? responseChars;
  final bool? dbWriteOk;
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
        status: status,
        callHash: callHash,
        retryReason: retryReason,
        responseChars: responseChars,
        dbWriteOk: dbWriteOk,
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
          ttsAudioPath: const Value(r'C:\tutor1on1\logs'),
          sttAutoSend: const Value(false),
          enterToSend: const Value(true),
          studyModeEnabled: const Value(false),
          logDirectory: const Value(r'C:\tutor1on1\logs'),
          llmLogPath: const Value(r'C:\tutor1on1\logs\llm_logs.jsonl'),
          ttsLogPath: const Value(r'C:\tutor1on1\logs\tts_logs.jsonl'),
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
  final courseRoot = await Directory.systemTemp.createTemp('session_service_');
  final courseVersionId = await db.createCourseVersion(
    teacherId: teacherId,
    subject: 'Math',
    granularity: 1,
    textbookText: 'textbook',
    sourcePath: courseRoot.path,
  );
  await File('${courseRoot.path}\\1.1_lecture.txt').writeAsString(
    'Integers can be positive, negative, or zero.',
  );
  await File('${courseRoot.path}\\1.1_easy.txt').writeAsString(
    'Easy Question bank',
  );
  await File('${courseRoot.path}\\1.1_medium.txt').writeAsString(
    'Medium Question bank',
  );
  await File('${courseRoot.path}\\1.1_hard.txt').writeAsString(
    'Hard Question bank',
  );
  await db.into(db.courseNodes).insert(
        CourseNodesCompanion.insert(
          courseVersionId: courseVersionId,
          kpKey: '1.1',
          title: 'Integers',
          description: 'Compare positive and negative integers.',
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
    studentId: studentId,
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

void _queueReviewQuestion(
  _FakeLlmService llmService, {
  required String callHash,
  String difficulty = 'easy',
  String text = 'Review question?',
}) {
  final responseText = text.replaceAll('{{difficulty}}', difficulty);
  llmService.queueCall(
    Future<LlmCallResult>.value(
      _llmOk(
        responseText: responseText,
        callHash: callHash,
      ),
    ),
  );
}

Future<void> _runReviewAction({
  required SessionService service,
  required _TutorFixture fixture,
  int? sessionId,
  String studentInput = '',
  String? helpBias,
}) async {
  final handle = await service.startTutorAction(
    sessionId: sessionId ?? fixture.sessionId,
    mode: 'review',
    studentInput: studentInput,
    courseVersion: fixture.courseVersion,
    node: fixture.node,
    helpBias: helpBias,
  );
  await handle.future;
}

Future<TutorControlState> _sessionControl(AppDatabase db, int sessionId) async {
  final session = await db.getSession(sessionId);
  final control = TutorControlState.fromJsonText(session?.controlStateJson);
  if (control == null) {
    throw StateError('Missing control state.');
  }
  return control;
}

Future<TutorEvidenceState> _sessionEvidence(
  AppDatabase db,
  int sessionId,
) async {
  final session = await db.getSession(sessionId);
  final evidence = TutorEvidenceState.fromJsonText(session?.evidenceStateJson);
  if (evidence == null) {
    throw StateError('Missing evidence state.');
  }
  return evidence;
}

Future<ChatMessage> _latestAssistantMessage(
    AppDatabase db, int sessionId) async {
  final messages = await db.getMessagesForSession(sessionId);
  return messages.lastWhere((message) => message.role == 'assistant');
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

  test(
      'learn turn falls back to cached bundle when scaffold misses lecture files',
      () async {
    final artifactRoot =
        await Directory.systemTemp.createTemp('session_bundle_artifacts_');
    final sourceRoot = await Directory.systemTemp.createTemp(
      'session_bundle_source_',
    );
    final scaffoldRoot = await Directory.systemTemp.createTemp(
      'session_bundle_scaffold_',
    );
    final courseArtifactService = CourseArtifactService(
      artifactsRootProvider: () async => artifactRoot,
    );
    File? bundleFile;
    final bundleBackedService = SessionService(
      db,
      llmService,
      promptRepository,
      settingsRepository,
      llmLogRepository,
      courseArtifactService: courseArtifactService,
    );
    try {
      final teacherId = await db.createUser(
        username: 'teacher_bundle_session',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 2001,
      );
      final studentId = await db.createUser(
        username: 'student_bundle_session',
        pinHash: 'hash',
        role: 'student',
        teacherId: teacherId,
        remoteUserId: 2002,
      );

      await File(p.join(sourceRoot.path, 'contents.txt')).writeAsString('''
1 Unit
1.1 Integers
''');
      await File(p.join(sourceRoot.path, '1_lecture.txt'))
          .writeAsString('Root lecture');
      await File(p.join(sourceRoot.path, '1.1_lecture.txt')).writeAsString(
        'Integers can be positive, negative, or zero.',
      );
      await File(p.join(sourceRoot.path, '1.1_easy.txt'))
          .writeAsString('Question bank');
      await File(p.join(scaffoldRoot.path, 'contents.txt')).writeAsString('''
1 Unit
1.1 Integers
''');

      final archive = Archive();
      final contentsBytes = utf8.encode('''
1 Unit
1.1 Integers
''');
      final rootLectureBytes = utf8.encode('Root lecture');
      final lectureBytes = utf8.encode(
        'Integers can be positive, negative, or zero.',
      );
      final questionBytes = utf8.encode('Question bank');
      archive.addFile(
        ArchiveFile('contents.txt', contentsBytes.length, contentsBytes),
      );
      archive.addFile(
        ArchiveFile('1_lecture.txt', rootLectureBytes.length, rootLectureBytes),
      );
      archive.addFile(
        ArchiveFile('1.1_lecture.txt', lectureBytes.length, lectureBytes),
      );
      archive.addFile(
        ArchiveFile('1.1_easy.txt', questionBytes.length, questionBytes),
      );
      bundleFile = File(p.join(sourceRoot.path, 'bundle.zip'));
      final encoded = ZipEncoder().encode(archive);
      expect(encoded, isNotNull);
      await bundleFile.writeAsBytes(encoded!, flush: true);
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Bundle Course',
        granularity: 1,
        textbookText: '''
1 Unit
1.1 Integers
''',
        sourcePath: scaffoldRoot.path,
      );
      await courseArtifactService.storeImportedContentBundle(
        courseVersionId: courseVersionId,
        folderPath: scaffoldRoot.path,
        bundleFile: bundleFile,
        buildChapterArtifacts: false,
      );
      await db.into(db.courseNodes).insert(
            CourseNodesCompanion.insert(
              courseVersionId: courseVersionId,
              kpKey: '1.1',
              title: 'Integers',
              description: '1.1 Integers',
              orderIndex: 0,
            ),
          );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );
      final sessionId = await bundleBackedService.startSession(
        studentId: studentId,
        courseVersionId: courseVersionId,
        kpKey: '1.1',
      );
      final courseVersion = await db.getCourseVersionById(courseVersionId);
      final node = await db.getCourseNodeByKey(courseVersionId, '1.1');
      expect(courseVersion, isNotNull);
      expect(node, isNotNull);

      llmService.queueCall(
        Future<LlmCallResult>.value(
          _llmOk(
            responseText: 'Bundle-backed response.',
          ),
        ),
      );

      final handle = await bundleBackedService.startTutorAction(
        sessionId: sessionId,
        mode: 'learn',
        studentInput: 'Teach me simply.',
        courseVersion: courseVersion!,
        node: node!,
      );
      await handle.future;

      expect(
        llmService.callInvocations.single.renderedPrompt,
        contains('Integers can be positive, negative, or zero.'),
      );
    } finally {
      if (bundleFile != null && bundleFile.existsSync()) {
        await bundleFile.delete();
      }
      await artifactRoot.delete(recursive: true);
      await sourceRoot.delete(recursive: true);
      await scaffoldRoot.delete(recursive: true);
    }
  });

  test('learn turn persists plain visible text without structured schema',
      () async {
    final fixture = await _createTutorFixture(db: db, service: service);
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: 'Start by thinking of zero as the middle point.',
        ),
      ),
    );

    final handle = await service.startTutorAction(
      sessionId: fixture.sessionId,
      mode: 'learn',
      studentInput: 'Teach me simply.',
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );
    await handle.future;

    final control = await _sessionControl(db, fixture.sessionId);
    final evidence = await _sessionEvidence(db, fixture.sessionId);
    final message = await _latestAssistantMessage(db, fixture.sessionId);

    expect(llmService.callInvocations.single.promptName, equals('learn'));
    expect(llmService.callInvocations.single.schemaMap, isNull);
    expect(
      llmService.callInvocations.single.renderedPrompt,
      contains('Teach me simply.'),
    );
    expect(message.content,
        equals('Start by thinking of zero as the middle point.'));
    expect(control.recommendedAction, isNull);
    expect(control.activeReviewQuestion, isNull);
    expect(control.turnFinished, isTrue);
    expect(evidence.reviewCorrectTotal, equals(0));
    expect(evidence.lastAssessedAction, equals('LEARN'));
  });

  test('visible tutor text strips think blocks but raw payload keeps them',
      () async {
    final fixture = await _createTutorFixture(db: db, service: service);
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: '<think>hidden chain of thought</think>Visible answer.',
        ),
      ),
    );

    final handle = await service.startTutorAction(
      sessionId: fixture.sessionId,
      mode: 'learn',
      studentInput: 'Teach me simply.',
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );
    await handle.future;

    final message = await _latestAssistantMessage(db, fixture.sessionId);

    expect(message.content, equals('Visible answer.'));
    expect(
        message.rawContent, contains('<think>hidden chain of thought</think>'));
  });

  test(
      'unfinished review keeps one active question and does not count progress',
      () async {
    final fixture = await _createTutorFixture(db: db, service: service);
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: 'Which number is greater: -3 or 2?',
        ),
      ),
    );

    final handle = await service.startTutorAction(
      sessionId: fixture.sessionId,
      mode: 'review',
      studentInput: '',
      courseVersion: fixture.courseVersion,
      node: fixture.node,
      helpBias: 'EASIER',
    );
    await handle.future;

    expect(
      llmService.callInvocations.single.renderedPrompt,
      contains('Question bank'),
    );
    expect(
      llmService.callInvocations.single.renderedPrompt,
      isNot(contains('[source_material]')),
    );
    final control = await _sessionControl(db, fixture.sessionId);
    final evidence = await _sessionEvidence(db, fixture.sessionId);

    expect(control.step, equals(TutorTurnStep.continueTurn));
    expect(control.turnFinished, isFalse);
    expect(control.activeReviewQuestion?['text'], contains('-3 or 2'));
    expect(control.activeReviewQuestion?['difficulty'], equals('easy'));
    expect(evidence.reviewCorrectTotal, equals(0));
    expect(evidence.reviewAttemptTotal, equals(0));
    expect(control.justPassedKpEvent, isNull);
  });

  test('review init clamps to the only available question difficulty',
      () async {
    final fixture = await _createTutorFixture(db: db, service: service);
    final sourcePath = fixture.courseVersion.sourcePath!;
    await File(p.join(sourcePath, '1.1_easy.txt')).delete();
    await File(p.join(sourcePath, '1.1_medium.txt')).delete();
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: 'Hard-only review question?',
          callHash: 'hard_only_prompt',
        ),
      ),
    );

    await _runReviewAction(
      service: service,
      fixture: fixture,
      helpBias: 'EASIER',
    );

    final control = await _sessionControl(db, fixture.sessionId);
    final progress = await db.getProgress(
      studentId: fixture.studentId,
      courseVersionId: fixture.courseVersion.id,
      kpKey: fixture.node.kpKey,
    );
    final renderedPrompt = llmService.callInvocations.single.renderedPrompt;

    expect(renderedPrompt, contains('Hard Question bank'));
    expect(renderedPrompt, isNot(contains('Easy Question bank')));
    expect(control.currentReviewDifficulty, equals('hard'));
    expect(control.activeReviewQuestion?['difficulty'], equals('hard'));
    expect(progress?.questionLevel, equals('hard'));
  });

  test('finished review increments local counters and flips lit after two wins',
      () async {
    final fixture = await _createTutorFixture(db: db, service: service);
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: 'Which number is greater: -3 or 2?',
          callHash: 'review_prompt_1',
        ),
      ),
    );
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: jsonEncode(<String, Object?>{
            'text': 'Correct. 2 is greater than -3.',
            'mistakes': <String>[],
            'finished': true,
            'difficulty_adjustment': 'harder',
          }),
          callHash: 'review_answer_1',
        ),
      ),
    );
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: 'Put these in ascending order: 1, -4, 2, -3.',
          callHash: 'review_prompt_2',
        ),
      ),
    );
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: jsonEncode(<String, Object?>{
            'text': 'Correct. The order is -4, -3, 1, 2.',
            'mistakes': <String>['ordering_integers'],
            'finished': true,
            'difficulty_adjustment': 'same',
          }),
          callHash: 'review_answer_2',
        ),
      ),
    );

    final firstPrompt = await service.startTutorAction(
      sessionId: fixture.sessionId,
      mode: 'review',
      studentInput: '',
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );
    await firstPrompt.future;

    final firstAnswer = await service.startTutorAction(
      sessionId: fixture.sessionId,
      mode: 'review',
      studentInput: '2',
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );
    await firstAnswer.future;

    var session = await db.getSession(fixture.sessionId);
    expect(session?.summaryLit, isFalse);

    final secondPrompt = await service.startTutorAction(
      sessionId: fixture.sessionId,
      mode: 'review',
      studentInput: '',
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );
    await secondPrompt.future;

    final secondAnswer = await service.startTutorAction(
      sessionId: fixture.sessionId,
      mode: 'review',
      studentInput: '-4, -3, 1, 2',
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );
    await secondAnswer.future;

    final evidence = await _sessionEvidence(db, fixture.sessionId);
    final control = await _sessionControl(db, fixture.sessionId);
    session = await db.getSession(fixture.sessionId);

    expect(evidence.reviewCorrectTotal, equals(2));
    expect(evidence.reviewAttemptTotal, equals(2));
    expect(evidence.mediumPassedCount, equals(1));
    expect(evidence.hardPassedCount, equals(1));
    expect(evidence.lastEvidence?['mistakes'],
        equals(<String>['ordering_integers']));
    expect(control.justPassedKpEvent?.easyPassedCount, equals(0));
    expect(control.justPassedKpEvent?.mediumPassedCount, equals(1));
    expect(control.justPassedKpEvent?.hardPassedCount, equals(1));
    expect(session?.summaryLit, isTrue);
  });

  test('learn payload does not require structured retry', () async {
    final fixture = await _createTutorFixture(db: db, service: service);
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: jsonEncode(<String, Object?>{
            'text': 'This payload is missing next_action.',
            'difficulty': 'easy',
            'mistakes': <String>[],
          }),
          callHash: 'invalid_learn',
        ),
      ),
    );

    final handle = await service.startTutorAction(
      sessionId: fixture.sessionId,
      mode: 'learn',
      studentInput: 'Help.',
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );
    await handle.future;

    final message = await _latestAssistantMessage(db, fixture.sessionId);

    expect(llmService.callInvocations.length, equals(1));
    expect(message.content, equals('This payload is missing next_action.'));
    expect(
      llmLogRepository.entries.any(
        (entry) => entry.promptName == 'learn' && entry.status == 'retry',
      ),
      isFalse,
    );
    expect(
      llmLogRepository.entries.any(
        (entry) =>
            entry.promptName == 'learn' &&
            entry.status == 'persist' &&
            entry.dbWriteOk == true,
      ),
      isTrue,
    );
  });

  test('custom student pass config can pass a KP after one easy win', () async {
    final fixture = await _createTutorFixture(db: db, service: service);
    await db.upsertStudentPassConfig(
      courseVersionId: fixture.courseVersion.id,
      studentId: fixture.studentId,
      easyWeight: 1,
      mediumWeight: 1,
      hardWeight: 1,
      passThreshold: 1,
    );
    _queueReviewQuestion(
      llmService,
      callHash: 'custom_pass_rule_prompt',
      difficulty: 'easy',
    );
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: jsonEncode(<String, Object?>{
            'text': 'Correct.',
            'mistakes': <String>[],
            'finished': true,
            'difficulty_adjustment': 'same',
          }),
          callHash: 'custom_pass_rule',
        ),
      ),
    );

    await _runReviewAction(
      service: service,
      fixture: fixture,
      helpBias: 'EASIER',
    );
    await _runReviewAction(
      service: service,
      fixture: fixture,
      studentInput: '2',
    );

    final session = await db.getSession(fixture.sessionId);
    final control = await _sessionControl(db, fixture.sessionId);
    final progress = await db.getProgress(
      studentId: fixture.studentId,
      courseVersionId: fixture.courseVersion.id,
      kpKey: fixture.node.kpKey,
    );

    expect(control.justPassedKpEvent?.easyPassedCount, equals(1));
    expect(control.justPassedKpEvent?.mediumPassedCount, equals(0));
    expect(control.justPassedKpEvent?.hardPassedCount, equals(0));
    expect(session?.summaryLit, isTrue);
    expect(session?.summaryLitPercent, equals(100));
    expect(progress?.lit, isTrue);
    expect(progress?.litPercent, equals(100));
  });

  test('finished review without active question does not increment progress',
      () async {
    final fixture = await _createTutorFixture(db: db, service: service);
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: jsonEncode(<String, Object?>{
            'text': 'Correct, but no active review question was pending.',
            'mistakes': <String>[],
            'finished': true,
            'difficulty_adjustment': 'same',
          }),
          callHash: 'orphan_finished_review',
        ),
      ),
    );

    await _runReviewAction(
      service: service,
      fixture: fixture,
      studentInput: '2',
    );

    final evidence = await _sessionEvidence(db, fixture.sessionId);
    final control = await _sessionControl(db, fixture.sessionId);
    final progress = await db.getProgress(
      studentId: fixture.studentId,
      courseVersionId: fixture.courseVersion.id,
      kpKey: fixture.node.kpKey,
    );

    expect(evidence.reviewCorrectTotal, equals(0));
    expect(evidence.reviewAttemptTotal, equals(0));
    expect(control.justPassedKpEvent, isNull);
    expect(progress?.easyPassedCount ?? 0, equals(0));
  });

  test('just-passed event uses post-update global progress counts', () async {
    final fixture = await _createTutorFixture(db: db, service: service);
    _queueReviewQuestion(
      llmService,
      callHash: 'global_counts_seed_prompt',
      difficulty: 'medium',
    );
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: jsonEncode(<String, Object?>{
            'text': 'Correct medium review.',
            'mistakes': <String>[],
            'finished': true,
            'difficulty_adjustment': 'harder',
          }),
          callHash: 'global_counts_seed',
        ),
      ),
    );

    await _runReviewAction(service: service, fixture: fixture);
    await _runReviewAction(
      service: service,
      fixture: fixture,
      studentInput: 'medium answer',
    );

    final secondSessionId = await service.startSession(
      studentId: fixture.studentId,
      courseVersionId: fixture.courseVersion.id,
      kpKey: fixture.node.kpKey,
    );
    _queueReviewQuestion(
      llmService,
      callHash: 'global_counts_pass_prompt',
      difficulty: 'hard',
    );
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: jsonEncode(<String, Object?>{
            'text': 'Correct hard review.',
            'mistakes': <String>[],
            'finished': true,
            'difficulty_adjustment': 'same',
          }),
          callHash: 'global_counts_pass',
        ),
      ),
    );

    await _runReviewAction(
      service: service,
      fixture: fixture,
      sessionId: secondSessionId,
    );
    await _runReviewAction(
      service: service,
      fixture: fixture,
      sessionId: secondSessionId,
      studentInput: 'hard answer',
    );

    final control = await _sessionControl(db, secondSessionId);
    final progress = await db.getProgress(
      studentId: fixture.studentId,
      courseVersionId: fixture.courseVersion.id,
      kpKey: fixture.node.kpKey,
    );
    final session = await db.getSession(secondSessionId);

    expect(control.justPassedKpEvent?.easyPassedCount, equals(0));
    expect(control.justPassedKpEvent?.mediumPassedCount, equals(1));
    expect(control.justPassedKpEvent?.hardPassedCount, equals(1));
    expect(progress?.mediumPassedCount, equals(1));
    expect(progress?.hardPassedCount, equals(1));
    expect(session?.summaryLit, isTrue);
  });

  test('unfinished review on an already-passed KP does not emit a pass event',
      () async {
    final fixture = await _createTutorFixture(db: db, service: service);
    await db.upsertStudentPassConfig(
      courseVersionId: fixture.courseVersion.id,
      studentId: fixture.studentId,
      easyWeight: 1,
      mediumWeight: 1,
      hardWeight: 1,
      passThreshold: 1,
    );
    _queueReviewQuestion(
      llmService,
      callHash: 'first_pass_prompt',
      difficulty: 'easy',
    );
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: jsonEncode(<String, Object?>{
            'text': 'Correct.',
            'mistakes': <String>[],
            'finished': true,
            'difficulty_adjustment': 'same',
          }),
          callHash: 'first_pass',
        ),
      ),
    );

    await _runReviewAction(
      service: service,
      fixture: fixture,
      helpBias: 'EASIER',
    );
    await _runReviewAction(
      service: service,
      fixture: fixture,
      studentInput: '2',
    );

    final secondSessionId = await service.startSession(
      studentId: fixture.studentId,
      courseVersionId: fixture.courseVersion.id,
      kpKey: fixture.node.kpKey,
    );
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: 'Keep working on the same question.',
          callHash: 'already_passed_unfinished',
        ),
      ),
    );

    final second = await service.startTutorAction(
      sessionId: secondSessionId,
      mode: 'review',
      studentInput: '',
      courseVersion: fixture.courseVersion,
      node: fixture.node,
    );
    await second.future;

    final control = await _sessionControl(db, secondSessionId);
    final session = await db.getSession(secondSessionId);

    expect(control.justPassedKpEvent, isNull);
    expect(control.turnFinished, isFalse);
    expect(session?.summaryLit, isTrue);
  });

  test('reviewing an already-passed KP does not re-award the pass event',
      () async {
    final fixture = await _createTutorFixture(db: db, service: service);
    await db.upsertStudentPassConfig(
      courseVersionId: fixture.courseVersion.id,
      studentId: fixture.studentId,
      easyWeight: 1,
      mediumWeight: 1,
      hardWeight: 1,
      passThreshold: 1,
    );
    _queueReviewQuestion(
      llmService,
      callHash: 'already_passed_seed_prompt',
      difficulty: 'easy',
    );
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: jsonEncode(<String, Object?>{
            'text': 'Correct.',
            'mistakes': <String>[],
            'finished': true,
            'difficulty_adjustment': 'same',
          }),
          callHash: 'already_passed_seed',
        ),
      ),
    );

    await _runReviewAction(
      service: service,
      fixture: fixture,
      helpBias: 'EASIER',
    );
    await _runReviewAction(
      service: service,
      fixture: fixture,
      studentInput: '2',
    );

    final secondSessionId = await service.startSession(
      studentId: fixture.studentId,
      courseVersionId: fixture.courseVersion.id,
      kpKey: fixture.node.kpKey,
    );
    _queueReviewQuestion(
      llmService,
      callHash: 'already_passed_repeat_prompt',
      difficulty: 'easy',
    );
    llmService.queueCall(
      Future<LlmCallResult>.value(
        _llmOk(
          responseText: jsonEncode(<String, Object?>{
            'text': 'Correct again.',
            'mistakes': <String>[],
            'finished': true,
            'difficulty_adjustment': 'same',
          }),
          callHash: 'already_passed_repeat',
        ),
      ),
    );

    await _runReviewAction(
      service: service,
      fixture: fixture,
      sessionId: secondSessionId,
    );
    await _runReviewAction(
      service: service,
      fixture: fixture,
      sessionId: secondSessionId,
      studentInput: '3',
    );

    final control = await _sessionControl(db, secondSessionId);
    final progress = await db.getProgress(
      studentId: fixture.studentId,
      courseVersionId: fixture.courseVersion.id,
      kpKey: fixture.node.kpKey,
    );

    expect(control.justPassedKpEvent, isNull);
    expect(progress?.easyPassedCount, equals(2));
    expect(progress?.lit, isTrue);
  });
}
