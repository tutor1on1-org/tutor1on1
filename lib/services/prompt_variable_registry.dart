class PromptVariableDefinition {
  const PromptVariableDefinition({
    required this.name,
    required this.description,
    required this.promptNames,
    this.requiredFor = const <String>{},
  });

  final String name;
  final String description;
  final Set<String> promptNames;
  final Set<String> requiredFor;

  bool supportsPrompt(String promptName) {
    return promptNames.isEmpty || promptNames.contains(promptName);
  }
}

class PromptVariableRegistry {
  PromptVariableRegistry._();

  static const String learnPrompt = 'learn';
  static const String reviewPrompt = 'review';

  static const String kpTitle = 'kp_title';
  static const String kpDescription = 'kp_description';
  static const String studentInput = 'student_input';
  static const String recentChat = 'recent_chat';
  static const String conversationHistory = 'conversation_history';
  static const String sessionHistory = 'session_history';
  static const String helpBias = 'help_bias';
  static const String studentSummary = 'student_summary';
  static const String studentProfile = 'student_profile';
  static const String studentPreferences = 'student_preferences';
  static const String lessonContent = 'lesson_content';
  static const String errorBookSummary = 'error_book_summary';
  static const String presentedQuestions = 'presented_questions';
  static const String activeReviewQuestionJson = 'active_review_question_json';
  static const String reviewPassCounts = 'review_pass_counts';
  static const String reviewFailCounts = 'review_fail_counts';
  static const String reviewCorrectTotal = 'review_correct_total';
  static const String reviewAttemptTotal = 'review_attempt_total';

  static const Set<String> _structuredPromptNames = {
    learnPrompt,
    reviewPrompt,
  };

  static const List<PromptVariableDefinition> definitions = [
    PromptVariableDefinition(
      name: kpTitle,
      description: 'Knowledge point title from the course node.',
      promptNames: {learnPrompt, reviewPrompt},
    ),
    PromptVariableDefinition(
      name: kpDescription,
      description: 'Knowledge point description from the course node.',
      promptNames: {learnPrompt, reviewPrompt},
      requiredFor: {learnPrompt, reviewPrompt},
    ),
    PromptVariableDefinition(
      name: studentInput,
      description: 'Latest student input text in this session.',
      promptNames: {learnPrompt, reviewPrompt},
      requiredFor: {learnPrompt, reviewPrompt},
    ),
    PromptVariableDefinition(
      name: recentChat,
      description: 'Short recent chat window from the current session.',
      promptNames: {learnPrompt, reviewPrompt},
    ),
    PromptVariableDefinition(
      name: conversationHistory,
      description: 'Full current session history, trimmed only when needed.',
      promptNames: {learnPrompt, reviewPrompt},
    ),
    PromptVariableDefinition(
      name: sessionHistory,
      description: 'Alias for conversation_history.',
      promptNames: {learnPrompt, reviewPrompt},
    ),
    PromptVariableDefinition(
      name: helpBias,
      description: 'Requested tutor help bias: EASIER, UNCHANGED, or HARDER.',
      promptNames: {learnPrompt, reviewPrompt},
    ),
    PromptVariableDefinition(
      name: studentSummary,
      description:
          'Saved summary for this student/course/kp, falling back to the session summary.',
      promptNames: {learnPrompt, reviewPrompt},
    ),
    PromptVariableDefinition(
      name: studentProfile,
      description:
          'Resolved student profile from teacher-defined fields such as level, language, interests, and support notes.',
      promptNames: {learnPrompt, reviewPrompt},
    ),
    PromptVariableDefinition(
      name: studentPreferences,
      description:
          'Resolved student preferences from teacher-defined fields such as tone, pace, and format.',
      promptNames: {learnPrompt, reviewPrompt},
    ),
    PromptVariableDefinition(
      name: lessonContent,
      description: 'Lesson content for the current knowledge point.',
      promptNames: {learnPrompt},
      requiredFor: {learnPrompt},
    ),
    PromptVariableDefinition(
      name: errorBookSummary,
      description: 'Aggregated mistake counts and tags for this knowledge point.',
      promptNames: {learnPrompt, reviewPrompt},
    ),
    PromptVariableDefinition(
      name: presentedQuestions,
      description: 'Candidate question pool provided for review selection.',
      promptNames: {reviewPrompt},
    ),
    PromptVariableDefinition(
      name: activeReviewQuestionJson,
      description:
          'Legacy JSON state for the one active review question, or null.',
      promptNames: {reviewPrompt},
    ),
    PromptVariableDefinition(
      name: reviewPassCounts,
      description:
          'JSON map with cumulative passed counts by difficulty: easy, medium, and hard.',
      promptNames: {reviewPrompt},
    ),
    PromptVariableDefinition(
      name: reviewFailCounts,
      description:
          'JSON map with cumulative failed counts by difficulty: easy, medium, and hard.',
      promptNames: {reviewPrompt},
    ),
    PromptVariableDefinition(
      name: reviewCorrectTotal,
      description:
          'Number of closed review questions answered correctly in this session.',
      promptNames: {reviewPrompt},
    ),
    PromptVariableDefinition(
      name: reviewAttemptTotal,
      description: 'Number of closed review questions attempted in this session.',
      promptNames: {reviewPrompt},
    ),
  ];

