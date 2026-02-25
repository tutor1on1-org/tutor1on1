import 'package:flutter/material.dart';
import 'package:family_teacher/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

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
  final _loginPassword = TextEditingController();
  final _teacherUsername = TextEditingController();
  final _teacherPassword = TextEditingController();
  final _teacherRecoveryEmail = TextEditingController();
  final _teacherDisplayName = TextEditingController();
  final _teacherBio = TextEditingController();
  final _teacherAvatarUrl = TextEditingController();
  final _teacherContact = TextEditingController();
  final _studentUsername = TextEditingController();
  final _studentPassword = TextEditingController();
  final _studentRecoveryEmail = TextEditingController();
  bool _teacherContactPublished = false;

  @override
  void dispose() {
    _loginUsername.dispose();
    _loginPassword.dispose();
    _teacherUsername.dispose();
    _teacherPassword.dispose();
    _teacherRecoveryEmail.dispose();
    _teacherDisplayName.dispose();
    _teacherBio.dispose();
    _teacherAvatarUrl.dispose();
    _teacherContact.dispose();
    _studentUsername.dispose();
    _studentPassword.dispose();
    _studentRecoveryEmail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 3,
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
              Tab(text: l10n.registerStudentTab),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildLogin(context),
            _buildRegisterTeacher(context),
            _buildRegisterStudent(context),
          ],
        ),
      ),
    );
  }

  Widget _buildLogin(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildLanguageSelector(context),
        const SizedBox(height: 16),
        TextField(
          key: const Key('login_username'),
          controller: _loginUsername,
          decoration: InputDecoration(labelText: l10n.usernameLabel),
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          autocorrect: false,
        ),
        TextField(
          key: const Key('login_password'),
          controller: _loginPassword,
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
    );
  }

  Widget _buildRegisterTeacher(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildLanguageSelector(context),
        const SizedBox(height: 8),
        Text(
          l10n.email2faHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('register_teacher_username'),
          controller: _teacherUsername,
          decoration: InputDecoration(labelText: l10n.usernameLabel),
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          autocorrect: false,
        ),
        TextField(
          key: const Key('register_teacher_password'),
          controller: _teacherPassword,
          decoration: InputDecoration(labelText: l10n.pinLabel),
          obscureText: true,
          textInputAction: TextInputAction.next,
        ),
        TextField(
          key: const Key('register_teacher_recovery_email'),
          controller: _teacherRecoveryEmail,
          decoration: InputDecoration(labelText: l10n.recoveryEmailLabel),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
        ),
        TextField(
          key: const Key('register_teacher_display_name'),
          controller: _teacherDisplayName,
          decoration: InputDecoration(labelText: l10n.displayNameLabel),
          textInputAction: TextInputAction.next,
        ),
        TextField(
          key: const Key('register_teacher_bio'),
          controller: _teacherBio,
          decoration: InputDecoration(labelText: l10n.bioLabel),
          textInputAction: TextInputAction.next,
        ),
        TextField(
          key: const Key('register_teacher_avatar'),
          controller: _teacherAvatarUrl,
          decoration: InputDecoration(labelText: l10n.avatarUrlLabel),
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.url,
        ),
        TextField(
          key: const Key('register_teacher_contact'),
          controller: _teacherContact,
          decoration: InputDecoration(labelText: l10n.contactLabel),
          textInputAction: TextInputAction.done,
        ),
        SwitchListTile(
          value: _teacherContactPublished,
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.contactPublishedLabel),
          onChanged: (value) {
            setState(() => _teacherContactPublished = value);
          },
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          key: const Key('register_teacher_button'),
          onPressed: () => _handleRegisterTeacher(context),
          child: Text(l10n.registerTeacherButton),
        ),
      ],
    );
  }

  Widget _buildRegisterStudent(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildLanguageSelector(context),
        const SizedBox(height: 8),
        Text(
          l10n.email2faHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('register_student_username'),
          controller: _studentUsername,
          decoration: InputDecoration(labelText: l10n.usernameLabel),
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          autocorrect: false,
        ),
        TextField(
          key: const Key('register_student_password'),
          controller: _studentPassword,
          decoration: InputDecoration(labelText: l10n.pinLabel),
          obscureText: true,
          textInputAction: TextInputAction.next,
        ),
        TextField(
          key: const Key('register_student_recovery_email'),
          controller: _studentRecoveryEmail,
          decoration: InputDecoration(labelText: l10n.recoveryEmailLabel),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _handleRegisterStudent(context),
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          key: const Key('register_student_button'),
          onPressed: () => _handleRegisterStudent(context),
          child: Text(l10n.registerStudentButton),
        ),
      ],
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
          label: '馃寪',
          tooltip: l10n.languageSystem,
          selected: locale.isEmpty,
        ),
        const SizedBox(width: 8),
        _languageButton(
          context: context,
          locale: 'en',
          label: '馃嚭馃嚫',
          tooltip: l10n.languageEnglish,
          selected: locale == 'en',
        ),
        const SizedBox(width: 8),
        _languageButton(
          context: context,
          locale: 'zh',
          label: '馃嚚馃嚦',
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

  bool _ensureUsername(BuildContext context, String username) {
    final l10n = AppLocalizations.of(context)!;
    if (username.trim().isEmpty) {
      _showMessage(context, l10n.usernameRequired);
      return false;
    }
    return true;
  }

  bool _ensureRecoveryEmail(BuildContext context, String email) {
    final l10n = AppLocalizations.of(context)!;
    if (email.trim().isEmpty) {
      _showMessage(context, l10n.emailRequired);
      return false;
    }
    return true;
  }

  bool _ensurePassword(BuildContext context, String password) {
    final l10n = AppLocalizations.of(context)!;
    if (password.trim().isEmpty) {
      _showMessage(context, l10n.passwordRequired);
      return false;
    }
    return true;
  }

  Future<void> _handleLogin(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final username = _loginUsername.text;
    final password = _loginPassword.text;
    if (!_ensureUsername(context, username) ||
        !_ensurePassword(context, password)) {
      return;
    }
    final auth = context.read<AuthController>();
    final ok = await auth.login(username, password);
    if (!ok && mounted) {
      _showMessage(context, auth.lastError ?? l10n.invalidLogin);
    }
  }

  Future<void> _handleRegisterTeacher(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final username = _teacherUsername.text;
    final password = _teacherPassword.text;
    final recoveryEmail = _teacherRecoveryEmail.text;
    final displayName = _teacherDisplayName.text.trim();
    if (!_ensureUsername(context, username) ||
        !_ensurePassword(context, password) ||
        !_ensureRecoveryEmail(context, recoveryEmail)) {
      return;
    }
    if (displayName.isEmpty) {
      _showMessage(context, l10n.displayNameRequired);
      return;
    }
    final auth = context.read<AuthController>();
    final user = await auth.registerTeacher(
      username: username,
      email: recoveryEmail,
      password: password,
      displayName: displayName,
      bio: _teacherBio.text,
      avatarUrl: _teacherAvatarUrl.text,
      contact: _teacherContact.text,
      contactPublished: _teacherContactPublished,
    );
    if (user == null && mounted) {
      _showMessage(context, auth.lastError ?? l10n.registrationFailed);
    }
  }

  Future<void> _handleRegisterStudent(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final username = _studentUsername.text;
    final password = _studentPassword.text;
    final recoveryEmail = _studentRecoveryEmail.text;
    if (!_ensureUsername(context, username) ||
        !_ensurePassword(context, password) ||
        !_ensureRecoveryEmail(context, recoveryEmail)) {
      return;
    }
    final auth = context.read<AuthController>();
    final user = await auth.registerStudent(
      username: username,
      email: recoveryEmail,
      password: password,
    );
    if (user == null && mounted) {
      _showMessage(context, auth.lastError ?? l10n.registrationFailed);
    }
  }
}
