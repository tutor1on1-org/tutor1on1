import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_services.dart';
import '../services/browser_exclusive_lock.dart';
import '../services/exit_sync_service.dart';
import '../services/session_sync_service.dart';
import '../state/auth_controller.dart';

class AppQuitFlow {
  const AppQuitFlow._();

  static const ExitSyncService _exitSyncService = ExitSyncService();

  static Future<bool> handleQuit(BuildContext context) async {
    final confirmed = await confirmTeacherPinIfRequired(context);
    if (!confirmed) {
      return false;
    }
    final synced = await _runFinalSync(
      context,
      actionLabel: 'quit',
    );
    if (!synced) {
      return false;
    }
    if (context.mounted) {
      _showMessage(
        context,
        'All changes are synchronized; this browser tab can now be closed.',
      );
    }
    return true;
  }

  static Future<bool> handleLogout(BuildContext context) async {
    final confirmed = await confirmTeacherPinIfRequired(context);
    if (!confirmed) {
      return false;
    }
    final auth = context.read<AuthController>();
    await _runFinalSync(
      context,
      actionLabel: 'logout',
      actionContinuesOnFailure: true,
    );
    await auth.logout();
    return true;
  }

  static Future<bool> confirmTeacherPinIfRequired(BuildContext context) async {
    return true;
  }

  static Future<bool> confirmTeacherPin(BuildContext context) async {
    return true;
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  static Future<bool> _runFinalSync(
    BuildContext context, {
    required String actionLabel,
    bool actionContinuesOnFailure = false,
  }) async {
    final auth = context.read<AuthController>();
    final user = auth.currentUser;
    if (user == null) {
      return true;
    }
    final services = context.read<AppServices>();
    final navigator = Navigator.of(context, rootNavigator: true);
    var dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope<void>(
          canPop: false,
          child: AlertDialog(
            title: Text('Sync before $actionLabel'),
            content: const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Syncing local and server changes...'),
                ),
              ],
            ),
          ),
        ),
      ).then((_) {
        dialogOpen = false;
      }),
    );
    await Future<void>.delayed(Duration.zero);
    try {
      await services.sessionService.waitForInFlightTutorActions();
      if (!context.mounted) {
        return false;
      }
      await runWithBrowserExclusiveLock<void>(
        browserSyncLockName(user.remoteUserId ?? 0),
        () async {
          await _exitSyncService.syncBeforeExit(
            user: user,
            runSessionSync: ({
              required currentUser,
              onProgress,
              mode = SessionSyncMode.full,
            }) {
              return services.sessionSyncService.syncNow(
                currentUser: currentUser,
                password: '',
                onProgress: onProgress,
                mode: mode,
              );
            },
          );
        },
      );
      return true;
    } on Object catch (error) {
      if (context.mounted) {
        final failure = _describeExitSyncFailure(
          actionLabel: actionLabel,
          error: error,
          actionContinuesOnFailure: actionContinuesOnFailure,
        );
        _showMessage(context, failure);
      }
      return false;
    } finally {
      if (dialogOpen && navigator.mounted) {
        navigator.pop();
      }
    }
  }

  static String _describeExitSyncFailure({
    required String actionLabel,
    required Object error,
    required bool actionContinuesOnFailure,
  }) {
    final raw = '$error'.trim();
    if (actionContinuesOnFailure) {
      if (raw.isEmpty) {
        return 'Logged out locally, but the final sync failed.';
      }
      return 'Logged out locally, but the final sync failed: $raw';
    }
    if (raw.isEmpty) {
      return 'Could not $actionLabel because the final sync failed.';
    }
    return 'Could not $actionLabel: $raw';
  }
}
