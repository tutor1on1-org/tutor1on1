import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../services/screen_lock_service.dart';
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
    await _applyStudyMode();
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
    _settings = await _repository.update(
      providerId: providerId,
      baseUrl: baseUrl,
      model: model,
      ttsModel: ttsModel,
      sttModel: sttModel,
      timeoutSeconds: timeoutSeconds,
      maxTokens: maxTokens,
      ttsInitialDelayMs: ttsInitialDelayMs,
      ttsTextLeadMs: ttsTextLeadMs,
      ttsAudioPath: ttsAudioPath,
      logDirectory: logDirectory,
      llmMode: llmMode,
      sttAutoSend: sttAutoSend,
      studyModeEnabled: studyModeEnabled,
      locale: locale,
    );
    await _applyStudyMode();
    notifyListeners();
  }

  Future<void> updateLocale(String? locale) async {
    _settings = await _repository.updateLocale(locale);
    notifyListeners();
  }

  Future<void> updateStudyMode(bool enabled) async {
    _settings = await _repository.updateStudyModeEnabled(enabled);
    await _applyStudyMode();
    notifyListeners();
  }

  Future<void> _applyStudyMode() async {
    final enabled = _settings?.studyModeEnabled ?? false;
    await ScreenLockService.instance.setEnabled(enabled);
  }
}
