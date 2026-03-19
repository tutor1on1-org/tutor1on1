import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:family_teacher/l10n/app_localizations.dart';

import 'services/app_services.dart';
import 'state/auth_controller.dart';
import 'state/settings_controller.dart';
import 'ui/quit_app_flow.dart';
import 'ui/pages/admin_home_page.dart';
import 'ui/pages/teacher_pending_page.dart';
import 'ui/pages/student_home_page.dart';
import 'ui/pages/teacher_home_page.dart';
import 'ui/pages/welcome_page.dart';

class FamilyTeacherApp extends StatelessWidget {
  const FamilyTeacherApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppServices>.value(value: services),
        Provider.value(value: services.db),
        ChangeNotifierProvider(
          create: (_) => AuthController(services.db, services.secureStorage),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsController(services.settingsRepository),
        ),
      ],
      child: Consumer<SettingsController>(
        builder: (context, settingsController, _) {
          final settings = settingsController.settings;
          Locale? locale;
          final localeCode = settings?.locale?.trim();
          if (localeCode != null && localeCode.isNotEmpty) {
            locale = Locale(localeCode);
          }
          return MaterialApp(
            onGenerateTitle: (context) =>
                AppLocalizations.of(context)!.appTitle,
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => _StudyModeExitGuard(
              enabled: settings?.studyModeEnabled ?? false,
              child: child ?? const SizedBox.shrink(),
            ),
            theme: ThemeData(
              useMaterial3: true,
              colorSchemeSeed: Colors.teal,
              fontFamily: 'Microsoft YaHei UI',
              fontFamilyFallback: const [
                'Microsoft YaHei',
                'Noto Sans CJK SC',
                'Source Han Sans SC',
                'PingFang SC',
                'SimHei',
              ],
            ),
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

class _StudyModeExitGuard extends StatefulWidget {
  const _StudyModeExitGuard({
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  State<_StudyModeExitGuard> createState() => _StudyModeExitGuardState();
}

class _StudyModeExitGuardState extends State<_StudyModeExitGuard> {
  bool _quitFlowRunning = false;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !widget.enabled,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !widget.enabled || _quitFlowRunning) {
          return;
        }
        _quitFlowRunning = true;
        unawaited(_handleStudyModeExit(context));
      },
      child: widget.child,
    );
  }

  Future<void> _handleStudyModeExit(BuildContext context) async {
    try {
      await AppQuitFlow.handleQuit(
        context,
        requireTeacherPin: false,
      );
    } finally {
      _quitFlowRunning = false;
    }
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthController>(
      builder: (context, auth, _) {
        final user = auth.currentUser;
        if (user == null) {
          return const WelcomePage();
        }
        if (user.role == 'admin') {
          return const AdminHomePage();
        }
        if (user.role == 'teacher') {
          return const TeacherHomePage();
        }
        if (user.role == 'teacher_pending' || user.role == 'teacher_rejected') {
          return TeacherPendingPage(role: user.role);
        }
        return const StudentHomePage();
      },
    );
  }
}
