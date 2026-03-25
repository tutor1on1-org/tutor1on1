import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/llm/prompt_repository.dart';
import 'package:tutor1on1/llm/schema_validator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('learn schema validation accepts valid output', () async {
    final repo = PromptRepository();
    final schema = await repo.loadSchema('learn');
    final validator = SchemaValidator();
    final sample = <String, Object?>{
      'text': 'Let us compare each number to zero.',
      'difficulty': 'easy',
      'mistakes': <String>[],
      'next_action': 'review',
    };
    final result = await validator.validateJson(
      schemaMap: schema,
      responseText: jsonEncode(sample),
    );
    expect(result.isValid, isTrue);
  });

  test('review schema validation accepts valid output', () async {
    final repo = PromptRepository();
    final schema = await repo.loadSchema('review');
    final validator = SchemaValidator();
    final sample = <String, Object?>{
      'text': 'Which number is greater: -3 or 2?',
      'difficulty': 'easy',
      'mistakes': <String>[],
      'next_action': 'review',
      'finished': false,
    };
    final result = await validator.validateJson(
      schemaMap: schema,
      responseText: jsonEncode(sample),
    );
    expect(result.isValid, isTrue);
  });

  test('review schema validation rejects missing finished', () async {
    final repo = PromptRepository();
    final schema = await repo.loadSchema('review');
    final validator = SchemaValidator();
    final invalid = <String, Object?>{
      'text': 'Try one more step.',
      'difficulty': 'easy',
      'mistakes': <String>[],
      'next_action': 'review',
    };
    final result = await validator.validateJson(
      schemaMap: schema,
      responseText: jsonEncode(invalid),
    );
    expect(result.isValid, isFalse);
    expect(result.error, isNotNull);
  });
}
