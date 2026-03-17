import 'package:family_teacher/models/tutor_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
            'finished': true,
            'mistakes': <String>[],
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
