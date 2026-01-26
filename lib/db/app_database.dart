import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';

part 'app_database.g.dart';

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text()();
  TextColumn get pinHash => text()();
  TextColumn get role => text()();
  IntColumn get teacherId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {username},
      ];
}

class CourseVersions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get teacherId => integer()();
  TextColumn get subject => text()();
  TextColumn get sourcePath => text().nullable()();
  IntColumn get granularity => integer()();
  TextColumn get textbookText => text()();
  TextColumn get treeGenStatus =>
      text().withDefault(const Constant('pending'))();
  TextColumn get treeGenRawResponse => text().nullable()();
  BoolColumn get treeGenValid => boolean().withDefault(const Constant(false))();
  TextColumn get treeGenParseError => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

class CourseNodes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get courseVersionId => integer()();
  TextColumn get kpKey => text()();
  TextColumn get title => text()();
  TextColumn get description => text()();
  IntColumn get orderIndex => integer()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {courseVersionId, kpKey},
      ];
}

class CourseEdges extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get courseVersionId => integer()();
  TextColumn get fromKpKey => text()();
  TextColumn get toKpKey => text()();
}

class StudentCourseAssignments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get studentId => integer()();
  IntColumn get courseVersionId => integer()();
  DateTimeColumn get assignedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {studentId, courseVersionId},
      ];
}

class ProgressEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get studentId => integer()();
  IntColumn get courseVersionId => integer()();
  TextColumn get kpKey => text()();
  BoolColumn get lit => boolean().withDefault(const Constant(false))();
  TextColumn get questionLevel => text().nullable()();
  TextColumn get summaryText => text().nullable()();
  TextColumn get summaryRawResponse => text().nullable()();
  BoolColumn get summaryValid => boolean().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {studentId, courseVersionId, kpKey},
      ];
}

class ChatSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get studentId => integer()();
  IntColumn get courseVersionId => integer()();
  TextColumn get kpKey => text()();
  TextColumn get title => text().nullable()();
  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get summaryText => text().nullable()();
  BoolColumn get summaryLit => boolean().nullable()();
  TextColumn get summaryRawResponse => text().nullable()();
  BoolColumn get summaryValid => boolean().nullable()();
  IntColumn get summarizeCallId => integer().nullable()();
}

class ChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer()();
  TextColumn get role => text()();
  TextColumn get content => text()();
  TextColumn get action => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class LlmCalls extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get callHash => text()();
  TextColumn get promptName => text()();
  TextColumn get renderedPrompt => text()();
  TextColumn get model => text()();
  TextColumn get baseUrl => text()();
  TextColumn get responseText => text().nullable()();
  TextColumn get responseJson => text().nullable()();
  BoolColumn get parseValid => boolean().nullable()();
  TextColumn get parseError => text().nullable()();
  IntColumn get latencyMs => integer().nullable()();
  IntColumn get teacherId => integer().nullable()();
  IntColumn get studentId => integer().nullable()();
  IntColumn get courseVersionId => integer().nullable()();
  IntColumn get sessionId => integer().nullable()();
  TextColumn get kpKey => text().nullable()();
  TextColumn get action => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get mode => text()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {callHash},
      ];
}

class AppSettings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get baseUrl => text()();
  TextColumn get providerId => text().nullable()();
  TextColumn get model => text()();
  IntColumn get timeoutSeconds => integer()();
  IntColumn get maxTokens => integer()();
  IntColumn get ttsInitialDelayMs =>
      integer().withDefault(const Constant(60000))();
  TextColumn get ttsAudioPath => text().nullable()();
  TextColumn get logDirectory => text().nullable()();
  TextColumn get llmLogPath => text().nullable()();
  TextColumn get ttsLogPath => text().nullable()();
  TextColumn get llmMode => text()();
  TextColumn get locale => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class ApiConfigs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get baseUrl => text()();
  TextColumn get model => text()();
  TextColumn get apiKeyHash => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {baseUrl, model, apiKeyHash},
      ];
}

class PromptTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get teacherId => integer()();
  TextColumn get promptName => text()();
  TextColumn get content => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(
  tables: [
    Users,
    CourseVersions,
    CourseNodes,
    CourseEdges,
    StudentCourseAssignments,
    ProgressEntries,
    ChatSessions,
    ChatMessages,
    LlmCalls,
    AppSettings,
    ApiConfigs,
    PromptTemplates,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(QueryExecutor executor) : super(executor);

  factory AppDatabase.open() {
    return AppDatabase(_openConnection());
  }

  factory AppDatabase.forTesting(QueryExecutor executor) {
    return AppDatabase(executor);
  }

  @override
  int get schemaVersion => 14;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(courseVersions, courseVersions.treeGenValid);
            await m.addColumn(chatSessions, chatSessions.summaryValid);
          }
          if (from < 3) {
            await m.addColumn(
              courseVersions,
              courseVersions.treeGenParseError,
            );
          }
          if (from < 4) {
            await m.addColumn(llmCalls, llmCalls.teacherId);
            await m.addColumn(llmCalls, llmCalls.studentId);
            await m.addColumn(llmCalls, llmCalls.courseVersionId);
            await m.addColumn(llmCalls, llmCalls.sessionId);
            await m.addColumn(llmCalls, llmCalls.kpKey);
            await m.addColumn(llmCalls, llmCalls.action);
          }
          if (from < 5) {
            await m.createTable(apiConfigs);
          }
          if (from < 6) {
            await m.addColumn(progressEntries, progressEntries.summaryText);
            await m.addColumn(
              progressEntries,
              progressEntries.summaryRawResponse,
            );
            await m.addColumn(progressEntries, progressEntries.summaryValid);
          }
          if (from < 7) {
            await m.addColumn(appSettings, appSettings.locale);
            await m.createTable(promptTemplates);
          }
          if (from < 8) {
            await m.addColumn(appSettings, appSettings.providerId);
          }
          if (from < 9) {
            await m.addColumn(chatSessions, chatSessions.title);
          }
          if (from < 10) {
            await m.addColumn(progressEntries, progressEntries.questionLevel);
          }
          if (from < 11) {
            await m.addColumn(courseVersions, courseVersions.sourcePath);
          }
          if (from < 12) {
            await m.addColumn(appSettings, appSettings.ttsInitialDelayMs);
          }
          if (from < 13) {
            await m.addColumn(appSettings, appSettings.ttsAudioPath);
          }
          if (from < 14) {
            await m.addColumn(appSettings, appSettings.logDirectory);
            await m.addColumn(appSettings, appSettings.llmLogPath);
            await m.addColumn(appSettings, appSettings.ttsLogPath);
          }
        },
      );

  Future<User?> findUserByUsername(String username) {
    return (select(users)..where((tbl) => tbl.username.equals(username)))
        .getSingleOrNull();
  }

  Future<User?> getUserById(int id) {
    return (select(users)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<bool> hasAnyTeacher() async {
    final query = selectOnly(users)
      ..addColumns([users.id.count()])
      ..where(users.role.equals('teacher'));
    final row = await query.getSingle();
    final count = row.read(users.id.count()) ?? 0;
    return count > 0;
  }

  Future<int> createUser({
    required String username,
    required String pinHash,
    required String role,
    int? teacherId,
  }) {
    return into(users).insert(
      UsersCompanion.insert(
        username: username,
        pinHash: pinHash,
        role: role,
        teacherId: Value(teacherId),
      ),
    );
  }

  Stream<List<User>> watchStudents(int teacherId) {
    return (select(users)
          ..where((tbl) =>
              tbl.role.equals('student') & tbl.teacherId.equals(teacherId)))
        .watch();
  }

  Stream<List<User>> watchTeachers() {
    return (select(users)..where((tbl) => tbl.role.equals('teacher'))).watch();
  }

  Stream<List<CourseVersion>> watchCourseVersions(int teacherId) {
    return (select(courseVersions)
          ..where((tbl) => tbl.teacherId.equals(teacherId)))
        .watch();
  }

  Future<CourseVersion?> getCourseVersionById(int id) {
    return (select(courseVersions)..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
  }

  Stream<List<CourseNode>> watchCourseNodes(int courseVersionId) {
    return (select(courseNodes)
          ..where((tbl) => tbl.courseVersionId.equals(courseVersionId))
          ..orderBy([(tbl) => OrderingTerm(expression: tbl.orderIndex)]))
        .watch();
  }

  Future<List<CourseNode>> getCourseNodes(int courseVersionId) {
    return (select(courseNodes)
          ..where((tbl) => tbl.courseVersionId.equals(courseVersionId))
          ..orderBy([(tbl) => OrderingTerm(expression: tbl.orderIndex)]))
        .get();
  }

  Future<CourseNode?> getCourseNodeByKey(
    int courseVersionId,
    String kpKey,
  ) {
    return (select(courseNodes)
          ..where((tbl) =>
              tbl.courseVersionId.equals(courseVersionId) &
              tbl.kpKey.equals(kpKey)))
        .getSingleOrNull();
  }

  Future<int> createCourseVersion({
    required int teacherId,
    required String subject,
    required int granularity,
    required String textbookText,
    String? sourcePath,
  }) {
    return into(courseVersions).insert(
      CourseVersionsCompanion.insert(
        teacherId: teacherId,
        subject: subject,
        sourcePath: Value(sourcePath),
        granularity: granularity,
        textbookText: textbookText,
        treeGenStatus: const Value('pending'),
        treeGenValid: const Value(false),
      ),
    );
  }

  Future<void> updateCourseVersion({
    required int id,
    required String subject,
    required int granularity,
    required String textbookText,
    String? sourcePath,
  }) async {
    await (update(courseVersions)..where((tbl) => tbl.id.equals(id))).write(
      CourseVersionsCompanion(
        subject: Value(subject),
        sourcePath:
            sourcePath == null ? const Value.absent() : Value(sourcePath),
        granularity: Value(granularity),
        textbookText: Value(textbookText),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> assignStudent({
    required int studentId,
    required int courseVersionId,
  }) async {
    await into(studentCourseAssignments).insert(
      StudentCourseAssignmentsCompanion.insert(
        studentId: studentId,
        courseVersionId: courseVersionId,
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Stream<List<CourseVersion>> watchAssignedCourses(int studentId) {
    final query = select(courseVersions).join([
      innerJoin(
        studentCourseAssignments,
        studentCourseAssignments.courseVersionId.equalsExp(courseVersions.id),
      ),
    ])
      ..where(studentCourseAssignments.studentId.equals(studentId));

    return query.watch().map((rows) {
      return rows.map((row) => row.readTable(courseVersions)).toList();
    });
  }

  Future<List<StudentCourseAssignment>> getAssignmentsForCourse(
    int courseVersionId,
  ) {
    return (select(studentCourseAssignments)
          ..where((tbl) => tbl.courseVersionId.equals(courseVersionId)))
        .get();
  }

  Stream<List<StudentCourseAssignment>> watchAssignmentsForCourse(
    int courseVersionId,
  ) {
    return (select(studentCourseAssignments)
          ..where((tbl) => tbl.courseVersionId.equals(courseVersionId)))
        .watch();
  }

  Stream<List<ChatMessage>> watchMessagesForSession(int sessionId) {
    return (select(chatMessages)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([(tbl) => OrderingTerm(expression: tbl.createdAt)]))
        .watch();
  }

  Stream<List<ProgressEntry>> watchProgressForCourse(
    int studentId,
    int courseVersionId,
  ) {
    return (select(progressEntries)
          ..where((tbl) =>
              tbl.studentId.equals(studentId) &
              tbl.courseVersionId.equals(courseVersionId)))
        .watch();
  }

  Future<List<ChatMessage>> getMessagesForSession(int sessionId) {
    return (select(chatMessages)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([(tbl) => OrderingTerm(expression: tbl.createdAt)]))
        .get();
  }

  Future<void> updateChatMessageContent({
    required int messageId,
    required String content,
  }) {
    return (update(chatMessages)..where((tbl) => tbl.id.equals(messageId)))
        .write(
      ChatMessagesCompanion(content: Value(content)),
    );
  }

  Future<ChatSession?> getSession(int sessionId) {
    return (select(chatSessions)..where((tbl) => tbl.id.equals(sessionId)))
        .getSingleOrNull();
  }

  Future<void> renameSession({
    required int sessionId,
    required String title,
  }) {
    final cleaned = title.trim();
    return (update(chatSessions)..where((tbl) => tbl.id.equals(sessionId)))
        .write(
      ChatSessionsCompanion(
        title: Value(cleaned.isEmpty ? null : cleaned),
      ),
    );
  }

  Future<void> deleteSession(int sessionId) async {
    await transaction(() async {
      await (delete(chatMessages)
            ..where((tbl) => tbl.sessionId.equals(sessionId)))
          .go();
      await (delete(llmCalls)..where((tbl) => tbl.sessionId.equals(sessionId)))
          .go();
      await (delete(chatSessions)..where((tbl) => tbl.id.equals(sessionId)))
          .go();
    });
  }

  Future<void> deleteMessagesFrom({
    required int sessionId,
    required int fromMessageId,
  }) {
    return (delete(chatMessages)
          ..where((tbl) =>
              tbl.sessionId.equals(sessionId) &
              tbl.id.isBiggerOrEqualValue(fromMessageId)))
        .go();
  }

  Future<LlmCall?> getLatestLlmCallForSession({
    required int sessionId,
    required String promptName,
  }) {
    return (select(llmCalls)
          ..where((tbl) =>
              tbl.sessionId.equals(sessionId) &
              tbl.promptName.equals(promptName))
          ..orderBy([
            (tbl) => OrderingTerm(
                  expression: tbl.createdAt,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<List<ChatSession>> getSessionsForNode({
    required int studentId,
    required int courseVersionId,
    required String kpKey,
  }) {
    return (select(chatSessions)
          ..where((tbl) =>
              tbl.studentId.equals(studentId) &
              tbl.courseVersionId.equals(courseVersionId) &
              tbl.kpKey.equals(kpKey))
          ..orderBy([(tbl) => OrderingTerm(expression: tbl.startedAt)]))
        .get();
  }

  Future<List<StudentSessionInfo>> getSessionsForStudent(int studentId) async {
    final rows = await customSelect(
      '''
SELECT s.id AS session_id,
       s.title AS session_title,
       s.started_at AS started_at,
       s.course_version_id AS course_version_id,
       s.kp_key AS kp_key,
       c.subject AS course_subject,
       n.title AS node_title
FROM chat_sessions s
LEFT JOIN course_versions c ON c.id = s.course_version_id
LEFT JOIN course_nodes n ON n.course_version_id = s.course_version_id
  AND n.kp_key = s.kp_key
WHERE s.student_id = ?
ORDER BY s.started_at DESC
''',
      variables: [Variable.withInt(studentId)],
      readsFrom: {chatSessions, courseVersions, courseNodes},
    ).get();

    return rows.map((row) => StudentSessionInfo.fromRow(row.data)).toList();
  }

  Future<ProgressEntry?> getProgress({
    required int studentId,
    required int courseVersionId,
    required String kpKey,
  }) {
    return (select(progressEntries)
          ..where((tbl) =>
              tbl.studentId.equals(studentId) &
              tbl.courseVersionId.equals(courseVersionId) &
              tbl.kpKey.equals(kpKey)))
        .getSingleOrNull();
  }

  Future<void> upsertProgress({
    required int studentId,
    required int courseVersionId,
    required String kpKey,
    required bool lit,
  }) async {
    final existing = await getProgress(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: kpKey,
    );
    if (existing == null) {
      await into(progressEntries).insert(
        ProgressEntriesCompanion.insert(
          studentId: studentId,
          courseVersionId: courseVersionId,
          kpKey: kpKey,
          lit: Value(lit),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return;
    }
    if (existing.lit && !lit) {
      return;
    }
    await (update(progressEntries)..where((tbl) => tbl.id.equals(existing.id)))
        .write(
      ProgressEntriesCompanion(
        lit: Value(lit || existing.lit),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setProgressLit({
    required int studentId,
    required int courseVersionId,
    required String kpKey,
    required bool lit,
  }) async {
    final existing = await getProgress(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: kpKey,
    );
    if (existing == null) {
      await into(progressEntries).insert(
        ProgressEntriesCompanion.insert(
          studentId: studentId,
          courseVersionId: courseVersionId,
          kpKey: kpKey,
          lit: Value(lit),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return;
    }
    await (update(progressEntries)..where((tbl) => tbl.id.equals(existing.id)))
        .write(
      ProgressEntriesCompanion(
        lit: Value(lit),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> upsertProgressSummary({
    required int studentId,
    required int courseVersionId,
    required String kpKey,
    required String? summaryText,
    required String? summaryRawResponse,
    required bool? summaryValid,
    bool? summaryLit,
    String? questionLevel,
  }) async {
    final existing = await getProgress(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: kpKey,
    );
    final shouldLit = summaryLit == true;
    if (existing == null) {
      await into(progressEntries).insert(
        ProgressEntriesCompanion.insert(
          studentId: studentId,
          courseVersionId: courseVersionId,
          kpKey: kpKey,
          lit: Value(shouldLit),
          questionLevel: Value(questionLevel),
          summaryText: Value(summaryText),
          summaryRawResponse: Value(summaryRawResponse),
          summaryValid: Value(summaryValid),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return;
    }
    final newLit = existing.lit || shouldLit;
    await (update(progressEntries)..where((tbl) => tbl.id.equals(existing.id)))
        .write(
      ProgressEntriesCompanion(
        lit: Value(newLit),
        questionLevel: Value(questionLevel ?? existing.questionLevel),
        summaryText: Value(summaryText),
        summaryRawResponse: Value(summaryRawResponse),
        summaryValid: Value(summaryValid),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> upsertTreeViewState({
    required int studentId,
    required int courseVersionId,
    required String viewStateJson,
  }) {
    return into(progressEntries).insert(
      ProgressEntriesCompanion.insert(
        studentId: studentId,
        courseVersionId: courseVersionId,
        kpKey: kTreeViewStateKpKey,
        lit: const Value(false),
        summaryText: Value(viewStateJson),
        updatedAt: Value(DateTime.now()),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<int> countLitNodes({
    required int studentId,
    required int courseVersionId,
  }) async {
    final query = selectOnly(progressEntries)
      ..addColumns([progressEntries.id.count()])
      ..where(progressEntries.studentId.equals(studentId))
      ..where(progressEntries.courseVersionId.equals(courseVersionId))
      ..where(progressEntries.lit.equals(true));
    final row = await query.getSingle();
    return row.read(progressEntries.id.count()) ?? 0;
  }

  Future<List<LlmLogEntry>> getLlmLogEntries() async {
    final rows = await customSelect(
      '''
SELECT l.id,
       l.call_hash,
       l.prompt_name,
       l.rendered_prompt,
       l.model,
       l.base_url,
       l.response_text,
       l.response_json,
       l.parse_valid,
       l.parse_error,
       l.latency_ms,
       l.teacher_id,
       l.student_id,
       l.course_version_id,
       l.session_id,
       l.kp_key,
       l.action,
       l.created_at,
       l.mode,
       t.username AS teacher_name,
       s.username AS student_name
FROM llm_calls l
LEFT JOIN users t ON t.id = l.teacher_id
LEFT JOIN users s ON s.id = l.student_id
ORDER BY l.created_at DESC
''',
      readsFrom: {llmCalls, users},
    ).get();

    return rows.map((row) => LlmLogEntry.fromRow(row.data)).toList();
  }

  Stream<List<ApiConfig>> watchApiConfigs() {
    return (select(apiConfigs)
          ..orderBy([
            (tbl) => OrderingTerm(expression: tbl.baseUrl),
            (tbl) => OrderingTerm(expression: tbl.model),
            (tbl) => OrderingTerm(expression: tbl.apiKeyHash),
          ]))
        .watch();
  }

  Future<int> countApiConfigsByHash(String apiKeyHash) async {
    final query = selectOnly(apiConfigs)
      ..addColumns([apiConfigs.id.count()])
      ..where(apiConfigs.apiKeyHash.equals(apiKeyHash));
    final row = await query.getSingle();
    return row.read(apiConfigs.id.count()) ?? 0;
  }

  Future<int> insertApiConfig({
    required String baseUrl,
    required String model,
    required String apiKeyHash,
  }) {
    return into(apiConfigs).insert(
      ApiConfigsCompanion.insert(
        baseUrl: baseUrl.trim(),
        model: model.trim(),
        apiKeyHash: apiKeyHash.trim(),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<int> deleteApiConfigById(int id) {
    return (delete(apiConfigs)..where((tbl) => tbl.id.equals(id))).go();
  }

  Future<void> updateUserPin({
    required int userId,
    required String pinHash,
  }) {
    return (update(users)..where((tbl) => tbl.id.equals(userId))).write(
      UsersCompanion(pinHash: Value(pinHash)),
    );
  }

  Future<void> deleteStudent(int studentId) async {
    await transaction(() async {
      await _deleteStudentInternal(studentId);
    });
  }

  Future<void> deleteTeacher(int teacherId) async {
    await transaction(() async {
      final students = await (select(users)
            ..where((tbl) =>
                tbl.role.equals('student') & tbl.teacherId.equals(teacherId)))
          .get();
      for (final student in students) {
        await _deleteStudentInternal(student.id);
      }
      final courses = await (select(courseVersions)
            ..where((tbl) => tbl.teacherId.equals(teacherId)))
          .get();
      final courseIds = courses.map((course) => course.id).toList();
      if (courseIds.isNotEmpty) {
        await (delete(courseNodes)
              ..where((tbl) => tbl.courseVersionId.isIn(courseIds)))
            .go();
        await (delete(courseEdges)
              ..where((tbl) => tbl.courseVersionId.isIn(courseIds)))
            .go();
        await (delete(studentCourseAssignments)
              ..where((tbl) => tbl.courseVersionId.isIn(courseIds)))
            .go();
        await (delete(courseVersions)..where((tbl) => tbl.id.isIn(courseIds)))
            .go();
      }
      await (delete(promptTemplates)
            ..where((tbl) => tbl.teacherId.equals(teacherId)))
          .go();
      await (delete(llmCalls)..where((tbl) => tbl.teacherId.equals(teacherId)))
          .go();
      await (delete(users)..where((tbl) => tbl.id.equals(teacherId))).go();
    });
  }

  Future<void> deleteCourseVersion(int courseVersionId) async {
    await transaction(() async {
      final sessions = await (select(chatSessions)
            ..where((tbl) => tbl.courseVersionId.equals(courseVersionId)))
          .get();
      final sessionIds = sessions.map((session) => session.id).toList();
      if (sessionIds.isNotEmpty) {
        await (delete(chatMessages)
              ..where((tbl) => tbl.sessionId.isIn(sessionIds)))
            .go();
        await (delete(llmCalls)..where((tbl) => tbl.sessionId.isIn(sessionIds)))
            .go();
        await (delete(chatSessions)
              ..where((tbl) => tbl.id.isIn(sessionIds)))
            .go();
      }
      await (delete(progressEntries)
            ..where((tbl) => tbl.courseVersionId.equals(courseVersionId)))
          .go();
      await (delete(studentCourseAssignments)
            ..where((tbl) => tbl.courseVersionId.equals(courseVersionId)))
          .go();
      await (delete(courseNodes)
            ..where((tbl) => tbl.courseVersionId.equals(courseVersionId)))
          .go();
      await (delete(courseEdges)
            ..where((tbl) => tbl.courseVersionId.equals(courseVersionId)))
          .go();
      await (delete(llmCalls)
            ..where((tbl) => tbl.courseVersionId.equals(courseVersionId)))
          .go();
      await (delete(courseVersions)
            ..where((tbl) => tbl.id.equals(courseVersionId)))
          .go();
    });
  }

  Future<void> ensureAdminUser({
    required String username,
    required String pinHash,
  }) async {
    final existingAdmin = await (select(users)
          ..where((tbl) => tbl.role.equals('admin')))
        .getSingleOrNull();
    if (existingAdmin != null) {
      return;
    }
    final existingUser = await findUserByUsername(username);
    if (existingUser == null) {
      await createUser(
        username: username,
        pinHash: pinHash,
        role: 'admin',
      );
      return;
    }
    await (update(users)..where((tbl) => tbl.id.equals(existingUser.id))).write(
      UsersCompanion(
        role: const Value('admin'),
        pinHash: Value(pinHash),
        teacherId: const Value(null),
      ),
    );
  }

  Future<void> _deleteStudentInternal(int studentId) async {
    final sessions = await (select(chatSessions)
          ..where((tbl) => tbl.studentId.equals(studentId)))
        .get();
    final sessionIds = sessions.map((session) => session.id).toList();
    if (sessionIds.isNotEmpty) {
      await (delete(chatMessages)
            ..where((tbl) => tbl.sessionId.isIn(sessionIds)))
          .go();
      await (delete(llmCalls)..where((tbl) => tbl.sessionId.isIn(sessionIds)))
          .go();
      await (delete(chatSessions)..where((tbl) => tbl.id.isIn(sessionIds)))
          .go();
    }
    await (delete(progressEntries)
          ..where((tbl) => tbl.studentId.equals(studentId)))
        .go();
    await (delete(studentCourseAssignments)
          ..where((tbl) => tbl.studentId.equals(studentId)))
        .go();
    await (delete(llmCalls)..where((tbl) => tbl.studentId.equals(studentId)))
        .go();
    await (delete(users)..where((tbl) => tbl.id.equals(studentId))).go();
  }

  Future<PromptTemplate?> getActivePromptTemplate({
    required int teacherId,
    required String promptName,
  }) {
    return (select(promptTemplates)
          ..where((tbl) =>
              tbl.teacherId.equals(teacherId) &
              tbl.promptName.equals(promptName) &
              tbl.isActive.equals(true))
          ..orderBy([
            (tbl) => OrderingTerm(
                  expression: tbl.createdAt,
                  mode: OrderingMode.desc,
                )
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  Stream<List<PromptTemplate>> watchPromptTemplates({
    required int teacherId,
    required String promptName,
  }) {
    return (select(promptTemplates)
          ..where((tbl) =>
              tbl.teacherId.equals(teacherId) &
              tbl.promptName.equals(promptName))
          ..orderBy([
            (tbl) => OrderingTerm(
                  expression: tbl.createdAt,
                  mode: OrderingMode.desc,
                )
          ]))
        .watch();
  }

  Future<int> insertPromptTemplate({
    required int teacherId,
    required String promptName,
    required String content,
  }) async {
    return transaction(() async {
      await (update(promptTemplates)
            ..where((tbl) =>
                tbl.teacherId.equals(teacherId) &
                tbl.promptName.equals(promptName)))
          .write(
        const PromptTemplatesCompanion(isActive: Value(false)),
      );
      return into(promptTemplates).insert(
        PromptTemplatesCompanion.insert(
          teacherId: teacherId,
          promptName: promptName,
          content: content,
          isActive: const Value(true),
        ),
      );
    });
  }

  Future<void> setActivePromptTemplate({
    required int teacherId,
    required String promptName,
    required int templateId,
  }) async {
    await transaction(() async {
      await (update(promptTemplates)
            ..where((tbl) =>
                tbl.teacherId.equals(teacherId) &
                tbl.promptName.equals(promptName)))
          .write(
        const PromptTemplatesCompanion(isActive: Value(false)),
      );
      await (update(promptTemplates)
            ..where((tbl) =>
                tbl.id.equals(templateId) &
                tbl.teacherId.equals(teacherId) &
                tbl.promptName.equals(promptName)))
          .write(
        const PromptTemplatesCompanion(isActive: Value(true)),
      );
    });
  }

  Future<void> clearActivePromptTemplates({
    required int teacherId,
    required String promptName,
  }) {
    return (update(promptTemplates)
          ..where((tbl) =>
              tbl.teacherId.equals(teacherId) &
              tbl.promptName.equals(promptName)))
        .write(
      const PromptTemplatesCompanion(isActive: Value(false)),
    );
  }
}

class LlmLogEntry {
  LlmLogEntry({
    required this.id,
    required this.callHash,
    required this.promptName,
    required this.renderedPrompt,
    required this.model,
    required this.baseUrl,
    required this.responseText,
    required this.responseJson,
    required this.parseValid,
    required this.parseError,
    required this.latencyMs,
    required this.teacherId,
    required this.studentId,
    required this.courseVersionId,
    required this.sessionId,
    required this.kpKey,
    required this.action,
    required this.createdAt,
    required this.mode,
    required this.teacherName,
    required this.studentName,
  });

  final int id;
  final String callHash;
  final String promptName;
  final String renderedPrompt;
  final String model;
  final String baseUrl;
  final String? responseText;
  final String? responseJson;
  final bool? parseValid;
  final String? parseError;
  final int? latencyMs;
  final int? teacherId;
  final int? studentId;
  final int? courseVersionId;
  final int? sessionId;
  final String? kpKey;
  final String? action;
  final DateTime createdAt;
  final String mode;
  final String? teacherName;
  final String? studentName;

  factory LlmLogEntry.fromRow(Map<String, Object?> row) {
    final createdRaw = row['created_at'];
    DateTime createdAt;
    if (createdRaw is DateTime) {
      createdAt = createdRaw;
    } else if (createdRaw is String) {
      createdAt = DateTime.tryParse(createdRaw) ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }
    return LlmLogEntry(
      id: row['id'] as int,
      callHash: row['call_hash'] as String,
      promptName: row['prompt_name'] as String,
      renderedPrompt: row['rendered_prompt'] as String,
      model: row['model'] as String,
      baseUrl: row['base_url'] as String,
      responseText: row['response_text'] as String?,
      responseJson: row['response_json'] as String?,
      parseValid: _boolFromRow(row['parse_valid']),
      parseError: row['parse_error'] as String?,
      latencyMs: row['latency_ms'] as int?,
      teacherId: row['teacher_id'] as int?,
      studentId: row['student_id'] as int?,
      courseVersionId: row['course_version_id'] as int?,
      sessionId: row['session_id'] as int?,
      kpKey: row['kp_key'] as String?,
      action: row['action'] as String?,
      createdAt: createdAt,
      mode: row['mode'] as String,
      teacherName: row['teacher_name'] as String?,
      studentName: row['student_name'] as String?,
    );
  }

  static bool? _boolFromRow(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is int) {
      return value == 1;
    }
    return null;
  }
}

class StudentSessionInfo {
  StudentSessionInfo({
    required this.sessionId,
    required this.sessionTitle,
    required this.startedAt,
    required this.courseVersionId,
    required this.courseSubject,
    required this.kpKey,
    required this.nodeTitle,
  });

  final int sessionId;
  final String? sessionTitle;
  final DateTime startedAt;
  final int courseVersionId;
  final String? courseSubject;
  final String kpKey;
  final String? nodeTitle;

  factory StudentSessionInfo.fromRow(Map<String, Object?> row) {
    final startedRaw = row['started_at'];
    DateTime startedAt;
    if (startedRaw is DateTime) {
      startedAt = startedRaw;
    } else if (startedRaw is String) {
      startedAt = DateTime.tryParse(startedRaw) ?? DateTime.now();
    } else {
      startedAt = DateTime.now();
    }
    return StudentSessionInfo(
      sessionId: row['session_id'] as int,
      sessionTitle: row['session_title'] as String?,
      startedAt: startedAt,
      courseVersionId: row['course_version_id'] as int,
      courseSubject: row['course_subject'] as String?,
      kpKey: row['kp_key'] as String,
      nodeTitle: row['node_title'] as String?,
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'family_teacher.db'));
    return NativeDatabase(file);
  });
}
