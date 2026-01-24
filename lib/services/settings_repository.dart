import 'dart:io';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../llm/llm_providers.dart';

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Future<AppSetting> load() async {
    final existing = await _db.select(_db.appSettings).getSingleOrNull();
    if (existing != null) {
      final providerId = existing.providerId?.trim();
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
          final companion = AppSettingsCompanion(
            providerId: Value(match.id),
            updatedAt: Value(DateTime.now()),
          );
          await (_db.update(_db.appSettings)
                ..where((tbl) => tbl.id.equals(existing.id)))
              .write(companion);
          return await _db.select(_db.appSettings).getSingle();
        }
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
    await _db.into(_db.appSettings).insert(
          AppSettingsCompanion.insert(
            baseUrl: _normalizeBaseUrl(baseUrl),
            providerId: Value(providerId),
            model: model,
            timeoutSeconds: 60,
            maxTokens: 800,
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
    required int timeoutSeconds,
    required int maxTokens,
    required String llmMode,
    String? locale,
  }) async {
    final current = await load();
    final companion = AppSettingsCompanion(
      baseUrl: Value(_normalizeBaseUrl(baseUrl)),
      providerId: Value(providerId),
      model: Value(model.trim()),
      timeoutSeconds: Value(timeoutSeconds),
      maxTokens: Value(maxTokens),
      llmMode: Value(llmMode),
      locale: Value(locale ?? current.locale),
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

  String _normalizeBaseUrl(String value) {
    var trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
