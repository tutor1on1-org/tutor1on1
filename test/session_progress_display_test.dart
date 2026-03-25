import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/ui/session_progress_display.dart';

void main() {
  test('uses teacher-configured weights and threshold for percent', () {
    const passRule = ResolvedStudentPassRule(
      easyWeight: 1,
      mediumWeight: 2,
      hardWeight: 5,
      passThreshold: 4,
    );

    expect(
      resolveSessionProgressPercent(
        passRule: passRule,
        easyPassedCount: 2,
        mediumPassedCount: 1,
        hardPassedCount: 0,
      ),
      equals(100),
    );
  });

  test('percent can exceed one hundred when score exceeds pass bar', () {
    const passRule = ResolvedStudentPassRule(
      easyWeight: 1,
      mediumWeight: 2,
      hardWeight: 5,
      passThreshold: 4,
    );

    expect(
      resolveSessionProgressPercent(
        passRule: passRule,
        easyPassedCount: 0,
        mediumPassedCount: 0,
        hardPassedCount: 1,
      ),
      equals(125),
    );
  });

  test('compact label shows easy medium hard counts and percent', () {
    const passRule = ResolvedStudentPassRule(
      easyWeight: 1,
      mediumWeight: 1,
      hardWeight: 1,
      passThreshold: 4,
    );

    expect(
      SessionProgressDisplayValue.fromProgress(
        passRule: passRule,
        progress: null,
      ).compactLabel,
      equals('0/0/0/0%'),
    );
    expect(
      SessionProgressDisplayValue.fromProgress(
        passRule: passRule,
        progress: ProgressEntry(
          id: 1,
          studentId: 1,
          courseVersionId: 1,
          kpKey: 'kp',
          lit: false,
          litPercent: 0,
          questionLevel: null,
          easyPassedCount: 2,
          mediumPassedCount: 1,
          hardPassedCount: 0,
          summaryText: null,
          summaryRawResponse: null,
          summaryValid: null,
          updatedAt: DateTime(2026, 3, 22),
        ),
      ).compactLabel,
      equals('2/1/0/75%'),
    );
  });
}
