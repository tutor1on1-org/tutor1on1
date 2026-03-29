import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/services/prompt_template_validator.dart';

void main() {
  test('validator rejects missing, unknown, and non-English variables', () {
    final validator = PromptTemplateValidator();
    final result = validator.validate(
      promptName: 'review',
      content: '''
{{kp_description}}
{{student_input}}
{{active_review_question_json}}
{{target_difficulty}}
{{presented_questions}}
{{bad_name}}
{{学生输入}}
''',
    );

    expect(result.missingVariables, contains('error_book_summary'));
    expect(result.unknownVariables, contains('bad_name'));
    expect(result.invalidVariables, contains('学生输入'));
    expect(result.isValid, isFalse);
  });
}
