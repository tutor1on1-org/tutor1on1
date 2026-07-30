import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutor1on1/services/window_lifecycle_diagnostics.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('records resume state and the next rendered frame',
      (tester) async {
    final sink = _FakeWindowLifecycleLogSink();
    final bridge = _FakeWindowDiagnosticsBridge();
    final diagnostics = WindowLifecycleDiagnostics(
      sink: sink,
      bridge: bridge,
    );
    addTearDown(diagnostics.stop);

    await diagnostics.start();
    expect(bridge.listener, same(diagnostics));
    expect(sink.events, <String>['startup']);

    diagnostics.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await diagnostics.flush();
    expect(sink.events, <String>['startup', 'app_lifecycle']);
    expect(sink.records.last['state'], 'resumed');

    await tester.pump();
    await diagnostics.flush();
    expect(
      sink.events,
      <String>['startup', 'app_lifecycle', 'post_resume_frame'],
    );
    expect(sink.records.last['trigger'], 'app_lifecycle');

    await diagnostics.stop();
    expect(bridge.listener, isNull);
  });

  test('records ordered window state events', () async {
    final sink = _FakeWindowLifecycleLogSink();
    final bridge = _FakeWindowDiagnosticsBridge();
    final diagnostics = WindowLifecycleDiagnostics(
      sink: sink,
      bridge: bridge,
    );
    addTearDown(diagnostics.stop);

    await diagnostics.start();
    bridge.listener!
      ..onWindowBlur()
      ..onWindowFocus()
      ..onWindowEnterFullScreen()
      ..onWindowRestore()
      ..onWindowLeaveFullScreen();
    await diagnostics.flush();

    expect(
      sink.events,
      <String>[
        'startup',
        'window_blur',
        'window_focus',
        'window_enter_full_screen',
        'window_restore',
        'window_leave_full_screen',
      ],
    );
    expect(
      sink.records.map((record) => record['sequence']),
      orderedEquals(<int>[1, 2, 3, 4, 5, 6]),
    );
    expect(sink.records.last['window_full_screen'], isTrue);
  });

  testWidgets('records only abnormal execution gaps', (tester) async {
    var now = DateTime.utc(2026, 7, 30, 1);
    final sink = _FakeWindowLifecycleLogSink();
    final diagnostics = WindowLifecycleDiagnostics(
      sink: sink,
      bridge: _FakeWindowDiagnosticsBridge(),
      clock: () => now,
    );
    addTearDown(diagnostics.stop);

    await diagnostics.start();
    now = now.add(const Duration(seconds: 30));
    diagnostics.checkForExecutionGap();
    await diagnostics.flush();
    expect(sink.events, <String>['startup']);

    now = now.add(const Duration(seconds: 50));
    diagnostics.checkForExecutionGap();
    await diagnostics.flush();
    expect(sink.events, <String>['startup', 'execution_gap']);
    expect(sink.records.last['gap_ms'], 50000);

    await tester.pump();
    await diagnostics.flush();
    expect(sink.events.last, 'post_resume_frame');
    await diagnostics.stop();
  });

  test('recovers the event queue after a window snapshot timeout', () async {
    final sink = _FakeWindowLifecycleLogSink();
    final bridge = _FirstSnapshotHangsBridge();
    final diagnostics = WindowLifecycleDiagnostics(
      sink: sink,
      bridge: bridge,
      operationTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(diagnostics.stop);

    await diagnostics.start();
    expect(sink.events, <String>['startup']);
    expect(sink.records.single['window_snapshot_error'], contains('timed out'));

    bridge.listener!.onWindowFocus();
    await diagnostics.flush();
    expect(sink.events, <String>['startup', 'window_focus']);
  });

  test('rotates the JSONL log when it reaches its size cap', () async {
    final directory =
        await Directory.systemTemp.createTemp('window_lifecycle_log_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}events.jsonl');
    await file.writeAsString('old-record\n');
    final sink = JsonlWindowLifecycleLogSink(file, maxBytes: 1);

    await sink.append(<String, Object?>{'event': 'new-record'});

    expect(await File('${file.path}.1').readAsString(), 'old-record\n');
    expect(await file.readAsString(), contains('"event":"new-record"'));
  });
}

class _FakeWindowLifecycleLogSink implements WindowLifecycleLogSink {
  final List<Map<String, Object?>> records = <Map<String, Object?>>[];

  List<String> get events => records
      .map((record) => record['event']! as String)
      .toList(growable: false);

  @override
  Future<void> append(Map<String, Object?> record) async {
    records.add(Map<String, Object?>.from(record));
  }
}

class _FakeWindowDiagnosticsBridge implements WindowDiagnosticsBridge {
  WindowListener? listener;

  @override
  void addListener(WindowListener value) {
    listener = value;
  }

  @override
  Future<Map<String, Object?>> readSnapshot() async {
    return <String, Object?>{
      'window_focused': true,
      'window_visible': true,
      'window_minimized': false,
      'window_full_screen': true,
    };
  }

  @override
  void removeListener(WindowListener value) {
    if (identical(listener, value)) {
      listener = null;
    }
  }
}

class _FirstSnapshotHangsBridge extends _FakeWindowDiagnosticsBridge {
  var _snapshotCount = 0;

  @override
  Future<Map<String, Object?>> readSnapshot() {
    _snapshotCount += 1;
    if (_snapshotCount == 1) {
      return Completer<Map<String, Object?>>().future;
    }
    return super.readSnapshot();
  }
}
