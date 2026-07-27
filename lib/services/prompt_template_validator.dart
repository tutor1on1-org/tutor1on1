import 'prompt_variable_registry.dart';

class PromptValidationResult {
  PromptValidationResult({
    required this.missingVariables,
    required this.unknownVariables,
    required this.invalidVariables,
  });

  final Set<String> missingVariables;
  final Set<String> unknownVariables;
  final Set<String> invalidVariables;

  bool get isValid =>
      missingVariables.isEmpty &&
      unknownVariables.isEmpty &&
      invalidVariables.isEmpty;
}

class PromptTemplateValidator {
  Set<String> allSupportedVariables() {
    return PromptVariableRegistry.allSupportedVariables();
  }

  PromptValidationResult validate({
    required String promptName,
    required String content,
    bool allowMissingRequired = false,
  }) {
    final required = requiredVariables(promptName);
    final allowed = allowedVariables(promptName);
    final extraction = _extractVariables(content);
    final used = extraction.validVariables;
    final missing =
        allowMissingRequired ? <String>{} : required.difference(used);
    final unknown = used.difference(allowed);
    return PromptValidationResult(
      missingVariables: missing,
      unknownVariables: unknown,
      invalidVariables: extraction.invalidVariables,
    );
  }

  Set<String> requiredVariables(String promptName) {
    return PromptVariableRegistry.requiredVariables(promptName);
  }

  Set<String> allowedVariables(String promptName) {
    return PromptVariableRegistry.allowedVariables(promptName);
  }

  _VariableExtraction _extractVariables(String content) {
    final valid = <String>{};
    final invalid = <String>{};
    final matches = RegExp(r'{{(.*?)}}').allMatches(content);
    for (final match in matches) {
      final raw = (match.group(1) ?? '').trim();
      if (raw.isEmpty) {
        invalid.add('{{}}');
        continue;
      }
      if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(raw)) {
        invalid.add(raw);
        continue;
      }
      valid.add(raw);
    }
    return _VariableExtraction(
      validVariables: valid,
      invalidVariables: invalid,
    );
  }
}

class _VariableExtraction {
  const _VariableExtraction({
    required this.validVariables,
    required this.invalidVariables,
  });

  final Set<String> validVariables;
  final Set<String> invalidVariables;
}
