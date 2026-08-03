import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/app_database.dart';
import '../services/app_services.dart';
import '../services/browser_exclusive_lock.dart';
import '../services/browser_connectivity_events.dart';
import '../state/auth_controller.dart';

class ContinuousSyncHost extends StatefulWidget {
  const ContinuousSyncHost({super.key, required this.child});

  final Widget child;

  @override
  State<ContinuousSyncHost> createState() => _ContinuousSyncHostState();
}

class _ContinuousSyncHostState extends State<ContinuousSyncHost>
    with WidgetsBindingObserver {
  static const _interval = Duration(seconds: 30);

  Timer? _timer;
  StreamSubscription<void>? _onlineSubscription;
  bool _syncing = false;
  int? _scheduledUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_interval, (_) => unawaited(_syncIfReady()));
    _onlineSubscription = browserOnlineEvents.listen((_) {
      unawaited(_syncIfReady());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _onlineSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncIfReady());
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().currentUser;
    if (_scheduledUserId != user?.id) {
      _scheduledUserId = user?.id;
      if (user != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_syncIfReady());
          }
        });
      }
    }
    return widget.child;
  }

  Future<void> _syncIfReady() async {
    if (!mounted || _syncing) {
      return;
    }
    final user = context.read<AuthController>().currentUser;
    if (!_canSync(user)) {
      return;
    }
    _syncing = true;
    try {
      final services = context.read<AppServices>();
      final syncUser = user!;
      await tryWithBrowserExclusiveLock<bool>(
        browserSyncLockName(syncUser.remoteUserId!),
        () async {
          await services.enrollmentSyncService.syncIfReady(
            currentUser: syncUser,
          );
          await services.sessionSyncService.syncIfReady(
            currentUser: syncUser,
          );
          return true;
        },
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'Tutor1on1 continuous sync',
          context: ErrorDescription('while synchronizing browser state'),
        ),
      );
    } finally {
      _syncing = false;
    }
  }

  bool _canSync(User? user) {
    if (user == null || (user.remoteUserId ?? 0) <= 0) {
      return false;
    }
    return user.role == 'teacher' || user.role == 'student';
  }
}
