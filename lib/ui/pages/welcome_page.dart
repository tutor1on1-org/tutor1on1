import 'package:flutter/material.dart';
import 'package:family_teacher/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../state/auth_controller.dart';
import '../../state/settings_controller.dart';
import '../app_settings_page.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _loginUsername = TextEditingController();
  final _loginPin = TextEditingController();
  final _registerUsername = TextEditingController();
  final _registerPin = TextEditingController();
  bool? _hasTeacher;

  @override
  void dispose() {
    _loginUsername.dispose();
    _loginPin.dispose();
    _registerUsername.dispose();
    _registerPin.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadTeacherStatus();
  }

  Future<void> _loadTeacherStatus() async {
    final db = context.read<AppDatabase>();
    bool hasTeacher = true;
    try {
      hasTeacher = await db.hasAnyTeacher();
    } catch (_) {
      hasTeacher = true;
    }
    if (mounted) {
      setState(() => _hasTeacher = hasTeacher);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasTeacher = _hasTeacher ?? true;
    if (hasTeacher) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.appTitle),
          actions: [
            IconButton(
              key: const Key('open_settings'),
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SettingsPage(),
                  ),
                );
              },
            ),
          ],
        ),
        body: _buildLogin(context),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.appTitle),
          actions: [
            IconButton(
              key: const Key('open_settings'),
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SettingsPage(),
                  ),
                );
              },
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.loginTab),
              Tab(text: l10n.registerTeacherTab),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildLogin(context),
            _buildRegister(context),
          ],
        ),
      ),
    );
  }

  Widget _buildLogin(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildLanguageSelector(context),
          const SizedBox(height: 16),
          TextField(
            key: const Key('login_username'),
            controller: _loginUsername,
            decoration: InputDecoration(labelText: l10n.usernameLabel),
          ),
          TextField(
            key: const Key('login_pin'),
            controller: _loginPin,
            decoration: InputDecoration(labelText: l10n.pinLabel),
            obscureText: true,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _handleLogin(context),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            key: const Key('login_button'),
            onPressed: () => _handleLogin(context),
            child: Text(l10n.loginButton),
          ),
        ],
      ),
    );
  }

  Widget _buildRegister(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildLanguageSelector(context),
          const SizedBox(height: 16),
          TextField(
            key: const Key('register_username'),
            controller: _registerUsername,
            decoration: InputDecoration(labelText: l10n.usernameLabel),
          ),
          TextField(
            key: const Key('register_pin'),
            controller: _registerPin,
            decoration: InputDecoration(labelText: l10n.pinLabel),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            key: const Key('register_button'),
            onPressed: () async {
              final auth = context.read<AuthController>();
              final user = await auth.registerTeacher(
                _registerUsername.text,
                _registerPin.text,
              );
              if (user == null && mounted) {
                _showMessage(context, l10n.usernameExists);
              }
            },
            child: Text(l10n.createTeacherButton),
          ),
        ],
      ),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildLanguageSelector(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsController>().settings;
    final locale = (settings?.locale ?? '').trim();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _languageButton(
          context: context,
          locale: null,
          label: '🌐',
          tooltip: l10n.languageSystem,
          selected: locale.isEmpty,
        ),
        const SizedBox(width: 8),
        _languageButton(
          context: context,
          locale: 'en',
          label: '🇺🇸',
          tooltip: l10n.languageEnglish,
          selected: locale == 'en',
        ),
        const SizedBox(width: 8),
        _languageButton(
          context: context,
          locale: 'zh',
          label: '🇨🇳',
          tooltip: l10n.languageChinese,
          selected: locale == 'zh',
        ),
      ],
    );
  }

  Widget _languageButton({
    required BuildContext context,
    required String? locale,
    required String label,
    required String tooltip,
    required bool selected,
  }) {
    final settingsController = context.read<SettingsController>();
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          side: BorderSide(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
          ),
        ),
        onPressed: () async {
          await settingsController.updateLocale(locale);
        },
        child: Text(label, style: const TextStyle(fontSize: 18)),
      ),
    );
  }

  Future<void> _handleLogin(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.read<AuthController>();
    final ok = await auth.login(
      _loginUsername.text,
      _loginPin.text,
    );
    if (!ok && mounted) {
      _showMessage(context, l10n.invalidLogin);
    }
  }
}
