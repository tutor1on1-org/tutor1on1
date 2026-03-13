import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/ui/progress_display.dart';

void main() {
  test('stored lit percent drives display even when lit is true', () {
    expect(
      resolveProgressDisplayPercent(
        litPercent: 33,
        lit: true,
        questionLevel: null,
      ),
      equals(33),
    );
  });

  test('hard question level renders as passed', () {
    expect(
      resolveProgressDisplayPercent(
        litPercent: 0,
        lit: false,
        questionLevel: 'hard',
      ),
      equals(100),
    );
  });

  test('question level raises weak stored percent for display', () {
    expect(
      resolveProgressDisplayPercent(
        litPercent: 0,
        lit: false,
        questionLevel: 'medium',
      ),
      equals(66),
    );
    expect(
      resolveProgressDisplayPercent(
        litPercent: 0,
        lit: false,
        questionLevel: 'easy',
      ),
      equals(33),
    );
  });

  test('stored percent takes precedence once review counts have set it', () {
    expect(
      resolveProgressDisplayPercent(
        litPercent: 66,
        lit: false,
        questionLevel: 'easy',
      ),
      equals(66),
    );
  });
}
