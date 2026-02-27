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
import '../services/model_list_service.dart';
import '../services/screen_lock_service.dart';
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
  final _ttsTextLeadController = TextEditingController();
  final _ttsAudioPathController = TextEditingController();
  final _logDirectoryController = TextEditingController();
  final _apiKeyController = TextEditingController();
  String _mode = LlmMode.liveRecord.value;
  bool _initialized = false;
  String? _apiKeyLoadedForBaseUrl;
  String? _providerId;
  String? _textModelSelection;
  String? _ttsModelSelection;
  String? _sttModelSelection;
  bool _sttAutoSend = false;
  bool _enterToSend = true;
  bool _studyModeEnabled = false;
  bool _ttsModelOverride = false;
  bool _sttModelOverride = false;
  bool _modelsLoaded = false;
  bool _apiTesting = false;
  String? _apiTestError;
  List<String> _textModelOptions = const [];
  List<String> _ttsModelOptions = const [];
  List<String> _sttModelOptions = const [];

  @override
  void dispose() {
    _timeoutController.dispose();
    _maxTokensController.dispose();
    _ttsDelayController.dispose();
    _ttsTextLeadController.dispose();
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
      _textModelSelection = settings.model.trim().isNotEmpty
          ? settings.model.trim()
          : (provider.models.isNotEmpty ? provider.models.first : '');
      _ttsModelSelection = (settings.ttsModel ?? '').trim();
      _sttModelSelection = (settings.sttModel ?? '').trim();
      _timeoutController.text = settings.timeoutSeconds.toString();
      _maxTokensController.text = settings.maxTokens.toString();
      _ttsDelayController.text =
          (settings.ttsInitialDelayMs / 1000).round().toString();
      _ttsTextLeadController.text =
          (settings.ttsTextLeadMs / 1000).round().toString();
      _ttsAudioPathController.text = settings.ttsAudioPath ?? '';
      _logDirectoryController.text = settings.logDirectory ?? '';
      _mode = settings.llmMode;
      _sttAutoSend = settings.sttAutoSend;
      _enterToSend = settings.enterToSend;
      _studyModeEnabled = settings.studyModeEnabled;
      _initialized = true;
    }

    final provider = _resolveProvider(providers, settings);
    _maybeLoadApiKey(services, provider.baseUrl);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.settingsTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.generalTab),
              Tab(text: l10n.apisTab),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildGeneralTab(
              context: context,
              l10n: l10n,
              settings: settings,
              settingsController: settingsController,
              provider: provider,
              providers: providers,
              currentUser: currentUser,
              services: services,
            ),
            _buildApisTab(
              context: context,
              l10n: l10n,
              settings: settings,
              settingsController: settingsController,
              provider: provider,
              providers: providers,
              services: services,
            ),
          ],
        ),
      ),
    );
  }

  LlmProvider _resolveProvider(
    List<LlmProvider> providers,
    AppSetting settings,
  ) {
    return LlmProviders.findById(providers, _providerId) ??
        LlmProviders.findByBaseUrl(providers, settings.baseUrl) ??
        providers.first;
  }

  void _maybeLoadApiKey(AppServices services, String baseUrl) {
    final normalized = _normalizeBaseUrl(baseUrl);
    if (_apiKeyLoadedForBaseUrl == normalized) {
      return;
    }
    _apiKeyLoadedForBaseUrl = normalized;
    Future.microtask(() async {
      final key = await services.secureStorage.readApiKeyForBaseUrl(normalized);
      if (!mounted) {
        return;
      }
      setState(() {
        _apiKeyController.text = key ?? '';
      });
    });
  }

  Widget _buildGeneralTab({
    required BuildContext context,
    required AppLocalizations l10n,
    required AppSetting settings,
    required SettingsController settingsController,
    required LlmProvider provider,
    required List<LlmProvider> providers,
    required User? currentUser,
    required AppServices services,
  }) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.generalTab,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        TextField(
          decoration: InputDecoration(labelText: l10n.timeoutSecondsLabel),
          controller: _timeoutController,
          keyboardType: TextInputType.number,
        ),
        TextField(
          decoration: InputDecoration(labelText: l10n.maxTokensLabel),
          controller: _maxTokensController,
          keyboardType: TextInputType.number,
        ),
        TextField(
          decoration: InputDecoration(labelText: l10n.ttsInitialDelayLabel),
          controller: _ttsDelayController,
          keyboardType: TextInputType.number,
        ),
        TextField(
          decoration: InputDecoration(labelText: l10n.ttsTextLeadLabel),
          controller: _ttsTextLeadController,
          keyboardType: TextInputType.number,
        ),
        SwitchListTile(
          title: Text(l10n.sttAutoSendLabel),
          value: _sttAutoSend,
          onChanged: (value) => setState(() => _sttAutoSend = value),
        ),
        SwitchListTile(
          title: Text(l10n.enterToSendLabel),
          value: _enterToSend,
          onChanged: (value) => setState(() => _enterToSend = value),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(labelText: l10n.ttsAudioPathLabel),
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
                decoration: InputDecoration(labelText: l10n.logDirectoryLabel),
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
        ElevatedButton(
          onPressed: () async {
            final model = _resolveTextModel(provider, settings);
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
                  ttsModel: _resolveTtsModel(settings),
                  sttModel: _resolveSttModel(settings),
                  timeoutSeconds:
                      int.tryParse(_timeoutController.text.trim()) ?? 60,
                  maxTokens:
                      int.tryParse(_maxTokensController.text.trim()) ?? 8000,
                  ttsInitialDelayMs: _parseSecondsMs(
                    _ttsDelayController,
                    settings.ttsInitialDelayMs,
                  ),
                  ttsTextLeadMs: _parseSecondsMs(
                    _ttsTextLeadController,
                    settings.ttsTextLeadMs,
                  ),
                  ttsAudioPath: resolvedAudioPath,
                  logDirectory: resolvedLogDir,
                  llmMode: _mode,
                  sttAutoSend: _sttAutoSend,
                  enterToSend: _enterToSend,
                  studyModeEnabled: _studyModeEnabled,
                );
            if (context.mounted) {
              _showMessage(context, l10n.settingsSavedMessage);
            }
          },
          child: Text(l10n.saveSettingsButton),
        ),
        const SizedBox(height: 8),
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
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.studyModeLabel),
          subtitle: Text(l10n.studyModeDescription),
          value: _studyModeEnabled,
          onChanged: (value) => _handleStudyModeToggle(value),
        ),
        ElevatedButton(
          onPressed: _handleQuit,
          child: Text(l10n.quitButton),
        ),
      ],
    );
  }

  Widget _buildApisTab({
    required BuildContext context,
    required AppLocalizations l10n,
    required AppSetting settings,
    required SettingsController settingsController,
    required LlmProvider provider,
    required List<LlmProvider> providers,
    required AppServices services,
  }) {
    return StreamBuilder<List<ApiConfig>>(
      stream: services.db.watchApiConfigs(),
      builder: (context, snapshot) {
        final configs = snapshot.data ?? [];
        final textOptions = _buildTextModelOptions(
          provider: provider,
          settings: settings,
          configs: configs,
        );
        final ttsOptions = _buildAudioModelOptions(
          configs: configs,
          baseUrl: provider.baseUrl,
          fromLoaded: _modelsLoaded ? _ttsModelOptions : const [],
          fallback: (settings.ttsModel ?? '').trim(),
          selector: (config) => (config.ttsModel ?? '').trim(),
        );
        final sttOptions = _buildAudioModelOptions(
          configs: configs,
          baseUrl: provider.baseUrl,
          fromLoaded: _modelsLoaded ? _sttModelOptions : const [],
          fallback: (settings.sttModel ?? '').trim(),
          selector: (config) => (config.sttModel ?? '').trim(),
        );

        final textValue = _coerceSelection(
          current: _textModelSelection,
          options: textOptions,
          fallback: settings.model.trim(),
          onUpdate: (value) => setState(() => _textModelSelection = value),
        );
        final ttsValue = _coerceSelection(
          current: _ttsModelSelection,
          options: ttsOptions,
          fallback: (settings.ttsModel ?? '').trim(),
          onUpdate: (value) => setState(() => _ttsModelSelection = value),
          allowEmpty: _ttsModelOverride,
        );
        final sttValue = _coerceSelection(
          current: _sttModelSelection,
          options: sttOptions,
          fallback: (settings.sttModel ?? '').trim(),
          onUpdate: (value) => setState(() => _sttModelSelection = value),
          allowEmpty: _sttModelOverride,
        );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              l10n.apisTab,
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
                final next =
                    LlmProviders.findById(providers, value) ?? providers.first;
                setState(() {
                  _providerId = next.id;
                  _modelsLoaded = false;
                  _apiTestError = null;
                  _textModelOptions = const [];
                  _ttsModelOptions = const [];
                  _sttModelOptions = const [];
                  _textModelSelection = next.models.isNotEmpty
                      ? next.models.first
                      : _textModelSelection;
                });
                _maybeLoadApiKey(services, next.baseUrl);
              },
            ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: InputDecoration(labelText: l10n.baseUrlLabel),
              child: SelectableText(provider.baseUrl),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _apiKeyController,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.apiKeyLabel),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _apiTesting
                      ? null
                      : () => _testApiKey(
                            context: context,
                            l10n: l10n,
                            provider: provider,
                            baseUrl: provider.baseUrl,
                          ),
                  child: _apiTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.testApiKeyButton),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () async {
                    final baseUrl = provider.baseUrl;
                    await services.secureStorage
                        .deleteApiKeyForBaseUrl(baseUrl);
                    if (context.mounted) {
                      _apiKeyController.clear();
                      _showMessage(context, l10n.apiKeyClearedMessage);
                    }
                  },
                  child: Text(l10n.clearKeyButton),
                ),
              ],
            ),
            if ((_apiTestError ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.apiKeyTestFailed(_apiTestError!),
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            const SizedBox(height: 12),
            _buildModelPicker(
              label: l10n.textModelLabel,
              options: textOptions,
              value: textValue,
              emptyMessage: l10n.modelsNotLoadedMessage,
              onChanged: (value) {
                setState(() => _textModelSelection = value);
              },
            ),
            const SizedBox(height: 8),
            _buildModelPicker(
              label: l10n.ttsModelSelectLabel,
              options: ttsOptions,
              value: ttsValue,
              emptyMessage: l10n.noTtsModelsMessage,
              allowEmpty: true,
              onChanged: (value) {
                setState(() {
                  _ttsModelSelection = value;
                  _ttsModelOverride = true;
                });
              },
            ),
            const SizedBox(height: 8),
            _buildModelPicker(
              label: l10n.sttModelSelectLabel,
              options: sttOptions,
              value: sttValue,
              emptyMessage: l10n.noSttModelsMessage,
              allowEmpty: true,
              onChanged: (value) {
                setState(() {
                  _sttModelSelection = value;
                  _sttModelOverride = true;
                });
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                final apiKey = _apiKeyController.text.trim();
                final model = _resolveTextModel(provider, settings);
                if (apiKey.isEmpty) {
                  _showMessage(context, l10n.apiKeyMissingMessage);
                  return;
                }
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
                  ttsModel: _resolveTtsModel(settings),
                  sttModel: _resolveSttModel(settings),
                  timeoutSeconds:
                      int.tryParse(_timeoutController.text.trim()) ?? 60,
                  maxTokens:
                      int.tryParse(_maxTokensController.text.trim()) ?? 8000,
                  ttsInitialDelayMs: _parseSecondsMs(
                    _ttsDelayController,
                    settings.ttsInitialDelayMs,
                  ),
                  ttsTextLeadMs: _parseSecondsMs(
                    _ttsTextLeadController,
                    settings.ttsTextLeadMs,
                  ),
                  ttsAudioPath: resolvedAudioPath,
                  logDirectory: resolvedLogDir,
                  llmMode: _mode,
                  sttAutoSend: _sttAutoSend,
                  enterToSend: _enterToSend,
                  studyModeEnabled: _studyModeEnabled,
                );
                await services.secureStorage
                    .writeApiKeyForBaseUrl(provider.baseUrl, apiKey);
                final hash = sha256Hex(apiKey);
                await services.db.insertApiConfig(
                  baseUrl: provider.baseUrl,
                  model: model,
                  ttsModel: _resolveTtsModel(settings),
                  sttModel: _resolveSttModel(settings),
                  apiKeyHash: hash,
                );
                if (context.mounted) {
                  _showMessage(context, l10n.configSavedMessage);
                }
              },
              child: Text(l10n.saveApiConfigButton),
            ),
            const Divider(height: 24),
            Text(
              l10n.savedApiConfigsTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (configs.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l10n.noSavedConfigs),
              )
            else
              Column(
                children: configs.map((config) {
                  final shortHash = config.apiKeyHash.length > 8
                      ? config.apiKeyHash.substring(0, 8)
                      : config.apiKeyHash;
                  final provider =
                      LlmProviders.findByBaseUrl(providers, config.baseUrl);
                  final providerLabel = provider?.label ?? config.baseUrl;
                  final ttsModel = (config.ttsModel ?? '').trim();
                  final sttModel = (config.sttModel ?? '').trim();
                  final subtitleLines = <String>[
                    '${l10n.baseUrlLabel}: ${config.baseUrl}',
                    '${l10n.keyHashLabel(shortHash)}',
                    '${l10n.textModelLabel}: ${config.model}',
                  ];
                  if (ttsModel.isNotEmpty) {
                    subtitleLines.add('${l10n.ttsModelSelectLabel}: $ttsModel');
                  }
                  if (sttModel.isNotEmpty) {
                    subtitleLines.add('${l10n.sttModelSelectLabel}: $sttModel');
                  }
                  return ListTile(
                    title: Text(providerLabel),
                    subtitle: Text(subtitleLines.join('\n')),
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
                              _textModelSelection = config.model;
                              _ttsModelSelection = ttsModel;
                              _sttModelSelection = sttModel;
                              _ttsModelOverride = true;
                              _sttModelOverride = true;
                              _modelsLoaded = false;
                              _apiTestError = null;
                            });
                            final key = await services.secureStorage
                                .readApiKeyForBaseUrl(config.baseUrl);
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
                            if (context.mounted) {
                              _showMessage(context, l10n.configDeletedMessage);
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        );
      },
    );
  }

  List<String> _buildTextModelOptions({
    required LlmProvider provider,
    required AppSetting settings,
    required List<ApiConfig> configs,
  }) {
    final options = <String>{
      if (_modelsLoaded) ..._textModelOptions,
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
    return options;
  }

  List<String> _buildAudioModelOptions({
    required List<ApiConfig> configs,
    required String baseUrl,
    required List<String> fromLoaded,
    required String fallback,
    required String Function(ApiConfig) selector,
  }) {
    final options = <String>{
      ...fromLoaded.where((model) => model.trim().isNotEmpty),
      ...configs
          .where(
            (config) =>
                _normalizeBaseUrl(config.baseUrl) == _normalizeBaseUrl(baseUrl),
          )
          .map(selector)
          .where((model) => model.trim().isNotEmpty),
      if (fallback.trim().isNotEmpty) fallback.trim(),
    }.toList()
      ..sort();
    return options;
  }

  String _resolveTextModel(LlmProvider provider, AppSetting settings) {
    return (_textModelSelection ?? '').trim().isNotEmpty
        ? _textModelSelection!.trim()
        : (settings.model.trim().isNotEmpty
            ? settings.model.trim()
            : (provider.models.isNotEmpty ? provider.models.first : ''));
  }

  String _resolveTtsModel(AppSetting settings) {
    final selection = (_ttsModelSelection ?? '').trim();
    if (_ttsModelOverride) {
      return selection;
    }
    if (selection.isNotEmpty) {
      return selection;
    }
    return (settings.ttsModel ?? '').trim();
  }

  String _resolveSttModel(AppSetting settings) {
    final selection = (_sttModelSelection ?? '').trim();
    if (_sttModelOverride) {
      return selection;
    }
    if (selection.isNotEmpty) {
      return selection;
    }
    return (settings.sttModel ?? '').trim();
  }

  String _coerceSelection({
    required String? current,
    required List<String> options,
    required String fallback,
    required void Function(String value) onUpdate,
    bool allowEmpty = false,
  }) {
    if (options.isEmpty) {
      return fallback.trim();
    }
    final trimmed = (current ?? '').trim();
    if (allowEmpty && trimmed.isEmpty) {
      return '';
    }
    final next = options.contains(trimmed)
        ? trimmed
        : (options.contains(fallback.trim()) ? fallback.trim() : options.first);
    if (trimmed.isEmpty || trimmed != next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          onUpdate(next);
        }
      });
    }
    return next;
  }

  Widget _buildModelPicker({
    required String label,
    required List<String> options,
    required String value,
    required String emptyMessage,
    required void Function(String? value) onChanged,
    bool allowEmpty = false,
    String emptyLabel = 'None',
  }) {
    if (options.isEmpty) {
      return InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(emptyMessage),
      );
    }
    final trimmed = value.trim();
    final selection = options.contains(trimmed)
        ? trimmed
        : (allowEmpty && trimmed.isEmpty ? '' : options.first);
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$selection'),
      initialValue: selection,
      decoration: InputDecoration(labelText: label),
      items: [
        if (allowEmpty)
          DropdownMenuItem(
            value: '',
            child: Text(emptyLabel),
          ),
        ...options.map(
          (model) => DropdownMenuItem(
            value: model,
            child: Text(model),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }

  Future<void> _testApiKey({
    required BuildContext context,
    required AppLocalizations l10n,
    required LlmProvider provider,
    required String baseUrl,
  }) async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _showMessage(context, l10n.apiKeyMissingMessage);
      return;
    }
    setState(() {
      _apiTesting = true;
      _apiTestError = null;
    });
    final result = await ModelListService.fetchModels(
      provider: provider,
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    if (!mounted) {
      return;
    }
    if (!result.isSuccess) {
      setState(() {
        _apiTesting = false;
        _modelsLoaded = false;
        _apiTestError = result.error ?? l10n.apiKeyTestFailedGeneric;
        _textModelOptions = const [];
        _ttsModelOptions = const [];
        _sttModelOptions = const [];
      });
      return;
    }
    final lists = ModelListService.splitModels(
      models: result.models,
      baseUrl: baseUrl,
      providerId: provider.id,
    );
    setState(() {
      _apiTesting = false;
      _modelsLoaded = true;
      _apiTestError = null;
      _textModelOptions = lists.textModels;
      _ttsModelOptions = lists.ttsModels;
      _sttModelOptions = lists.sttModels;
    });
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

  int _parseSecondsMs(TextEditingController controller, int fallbackMs) {
    final raw = controller.text.trim();
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
                initialValue: selectedStudent,
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

  Future<void> _handleStudyModeToggle(bool enabled) async {
    if (enabled == _studyModeEnabled) {
      return;
    }
    if (!enabled) {
      final confirmed = await _confirmTeacherPin();
      if (!confirmed) {
        return;
      }
    }
    setState(() => _studyModeEnabled = enabled);
    final settingsController = context.read<SettingsController>();
    await settingsController.updateStudyMode(enabled);
  }

  Future<void> _handleQuit() async {
    final settings = context.read<SettingsController>().settings;
    final requiresPin = settings?.studyModeEnabled ?? false;
    if (requiresPin) {
      final confirmed = await _confirmTeacherPin();
      if (!confirmed) {
        return;
      }
    }
    await _quitApp();
  }

  Future<bool> _confirmTeacherPin() async {
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

  Future<void> _quitApp() async {
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
}

