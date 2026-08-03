import 'package:flutter_test/flutter_test.dart';
import 'package:tutor1on1/services/screen_lock_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('browser study mode retains logical enabled state', () async {
    final service = ScreenLockService();

    await service.start();

    expect(service.isEnabled, isTrue);

    await service.stop();

    expect(service.isEnabled, isFalse);
  });

  test('browser close allowance is an intentional no-op', () async {
    final service = ScreenLockService();

    await service.start();
    await service.allowCloseOnce();

    expect(service.isEnabled, isTrue);
  });
}
