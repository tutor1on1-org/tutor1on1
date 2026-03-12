import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/llm/prompt_repository.dart';
import 'package:family_teacher/llm/schema_validator.dart';

Map<String, Object?> _control({
  required String mode,
  required String step,
  required bool turnFinished,
  List<String> allowedActions = const <String>[],
  String? recommendedAction,
}) {
  return <String, Object?>{
    'version': 1,
    'mode': mode,
    'step': step,
    'turn_finished': turnFinished,
    'help_bias': 'UNCHANGED',
    'allowed_actions': allowedActions,
    'recommended_action': recommendedAction,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('summarize schema validation accepts valid output', () async {
    final repo = PromptRepository();
    final schema = await repo.loadSchema('summarize');
    final validator = SchemaValidator();
    final sample = {
      'teacher_message': 'You can move on.',
      'control': _control(
        mode: 'REVIEW',
        step: 'NEW',
        turnFinished: true,
        allowedActions: const ['PAUSE'],
        recommendedAction: 'PAUSE',
      ),
      'mastery_level': 'PASS_HARD',
      'next_step': 'MOVE_ON',
    };
    final result = await validator.validateJson(
      schemaMap: schema,
      responseText: jsonEncode(sample),
    );
    expect(result.isValid, isTrue);
  });

  test(
    'summarize schema validation accepts JSON object wrapped in markdown',
    () async {
      final repo = PromptRepository();
      final schema = await repo.loadSchema('summarize');
      final validator = SchemaValidator();
      final wrapped = '''
Model output:
```json
{"teacher_message":"Nice work.","control":{"version":1,"mode":"REVIEW","step":"NEW","turn_finished":true,"help_bias":"UNCHANGED","allowed_actions":["NEXT_QUESTION","LEARN","PAUSE"],"recommended_action":"NEXT_QUESTION"},"mastery_level":"PASS_MEDIUM","next_step":"MOVE_ON"}
```
''';
      final result = await validator.validateJson(
        schemaMap: schema,
        responseText: wrapped,
      );
      expect(result.isValid, isTrue);
    },
  );

  test('summarize schema validation rejects missing required fields', () async {
    final repo = PromptRepository();
    final schema = await repo.loadSchema('summarize');
    final validator = SchemaValidator();
    final invalid = {
      'teacher_message': 'Reviewed the node.',
      'mastery_level': 'PASS_EASY',
    };
    final result = await validator.validateJson(
      schemaMap: schema,
      responseText: jsonEncode(invalid),
    );
    expect(result.isValid, isFalse);
    expect(result.error, isNotNull);
  });

  test('learn_init schema validation accepts valid structured output',
      () async {
    final repo = PromptRepository();
    final schema = await repo.loadSchema('learn_init');
    final validator = SchemaValidator();
    final sample = {
      'teacher_message': 'Let us focus on one idea, then a quick check.',
      'understanding': 'PARTIAL',
      'control': _control(
        mode: 'LEARN',
        step: 'CONTINUE',
        turnFinished: false,
      ),
    };
    final result = await validator.validateJson(
      schemaMap: schema,
      responseText: jsonEncode(sample),
    );
    expect(result.isValid, isTrue);
  });

  test(
      'review_init schema validation accepts visible question in teacher_message',
      () async {
    final repo = PromptRepository();
    final schema = await repo.loadSchema('review_init');
    final validator = SchemaValidator();
    final valid = {
      'teacher_message':
          'In a histogram, the class interval 20-30 has frequency density 4.5. What is the frequency for this class?',
      'control': _control(
        mode: 'REVIEW',
        step: 'CONTINUE',
        turnFinished: false,
      ),
      'difficulty_level': 'easy',
      'grading': null,
      'error_book_update': null,
      'evidence': {
        'a': 0,
        'c': 0,
        'h': 0,
        't': 'OTHER',
        'mt': <String>[],
      },
      'mastery_level': 'NOT_PASS',
    };
    final result = await validator.validateJson(
      schemaMap: schema,
      responseText: jsonEncode(valid),
    );
    expect(result.isValid, isTrue);
  });

  test('review_cont schema validation requires answer_state', () async {
    final repo = PromptRepository();
    final schema = await repo.loadSchema('review_cont');
    final validator = SchemaValidator();
    final invalid = {
      'teacher_message': 'Try one more step.',
      'control': _control(
        mode: 'REVIEW',
        step: 'CONTINUE',
        turnFinished: false,
      ),
      'difficulty_action': 'HOLD',
      'recommended_level': 'easy',
      'grading': null,
      'error_book_update': null,
      'evidence': {
        'a': 0,
        'c': 0,
        'h': 0,
        't': 'OTHER',
        'mt': <String>[],
      },
      'mastery_level': 'NOT_PASS',
    };
    final result = await validator.validateJson(
      schemaMap: schema,
      responseText: jsonEncode(invalid),
    );
    expect(result.isValid, isFalse);
    expect(result.error, isNotNull);
  });

  test('review_cont schema validation accepts answer_state field', () async {
    final repo = PromptRepository();
    final schema = await repo.loadSchema('review_cont');
    final validator = SchemaValidator();
    final valid = {
      'teacher_message': 'Please provide your final numeric result.',
      'control': _control(
        mode: 'REVIEW',
        step: 'CONTINUE',
        turnFinished: false,
      ),
      'answer_state': 'PARTIAL_ATTEMPT',
      'difficulty_action': 'HOLD',
      'recommended_level': 'easy',
      'grading': null,
      'error_book_update': null,
      'evidence': {
        'a': 0,
        'c': 0,
        'h': 0,
        't': 'OTHER',
        'mt': <String>[],
      },
      'mastery_level': 'NOT_PASS',
    };
    final result = await validator.validateJson(
      schemaMap: schema,
      responseText: jsonEncode(valid),
    );
    expect(result.isValid, isTrue);
  });
}
