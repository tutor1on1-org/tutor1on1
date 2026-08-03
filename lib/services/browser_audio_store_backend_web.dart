import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'browser_audio_data.dart';
import 'browser_exclusive_lock.dart';

class BrowserAudioStoreBackend {
  static const _cacheName = 'tutor1on1-message-audio-v1';
  static const _indexKey = 'tutor1on1.message-audio-index.v1';
  static const _lockName = 'tutor1on1-message-audio-store-v1';

  bool contains(String path) {
    if (path.trim().isEmpty) {
      return false;
    }
    return _readIndex().contains(path);
  }

  Future<void> write({
    required String path,
    required List<int> bytes,
    required String mimeType,
  }) =>
      _mutate(path, bytes, mimeType: mimeType, append: false);

  Future<void> append({
    required String path,
    required List<int> bytes,
    required String mimeType,
  }) =>
      _mutate(path, bytes, mimeType: mimeType, append: true);

  Future<BrowserAudioData?> read(String path) async {
    if (path.trim().isEmpty) {
      return null;
    }
    return runWithBrowserExclusiveLock<BrowserAudioData?>(_lockName, () async {
      final cache = await web.window.caches.open(_cacheName).toDart;
      final response = await cache.match(_cacheUrl(path).toJS).toDart;
      if (response != null) {
        return _readResponse(path, response);
      }
      final index = _readIndex()..remove(path);
      _writeIndex(index);
      return null;
    });
  }

  Future<void> remove(String path) async {
    if (path.trim().isEmpty) {
      return;
    }
    await runWithBrowserExclusiveLock<void>(_lockName, () async {
      final cache = await web.window.caches.open(_cacheName).toDart;
      await cache.delete(_cacheUrl(path).toJS).toDart;
      final index = _readIndex()..remove(path);
      _writeIndex(index);
    });
  }

  Future<void> removeExcept(Set<String> retainedPaths) async {
    await runWithBrowserExclusiveLock<void>(_lockName, () async {
      final cache = await web.window.caches.open(_cacheName).toDart;
      final index = _readIndex();
      final stalePaths = index.difference(retainedPaths);
      for (final path in stalePaths) {
        await cache.delete(_cacheUrl(path).toJS).toDart;
      }
      if (stalePaths.isNotEmpty) {
        _writeIndex(index..removeAll(stalePaths));
      }
    });
  }

  void revokeObjectUrl(String url) {
    if (url.startsWith('blob:')) {
      web.URL.revokeObjectURL(url);
    }
  }

  String _cacheUrl(String path) {
    final encoded = base64Url.encode(utf8.encode(path)).replaceAll('=', '');
    return '${web.window.location.origin}/__tutor1on1_audio__/$encoded';
  }

  Future<void> _mutate(
    String path,
    List<int> bytes, {
    required String mimeType,
    required bool append,
  }) async {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'must not be empty');
    }
    await runWithBrowserExclusiveLock<void>(_lockName, () async {
      final cache = await web.window.caches.open(_cacheName).toDart;
      final current =
          append ? await cache.match(_cacheUrl(path).toJS).toDart : null;
      final existing = current == null
          ? Uint8List(0)
          : (await current.arrayBuffer().toDart).toDart.asUint8List();
      final data = Uint8List.fromList(<int>[...existing, ...bytes]);
      final blob = web.Blob(
        <JSUint8Array>[data.toJS].toJS,
        web.BlobPropertyBag(type: mimeType),
      );
      await cache.put(_cacheUrl(path).toJS, web.Response(blob)).toDart;
      final index = _readIndex()..add(path);
      _writeIndex(index);
    });
  }

  Future<BrowserAudioData> _readResponse(
    String path,
    web.Response response,
  ) async {
    final buffer = await response.arrayBuffer().toDart;
    final bytes = Uint8List.fromList(buffer.toDart.asUint8List());
    final mimeType = response.headers.get('content-type')?.split(';').first ??
        _defaultMimeType(path);
    return BrowserAudioData(bytes: bytes, mimeType: mimeType);
  }

  Set<String> _readIndex() {
    final raw = web.window.localStorage.getItem(_indexKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <String>{};
      }
      return decoded.whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  void _writeIndex(Set<String> index) {
    final sorted = index.toList()..sort();
    web.window.localStorage.setItem(_indexKey, jsonEncode(sorted));
  }

  String _defaultMimeType(String path) {
    return path.contains('stt') ? 'audio/webm' : 'audio/mpeg';
  }
}
