import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/l10n/app_localizations.dart';
import 'package:tutor1on1/services/app_services.dart';
import 'package:tutor1on1/services/session_sync_service.dart';
import 'package:tutor1on1/state/auth_controller.dart';
import 'package:tutor1on1/ui/pages/skill_tree_page.dart';

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

class _DelayedSessionSyncService implements SessionSyncService {
  final Completer<void> materializeCompleter = Completer<void>();
  int materializeCalls = 0;
  int? lastLocalStudentId;
  int? lastCourseVersionId;

  @override
  Future<void> materializeTeacherArtifactsForView({
    required User currentUser,
    required int localStudentId,
    int? courseVersionId,
  }) {
    materializeCalls += 1;
    lastLocalStudentId = localStudentId;
    lastCourseVersionId = courseVersionId;
    return materializeCompleter.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAppServices implements AppServices {
  _FakeAppServices({
    required this.db,
    required this.sessionSyncService,
  });

  @override
  final AppDatabase db;

  @override
  final SessionSyncService sessionSyncService;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'teacher tree keeps assigned student while artifact materialization is pending',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async => db.close());

      final teacherId = await db.createUser(
        username: 'dennis',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 9001,
      );
      final studentId = await db.createUser(
        username: 'albert',
        pinHash: 'hash',
        role: 'student',
        teacherId: teacherId,
        remoteUserId: 3001,
      );
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'hksi_paper2',
        granularity: 1,
        textbookText: '''
1 Unit
1.1 (Counting, Y1)
''',
        sourcePath: r'C:\courses\hksi_paper2',
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );
      await db.into(db.courseNodes).insert(
            CourseNodesCompanion.insert(
              courseVersionId: courseVersionId,
              kpKey: '1.1',
              title: 'Counting',
              description: 'Count simple values.',
              orderIndex: 1,
            ),
          );
      await db.into(db.chatSessions).insert(
            ChatSessionsCompanion.insert(
              studentId: studentId,
              courseVersionId: courseVersionId,
              kpKey: '1.1',
              title: const Value('Existing session'),
            ),
          );

      final teacher = (await db.getUserById(teacherId))!;
      final sessionSyncService = _DelayedSessionSyncService();
      try {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<AppDatabase>.value(value: db),
              Provider<AppServices>.value(
                value: _FakeAppServices(
                  db: db,
                  sessionSyncService: sessionSyncService,
                ),
              ),
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
                home: SkillTreePage(
                  courseVersionId: courseVersionId,
                  isTeacherView: true,
                  teacherStudentId: studentId,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(sessionSyncService.materializeCalls, 1);
        expect(sessionSyncService.lastLocalStudentId, studentId);
        expect(sessionSyncService.lastCourseVersionId, courseVersionId);
        expect(sessionSyncService.materializeCompleter.isCompleted, isFalse);

        await tester.enterText(find.byType(TextField), '1.1');
        await tester.pump();
        await tester.tap(find.widgetWithText(ActionChip, '1.1'));
        await tester.pump();

        expect(find.text('(Counting, Y1)'), findsOneWidget);

        await tester.tap(find.text('(Counting, Y1)'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('No assigned student for this course.'), findsNothing);
        expect(find.text('Existing session'), findsOneWidget);
      } finally {
        if (!sessionSyncService.materializeCompleter.isCompleted) {
          sessionSyncService.materializeCompleter.complete();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 500));
      }
    },
  );
}
