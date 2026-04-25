import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/llm/prompt_repository.dart';
import 'package:tutor1on1/llm/schema_validator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('review_cont schema validation accepts valid output', () async {
    final repo = PromptRepository();
    final schema = await repo.loadSchema('review_cont');
    final validator = SchemaValidator();
    final sample = <String, Object?>{
      'text': 'Which number is greater: -3 or 2?',
      'mistakes': <String>[],
      'finished': false,
      'difficulty_adjustment': 'same',
    };
    final result = await validator.validateJson(
      schemaMap: schema,
      responseText: jsonEncode(sample),
    );
    expect(result.isValid, isTrue);
  });

  test('review_cont schema validation rejects missing finished', () async {
    final repo = PromptRepository();
    final schema = await repo.loadSchema('review_cont');
    final validator = SchemaValidator();
    final invalid = <String, Object?>{
      'text': 'Try one more step.',
      'mistakes': <String>[],
      'difficulty_adjustment': 'same',
    };
    final result = await validator.validateJson(
      schemaMap: schema,
      responseText: jsonEncode(invalid),
    );
    expect(result.isValid, isFalse);
    expect(result.error, isNotNull);
  });
}
