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
    };
    const historyContext = {
      'conversation_history',
      'session_history',
      'student_input',
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
    switch (promptName) {
      case 'learn':
      case 'review':
      case 'summarize':
        return {
          ...required,
          ...baseContext,
          ...historyContext,
        };
      case 'learn_init':
      case 'learn_cont':
      case 'review_init':
      case 'review_cont':
      case 'summary':
        return {
          ...required,
          ...baseContext,
          ...nextGenContext,
          ...historyContext,
        };
      default:
        return {
          ...required,
          ...baseContext,
          ...historyContext,
          ...nextGenContext,
        };
    }
  }

  bool _requiresHistory(String promptName) {
    return promptName == 'learn' ||
        promptName == 'review' ||
        promptName == 'summarize';
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
