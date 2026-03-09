import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/ui/tutor_turn_logic.dart';

void main() {
  test('review turn stays active while turn_state is unfinished', () {
    expect(
      hasActiveTutorTurn(
        action: 'review',
        parsed: <String, dynamic>{
          'turn_state': 'UNFINISHED',
          'question': null,
        },
      ),
      isTrue,
    );
  });

  test('finished review turn is not active anymore', () {
    expect(
      hasActiveTutorTurn(
        action: 'review',
        parsed: <String, dynamic>{
          'turn_state': 'FINISHED',
        },
      ),
      isFalse,
    );
    expect(
      isFinishedTutorTurn(
        action: 'review',
        parsed: <String, dynamic>{
          'turn_state': 'FINISHED',
        },
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
    expect(
      normalized.selection,
      const TextSelection.collapsed(offset: 12),
    );
    expect(normalized.composing, TextRange.empty);
  });

  test('prompt resolution stays on the message action branch', () {
    expect(
      resolveTutorPromptName(
        action: 'review',
        wantsContinue: true,
        hasActiveTurn: true,
      ),
      equals('review_cont'),
    );
    expect(
      resolveTutorPromptName(
        action: 'learn',
        wantsContinue: true,
        hasActiveTurn: false,
      ),
      equals('learn_init'),
    );
  });

  test('non tutor actions pass through prompt resolution unchanged', () {
    expect(
      resolveTutorPromptName(
        action: 'summary',
        wantsContinue: true,
        hasActiveTurn: true,
      ),
      equals('summary'),
    );
  });
}
