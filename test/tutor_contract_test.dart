import 'package:tutor1on1/models/tutor_contract.dart';
import 'package:tutor1on1/models/tutor_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('control state round-trips a just-passed event', () {
    const control = TutorControlState(
      version: TutorControlState.currentVersion,
      mode: TutorMode.review,
      step: TutorTurnStep.newTurn,
      turnFinished: true,
      helpBias: TutorHelpBias.unchanged,
      recommendedAction: TutorFinishedAction.review,
      activeReviewQuestion: null,
      justPassedKpEvent: TutorJustPassedKpEvent(
        easyPassedCount: 1,
        mediumPassedCount: 2,
        hardPassedCount: 3,
      ),
    );

    final decoded = TutorControlState.fromJsonText(control.toJsonText());

    expect(decoded?.justPassedKpEvent?.easyPassedCount, equals(1));
    expect(decoded?.justPassedKpEvent?.mediumPassedCount, equals(2));
    expect(decoded?.justPassedKpEvent?.hardPassedCount, equals(3));
  });

  test('control state copyWith can clear recommended action', () {
    const control = TutorControlState(
      version: TutorControlState.currentVersion,
      mode: TutorMode.review,
      step: TutorTurnStep.newTurn,
      turnFinished: true,
      helpBias: TutorHelpBias.unchanged,
      recommendedAction: TutorFinishedAction.review,
      activeReviewQuestion: null,
      justPassedKpEvent: null,
    );

    final updated = control.copyWith(recommendedAction: null);

    expect(updated.recommendedAction, isNull);
  });

  test('control state ignores legacy allowed actions field', () {
    final decoded = TutorControlState.fromJson(<String, dynamic>{
      'version': 2,
      'mode': 'REVIEW',
      'step': 'NEW',
      'turn_finished': true,
      'help_bias': 'UNCHANGED',
      'allowed_actions': <String>['REVIEW'],
      'recommended_action': 'REVIEW',
      'active_review_question': null,
      'just_passed_kp_event': null,
    });

    expect(decoded?.recommendedAction, equals(TutorFinishedAction.review));
    expect(decoded?.toJson().containsKey('allowed_actions'), isFalse);
  });

  test('rebuilds evidence counts from finished review turns', () {
    final seed = TutorEvidenceState(
      version: TutorEvidenceState.currentVersion,
      policy: TutorEvidenceState.reviewOnlyPolicy,
      gradedReviewCount: 1,
      summaryConsumedReviewCount: 0,
      reviewCorrectTotal: 1,
      reviewAttemptTotal: 1,
      easyPassedCount: 0,
      mediumPassedCount: 0,
      hardPassedCount: 1,
      easyFailedCount: 0,
      mediumFailedCount: 0,
      hardFailedCount: 0,
      lastAssessedAction: 'REVIEW',
      lastEvidence: const <String, dynamic>{
        'difficulty': 'hard',
        'finished': true,
        'mistakes': <String>[],
      },
    );

    final rebuilt = TutorEvidenceState.rebuildFromAssistantTurns(
      seed: seed,
      turns: const <TutorEvidenceAssistantTurn>[
        TutorEvidenceAssistantTurn(
          actionMode: 'review',
          parsed: <String, dynamic>{
            'difficulty': 'easy',
            'finished': false,
            'mistakes': <String>['retry'],
          },
        ),
        TutorEvidenceAssistantTurn(
          actionMode: 'review',
          parsed: <String, dynamic>{
            'difficulty': 'easy',
            'finished': true,
            'mistakes': <String>[],
          },
        ),
        TutorEvidenceAssistantTurn(
          actionMode: 'review',
          parsed: <String, dynamic>{
            'difficulty': 'medium',
            'finished': false,
            'mistakes': <String>['retry'],
          },
        ),
        TutorEvidenceAssistantTurn(
          actionMode: 'review',
          parsed: <String, dynamic>{
            'difficulty': 'medium',
            'finished': true,
            'mistakes': <String>[],
          },
        ),
        TutorEvidenceAssistantTurn(
          actionMode: 'review',
          parsed: <String, dynamic>{
            'difficulty': 'hard',
            'finished': false,
            'mistakes': <String>['retry'],
          },
        ),
        TutorEvidenceAssistantTurn(
          actionMode: 'review',
          parsed: <String, dynamic>{
            'difficulty': 'hard',
            'finished': true,
            'mistakes': <String>[],
          },
        ),
      ],
    );

    expect(rebuilt.easyPassedCount, 1);
    expect(rebuilt.mediumPassedCount, 1);
    expect(rebuilt.hardPassedCount, 1);
    expect(rebuilt.reviewCorrectTotal, 3);
    expect(rebuilt.reviewAttemptTotal, 3);
    expect(rebuilt.gradedReviewCount, 3);
  });
}
