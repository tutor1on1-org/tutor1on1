import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/services/audio_model_selection.dart';

void main() {
  group('AudioModelSelection', () {
    test('returns no options and clears selections for unsupported providers', () {
      final options = AudioModelSelection.buildOptions(
        providerSupported: false,
        modelsLoaded: false,
        loadedModels: const <String>['gpt-4o-mini-tts'],
        savedModels: const <String>['gpt-4o-mini-tts'],
        fallback: 'gpt-4o-mini-tts',
      );

      expect(options, isEmpty);
      expect(
        AudioModelSelection.resolveModel(
          providerSupported: false,
          modelsLoaded: true,
          availableOptions: options,
          selection: 'gpt-4o-mini-tts',
          selectionOverride: false,
          fallback: 'gpt-4o-mini-tts',
        ),
        isEmpty,
      );
    });

    test('successful model load clears stale saved audio models', () {
      final options = AudioModelSelection.buildOptions(
        providerSupported: true,
        modelsLoaded: true,
        loadedModels: const <String>[],
        savedModels: const <String>['gpt-4o-mini-tts'],
        fallback: 'gpt-4o-mini-tts',
      );

      expect(options, isEmpty);
      expect(
        AudioModelSelection.resolveModel(
          providerSupported: true,
          modelsLoaded: true,
          availableOptions: options,
          selection: 'gpt-4o-mini-tts',
          selectionOverride: false,
          fallback: 'gpt-4o-mini-tts',
        ),
        isEmpty,
      );
    });

    test('keeps supported pre-test fallback before authoritative model load', () {
      final options = AudioModelSelection.buildOptions(
        providerSupported: true,
        modelsLoaded: false,
        loadedModels: const <String>[],
        savedModels: const <String>['gpt-4o-mini-tts'],
        fallback: 'gpt-4o-mini-tts',
      );

      expect(options, equals(const <String>['gpt-4o-mini-tts']));
      expect(
        AudioModelSelection.resolveModel(
          providerSupported: true,
          modelsLoaded: false,
          availableOptions: options,
          selection: null,
          selectionOverride: false,
          fallback: 'gpt-4o-mini-tts',
        ),
        equals('gpt-4o-mini-tts'),
      );
    });
  });
}
