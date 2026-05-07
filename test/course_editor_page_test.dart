import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/l10n/app_localizations.dart';
import 'package:tutor1on1/services/app_services.dart';
import 'package:tutor1on1/services/course_service.dart';
import 'package:tutor1on1/state/auth_controller.dart';
import 'package:tutor1on1/ui/pages/course_editor_page.dart';

class _FixedAuthController extends ChangeNotifier implements AuthController {
  _FixedAuthController(this._currentUser);

  final User _currentUser;

  @override
  User? get currentUser => _currentUser;

  @override
  String? get lastError => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAppServices implements AppServices {
  _FakeAppServices({required this.db}) : courseService = CourseService(db);

  @override
  final AppDatabase db;

  @override
  final CourseService courseService;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> pumpCourseEditor({
    required WidgetTester tester,
    required AppDatabase db,
    required User teacher,
    required int courseId,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          Provider<AppServices>.value(value: _FakeAppServices(db: db)),
          ChangeNotifierProvider<AuthController>.value(
            value: _FixedAuthController(teacher),
          ),
        ],
        child: SizedBox(
          width: 1000,
          height: 900,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: CourseEditorPage(courseVersionId: courseId),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('course editor reuses skill tree expand and right-click menu',
      (tester) async {
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
1.1.1 Carrying
''',
    );
    final teacher = (await db.getUserById(teacherId))!;

    await pumpCourseEditor(
      tester: tester,
      db: db,
      teacher: teacher,
      courseId: courseId,
    );

    expect(find.text('Course Editor'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('Carrying'), findsNothing);

    await tester.enterText(find.byType(TextField), '1.1');
    await tester.pump();
    await tester.tap(find.widgetWithText(ActionChip, '1.1'));
    await tester.pumpAndSettle();

    expect(find.text('Adding'), findsOneWidget);
    expect(find.text('Carrying'), findsOneWidget);

    await tester.tapAt(
      tester.getCenter(find.text('Adding')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('AI edit content'), findsOneWidget);
    expect(find.text('Edit title'), findsOneWidget);
    expect(find.text('Add sub'), findsOneWidget);
    expect(find.text('Add sibling'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);

    await tester.tap(find.text('AI edit content'));
    await tester.pumpAndSettle();

    expect(find.text('1.1 Adding'), findsOneWidget);
    expect(find.text('Course Builder'), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
    expect(find.text('Question'), findsOneWidget);
  });

  testWidgets('course editor right-click edits title adds sibling and hides KP',
      (tester) async {
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
    final teacher = (await db.getUserById(teacherId))!;

    await pumpCourseEditor(
      tester: tester,
      db: db,
      teacher: teacher,
      courseId: courseId,
    );
    await tester.enterText(find.byType(TextField), '1.1');
    await tester.pump();
    await tester.tap(find.widgetWithText(ActionChip, '1.1'));
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(find.text('Adding')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit title'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Renamed adding');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Renamed adding'), findsOneWidget);
    expect((await db.getCourseVersionById(courseId))!.textbookText,
        contains('1.1 Renamed adding'));

    await tester.tapAt(
      tester.getCenter(find.text('Renamed adding')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add sibling'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Subtraction');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final afterAdd = (await db.getCourseVersionById(courseId))!.textbookText;
    expect(afterAdd, contains('1.2 Subtraction'));

    await tester.enterText(find.byType(TextField).first, '1.2');
    await tester.pump();
    await tester.tap(find.widgetWithText(ActionChip, '1.2'));
    await tester.pumpAndSettle();
    expect(find.text('Subtraction'), findsOneWidget);

    await tester.tapAt(
      tester.getCenter(find.text('Subtraction')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Hide'));
    await tester.pumpAndSettle();

    expect((await db.getCourseVersionById(courseId))!.textbookText,
        contains('1.2 [hidden] Subtraction'));
    await tester.enterText(find.byType(TextField).first, '1.2');
    await tester.pump();
    expect(find.widgetWithText(ActionChip, '1.2'), findsNothing);
  });
}
