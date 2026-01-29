import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/app_database.dart';
import '../llm/llm_providers.dart';

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

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
          envBaseUrl: Platform.environment['OPENAI_BASE_URL'],
          envModel: Platform.environment['OPENAI_MODEL'],
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
        final resolvedLlmPath =
            llmLogPath.isEmpty ? paths['llm']! : llmLogPath;
        final resolvedTtsPath =
            ttsLogPath.isEmpty ? paths['tts']! : ttsLogPath;
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
      if (needsUpdate) {
        await (_db.update(_db.appSettings)
              ..where((tbl) => tbl.id.equals(existing.id)))
            .write(companion);
        return await _db.select(_db.appSettings).getSingle();
      }
      return existing;
    }
    final envBaseUrl = Platform.environment['OPENAI_BASE_URL']?.trim() ?? '';
    final envModel = Platform.environment['OPENAI_MODEL']?.trim() ?? '';
    final hasEnvBaseUrl = envBaseUrl.isNotEmpty;
    final baseUrl =
        hasEnvBaseUrl ? envBaseUrl : 'https://api.siliconflow.cn/v1';
    final model =
        envModel.isNotEmpty ? envModel : 'deepseek-ai/DeepSeek-V3.2';
    final providerId = hasEnvBaseUrl ? 'env' : 'siliconflow';
    final ttsAudioPath = await _defaultTtsAudioPath();
    final logDirectory = await _defaultLogDirectory();
    final logPaths = _buildLogPaths(logDirectory);
    await _db.into(_db.appSettings).insert(
          AppSettingsCompanion.insert(
            baseUrl: _normalizeBaseUrl(baseUrl),
            providerId: Value(providerId),
            model: model,
            timeoutSeconds: 60,
            maxTokens: 8000,
            ttsInitialDelayMs: const Value(60000),
            ttsTextLeadMs: const Value(1000),
            ttsAudioPath: Value(ttsAudioPath),
            sttAutoSend: const Value(false),
            studyModeEnabled: const Value(false),
            logDirectory: Value(logDirectory),
            llmLogPath: Value(logPaths['llm']!),
            ttsLogPath: Value(logPaths['tts']!),
            llmMode: 'LIVE_RECORD',
            locale: const Value(null),
          ),
        );
    return await _db.select(_db.appSettings).getSingle();
  }

  Future<AppSetting> update({
    required String providerId,
    required String baseUrl,
    required String model,
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
    required bool studyModeEnabled,
    String? locale,
  }) async {
    final current = await load();
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
      ttsModel: Value(ttsModel.trim().isEmpty ? null : ttsModel.trim()),
      sttModel: Value(sttModel.trim().isEmpty ? null : sttModel.trim()),
      timeoutSeconds: Value(timeoutSeconds),
      maxTokens: Value(maxTokens),
      ttsInitialDelayMs: Value(ttsInitialDelayMs),
      ttsTextLeadMs: Value(ttsTextLeadMs),
      ttsAudioPath: Value(resolvedPath),
      sttAutoSend: Value(sttAutoSend),
      studyModeEnabled: Value(studyModeEnabled),
      logDirectory: Value(resolvedLogDir),
      llmLogPath: Value(logPaths['llm']!),
      ttsLogPath: Value(logPaths['tts']!),
      llmMode: Value(llmMode),
      locale: Value(locale ?? current.locale),
      updatedAt: Value(DateTime.now()),
    );
    await (_db.update(_db.appSettings)..where((tbl) => tbl.id.equals(current.id)))
        .write(companion);
    return (await _db.select(_db.appSettings).getSingle());
  }

  Future<AppSetting> updateStudyModeEnabled(bool enabled) async {
    final current = await load();
    final companion = AppSettingsCompanion(
      studyModeEnabled: Value(enabled),
      updatedAt: Value(DateTime.now()),
    );
    await (_db.update(_db.appSettings)..where((tbl) => tbl.id.equals(current.id)))
        .write(companion);
    return (await _db.select(_db.appSettings).getSingle());
  }

  Future<AppSetting> updateLocale(String? locale) async {
    final current = await load();
    final companion = AppSettingsCompanion(
      locale: Value(locale),
      updatedAt: Value(DateTime.now()),
    );
    await (_db.update(_db.appSettings)..where((tbl) => tbl.id.equals(current.id)))
        .write(companion);
    return (await _db.select(_db.appSettings).getSingle());
  }

  Future<String> _defaultTtsAudioPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<String> _defaultLogDirectory() async {
    if (Platform.isWindows) {
      return r'C:\family_teacher\logs';
    }
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'logs');
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
