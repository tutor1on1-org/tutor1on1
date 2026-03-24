import 'package:flutter/widgets.dart';

class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.label,
  });

  final String code;
  final String label;
}

const List<AppLanguage> supportedAppLanguages = <AppLanguage>[
  AppLanguage(code: 'en', label: 'English'),
  AppLanguage(code: 'zh', label: '简体中文'),
];

String normalizeAppLanguageCode(String? localeCode) {
  final normalized = (localeCode ?? '').trim().toLowerCase();
  if (normalized.isEmpty) {
    return '';
  }
  if (normalized == 'en' ||
      normalized.startsWith('en-') ||
      normalized.startsWith('en_')) {
    return 'en';
  }
  if (normalized == 'zh' ||
      normalized.startsWith('zh-') ||
      normalized.startsWith('zh_')) {
    return 'zh';
  }
  return '';
}

Locale? appLocaleFromSetting(String? localeCode) {
  final normalized = normalizeAppLanguageCode(localeCode);
  if (normalized.isEmpty) {
    return null;
  }
  return Locale(normalized);
}
