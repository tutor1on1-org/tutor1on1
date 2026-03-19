import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

class ScreenLockService with WidgetsBindingObserver, WindowListener {
  static final ScreenLockService instance = ScreenLockService();

  ScreenLockService({
    this.lockDelay = const Duration(seconds: 10),
    StudyModePlatformBridge? bridge,
  }) : _bridge = bridge ?? DefaultStudyModePlatformBridge();

  final Duration lockDelay;
  final StudyModePlatformBridge _bridge;
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
  }

  Future<void> start() async {
    _enabled = true;
    WidgetsBinding.instance.addObserver(this);
    await _bridge.setScreenAwake(true);
    await _bridge.enableStudyUi();
    if (!_bridge.supportsDesktopWindowControls) {
      return;
    }

    _bridge.addWindowListener(this);
    await _bridge.setPreventClose(true);
    await _bridge.setAlwaysOnTop(true);
    if (_bridge.shouldUseFullScreenSoftMode) {
      await _bridge.setFullScreen(true);
    }
    if (_bridge.isWindows) {
      _watchTimer?.cancel();
      _watchTimer = Timer.periodic(lockDelay, (_) {
        unawaited(_enforceWindowsFocus());
      });
    }
  }

  Future<void> stop() async {
    WidgetsBinding.instance.removeObserver(this);
    _lockTimer?.cancel();
    _watchTimer?.cancel();
    _allowClose = false;
    _enabled = false;
    await _bridge.setScreenAwake(false);
    await _bridge.disableStudyUi();
    if (!_bridge.supportsDesktopWindowControls) {
      return;
    }

    _bridge.removeWindowListener(this);
    try {
      await _bridge.setPreventClose(false);
      await _bridge.setAlwaysOnTop(false);
      if (_bridge.shouldUseFullScreenSoftMode) {
        await _bridge.setFullScreen(false);
      }
    } catch (_) {}
  }

  Future<void> allowCloseOnce() async {
    if (!_bridge.supportsDesktopWindowControls) {
      return;
    }
    _allowClose = true;
    await _bridge.setPreventClose(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled || state != AppLifecycleState.resumed) {
      return;
    }
    unawaited(_reapplySoftMode());
  }

  @override
  void onWindowBlur() {
    if (!_enabled || !_bridge.supportsDesktopWindowControls) {
      return;
    }
    if (_bridge.isWindows) {
      _attemptRefocus();
      _startLockTimer();
    }
  }

  @override
  void onWindowFocus() {
    if (!_enabled) {
      return;
    }
    _lockTimer?.cancel();
    unawaited(_reapplyDesktopWindowState());
  }

  @override
  void onWindowClose() {
    if (!_enabled || !_bridge.supportsDesktopWindowControls || _allowClose) {
      return;
    }
    _attemptRefocus();
  }

  void _startLockTimer() {
    _lockTimer?.cancel();
    _lockTimer = Timer(lockDelay, () {
      unawaited(_lockWindowsIfBlurred());
    });
  }

  Future<void> _reapplySoftMode() async {
    await _bridge.setScreenAwake(true);
    await _bridge.enableStudyUi();
    await _reapplyDesktopWindowState();
  }

  Future<void> _reapplyDesktopWindowState() async {
    if (!_enabled || !_bridge.supportsDesktopWindowControls) {
      return;
    }
    final isTop = await _bridge.isAlwaysOnTop();
    if (!isTop) {
      await _bridge.setAlwaysOnTop(true);
    }
    if (_bridge.shouldUseFullScreenSoftMode) {
      final isFullScreen = await _bridge.isFullScreen();
      if (!isFullScreen) {
        await _bridge.setFullScreen(true);
      }
    }
  }

  Future<void> _enforceWindowsFocus() async {
    if (!_enabled || !_bridge.isWindows) {
      return;
    }
    final focused = await _bridge.isFocused();
    if (!focused) {
      _lockWindows();
      return;
    }
    final isTop = await _bridge.isAlwaysOnTop();
    if (!isTop) {
      await _bridge.setAlwaysOnTop(true);
    }
  }

  Future<void> _lockWindowsIfBlurred() async {
    if (!_enabled || !_bridge.isWindows) {
      return;
    }
    final focused = await _bridge.isFocused();
    if (!focused) {
      _lockWindows();
    }
  }

  Future<void> _attemptRefocus() async {
    try {
      await _bridge.show();
      await _bridge.focus();
    } catch (_) {}
  }

  void _lockWindows() {
    _bridge.lockWorkstation();
  }
}

abstract class StudyModePlatformBridge {
  bool get isWindows;
  bool get isAndroid;
  bool get isIOS;
  bool get isMacOS;
  bool get isLinux;

  bool get supportsDesktopWindowControls => isWindows || isMacOS || isLinux;
  bool get shouldUseFullScreenSoftMode => isMacOS || isLinux;

  void addWindowListener(WindowListener listener);
  void removeWindowListener(WindowListener listener);
  Future<void> setPreventClose(bool enabled);
  Future<void> setAlwaysOnTop(bool enabled);
  Future<void> setFullScreen(bool enabled);
  Future<bool> isFocused();
  Future<bool> isAlwaysOnTop();
  Future<bool> isFullScreen();
  Future<void> show();
  Future<void> focus();
  Future<void> setScreenAwake(bool enabled);
  Future<void> enableStudyUi();
  Future<void> disableStudyUi();
  void lockWorkstation();
}

