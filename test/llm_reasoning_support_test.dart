import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/llm/llm_models.dart';
import 'package:tutor1on1/llm/llm_providers.dart';
import 'package:tutor1on1/llm/llm_reasoning_support.dart';

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

      const siliconFlow = LlmProvider(
        id: 'siliconflow',
        label: 'SiliconFlow',
        baseUrl: 'https://api.siliconflow.cn/v1',
        models: <String>['deepseek-ai/DeepSeek-V3.2'],
        maxTokensParam: MaxTokensParam.maxTokens,
        reasoningControlStyle: ReasoningControlStyle.siliconFlowThinkingBudget,
      );
      final siliconFlowBody = <String, dynamic>{};
      LlmReasoningSupport.applyRequestFields(
        bodyMap: siliconFlowBody,
        provider: siliconFlow,
        model: 'deepseek-ai/DeepSeek-V3.2',
        reasoningEffort: ReasoningEffort.medium,
        maxTokens: 8000,
      );
      expect(siliconFlowBody['enable_thinking'], isTrue);
      expect(siliconFlowBody['thinking_budget'], equals(4096));

      final siliconFlowDisabledBody = <String, dynamic>{};
      LlmReasoningSupport.applyRequestFields(
        bodyMap: siliconFlowDisabledBody,
        provider: siliconFlow,
        model: 'deepseek-ai/DeepSeek-V3.2',
        reasoningEffort: ReasoningEffort.none,
        maxTokens: 8000,
      );
      expect(siliconFlowDisabledBody['enable_thinking'], isFalse);
      expect(siliconFlowDisabledBody.containsKey('thinking_budget'), isFalse);

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

    test('preserves whitespace-only streamed JSON fragments', () {
      const provider = LlmProvider(
        id: 'openai',
        label: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        models: <String>['gpt-5.4'],
        maxTokensParam: MaxTokensParam.auto,
        reasoningControlStyle: ReasoningControlStyle.openAiEffort,
      );
      final payload = <String, dynamic>{
        'choices': <Map<String, dynamic>>[
          <String, dynamic>{
            'delta': <String, dynamic>{
              'content': ' ',
            },
          },
        ],
      };

      final extracted = LlmReasoningSupport.extractResponse(
        payload: payload,
        provider: provider,
      );

      expect(extracted.responseText, equals(' '));
    });

    test('rejoins split JSON string fragments without inserting spaces', () {
      const provider = LlmProvider(
        id: 'openai',
        label: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        models: <String>['gpt-5.4'],
        maxTokensParam: MaxTokensParam.auto,
        reasoningControlStyle: ReasoningControlStyle.openAiEffort,
      );
      final payload = <String, dynamic>{
        'choices': <Map<String, dynamic>>[
          <String, dynamic>{
            'message': <String, dynamic>{
              'content': <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'text',
                  'text': '{"teacher_message":"Gal',
                },
                <String, dynamic>{
                  'type': 'text',
                  'text': 'ilean relat',
                },
                <String, dynamic>{
                  'type': 'text',
                  'text':
                      'ivity says the laws of mechanics are the same in every inert',
                },
                <String, dynamic>{
                  'type': 'text',
                  'text':
                      'ial frame. An inertial frame is one where a free object moves at constant velocity in a straight line unless a force acts."}',
                },
              ],
            },
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
          '{"teacher_message":"Galilean relativity says the laws of mechanics are the same in every inertial frame. An inertial frame is one where a free object moves at constant velocity in a straight line unless a force acts."}',
        ),
      );
    });

    test('streaming delta preserves split words inside JSON string values', () {
      final buffer = StringBuffer('{"teacher_message":"Gal');

      final delta = LlmReasoningSupport.appendJsonAwareFragmentAndReturnDelta(
        buffer,
        'ilean',
      );

      expect(delta, equals('ilean'));
      expect(buffer.toString(), equals('{"teacher_message":"Galilean'));
    });

    test('streaming delta preserves spaces around number fragments', () {
      final buffer = StringBuffer('{"teacher_message":"Lesson');

      final firstDelta =
          LlmReasoningSupport.appendJsonAwareFragmentAndReturnDelta(
        buffer,
        ' ',
      );
      final secondDelta =
          LlmReasoningSupport.appendJsonAwareFragmentAndReturnDelta(
        buffer,
        '2',
      );
      final thirdDelta =
          LlmReasoningSupport.appendJsonAwareFragmentAndReturnDelta(
        buffer,
        ' examples."}',
      );

      expect(firstDelta, equals(' '));
      expect(secondDelta, equals('2'));
      expect(thirdDelta, equals(' examples."}'));
      expect(
        buffer.toString(),
        equals('{"teacher_message":"Lesson 2 examples."}'),
      );
    });

    test('streaming delta collapses duplicated seam spaces inside JSON values',
        () {
      final buffer = StringBuffer('{"teacher_message":"Newton ');

      final delta = LlmReasoningSupport.appendJsonAwareFragmentAndReturnDelta(
        buffer,
        ' laws are consistent."}',
      );

      expect(delta, equals('laws are consistent."}'));
      expect(
        buffer.toString(),
        equals('{"teacher_message":"Newton laws are consistent."}'),
      );
    });

    test('streaming join does not insert spaces inside JSON keys', () {
      final buffer = StringBuffer('{"mist');

      final delta = LlmReasoningSupport.appendJsonAwareFragmentAndReturnDelta(
        buffer,
        'akes":[]}',
      );

      expect(delta, equals('akes":[]}'));
      expect(buffer.toString(), equals('{"mistakes":[]}'));
    });

    test('preserves leading spaces in streamed reasoning fragments', () {
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
            'delta': <String, dynamic>{
              'reasoning_content': ' next step',
            },
          },
        ],
      };

      final extracted = LlmReasoningSupport.extractResponse(
        payload: payload,
        provider: provider,
      );

      expect(extracted.reasoningText, equals(' next step'));
    });

    test('streamed reasoning collapses duplicated seam spaces', () {
      final buffer = StringBuffer('step ');

      LlmReasoningSupport.appendReasoningFragment(buffer, ' next');

      expect(buffer.toString(), equals('step next'));
    });

    test('streamed reasoning inserts a missing word boundary space', () {
      final buffer = StringBuffer('step');

      LlmReasoningSupport.appendReasoningFragment(buffer, 'next');

      expect(buffer.toString(), equals('step next'));
    });

    test('reasoning log keeps requested effort even without returned text', () {
      const provider = LlmProvider(
        id: 'openai',
        label: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        models: <String>['gpt-5.4'],
        maxTokensParam: MaxTokensParam.auto,
        reasoningControlStyle: ReasoningControlStyle.openAiEffort,
      );

      final encoded = LlmReasoningSupport.encodeReasoningLog(
        provider: provider,
        model: 'gpt-5.4',
        reasoningEffort: ReasoningEffort.medium,
      );

      expect(encoded, isNotNull);
      final decoded = jsonDecode(encoded!) as Map<String, dynamic>;
      expect(decoded['reasoning_effort'], equals(ReasoningEffort.medium));
      expect(decoded['reasoning_text'], isNull);
      expect(decoded['reasoning_tokens'], isNull);
    });

    test('reasoning log preserves reasoning text verbatim', () {
      const provider = LlmProvider(
        id: 'openai',
        label: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        models: <String>['gpt-5.4'],
        maxTokensParam: MaxTokensParam.auto,
        reasoningControlStyle: ReasoningControlStyle.openAiEffort,
      );

      final encoded = LlmReasoningSupport.encodeReasoningLog(
        provider: provider,
        model: 'gpt-5.4',
        reasoningEffort: ReasoningEffort.medium,
        reasoningText: ' Keep exact spacing. ',
      );

      expect(encoded, isNotNull);
      final decoded = jsonDecode(encoded!) as Map<String, dynamic>;
      expect(decoded['reasoning_text'], equals(' Keep exact spacing. '));
    });
  });
}
