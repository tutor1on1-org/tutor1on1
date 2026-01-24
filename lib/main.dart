import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_bootstrap.dart';
import 'ui/widgets/restart_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
