import 'dart:convert';

import 'package:crypto/crypto.dart';

class LlmHash {
  static String compute({
    required String baseUrl,
    required String model,
    required String promptName,
    required String renderedPrompt,
    String? reasoningEffort,
    String? conversationDigest,
  }) {
    final buffer = StringBuffer()
      ..write(baseUrl)
      ..write('|')
      ..write(model)
      ..write('|')
      ..write(reasoningEffort ?? '')
      ..write('|')
      ..write(promptName)
      ..write('|')
      ..write(renderedPrompt)
      ..write('|')
      ..write(conversationDigest ?? '');
    return sha256.convert(utf8.encode(buffer.toString())).toString();
  }
}
