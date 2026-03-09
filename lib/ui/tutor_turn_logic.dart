import 'package:flutter/services.dart';

String? normalizeTutorTurnState(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim().toUpperCase();
  if (normalized == 'UNFINISHED' || normalized == 'FINISHED') {
    return normalized;
  }
  return null;
}

bool hasActiveTutorTurn({
  required String action,
  required Map<String, dynamic>? parsed,
}) {
  if (action != 'learn' && action != 'review') {
    return false;
  }
  return normalizeTutorTurnState(parsed?['turn_state']) == 'UNFINISHED';
}

bool isFinishedTutorTurn({
  required String action,
  required Map<String, dynamic>? parsed,
}) {
  if (action != 'learn' && action != 'review') {
    return false;
  }
  return normalizeTutorTurnState(parsed?['turn_state']) == 'FINISHED';
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
  required bool hasActiveTurn,
}) {
  final normalized = action.trim().toLowerCase();
  if (normalized == 'learn') {
    return wantsContinue && hasActiveTurn ? 'learn_cont' : 'learn_init';
  }
  if (normalized == 'review') {
    return wantsContinue && hasActiveTurn ? 'review_cont' : 'review_init';
  }
  return normalized;
}
