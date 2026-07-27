import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/llm/llm_providers.dart';
import 'package:tutor1on1/services/model_list_service.dart';

void main() {
  group('ModelListService', () {
    test('filters Gemini TTS-only models out of text models', () {
      final provider =
          LlmProviders.findById(LlmProviders.defaultProviders(), 'gemini')!;

      final lists = ModelListService.splitModels(
        provider: provider,
        models: const <ApiModelInfo>[
          ApiModelInfo(id: 'gemini-2.5-flash'),
          ApiModelInfo(id: 'gemini-2.5-flash-preview-tts'),
        ],
      );

      expect(lists.textModels, equals(const <String>['gemini-2.5-flash']));
      expect(lists.ttsModels, isEmpty);
      expect(lists.sttModels, isEmpty);
    });

    test('classifies OpenAI audio models into dedicated buckets', () {
      final provider =
          LlmProviders.findById(LlmProviders.defaultProviders(), 'openai')!;

      final lists = ModelListService.splitModels(
        provider: provider,
        models: const <ApiModelInfo>[
          ApiModelInfo(id: 'gpt-4.1'),
          ApiModelInfo(id: 'gpt-4o-mini-tts'),
          ApiModelInfo(id: 'gpt-4o-mini-transcribe'),
        ],
      );

      expect(lists.textModels, equals(const <String>['gpt-4.1']));
      expect(lists.ttsModels, equals(const <String>['gpt-4o-mini-tts']));
      expect(
        lists.sttModels,
        equals(const <String>['gpt-4o-mini-transcribe']),
      );
    });

    test('keeps SiliconFlow DeepSeek V4 models in text models', () {
      final provider = LlmProviders.findById(
        LlmProviders.defaultProviders(),
        'siliconflow',
      )!;

      final lists = ModelListService.splitModels(
        provider: provider,
        models: const <ApiModelInfo>[
          ApiModelInfo(id: 'deepseek-ai/DeepSeek-V4-Flash'),
          ApiModelInfo(id: 'FunAudioLLM/SenseVoiceSmall'),
          ApiModelInfo(id: 'FunAudioLLM/CosyVoice2-0.5B'),
        ],
      );

      expect(
        lists.textModels,
        equals(const <String>['deepseek-ai/DeepSeek-V4-Flash']),
      );
      expect(lists.sttModels,
          equals(const <String>['FunAudioLLM/SenseVoiceSmall']));
      expect(lists.ttsModels,
          equals(const <String>['FunAudioLLM/CosyVoice2-0.5B']));
    });
  });
}
