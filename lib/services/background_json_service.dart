import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;

class BackgroundJsonService {
  const BackgroundJsonService();

  static const int _decodeOffloadThresholdBytes = 32 * 1024;

  Future<Object?> decode(String text) async {
    if (kIsWeb || text.length < _decodeOffloadThresholdBytes) {
      return jsonDecode(text);
    }
    return Isolate.run<Object?>(() => jsonDecode(text));
  }
}
