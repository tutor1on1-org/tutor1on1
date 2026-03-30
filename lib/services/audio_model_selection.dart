class AudioModelSelection {
  static List<String> buildOptions({
    required bool providerSupported,
    required bool modelsLoaded,
    required List<String> loadedModels,
    required Iterable<String> savedModels,
    required String fallback,
  }) {
    if (!providerSupported) {
      return const [];
    }
    if (modelsLoaded) {
      return _normalizeOptions(loadedModels);
    }
    final options = <String>{
      ...savedModels.map((model) => model.trim()).where((model) => model.isNotEmpty),
      if (fallback.trim().isNotEmpty) fallback.trim(),
    }.toList()
      ..sort();
    return options;
  }

  static String resolveModel({
    required bool providerSupported,
    required bool modelsLoaded,
    required List<String> availableOptions,
    required String? selection,
    required bool selectionOverride,
    required String fallback,
  }) {
    if (!providerSupported) {
      return '';
    }
    final current = (selection ?? '').trim();
    if (modelsLoaded) {
      final normalizedOptions = _normalizeOptions(availableOptions);
      if (current.isNotEmpty && normalizedOptions.contains(current)) {
        return current;
      }
      if (selectionOverride && current.isEmpty) {
        return '';
      }
      return normalizedOptions.isNotEmpty ? normalizedOptions.first : '';
    }
    if (selectionOverride) {
      return current;
    }
    if (current.isNotEmpty) {
      return current;
    }
    return fallback.trim();
  }

  static List<String> _normalizeOptions(Iterable<String> values) {
    final normalized = <String>{
      ...values.map((value) => value.trim()).where((value) => value.isNotEmpty),
    }.toList()
      ..sort();
    return normalized;
  }
}
