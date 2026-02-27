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
    'learn_init',
    'learn_cont',
    'review_init',
    'review_cont',
    'summary',
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
      case 'learn_init':
        return {
          'lesson_content',
          'types',
          'error_book_summary',
          'practice_history_summary',
        };
      case 'review_init':
        return {
          'lesson_content',
          'types',
          'error_book_summary',
          'practice_history_summary',
          'presented_questions',
        };
      case 'learn_cont':
      case 'review_cont':
        return {
          'recent_dialogue',
          'prev_json',
        };
      case 'summary':
        return {
          'practice_history_summary',
          'error_book_summary',
          'last_evidence',
          'current_mastery_level',
        };
      default:
        return {};
    }
  }

  Set<String> allowedVariables(String promptName) {
    final required = requiredVariables(promptName);
    const baseContext = {
      'subject',
      'course_version_id',
      'kp_key',
      'kp_title',
      'kp_description',
      'student_summary',
      'student_profile',
      'student_preferences',
    };
    const historyContext = {
      'conversation_history',
      'session_history',
      'student_input',
      'student_intent',
    };
    const nextGenContext = {
      'lesson_content',
      'types',
      'error_book_summary',
      'practice_history_summary',
      'presented_questions',
      'recent_dialogue',
      'prev_json',
      'last_evidence',
      'current_mastery_level',
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
