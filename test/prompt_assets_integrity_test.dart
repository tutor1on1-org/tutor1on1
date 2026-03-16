import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/llm/prompt_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const requiredPromptNames = <String>[
    'learn',
    'review',
  ];

  for (final promptName in requiredPromptNames) {
    test('bundled prompt "$promptName" is readable UTF-8 text', () async {
      final repository = PromptRepository();
      final content = await repository.loadBundledSystemPrompt(promptName);
      expect(content.trim(), isNotEmpty);
      expect(content, isNot(contains('%TSD-Header-###%')));
      expect(content, contains('You are a one-on-one teacher.'));
    });
  }
}
