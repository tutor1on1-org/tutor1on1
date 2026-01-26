import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:family_teacher/l10n/app_localizations.dart';

import '../db/app_database.dart';
import '../llm/llm_models.dart';
import '../llm/llm_providers.dart';
import '../security/hash_utils.dart';
import '../security/pin_hasher.dart';
import '../services/app_services.dart';
import '../services/tts_service.dart';
import '../state/auth_controller.dart';
import '../state/settings_controller.dart';
import 'pages/llm_logs_page.dart';
import 'pages/tts_logs_page.dart';
import 'widgets/restart_widget.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _timeoutController = TextEditingController();
  final _maxTokensController = TextEditingController();
  final _ttsDelayController = TextEditingController();
  final _ttsAudioPathController = TextEditingController();
  final _logDirectoryController = TextEditingController();
  final _apiKeyController = TextEditingController();
  String _mode = LlmMode.liveRecord.value;
  bool _initialized = false;
  bool _apiKeyLoaded = false;
  String? _providerId;
  String? _modelSelection;

  @override
  void dispose() {
    _timeoutController.dispose();
    _maxTokensController.dispose();
    _ttsDelayController.dispose();
    _ttsAudioPathController.dispose();
    _logDirectoryController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settingsController = context.watch<SettingsController>();
    final settings = settingsController.settings;
    final services = context.read<AppServices>();
    final auth = context.read<AuthController>();
    final currentUser = auth.currentUser;

    if (settings == null || settingsController.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final envBaseUrl = Platform.environment['OPENAI_BASE_URL']?.trim() ?? '';
    final envModel = Platform.environment['OPENAI_MODEL']?.trim() ?? '';
    final hasEnvDefaults = envBaseUrl.isNotEmpty || envModel.isNotEmpty;
    final providers = LlmProviders.defaultProviders(
      envBaseUrl: envBaseUrl,
      envModel: envModel,
    );

    if (!_initialized) {
      final provider = LlmProviders.findById(
            providers,
            settings.providerId,
          ) ??
          LlmProviders.findByBaseUrl(providers, settings.baseUrl) ??
          providers.first;
      _providerId = provider.id;
      _modelSelection = settings.model.trim().isNotEmpty
          ? settings.model.trim()
          : (provider.models.isNotEmpty ? provider.models.first : '');
      _timeoutController.text = settings.timeoutSeconds.toString();
      _maxTokensController.text = settings.maxTokens.toString();
      _ttsDelayController.text =
          (settings.ttsInitialDelayMs / 1000).round().toString();
      _ttsAudioPathController.text = settings.ttsAudioPath ?? '';
      _logDirectoryController.text = settings.logDirectory ?? '';
      _mode = settings.llmMode;
      _initialized = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.llmSettingsTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey(_providerId ?? providers.first.id),
            initialValue: _providerId ?? providers.first.id,
            decoration: InputDecoration(labelText: l10n.providerLabel),
            items: providers
                .map(
                  (provider) => DropdownMenuItem(
                    value: provider.id,
                    child: Text(provider.label),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              final provider =
                  LlmProviders.findById(providers, value) ?? providers.first;
              setState(() {
                _providerId = provider.id;
                _modelSelection = provider.models.isNotEmpty
                    ? provider.models.first
                    : _modelSelection;
              });
            },
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final provider = LlmProviders.findById(providers, _providerId) ??
                  providers.first;
              return InputDecorator(
                decoration: InputDecoration(labelText: l10n.baseUrlLabel),
                child: SelectableText(provider.baseUrl),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildModelDropdown(
            db: services.db,
            l10n: l10n,
            providers: providers,
            settings: settings,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () {
                  final provider = LlmProviders.findById(
                        providers,
                        'siliconflow',
                      ) ??
                      providers.first;
                  setState(() {
                    _providerId = provider.id;
                    _modelSelection = provider.models.isNotEmpty
                        ? provider.models.first
                        : _modelSelection;
                  });
                },
                child: Text(l10n.useSiliconflowDefaults),
              ),
              TextButton(
                onPressed: hasEnvDefaults
                    ? () {
                        final provider = LlmProviders.findById(
                              providers,
                              'env',
                            ) ??
                            providers.first;
                        setState(() {
                          _providerId = provider.id;
                          _modelSelection = provider.models.isNotEmpty
                              ? provider.models.first
                              : _modelSelection;
                        });
                      }
                    : null,
                child: Text(l10n.useEnvDefaults),
              ),
            ],
          ),
          TextField(
            decoration:
                InputDecoration(labelText: l10n.timeoutSecondsLabel),
            controller: _timeoutController,
            keyboardType: TextInputType.number,
          ),
          TextField(
            decoration: InputDecoration(labelText: l10n.maxTokensLabel),
            controller: _maxTokensController,
            keyboardType: TextInputType.number,
          ),
          TextField(
            decoration:
                InputDecoration(labelText: l10n.ttsInitialDelayLabel),
            controller: _ttsDelayController,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration:
                      InputDecoration(labelText: l10n.ttsAudioPathLabel),
                  controller: _ttsAudioPathController,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  final selected =
                      await FilePicker.platform.getDirectoryPath();
                  if (selected == null) {
                    return;
                  }
                  setState(() {
                    _ttsAudioPathController.text = selected;
                  });
                },
                child: Text(l10n.browseButton),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration:
                      InputDecoration(labelText: l10n.logDirectoryLabel),
                  controller: _logDirectoryController,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  final selected =
                      await FilePicker.platform.getDirectoryPath();
                  if (selected == null) {
                    return;
                  }
                  setState(() {
                    _logDirectoryController.text = selected;
                  });
                },
                child: Text(l10n.browseButton),
              ),
            ],
          ),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: InputDecoration(labelText: l10n.llmLogPathLabel),
            child: SelectableText(settings.llmLogPath ?? ''),
          ),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: InputDecoration(labelText: l10n.ttsLogPathLabel),
            child: SelectableText(settings.ttsLogPath ?? ''),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _mode,
            decoration: InputDecoration(labelText: l10n.llmModeLabel),
            items: [
              DropdownMenuItem(
                value: 'LIVE_RECORD',
                child: Text(l10n.llmModeLiveRecord),
              ),
              DropdownMenuItem(
                value: 'REPLAY',
                child: Text(l10n.llmModeReplay),
              ),
              DropdownMenuItem(
                value: 'LIVE',
                child: Text(l10n.llmModeLive),
              ),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() => _mode = value);
            },
          ),
          const SizedBox(height: 12),
          FutureBuilder<String?>(
            future: services.secureStorage.readApiKey(),
            builder: (context, snapshot) {
              final key = snapshot.data ?? '';
              if (!_apiKeyLoaded) {
                _apiKeyController.text = key;
                _apiKeyLoaded = true;
              }
              return TextField(
                controller: _apiKeyController,
                obscureText: true,
                decoration: InputDecoration(labelText: l10n.apiKeyLabel),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton(
                onPressed: () async {
                  final apiKey = _apiKeyController.text.trim();
                  final provider =
                      LlmProviders.findById(providers, _providerId) ??
                          providers.first;
                  final model = (_modelSelection ?? '').trim().isNotEmpty
                      ? _modelSelection!.trim()
                      : (provider.models.isNotEmpty
                          ? provider.models.first
                          : settings.model.trim());
                  if (model.trim().isEmpty) {
                    _showMessage(context, l10n.modelMissingMessage);
                    return;
                  }
                  final audioPath = _ttsAudioPathController.text.trim();
                  final resolvedAudioPath = audioPath.isEmpty
                      ? (settings.ttsAudioPath ?? '').trim()
                      : audioPath;
                  final logDir = _logDirectoryController.text.trim();
                  final resolvedLogDir = logDir.isEmpty
                      ? (settings.logDirectory ?? '').trim()
                      : logDir;
                  await settingsController.update(
                    providerId: provider.id,
                    baseUrl: provider.baseUrl,
                    model: model,
                    timeoutSeconds:
                        int.tryParse(_timeoutController.text.trim()) ?? 60,
                    maxTokens:
                        int.tryParse(_maxTokensController.text.trim()) ?? 8000,
                    ttsInitialDelayMs:
                        _parseDelayMs(settings.ttsInitialDelayMs),
                    ttsAudioPath: resolvedAudioPath,
                    logDirectory: resolvedLogDir,
                    llmMode: _mode,
                  );
                  if (apiKey.isNotEmpty) {
                    await services.secureStorage.writeApiKey(apiKey);
                    final hash = sha256Hex(apiKey);
                    await services.secureStorage
                        .writeApiKeyForHash(hash, apiKey);
                    final updated = settingsController.settings;
                    if (updated != null) {
                      final insertId = await services.db.insertApiConfig(
                        baseUrl: updated.baseUrl,
                        model: updated.model,
                        apiKeyHash: hash,
                      );
                      if (context.mounted) {
                        final message = insertId == 0
                            ? l10n.configAlreadySavedMessage
                            : l10n.configSavedMessage;
                        _showMessage(context, message);
                      }
                    }
                  }
                },
                child: Text(l10n.saveLlmConfigButton),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () async {
                  await services.secureStorage.deleteApiKey();
                  if (context.mounted) {
                    _apiKeyController.clear();
                    _showMessage(context, l10n.apiKeyClearedMessage);
                  }
                },
                child: Text(l10n.clearKeyButton),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () async {
                  final envKey = Platform.environment['OPENAI_API_KEY'];
                  if (envKey == null || envKey.trim().isEmpty) {
                    if (context.mounted) {
                      _showMessage(context, l10n.apiKeyNotFoundMessage);
                    }
                    return;
                  }
                  if (context.mounted) {
                    _apiKeyController.text = envKey;
                    _showMessage(context, l10n.apiKeyLoadedMessage);
                  }
                },
                child: Text(l10n.loadKeyFromEnvButton),
              ),
            ],
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LlmLogsPage(),
                ),
              );
            },
            child: Text(l10n.viewLlmLogsButton),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TtsLogsPage(),
                ),
              );
            },
            child: Text(l10n.viewTtsLogsButton),
          ),
          TextButton(
            onPressed: () async {
              final result =
                  await services.ttsService.playLastAudio();
              if (!context.mounted) {
                return;
              }
              switch (result.status) {
                case TtsTestStatus.played:
                  _showMessage(
                    context,
                    l10n.ttsTestStartedMessage(result.path ?? ''),
                  );
                  break;
                case TtsTestStatus.missing:
                  _showMessage(context, l10n.ttsTestMissingMessage);
                  break;
                case TtsTestStatus.failed:
                  _showMessage(context, l10n.ttsTestFailedMessage);
                  break;
              }
            },
            child: Text(l10n.ttsTestButton),
          ),
          if (currentUser != null) ...[
            const Divider(height: 32),
            Text(
              l10n.passwordSectionTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            ElevatedButton(
              onPressed: () => _showChangePasswordDialog(
                context,
                currentUser,
              ),
              child: Text(l10n.changePasswordButton),
            ),
            if (currentUser.role == 'teacher')
              ElevatedButton(
                onPressed: () => _showChangeStudentPasswordDialog(
                  context,
                  currentUser,
                ),
                child: Text(l10n.changeStudentPasswordButton),
              ),
          ],
          const Divider(height: 32),
          Text(
            l10n.savedApiConfigsTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          StreamBuilder<List<ApiConfig>>(
            stream: services.db.watchApiConfigs(),
            builder: (context, snapshot) {
              final configs = snapshot.data ?? [];
              if (configs.isEmpty) {
                return Text(l10n.noSavedConfigs);
              }
              return Column(
                children: configs.map((config) {
                  final shortHash = config.apiKeyHash.length > 8
                      ? config.apiKeyHash.substring(0, 8)
                      : config.apiKeyHash;
                  final provider =
                      LlmProviders.findByBaseUrl(providers, config.baseUrl);
                  final providerLabel = provider?.label ?? config.baseUrl;
                  return ListTile(
                    title: Text('$providerLabel - ${config.model}'),
                    subtitle: Text(
                      '${l10n.baseUrlLabel}: ${config.baseUrl}\n${l10n.keyHashLabel(shortHash)}',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () async {
                            final provider = LlmProviders.findByBaseUrl(
                                  providers,
                                  config.baseUrl,
                                ) ??
                                providers.first;
                            setState(() {
                              _providerId = provider.id;
                              _modelSelection = config.model;
                            });
                            final key = await services.secureStorage
                                .readApiKeyForHash(config.apiKeyHash);
                            if (key == null || key.trim().isEmpty) {
                              _apiKeyController.clear();
                              if (context.mounted) {
                                _showMessage(
                                  context,
                                  l10n.apiKeyMissingForConfig,
                                );
                              }
                            } else {
                              _apiKeyController.text = key;
                            }
                            if (context.mounted) {
                              setState(() {});
                            }
                          },
                          child: Text(l10n.loadButton),
                        ),
                        IconButton(
                          tooltip: l10n.deleteButton,
                          icon: const Icon(Icons.delete),
                          onPressed: () async {
                            await services.db.deleteApiConfigById(config.id);
                            final remaining = await services.db
                                .countApiConfigsByHash(config.apiKeyHash);
                            if (remaining == 0) {
                              await services.secureStorage
                                  .deleteApiKeyForHash(config.apiKeyHash);
                            }
                            if (context.mounted) {
                              _showMessage(context, l10n.configDeletedMessage);
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const Divider(height: 32),
          Text(
            l10n.backupRestoreTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          ElevatedButton(
            onPressed: () async {
              final path = await FilePicker.platform.saveFile(
                dialogTitle: l10n.exportDbDialogTitle,
                fileName: 'family_teacher_backup.db',
              );
              if (path == null) {
                return;
              }
              await services.backupService.exportTo(File(path));
              if (context.mounted) {
                _showMessage(context, l10n.backupExportedMessage);
              }
            },
            child: Text(l10n.exportDbButton),
          ),
          ElevatedButton(
            onPressed: () async {
              final result = await FilePicker.platform.pickFiles(
                dialogTitle: l10n.restoreDbDialogTitle,
              );
              if (result == null || result.files.isEmpty) {
                return;
              }
              final confirm = await _confirmRestore(context);
              if (!confirm) {
                return;
              }
              await services.backupService
                  .restoreFrom(File(result.files.single.path!));
              if (context.mounted) {
                _showMessage(context, l10n.restoreCompletedMessage);
                RestartWidget.restartApp(context);
              }
            },
            child: Text(l10n.restoreDbButton),
          ),
          const Divider(height: 32),
          Text(
            l10n.appSectionTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          ElevatedButton(
            onPressed: _handleQuit,
            child: Text(l10n.quitButton),
          ),
        ],
      ),
    );
  }

  Widget _buildModelDropdown({
    required AppDatabase db,
    required AppLocalizations l10n,
    required List<LlmProvider> providers,
    required AppSetting settings,
  }) {
    final provider = LlmProviders.findById(providers, _providerId) ??
        providers.first;
    return StreamBuilder<List<ApiConfig>>(
      stream: db.watchApiConfigs(),
      builder: (context, snapshot) {
        final configs = snapshot.data ?? [];
        final models = <String>{
          ...provider.models.map((model) => model.trim()).where(
                (model) => model.isNotEmpty,
              ),
          ...configs
              .where(
                (config) =>
                    _normalizeBaseUrl(config.baseUrl) ==
                    _normalizeBaseUrl(provider.baseUrl),
              )
              .map((config) => config.model.trim())
              .where((model) => model.isNotEmpty),
          if (settings.model.trim().isNotEmpty) settings.model.trim(),
        }.toList()
          ..sort();

        if (models.isEmpty) {
          return InputDecorator(
            decoration: InputDecoration(labelText: l10n.modelLabel),
            child: Text(l10n.noModelsAvailable),
          );
        }

        final selected = (_modelSelection?.trim().isNotEmpty == true)
            ? _modelSelection!.trim()
            : settings.model.trim();
        final value = models.contains(selected) ? selected : models.first;
        if ((_modelSelection == null ||
                !_modelSelection!.trim().isNotEmpty ||
                !models.contains(_modelSelection!.trim())) &&
            value.isNotEmpty) {
          _modelSelection = value;
        }
        return DropdownButtonFormField<String>(
          key: ValueKey('${provider.id}-$value'),
          initialValue: value,
          decoration: InputDecoration(labelText: l10n.modelLabel),
          items: models
              .map(
                (model) => DropdownMenuItem(
                  value: model,
                  child: Text(model),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() => _modelSelection = value);
          },
        );
      },
    );
  }

  String _normalizeBaseUrl(String value) {
    var trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  Future<bool> _confirmRestore(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.restoreConfirmTitle),
        content: Text(l10n.restoreConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.restoreConfirmButton),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  int _parseDelayMs(int fallbackMs) {
    final raw = _ttsDelayController.text.trim();
    if (raw.isEmpty) {
      return fallbackMs;
    }
    final seconds = int.tryParse(raw);
    if (seconds == null) {
      return fallbackMs;
    }
    if (seconds <= 0) {
      return 0;
    }
    return seconds * 1000;
  }

  Future<void> _showChangePasswordDialog(
    BuildContext context,
    User user,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    final db = context.read<AppDatabase>();
    final auth = context.read<AuthController>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.changePasswordTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentController,
              decoration:
                  InputDecoration(labelText: l10n.currentPasswordLabel),
              obscureText: true,
            ),
            TextField(
              controller: newController,
              decoration: InputDecoration(labelText: l10n.newPasswordLabel),
              obscureText: true,
            ),
            TextField(
              controller: confirmController,
              decoration:
                  InputDecoration(labelText: l10n.confirmPasswordLabel),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () async {
              final currentPin = currentController.text.trim();
              final newPin = newController.text.trim();
              final confirmPin = confirmController.text.trim();
              if (currentPin.isEmpty ||
                  newPin.isEmpty ||
                  confirmPin.isEmpty) {
                return;
              }
              if (newPin != confirmPin) {
                _showMessage(context, l10n.passwordMismatchMessage);
                return;
              }
              final latest = await db.getUserById(user.id);
              if (latest == null) {
                return;
              }
              final hashed = PinHasher.hash(currentPin);
              if (hashed != latest.pinHash) {
                _showMessage(context, l10n.passwordInvalidMessage);
                return;
              }
              await db.updateUserPin(
                userId: user.id,
                pinHash: PinHasher.hash(newPin),
              );
              await auth.refreshCurrentUser();
              if (context.mounted) {
                Navigator.of(dialogContext).pop();
                _showMessage(context, l10n.passwordUpdatedMessage);
              }
            },
            child: Text(l10n.confirmButton),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangeStudentPasswordDialog(
    BuildContext context,
    User teacher,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    final students = await db.watchStudents(teacher.id).first;
    if (students.isEmpty) {
      if (context.mounted) {
        _showMessage(context, l10n.noStudents);
      }
      return;
    }
    final teacherPinController = TextEditingController();
    final studentPinController = TextEditingController();
    User selectedStudent = students.first;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.changeStudentPasswordTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<User>(
                value: selectedStudent,
                decoration:
                    InputDecoration(labelText: l10n.selectStudentLabel),
                items: students
                    .map(
                      (student) => DropdownMenuItem(
                        value: student,
                        child: Text(student.username),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() => selectedStudent = value);
                },
              ),
              TextField(
                controller: studentPinController,
                decoration:
                    InputDecoration(labelText: l10n.studentPasswordLabel),
                obscureText: true,
              ),
              TextField(
                controller: teacherPinController,
                decoration:
                    InputDecoration(labelText: l10n.teacherPasswordLabel),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancelButton),
            ),
            ElevatedButton(
              onPressed: () async {
                final teacherPin = teacherPinController.text.trim();
                final studentPin = studentPinController.text.trim();
                if (teacherPin.isEmpty || studentPin.isEmpty) {
                  return;
                }
                final latestTeacher = await db.getUserById(teacher.id);
                if (latestTeacher == null) {
                  return;
                }
                final hashed = PinHasher.hash(teacherPin);
                if (hashed != latestTeacher.pinHash) {
                  _showMessage(context, l10n.passwordInvalidMessage);
                  return;
                }
                await db.updateUserPin(
                  userId: selectedStudent.id,
                  pinHash: PinHasher.hash(studentPin),
                );
                if (context.mounted) {
                  Navigator.of(dialogContext).pop();
                  _showMessage(context, l10n.passwordUpdatedMessage);
                }
              },
              child: Text(l10n.confirmButton),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleQuit() async {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.read<AuthController>();
    final db = context.read<AppDatabase>();
    final user = auth.currentUser;
    if (user == null) {
      if (context.mounted) {
        _showMessage(context, l10n.notLoggedInMessage);
      }
      return;
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
      return;
    }

    final pin = await _promptForPin(context);
    if (pin == null || pin.isEmpty) {
      return;
    }

    final hash = PinHasher.hash(pin);
    if (hash != teacher.pinHash) {
      if (context.mounted) {
        _showMessage(context, l10n.invalidPinMessage);
      }
      return;
    }

    await _quitApp();
  }

  Future<String?> _promptForPin(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.teacherPinTitle),
        content: TextField(
          controller: controller,
          obscureText: true,
          keyboardType: TextInputType.number,
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

  Future<void> _quitApp() async {
    if (Platform.isAndroid || Platform.isIOS) {
      SystemNavigator.pop();
      return;
    }
    try {
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } catch (_) {}
    exit(0);
  }
}

