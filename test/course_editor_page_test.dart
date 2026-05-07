import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/l10n/app_localizations.dart';
import 'package:tutor1on1/services/app_services.dart';
import 'package:tutor1on1/ui/pages/course_editor_page.dart';

class _FakeAppServices implements AppServices {
  _FakeAppServices({required this.db});

  @override
  final AppDatabase db;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('course editor opens AI editor from KP menu', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async => db.close());

    final teacherId = await db.createUser(
      username: 'teacher',
      pinHash: 'hash',
      role: 'teacher',
    );
    final courseId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Math',
      granularity: 2,
      textbookText: '''
1 Unit
1.1 Adding
''',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          Provider<AppServices>.value(value: _FakeAppServices(db: db)),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SizedBox.shrink(),
        ),
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          Provider<AppServices>.value(value: _FakeAppServices(db: db)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CourseEditorPage(courseVersionId: courseId),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Course Editor - Math'), findsOneWidget);
    expect(find.text('Unit'), findsOneWidget);

    await tester.tap(find.text('Unit'));
    await tester.pumpAndSettle();

    expect(find.text('Adding'), findsOneWidget);

    await tester.tap(find.byKey(const Key('course_editor_node_menu_1.1')));
    await tester.pumpAndSettle();

    expect(find.text('AI edit content'), findsOneWidget);
    expect(find.text('Edit title'), findsOneWidget);
    expect(find.text('Add sub'), findsOneWidget);

    await tester.tap(find.text('AI edit content'));
    await tester.pumpAndSettle();

    expect(find.text('1.1 Adding'), findsOneWidget);
    expect(find.text('Course Builder'), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
    expect(find.text('Question'), findsOneWidget);
  });
}
