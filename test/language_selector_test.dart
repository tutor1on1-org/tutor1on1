import 'package:family_teacher/l10n/app_language.dart';
import 'package:family_teacher/l10n/app_localizations.dart';
import 'package:family_teacher/ui/widgets/language_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps visible language choices onto supported app locales', () {
    expect(appLocaleFromSetting(null), isNull);
    expect(appLocaleFromSetting(''), isNull);
    expect(appLocaleFromSetting('en'), const Locale('en'));
    expect(appLocaleFromSetting('zh-CN'), const Locale('zh'));
    expect(appLocaleFromSetting('zh-TW'), const Locale('zh'));
    expect(appLocaleFromSetting('ja'), const Locale('en'));
    expect(appLocaleFromSetting('ko-KR'), const Locale('en'));
    expect(appLocaleFromSetting('es-ES'), const Locale('en'));
    expect(appLocaleFromSetting('fr-FR'), const Locale('en'));
    expect(appLocaleFromSetting('de-DE'), const Locale('en'));
  });

  testWidgets('shows globe icon and all supported language names',
      (tester) async {
    String? selectedLanguage;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LanguageSelector(
            localeCode: 'zh-TW',
            onChanged: (value) => selectedLanguage = value,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.language), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(find.text('System default'), findsOneWidget);
    expect(find.text('English'), findsWidgets);
    expect(find.text('简体中文'), findsWidgets);
    expect(find.text('繁體中文'), findsWidgets);
    expect(find.text('日本語'), findsWidgets);
    expect(find.text('한국어'), findsWidgets);
    expect(find.text('Español'), findsWidgets);
    expect(find.text('Français'), findsWidgets);
    expect(find.text('Deutsch'), findsWidgets);

    await tester.tap(find.text('日本語').last);
    await tester.pumpAndSettle();

    expect(selectedLanguage, 'ja');
  });
}
