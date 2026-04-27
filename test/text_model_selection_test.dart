import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/services/text_model_selection.dart';

void main() {
  group('TextModelSelection', () {
    test('uses authoritative loaded models after a successful model load', () {
      final options = TextModelSelection.buildOptions(
        modelsLoaded: true,
        loadedModels: const <String>[
          'deepseek-ai/DeepSeek-V4-Flash',
        ],
        defaultModels: const <String>[
          'deepseek-ai/DeepSeek-V3.2',
        ],
        savedModels: const <String>[
          'gpt-5.4',
        ],
        settingsModel: 'gpt-5.4',
      );

      expect(options, equals(const <String>['deepseek-ai/DeepSeek-V4-Flash']));
    });

    test('keeps defaults and saved models before live model load', () {
      final options = TextModelSelection.buildOptions(
        modelsLoaded: false,
        loadedModels: const <String>[
          'deepseek-ai/DeepSeek-V4-Flash',
        ],
        defaultModels: const <String>[
          'deepseek-ai/DeepSeek-V3.2',
        ],
        savedModels: const <String>[
          'gpt-5.4',
        ],
        settingsModel: '',
      );

      expect(
        options,
        equals(
          const <String>[
            'deepseek-ai/DeepSeek-V3.2',
            'gpt-5.4',
          ],
        ),
      );
    });

    test('resolves stale selection to first authoritative option', () {
      final resolved = TextModelSelection.resolveModel(
        availableOptions: const <String>[
          'deepseek-ai/DeepSeek-V4-Flash',
        ],
        selection: 'gpt-5.4',
      );

      expect(resolved, equals('deepseek-ai/DeepSeek-V4-Flash'));
    });
  });
}
