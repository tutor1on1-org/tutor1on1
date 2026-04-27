class TextModelSelection {
  static List<String> buildOptions({
    required bool modelsLoaded,
    required Iterable<String> loadedModels,
    required Iterable<String> defaultModels,
    required Iterable<String> savedModels,
    required String settingsModel,
  }) {
    if (modelsLoaded) {
      return _normalizeOptions(loadedModels);
    }
    return _normalizeOptions(<String>[
      ...defaultModels,
      ...savedModels,
      if (settingsModel.trim().isNotEmpty) settingsModel.trim(),
    ]);
  }

  static String resolveModel({
    required List<String> availableOptions,
    String? selection,
    String fallback = '',
  }) {
    final options = _normalizeOptions(availableOptions);
    if (options.isEmpty) {
      return '';
    }
    final current = (selection ?? '').trim();
    if (current.isNotEmpty && options.contains(current)) {
      return current;
    }
    final fallbackValue = fallback.trim();
    if (fallbackValue.isNotEmpty && options.contains(fallbackValue)) {
      return fallbackValue;
    }
    return options.first;
  }

  static List<String> _normalizeOptions(Iterable<String> values) {
    return <String>{
      ...values.map((value) => value.trim()).where((value) => value.isNotEmpty),
    }.toList()
      ..sort();
  }
}
