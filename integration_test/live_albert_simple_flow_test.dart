import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:family_teacher/db/app_database.dart';
import 'package:family_teacher/llm/llm_models.dart';
import 'package:family_teacher/models/tutor_contract.dart';
import 'package:family_teacher/services/app_services.dart';
import 'package:family_teacher/services/log_crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

const String _albertUsername = 'albert';
const String _albertPassword = '1234';
const String _courseSubject = 'UK_MATH_7-13';
const String _kpKey = '1.1.1.1';
const Map<String, dynamic> _studentReplySchema = <String, dynamic>{
  'type': 'object',
  'required': <String>['student_reply'],
  'properties': <String, dynamic>{
    'student_reply': <String, dynamic>{
      'type': 'string',
      'minLength': 1,
    },
  },
  'additionalProperties': false,
};

Future<File> _copyLiveDatabase(Directory tempDir) async {
  final source = File(r'C:\Mac\Home\Documents\family_teacher.db');
  if (!await source.exists()) {
    throw StateError('Live database not found at ${source.path}');
  }
  final target = File(p.join(tempDir.path, 'family_teacher_live_copy.db'));
  await source.copy(target.path);
  for (final suffix in const <String>['-wal', '-shm']) {
    final sidecar = File('${source.path}$suffix');
    if (await sidecar.exists()) {
      await sidecar.copy('${target.path}$suffix');
    }
  }
  return target;
}

Future<void> _pointSettingsToTempLogs(
  AppServices services,
  Directory tempDir,
) async {
  final current = await services.settingsRepository.load();
  final logDir = p.join(tempDir.path, 'logs');
  await Directory(logDir).create(recursive: true);
  await services.settingsRepository.update(
    providerId: current.providerId ?? 'custom',
    baseUrl: current.baseUrl,
    model: current.model,
    reasoningEffort: current.reasoningEffort,
    ttsModel: current.ttsModel ?? '',
    sttModel: current.sttModel ?? '',
    timeoutSeconds: current.timeoutSeconds,
    maxTokens: current.maxTokens,
    ttsInitialDelayMs: current.ttsInitialDelayMs,
    ttsTextLeadMs: current.ttsTextLeadMs,
    ttsAudioPath: tempDir.path,
    logDirectory: logDir,
    llmMode: 'LIVE',
    sttAutoSend: current.sttAutoSend,
    enterToSend: current.enterToSend,
    locale: current.locale,
  );
}

Future<User> _requireAlbert(AppDatabase db) async {
  final user = await db.findUserByUsername(_albertUsername);
  if (user == null) {
    throw StateError('Albert user not found in copied database.');
  }
  return user;
}

Future<_LiveCourseFixture> _requireCourseFixture(AppDatabase db) async {
  final rows = await db.customSelect(
    '''
    SELECT cv.id AS course_version_id
    FROM course_versions cv
    JOIN course_nodes cn ON cn.course_version_id = cv.id
    WHERE cv.subject = ? AND cn.kp_key = ?
    LIMIT 1
    ''',
    variables: <Variable<Object>>[
      const Variable<String>(_courseSubject),
      const Variable<String>(_kpKey),
    ],
  ).get();
  if (rows.isEmpty) {
    throw StateError(
      'Course "$_courseSubject" with KP $_kpKey not found in copied database.',
    );
  }
  final courseVersionId = rows.single.read<int>('course_version_id');
  final courseVersion = await db.getCourseVersionById(courseVersionId);
  final node = await db.getCourseNodeByKey(courseVersionId, _kpKey);
  if (courseVersion == null || node == null) {
    throw StateError('Failed to resolve copied course/node fixture.');
  }
  return _LiveCourseFixture(courseVersion: courseVersion, node: node);
}

Map<String, dynamic> _decodeJsonObject(String? input) {
  final trimmed = (input ?? '').trim();
  if (trimmed.isEmpty) {
    throw StateError('Expected JSON object text, but value was empty.');
  }
  final decoded = jsonDecode(trimmed);
  if (decoded is! Map<String, dynamic>) {
    throw StateError('Expected JSON object text, got: $trimmed');
  }
  return decoded;
}

Future<Map<String, dynamic>> _latestAssistantPayload({
  required AppDatabase db,
  required int sessionId,
  required String action,
}) async {
  final messages = await db.getMessagesForSession(sessionId);
  for (final message in messages.reversed) {
    if (message.role != 'assistant' || message.action != action) {
      continue;
    }
    return _decodeJsonObject(message.parsedJson ?? message.rawContent);
  }
  throw StateError('No assistant payload found for action "$action".');
}

