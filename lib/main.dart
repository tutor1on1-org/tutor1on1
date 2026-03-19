import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_bootstrap.dart';
import 'services/single_instance_service.dart';
import 'ui/widgets/restart_widget.dart';

final SingleInstanceService _singleInstanceService =
    SingleInstanceService('family_teacher');

bool get _supportsDesktopWindowing =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    final acquired = await _singleInstanceService.acquire();
    if (!acquired) {
      exit(0);
    }
  }

  if (_supportsDesktopWindowing) {
    await windowManager.ensureInitialized();
  }

  if (Platform.isWindows) {
    const windowOptions = WindowOptions(
      title: 'Tutor1on1',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setFullScreen(true);
    });
  }

  runApp(
    RestartWidget(
      child: const AppBootstrap(),
    ),
  );
}
