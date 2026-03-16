import 'package:flutter/services.dart';

bool hasActiveTutorTurn({
  required String action,
  required Map<String, dynamic>? parsed,
}) {
  final normalized = action.trim().toLowerCase();
  if (normalized == 'review') {
    return parsed?['finished'] == false;
  }
  if (normalized == 'learn') {
    return false;
  }
  return false;
}

bool isFinishedTutorTurn({
  required String action,
  required Map<String, dynamic>? parsed,
}) {
  final normalized = action.trim().toLowerCase();
  if (normalized == 'review') {
    return parsed?['finished'] == true;
  }
  if (normalized == 'learn') {
    return parsed != null;
  }
  return false;
}

TextEditingValue normalizeDraftForSttRecording(TextEditingValue value) {
  final text = value.text;
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
    composing: TextRange.empty,
  );
}

String resolveTutorPromptName({
  required String action,
  required bool wantsContinue,
}) {
  final normalized = action.trim().toLowerCase();
  if (normalized == 'learn' || normalized == 'review') {
    return normalized;
  }
  return normalized;
}