  static Set<String> allSupportedVariables() {
    return definitions.map((definition) => definition.name).toSet();
  }

  static Set<String> allowedVariables(String promptName) {
    final normalized = promptName.trim().toLowerCase();
    if (!_structuredPromptNames.contains(normalized)) {
      return allSupportedVariables();
    }
    return definitions
        .where((definition) => definition.supportsPrompt(normalized))
        .map((definition) => definition.name)
        .toSet();
  }

  static Set<String> requiredVariables(String promptName) {
    final normalized = promptName.trim().toLowerCase();
    return definitions
        .where((definition) => definition.requiredFor.contains(normalized))
        .map((definition) => definition.name)
        .toSet();
  }

  static String? descriptionFor(String variableName) {
    for (final definition in definitions) {
      if (definition.name == variableName) {
        return definition.description;
      }
    }
    return null;
  }

  static Map<String, Object?> buildTutorPromptValues({
    required Object? kpTitle,
    required Object? kpDescription,
    required Object? studentInput,
    required Object? recentChat,
    required Object? conversationHistory,
    required Object? helpBias,
    required Object? studentSummary,
    required Object? studentProfile,
    required Object? studentPreferences,
    required Object? lessonContent,
    required Object? errorBookSummary,
    required Object? presentedQuestions,
    required Object? activeReviewQuestionJson,
    required Object? reviewPassCounts,
    required Object? reviewFailCounts,
    required Object? reviewCorrectTotal,
    required Object? reviewAttemptTotal,
  }) {
    return {
      PromptVariableRegistry.kpTitle: kpTitle,
      PromptVariableRegistry.kpDescription: kpDescription,
      PromptVariableRegistry.studentInput: studentInput,
      PromptVariableRegistry.recentChat: recentChat,
      PromptVariableRegistry.conversationHistory: conversationHistory,
      PromptVariableRegistry.sessionHistory: conversationHistory,
      PromptVariableRegistry.helpBias: helpBias,
      PromptVariableRegistry.studentSummary: studentSummary,
      PromptVariableRegistry.studentProfile: studentProfile,
      PromptVariableRegistry.studentPreferences: studentPreferences,
      PromptVariableRegistry.lessonContent: lessonContent,
      PromptVariableRegistry.errorBookSummary: errorBookSummary,
      PromptVariableRegistry.presentedQuestions: presentedQuestions,
      PromptVariableRegistry.activeReviewQuestionJson: activeReviewQuestionJson,
      PromptVariableRegistry.reviewPassCounts: reviewPassCounts,
      PromptVariableRegistry.reviewFailCounts: reviewFailCounts,
      PromptVariableRegistry.reviewCorrectTotal: reviewCorrectTotal,
      PromptVariableRegistry.reviewAttemptTotal: reviewAttemptTotal,
    };
  }
}
