import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/ui/progress_display.dart';

void main() {
  test('lit flag forces passed display percent', () {
    expect(
      resolveProgressDisplayPercent(
        litPercent: 0,
        lit: true,
        questionLevel: null,
      ),
      equals(100),
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

  test('stored stronger percent still wins', () {
    expect(
      resolveProgressDisplayPercent(
        litPercent: 85,
        lit: false,
        questionLevel: 'easy',
      ),
      equals(85),
    );
  });
}
