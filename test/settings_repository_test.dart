import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/services/settings_repository.dart';

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
}
