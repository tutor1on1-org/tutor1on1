import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:family_teacher/db/app_database.dart';
import 'package:family_teacher/services/llm_log_repository.dart';
import 'package:family_teacher/services/log_crypto_service.dart';
import 'package:family_teacher/services/settings_repository.dart';

class _FakeSettingsRepository extends SettingsRepository {
  _FakeSettingsRepository(super.db, this._settings);

  final AppSetting _settings;

  @override
  Future<AppSetting> load() async => _settings;
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late LlmLogRepository repository;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('llm_log_repo_test_');
    final settingsRepository = _FakeSettingsRepository(
      db,
      AppSetting(
        id: 1,
        baseUrl: 'https://api.openai.com/v1',
        providerId: 'openai',
        model: 'gpt-test',
        reasoningEffort: 'high',
        ttsModel: null,
        sttModel: null,
        timeoutSeconds: 60,
        maxTokens: 8000,
        ttsInitialDelayMs: 60000,
        ttsTextLeadMs: 1000,
        ttsAudioPath: tempDir.path,
        sttAutoSend: false,
        enterToSend: true,
        studyModeEnabled: false,
        logDirectory: tempDir.path,
        llmLogPath: p.join(tempDir.path, 'llm_logs.jsonl'),
        ttsLogPath: p.join(tempDir.path, 'tts_logs.jsonl'),
        llmMode: 'LIVE_RECORD',
        locale: null,
        updatedAt: DateTime.now(),
      ),
    );
    repository = LlmLogRepository(
      settingsRepository,
      logCrypto: LogCryptoService.instance,
    );
    await LogCryptoService.instance.activate(
      userId: 6,
      role: 'student',
      password: '1234',
    );
  });

  tearDown(() async {
    LogCryptoService.instance.clear();
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('loadEntries decrypts reasoning text and owner metadata', () async {
    await repository.appendEntry(
      promptName: 'review',
      model: 'gpt-5.4',
      baseUrl: 'https://api.openai.com/v1',
      mode: 'LIVE_RECORD',
      status: 'ok',
      callHash: 'hash_123',
      latencyMs: 1234,
      parseValid: true,
      teacherId: 1,
      studentId: 6,
      courseVersionId: 17,
      sessionId: 83,
      kpKey: '2.3.5.1',
      action: 'review',
      renderedChars: 6000,
      responseChars: 400,
      reasoningText:
          '{"provider":"openai","model":"gpt-5.4","reasoning_effort":"high","reasoning_text":"Think step by step."}',
      dbWriteOk: true,
    );

    final entries = await repository.loadEntries();

    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry.logVersion, equals(2));
    expect(entry.promptName, equals('review'));
    expect(entry.model, equals('gpt-5.4'));
    expect(entry.status, equals('ok'));
    expect(entry.reasoningText,
        contains('"reasoning_text":"Think step by step."'));
    expect(entry.ownerUserId, equals(6));
    expect(entry.ownerRole, equals('student'));
    expect(entry.dbWriteOk, isTrue);
  });
}
