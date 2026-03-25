import 'package:flutter/material.dart';
import 'package:tutor1on1/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../services/app_services.dart';
import '../../services/app_version_service.dart';
import '../../services/marketplace_api_service.dart';
import '../../state/auth_controller.dart';
import '../../state/settings_controller.dart';
import '../app_close_button.dart';
import '../app_settings_page.dart';
import '../widgets/language_selector.dart';

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
  List<SubjectLabelSummary> _subjectLabels = const <SubjectLabelSummary>[];
  final Set<int> _selectedTeacherSubjectLabelIds = <int>{};
  late final Future<AppVersionInfo> _appVersionFuture =
      AppVersionService.load();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadSubjectLabels();
    });
  }

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

  Future<void> _loadSubjectLabels() async {
    final services = context.read<AppServices>();
    final api = MarketplaceApiService(secureStorage: services.secureStorage);
    try {
      final labels = await api.listSubjectLabels();
      if (!mounted) {
        return;
      }
      setState(() {
        _subjectLabels = labels;
        if (_selectedTeacherSubjectLabelIds.isEmpty) {
          final others = labels.where((label) => label.slug == 'others');
          if (others.isNotEmpty) {
            _selectedTeacherSubjectLabelIds.add(others.first.subjectLabelId);
          }
        }
      });
    } catch (_) {
      // Registration stays usable even if subject labels cannot be fetched.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.appTitle),
          actions: buildAppBarActionsWithClose(
            context,
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
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('forgot_password_button'),
            onPressed: () => _openRequestRecoveryDialog(context),
            child: Text(l10n.forgotPasswordButton),
          ),
        ),
        const SizedBox(height: 12),
        _buildAppVersionInfo(context),
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
        const SizedBox(height: 8),
        const Text(
          'Subject labels',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (_subjectLabels.isEmpty)
          const Text('Loading subject labels...')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final label in _subjectLabels)
                FilterChip(
                  label: Text(label.name),
                  selected: _selectedTeacherSubjectLabelIds
                      .contains(label.subjectLabelId),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedTeacherSubjectLabelIds
                            .add(label.subjectLabelId);
                      } else {
                        _selectedTeacherSubjectLabelIds
                            .remove(label.subjectLabelId);
                      }
                    });
                  },
                ),
            ],
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
        const SizedBox(height: 12),
        _buildAppVersionInfo(context),
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
        const SizedBox(height: 12),
        _buildAppVersionInfo(context),
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
    final settingsController = context.read<SettingsController>();
    return Align(
      alignment: Alignment.centerRight,
      child: LanguageSelector(
        localeCode: settings?.locale,
        width: 220,
        onChanged: (value) async {
          await settingsController.updateLocale(value);
          if (!context.mounted) {
            return;
          }
          _showMessage(context, l10n.languageSavedMessage);
        },
      ),
    );
  }

  Widget _buildAppVersionInfo(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final style = Theme.of(context).textTheme.bodySmall;
    return FutureBuilder<AppVersionInfo>(
      future: _appVersionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Text(l10n.loadingLabel, style: style);
        }
        if (snapshot.hasError) {
          return Text(
            l10n.appVersionLoadFailed('${snapshot.error}'),
            style: style?.copyWith(color: Colors.redAccent) ??
                const TextStyle(color: Colors.redAccent),
          );
        }
        final versionInfo = snapshot.data;
        if (versionInfo == null) {
          return Text(
            l10n.appVersionLoadFailed('Version payload missing.'),
            style: style?.copyWith(color: Colors.redAccent) ??
                const TextStyle(color: Colors.redAccent),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.appVersionLabel}: ${versionInfo.appVersion}',
              style: style,
            ),
            Text(
              '${l10n.publicReleaseTagLabel}: ${versionInfo.releaseTag}',
              style: style,
            ),
          ],
        );
      },
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
      return;
    }
    if (!mounted) {
      return;
    }
    final user = auth.currentUser;
    if (user == null) {
      return;
    }
    final services = context.read<AppServices>();
    try {
      await services.sessionSyncService.prepareForAutoSync(
        currentUser: user,
        password: password,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(context, l10n.sessionSyncFailed('$error'));
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
      subjectLabelIds: _selectedTeacherSubjectLabelIds.toList(growable: false),
      bio: _teacherBio.text,
      avatarUrl: _teacherAvatarUrl.text,
      contact: _teacherContact.text,
      contactPublished: _teacherContactPublished,
    );
    if (user == null && mounted) {
      _showMessage(context, auth.lastError ?? l10n.registrationFailed);
      return;
    }
    if (!mounted || user == null) {
      return;
    }
    final services = context.read<AppServices>();
    try {
      await services.sessionSyncService.prepareForAutoSync(
        currentUser: user,
        password: password,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(context, l10n.sessionSyncFailed('$error'));
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
      return;
    }
    if (!mounted || user == null) {
      return;
    }
    final services = context.read<AppServices>();
    try {
      await services.sessionSyncService.prepareForAutoSync(
        currentUser: user,
        password: password,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(context, l10n.sessionSyncFailed('$error'));
    }
  }

  Future<void> _openRequestRecoveryDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final emailController = TextEditingController();
    String? email;
    try {
      email = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          var sending = false;
          String? errorText;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(l10n.requestRecoveryDialogTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.requestRecoveryDialogBody,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                      labelText: l10n.recoveryEmailLabel,
                      errorText: errorText,
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) async {
                      if (sending) {
                        return;
                      }
                      final email = emailController.text.trim();
                      if (email.isEmpty) {
                        setDialogState(() {
                          errorText = l10n.emailRequired;
                        });
                        return;
                      }
                      setDialogState(() {
                        sending = true;
                        errorText = null;
                      });
                      final auth = context.read<AuthController>();
                      final ok = await auth.requestRecovery(email);
                      if (!context.mounted) {
                        return;
                      }
                      if (!ok) {
                        setDialogState(() {
                          sending = false;
                          errorText = auth.lastError ?? l10n.requestFailedTitle;
                        });
                        return;
                      }
                      Navigator.of(dialogContext).pop(email);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      sending ? null : () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.cancelButton),
                ),
                ElevatedButton(
                  onPressed: sending
                      ? null
                      : () async {
                          final email = emailController.text.trim();
                          if (email.isEmpty) {
                            setDialogState(() {
                              errorText = l10n.emailRequired;
                            });
                            return;
                          }
                          setDialogState(() {
                            sending = true;
                            errorText = null;
                          });
                          final auth = context.read<AuthController>();
                          final ok = await auth.requestRecovery(email);
                          if (!context.mounted) {
                            return;
                          }
                          if (!ok) {
                            setDialogState(() {
                              sending = false;
                              errorText =
                                  auth.lastError ?? l10n.requestFailedTitle;
                            });
                            return;
                          }
                          Navigator.of(dialogContext).pop(email);
                        },
                  child: Text(l10n.requestRecoveryButton),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      emailController.dispose();
    }
    if (!mounted || email == null) {
      return;
    }
    _showMessage(context, l10n.recoveryEmailSentMessage);
    await _openResetPasswordDialog(context, initialEmail: email);
  }

  Future<void> _openResetPasswordDialog(
    BuildContext context, {
    String initialEmail = '',
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final emailController = TextEditingController(text: initialEmail);
    final tokenController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool resetCompleted = false;
    try {
      resetCompleted = await showDialog<bool>(
            context: context,
            builder: (dialogContext) {
              var submitting = false;
              String? errorText;
              return StatefulBuilder(
                builder: (context, setDialogState) => AlertDialog(
                  title: Text(l10n.resetPasswordWithTokenTitle),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.recoveryEmailSpamHint),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emailController,
                        decoration: InputDecoration(
                          labelText: l10n.recoveryEmailLabel,
                        ),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                      ),
                      TextField(
                        controller: tokenController,
                        decoration: InputDecoration(
                          labelText: l10n.recoveryTokenLabel,
                          errorText: errorText,
                        ),
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                      ),
                      TextField(
                        controller: newPasswordController,
                        decoration: InputDecoration(
                          labelText: l10n.newPasswordLabel,
                        ),
                        obscureText: true,
                        textInputAction: TextInputAction.next,
                      ),
                      TextField(
                        controller: confirmPasswordController,
                        decoration: InputDecoration(
                          labelText: l10n.confirmPasswordLabel,
                        ),
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) async {
                          if (submitting) {
                            return;
                          }
                          final email = emailController.text.trim();
                          final token = tokenController.text.trim();
                          final newPassword = newPasswordController.text;
                          final confirmPassword =
                              confirmPasswordController.text;
                          if (email.isEmpty) {
                            setDialogState(() {
                              errorText = l10n.emailRequired;
                            });
                            return;
                          }
                          if (token.isEmpty) {
                            setDialogState(() {
                              errorText = l10n.recoveryTokenRequired;
                            });
                            return;
                          }
                          if (newPassword.trim().isEmpty) {
                            setDialogState(() {
                              errorText = l10n.passwordRequired;
                            });
                            return;
                          }
                          if (newPassword != confirmPassword) {
                            setDialogState(() {
                              errorText = l10n.passwordMismatchMessage;
                            });
                            return;
                          }
                          setDialogState(() {
                            submitting = true;
                            errorText = null;
                          });
                          final auth = context.read<AuthController>();
                          final ok = await auth.resetPassword(
                            email: email,
                            recoveryToken: token,
                            newPassword: newPassword,
                          );
                          if (!context.mounted) {
                            return;
                          }
                          if (!ok) {
                            setDialogState(() {
                              submitting = false;
                              errorText =
                                  auth.lastError ?? l10n.requestFailedTitle;
                            });
                            return;
                          }
                          Navigator.of(dialogContext).pop(true);
                        },
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: submitting
                          ? null
                          : () => Navigator.of(dialogContext).pop(),
                      child: Text(l10n.cancelButton),
                    ),
                    ElevatedButton(
                      onPressed: submitting
                          ? null
                          : () async {
                              final email = emailController.text.trim();
                              final token = tokenController.text.trim();
                              final newPassword = newPasswordController.text;
                              final confirmPassword =
                                  confirmPasswordController.text;
                              if (email.isEmpty) {
                                setDialogState(() {
                                  errorText = l10n.emailRequired;
                                });
                                return;
                              }
                              if (token.isEmpty) {
                                setDialogState(() {
                                  errorText = l10n.recoveryTokenRequired;
                                });
                                return;
                              }
                              if (newPassword.trim().isEmpty) {
                                setDialogState(() {
                                  errorText = l10n.passwordRequired;
                                });
                                return;
                              }
                              if (newPassword != confirmPassword) {
                                setDialogState(() {
                                  errorText = l10n.passwordMismatchMessage;
                                });
                                return;
                              }
                              setDialogState(() {
                                submitting = true;
                                errorText = null;
                              });
                              final auth = context.read<AuthController>();
                              final ok = await auth.resetPassword(
                                email: email,
                                recoveryToken: token,
                                newPassword: newPassword,
                              );
                              if (!context.mounted) {
                                return;
                              }
                              if (!ok) {
                                setDialogState(() {
                                  submitting = false;
                                  errorText =
                                      auth.lastError ?? l10n.requestFailedTitle;
                                });
                                return;
                              }
                              Navigator.of(dialogContext).pop(true);
                            },
                      child: Text(l10n.resetPasswordWithTokenButton),
                    ),
                  ],
                ),
              );
            },
          ) ??
          false;
    } finally {
      emailController.dispose();
      tokenController.dispose();
      newPasswordController.dispose();
      confirmPasswordController.dispose();
    }
    if (!mounted || !resetCompleted) {
      return;
    }
    _showMessage(context, l10n.resetPasswordSuccessMessage);
  }
}
