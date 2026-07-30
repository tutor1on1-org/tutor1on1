import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

abstract interface class WindowLifecycleLogSink {
  Future<void> append(Map<String, Object?> record);
}

class JsonlWindowLifecycleLogSink implements WindowLifecycleLogSink {
  JsonlWindowLifecycleLogSink(
    this.file, {
    this.maxBytes = 2 * 1024 * 1024,
  }) : assert(maxBytes > 0);

  final File file;
  final int maxBytes;

  @override
  Future<void> append(Map<String, Object?> record) async {
    final directory = Directory(p.dirname(file.path));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    if (await file.exists() && await file.length() >= maxBytes) {
      final rotatedFile = File('${file.path}.1');
      if (await rotatedFile.exists()) {
        await rotatedFile.delete();
      }
      await file.rename(rotatedFile.path);
    }
    await file.writeAsString(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
    );
  }
}

abstract interface class WindowDiagnosticsBridge {
  void addListener(WindowListener listener);
  void removeListener(WindowListener listener);
  Future<Map<String, Object?>> readSnapshot();
}

class DefaultWindowDiagnosticsBridge implements WindowDiagnosticsBridge {
  DefaultWindowDiagnosticsBridge({
    this.queryTimeout = const Duration(seconds: 2),
  });

  final Duration queryTimeout;

  @override
  void addListener(WindowListener listener) {
    windowManager.addListener(listener);
  }

  @override
  void removeListener(WindowListener listener) {
    windowManager.removeListener(listener);
  }

  @override
  Future<Map<String, Object?>> readSnapshot() async {
    final errors = <String>[];

    Future<T?> read<T>(
      String name,
      Future<T> Function() query,
    ) async {
      try {
        return await query().timeout(queryTimeout);
      } on TimeoutException {
        errors.add('$name: timed out after ${queryTimeout.inMilliseconds} ms');
        return null;
      } catch (error) {
        errors.add('$name: $error');
        return null;
      }
    }

    final focusedRead = read<bool>('isFocused', windowManager.isFocused);
    final visibleRead = read<bool>('isVisible', windowManager.isVisible);
    final minimizedRead = read<bool>('isMinimized', windowManager.isMinimized);
    final fullScreenRead =
        read<bool>('isFullScreen', windowManager.isFullScreen);
    final boundsRead = read<Rect>('getBounds', windowManager.getBounds);
    final focused = await focusedRead;
    final visible = await visibleRead;
    final minimized = await minimizedRead;
    final fullScreen = await fullScreenRead;
    final bounds = await boundsRead;

    return <String, Object?>{
      'window_focused': focused,
      'window_visible': visible,
      'window_minimized': minimized,
      'window_full_screen': fullScreen,
      if (bounds != null)
        'window_bounds': <String, double>{
          'left': bounds.left,
          'top': bounds.top,
          'width': bounds.width,
          'height': bounds.height,
        },
      if (errors.isNotEmpty) 'window_query_errors': errors,
    };
  }
}

class WindowResumeGapDetector {
  WindowResumeGapDetector({
    this.minimumResumeGap = const Duration(seconds: 45),
  });

  final Duration minimumResumeGap;
  DateTime? _lastObservation;

  Duration? observe(DateTime now) {
    final previous = _lastObservation;
    _lastObservation = now;
    if (previous == null) {
      return null;
    }
    final elapsed = now.difference(previous);
    if (elapsed <= minimumResumeGap) {
      return null;
    }
    return elapsed;
  }
}

class WindowLifecycleDiagnostics with WidgetsBindingObserver, WindowListener {
  WindowLifecycleDiagnostics({
    required WindowLifecycleLogSink sink,
    WindowDiagnosticsBridge? bridge,
    DateTime Function()? clock,
    Duration heartbeatInterval = const Duration(seconds: 15),
    Duration minimumResumeGap = const Duration(seconds: 45),
    Duration operationTimeout = const Duration(seconds: 5),
  })  : _sink = sink,
        _bridge = bridge ?? DefaultWindowDiagnosticsBridge(),
        _clock = clock ?? DateTime.now,
        _heartbeatInterval = heartbeatInterval,
        _operationTimeout = operationTimeout,
        _gapDetector = WindowResumeGapDetector(
          minimumResumeGap: minimumResumeGap,
        );

