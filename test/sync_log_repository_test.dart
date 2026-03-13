import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:family_teacher/db/app_database.dart';
import 'package:family_teacher/services/settings_repository.dart';
import 'package:family_teacher/services/sync_log_repository.dart';

class _FakeSettingsRepository extends SettingsRepository {
  _FakeSettingsRepository(super.db, this._settings);

  final AppSetting _settings;

  @override
  Future<AppSetting> load() async => _settings;
}

void main() {
  late AppDatabase db;
  late SettingsRepository settingsRepository;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('sync_log_repo_test_');
    settingsRepository = _FakeSettingsRepository(
      db,
      AppSetting(
        id: 1,
        baseUrl: 'https://example.com',
        providerId: 'openai',
        model: 'gpt-test',
        reasoningEffort: 'medium',
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
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('successful run with no transfer does not create a log line', () async {
    final repository = SyncLogRepository(settingsRepository);
    final file = File(p.join(tempDir.path, 'sync_logs.jsonl'));

    await repository.appendRunEvent(
      trigger: 'timer',
      actorRole: 'student',
      actorUserId: 7,
      stats: SyncRunStats(),
      success: true,
    );

    expect(await file.exists(), isFalse);
  });

  test('successful run with transfer writes one summary line', () async {
    final repository = SyncLogRepository(settingsRepository);
    final stats = SyncRunStats()
      ..addUploaded(count: 2, bytes: 1536)
      ..addDownloaded(count: 1, bytes: 10);

    await repository.appendRunEvent(
      trigger: 'login',
      actorRole: 'teacher',
      actorUserId: 11,
      stats: stats,
      success: true,
    );

    final file = File(p.join(tempDir.path, 'sync_logs.jsonl'));
    final lines = await file.readAsLines();
    expect(lines, hasLength(1));
    final decoded = jsonDecode(lines.single) as Map<String, dynamic>;
    expect(decoded['event'], equals('sync_run'));
    expect(decoded['status'], equals('success'));
    expect(decoded['trigger'], equals('login'));
    expect(decoded['actor_role'], equals('teacher'));
    expect(decoded['actor_user_id'], equals(11));
    expect(decoded['uploaded_count'], equals(2));
    expect(decoded['downloaded_count'], equals(1));
    expect(decoded['uploaded_bytes'], equals(1536));
    expect(decoded['downloaded_bytes'], equals(10));
    expect(decoded['uploaded_kb'], equals(2));
    expect(decoded['downloaded_kb'], equals(1));
  });

  test('failed run writes one error line even without transfer', () async {
    final repository = SyncLogRepository(settingsRepository);

    await repository.appendRunEvent(
      trigger: 'timer',
      actorRole: 'student',
      actorUserId: 5,
      stats: SyncRunStats(),
      success: false,
      error: 'HandshakeException',
    );

    final file = File(p.join(tempDir.path, 'sync_logs.jsonl'));
    final lines = await file.readAsLines();
    expect(lines, hasLength(1));
    final decoded = jsonDecode(lines.single) as Map<String, dynamic>;
    expect(decoded['status'], equals('failed'));
    expect(decoded['error'], equals('HandshakeException'));
    expect(decoded['uploaded_count'], equals(0));
    expect(decoded['downloaded_count'], equals(0));
    expect(decoded['uploaded_kb'], equals(0));
    expect(decoded['downloaded_kb'], equals(0));
  });
}
