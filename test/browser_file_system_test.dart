@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:tutor1on1/services/file_system.dart';
import 'package:web/web.dart' as web;

const _indexKey = 'tutor1on1.vfs.index.v1';
const _cacheName = 'tutor1on1-vfs-v1';

void main() {
  test('browser file store persists bytes and directory metadata', () async {
    final root = Directory(
      '/tutor1on1/test/vfs_${DateTime.now().microsecondsSinceEpoch}',
    );
    await root.create(recursive: true);
    final source = File('${root.path}/course/contents.txt');
    await source.writeAsString('1 Numbers', encoding: utf8);
    await source.writeAsString('\n1.1 Counting', mode: FileMode.append);

    expect(source.existsSync(), isTrue);
    expect(await source.readAsString(), '1 Numbers\n1.1 Counting');
    expect(source.lengthSync(), greaterThan(0));

    final copy = await source.copy('${root.path}/copy/contents.txt');
    expect(await copy.readAsString(), '1 Numbers\n1.1 Counting');
    expect(
      root.listSync(recursive: true).whereType<File>().map((file) => file.path),
      containsAll(<String>[source.path, copy.path]),
    );

    await root.delete(recursive: true);
    expect(root.existsSync(), isFalse);
  });

  test('merges the latest index and keeps cache content in sync', () async {
    final root = Directory(
      '/tutor1on1/test/vfs_index_${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    await root.create(recursive: true);
    final first = File('${root.path}/first.txt');
    await first.writeAsString('first');
    expect(await first.readAsString(), 'first');

    final cache = await web.window.caches.open(_cacheName).toDart;
    await cache
        .put(
          _vfsRequest(first.path),
          web.Response('other'.toJS),
        )
        .toDart;
    expect(await first.readAsString(), 'other');

    final externalDirectory = '${root.path}/external';
    final externallyUpdated = _readVfsIndex()
      ..[externalDirectory] = <String, Object?>{
        'kind': 'directory',
        'length': 0,
      };
    web.window.localStorage.setItem(_indexKey, jsonEncode(externallyUpdated));
    expect(Directory(externalDirectory).existsSync(), isTrue);

    final second = File('${root.path}/second.txt');
    await second.writeAsString('second');

    final afterWrite = _readVfsIndex();
    expect(afterWrite, contains(externalDirectory));
    expect(afterWrite, contains(second.path));
    expect(await cache.match(_vfsRequest(second.path)).toDart, isNotNull);

    await second.delete();
    expect(await cache.match(_vfsRequest(second.path)).toDart, isNull);
    expect(_readVfsIndex(), isNot(contains(second.path)));
  });
}

Map<String, dynamic> _readVfsIndex() {
  final raw = web.window.localStorage.getItem(_indexKey);
  final decoded = raw == null ? null : jsonDecode(raw);
  return decoded is Map
      ? Map<String, dynamic>.from(decoded)
      : <String, dynamic>{};
}

web.Request _vfsRequest(String path) {
  final encoded = base64Url.encode(utf8.encode(path));
  final url = Uri.base.resolve('__tutor1on1_vfs__/$encoded').toString();
  return web.Request(url.toJS);
}
