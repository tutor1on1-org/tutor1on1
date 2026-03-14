import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/ui/progress_display.dart';

void main() {
  test('easy passed count renders one-third progress', () {
    expect(
      resolveProgressDisplayPercent(
        lit: false,
        easyPassedCount: 1,
        mediumPassedCount: 0,
        hardPassedCount: 0,
      ),
      equals(33),
    );
  });

  test('hard passed count renders full progress', () {
    expect(
      resolveProgressDisplayPercent(
        lit: false,
        easyPassedCount: 0,
        mediumPassedCount: 0,
        hardPassedCount: 1,
      ),
      equals(100),
    );
  });

  test('medium passed count renders two-thirds progress', () {
    expect(
      resolveProgressDisplayPercent(
        lit: false,
        easyPassedCount: 0,
        mediumPassedCount: 1,
        hardPassedCount: 0,
      ),
      equals(66),
    );
  });

  test('lit without passed counts still renders full progress', () {
    expect(
      resolveProgressDisplayPercent(
        lit: true,
        easyPassedCount: 0,
        mediumPassedCount: 0,
        hardPassedCount: 0,
      ),
      equals(100),
    );
  });
}
