import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../services/app_services.dart';
import '../services/marketplace_api_service.dart';
import '../services/screen_lock_service.dart';
import '../state/auth_controller.dart';
import '../state/study_mode_controller.dart';
import '../l10n/app_localizations.dart';

class AppQuitFlow {
  const AppQuitFlow._();

  static Future<bool> handleQuit(BuildContext context) async {
    final confirmed = await confirmTeacherPinIfRequired(context);
    if (!confirmed) {
      return false;
    }
    await _quitApp();
    return true;
  }

  static Future<bool> confirmTeacherPinIfRequired(BuildContext context) async {
    final studyMode = Provider.of<StudyModeController?>(
      context,
      listen: false,
    );
    if (studyMode == null) {
      return true;
    }
    await _refreshStudyModeStateIfPossible(
      context,
      studyMode: studyMode,
    );
    if (!studyMode.requiresTeacherPin) {
      return true;
    }
    return _confirmTeacherPinWithCurrentState(
      context,
      studyMode: studyMode,
    );
  }

  static Future<bool> confirmTeacherPin(BuildContext context) async {
    final studyMode = context.read<StudyModeController?>();
    if (studyMode == null) {
      return true;
    }
    await _refreshStudyModeStateIfPossible(
      context,
      studyMode: studyMode,
    );
    if (!studyMode.requiresTeacherPin) {
      return true;
    }
    return _confirmTeacherPinWithCurrentState(
      context,
      studyMode: studyMode,
    );
  }

  static Future<bool> _confirmTeacherPinWithCurrentState(
    BuildContext context, {
    required StudyModeController studyMode,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.read<AuthController>();
    final user = auth.currentUser;
    if (user == null ||
        user.role != 'student' ||
        (user.remoteUserId ?? 0) <= 0) {
      if (context.mounted) {
        _showMessage(context, l10n.notLoggedInMessage);
      }
      return false;
    }

    final pin = await _promptForPin(context);
    if (pin == null || pin.isEmpty) {
      return false;
    }
    return _verifyTeacherPin(
      context,
      pin: pin,
      studyMode: studyMode,
    );
  }

  static Future<void> _refreshStudyModeStateIfPossible(
    BuildContext context, {
    required StudyModeController studyMode,
  }) async {
    final auth = context.read<AuthController>();
    final user = auth.currentUser;
    if (user == null ||
        user.role != 'student' ||
        (user.remoteUserId ?? 0) <= 0) {
      await studyMode.clear();
      return;
    }
    final hadTeacherPinRequirement = studyMode.requiresTeacherPin;
    final services = context.read<AppServices>();
    final api = MarketplaceApiService(secureStorage: services.secureStorage);
    try {
      final snapshot = await services.deviceIdentityService.snapshot();
      final response = await api.heartbeatStudentDevice(
        deviceKey: snapshot.deviceKey,
        deviceName: snapshot.deviceName,
        platform: snapshot.platform,
        timezoneName: snapshot.timezoneName,
        timezoneOffsetMinutes: snapshot.timezoneOffsetMinutes,
        localWeekday: snapshot.localWeekday,
        localMinuteOfDay: snapshot.localMinuteOfDay,
        currentStudyModeEnabled: studyMode.enabled,
        appVersion: snapshot.appVersion,
      );
      await studyMode.applyHeartbeat(user, response);
    } on Object catch (error) {
      if (hadTeacherPinRequirement && context.mounted) {
        _showMessage(
          context,
          'Failed to refresh study mode state before quit: $error',
        );
      }
    }
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

  static Future<bool> _verifyTeacherPin(
    BuildContext context, {
    required String pin,
    required StudyModeController studyMode,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final services = context.read<AppServices>();
    final api = MarketplaceApiService(secureStorage: services.secureStorage);
    try {
      final snapshot = await services.deviceIdentityService.snapshot();
      await api.verifyStudentStudyModeControlPin(
        controlPin: pin,
        localWeekday: snapshot.localWeekday,
        localMinuteOfDay: snapshot.localMinuteOfDay,
      );
      return true;
    } on MarketplaceApiException catch (error) {
      if (error.statusCode == 403) {
        if (context.mounted) {
          _showMessage(context, l10n.invalidPinMessage);
        }
        return false;
      }
      if (error.statusCode == 409) {
        await studyMode.clear();
        return true;
      }
      if (context.mounted) {
        _showMessage(
            context, 'Teacher PIN verification failed: ${error.message}');
      }
      return false;
    } on Object catch (error) {
      if (context.mounted) {
        _showMessage(context, 'Teacher PIN verification failed: $error');
      }
      return false;
    }
  }
}
