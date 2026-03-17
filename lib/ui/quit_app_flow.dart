import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../db/app_database.dart';
import '../security/pin_hasher.dart';
import '../services/screen_lock_service.dart';
import '../state/auth_controller.dart';
import '../l10n/app_localizations.dart';

class AppQuitFlow {
  const AppQuitFlow._();

  static Future<bool> handleQuit(
    BuildContext context, {
    required bool requireTeacherPin,
  }) async {
    if (requireTeacherPin) {
      final confirmed = await confirmTeacherPin(context);
      if (!confirmed) {
        return false;
      }
    }
    await _quitApp();
    return true;
  }

  static Future<bool> confirmTeacherPin(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.read<AuthController>();
    final db = context.read<AppDatabase>();
    final user = auth.currentUser;
    if (user == null) {
      if (context.mounted) {
        _showMessage(context, l10n.notLoggedInMessage);
      }
      return false;
    }

    User? teacher;
    if (user.role == 'teacher') {
      teacher = user;
    } else if (user.teacherId != null) {
      teacher = await db.getUserById(user.teacherId!);
    }

    if (teacher == null) {
      if (context.mounted) {
        _showMessage(context, l10n.teacherNotFoundMessage);
      }
      return false;
    }

    final pin = await _promptForPin(context);
    if (pin == null || pin.isEmpty) {
      return false;
    }

    final hash = PinHasher.hash(pin);
    if (hash != teacher.pinHash) {
      if (context.mounted) {
        _showMessage(context, l10n.invalidPinMessage);
      }
      return false;
    }

    return true;
  }

  static Future<String?> _promptForPin(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.teacherPinTitle),
        content: TextField(
          controller: controller,
          obscureText: true,
          keyboardType: TextInputType.visiblePassword,
          decoration: InputDecoration(labelText: l10n.pinLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(
              controller.text.trim(),
            ),
            child: Text(l10n.confirmButton),
          ),
        ],
      ),
    );
    return result;
  }

  static Future<void> _quitApp() async {
    if (Platform.isAndroid || Platform.isIOS) {
      SystemNavigator.pop();
      return;
    }
    try {
      await ScreenLockService.instance.allowCloseOnce();
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } catch (_) {}
    exit(0);
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
