import 'dart:async';

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

  test('upsertApiModelCache stores shared live model lists by key hash',
      () async {
    await db.upsertApiModelCache(
      baseUrl: ' https://API.openai.com/v1/ ',
      apiKeyHash: 'hash_1',
      textModels: const <String>['gpt-live-b', 'gpt-live-a', 'gpt-live-a'],
      ttsModels: const <String>['tts-1'],
      sttModels: const <String>['whisper-1'],
    );
    await db.upsertApiModelCache(
      baseUrl: 'https://api.openai.com/v1',
      apiKeyHash: 'hash_1',
      textModels: const <String>['gpt-live-c'],
      ttsModels: const <String>[],
      sttModels: const <String>[],
    );

    final rows = await db.watchApiModelCaches().first;
    final cached = AppDatabase.cachedModelListsFor(
      rows,
      baseUrl: 'https://api.openai.com/v1/',
      apiKeyHash: 'hash_1',
    );

    expect(rows, hasLength(1));
    expect(rows.single.baseUrl, equals('https://api.openai.com/v1'));
    expect(cached, isNotNull);
    expect(cached!.textModels, equals(const <String>['gpt-live-c']));
    expect(cached.ttsModels, isEmpty);
    expect(cached.sttModels, isEmpty);
  });

  test('upsertApiModelCache refreshes active model cache watchers', () async {
    final initialSeen = Completer<void>();
    final updateSeen = Completer<List<ApiModelCache>>();
    late final StreamSubscription<List<ApiModelCache>> subscription;
    subscription = db.watchApiModelCaches().listen((rows) {
      if (!initialSeen.isCompleted) {
        expect(rows, isEmpty);
        initialSeen.complete();
        return;
      }
      if (!updateSeen.isCompleted) {
        updateSeen.complete(rows);
      }
    });

    try {
      await initialSeen.future.timeout(const Duration(seconds: 1));
      await db.upsertApiModelCache(
        baseUrl: 'https://api.openai.com/v1',
        apiKeyHash: 'hash_1',
        textModels: const <String>['gpt-live-refresh'],
        ttsModels: const <String>[],
        sttModels: const <String>[],
      );

      final rows = await updateSeen.future.timeout(const Duration(seconds: 1));
      final cached = AppDatabase.cachedModelListsFor(
        rows,
        baseUrl: 'https://api.openai.com/v1',
        apiKeyHash: 'hash_1',
      );

      expect(cached, isNotNull);
      expect(cached!.textModels, equals(const <String>['gpt-live-refresh']));
      expect(cached.ttsModels, isEmpty);
      expect(cached.sttModels, isEmpty);
    } finally {
      await subscription.cancel();
    }
  });
}
