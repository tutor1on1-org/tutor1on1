import 'dart:typed_data';

class BrowserAudioData {
  const BrowserAudioData({
    required this.bytes,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String mimeType;
}
