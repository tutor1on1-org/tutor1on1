import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../db/app_database.dart';
import '../llm/llm_models.dart';
import '../llm/llm_providers.dart';
import 'runtime_environment.dart';
import 'secure_storage_service.dart';

class SettingsRepository {
  SettingsRepository(
    this._db, {
    SecureStorageService? secureStorage,
    String? appLabel,
  })  : _secureStorage = secureStorage,
        _appLabel = appLabel ?? runtimeAppLabel;

  final AppDatabase _db;
  final SecureStorageService? _secureStorage;
  final String _appLabel;

  bool get _isAgentTutor => _appLabel.trim().toLowerCase() == 'agent_tutor';

  Future<AppSetting> load() async {
    final existing = await _db.select(_db.appSettings).getSingleOrNull();
    if (existing != null) {
      final providerId = existing.providerId?.trim().toLowerCase();
      var needsUpdate = false;
      var companion = AppSettingsCompanion(
        updatedAt: Value(DateTime.now()),
      );
      if (providerId == null || providerId.isEmpty) {
        final providers = LlmProviders.defaultProviders(
          envBaseUrl: runtimeOpenAiBaseUrl,
          envModel: runtimeOpenAiModel,
        );
        final match = LlmProviders.findByBaseUrl(
          providers,
          existing.baseUrl,
        );
        if (match != null) {
          companion = companion.copyWith(
            providerId: Value(match.id),
          );
          needsUpdate = true;
        }
      }
      final reasoningEffort =
          ReasoningEffort.normalize(existing.reasoningEffort);
      if (reasoningEffort != existing.reasoningEffort) {
        companion = companion.copyWith(
          reasoningEffort: Value(reasoningEffort),
        );
        needsUpdate = true;
      }
      if ((existing.ttsAudioPath ?? '').trim().isEmpty) {
        final defaultPath = await _defaultTtsAudioPath();
        companion = companion.copyWith(
          ttsAudioPath: Value(defaultPath),
        );
        needsUpdate = true;
      }
      final logDir = (existing.logDirectory ?? '').trim();
      final llmLogPath = (existing.llmLogPath ?? '').trim();
      final ttsLogPath = (existing.ttsLogPath ?? '').trim();
      if (logDir.isEmpty || llmLogPath.isEmpty || ttsLogPath.isEmpty) {
        final resolvedDir = logDir.isNotEmpty
            ? logDir
            : (llmLogPath.isNotEmpty
                ? p.dirname(llmLogPath)
                : (ttsLogPath.isNotEmpty
                    ? p.dirname(ttsLogPath)
                    : await _defaultLogDirectory()));
        final paths = _buildLogPaths(resolvedDir);
        final resolvedLlmPath = llmLogPath.isEmpty ? paths['llm']! : llmLogPath;
        final resolvedTtsPath = ttsLogPath.isEmpty ? paths['tts']! : ttsLogPath;
        companion = companion.copyWith(
          logDirectory: Value(resolvedDir),
          llmLogPath: Value(resolvedLlmPath),
          ttsLogPath: Value(resolvedTtsPath),
        );
        needsUpdate = true;
      }
      if (existing.ttsTextLeadMs <= 0) {
        companion = companion.copyWith(
          ttsTextLeadMs: const Value(1000),
        );
        needsUpdate = true;
      }
      if (existing.studyModeEnabled) {
        companion = companion.copyWith(
          studyModeEnabled: const Value(false),
        );
        needsUpdate = true;
      }
      if (needsUpdate) {
        await (_db.update(_db.appSettings)
              ..where((tbl) => tbl.id.equals(existing.id)))
            .write(companion);
        return _overlayAgentTutorSettings(
          await _db.select(_db.appSettings).getSingle(),
        );
      }
      return _overlayAgentTutorSettings(existing);
    }
    final envBaseUrl = runtimeOpenAiBaseUrl.trim();
    final envModel = runtimeOpenAiModel.trim();
    final hasEnvBaseUrl = envBaseUrl.isNotEmpty;
    final baseUrl =
        hasEnvBaseUrl ? envBaseUrl : 'https://api.siliconflow.cn/v1';
    final model = envModel.isNotEmpty ? envModel : 'deepseek-ai/DeepSeek-V3.2';
    final providerId = hasEnvBaseUrl ? 'env' : 'siliconflow';
    final ttsAudioPath = await _defaultTtsAudioPath();
    final logDirectory = await _defaultLogDirectory();
    final logPaths = _buildLogPaths(logDirectory);
    await _db.into(_db.appSettings).insert(
          AppSettingsCompanion.insert(
            baseUrl: _normalizeBaseUrl(baseUrl),
            providerId: Value(providerId),
            model: model,
            reasoningEffort: const Value(ReasoningEffort.medium),
            timeoutSeconds: 60,
            maxTokens: 8000,
            ttsInitialDelayMs: const Value(60000),
            ttsTextLeadMs: const Value(1000),
            ttsAudioPath: Value(ttsAudioPath),
            sttAutoSend: const Value(false),
            enterToSend: const Value(true),
            studyModeEnabled: const Value(false),
            logDirectory: Value(logDirectory),
            llmLogPath: Value(logPaths['llm']!),
            ttsLogPath: Value(logPaths['tts']!),
            llmMode: 'LIVE_RECORD',
            locale: const Value(null),
          ),
        );
    return _overlayAgentTutorSettings(
      await _db.select(_db.appSettings).getSingle(),
    );
  }

