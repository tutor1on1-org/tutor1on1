import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/llm/llm_providers.dart';

void main() {
  group('LlmProviders', () {
    test('includes OpenRouter and current provider defaults', () {
      final providers = LlmProviders.defaultProviders();

      final openRouter = LlmProviders.findById(providers, 'openrouter');
      expect(openRouter, isNotNull);
      expect(
        openRouter!.baseUrl,
        equals('https://openrouter.ai/api/v1'),
      );
      expect(
        openRouter.reasoningControlStyle,
        equals(ReasoningControlStyle.openRouterReasoning),
      );
      expect(openRouter.supportsStructuredOutputs, isTrue);
      expect(
        openRouter.extraHeaders['HTTP-Referer'],
        equals('https://www.tutor1on1.org'),
      );
      expect(
        openRouter.extraHeaders['X-OpenRouter-Title'],
        equals('Tutor1on1'),
      );

      final anthropic = LlmProviders.findById(providers, 'anthropic');
      expect(
        anthropic!.models,
        containsAll(<String>[
          'claude-sonnet-4-6',
          'claude-haiku-4-5',
          'claude-opus-4-6',
        ]),
      );
      expect(
        anthropic.models,
        isNot(contains('claude-3-5-sonnet-20240620')),
      );

      final gemini = LlmProviders.findById(providers, 'gemini');
      expect(
        gemini!.models,
        containsAll(<String>[
          'gemini-2.5-pro',
          'gemini-2.5-flash',
          'gemini-2.5-flash-lite',
        ]),
      );
      expect(gemini.supportsStructuredOutputs, isTrue);
      expect(gemini.supportsTts, isFalse);
      expect(gemini.supportsStt, isFalse);

      final openAi = LlmProviders.findById(providers, 'openai');
      expect(openAi!.supportsTts, isTrue);
      expect(openAi.supportsStt, isTrue);

      final siliconflow = LlmProviders.findById(providers, 'siliconflow');
      expect(siliconflow!.supportsTts, isTrue);
      expect(siliconflow.supportsStt, isTrue);

      final grok = LlmProviders.findById(providers, 'grok');
      expect(
        grok!.models,
        containsAll(<String>[
          'grok-4',
          'grok-4-fast-reasoning',
          'grok-4-fast-non-reasoning',
        ]),
      );
      expect(grok.supportsStructuredOutputs, isTrue);
    });
  });
}
