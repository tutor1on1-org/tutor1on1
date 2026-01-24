import 'package:flutter/material.dart';

import 'app.dart';
import 'services/app_services.dart';

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late Future<AppServices> _servicesFuture;

  @override
  void initState() {
    super.initState();
    _servicesFuture = AppServices.create();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppServices>(
      future: _servicesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            home: Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError) {
          return MaterialApp(
            home: Scaffold(
              body: Center(
                child: Text('Failed to start app: ${snapshot.error}'),
              ),
            ),
          );
        }
        return FamilyTeacherApp(services: snapshot.data!);
      },
    );
  }
}
