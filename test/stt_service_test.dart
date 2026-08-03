import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:tutor1on1/services/stt_service.dart';

void main() {
  test('browser recording uses Opus regardless of retired platform hint', () {
    expect(
      SttService.selectRecordingEncoder(isWindows: true),
      equals(AudioEncoder.opus),
    );
    expect(
      SttService.selectRecordingEncoder(isWindows: false),
      equals(AudioEncoder.opus),
    );
  });
}
