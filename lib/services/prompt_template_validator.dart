class PromptValidationResult {
  PromptValidationResult({
    required this.missingVariables,
    required this.unknownVariables,
  });

  final Set<String> missingVariables;
  final Set<String> unknownVariables;

  bool get isValid =>
      missingVariables.isEmpty && unknownVariables.isEmpty;
}

class PromptTemplateValidator {
  PromptValidationResult validate({
    required String promptName,
    required String content,
    bool allowMissingRequired = false,
  }) {
    final required = requiredVariables(promptName);
    final allowed = allowedVariables(promptName);
    final used = _extractVariables(content);
    final missing = allowMissingRequired ? <String>{} : required.difference(used);
    if (_requiresHistory(promptName) &&
        missing.contains('conversation_history') &&
        used.contains('session_history')) {
      missing.remove('conversation_history');
    }
    final unknown = used.difference(allowed);
    return PromptValidationResult(
      missingVariables: missing,
      unknownVariables: unknown,
    );
  }

  Set<String> requiredVariables(String promptName) {
    switch (promptName) {
      case 'learn':
      case 'review':
        return {
          'subject',
          'kp_title',
          'kp_description',
          'conversation_history',
          'student_input',
          'student_summary',
        };
      case 'summarize':
        return {
          'subject',
          'kp_title',
          'kp_description',
          'conversation_history',
          'student_summary',
        };
      default:
        return {};
    }
  }

  Set<String> allowedVariables(String promptName) {
    final required = requiredVariables(promptName);
    return {
      ...required,
      'course_version_id',
      'kp_key',
      'session_history',
    };
  }

  bool _requiresHistory(String promptName) {
    return promptName == 'learn' ||
        promptName == 'review' ||
        promptName == 'summarize';
  }

  Set<String> _extractVariables(String content) {
    final matches = RegExp(r'{{\s*([a-zA-Z0-9_]+)\s*}}')
        .allMatches(content);
    return matches
        .map((match) => match.group(1))
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }
}
