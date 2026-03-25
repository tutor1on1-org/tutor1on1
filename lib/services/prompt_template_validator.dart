class PromptValidationResult {
  PromptValidationResult({
    required this.missingVariables,
    required this.unknownVariables,
  });

  final Set<String> missingVariables;
  final Set<String> unknownVariables;

  bool get isValid => missingVariables.isEmpty && unknownVariables.isEmpty;
}

class PromptTemplateValidator {
  static const Set<String> _structuredPromptNames = {
    'learn',
    'review',
  };

  Set<String> allSupportedVariables() {
    return allowedVariables('__all__');
  }

  PromptValidationResult validate({
    required String promptName,
    required String content,
    bool allowMissingRequired = false,
  }) {
    final required = requiredVariables(promptName);
    final allowed = allowedVariables(promptName);
    final used = _extractVariables(content);
    final missing =
        allowMissingRequired ? <String>{} : required.difference(used);
    final unknown = used.difference(allowed);
    return PromptValidationResult(
      missingVariables: missing,
      unknownVariables: unknown,
    );
  }

  Set<String> requiredVariables(String promptName) {
    switch (promptName) {
      case 'learn':
        return {
          'kp_description',
          'student_input',
          'lesson_content',
        };
      case 'review':
        return {
          'kp_description',
          'student_input',
          'active_review_question_json',
          'target_difficulty',
          'presented_questions',
          'error_book_summary',
        };
      default:
        return {};
    }
  }

  Set<String> allowedVariables(String promptName) {
    final required = requiredVariables(promptName);
    const baseContext = {
      'kp_title',
      'kp_description',
      'student_summary',
      'student_profile',
      'student_preferences',
    };
    const historyContext = {
      'student_input',
      'recent_chat',
      'help_bias',
    };
    const nextGenContext = {
      'lesson_content',
      'error_book_summary',
      'presented_questions',
      'active_review_question_json',
      'target_difficulty',
      'review_correct_total',
      'review_attempt_total',
    };
    if (_structuredPromptNames.contains(promptName)) {
      return {
        ...required,
        ...baseContext,
        ...nextGenContext,
        ...historyContext,
      };
    }
    return {
      ...required,
      ...baseContext,
      ...historyContext,
      ...nextGenContext,
    };
  }

  Set<String> _extractVariables(String content) {
    final matches = RegExp(r'{{\s*([a-zA-Z0-9_]+)\s*}}').allMatches(content);
    return matches
        .map((match) => match.group(1))
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }
}
