import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/llm/llm_providers.dart';
import 'package:tutor1on1/services/settings_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('load migrates retired OpenAI Codex settings to OpenAI API', () async {
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

    final openAi = LlmProviders.findById(
      LlmProviders.defaultProviders(),
      'openai',
    )!;
    final loaded = await SettingsRepository(db).load();
    final persisted = await db.select(db.appSettings).getSingle();

    expect(loaded.providerId, equals(openAi.id));
    expect(loaded.baseUrl, equals(openAi.baseUrl));
    expect(loaded.model, equals(openAi.models.first));
    expect(persisted.providerId, equals(openAi.id));
    expect(persisted.baseUrl, equals(openAi.baseUrl));
    expect(persisted.model, equals(openAi.models.first));
  });
}