class DefaultStudyModePlatformBridge implements StudyModePlatformBridge {
  @override
  bool get supportsDesktopWindowControls => isWindows || isMacOS || isLinux;

  @override
  bool get shouldUseFullScreenSoftMode => isMacOS || isLinux;

  @override
  bool get isWindows => Platform.isWindows;

  @override
  bool get isAndroid => Platform.isAndroid;

  @override
  bool get isIOS => Platform.isIOS;

  @override
  bool get isMacOS => Platform.isMacOS;

  @override
  bool get isLinux => Platform.isLinux;

  @override
  void addWindowListener(WindowListener listener) {
    if (!supportsDesktopWindowControls) {
      return;
    }
    windowManager.addListener(listener);
  }

  @override
  void removeWindowListener(WindowListener listener) {
    if (!supportsDesktopWindowControls) {
      return;
    }
    windowManager.removeListener(listener);
  }

  @override
  Future<void> setPreventClose(bool enabled) async {
    if (!supportsDesktopWindowControls) {
      return;
    }
    await windowManager.setPreventClose(enabled);
  }

  @override
  Future<void> setAlwaysOnTop(bool enabled) async {
    if (!supportsDesktopWindowControls) {
      return;
    }
    await windowManager.setAlwaysOnTop(enabled);
  }

  @override
  Future<void> setFullScreen(bool enabled) async {
    if (!shouldUseFullScreenSoftMode) {
      return;
    }
    await windowManager.setFullScreen(enabled);
  }

  @override
  Future<bool> isFocused() async {
    if (!supportsDesktopWindowControls) {
      return false;
    }
    return windowManager.isFocused();
  }

  @override
  Future<bool> isAlwaysOnTop() async {
    if (!supportsDesktopWindowControls) {
      return false;
    }
    return windowManager.isAlwaysOnTop();
  }

  @override
  Future<bool> isFullScreen() async {
    if (!shouldUseFullScreenSoftMode) {
      return false;
    }
    return windowManager.isFullScreen();
  }

  @override
  Future<void> show() async {
    if (!supportsDesktopWindowControls) {
      return;
    }
    await windowManager.show();
  }

  @override
  Future<void> focus() async {
    if (!supportsDesktopWindowControls) {
      return;
    }
    await windowManager.focus();
  }

  @override
  Future<void> setScreenAwake(bool enabled) async {
    await WakelockPlus.toggle(enable: enabled);
  }

  @override
  Future<void> enableStudyUi() async {
    if (isAndroid) {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );
      return;
    }
    if (isIOS) {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: const <SystemUiOverlay>[],
      );
    }
  }

  @override
  Future<void> disableStudyUi() async {
    if (!isAndroid && !isIOS) {
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void lockWorkstation() {
    if (!isWindows) {
      return;
    }
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final lock = user32.lookupFunction<Int32 Function(), int Function()>(
        'LockWorkStation',
      );
      lock();
    } catch (_) {}
  }
}

@visibleForTesting
class FakeStudyModePlatformBridge implements StudyModePlatformBridge {
  FakeStudyModePlatformBridge({
    this.isWindows = false,
    this.isAndroid = false,
    this.isIOS = false,
    this.isMacOS = false,
    this.isLinux = false,
    this.focused = true,
    this.alwaysOnTop = false,
    this.fullScreen = false,
  });

  @override
  final bool isWindows;

  @override
  final bool isAndroid;

  @override
  final bool isIOS;

  @override
  final bool isMacOS;

  @override
  final bool isLinux;

  bool focused;
  bool alwaysOnTop;
  bool fullScreen;
  bool preventClose = false;
  bool screenAwake = false;
  bool studyUiEnabled = false;
  bool workstationLocked = false;
  int addListenerCalls = 0;
  int removeListenerCalls = 0;
  int showCalls = 0;
  int focusCalls = 0;

  @override
  bool get supportsDesktopWindowControls => isWindows || isMacOS || isLinux;

  @override
  bool get shouldUseFullScreenSoftMode => isMacOS || isLinux;

  @override
  void addWindowListener(WindowListener listener) {
    addListenerCalls += 1;
  }

  @override
  void removeWindowListener(WindowListener listener) {
    removeListenerCalls += 1;
  }

  @override
  Future<void> setPreventClose(bool enabled) async {
    preventClose = enabled;
  }

  @override
  Future<void> setAlwaysOnTop(bool enabled) async {
    alwaysOnTop = enabled;
  }

  @override
  Future<void> setFullScreen(bool enabled) async {
    fullScreen = enabled;
  }

  @override
  Future<bool> isFocused() async => focused;

  @override
  Future<bool> isAlwaysOnTop() async => alwaysOnTop;

  @override
  Future<bool> isFullScreen() async => fullScreen;

  @override
  Future<void> show() async {
    showCalls += 1;
  }

  @override
  Future<void> focus() async {
    focusCalls += 1;
  }

  @override
  Future<void> setScreenAwake(bool enabled) async {
    screenAwake = enabled;
  }

  @override
  Future<void> enableStudyUi() async {
    studyUiEnabled = true;
  }

  @override
  Future<void> disableStudyUi() async {
    studyUiEnabled = false;
  }

  @override
  void lockWorkstation() {
    workstationLocked = true;
  }
}
