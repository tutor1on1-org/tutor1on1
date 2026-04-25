import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/llm/prompt_repository.dart';
import 'package:tutor1on1/services/prompt_template_validator.dart';

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

  test(
    'bundled review prompt includes full conversation history context',
    () async {
      final repository = PromptRepository();
      final content = await repository.loadBundledSystemPrompt('review');
      expect(content, contains('{{conversation_history}}'));
      expect(content, contains('Use conversation_history'));
    },
  );

  test('bundled learn prompt is plain text and uses compact context', () async {
    final repository = PromptRepository();
    final content = await repository.loadBundledSystemPrompt('learn');
    expect(content, contains('{{conversation_history}}'));
    expect(content, contains('{{student_context}}'));
    expect(content, contains('Output only the student-visible text.'));
    expect(content, isNot(contains('Return JSON only')));
  });

  for (final promptName in requiredPromptNames) {
    test('bundled prompt "$promptName" only uses supported variables',
        () async {
      final repository = PromptRepository();
      final validator = PromptTemplateValidator();
      final content = await repository.loadBundledSystemPrompt(promptName);
      final result = validator.validate(
        promptName: promptName,
        content: content,
      );
      expect(
        result.isValid,
        isTrue,
        reason:
            'missing=${result.missingVariables}; unknown=${result.unknownVariables}; invalid=${result.invalidVariables}',
      );
    });
  }
}