  final WindowLifecycleLogSink _sink;
  final WindowDiagnosticsBridge _bridge;
  final DateTime Function() _clock;
  final Duration _heartbeatInterval;
  final Duration _operationTimeout;
  final WindowResumeGapDetector _gapDetector;

  Future<void> _writeQueue = Future<void>.value();
  Timer? _heartbeatTimer;
  bool _started = false;
  int _sequence = 0;
  int _resumeToken = 0;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    try {
      WidgetsBinding.instance.addObserver(this);
      _bridge.addListener(this);
      _gapDetector.observe(_clock());
      _heartbeatTimer = Timer.periodic(
        _heartbeatInterval,
        (_) => checkForExecutionGap(),
      );
      _record('startup');
      await flush();
    } catch (_) {
      _heartbeatTimer?.cancel();
      _bridge.removeListener(this);
      WidgetsBinding.instance.removeObserver(this);
      _started = false;
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_started) {
      return;
    }
    _started = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _bridge.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    await flush();
  }

  @visibleForTesting
  Future<void> flush() => _writeQueue;

  @visibleForTesting
  void checkForExecutionGap() {
    if (!_started) {
      return;
    }
    final gap = _gapDetector.observe(_clock());
    if (gap == null) {
      return;
    }
    final token = ++_resumeToken;
    _record(
      'execution_gap',
      details: <String, Object?>{
        'gap_ms': gap.inMilliseconds,
        'resume_token': token,
      },
    );
    _recordPostResumeFrame(
      trigger: 'execution_gap',
      resumeToken: token,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started) {
      return;
    }
    final token =
        state == AppLifecycleState.resumed ? ++_resumeToken : _resumeToken;
    _record(
      'app_lifecycle',
      details: <String, Object?>{
        'state': state.name,
        if (state == AppLifecycleState.resumed) 'resume_token': token,
      },
    );
    if (state == AppLifecycleState.resumed) {
      _recordPostResumeFrame(
        trigger: 'app_lifecycle',
        resumeToken: token,
      );
    }
  }

  @override
  void didChangeMetrics() {
    _record('display_metrics_changed');
  }

  @override
  void onWindowFocus() {
    _record('window_focus');
  }

  @override
  void onWindowBlur() {
    _record('window_blur');
  }

  @override
  void onWindowRestore() {
    _record('window_restore');
  }

  @override
  void onWindowEnterFullScreen() {
    _record('window_enter_full_screen');
  }

  @override
  void onWindowLeaveFullScreen() {
    _record('window_leave_full_screen');
  }

  void _recordPostResumeFrame({
    required String trigger,
    required int resumeToken,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_started) {
        return;
      }
      _record(
        'post_resume_frame',
        details: <String, Object?>{
          'trigger': trigger,
          'resume_token': resumeToken,
        },
      );
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _record(
    String event, {
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    if (!_started) {
      return;
    }
    final sequence = ++_sequence;
    final occurredAt = _clock().toUtc();
    final detailsCopy = Map<String, Object?>.from(details);
    _writeQueue = _writeQueue.then((_) async {
      try {
        final record = <String, Object?>{
          'created_at_utc': occurredAt.toIso8601String(),
          'sequence': sequence,
          'event': event,
          'app_lifecycle_state': WidgetsBinding.instance.lifecycleState?.name,
          ...detailsCopy,
          ...await _readWindowSnapshot(),
          ..._readFlutterViewSnapshot(),
        };
        await _sink.append(record).timeout(_operationTimeout);
      } catch (error, stackTrace) {
        debugPrint(
          'Window lifecycle diagnostics failed for $event: '
          '$error\n$stackTrace',
        );
      }
    });
  }

  Future<Map<String, Object?>> _readWindowSnapshot() async {
    try {
      return await _bridge.readSnapshot().timeout(_operationTimeout);
    } on TimeoutException {
      return <String, Object?>{
        'window_snapshot_error':
            'timed out after ${_operationTimeout.inMilliseconds} ms',
      };
    } catch (error) {
      return <String, Object?>{
        'window_snapshot_error': error.toString(),
      };
    }
  }

  Map<String, Object?> _readFlutterViewSnapshot() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) {
      return const <String, Object?>{};
    }
    final view = views.first;
    return <String, Object?>{
      'view_physical_width': view.physicalSize.width,
      'view_physical_height': view.physicalSize.height,
      'view_device_pixel_ratio': view.devicePixelRatio,
    };
  }
}
