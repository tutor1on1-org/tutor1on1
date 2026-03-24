import 'package:flutter/widgets.dart';

class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.label,
    required this.fallbackLocaleCode,
  });

  final String code;
  final String label;
  final String fallbackLocaleCode;
}

const List<AppLanguage> supportedAppLanguages = <AppLanguage>[
  AppLanguage(code: 'en', label: 'English', fallbackLocaleCode: 'en'),
  AppLanguage(code: 'zh', label: '简体中文', fallbackLocaleCode: 'zh'),
  AppLanguage(code: 'zh-tw', label: '繁體中文', fallbackLocaleCode: 'zh'),
  AppLanguage(code: 'ja', label: '日本語', fallbackLocaleCode: 'en'),
  AppLanguage(code: 'ko', label: '한국어', fallbackLocaleCode: 'en'),
  AppLanguage(code: 'es', label: 'Español', fallbackLocaleCode: 'en'),
  AppLanguage(code: 'fr', label: 'Français', fallbackLocaleCode: 'en'),
  AppLanguage(code: 'de', label: 'Deutsch', fallbackLocaleCode: 'en'),
];

String normalizeAppLanguageCode(String? localeCode) {
  final normalized =
      (localeCode ?? '').trim().toLowerCase().replaceAll('_', '-');
  if (normalized.isEmpty) {
    return '';
  }
  if (normalized == 'en' || normalized.startsWith('en-')) {
    return 'en';
  }
  if (normalized == 'zh-tw' ||
      normalized == 'zh-hk' ||
      normalized == 'zh-mo' ||
      normalized == 'zh-hant') {
    return 'zh-tw';
  }
  if (normalized == 'zh' || normalized.startsWith('zh-')) {
    return 'zh';
  }
  if (normalized == 'ja' || normalized.startsWith('ja-')) {
    return 'ja';
  }
  if (normalized == 'ko' || normalized.startsWith('ko-')) {
    return 'ko';
  }
  if (normalized == 'es' || normalized.startsWith('es-')) {
    return 'es';
  }
  if (normalized == 'fr' || normalized.startsWith('fr-')) {
    return 'fr';
  }
  if (normalized == 'de' || normalized.startsWith('de-')) {
    return 'de';
  }
  return '';
}

Locale? appLocaleFromSetting(String? localeCode) {
  final normalized = normalizeAppLanguageCode(localeCode);
  if (normalized.isEmpty) {
    return null;
  }
  for (final language in supportedAppLanguages) {
    if (language.code == normalized) {
      return Locale(language.fallbackLocaleCode);
    }
  }
  return null;
}
