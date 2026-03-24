import 'package:family_teacher/l10n/app_localizations.dart';
import 'package:family_teacher/ui/widgets/language_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows globe icon and supported language names', (tester) async {
    String? selectedLanguage;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LanguageSelector(
            localeCode: 'zh-CN',
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

    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(selectedLanguage, 'en');
  });
}
