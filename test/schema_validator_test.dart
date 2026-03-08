import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/llm/prompt_repository.dart';
import 'package:family_teacher/llm/schema_validator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('summarize schema validation accepts valid output', () async {
    final repo = PromptRepository();
    final schema = await repo.loadSchema('summarize');
    final validator = SchemaValidator();
    final sample = {
      'summary_text': 'Reviewed the node and completed one check.',
      'master_level': 'easy',
      'lit': true,
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
{"teacher_message":"Nice work.","mastery_level":"PASS_MEDIUM","next_step":"MOVE_ON"}
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
      'summary_text': 'Reviewed the node.',
      'master_level': 'easy',
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
      'next_mode': 'LEARN',
      'next_action': 'NONE',
      'next_help_bias': 'UNCHANGED',
      'turn_state': 'UNFINISHED',
    };
    final result = await validator.validateJson(
      schemaMap: schema,
      responseText: jsonEncode(sample),
    );
    expect(result.isValid, isTrue);
  });

  test('review_init schema validation rejects missing question', () async {
    final repo = PromptRepository();
    final schema = await repo.loadSchema('review_init');
    final validator = SchemaValidator();
    final invalid = {
      'teacher_message': 'Try this.',
      'turn_state': 'UNFINISHED',
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
      'next_mode': 'REVIEW',
      'next_action': 'NONE',
      'next_help_bias': 'UNCHANGED',
    };
    final result = await validator.validateJson(
      schemaMap: schema,
      responseText: jsonEncode(invalid),
    );
    expect(result.isValid, isFalse);
    expect(result.error, isNotNull);
  });

  test('review_cont schema validation requires answer_state', () async {
    final repo = PromptRepository();
    final schema = await repo.loadSchema('review_cont');
    final validator = SchemaValidator();
    final invalid = {
      'teacher_message': 'Try one more step.',
      'difficulty_action': 'HOLD',
      'recommended_level': 'easy',
      'turn_state': 'UNFINISHED',
      'question': {
        'text': 'What is 3 + 4?',
        'type_id': 'OTHER',
      },
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
      'next_mode': 'REVIEW',
      'next_action': 'NONE',
      'next_help_bias': 'UNCHANGED',
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
      'answer_state': 'PARTIAL_ATTEMPT',
      'difficulty_action': 'HOLD',
      'recommended_level': 'easy',
      'turn_state': 'UNFINISHED',
      'question': {
        'text': 'What is 3 + 4?',
        'type_id': 'OTHER',
      },
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
      'next_mode': 'REVIEW',
      'next_action': 'NONE',
      'next_help_bias': 'UNCHANGED',
    };
    final result = await validator.validateJson(
      schemaMap: schema,
      responseText: jsonEncode(valid),
    );
    expect(result.isValid, isTrue);
  });
}
