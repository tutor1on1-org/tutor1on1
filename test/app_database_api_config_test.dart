import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test(
      'insertApiConfig rejects normalized duplicate rows with empty audio models',
      () async {
    final inserted = await db.insertApiConfig(
      baseUrl: ' https://API.openai.com/v1 ',
      model: 'gpt-test',
      reasoningEffort: 'HIGH',
      ttsModel: '',
      sttModel: '',
      apiKeyHash: 'hash_1',
    );
    final duplicate = await db.insertApiConfig(
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-test',
      reasoningEffort: 'high',
      ttsModel: '',
      sttModel: '',
      apiKeyHash: 'hash_1',
    );

    final rows = await db.watchApiConfigs().first;

    expect(inserted, isTrue);
    expect(duplicate, isFalse);
    expect(rows, hasLength(1));
    expect(rows.single.baseUrl, equals('https://API.openai.com/v1'));
    expect(rows.single.reasoningEffort, equals('high'));
    expect(rows.single.ttsModel, isNull);
    expect(rows.single.sttModel, isNull);
  });
}
