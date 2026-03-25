import 'dart:convert';

import 'package:json_schema/json_schema.dart';

class ValidationResult {
  ValidationResult({
    required this.isValid,
    this.error,
    this.data,
    this.rawJson,
  });

  final bool isValid;
  final String? error;
  final Map<String, dynamic>? data;
  final Object? rawJson;
}

class SchemaValidator {
  Future<ValidationResult> validateJson({
    required Map<String, dynamic> schemaMap,
    required String responseText,
  }) async {
    final extracted = _extractJsonObject(responseText);
    if (extracted == null) {
      return ValidationResult(
        isValid: false,
        error: 'No JSON object found in response.',
      );
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(extracted);
    } catch (e) {
      return ValidationResult(
        isValid: false,
        error: 'JSON decode failed: $e',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      return ValidationResult(
        isValid: false,
        error: 'Expected a JSON object at root.',
        rawJson: decoded,
      );
    }
    final schema = JsonSchema.create(schemaMap);
    final results = schema.validate(decoded);
    if (results.errors.isNotEmpty) {
      return ValidationResult(
        isValid: false,
        error: results.errors.map((e) => e.message).join(' | '),
        rawJson: decoded,
      );
    }
    return ValidationResult(isValid: true, data: decoded, rawJson: decoded);
  }

  String? _extractJsonObject(String input) {
    final start = input.indexOf('{');
    final end = input.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      return null;
    }
    return input.substring(start, end + 1);
  }
}
