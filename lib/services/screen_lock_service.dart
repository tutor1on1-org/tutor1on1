import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:window_manager/window_manager.dart';

class ScreenLockService with WindowListener {
  static final ScreenLockService instance = ScreenLockService();

  ScreenLockService({
    this.lockDelay = const Duration(seconds: 10),
  });

  final Duration lockDelay;
  Timer? _lockTimer;
  Timer? _watchTimer;
  bool _allowClose = false;
  bool _enabled = false;

  bool get isEnabled => _enabled;

  Future<void> setEnabled(bool enabled) async {
    if (enabled == _enabled) {
      return;
    }
    if (enabled) {
      await start();
    } else {
      await stop();
    }
    _enabled = enabled;
  }

  Future<void> start() async {
    if (!Platform.isWindows) {
      return;
    }
    _enabled = true;
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    await windowManager.setAlwaysOnTop(true);
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(lockDelay, (_) async {
      if (!Platform.isWindows) {
        return;
      }
      final focused = await windowManager.isFocused();
      if (!focused) {
        _lockWindows();
        return;
      }
      final isTop = await windowManager.isAlwaysOnTop();
      if (!isTop) {
        await windowManager.setAlwaysOnTop(true);
      }
    });
  }

  Future<void> stop() async {
    if (!Platform.isWindows) {
      return;
    }
    windowManager.removeListener(this);
    _lockTimer?.cancel();
    _watchTimer?.cancel();
    _allowClose = false;
    _enabled = false;
    try {
      await windowManager.setPreventClose(false);
      await windowManager.setAlwaysOnTop(false);
    } catch (_) {}
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
    if (!Platform.isWindows || !_enabled) {
      return;
    }
    _attemptRefocus();
    _startLockTimer();
  }

  @override
  void onWindowFocus() {
    if (!_enabled) {
      return;
    }
    _lockTimer?.cancel();
  }

  @override
  void onWindowClose() {
    if (!Platform.isWindows || !_enabled) {
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
