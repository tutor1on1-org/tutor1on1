import 'package:flutter/material.dart';

import 'app_bootstrap.dart';
import 'ui/widgets/restart_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    RestartWidget(
      child: const AppBootstrap(),
    ),
  );
}
