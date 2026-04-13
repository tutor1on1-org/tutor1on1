import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/l10n/app_localizations.dart';
import 'package:tutor1on1/services/prompt_template_validator.dart';
import 'package:tutor1on1/ui/widgets/prompt_editor_dialog.dart';

void main() {
  testWidgets(
    'invalid save keeps prompt editor open and shows inline validation errors',
    (tester) async {
      final validator = PromptTemplateValidator();
      const invalidContent = '''
{{kp_description}}
{{student_input}}
{{lesson_content}}
{{瀛︾敓杈撳叆}}
''';
      const validContent = '''
{{kp_description}}
{{student_input}}
{{lesson_content}}
''';
      String? savedContent;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    savedContent = await showDialog<String>(
                      context: context,
                      builder: (context) => PromptEditorDialog(
                        title: 'Edit learn prompt',
                        promptName: 'learn',
                        initialContent: invalidContent,
                        validator: validator,
                        variableRows: const <Widget>[Text('vars')],
                        allVariableRows: const <Widget>[Text('all vars')],
                        requireRequiredVariables: true,
                      ),
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(PromptEditorDialog), findsOneWidget);
      expect(
        find.textContaining('Invalid variables: 瀛︾敓杈撳叆'),
        findsOneWidget,
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(PromptEditorDialog), findsOneWidget);
      expect(
        find.textContaining('Invalid variables: 瀛︾敓杈撳叆'),
        findsOneWidget,
      );
      expect(savedContent, isNull);

      await tester.enterText(find.byType(TextField), validContent);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(PromptEditorDialog), findsNothing);
      expect(savedContent, equals(validContent));
    },
  );

  testWidgets(
    'scoped prompt requires complete full prompt variables',
    (tester) async {
      final validator = PromptTemplateValidator();
      const incompleteContent = 'Use a concise tone. {{conversation_history}}';
      const fullContent = '''
{{kp_description}}
{{student_input}}
Use a concise tone. {{conversation_history}}
''';
      String? savedContent;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    savedContent = await showDialog<String>(
                      context: context,
                      builder: (context) => PromptEditorDialog(
                        title: 'Edit review scoped prompt',
                        promptName: 'review',
                        initialContent: incompleteContent,
                        validator: validator,
                        variableRows: const <Widget>[Text('vars')],
                        allVariableRows: const <Widget>[Text('all vars')],
                        requireRequiredVariables: true,
                      ),
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(PromptEditorDialog), findsOneWidget);
      expect(find.textContaining('Missing variables'), findsOneWidget);
      expect(savedContent, isNull);

      await tester.enterText(find.byType(TextField), fullContent);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(PromptEditorDialog), findsNothing);
      expect(savedContent, equals(fullContent));
    },
  );
}
