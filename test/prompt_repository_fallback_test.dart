import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/llm/prompt_repository.dart';

class _AlwaysFailAssetBundle extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    throw StateError('Unable to load asset: "$key".');
  }

  @override
  Future<ByteData> load(String key) async {
    throw StateError('Unable to load asset: "$key".');
  }
}

void main() {
  test('uses emergency fallback prompts when bundled assets are unavailable',
      () async {
    final repository = PromptRepository(assetBundle: _AlwaysFailAssetBundle());
    const promptNames = <String>[
      'learn',
      'review',
    ];

    for (final promptName in promptNames) {
      final content = await repository.loadBundledSystemPrompt(promptName);
      expect(content.trim(), isNotEmpty);
      expect(content, contains('You are a one-on-one teacher.'));
    }
  });

  test('throws for unknown prompt names when assets are unavailable', () async {
    final repository = PromptRepository(assetBundle: _AlwaysFailAssetBundle());
    await expectLater(
      () => repository.loadBundledSystemPrompt('unknown_prompt'),
      throwsA(isA<StateError>()),
    );
  });
}
