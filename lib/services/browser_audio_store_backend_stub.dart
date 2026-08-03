import 'browser_audio_data.dart';

class BrowserAudioStoreBackend {
  bool contains(String path) => false;

  Future<void> write({
    required String path,
    required List<int> bytes,
    required String mimeType,
  }) {
    throw UnsupportedError('Browser audio storage requires Flutter Web.');
  }

  Future<void> append({
    required String path,
    required List<int> bytes,
    required String mimeType,
  }) {
    throw UnsupportedError('Browser audio storage requires Flutter Web.');
  }

  Future<BrowserAudioData?> read(String path) async => null;

  Future<void> remove(String path) async {}

  Future<void> removeExcept(Set<String> retainedPaths) async {}

  void revokeObjectUrl(String url) {}
}