Future<String> _buildStudentReply({
  required AppServices services,
  required _LiveCourseFixture fixture,
  required String teacherText,
}) async {
  final prompt = '''
You are role-playing Albert, a Year 7 student in a tutoring chat.

Goal:
- Answer the teacher's current review question correctly.
- Sound like a short student reply, not a teacher.

Knowledge point:
- ${fixture.node.title}
- ${fixture.node.description}

Teacher visible text:
$teacherText

Rules:
- Return exactly one JSON object with only "student_reply".
- Keep the reply short.
- Answer the current question directly.
- If the teacher text is a hint, use the hint to answer the question.
- Do not add explanation unless the question asks for it.
''';
  final handle = services.llmService.startCall(
    promptName: 'student_roleplay',
    renderedPrompt: prompt,
    schemaMap: _studentReplySchema,
    context: const LlmCallContext(action: 'student_roleplay'),
  );
  final result = await handle.future;
  final decoded = _decodeJsonObject(result.responseText);
  final reply = (decoded['student_reply'] as String?)?.trim() ?? '';
  if (reply.isEmpty) {
    throw StateError('Student role-play returned an empty reply.');
  }
  return reply;
}

Future<void> _printSessionTranscript(AppDatabase db, int sessionId) async {
  final messages = await db.getMessagesForSession(sessionId);
  for (final message in messages) {
    // ignore: avoid_print
    print('${message.role}/${message.action ?? '-'}: ${message.content}');
  }
}

