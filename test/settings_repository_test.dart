import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/services/secure_storage_service.dart';
import 'package:tutor1on1/services/settings_repository.dart';

class _AgentSettingsStorage implements SecureStorageService {
  String? model;
  String? effort;

  @override
  Future<String?> readAgentTutorModel() async => model;

  @override
  Future<void> writeAgentTutorModel(String value) async {
    model = value;
  }

  @override
  Future<String?> readAgentTutorReasoningEffort() async => effort;

  @override
  Future<void> writeAgentTutorReasoningEffort(String value) async {
    effort = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('load preserves OpenAI Codex OAuth settings', () async {
    await db.into(db.appSettings).insert(
          AppSettingsCompanion.insert(
            baseUrl: 'https://chatgpt.com/backend-api',
            providerId: const Value('openai-codex'),
            model: 'gpt-5.5',
            timeoutSeconds: 60,
            maxTokens: 8000,
            ttsAudioPath: const Value('/browser/audio'),
            logDirectory: const Value('/browser/logs'),
            llmLogPath: const Value('/browser/logs/llm_logs.jsonl'),
            ttsLogPath: const Value('/browser/logs/tts_logs.jsonl'),
            llmMode: 'LIVE_RECORD',
          ),
        );

    final loaded = await SettingsRepository(db).load();
    final persisted = await db.select(db.appSettings).getSingle();

    expect(loaded.providerId, equals('openai-codex'));
    expect(loaded.baseUrl, equals('https://chatgpt.com/backend-api'));
    expect(loaded.model, equals('gpt-5.5'));
    expect(persisted.providerId, equals('openai-codex'));
    expect(persisted.baseUrl, equals('https://chatgpt.com/backend-api'));
    expect(persisted.model, equals('gpt-5.5'));
  });

  test('Agent Tutor model settings do not overwrite Tutor provider settings',
      () async {
    await db.into(db.appSettings).insert(
          AppSettingsCompanion.insert(
            baseUrl: 'https://api.openai.com/v1',
            providerId: const Value('openai'),
            model: 'gpt-4.1',
            reasoningEffort: const Value('high'),
            timeoutSeconds: 60,
            maxTokens: 8000,
            ttsAudioPath: const Value('/browser/audio'),
            logDirectory: const Value('/browser/logs'),
            llmLogPath: const Value('/browser/logs/llm_logs.jsonl'),
            ttsLogPath: const Value('/browser/logs/tts_logs.jsonl'),
            llmMode: 'LIVE_RECORD',
          ),
        );
    final storage = _AgentSettingsStorage();
    final repository = SettingsRepository(
      db,
      secureStorage: storage,
      appLabel: 'agent_tutor',
    );

    final initial = await repository.load();
    expect(initial.providerId, 'agent-tutor');
    expect(initial.model, 'gpt-5.6-sol');
    expect(initial.timeoutSeconds, 600);
    expect(initial.ttsModel, isNull);

    final updated = await repository.update(
      providerId: 'agent-tutor',
      baseUrl: 'https://api.tutor1on1.org',
      model: 'gpt-custom-agent',
      reasoningEffort: 'max',
      ttsModel: '',
      sttModel: '',
      timeoutSeconds: 600,
      maxTokens: 8000,
      ttsInitialDelayMs: 1000,
      ttsTextLeadMs: 1000,
      ttsAudioPath: '/browser/audio',
      logDirectory: '/browser/logs',
      llmMode: 'LIVE',
      sttAutoSend: false,
      enterToSend: true,
    );
    final persisted = await db.select(db.appSettings).getSingle();

    expect(updated.model, 'gpt-custom-agent');
    expect(updated.reasoningEffort, 'max');
    expect(persisted.providerId, 'openai');
    expect(persisted.baseUrl, 'https://api.openai.com/v1');
    expect(persisted.model, 'gpt-4.1');
    expect(persisted.reasoningEffort, 'high');
  });
}
