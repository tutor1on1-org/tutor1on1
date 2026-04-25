import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/services/prompt_variable_registry.dart';
import 'package:tutor1on1/services/prompt_template_validator.dart';

void main() {
  test('validator rejects missing, unknown, and non-English variables', () {
    final validator = PromptTemplateValidator();
    final result = validator.validate(
      promptName: 'review_cont',
      content: '''
{{kp_description}}
{{conversation_history}}
{{session_history}}
{{target_difficulty}}
{{bad_name}}
{{学生输入}}
''',
    );

    expect(result.missingVariables, contains('active_review_question_json'));
    expect(
      result.unknownVariables,
      containsAll(['target_difficulty', 'bad_name']),
    );
    expect(result.unknownVariables, isNot(contains('conversation_history')));
    expect(result.unknownVariables, isNot(contains('session_history')));
    expect(result.invalidVariables, contains('学生输入'));
    expect(result.isValid, isFalse);
  });

  test('runtime prompt values are covered by the registry and validator', () {
    final validator = PromptTemplateValidator();
    final runtimeKeys = PromptVariableRegistry.buildTutorPromptValues(
      kpTitle: '',
      kpDescription: '',
      studentInput: '',
      recentChat: '',
      conversationHistory: '',
      helpBias: '',
      studentSummary: '',
      studentContext: '',
      studentProfile: '',
      studentPreferences: '',
      lessonContent: '',
      errorBookSummary: '',
      presentedQuestions: '',
      activeReviewQuestionJson: '',
      reviewPassCounts: '',
      reviewFailCounts: '',
      reviewCorrectTotal: '',
      reviewAttemptTotal: '',
    ).keys.toSet();

    expect(validator.allSupportedVariables(), containsAll(runtimeKeys));
    expect(runtimeKeys, contains('conversation_history'));
    expect(runtimeKeys, contains('session_history'));
    expect(
      validator.allowedVariables('review_cont'),
      containsAll(['conversation_history', 'session_history']),
    );
    expect(
      validator.allowedVariables('review_init'),
      containsAll(['conversation_history', 'session_history']),
    );
  });
}
