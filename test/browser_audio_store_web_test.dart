@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:tutor1on1/services/browser_audio_store.dart';

const _audioIndexKey = 'tutor1on1.message-audio-index.v1';

void main() {
  test('persists, appends, reads, and removes browser audio', () async {
    final path = BrowserAudioStore.messagePath(
      kind: 'tts-test',
      messageId: DateTime.now().microsecondsSinceEpoch,
    );
    addTearDown(() => BrowserAudioStore.remove(path));

    await BrowserAudioStore.write(
      path: path,
      bytes: const <int>[1, 2, 3],
      mimeType: 'audio/mpeg',
    );
    expect(BrowserAudioStore.contains(path), isTrue);

    await BrowserAudioStore.append(
      path: path,
      bytes: const <int>[4, 5],
      mimeType: 'audio/mpeg',
    );
    final stored = await BrowserAudioStore.read(path);
    expect(stored, isNotNull);
    expect(stored!.bytes, orderedEquals(const <int>[1, 2, 3, 4, 5]));
    expect(stored.mimeType, 'audio/mpeg');

    await BrowserAudioStore.remove(path);
    expect(BrowserAudioStore.contains(path), isFalse);
    expect(await BrowserAudioStore.read(path), isNull);
  });

  test('serializes concurrent audio appends without losing bytes', () async {
    final path = BrowserAudioStore.messagePath(
      kind: 'tts-race-test',
      messageId: DateTime.now().microsecondsSinceEpoch,
    );
    addTearDown(() => BrowserAudioStore.remove(path));
    await BrowserAudioStore.write(
      path: path,
      bytes: const <int>[0],
      mimeType: 'audio/mpeg',
    );

    await Future.wait(
      <int>[1, 2, 3, 4, 5].map(
        (value) => BrowserAudioStore.append(
          path: path,
          bytes: <int>[value],
          mimeType: 'audio/mpeg',
        ),
      ),
    );

    final stored = await BrowserAudioStore.read(path);
    expect(stored, isNotNull);
    expect(stored!.bytes, hasLength(6));
    expect(stored.bytes.toSet(), <int>{0, 1, 2, 3, 4, 5});
  });

  test('observes an audio index update made outside this store', () async {
    final path = BrowserAudioStore.messagePath(
      kind: 'external-index-test',
      messageId: DateTime.now().microsecondsSinceEpoch,
    );
    addTearDown(() => BrowserAudioStore.remove(path));
    final index = _readAudioIndex()..add(path);
    web.window.localStorage.setItem(_audioIndexKey, jsonEncode(index.toList()));

    expect(BrowserAudioStore.contains(path), isTrue);
  });

  test('startup pruning removes orphaned message audio only', () async {
    final retained = BrowserAudioStore.messagePath(kind: 'tts', messageId: 41);
    final orphaned = BrowserAudioStore.messagePath(kind: 'stt', messageId: 42);
    addTearDown(() => BrowserAudioStore.remove(retained));
    addTearDown(() => BrowserAudioStore.remove(orphaned));
    await BrowserAudioStore.write(
      path: retained,
      bytes: const <int>[4, 1],
      mimeType: 'audio/mpeg',
    );
    await BrowserAudioStore.write(
      path: orphaned,
      bytes: const <int>[4, 2],
      mimeType: 'audio/webm',
    );

    await BrowserAudioStore.pruneMessageAudio(const <int>{41});

    expect(await BrowserAudioStore.read(retained), isNotNull);
    expect(await BrowserAudioStore.read(orphaned), isNull);
  });
}

Set<String> _readAudioIndex() {
  final raw = web.window.localStorage.getItem(_audioIndexKey);
  final decoded = raw == null ? null : jsonDecode(raw);
  return decoded is List ? decoded.whereType<String>().toSet() : <String>{};
}
