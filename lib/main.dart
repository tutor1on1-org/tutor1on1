import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_bootstrap.dart';
import 'services/single_instance_service.dart';
import 'ui/widgets/restart_widget.dart';

final SingleInstanceService _singleInstanceService =
    SingleInstanceService('family_teacher');
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final acquired = await _singleInstanceService.acquire();
  if (!acquired) {
    exit(0);
  }

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      title: 'Family Teacher',
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
