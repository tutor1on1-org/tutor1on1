import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../services/settings_repository.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._repository) {
    _load();
  }

  final SettingsRepository _repository;
  AppSetting? _settings;
  bool _loading = true;

  AppSetting? get settings => _settings;
  bool get isLoading => _loading;

  Future<void> _load() async {
    _settings = await _repository.load();
    _loading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    await _load();
  }

  Future<void> update({
    required String providerId,
    required String baseUrl,
    required String model,
    required int timeoutSeconds,
    required int maxTokens,
    required String llmMode,
    String? locale,
  }) async {
    _settings = await _repository.update(
      providerId: providerId,
      baseUrl: baseUrl,
      model: model,
      timeoutSeconds: timeoutSeconds,
      maxTokens: maxTokens,
      llmMode: llmMode,
      locale: locale,
    );
    notifyListeners();
  }

  Future<void> updateLocale(String? locale) async {
    _settings = await _repository.updateLocale(locale);
    notifyListeners();
  }
}
