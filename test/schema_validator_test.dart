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
}
