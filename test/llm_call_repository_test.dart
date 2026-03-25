import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/services/llm_call_repository.dart';
import 'package:tutor1on1/services/log_crypto_service.dart';

void main() {
  late AppDatabase db;
  late LlmCallRepository repository;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LlmCallRepository(db);
    await LogCryptoService.instance.activate(
      userId: 1,
      role: 'teacher',
      password: '1234',
    );
  });

  tearDown(() async {
    LogCryptoService.instance.clear();
    await db.close();
  });

  test('keeps multiple llm call attempts with the same call hash', () async {
    await repository.insert(
      callHash: 'same_hash',
      promptName: 'review',
      renderedPrompt: 'prompt 1',
      model: 'gpt-test',
      baseUrl: 'https://example.com/v1',
      responseText: '{"text":"first"}',
      parseValid: false,
      parseError: 'bad key',
      mode: 'LIVE_RECORD',
      teacherId: 1,
      studentId: 2,
      sessionId: 3,
      action: 'review',
    );
    await repository.insert(
      callHash: 'same_hash',
      promptName: 'review',
      renderedPrompt: 'prompt 1',
      model: 'gpt-test',
      baseUrl: 'https://example.com/v1',
      responseText: '{"text":"second"}',
      parseValid: true,
      mode: 'LIVE_RECORD',
      teacherId: 1,
      studentId: 2,
      sessionId: 3,
      action: 'review',
    );

    final entries = await db.getLlmLogEntries();
    final matching = entries.where((entry) => entry.callHash == 'same_hash');
    final latest = await repository.findByHash('same_hash');

    expect(matching.length, equals(2));
    expect(latest?.responseText, equals('{"text":"second"}'));
    expect(latest?.parseValid, isTrue);
  });
}
