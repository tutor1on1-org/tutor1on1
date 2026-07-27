import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/l10n/app_localizations.dart';
import 'package:tutor1on1/models/tutor_action.dart';
import 'package:tutor1on1/models/tutor_contract.dart';
import 'package:tutor1on1/security/hash_utils.dart';
import 'package:tutor1on1/services/app_services.dart';
import 'package:tutor1on1/services/secure_storage_service.dart';
import 'package:tutor1on1/services/settings_repository.dart';
import 'package:tutor1on1/services/stt_service.dart';
import 'package:tutor1on1/services/tts_service.dart';
import 'package:tutor1on1/state/auth_controller.dart';
import 'package:tutor1on1/state/settings_controller.dart';
import 'package:tutor1on1/ui/tutor_session_page.dart';
import 'package:tutor1on1/ui/widgets/searchable_model_picker.dart';

class _FixedAuthController extends ChangeNotifier implements AuthController {
  _FixedAuthController(this._currentUser);

  final User _currentUser;

  @override
  User? get currentUser => _currentUser;

  @override
  String? get lastError => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedSettingsController extends ChangeNotifier
    implements SettingsController {
  _FixedSettingsController(this._settings);

  AppSetting _settings;
  String? updatedModel;

  @override
  AppSetting? get settings => _settings;

  @override
  bool get isLoading => false;

  @override
  Future<void> update({
    required String providerId,
    required String baseUrl,
    required String model,
    required String reasoningEffort,
    required String ttsModel,
    required String sttModel,
    required int timeoutSeconds,
    required int maxTokens,
    required int ttsInitialDelayMs,
    required int ttsTextLeadMs,
    required String ttsAudioPath,
    required String logDirectory,
    required String llmMode,
    required bool sttAutoSend,
    required bool enterToSend,
    String? locale,
  }) async {
    updatedModel = model;
    _settings = _settings.copyWith(
      providerId: Value(providerId),
      baseUrl: baseUrl,
      model: model,
      reasoningEffort: reasoningEffort,
      ttsModel: Value(ttsModel.trim().isEmpty ? null : ttsModel),
      sttModel: Value(sttModel.trim().isEmpty ? null : sttModel),
      timeoutSeconds: timeoutSeconds,
      maxTokens: maxTokens,
      ttsInitialDelayMs: ttsInitialDelayMs,
      ttsTextLeadMs: ttsTextLeadMs,
      ttsAudioPath: Value(ttsAudioPath),
      sttAutoSend: sttAutoSend,
      enterToSend: enterToSend,
      logDirectory: Value(logDirectory),
      llmMode: llmMode,
      locale: Value(locale),
    );
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSecureStorage extends SecureStorageService {
  _FakeSecureStorage({Map<String, String>? apiKeys})
      : _apiKeys = Map<String, String>.from(apiKeys ?? const {});

  final Map<String, String> _apiKeys;

  @override
  Future<String?> readApiKeyForBaseUrl(String baseUrl) async {
    return _apiKeys[baseUrl] ?? _apiKeys[baseUrl.toLowerCase()];
  }

  @override
  Future<void> writeApiKeyForBaseUrl(String baseUrl, String value) async {
    _apiKeys[baseUrl] = value;
    _apiKeys[baseUrl.toLowerCase()] = value;
  }
}

class _FakeTtsService implements TtsService {
  @override
  Stream<TtsPlaybackState> get playbackStream =>
      const Stream<TtsPlaybackState>.empty();

  @override
  Future<void> stop({int? sessionId}) async {}

  @override
  Future<void> stopReplay({int? sessionId}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSttService implements SttService {
  @override
  Future<void> cancelRecording({int? sessionId}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAppServices implements AppServices {
  _FakeAppServices({
    required this.db,
    required this.settingsRepository,
    SecureStorageService? secureStorage,
    required this.ttsService,
    required this.sttService,
  }) : secureStorage = secureStorage ?? _FakeSecureStorage();

  @override
  final AppDatabase db;

  @override
  final SettingsRepository settingsRepository;

  @override
  final SecureStorageService secureStorage;

  @override
  final TtsService ttsService;

  @override
  final SttService sttService;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TutorPageFixture {
  const _TutorPageFixture({
    required this.sessionId,
    required this.student,
    required this.courseVersion,
    required this.node,
  });

  final int sessionId;
  final User student;
  final CourseVersion courseVersion;
  final CourseNode node;
}

Future<_TutorPageFixture> _createFixture(AppDatabase db) async {
  final teacherId = await db.createUser(
    username: 'teacher_footer',
    pinHash: 'hash',
    role: 'teacher',
    remoteUserId: 5001,
  );
  final studentId = await db.createUser(
    username: 'charles',
    pinHash: 'hash',
    role: 'student',
    teacherId: teacherId,
    remoteUserId: 5002,
  );
  final courseVersionId = await db.createCourseVersion(
    teacherId: teacherId,
    subject: 'Math',
    granularity: 1,
    textbookText: 'Numbers',
    sourcePath: r'C:\tutor1on1\test_course',
  );
  await db.into(db.courseNodes).insert(
        CourseNodesCompanion.insert(
          courseVersionId: courseVersionId,
          kpKey: '1.1.1.1',
          title: 'Integers',
          description: 'Compare integers.',
          orderIndex: 0,
        ),
      );
  await db.assignStudent(
    studentId: studentId,
    courseVersionId: courseVersionId,
  );
  await db.upsertStudentPassConfig(
    courseVersionId: courseVersionId,
    studentId: studentId,
    easyWeight: 1,
    mediumWeight: 1,
    hardWeight: 1,
    passThreshold: 4,
  );
  await db.into(db.progressEntries).insert(
        ProgressEntriesCompanion.insert(
          studentId: studentId,
          courseVersionId: courseVersionId,
          kpKey: '1.1.1.1',
          lit: const Value(false),
          litPercent: const Value(0),
          easyPassedCount: const Value(2),
          mediumPassedCount: const Value(1),
          hardPassedCount: const Value(0),
        ),
      );
  final sessionId = await db.into(db.chatSessions).insert(
        ChatSessionsCompanion.insert(
          studentId: studentId,
          courseVersionId: courseVersionId,
          kpKey: '1.1.1.1',
          title: const Value('KP 1.1.1.1'),
          controlStateJson: Value(
            TutorControlState.defaultForMode(TutorMode.learn).toJsonText(),
          ),
          controlStateUpdatedAt: Value(DateTime.utc(2026, 3, 23)),
          evidenceStateJson: Value(TutorEvidenceState.initial().toJsonText()),
          evidenceStateUpdatedAt: Value(DateTime.utc(2026, 3, 23)),
          syncId: const Value('session-footer-test'),
          syncUpdatedAt: Value(DateTime.utc(2026, 3, 23)),
        ),
      );
  await db.into(db.chatMessages).insert(
        ChatMessagesCompanion.insert(
          sessionId: sessionId,
          role: 'assistant',
          content: 'Ready.',
          rawContent: const Value('Ready.'),
          action: const Value('learn'),
        ),
      );
  final student = await db.getUserById(studentId);
  final courseVersion = await db.getCourseVersionById(courseVersionId);
  final node = await db.getCourseNodeByKey(courseVersionId, '1.1.1.1');
  if (student == null || courseVersion == null || node == null) {
    throw StateError('Failed to seed tutor footer fixture.');
  }
  return _TutorPageFixture(
    sessionId: sessionId,
    student: student,
    courseVersion: courseVersion,
    node: node,
  );
}

AppSetting _testSettings() {
  return AppSetting(
    id: 1,
    baseUrl: 'https://api.openai.com/v1',
    providerId: 'openai',
    model: 'gpt-4o-mini',
    reasoningEffort: 'medium',
    ttsModel: null,
    sttModel: null,
    timeoutSeconds: 30,
    maxTokens: 4000,
    ttsInitialDelayMs: 60000,
    ttsTextLeadMs: 1000,
    ttsAudioPath: r'C:\tutor1on1\logs',
    sttAutoSend: false,
    enterToSend: true,
    studyModeEnabled: false,
    logDirectory: r'C:\tutor1on1\logs',
    llmLogPath: r'C:\tutor1on1\logs\llm_logs.jsonl',
    ttsLogPath: r'C:\tutor1on1\logs\tts_logs.jsonl',
    llmMode: 'LIVE',
    locale: 'en',
    updatedAt: DateTime.utc(2026, 3, 23),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'student footer keeps progress badge visible beside the model selector',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        final fixture = await _createFixture(db);
        final settings = _testSettings();
        final settingsRepository = SettingsRepository(db);
        final authController = _FixedAuthController(fixture.student);
        final settingsController = _FixedSettingsController(settings);
        final services = _FakeAppServices(
          db: db,
          settingsRepository: settingsRepository,
          ttsService: _FakeTtsService(),
          sttService: _FakeSttService(),
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<AppDatabase>.value(value: db),
              Provider<AppServices>.value(value: services),
              ChangeNotifierProvider<AuthController>.value(
                value: authController,
              ),
              ChangeNotifierProvider<SettingsController>.value(
                value: settingsController,
              ),
            ],
            child: Center(
              child: SizedBox(
                width: 720,
                height: 900,
                child: MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: ChatSessionPage(
                    sessionId: fixture.sessionId,
                    courseVersion: fixture.courseVersion,
                    node: fixture.node,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        for (var i = 0; i < 10; i += 1) {
          await tester.pump(const Duration(milliseconds: 20));
        }

        expect(
          find.byKey(const Key('student_session_progress_badge')),
          findsOneWidget,
        );
        expect(find.text('2/1/0/75%'), findsOneWidget);
        expect(find.byType(SearchableModelPicker), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<AppDatabase>.value(value: db),
              Provider<AppServices>.value(
                value: _FakeAppServices(
                  db: db,
                  settingsRepository: SettingsRepository(db),
                  ttsService: _FakeTtsService(),
                  sttService: _FakeSttService(),
                ),
              ),
              ChangeNotifierProvider<AuthController>.value(
                value: _FixedAuthController(
                  User(
                    id: 0,
                    username: 'disposed',
                    pinHash: 'hash',
                    role: 'student',
                    teacherId: null,
                    remoteUserId: null,
                    createdAt: DateTime.utc(2026, 3, 23),
                  ),
                ),
              ),
              ChangeNotifierProvider<SettingsController>.value(
                value: _FixedSettingsController(_testSettings()),
              ),
            ],
            child: const SizedBox.shrink(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        await db.close();
      }
    },
  );

  testWidgets(
    'session model picker searches same-key live model cache and auto-saves',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        final fixture = await _createFixture(db);
        final settings = _testSettings();
        final settingsRepository = SettingsRepository(db);
        final authController = _FixedAuthController(fixture.student);
        final settingsController = _FixedSettingsController(settings);
        final baseUrl = settings.baseUrl;
        const currentApiKey = 'same-key-secret';
        await db.insertApiConfig(
          baseUrl: baseUrl,
          model: 'same-key-model',
          reasoningEffort: 'medium',
          ttsModel: '',
          sttModel: '',
          apiKeyHash: sha256Hex(currentApiKey),
        );
        await db.insertApiConfig(
          baseUrl: baseUrl,
          model: 'other-key-model',
          reasoningEffort: 'medium',
          ttsModel: '',
          sttModel: '',
          apiKeyHash: sha256Hex('other-key-secret'),
        );
        await db.upsertApiModelCache(
          baseUrl: baseUrl,
          apiKeyHash: sha256Hex(currentApiKey),
          textModels: const <String>['live-model-a', 'live-model-b'],
          ttsModels: const <String>[],
          sttModels: const <String>[],
        );
        final services = _FakeAppServices(
          db: db,
          settingsRepository: settingsRepository,
          secureStorage: _FakeSecureStorage(
            apiKeys: <String, String>{baseUrl: currentApiKey},
          ),
          ttsService: _FakeTtsService(),
          sttService: _FakeSttService(),
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<AppDatabase>.value(value: db),
              Provider<AppServices>.value(value: services),
              ChangeNotifierProvider<AuthController>.value(
                value: authController,
              ),
              ChangeNotifierProvider<SettingsController>.value(
                value: settingsController,
              ),
            ],
            child: Center(
              child: SizedBox(
                width: 720,
                height: 900,
                child: MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: ChatSessionPage(
                    sessionId: fixture.sessionId,
                    courseVersion: fixture.courseVersion,
                    node: fixture.node,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        for (var i = 0; i < 10; i += 1) {
          await tester.pump(const Duration(milliseconds: 20));
        }

        await tester.tap(find.byType(SearchableModelPicker));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'model');
        await tester.pumpAndSettle();

        expect(find.text('live-model-b'), findsOneWidget);
        expect(find.text('same-key-model'), findsNothing);
        expect(find.text('other-key-model'), findsNothing);

        await tester.tap(find.text('live-model-b'));
        await tester.pumpAndSettle();

        expect(settingsController.updatedModel, equals('live-model-b'));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<AppDatabase>.value(value: db),
              Provider<AppServices>.value(
                value: _FakeAppServices(
                  db: db,
                  settingsRepository: SettingsRepository(db),
                  ttsService: _FakeTtsService(),
                  sttService: _FakeSttService(),
                ),
              ),
              ChangeNotifierProvider<AuthController>.value(
                value: _FixedAuthController(
                  User(
                    id: 0,
                    username: 'disposed',
                    pinHash: 'hash',
                    role: 'student',
                    teacherId: null,
                    remoteUserId: null,
                    createdAt: DateTime.utc(2026, 3, 23),
                  ),
                ),
              ),
              ChangeNotifierProvider<SettingsController>.value(
                value: _FixedSettingsController(_testSettings()),
              ),
            ],
            child: const SizedBox.shrink(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        await db.close();
      }
    },
  );
}