  Future<AppSetting> update({
    required String providerId,
    required String baseUrl,
    required String model,
    required String reasoningEffort,
    required String ttsModel,
    required String sttModel,
    required int timeoutSeconds,
    required int maxTokens,
    required int ttsInitialDelayMs,
    required int ttsTextLeadMs,
    required String ttsAudioPath,
    required String logDirectory,
    required String llmMode,
    required bool sttAutoSend,
    required bool enterToSend,
    String? locale,
  }) async {
    final current = await load();
    if (_isAgentTutor) {
      return _updateAgentTutor(
        current: current,
        model: model,
        reasoningEffort: reasoningEffort,
        enterToSend: enterToSend,
        logDirectory: logDirectory,
        locale: locale,
      );
    }
    final cleanedPath = ttsAudioPath.trim();
    final resolvedPath =
        cleanedPath.isEmpty ? await _defaultTtsAudioPath() : cleanedPath;
    final cleanedLogDir = logDirectory.trim();
    final resolvedLogDir =
        cleanedLogDir.isEmpty ? await _defaultLogDirectory() : cleanedLogDir;
    final logPaths = _buildLogPaths(resolvedLogDir);
    final companion = AppSettingsCompanion(
      baseUrl: Value(_normalizeBaseUrl(baseUrl)),
      providerId: Value(providerId),
      model: Value(model.trim()),
      reasoningEffort: Value(ReasoningEffort.normalize(reasoningEffort)),
      ttsModel: Value(ttsModel.trim().isEmpty ? null : ttsModel.trim()),
      sttModel: Value(sttModel.trim().isEmpty ? null : sttModel.trim()),
      timeoutSeconds: Value(timeoutSeconds),
      maxTokens: Value(maxTokens),
      ttsInitialDelayMs: Value(ttsInitialDelayMs),
      ttsTextLeadMs: Value(ttsTextLeadMs),
      ttsAudioPath: Value(resolvedPath),
      sttAutoSend: Value(sttAutoSend),
      enterToSend: Value(enterToSend),
      logDirectory: Value(resolvedLogDir),
      llmLogPath: Value(logPaths['llm']!),
      ttsLogPath: Value(logPaths['tts']!),
      llmMode: Value(llmMode),
      locale: Value(locale ?? current.locale),
      updatedAt: Value(DateTime.now()),
    );
    await (_db.update(_db.appSettings)
          ..where((tbl) => tbl.id.equals(current.id)))
        .write(companion);
    return _overlayAgentTutorSettings(
      await _db.select(_db.appSettings).getSingle(),
    );
  }

