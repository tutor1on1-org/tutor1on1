import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/llm/llm_providers.dart';
import 'package:tutor1on1/llm/llm_models.dart';

void main() {
  group('LlmProviders', () {
    test('agent_tutor exposes only the server Codex provider', () {
      final providers = LlmProviders.defaultProviders(
        appLabel: 'agent_tutor',
      );

      expect(providers, hasLength(1));
      final provider = providers.single;
      expect(provider.id, equals('agent-tutor'));
      expect(provider.label, equals('Agent Tutor'));
      expect(provider.authMode, equals(LlmAuthMode.tutorSession));
      expect(provider.apiFormat, equals(LlmApiFormat.agentTutorExec));
      expect(
        provider.models,
        equals(<String>[
          'gpt-5.6-luna',
          'gpt-5.6-sol',
          'gpt-5.6-terra',
        ]),
      );
      expect(provider.supportsTts, isFalse);
      expect(provider.supportsStt, isFalse);
      expect(
        provider.reasoningEfforts,
        equals(<String>[
          ReasoningEffort.low,
          ReasoningEffort.medium,
          ReasoningEffort.high,
          ReasoningEffort.xhigh,
          ReasoningEffort.max,
        ]),
      );
    });

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
      expect(
        anthropic.extraHeaders['anthropic-dangerous-direct-browser-access'],
        equals('true'),
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

      final openAiCodex = LlmProviders.findById(providers, 'openai-codex');
      expect(openAiCodex, isNotNull);
      expect(
        openAiCodex!.baseUrl,
        equals('https://chatgpt.com/backend-api'),
      );
      expect(openAiCodex.authMode, equals(LlmAuthMode.openAiCodexOAuth));
      expect(
        openAiCodex.apiFormat,
        equals(LlmApiFormat.openAiCodexResponses),
      );
      expect(openAiCodex.models, contains('gpt-5.5'));

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

      final deepSeek = LlmProviders.findById(providers, 'deepseek');
      expect(deepSeek!.baseUrl, equals('https://api.deepseek.com'));
    });
  });
}
