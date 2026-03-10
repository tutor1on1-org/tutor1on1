import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/models/tutor_contract.dart';
import 'package:family_teacher/ui/tutor_turn_logic.dart';

void main() {
  test('review turn stays active while control says unfinished', () {
    expect(
      hasActiveTutorTurn(
        action: 'review',
        parsed: <String, dynamic>{
          'control': {
            'version': 1,
            'mode': 'REVIEW',
            'step': 'CONTINUE',
            'turn_finished': false,
            'help_bias': 'UNCHANGED',
            'allowed_actions': const <String>[],
            'recommended_action': null,
          },
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
          'control': {
            'version': 1,
            'mode': 'REVIEW',
            'step': 'NEW',
            'turn_finished': true,
            'help_bias': 'UNCHANGED',
            'allowed_actions': const <String>['NEXT_QUESTION'],
            'recommended_action': 'NEXT_QUESTION',
          },
        },
      ),
      isFalse,
    );
    expect(
      isFinishedTutorTurn(
        action: 'review',
        parsed: <String, dynamic>{
          'control': {
            'version': 1,
            'mode': 'REVIEW',
            'step': 'NEW',
            'turn_finished': true,
            'help_bias': 'UNCHANGED',
            'allowed_actions': const <String>['NEXT_QUESTION'],
            'recommended_action': 'NEXT_QUESTION',
          },
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
      ),
      equals('review_cont'),
    );
    expect(
      resolveTutorPromptName(
        action: 'learn',
        wantsContinue: true,
      ),
      equals('learn_cont'),
    );
  });

  test('non tutor actions pass through prompt resolution unchanged', () {
    expect(
      resolveTutorPromptName(
        action: 'summary',
        wantsContinue: true,
      ),
      equals('summary'),
    );
  });

  test('invalid control contract is rejected by parser', () {
    expect(
      TutorControlState.fromJson(<String, dynamic>{
        'version': 1,
        'mode': 'REVIEW',
        'step': 'NEW',
        'turn_finished': true,
        'help_bias': 'UNCHANGED',
        'allowed_actions': const <String>['INVALID'],
        'recommended_action': null,
      }),
      isNull,
    );
  });
}