  Future<AppSetting> updateLocale(String? locale) async {
    final current = await load();
    final companion = AppSettingsCompanion(
      locale: Value(locale),
      updatedAt: Value(DateTime.now()),
    );
    await (_db.update(_db.appSettings)
          ..where((tbl) => tbl.id.equals(current.id)))
        .write(companion);
    return _overlayAgentTutorSettings(
      await _db.select(_db.appSettings).getSingle(),
    );
  }

  Future<AppSetting> _updateAgentTutor({
    required AppSetting current,
    required String model,
    required String reasoningEffort,
    required bool enterToSend,
    required String logDirectory,
    required String? locale,
  }) async {
    final storage = _secureStorage;
    if (storage == null) {
      throw StateError('Agent Tutor settings storage is unavailable.');
    }
    final provider = LlmProviders.defaultProviders(appLabel: _appLabel).single;
    final normalizedModel = model.trim();
    if (normalizedModel.isEmpty) {
      throw StateError('Agent Tutor model is required.');
    }
    final normalizedEffort = ReasoningEffort.normalize(reasoningEffort);
    if (!provider.reasoningEfforts.contains(normalizedEffort)) {
      throw StateError('Agent Tutor reasoning effort is invalid.');
    }
    await storage.writeAgentTutorModel(normalizedModel);
    await storage.writeAgentTutorReasoningEffort(normalizedEffort);
    final cleanedLogDir = logDirectory.trim();
    final resolvedLogDir = cleanedLogDir.isEmpty
        ? (current.logDirectory ?? await _defaultLogDirectory())
        : cleanedLogDir;
    final logPaths = _buildLogPaths(resolvedLogDir);
    await (_db.update(_db.appSettings)
          ..where((tbl) => tbl.id.equals(current.id)))
        .write(
      AppSettingsCompanion(
        enterToSend: Value(enterToSend),
        logDirectory: Value(resolvedLogDir),
        llmLogPath: Value(logPaths['llm']!),
        locale: Value(locale ?? current.locale),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return _overlayAgentTutorSettings(
      await _db.select(_db.appSettings).getSingle(),
    );
  }

  Future<AppSetting> _overlayAgentTutorSettings(AppSetting settings) async {
    if (!_isAgentTutor) {
      return settings;
    }
    final provider = LlmProviders.defaultProviders(appLabel: _appLabel).single;
    final storedModel = (await _secureStorage?.readAgentTutorModel())?.trim();
    final storedEffort =
        (await _secureStorage?.readAgentTutorReasoningEffort())?.trim();
    final effort = ReasoningEffort.normalize(storedEffort);
    return settings.copyWith(
      baseUrl: provider.baseUrl,
      providerId: Value(provider.id),
      model: storedModel == null || storedModel.isEmpty
          ? provider.models.first
          : storedModel,
      reasoningEffort: provider.reasoningEfforts.contains(effort)
          ? effort
          : ReasoningEffort.medium,
      ttsModel: const Value(null),
      sttModel: const Value(null),
      timeoutSeconds:
          settings.timeoutSeconds < 600 ? 600 : settings.timeoutSeconds,
      sttAutoSend: false,
      llmMode: LlmMode.live.value,
    );
  }

  Future<String> _defaultTtsAudioPath() async {
    return '/browser/audio';
  }

  Future<String> _defaultLogDirectory() async {
    return '/browser/logs';
  }

  Map<String, String> _buildLogPaths(String directory) {
    return {
      'llm': p.join(directory, 'llm_logs.jsonl'),
      'tts': p.join(directory, 'tts_logs.jsonl'),
    };
  }

  String _normalizeBaseUrl(String value) {
    var trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
