import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/llm/llm_models.dart';
import 'package:family_teacher/llm/llm_providers.dart';
import 'package:family_teacher/llm/llm_reasoning_support.dart';

void main() {
  group('LlmReasoningSupport', () {
    test('extracts DeepSeek reasoning_content separately from final JSON', () {
      const provider = LlmProvider(
        id: 'deepseek',
        label: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com/v1',
        models: <String>['deepseek-reasoner'],
        maxTokensParam: MaxTokensParam.maxTokens,
        reasoningControlStyle: ReasoningControlStyle.deepSeekThinking,
      );
      final payload = <String, dynamic>{
        'choices': <Map<String, dynamic>>[
          <String, dynamic>{
            'message': <String, dynamic>{
              'reasoning_content': 'Work through the algebra carefully.',
              'content': jsonEncode(<String, Object?>{
                'teacher_message': 'x = 5',
              }),
            },
          },
        ],
        'usage': <String, dynamic>{
          'reasoning_tokens': 77,
        },
      };

      final extracted = LlmReasoningSupport.extractResponse(
        payload: payload,
        provider: provider,
      );

      expect(
        extracted.responseText,
        equals(jsonEncode(<String, Object?>{'teacher_message': 'x = 5'})),
      );
      expect(
        extracted.reasoningText,
        equals('Work through the algebra carefully.'),
      );
      expect(extracted.reasoningTokens, equals(77));
    });

    test('extracts Anthropic thinking blocks separately from final text', () {
      const provider = LlmProvider(
        id: 'anthropic',
        label: 'Anthropic',
        baseUrl: 'https://api.anthropic.com/v1',
        models: <String>['claude-3-5-sonnet-20240620'],
        maxTokensParam: MaxTokensParam.maxTokens,
        apiFormat: LlmApiFormat.anthropicMessages,
        chatPath: '/messages',
        reasoningControlStyle: ReasoningControlStyle.anthropicThinking,
      );
      final payload = <String, dynamic>{
        'content': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'thinking',
            'thinking': 'Compare the student answer against the rubric.',
          },
          <String, dynamic>{
            'type': 'text',
            'text': jsonEncode(<String, Object?>{
              'teacher_message': 'Correct and concise.',
            }),
          },
        ],
      };

      final extracted = LlmReasoningSupport.extractResponse(
        payload: payload,
        provider: provider,
      );

      expect(
        extracted.responseText,
        equals(
          jsonEncode(<String, Object?>{
            'teacher_message': 'Correct and concise.',
          }),
        ),
      );
      expect(
        extracted.reasoningText,
        equals('Compare the student answer against the rubric.'),
      );
    });

    test('applies provider-specific reasoning request fields', () {
      const openAi = LlmProvider(
        id: 'openai',
        label: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        models: <String>['gpt-5.2-2025-12-11'],
        maxTokensParam: MaxTokensParam.auto,
        reasoningControlStyle: ReasoningControlStyle.openAiEffort,
      );
      final openAiBody = <String, dynamic>{};
      LlmReasoningSupport.applyRequestFields(
        bodyMap: openAiBody,
        provider: openAi,
        model: 'gpt-5.2-2025-12-11',
        reasoningEffort: ReasoningEffort.high,
        maxTokens: 8000,
      );
      expect(openAiBody['reasoning_effort'], equals(ReasoningEffort.high));

      const deepSeek = LlmProvider(
        id: 'deepseek',
        label: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com/v1',
        models: <String>['deepseek-chat'],
        maxTokensParam: MaxTokensParam.maxTokens,
        reasoningControlStyle: ReasoningControlStyle.deepSeekThinking,
      );
      final deepSeekBody = <String, dynamic>{};
      LlmReasoningSupport.applyRequestFields(
        bodyMap: deepSeekBody,
        provider: deepSeek,
        model: 'deepseek-chat',
        reasoningEffort: ReasoningEffort.none,
        maxTokens: 8000,
      );
      expect(
        deepSeekBody['thinking'],
        equals(<String, dynamic>{'type': 'disabled'}),
      );
    });
  });
}