Future<void> _expectSavedApiKey(AppServices services) async {
  final settings = await services.settingsRepository.load();
  final apiKey = await services.secureStorage.readApiKeyForBaseUrl(
    settings.baseUrl,
  );
  expect(
    (apiKey ?? '').trim(),
    isNotEmpty,
    reason: 'Missing saved API key for ${settings.baseUrl}.',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late AppServices services;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'albert_simple_validation_',
    );
    final dbFile = await _copyLiveDatabase(tempDir);
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    services = await AppServices.create(databaseOverride: db);
    await _pointSettingsToTempLogs(services, tempDir);
    final albert = await _requireAlbert(db);
    await LogCryptoService.instance.activate(
      userId: albert.id,
      role: 'student',
      password: _albertPassword,
    );
  });

  tearDown(() async {
    LogCryptoService.instance.clear();
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets(
    'Albert simple flow on UK math 1.1.1.1 keeps lit false without summary',
    (tester) async {
      await _expectSavedApiKey(services);

      final albert = await _requireAlbert(db);
      final fixture = await _requireCourseFixture(db);
      final bundledLearnPrompt =
          await services.promptRepository.loadBundledSystemPrompt('learn');
      final resolvedLearnPrompt = await services.promptRepository.loadPrompt(
        'learn',
        teacherId: fixture.courseVersion.teacherId,
        courseKey: fixture.courseVersion.sourcePath,
        studentId: albert.id,
      );
      expect(
        resolvedLearnPrompt,
        equals(bundledLearnPrompt),
        reason:
            'Simplified tutor must ignore legacy prompt template overrides.',
      );

      final sessionId = await services.sessionService.startSession(
        studentId: albert.id,
        courseVersionId: fixture.courseVersion.id,
        kpKey: fixture.node.kpKey,
      );

      for (final request in const <(String, String)>[
        ('learn', ''),
        ('learn', ''),
        ('review', ''),
        ('review', "I don't understand"),
      ]) {
        final handle = await services.sessionService.startTutorAction(
          sessionId: sessionId,
          mode: request.$1,
          studentInput: request.$2,
          courseVersion: fixture.courseVersion,
          node: fixture.node,
        );
        await handle.future;
      }

      final session = await db.getSession(sessionId);
      final evidenceState = TutorEvidenceState.fromJsonText(
        session?.evidenceStateJson,
      );
      await _printSessionTranscript(db, sessionId);
      // ignore: avoid_print
      print(
        'LIT_FALSE_FLOW lit=${session?.summaryLit} correct=${evidenceState?.reviewCorrectTotal} attempts=${evidenceState?.reviewAttemptTotal}',
      );

      expect(session?.summaryLit, isFalse);
      expect(evidenceState?.reviewCorrectTotal, equals(0));
    },
  );

  testWidgets(
    'Albert role-play student can pass UK math 1.1.1.1 with local lit',
    (tester) async {
      await _expectSavedApiKey(services);

      final albert = await _requireAlbert(db);
      final fixture = await _requireCourseFixture(db);
      final sessionId = await services.sessionService.startSession(
        studentId: albert.id,
        courseVersionId: fixture.courseVersion.id,
        kpKey: fixture.node.kpKey,
      );

      final learn = await services.sessionService.startTutorAction(
        sessionId: sessionId,
        mode: 'learn',
        studentInput: 'Can you teach this simply first?',
        courseVersion: fixture.courseVersion,
        node: fixture.node,
      );
      await learn.future;

      const maxReviewTurns = 12;
      for (var turn = 0; turn < maxReviewTurns; turn++) {
        final session = await db.getSession(sessionId);
        if (session?.summaryLit == true) {
          break;
        }

        final reviewHandle = await services.sessionService.startTutorAction(
          sessionId: sessionId,
          mode: 'review',
          studentInput: '',
          courseVersion: fixture.courseVersion,
          node: fixture.node,
        );
        await reviewHandle.future;

        final payload = await _latestAssistantPayload(
          db: db,
          sessionId: sessionId,
          action: 'review',
        );
        final finished = payload['finished'];
        if (finished is! bool) {
          throw StateError('Review payload missing boolean finished.');
        }
        if (finished) {
          continue;
        }

        final teacherText = (payload['text'] as String?)?.trim() ?? '';
        if (teacherText.isEmpty) {
          throw StateError('Review payload missing visible text.');
        }
        final studentReply = await _buildStudentReply(
          services: services,
          fixture: fixture,
          teacherText: teacherText,
        );
        // ignore: avoid_print
        print('student/review: $studentReply');
        final answerHandle = await services.sessionService.startTutorAction(
          sessionId: sessionId,
          mode: 'review',
          studentInput: studentReply,
          courseVersion: fixture.courseVersion,
          node: fixture.node,
        );
        await answerHandle.future;
      }

      final session = await db.getSession(sessionId);
      final evidenceState = TutorEvidenceState.fromJsonText(
        session?.evidenceStateJson,
      );
      await _printSessionTranscript(db, sessionId);
      // ignore: avoid_print
      print(
        'PASS_FLOW lit=${session?.summaryLit} correct=${evidenceState?.reviewCorrectTotal} attempts=${evidenceState?.reviewAttemptTotal}',
      );

      expect(session?.summaryLit, isTrue);
      expect(evidenceState?.reviewCorrectTotal, greaterThan(0));
    },
  );

  testWidgets(
    'Albert prompt quality review flow prints 10 learn/review tutor calls',
    (tester) async {
      await _expectSavedApiKey(services);

      final albert = await _requireAlbert(db);
      final fixture = await _requireCourseFixture(db);
      final sessionId = await services.sessionService.startSession(
        studentId: albert.id,
        courseVersionId: fixture.courseVersion.id,
        kpKey: fixture.node.kpKey,
      );

      Future<void> tutorTurn({
        required String mode,
        required String studentInput,
      }) async {
        final handle = await services.sessionService.startTutorAction(
          sessionId: sessionId,
          mode: mode,
          studentInput: studentInput,
          courseVersion: fixture.courseVersion,
          node: fixture.node,
        );
        await handle.future;
      }

      await tutorTurn(
        mode: 'learn',
        studentInput: 'Can you teach this simply first?',
      );
      await tutorTurn(
        mode: 'learn',
        studentInput:
            'What is the difference between absolute value and distance?',
      );
      await tutorTurn(mode: 'review', studentInput: '');
      await tutorTurn(mode: 'review', studentInput: "I don't understand");

      for (var i = 0; i < 3; i++) {
        final reviewPayload = await _latestAssistantPayload(
          db: db,
          sessionId: sessionId,
          action: 'review',
        );
        final teacherText = (reviewPayload['text'] as String?)?.trim() ?? '';
        if (reviewPayload['finished'] != false || teacherText.isEmpty) {
          await tutorTurn(mode: 'review', studentInput: '');
          continue;
        }
        final studentReply = await _buildStudentReply(
          services: services,
          fixture: fixture,
          teacherText: teacherText,
        );
        await tutorTurn(mode: 'review', studentInput: studentReply);
        if (i == 1) {
          await tutorTurn(
            mode: 'learn',
            studentInput: 'Why is -1 greater than -4?',
          );
        } else {
          await tutorTurn(mode: 'review', studentInput: '');
        }
      }

      await tutorTurn(mode: 'review', studentInput: "I don't understand");

      final messages = await db.getMessagesForSession(sessionId);
      final tutorMessages = messages.where((message) {
        if (message.role != 'assistant') {
          return false;
        }
        return message.action == 'learn' || message.action == 'review';
      }).toList(growable: false);

      expect(tutorMessages.length, equals(10));
      for (var i = 0; i < tutorMessages.length; i++) {
        final message = tutorMessages[i];
        // ignore: avoid_print
        print('QUALITY_CALL_${i + 1} [${message.action}]: ${message.content}');
      }
    },
  );
}

class _LiveCourseFixture {
  _LiveCourseFixture({
    required this.courseVersion,
    required this.node,
  });

  final CourseVersion courseVersion;
  final CourseNode node;
}
