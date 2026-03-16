import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/ui/tutor_turn_logic.dart';

void main() {
  test('review turn stays active while finished is false', () {
    expect(
      hasActiveTutorTurn(
        action: 'review',
        parsed: <String, dynamic>{'finished': false},
      ),
      isTrue,
    );
  });

  test('closed review turn is finished', () {
    expect(
      hasActiveTutorTurn(
        action: 'review',
        parsed: <String, dynamic>{'finished': true},
      ),
      isFalse,
    );
    expect(
      isFinishedTutorTurn(
        action: 'review',
        parsed: <String, dynamic>{'finished': true},
      ),
      isTrue,
    );
  });

  test('draft normalization clears composing range before STT starts', () {
    final normalized = normalizeDraftForSttRecording(
      const TextEditingValue(
        text: 'draft answer',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
        composing: TextRange(start: 0, end: 5),
      ),
    );

    expect(normalized.text, equals('draft answer'));
    expect(normalized.selection, const TextSelection.collapsed(offset: 12));
    expect(normalized.composing, TextRange.empty);
  });

  test('prompt resolution uses simple learn/review names', () {
    expect(
      resolveTutorPromptName(action: 'review', wantsContinue: true),
      equals('review'),
    );
    expect(
      resolveTutorPromptName(action: 'learn', wantsContinue: true),
      equals('learn'),
    );
  });
}
