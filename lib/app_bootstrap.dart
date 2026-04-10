import 'package:flutter/material.dart';

import 'app.dart';
import 'app_theme.dart';
import 'services/app_services.dart';
import 'ui/app_close_button.dart';

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
          return const _BootstrapShell(
            message: 'Starting Tutor1on1...',
            showProgress: true,
          );
        }
        if (snapshot.hasError) {
          return _BootstrapShell(
            message: 'Failed to start app.',
            detail: '${snapshot.error}',
          );
        }
        return Tutor1on1App(services: snapshot.data!);
      },
    );
  }
}

class _BootstrapShell extends StatelessWidget {
  const _BootstrapShell({
    required this.message,
    this.detail,
    this.showProgress = false,
  });

  final String message;
  final String? detail;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildTutor1on1Theme(),
      home: Builder(
        builder: (innerContext) {
          final theme = Theme.of(innerContext);
          return Scaffold(
            appBar: AppBar(
              title: const Text('Tutor1on1'),
              actions: buildAppBarActionsWithClose(innerContext),
            ),
            body: ColoredBox(
              color: theme.colorScheme.surface,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Card(
                    margin: const EdgeInsets.all(24),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message,
                            style: theme.textTheme.titleMedium,
                          ),
                          if ((detail ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            SelectableText(
                              detail!.trim(),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                          if (showProgress) ...[
                            const SizedBox(height: 16),
                            const LinearProgressIndicator(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
