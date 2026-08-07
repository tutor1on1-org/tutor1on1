import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tutor1on1/l10n/app_language.dart';
import 'package:tutor1on1/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'services/app_services.dart';
import 'services/runtime_environment.dart';
import 'state/auth_controller.dart';
import 'state/settings_controller.dart';
import 'state/study_mode_controller.dart';
import 'ui/auth_session_guard.dart';
import 'ui/continuous_sync_host.dart';
import 'ui/pages/admin_home_page.dart';
import 'ui/pages/teacher_pending_page.dart';
import 'ui/pages/student_home_page.dart';
import 'ui/pages/teacher_home_page.dart';
import 'ui/pages/welcome_page.dart';

class Tutor1on1App extends StatelessWidget {
  const Tutor1on1App({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppServices>.value(value: services),
        Provider.value(value: services.db),
        ChangeNotifierProvider(
          create: (_) => StudyModeController(),
        ),
        ChangeNotifierProvider(
          create: (context) => AuthController(
            services.db,
            services.secureStorage,
            deviceIdentityService: services.deviceIdentityService,
            studyModeController: context.read<StudyModeController>(),
            authSessionValidator: () async {
              await services.marketplaceApiService.getAccountProfile();
            },
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsController(services.settingsRepository),
        ),
      ],
      child: Consumer2<SettingsController, StudyModeController>(
        builder: (context, settingsController, studyModeController, _) {
          final settings = settingsController.settings;
          return MaterialApp(
            onGenerateTitle: (context) => runtimeIsAgentTutor
                ? runtimeAppTitle
                : AppLocalizations.of(context)!.appTitle,
            locale: appLocaleFromSetting(settings?.locale),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => _BrowserStorageNotice(
              show: !services.browserStorageProtected,
              child: child ?? const SizedBox.shrink(),
            ),
            theme: buildTutor1on1Theme(),
            home: const ContinuousSyncHost(child: AuthGate()),
          );
        },
      ),
    );
  }
}

class _BrowserStorageNotice extends StatefulWidget {
  const _BrowserStorageNotice({required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  State<_BrowserStorageNotice> createState() => _BrowserStorageNoticeState();
}

class _BrowserStorageNoticeState extends State<_BrowserStorageNotice> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.show || _dismissed) {
      return widget.child;
    }
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        MaterialBanner(
          content: Text(l10n.browserStorageNotProtectedMessage),
          actions: [
            TextButton(
              onPressed: () => setState(() => _dismissed = true),
              child: Text(l10n.closeButton),
            ),
          ],
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  bool _wasAuthenticated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(validateActiveAuthSession(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthController>(
      builder: (context, auth, _) {
        final user = auth.currentUser;
        final authenticated = user != null;
        if (_wasAuthenticated && !authenticated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          });
        }
        _wasAuthenticated = authenticated;
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
