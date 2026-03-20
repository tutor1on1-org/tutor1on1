import 'package:flutter_test/flutter_test.dart';
import 'package:family_teacher/services/screen_lock_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mobile study mode enables soft UI and wake lock', () async {
    final bridge = FakeStudyModePlatformBridge(isAndroid: true);
    final service = ScreenLockService(bridge: bridge);

    await service.start();

    expect(service.isEnabled, isTrue);
    expect(bridge.screenAwake, isTrue);
    expect(bridge.studyUiEnabled, isTrue);
    expect(bridge.addListenerCalls, 0);

    await service.stop();

    expect(service.isEnabled, isFalse);
    expect(bridge.screenAwake, isFalse);
    expect(bridge.studyUiEnabled, isFalse);
  });

  test('macOS study mode applies desktop soft controls', () async {
    final bridge = FakeStudyModePlatformBridge(isMacOS: true);
    final service = ScreenLockService(bridge: bridge);

    await service.start();

    expect(bridge.addListenerCalls, 1);
    expect(bridge.preventClose, isTrue);
    expect(bridge.alwaysOnTop, isTrue);
    expect(bridge.fullScreen, isTrue);
    expect(bridge.screenAwake, isTrue);

    await service.stop();

    expect(bridge.removeListenerCalls, 1);
    expect(bridge.preventClose, isFalse);
    expect(bridge.alwaysOnTop, isFalse);
    expect(bridge.fullScreen, isFalse);
    expect(bridge.screenAwake, isFalse);
  });

  test('macOS study mode restores window after blur timeout', () async {
    final bridge = FakeStudyModePlatformBridge(isMacOS: true);
    final service = ScreenLockService(
      bridge: bridge,
      lockDelay: const Duration(milliseconds: 10),
    );

    await service.start();
    bridge.focused = false;
    bridge.alwaysOnTop = false;
    bridge.fullScreen = false;

    service.onWindowBlur();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.workstationLocked, isFalse);
    expect(bridge.showCalls, greaterThanOrEqualTo(1));
    expect(bridge.focusCalls, greaterThanOrEqualTo(1));
    expect(bridge.alwaysOnTop, isTrue);
    expect(bridge.fullScreen, isTrue);
    await service.stop();
  });

  test('windows study mode still locks after blur timeout', () async {
    final bridge = FakeStudyModePlatformBridge(
      isWindows: true,
      focused: false,
    );
    final service = ScreenLockService(
      bridge: bridge,
      lockDelay: const Duration(milliseconds: 10),
    );

    await service.start();
    service.onWindowBlur();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.workstationLocked, isTrue);
    expect(bridge.showCalls, greaterThanOrEqualTo(1));
    expect(bridge.focusCalls, greaterThanOrEqualTo(1));
    await service.stop();
  });
}
