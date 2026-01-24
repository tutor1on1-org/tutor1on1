import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:window_manager/window_manager.dart';

class ScreenLockService with WindowListener {
  ScreenLockService({
    this.lockDelay = const Duration(seconds: 10),
  });

  final Duration lockDelay;
  Timer? _lockTimer;
  bool _allowClose = false;

  Future<void> start() async {
    if (!Platform.isWindows) {
      return;
    }
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
  }

  Future<void> dispose() async {
    if (!Platform.isWindows) {
      return;
    }
    windowManager.removeListener(this);
    _lockTimer?.cancel();
  }

  Future<void> allowCloseOnce() async {
    if (!Platform.isWindows) {
      return;
    }
    _allowClose = true;
    await windowManager.setPreventClose(false);
  }

  @override
  void onWindowBlur() {
    if (!Platform.isWindows) {
      return;
    }
    _attemptRefocus();
    _startLockTimer();
  }

  @override
  void onWindowFocus() {
    _lockTimer?.cancel();
  }

  @override
  void onWindowClose() {
    if (!Platform.isWindows) {
      return;
    }
    if (_allowClose) {
      return;
    }
    _attemptRefocus();
  }

  void _startLockTimer() {
    _lockTimer?.cancel();
    _lockTimer = Timer(lockDelay, () async {
      if (!Platform.isWindows) {
        return;
      }
      final focused = await windowManager.isFocused();
      if (!focused) {
        _lockWindows();
      }
    });
  }

  Future<void> _attemptRefocus() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  void _lockWindows() {
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final lock = user32.lookupFunction<Int32 Function(), int Function()>(
        'LockWorkStation',
      );
      lock();
    } catch (_) {}
  }
}
