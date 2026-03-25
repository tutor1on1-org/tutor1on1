import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:tutor1on1/services/stt_service.dart';

void main() {
  test('Windows recording uses wav encoder', () {
    expect(
      SttService.selectRecordingEncoder(isWindows: true),
      equals(AudioEncoder.wav),
    );
  });

  test('Non-Windows recording uses aac encoder', () {
    expect(
      SttService.selectRecordingEncoder(isWindows: false),
      equals(AudioEncoder.aacLc),
    );
  });
}
