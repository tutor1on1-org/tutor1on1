import 'dart:convert';

import 'browser_audio_data.dart';
import 'browser_audio_store_backend_stub.dart'
    if (dart.library.js_interop) 'browser_audio_store_backend_web.dart'
    as backend;

export 'browser_audio_data.dart';

class BrowserAudioStore {
  BrowserAudioStore._();

  static final backend.BrowserAudioStoreBackend _backend =
      backend.BrowserAudioStoreBackend();

  static String messagePath({
    required String kind,
    required int messageId,
  }) {
    return 'browser-audio://$kind/$messageId';
  }

  static bool contains(String path) => _backend.contains(path);

  static Future<void> write({
    required String path,
    required List<int> bytes,
    required String mimeType,
  }) {
    return _backend.write(path: path, bytes: bytes, mimeType: mimeType);
  }

  static Future<void> append({
    required String path,
    required List<int> bytes,
    required String mimeType,
  }) =>
      _backend.append(path: path, bytes: bytes, mimeType: mimeType);

  static Future<BrowserAudioData?> read(String path) => _backend.read(path);

  static Future<void> remove(String path) => _backend.remove(path);

  static Future<void> pruneMessageAudio(Set<int> liveMessageIds) {
    final retainedPaths = <String>{
      'browser-audio://tts/last',
      for (final messageId in liveMessageIds) ...{
        messagePath(kind: 'tts', messageId: messageId),
        messagePath(kind: 'stt', messageId: messageId),
      },
    };
    return _backend.removeExcept(retainedPaths);
  }

  static void revokeObjectUrl(String url) => _backend.revokeObjectUrl(url);

  static String dataUrl(BrowserAudioData audio) {
    return 'data:${audio.mimeType};base64,${base64Encode(audio.bytes)}';
  }
}
