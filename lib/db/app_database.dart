import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../constants.dart';
import '../security/pin_hasher.dart';
import '../services/db_path_provider.dart';

part 'app_database.g.dart';

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text()();
  TextColumn get pinHash => text()();
  TextColumn get role => text()();
  IntColumn get teacherId => integer().nullable()();
  IntColumn get remoteUserId => integer().nullable()();
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
  IntColumn get litPercent => integer().withDefault(const Constant(0))();
  TextColumn get questionLevel => text().nullable()();
  IntColumn get easyPassedCount => integer().withDefault(const Constant(0))();
  IntColumn get mediumPassedCount => integer().withDefault(const Constant(0))();
  IntColumn get hardPassedCount => integer().withDefault(const Constant(0))();
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
  IntColumn get summaryLitPercent => integer().nullable()();
  TextColumn get summaryRawResponse => text().nullable()();
  BoolColumn get summaryValid => boolean().nullable()();
  IntColumn get summarizeCallId => integer().nullable()();
  TextColumn get controlStateJson => text().nullable()();
  DateTimeColumn get controlStateUpdatedAt => dateTime().nullable()();
  TextColumn get evidenceStateJson => text().nullable()();
  DateTimeColumn get evidenceStateUpdatedAt => dateTime().nullable()();
  TextColumn get syncId => text().nullable()();
  DateTimeColumn get syncUpdatedAt => dateTime().nullable()();
  DateTimeColumn get syncUploadedAt => dateTime().nullable()();
}

class CourseRemoteLinks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get courseVersionId => integer()();
  IntColumn get remoteCourseId => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {courseVersionId},
        {remoteCourseId},
      ];
}

class ChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer()();
  TextColumn get role => text()();
  TextColumn get content => text()();
  TextColumn get rawContent => text().nullable()();
  TextColumn get parsedJson => text().nullable()();
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
}

class AppSettings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get baseUrl => text()();
  TextColumn get providerId => text().nullable()();
  TextColumn get model => text()();
  TextColumn get reasoningEffort =>
      text().withDefault(const Constant('medium'))();
  TextColumn get ttsModel => text().nullable()();
  TextColumn get sttModel => text().nullable()();
  IntColumn get timeoutSeconds => integer()();
  IntColumn get maxTokens => integer()();
  IntColumn get ttsInitialDelayMs =>
      integer().withDefault(const Constant(60000))();
  IntColumn get ttsTextLeadMs => integer().withDefault(const Constant(1000))();
  TextColumn get ttsAudioPath => text().nullable()();
  BoolColumn get sttAutoSend => boolean().withDefault(const Constant(false))();
  BoolColumn get enterToSend => boolean().withDefault(const Constant(true))();
  BoolColumn get studyModeEnabled =>
      boolean().withDefault(const Constant(false))();
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
  TextColumn get reasoningEffort =>
      text().withDefault(const Constant('medium'))();
  TextColumn get ttsModel => text().nullable()();
  TextColumn get sttModel => text().nullable()();
  TextColumn get apiKeyHash => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {baseUrl, model, reasoningEffort, ttsModel, sttModel, apiKeyHash},
      ];
}

class PromptTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get teacherId => integer()();
  TextColumn get courseKey => text().nullable()();
  IntColumn get studentId => integer().nullable()();
  TextColumn get promptName => text()();
  TextColumn get content => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class StudentPromptProfiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get teacherId => integer()();
  TextColumn get courseKey => text().nullable()();
  IntColumn get studentId => integer().nullable()();
  TextColumn get gradeLevel => text().nullable()();
  TextColumn get readingLevel => text().nullable()();
  TextColumn get preferredLanguage => text().nullable()();
  TextColumn get interests => text().nullable()();
  TextColumn get preferredTone => text().nullable()();
  TextColumn get preferredPace => text().nullable()();
  TextColumn get preferredFormat => text().nullable()();
  TextColumn get supportNotes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

class StudentPassConfigs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get courseVersionId => integer()();
  IntColumn get studentId => integer()();
  RealColumn get easyWeight => real().withDefault(const Constant(0.25))();
  RealColumn get mediumWeight => real().withDefault(const Constant(0.5))();
  RealColumn get hardWeight => real().withDefault(const Constant(1.0))();
  RealColumn get passThreshold => real().withDefault(const Constant(1.0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {courseVersionId, studentId},
      ];
}

class SyncItemStates extends Table {
  IntColumn get remoteUserId => integer()();
  TextColumn get domain => text()();
  TextColumn get scopeKey => text()();
  TextColumn get contentHash => text()();
  DateTimeColumn get lastChangedAt => dateTime()();
  DateTimeColumn get lastSyncedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {remoteUserId, domain, scopeKey};
}

class SyncMetadataEntries extends Table {
  IntColumn get remoteUserId => integer()();
  TextColumn get kind => text()();
  TextColumn get domain => text()();
  TextColumn get scopeKey => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {remoteUserId, kind, domain, scopeKey};
}

class SyncRelevantChange {
  const SyncRelevantChange({
    this.localUserIds = const <int>{},
    this.refreshEnrollmentState = true,
    this.refreshSessionArtifacts = true,
  });

  final Set<int> localUserIds;
  final bool refreshEnrollmentState;
  final bool refreshSessionArtifacts;

  bool get isEmpty =>
      localUserIds.isEmpty ||
      (!refreshEnrollmentState && !refreshSessionArtifacts);
}

class SyncedProgressUpsert {
  const SyncedProgressUpsert({
    required this.studentId,
    required this.courseVersionId,
    required this.kpKey,
    required this.lit,
    required this.litPercent,
    required this.updatedAt,
    this.easyPassedCount = 0,
    this.mediumPassedCount = 0,
    this.hardPassedCount = 0,
    this.questionLevel,
    this.summaryText,
    this.summaryRawResponse,
    this.summaryValid,
  });

  final int studentId;
  final int courseVersionId;
  final String kpKey;
  final bool lit;
  final int litPercent;
  final int easyPassedCount;
  final int mediumPassedCount;
  final int hardPassedCount;
  final String? questionLevel;
  final String? summaryText;
  final String? summaryRawResponse;
  final bool? summaryValid;
  final DateTime updatedAt;
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
    StudentPromptProfiles,
    StudentPassConfigs,
    CourseRemoteLinks,
    SyncItemStates,
    SyncMetadataEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(QueryExecutor executor) : super(executor);
  static final String _remoteTeacherPlaceholderPinHash =
      PinHasher.hash('remote_teacher_placeholder');
  static final String _remoteStudentPlaceholderPinHash =
      PinHasher.hash('remote_student_placeholder');
  static final String _remoteUserPlaceholderPinHash =
      PinHasher.hash('remote_user_placeholder');
  Future<void> Function(SyncRelevantChange change)? _onSyncRelevantChange;

  factory AppDatabase.open() {
    return AppDatabase(_openConnection());
  }

  factory AppDatabase.forTesting(QueryExecutor executor) {
    return AppDatabase(executor);
  }

  void setSyncRelevantChangeCallback(
    Future<void> Function(SyncRelevantChange change)? callback,
  ) {
    _onSyncRelevantChange = callback;
  }

  Future<void> _notifySyncRelevantChange([
    SyncRelevantChange change = const SyncRelevantChange(),
  ]) async {
    final callback = _onSyncRelevantChange;
    if (callback == null || change.isEmpty) {
      return;
    }
    await callback(change);
  }

  Future<void> _notifySyncRelevantUsers(
    Iterable<int> userIds, {
    bool refreshEnrollmentState = true,
    bool refreshSessionArtifacts = false,
  }) async {
    final normalized = <int>{};
    for (final userId in userIds) {
      if (userId > 0) {
        normalized.add(userId);
      }
    }
    await _notifySyncRelevantChange(
      SyncRelevantChange(
        localUserIds: normalized,
        refreshEnrollmentState: refreshEnrollmentState,
        refreshSessionArtifacts: refreshSessionArtifacts,
      ),
    );
  }

  Future<Set<int>> _syncAffectedUsersForCourseVersion(
      int courseVersionId) async {
    final affected = <int>{};
    final course = await getCourseVersionById(courseVersionId);
    if (course != null && course.teacherId > 0) {
      affected.add(course.teacherId);
    }
    final assignments = await getAssignmentsForCourse(courseVersionId);
    for (final assignment in assignments) {
      if (assignment.studentId > 0) {
        affected.add(assignment.studentId);
      }
    }
    return affected;
  }

  Set<int> _syncAffectedUsersForTeacherOnly(int teacherId) {
    if (teacherId <= 0) {
      return const <int>{};
    }
    return <int>{teacherId};
  }

  Future<Set<int>> _syncAffectedUsersForCourseTeacherOnly(
    int courseVersionId,
  ) async {
    final course = await getCourseVersionById(courseVersionId);
    if (course == null || course.teacherId <= 0) {
      return const <int>{};
    }
    return <int>{course.teacherId};
  }

  Future<Set<int>> _syncAffectedUsersForTeacher(
    int teacherId, {
    required bool includeAssignedStudents,
  }) async {
    final affected = <int>{};
    if (teacherId > 0) {
      affected.add(teacherId);
    }
    if (!includeAssignedStudents) {
      return affected;
    }
    final courses = await getCourseVersionsForTeacher(teacherId);
    for (final course in courses) {
      final assignments = await getAssignmentsForCourse(course.id);
      for (final assignment in assignments) {
        if (assignment.studentId > 0) {
          affected.add(assignment.studentId);
        }
      }
    }
    return affected;
  }

  Future<Set<int>> _syncAffectedUsersForStudent(
    int studentId, {
    required bool includeAssignedTeachers,
  }) async {
    final affected = <int>{};
    if (studentId > 0) {
      affected.add(studentId);
    }
    if (!includeAssignedTeachers) {
      return affected;
    }
    final courses = await getAssignedCoursesForStudent(studentId);
    for (final course in courses) {
      if (course.teacherId > 0) {
        affected.add(course.teacherId);
      }
    }
    return affected;
  }

  Future<Set<int>> _syncAffectedUsersForUser(int userId) async {
    final user = await getUserById(userId);
    if (user == null) {
      return const <int>{};
    }
    if (user.role == 'teacher') {
      return _syncAffectedUsersForTeacher(
        userId,
        includeAssignedStudents: true,
      );
    }
    if (user.role == 'student') {
      return _syncAffectedUsersForStudent(
        userId,
        includeAssignedTeachers: true,
      );
    }
    return <int>{userId};
  }

  @override
  int get schemaVersion => 30;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS '
            'uq_users_remote_user_id '
            'ON users(remote_user_id) '
            'WHERE remote_user_id IS NOT NULL',
          );
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
          if (from < 16 && from >= 7) {
            await m.addColumn(promptTemplates, promptTemplates.courseKey);
            await m.addColumn(promptTemplates, promptTemplates.studentId);
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
          if (from < 15) {
            await m.addColumn(appSettings, appSettings.ttsTextLeadMs);
          }
          if (from < 17) {
            await m.addColumn(appSettings, appSettings.ttsModel);
            await m.addColumn(appSettings, appSettings.sttModel);
            await m.addColumn(appSettings, appSettings.sttAutoSend);
            if (from >= 5) {
              await m.addColumn(apiConfigs, apiConfigs.ttsModel);
              await m.addColumn(apiConfigs, apiConfigs.sttModel);
            }
          }
          if (from < 18) {
            await m.addColumn(appSettings, appSettings.studyModeEnabled);
          }
          if (from < 19) {
            await m.addColumn(progressEntries, progressEntries.litPercent);
            await m.addColumn(chatSessions, chatSessions.summaryLitPercent);
          }
          if (from < 20) {
            await m.addColumn(chatMessages, chatMessages.rawContent);
            await m.addColumn(chatMessages, chatMessages.parsedJson);
          }
          if (from < 21) {
            await m.addColumn(appSettings, appSettings.enterToSend);
          }
          if (from < 22) {
            await m.createTable(studentPromptProfiles);
          }
          if (from < 23) {
            await m.addColumn(users, users.remoteUserId);
            await m.addColumn(chatSessions, chatSessions.syncId);
            await m.addColumn(chatSessions, chatSessions.syncUpdatedAt);
            await m.addColumn(chatSessions, chatSessions.syncUploadedAt);
            await m.createTable(courseRemoteLinks);
          }
          if (from < 24) {
            await m.createTable(syncItemStates);
            await m.createTable(syncMetadataEntries);
          }
          if (from < 25) {
            await ensureRemoteUserUniqueness();
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS '
              'uq_users_remote_user_id '
              'ON users(remote_user_id) '
              'WHERE remote_user_id IS NOT NULL',
            );
          }
          if (from < 26) {
            await m.addColumn(chatSessions, chatSessions.controlStateJson);
            await m.addColumn(
              chatSessions,
              chatSessions.controlStateUpdatedAt,
            );
            await m.addColumn(chatSessions, chatSessions.evidenceStateJson);
            await m.addColumn(
              chatSessions,
              chatSessions.evidenceStateUpdatedAt,
            );
          }
          if (from < 27) {
            await m.addColumn(appSettings, appSettings.reasoningEffort);
            if (from >= 5) {
              await m.addColumn(apiConfigs, apiConfigs.reasoningEffort);
            }
          }
          if (from < 28) {
            await customStatement(
              'ALTER TABLE progress_entries '
              'ADD COLUMN easy_passed_count INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE progress_entries '
              'ADD COLUMN medium_passed_count INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE progress_entries '
              'ADD COLUMN hard_passed_count INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (from < 29) {
            await m.createTable(studentPassConfigs);
          }
          if (from < 30) {
            await customStatement('''
CREATE TABLE llm_calls_new (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  call_hash TEXT NOT NULL,
  prompt_name TEXT NOT NULL,
  rendered_prompt TEXT NOT NULL,
  model TEXT NOT NULL,
  base_url TEXT NOT NULL,
  response_text TEXT NULL,
  response_json TEXT NULL,
  parse_valid INTEGER NULL CHECK (parse_valid IN (0, 1)),
  parse_error TEXT NULL,
  latency_ms INTEGER NULL,
  teacher_id INTEGER NULL,
  student_id INTEGER NULL,
  course_version_id INTEGER NULL,
  session_id INTEGER NULL,
  kp_key TEXT NULL,
  action TEXT NULL,
  created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  mode TEXT NOT NULL
)
''');
            await customStatement('''
INSERT INTO llm_calls_new (
  id,
  call_hash,
  prompt_name,
  rendered_prompt,
  model,
  base_url,
  response_text,
  response_json,
  parse_valid,
  parse_error,
  latency_ms,
  teacher_id,
  student_id,
  course_version_id,
  session_id,
  kp_key,
  action,
  created_at,
  mode
)
SELECT
  id,
  call_hash,
  prompt_name,
  rendered_prompt,
  model,
  base_url,
  response_text,
  response_json,
  parse_valid,
  parse_error,
  latency_ms,
  teacher_id,
  student_id,
  course_version_id,
  session_id,
  kp_key,
  action,
  created_at,
  mode
FROM llm_calls
ORDER BY id
''');
            await customStatement('DROP TABLE llm_calls');
            await customStatement(
              'ALTER TABLE llm_calls_new RENAME TO llm_calls',
            );
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
    int? remoteUserId,
  }) {
    return into(users).insert(
      UsersCompanion.insert(
        username: username,
        pinHash: pinHash,
        role: role,
        teacherId: Value(teacherId),
        remoteUserId: Value(remoteUserId),
      ),
    );
  }

  Future<User?> findUserByRemoteId(int remoteUserId) {
    return (select(users)
          ..where((tbl) => tbl.remoteUserId.equals(remoteUserId)))
        .getSingleOrNull();
  }

  Future<void> updateUsername({
    required int userId,
    required String username,
  }) async {
    final affectedUsers = await _syncAffectedUsersForUser(userId);
    await (update(users)..where((tbl) => tbl.id.equals(userId))).write(
      UsersCompanion(username: Value(username)),
    );
    await _notifySyncRelevantUsers(affectedUsers);
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

  Future<List<CourseVersion>> getCourseVersionsForTeacher(int teacherId) {
    return (select(courseVersions)
          ..where((tbl) => tbl.teacherId.equals(teacherId)))
        .get();
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
  }) async {
    final courseVersionId = await into(courseVersions).insert(
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
    await _notifySyncRelevantUsers(<int>{teacherId});
    return courseVersionId;
  }

  Future<void> updateCourseVersion({
    required int id,
    required String subject,
    required int granularity,
    required String textbookText,
    String? sourcePath,
  }) async {
    final affectedUsers = await _syncAffectedUsersForCourseVersion(id);
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
    await _notifySyncRelevantUsers(affectedUsers);
  }

  Future<void> updateCourseVersionSubject({
    required int id,
    required String subject,
  }) async {
    final affectedUsers = await _syncAffectedUsersForCourseVersion(id);
    await (update(courseVersions)..where((tbl) => tbl.id.equals(id))).write(
      CourseVersionsCompanion(
        subject: Value(subject),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _notifySyncRelevantUsers(affectedUsers);
  }

  Future<void> updateCourseVersionTeacherId({
    required int id,
    required int teacherId,
  }) async {
    final affectedUsers = await _syncAffectedUsersForCourseVersion(id);
    await (update(courseVersions)..where((tbl) => tbl.id.equals(id))).write(
      CourseVersionsCompanion(
        teacherId: Value(teacherId),
        updatedAt: Value(DateTime.now()),
      ),
    );
    affectedUsers.addAll(await _syncAffectedUsersForCourseVersion(id));
    await _notifySyncRelevantUsers(affectedUsers);
  }

  Future<void> assignStudent({
    required int studentId,
    required int courseVersionId,
    bool notifySyncUsers = true,
  }) async {
    await into(studentCourseAssignments).insert(
      StudentCourseAssignmentsCompanion.insert(
        studentId: studentId,
        courseVersionId: courseVersionId,
      ),
      mode: InsertMode.insertOrIgnore,
    );
    if (notifySyncUsers) {
      await _notifySyncRelevantUsers(
        await _syncAffectedUsersForCourseVersion(courseVersionId),
      );
    }
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

  Future<List<CourseVersion>> getAssignedCoursesForStudent(
      int studentId) async {
    final query = select(courseVersions).join([
      innerJoin(
        studentCourseAssignments,
        studentCourseAssignments.courseVersionId.equalsExp(courseVersions.id),
      ),
    ])
      ..where(studentCourseAssignments.studentId.equals(studentId));
    final rows = await query.get();
    return rows.map((row) => row.readTable(courseVersions)).toList();
  }

  Future<List<AssignedRemoteCourseInfo>> getAssignedRemoteCoursesForStudent(
    int studentId,
  ) async {
    final rows = await customSelect(
      '''
SELECT a.course_version_id AS course_version_id,
       r.remote_course_id AS remote_course_id,
       c.subject AS course_subject
FROM student_course_assignments a
JOIN course_remote_links r ON r.course_version_id = a.course_version_id
JOIN course_versions c ON c.id = a.course_version_id
WHERE a.student_id = ?
ORDER BY c.subject COLLATE NOCASE ASC
''',
      variables: [Variable.withInt(studentId)],
      readsFrom: {studentCourseAssignments, courseRemoteLinks, courseVersions},
    ).get();
    return rows
        .map((row) => AssignedRemoteCourseInfo.fromRow(row.data))
        .toList();
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

  Stream<List<CourseStudentTreeInfo>> watchCourseStudentTrees(int teacherId) {
    return customSelect(
      '''
      SELECT a.course_version_id AS course_version_id,
             c.subject AS course_subject,
             a.student_id AS student_id,
             u.username AS student_username
      FROM student_course_assignments a
      JOIN course_versions c ON c.id = a.course_version_id
      JOIN users u ON u.id = a.student_id
      WHERE c.teacher_id = ?
      ORDER BY c.subject COLLATE NOCASE ASC, u.username COLLATE NOCASE ASC
      ''',
      variables: [Variable.withInt(teacherId)],
      readsFrom: {studentCourseAssignments, courseVersions, users},
    ).watch().map(
          (rows) => rows
              .map((row) => CourseStudentTreeInfo.fromRow(row.data))
              .toList(),
        );
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

  Future<List<ProgressEntry>> getProgressForCourse({
    required int studentId,
    required int courseVersionId,
  }) {
    return (select(progressEntries)
          ..where((tbl) =>
              tbl.studentId.equals(studentId) &
              tbl.courseVersionId.equals(courseVersionId)))
        .get();
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

  Future<void> updateChatMessageAssistantPayload({
    required int messageId,
    required String content,
    String? rawContent,
    String? parsedJson,
  }) {
    return (update(chatMessages)..where((tbl) => tbl.id.equals(messageId)))
        .write(
      ChatMessagesCompanion(
        content: Value(content),
        rawContent: Value(rawContent),
        parsedJson: Value(parsedJson),
      ),
    );
  }

  Future<ChatSession?> getSession(int sessionId) {
    return (select(chatSessions)..where((tbl) => tbl.id.equals(sessionId)))
        .getSingleOrNull();
  }

  Stream<ChatSession?> watchSession(int sessionId) {
    return (select(chatSessions)..where((tbl) => tbl.id.equals(sessionId)))
        .watchSingleOrNull();
  }

  Future<void> updateSessionContracts({
    required int sessionId,
    String? controlStateJson,
    DateTime? controlStateUpdatedAt,
    String? evidenceStateJson,
    DateTime? evidenceStateUpdatedAt,
    bool touchSync = true,
  }) {
    final now = DateTime.now();
    return (update(chatSessions)..where((tbl) => tbl.id.equals(sessionId)))
        .write(
      ChatSessionsCompanion(
        controlStateJson: Value(controlStateJson),
        controlStateUpdatedAt: Value(controlStateUpdatedAt),
        evidenceStateJson: Value(evidenceStateJson),
        evidenceStateUpdatedAt: Value(evidenceStateUpdatedAt),
        syncUpdatedAt: touchSync ? Value(now) : const Value.absent(),
      ),
    );
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
        syncUpdatedAt: Value(DateTime.now()),
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
       s.summary_text AS summary_text,
       s.summary_lit AS summary_lit,
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

  Stream<ProgressEntry?> watchProgress({
    required int studentId,
    required int courseVersionId,
    required String kpKey,
  }) {
    return (select(progressEntries)
          ..where((tbl) =>
              tbl.studentId.equals(studentId) &
              tbl.courseVersionId.equals(courseVersionId) &
              tbl.kpKey.equals(kpKey)))
        .watchSingleOrNull();
  }

  Future<DateTime?> getLatestProgressUpdatedAtForSync({
    required int studentId,
  }) async {
    final query = selectOnly(progressEntries)
      ..addColumns([progressEntries.updatedAt.max()])
      ..where(progressEntries.studentId.equals(studentId))
      ..where(progressEntries.kpKey.isNotValue(kTreeViewStateKpKey));
    final row = await query.getSingle();
    final value = row.read(progressEntries.updatedAt.max());
    return value?.toUtc();
  }

  Future<List<ProgressEntry>> listProgressEntriesForSyncUpload({
    required int studentId,
    DateTime? updatedAtOrAfter,
  }) {
    final normalizedUpdatedAt = updatedAtOrAfter?.toUtc();
    final query = select(progressEntries)
      ..where((tbl) =>
          tbl.studentId.equals(studentId) &
          tbl.kpKey.isNotValue(kTreeViewStateKpKey));
    if (normalizedUpdatedAt != null) {
      query.where(
          (tbl) => tbl.updatedAt.isBiggerOrEqualValue(normalizedUpdatedAt));
    }
    return query.get();
  }

  Future<List<ProgressEntry>> listProgressEntriesForChapterSyncUpload({
    required int studentId,
    required int courseVersionId,
    required String chapterKey,
  }) {
    final normalizedChapter = chapterKey.trim();
    final query = select(progressEntries)
      ..where((tbl) =>
          tbl.studentId.equals(studentId) &
          tbl.courseVersionId.equals(courseVersionId) &
          tbl.kpKey.isNotValue(kTreeViewStateKpKey));
    if (normalizedChapter.isNotEmpty && normalizedChapter != 'ungrouped') {
      query.where((tbl) =>
          tbl.kpKey.equals(normalizedChapter) |
          tbl.kpKey.like('$normalizedChapter.%'));
    }
    return query.get();
  }

  Future<Map<String, DateTime>> getProgressUpdatedAtByRemoteCourseAndKp({
    required int studentId,
  }) async {
    final rows = await customSelect(
      '''
SELECT crl.remote_course_id AS remote_course_id,
       p.kp_key AS kp_key,
       p.updated_at AS updated_at
FROM progress_entries p
JOIN course_remote_links crl ON crl.course_version_id = p.course_version_id
WHERE p.student_id = ? AND p.kp_key <> ?
''',
      variables: [
        Variable.withInt(studentId),
        Variable.withString(kTreeViewStateKpKey),
      ],
      readsFrom: {progressEntries, courseRemoteLinks},
    ).get();
    final result = <String, DateTime>{};
    for (final row in rows) {
      final remoteCourseRaw = row.data['remote_course_id'];
      final remoteCourseId =
          remoteCourseRaw is num ? remoteCourseRaw.toInt() : 0;
      if (remoteCourseId <= 0) {
        continue;
      }
      final kpRaw = row.data['kp_key'];
      final kpKey = kpRaw is String ? kpRaw.trim() : '';
      if (kpKey.isEmpty) {
        continue;
      }
      final updatedRaw = row.data['updated_at'];
      DateTime? updatedAt;
      if (updatedRaw is DateTime) {
        updatedAt = updatedRaw.toUtc();
      } else if (updatedRaw is String) {
        updatedAt = DateTime.tryParse(updatedRaw)?.toUtc();
      } else if (updatedRaw is num) {
        final rawInt = updatedRaw.toInt();
        final millis = rawInt > 1000000000000 ? rawInt : rawInt * 1000;
        updatedAt = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
      }
      if (updatedAt == null) {
        continue;
      }
      final key = '$remoteCourseId:$kpKey';
      final current = result[key];
      if (current == null || updatedAt.isAfter(current)) {
        result[key] = updatedAt;
      }
    }
    return result;
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
    int? litPercent,
  }) async {
    final existing = await getProgress(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: kpKey,
    );
    final normalizedCounts = existing == null
        ? _normalizePassedCounts(
            lit: lit,
            litPercent: litPercent ?? 0,
            questionLevel: null,
            easyPassedCount: 0,
            mediumPassedCount: 0,
            hardPassedCount: 0,
            fallbackHardForLit: lit,
          )
        : _NormalizedPassedCounts(
            easyPassedCount: existing.easyPassedCount,
            mediumPassedCount: existing.mediumPassedCount,
            hardPassedCount: existing.hardPassedCount,
          );
    final resolvedPercent = litPercent == null
        ? _deriveLitPercentFromPassedCounts(
            easyPassedCount: normalizedCounts.easyPassedCount,
            mediumPassedCount: normalizedCounts.mediumPassedCount,
            hardPassedCount: normalizedCounts.hardPassedCount,
            fallbackPercent: lit ? 100 : 0,
          )
        : litPercent.clamp(0, 100);
    if (existing == null) {
      await into(progressEntries).insert(
        ProgressEntriesCompanion.insert(
          studentId: studentId,
          courseVersionId: courseVersionId,
          kpKey: kpKey,
          lit: Value(lit),
          litPercent: Value(resolvedPercent),
          easyPassedCount: Value(normalizedCounts.easyPassedCount),
          mediumPassedCount: Value(normalizedCounts.mediumPassedCount),
          hardPassedCount: Value(normalizedCounts.hardPassedCount),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return;
    }
    await (update(progressEntries)..where((tbl) => tbl.id.equals(existing.id)))
        .write(
      ProgressEntriesCompanion(
        lit: Value(lit),
        litPercent: Value(resolvedPercent),
        questionLevel: const Value(null),
        easyPassedCount: Value(normalizedCounts.easyPassedCount),
        mediumPassedCount: Value(normalizedCounts.mediumPassedCount),
        hardPassedCount: Value(normalizedCounts.hardPassedCount),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> incrementProgressPassedCount({
    required int studentId,
    required int courseVersionId,
    required String kpKey,
    required String passedLevel,
  }) async {
    final normalized = _normalizeLevel(passedLevel);
    if (normalized == null) {
      throw StateError('Unsupported passed level: $passedLevel');
    }
    final existing = await getProgress(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: kpKey,
    );
    final easyCount =
        (existing?.easyPassedCount ?? 0) + (normalized == 'easy' ? 1 : 0);
    final mediumCount =
        (existing?.mediumPassedCount ?? 0) + (normalized == 'medium' ? 1 : 0);
    final hardCount =
        (existing?.hardPassedCount ?? 0) + (normalized == 'hard' ? 1 : 0);
    final derivedLitPercent = _deriveLitPercentFromPassedCounts(
      easyPassedCount: easyCount,
      mediumPassedCount: mediumCount,
      hardPassedCount: hardCount,
    );
    if (existing == null) {
      await into(progressEntries).insert(
        ProgressEntriesCompanion.insert(
          studentId: studentId,
          courseVersionId: courseVersionId,
          kpKey: kpKey,
          litPercent: Value(derivedLitPercent),
          questionLevel: const Value(null),
          easyPassedCount: Value(easyCount),
          mediumPassedCount: Value(mediumCount),
          hardPassedCount: Value(hardCount),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return;
    }
    await (update(progressEntries)..where((tbl) => tbl.id.equals(existing.id)))
        .write(
      ProgressEntriesCompanion(
        litPercent: Value(derivedLitPercent),
        questionLevel: const Value(null),
        easyPassedCount: Value(easyCount),
        mediumPassedCount: Value(mediumCount),
        hardPassedCount: Value(hardCount),
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
  }) async {
    final existing = await getProgress(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: kpKey,
    );
    final shouldLit = summaryLit == true;
    final resolvedPercent = _deriveLitPercentFromPassedCounts(
      easyPassedCount: existing?.easyPassedCount ?? 0,
      mediumPassedCount: existing?.mediumPassedCount ?? 0,
      hardPassedCount: existing?.hardPassedCount ?? 0,
    );
    if (existing == null) {
      await into(progressEntries).insert(
        ProgressEntriesCompanion.insert(
          studentId: studentId,
          courseVersionId: courseVersionId,
          kpKey: kpKey,
          lit: Value(shouldLit),
          litPercent: Value(resolvedPercent),
          easyPassedCount: const Value(0),
          mediumPassedCount: const Value(0),
          hardPassedCount: const Value(0),
          summaryText: Value(summaryText),
          summaryRawResponse: Value(summaryRawResponse),
          summaryValid: Value(summaryValid),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return;
    }
    await (update(progressEntries)..where((tbl) => tbl.id.equals(existing.id)))
        .write(
      ProgressEntriesCompanion(
        lit: Value(shouldLit),
        litPercent: Value(resolvedPercent),
        questionLevel: const Value(null),
        summaryText: Value(summaryText),
        summaryRawResponse: Value(summaryRawResponse),
        summaryValid: Value(summaryValid),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> upsertProgressFromSync({
    required int studentId,
    required int courseVersionId,
    required String kpKey,
    required bool lit,
    required int litPercent,
    int easyPassedCount = 0,
    int mediumPassedCount = 0,
    int hardPassedCount = 0,
    String? questionLevel,
    String? summaryText,
    String? summaryRawResponse,
    bool? summaryValid,
    required DateTime updatedAt,
    bool mergeWithLocal = true,
  }) async {
    final normalizedCounts = _normalizePassedCounts(
      lit: lit,
      litPercent: litPercent,
      questionLevel: questionLevel,
      easyPassedCount: easyPassedCount,
      mediumPassedCount: mediumPassedCount,
      hardPassedCount: hardPassedCount,
      fallbackHardForLit: lit,
    );
    final clampedPercent = _deriveLitPercentFromPassedCounts(
      easyPassedCount: normalizedCounts.easyPassedCount,
      mediumPassedCount: normalizedCounts.mediumPassedCount,
      hardPassedCount: normalizedCounts.hardPassedCount,
      fallbackPercent: litPercent.clamp(0, 100),
    );
    final normalizedQuestionLevel = _normalizeLevel(questionLevel) == null
        ? null
        : _normalizeLevel(questionLevel);
    if (!mergeWithLocal) {
      await into(progressEntries).insert(
        ProgressEntriesCompanion.insert(
          studentId: studentId,
          courseVersionId: courseVersionId,
          kpKey: kpKey,
          lit: Value(lit),
          litPercent: Value(clampedPercent),
          questionLevel: Value(normalizedQuestionLevel),
          easyPassedCount: Value(normalizedCounts.easyPassedCount),
          mediumPassedCount: Value(normalizedCounts.mediumPassedCount),
          hardPassedCount: Value(normalizedCounts.hardPassedCount),
          summaryText: Value(summaryText),
          summaryRawResponse: Value(summaryRawResponse),
          summaryValid: Value(summaryValid),
          updatedAt: Value(updatedAt),
        ),
        mode: InsertMode.insertOrReplace,
      );
      return;
    }
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
          litPercent: Value(clampedPercent),
          questionLevel: Value(mergeWithLocal ? null : normalizedQuestionLevel),
          easyPassedCount: Value(normalizedCounts.easyPassedCount),
          mediumPassedCount: Value(normalizedCounts.mediumPassedCount),
          hardPassedCount: Value(normalizedCounts.hardPassedCount),
          summaryText: Value(summaryText),
          summaryRawResponse: Value(summaryRawResponse),
          summaryValid: Value(summaryValid),
          updatedAt: Value(updatedAt),
        ),
      );
      return;
    }
    if (!mergeWithLocal) {
      await (update(progressEntries)
            ..where((tbl) => tbl.id.equals(existing.id)))
          .write(
        ProgressEntriesCompanion(
          lit: Value(lit),
          litPercent: Value(clampedPercent),
          questionLevel: Value(normalizedQuestionLevel),
          easyPassedCount: Value(normalizedCounts.easyPassedCount),
          mediumPassedCount: Value(normalizedCounts.mediumPassedCount),
          hardPassedCount: Value(normalizedCounts.hardPassedCount),
          summaryText: Value(summaryText),
          summaryRawResponse: Value(summaryRawResponse),
          summaryValid: Value(summaryValid),
          updatedAt: Value(updatedAt),
        ),
      );
      return;
    }
    final mergedEasyPassedCount =
        existing.easyPassedCount >= normalizedCounts.easyPassedCount
            ? existing.easyPassedCount
            : normalizedCounts.easyPassedCount;
    final mergedMediumPassedCount =
        existing.mediumPassedCount >= normalizedCounts.mediumPassedCount
            ? existing.mediumPassedCount
            : normalizedCounts.mediumPassedCount;
    final mergedHardPassedCount =
        existing.hardPassedCount >= normalizedCounts.hardPassedCount
            ? existing.hardPassedCount
            : normalizedCounts.hardPassedCount;
    final mergedLitPercent = _deriveLitPercentFromPassedCounts(
      easyPassedCount: mergedEasyPassedCount,
      mediumPassedCount: mergedMediumPassedCount,
      hardPassedCount: mergedHardPassedCount,
      fallbackPercent: existing.litPercent >= clampedPercent
          ? existing.litPercent
          : clampedPercent,
    );
    final shouldTakeIncomingDetails = _shouldTakeIncomingProgressDetails(
      existing: existing,
      incomingLitPercent: clampedPercent,
      incomingQuestionLevel: questionLevel,
      incomingUpdatedAt: updatedAt,
    );
    await (update(progressEntries)..where((tbl) => tbl.id.equals(existing.id)))
        .write(
      ProgressEntriesCompanion(
        lit: Value(shouldTakeIncomingDetails ? lit : existing.lit),
        litPercent: Value(mergedLitPercent),
        questionLevel: const Value(null),
        easyPassedCount: Value(mergedEasyPassedCount),
        mediumPassedCount: Value(mergedMediumPassedCount),
        hardPassedCount: Value(mergedHardPassedCount),
        summaryText: Value(
          shouldTakeIncomingDetails ? summaryText : existing.summaryText,
        ),
        summaryRawResponse: Value(
          shouldTakeIncomingDetails
              ? summaryRawResponse
              : existing.summaryRawResponse,
        ),
        summaryValid: Value(
          shouldTakeIncomingDetails ? summaryValid : existing.summaryValid,
        ),
        updatedAt: Value(
          shouldTakeIncomingDetails ? updatedAt : existing.updatedAt,
        ),
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
        litPercent: const Value(0),
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
            (tbl) => OrderingTerm(
                  expression: tbl.createdAt,
                  mode: OrderingMode.desc,
                ),
            (tbl) => OrderingTerm(expression: tbl.baseUrl),
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
    required String reasoningEffort,
    required String ttsModel,
    required String sttModel,
    required String apiKeyHash,
  }) {
    return into(apiConfigs).insert(
      ApiConfigsCompanion.insert(
        baseUrl: baseUrl.trim(),
        model: model.trim(),
        reasoningEffort: Value(
          reasoningEffort.trim().isEmpty
              ? 'medium'
              : reasoningEffort.trim().toLowerCase(),
        ),
        ttsModel: Value(ttsModel.trim().isEmpty ? null : ttsModel.trim()),
        sttModel: Value(sttModel.trim().isEmpty ? null : sttModel.trim()),
        apiKeyHash: apiKeyHash.trim(),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<void> backfillApiConfigModels({
    required String openAiTtsModel,
    required String openAiSttModel,
    required String siliconTtsModel,
    required String siliconSttModel,
  }) async {
    final configs = await select(apiConfigs).get();
    for (final config in configs) {
      final normalized = _normalizeBaseUrl(config.baseUrl).toLowerCase();
      final isOpenAi = normalized.contains('openai.com');
      final isSilicon = normalized.contains('siliconflow');
      final desiredTts =
          isSilicon ? siliconTtsModel : (isOpenAi ? openAiTtsModel : '');
      final desiredStt =
          isSilicon ? siliconSttModel : (isOpenAi ? openAiSttModel : '');
      final currentTts = (config.ttsModel ?? '').trim();
      final currentStt = (config.sttModel ?? '').trim();
      final shouldUpdateTts =
          currentTts.isEmpty && desiredTts.trim().isNotEmpty;
      final shouldUpdateStt =
          currentStt.isEmpty && desiredStt.trim().isNotEmpty;
      if (!shouldUpdateTts && !shouldUpdateStt) {
        continue;
      }
      await (update(apiConfigs)..where((tbl) => tbl.id.equals(config.id)))
          .write(
        ApiConfigsCompanion(
          ttsModel:
              shouldUpdateTts ? Value(desiredTts.trim()) : const Value.absent(),
          sttModel:
              shouldUpdateStt ? Value(desiredStt.trim()) : const Value.absent(),
        ),
      );
    }
  }

  Future<void> upsertProgressBatchFromSync({
    required List<SyncedProgressUpsert> rows,
  }) async {
    if (rows.isEmpty) {
      return;
    }
    await batch((batch) {
      for (final row in rows) {
        final normalizedCounts = _normalizePassedCounts(
          lit: row.lit,
          litPercent: row.litPercent,
          questionLevel: row.questionLevel,
          easyPassedCount: row.easyPassedCount,
          mediumPassedCount: row.mediumPassedCount,
          hardPassedCount: row.hardPassedCount,
          fallbackHardForLit: row.lit,
        );
        final clampedPercent = _deriveLitPercentFromPassedCounts(
          easyPassedCount: normalizedCounts.easyPassedCount,
          mediumPassedCount: normalizedCounts.mediumPassedCount,
          hardPassedCount: normalizedCounts.hardPassedCount,
          fallbackPercent: row.litPercent.clamp(0, 100),
        );
        final normalizedQuestionLevel = _normalizeLevel(row.questionLevel);
        batch.insert(
          progressEntries,
          ProgressEntriesCompanion.insert(
            studentId: row.studentId,
            courseVersionId: row.courseVersionId,
            kpKey: row.kpKey,
            lit: Value(row.lit),
            litPercent: Value(clampedPercent),
            questionLevel: Value(normalizedQuestionLevel),
            easyPassedCount: Value(normalizedCounts.easyPassedCount),
            mediumPassedCount: Value(normalizedCounts.mediumPassedCount),
            hardPassedCount: Value(normalizedCounts.hardPassedCount),
            summaryText: Value(row.summaryText),
            summaryRawResponse: Value(row.summaryRawResponse),
            summaryValid: Value(row.summaryValid),
            updatedAt: Value(row.updatedAt),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
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

  Future<void> updateUserAuth({
    required int userId,
    required String pinHash,
    required String role,
    int? remoteUserId,
  }) async {
    final affectedUsers = await _syncAffectedUsersForUser(userId);
    await (update(users)..where((tbl) => tbl.id.equals(userId))).write(
      UsersCompanion(
        pinHash: Value(pinHash),
        role: Value(role),
        remoteUserId:
            remoteUserId == null ? const Value.absent() : Value(remoteUserId),
      ),
    );
    affectedUsers.addAll(await _syncAffectedUsersForUser(userId));
    await _notifySyncRelevantUsers(affectedUsers);
  }

  Future<User> upsertAuthenticatedUser({
    required String username,
    required String pinHash,
    required String role,
    int? remoteUserId,
  }) async {
    return transaction(() async {
      final normalizedUsername = username.trim().toLowerCase();
      final existingByRemoteId = remoteUserId == null || remoteUserId <= 0
          ? null
          : await findUserByRemoteId(remoteUserId);
      final existingByUsername = await findUserByUsername(normalizedUsername);

      User? target;
      if (existingByRemoteId != null &&
          existingByUsername != null &&
          existingByRemoteId.id != existingByUsername.id) {
        target = _preferAuthCanonicalUser(
          existingByUsername,
          existingByRemoteId,
        );
        final duplicate = target.id == existingByUsername.id
            ? existingByRemoteId
            : existingByUsername;
        await mergeUsers(
          keepUserId: target.id,
          removeUserId: duplicate.id,
        );
      } else {
        target = existingByUsername ?? existingByRemoteId;
      }

      if (target == null) {
        final userId = await createUser(
          username: normalizedUsername,
          pinHash: pinHash,
          role: role,
          remoteUserId: remoteUserId,
        );
        await _notifySyncRelevantUsers(<int>{userId});
        return (await getUserById(userId))!;
      }
      final targetId = target.id;
      final affectedUsers = await _syncAffectedUsersForUser(targetId);

      await (update(users)..where((tbl) => tbl.id.equals(targetId))).write(
        UsersCompanion(
          username: Value(normalizedUsername),
          pinHash: Value(pinHash),
          role: Value(role),
          remoteUserId:
              remoteUserId == null ? const Value.absent() : Value(remoteUserId),
        ),
      );
      affectedUsers.addAll(await _syncAffectedUsersForUser(targetId));
      await _notifySyncRelevantUsers(affectedUsers);
      return (await getUserById(targetId))!;
    });
  }

  Future<void> ensureRemoteUserUniqueness() async {
    final duplicateRows = await customSelect(
      '''
SELECT remote_user_id AS remote_user_id
FROM users
WHERE remote_user_id IS NOT NULL
GROUP BY remote_user_id
HAVING COUNT(*) > 1
''',
      readsFrom: {users},
    ).get();
    for (final row in duplicateRows) {
      final remoteUserId = (row.data['remote_user_id'] as num?)?.toInt() ?? 0;
      if (remoteUserId <= 0) {
        continue;
      }
      final matches = await (select(users)
            ..where((tbl) => tbl.remoteUserId.equals(remoteUserId))
            ..orderBy([(tbl) => OrderingTerm(expression: tbl.id)]))
          .get();
      if (matches.length <= 1) {
        continue;
      }
      final canonical = _preferMigrationCanonicalUser(matches);
      for (final duplicate in matches) {
        if (duplicate.id == canonical.id) {
          continue;
        }
        await mergeUsers(
          keepUserId: canonical.id,
          removeUserId: duplicate.id,
        );
      }
    }
  }

  Future<void> mergeUsers({
    required int keepUserId,
    required int removeUserId,
  }) async {
    if (keepUserId == removeUserId) {
      return;
    }
    final affectedUsers = <int>{keepUserId, removeUserId}
      ..addAll(await _syncAffectedUsersForUser(keepUserId))
      ..addAll(await _syncAffectedUsersForUser(removeUserId));
    await transaction(() async {
      final keep = await getUserById(keepUserId);
      final remove = await getUserById(removeUserId);
      if (keep == null || remove == null) {
        return;
      }

      await _mergeTeacherReferences(
        keepUserId: keepUserId,
        removeUserId: removeUserId,
      );
      await _mergeStudentReferences(
        keepUserId: keepUserId,
        removeUserId: removeUserId,
      );

      final keepRemoteUserId = keep.remoteUserId ?? remove.remoteUserId;
      final keepTeacherId = keep.teacherId ?? remove.teacherId;
      final keepRole =
          _preferCanonicalRole(primary: keep.role, secondary: remove.role);
      await (update(users)..where((tbl) => tbl.id.equals(keepUserId))).write(
        UsersCompanion(
          role: Value(keepRole),
          teacherId: Value(keepTeacherId),
          remoteUserId: keepRemoteUserId == null
              ? const Value.absent()
              : Value(keepRemoteUserId),
        ),
      );
      await (delete(users)..where((tbl) => tbl.id.equals(removeUserId))).go();
    });
    affectedUsers.addAll(await _syncAffectedUsersForUser(keepUserId));
    await _notifySyncRelevantUsers(affectedUsers);
  }

  Future<void> updateStudentTeacherId({
    required int studentId,
    required int teacherId,
  }) async {
    final affectedUsers = <int>{studentId, teacherId}
      ..addAll(await _syncAffectedUsersForUser(studentId));
    await (update(users)
          ..where(
              (tbl) => tbl.id.equals(studentId) & tbl.role.equals('student')))
        .write(
      UsersCompanion(
        teacherId: Value(teacherId),
      ),
    );
    affectedUsers.addAll(await _syncAffectedUsersForUser(studentId));
    await _notifySyncRelevantUsers(affectedUsers);
  }

  Future<void> _mergeTeacherReferences({
    required int keepUserId,
    required int removeUserId,
  }) async {
    await (update(users)..where((tbl) => tbl.teacherId.equals(removeUserId)))
        .write(
      UsersCompanion(
        teacherId: Value(keepUserId),
      ),
    );
    await (update(courseVersions)
          ..where((tbl) => tbl.teacherId.equals(removeUserId)))
        .write(
      CourseVersionsCompanion(
        teacherId: Value(keepUserId),
      ),
    );
    await (update(llmCalls)..where((tbl) => tbl.teacherId.equals(removeUserId)))
        .write(
      LlmCallsCompanion(
        teacherId: Value(keepUserId),
      ),
    );
    await (update(promptTemplates)
          ..where((tbl) => tbl.teacherId.equals(removeUserId)))
        .write(
      PromptTemplatesCompanion(
        teacherId: Value(keepUserId),
      ),
    );
    await (update(studentPromptProfiles)
          ..where((tbl) => tbl.teacherId.equals(removeUserId)))
        .write(
      StudentPromptProfilesCompanion(
        teacherId: Value(keepUserId),
      ),
    );
  }

  Future<void> _mergeStudentReferences({
    required int keepUserId,
    required int removeUserId,
  }) async {
    final assignments = await (select(studentCourseAssignments)
          ..where((tbl) => tbl.studentId.equals(removeUserId)))
        .get();
    for (final assignment in assignments) {
      await assignStudent(
        studentId: keepUserId,
        courseVersionId: assignment.courseVersionId,
      );
    }

    final sourceProgress = await (select(progressEntries)
          ..where((tbl) => tbl.studentId.equals(removeUserId)))
        .get();
    for (final progress in sourceProgress) {
      final existing = await getProgress(
        studentId: keepUserId,
        courseVersionId: progress.courseVersionId,
        kpKey: progress.kpKey,
      );
      if (existing == null) {
        await (update(progressEntries)
              ..where((tbl) => tbl.id.equals(progress.id)))
            .write(
          ProgressEntriesCompanion(
            studentId: Value(keepUserId),
          ),
        );
        continue;
      }
      final sourceIsNewer = progress.updatedAt.isAfter(existing.updatedAt);
      final mergedEasyPassedCount =
          existing.easyPassedCount >= progress.easyPassedCount
              ? existing.easyPassedCount
              : progress.easyPassedCount;
      final mergedMediumPassedCount =
          existing.mediumPassedCount >= progress.mediumPassedCount
              ? existing.mediumPassedCount
              : progress.mediumPassedCount;
      final mergedHardPassedCount =
          existing.hardPassedCount >= progress.hardPassedCount
              ? existing.hardPassedCount
              : progress.hardPassedCount;
      await (update(progressEntries)
            ..where((tbl) => tbl.id.equals(existing.id)))
          .write(
        ProgressEntriesCompanion(
          lit: Value(existing.lit || progress.lit),
          litPercent: Value(
            _deriveLitPercentFromPassedCounts(
              easyPassedCount: mergedEasyPassedCount,
              mediumPassedCount: mergedMediumPassedCount,
              hardPassedCount: mergedHardPassedCount,
              fallbackPercent: existing.litPercent >= progress.litPercent
                  ? existing.litPercent
                  : progress.litPercent,
            ),
          ),
          questionLevel: const Value(null),
          easyPassedCount: Value(mergedEasyPassedCount),
          mediumPassedCount: Value(mergedMediumPassedCount),
          hardPassedCount: Value(mergedHardPassedCount),
          summaryText: Value(
            sourceIsNewer ? progress.summaryText : existing.summaryText,
          ),
          summaryRawResponse: Value(
            sourceIsNewer
                ? progress.summaryRawResponse
                : existing.summaryRawResponse,
          ),
          summaryValid: Value(
            sourceIsNewer ? progress.summaryValid : existing.summaryValid,
          ),
          updatedAt: Value(
            sourceIsNewer ? progress.updatedAt : existing.updatedAt,
          ),
        ),
      );
      await (delete(progressEntries)
            ..where((tbl) => tbl.id.equals(progress.id)))
          .go();
    }

    await (update(chatSessions)
          ..where((tbl) => tbl.studentId.equals(removeUserId)))
        .write(
      ChatSessionsCompanion(
        studentId: Value(keepUserId),
      ),
    );
    await (update(llmCalls)..where((tbl) => tbl.studentId.equals(removeUserId)))
        .write(
      LlmCallsCompanion(
        studentId: Value(keepUserId),
      ),
    );
    await (update(promptTemplates)
          ..where((tbl) => tbl.studentId.equals(removeUserId)))
        .write(
      PromptTemplatesCompanion(
        studentId: Value(keepUserId),
      ),
    );
    await (update(studentPromptProfiles)
          ..where((tbl) => tbl.studentId.equals(removeUserId)))
        .write(
      StudentPromptProfilesCompanion(
        studentId: Value(keepUserId),
      ),
    );
    await (delete(studentCourseAssignments)
          ..where((tbl) => tbl.studentId.equals(removeUserId)))
        .go();
  }

  Future<void> upsertCourseRemoteLink({
    required int courseVersionId,
    required int remoteCourseId,
  }) async {
    await into(courseRemoteLinks).insert(
      CourseRemoteLinksCompanion.insert(
        courseVersionId: courseVersionId,
        remoteCourseId: remoteCourseId,
      ),
      mode: InsertMode.insertOrReplace,
    );
    await _notifySyncRelevantUsers(
      await _syncAffectedUsersForCourseVersion(courseVersionId),
    );
  }

  Future<int?> getRemoteCourseId(int courseVersionId) async {
    final row = await (select(courseRemoteLinks)
          ..where((tbl) => tbl.courseVersionId.equals(courseVersionId)))
        .getSingleOrNull();
    return row?.remoteCourseId;
  }

  Future<void> deleteCourseRemoteLink(int courseVersionId) async {
    await (delete(courseRemoteLinks)
          ..where((tbl) => tbl.courseVersionId.equals(courseVersionId)))
        .go();
    await _notifySyncRelevantUsers(
      await _syncAffectedUsersForCourseVersion(courseVersionId),
    );
  }

  Future<int?> getCourseVersionIdForRemoteCourse(int remoteCourseId) async {
    final row = await (select(courseRemoteLinks)
          ..where((tbl) => tbl.remoteCourseId.equals(remoteCourseId)))
        .getSingleOrNull();
    return row?.courseVersionId;
  }

  Future<int?> getRemoteCourseIdForCourseVersion(int courseVersionId) async {
    final row = await (select(courseRemoteLinks)
          ..where((tbl) => tbl.courseVersionId.equals(courseVersionId)))
        .getSingleOrNull();
    return row?.remoteCourseId;
  }

  String _normalizeBaseUrl(String value) {
    var trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
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
        await (delete(courseRemoteLinks)
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
    final affectedUsers = await _syncAffectedUsersForCourseVersion(
      courseVersionId,
    );
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
        await (delete(chatSessions)..where((tbl) => tbl.id.isIn(sessionIds)))
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
      await (delete(courseRemoteLinks)
            ..where((tbl) => tbl.courseVersionId.equals(courseVersionId)))
          .go();
      await (delete(llmCalls)
            ..where((tbl) => tbl.courseVersionId.equals(courseVersionId)))
          .go();
      await (delete(courseVersions)
            ..where((tbl) => tbl.id.equals(courseVersionId)))
          .go();
    });
    await _notifySyncRelevantUsers(affectedUsers);
  }

  Future<void> deleteStudentCourseData({
    required int studentId,
    required int courseVersionId,
    bool removeAssignment = true,
  }) async {
    final affectedUsers = removeAssignment
        ? await _syncAffectedUsersForCourseVersion(courseVersionId)
        : const <int>{};
    await transaction(() async {
      final sessions = await (select(chatSessions)
            ..where((tbl) =>
                tbl.studentId.equals(studentId) &
                tbl.courseVersionId.equals(courseVersionId)))
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
            ..where((tbl) =>
                tbl.studentId.equals(studentId) &
                tbl.courseVersionId.equals(courseVersionId)))
          .go();
      if (removeAssignment) {
        await (delete(studentCourseAssignments)
              ..where((tbl) =>
                  tbl.studentId.equals(studentId) &
                  tbl.courseVersionId.equals(courseVersionId)))
            .go();
      }
    });
    await _notifySyncRelevantUsers(affectedUsers);
  }

  Future<void> migrateStudentCourseData({
    required int studentId,
    required int fromCourseVersionId,
    required int toCourseVersionId,
  }) async {
    if (fromCourseVersionId == toCourseVersionId) {
      return;
    }
    await transaction(() async {
      await assignStudent(
        studentId: studentId,
        courseVersionId: toCourseVersionId,
      );

      final sourceProgress = await (select(progressEntries)
            ..where((tbl) =>
                tbl.studentId.equals(studentId) &
                tbl.courseVersionId.equals(fromCourseVersionId)))
          .get();
      for (final progress in sourceProgress) {
        final existing = await getProgress(
          studentId: studentId,
          courseVersionId: toCourseVersionId,
          kpKey: progress.kpKey,
        );
        if (existing == null) {
          await into(progressEntries).insert(
            ProgressEntriesCompanion.insert(
              studentId: progress.studentId,
              courseVersionId: toCourseVersionId,
              kpKey: progress.kpKey,
              lit: Value(progress.lit),
              litPercent: Value(
                _deriveLitPercentFromPassedCounts(
                  easyPassedCount: progress.easyPassedCount,
                  mediumPassedCount: progress.mediumPassedCount,
                  hardPassedCount: progress.hardPassedCount,
                  fallbackPercent: progress.litPercent,
                ),
              ),
              questionLevel: const Value(null),
              easyPassedCount: Value(progress.easyPassedCount),
              mediumPassedCount: Value(progress.mediumPassedCount),
              hardPassedCount: Value(progress.hardPassedCount),
              summaryText: Value(progress.summaryText),
              summaryRawResponse: Value(progress.summaryRawResponse),
              summaryValid: Value(progress.summaryValid),
              updatedAt: Value(progress.updatedAt),
            ),
            mode: InsertMode.insertOrReplace,
          );
          continue;
        }
        final mergedLit = existing.lit || progress.lit;
        final mergedEasyPassedCount =
            existing.easyPassedCount >= progress.easyPassedCount
                ? existing.easyPassedCount
                : progress.easyPassedCount;
        final mergedMediumPassedCount =
            existing.mediumPassedCount >= progress.mediumPassedCount
                ? existing.mediumPassedCount
                : progress.mediumPassedCount;
        final mergedHardPassedCount =
            existing.hardPassedCount >= progress.hardPassedCount
                ? existing.hardPassedCount
                : progress.hardPassedCount;
        final mergedLitPercent = _deriveLitPercentFromPassedCounts(
          easyPassedCount: mergedEasyPassedCount,
          mediumPassedCount: mergedMediumPassedCount,
          hardPassedCount: mergedHardPassedCount,
          fallbackPercent: existing.litPercent >= progress.litPercent
              ? existing.litPercent
              : progress.litPercent,
        );
        final sourceIsNewer = progress.updatedAt.isAfter(existing.updatedAt);
        await (update(progressEntries)
              ..where((tbl) => tbl.id.equals(existing.id)))
            .write(
          ProgressEntriesCompanion(
            lit: Value(mergedLit),
            litPercent: Value(mergedLitPercent),
            questionLevel: const Value(null),
            easyPassedCount: Value(mergedEasyPassedCount),
            mediumPassedCount: Value(mergedMediumPassedCount),
            hardPassedCount: Value(mergedHardPassedCount),
            summaryText: Value(
              sourceIsNewer ? progress.summaryText : existing.summaryText,
            ),
            summaryRawResponse: Value(
              sourceIsNewer
                  ? progress.summaryRawResponse
                  : existing.summaryRawResponse,
            ),
            summaryValid: Value(
              sourceIsNewer ? progress.summaryValid : existing.summaryValid,
            ),
            updatedAt: Value(
              sourceIsNewer ? progress.updatedAt : existing.updatedAt,
            ),
          ),
        );
      }

      await (delete(progressEntries)
            ..where((tbl) =>
                tbl.studentId.equals(studentId) &
                tbl.courseVersionId.equals(fromCourseVersionId)))
          .go();

      await (update(chatSessions)
            ..where((tbl) =>
                tbl.studentId.equals(studentId) &
                tbl.courseVersionId.equals(fromCourseVersionId)))
          .write(
        ChatSessionsCompanion(
          courseVersionId: Value(toCourseVersionId),
        ),
      );

      await (delete(studentCourseAssignments)
            ..where((tbl) =>
                tbl.studentId.equals(studentId) &
                tbl.courseVersionId.equals(fromCourseVersionId)))
          .go();
    });
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
    String? courseKey,
    int? studentId,
  }) {
    final normalizedCourseKey = _normalizeCourseKey(courseKey);
    final scopeMatch = _promptScopeMatch(
      courseKey: normalizedCourseKey,
      studentId: studentId,
    );
    return (select(promptTemplates)
          ..where((tbl) =>
              tbl.teacherId.equals(teacherId) &
              tbl.promptName.equals(promptName) &
              tbl.isActive.equals(true) &
              scopeMatch(tbl))
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
    String? courseKey,
    int? studentId,
  }) {
    final normalizedCourseKey = _normalizeCourseKey(courseKey);
    final scopeMatch = _promptScopeMatch(
      courseKey: normalizedCourseKey,
      studentId: studentId,
    );
    return (select(promptTemplates)
          ..where((tbl) =>
              tbl.teacherId.equals(teacherId) &
              tbl.promptName.equals(promptName) &
              scopeMatch(tbl))
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
    String? courseKey,
    int? studentId,
  }) async {
    final normalizedCourseKey = _normalizeCourseKey(courseKey);
    final templateId = await transaction(() async {
      await (update(promptTemplates)
            ..where((tbl) =>
                tbl.teacherId.equals(teacherId) &
                tbl.promptName.equals(promptName) &
                _promptScopeMatch(
                  courseKey: normalizedCourseKey,
                  studentId: studentId,
                )(tbl)))
          .write(
        const PromptTemplatesCompanion(isActive: Value(false)),
      );
      return into(promptTemplates).insert(
        PromptTemplatesCompanion.insert(
          teacherId: teacherId,
          courseKey: Value(normalizedCourseKey),
          studentId: Value(studentId),
          promptName: promptName,
          content: content,
          isActive: const Value(true),
        ),
      );
    });
    await _notifySyncRelevantUsers(_syncAffectedUsersForTeacherOnly(teacherId));
    return templateId;
  }

  Future<int> importPromptTemplate({
    required int teacherId,
    required String promptName,
    required String content,
    required DateTime createdAt,
    String? courseKey,
    int? studentId,
  }) async {
    final normalizedCourseKey = _normalizeCourseKey(courseKey);
    final normalizedCreatedAt = createdAt.toUtc();
    final templateId = await transaction(() async {
      await (update(promptTemplates)
            ..where((tbl) =>
                tbl.teacherId.equals(teacherId) &
                tbl.promptName.equals(promptName) &
                _promptScopeMatch(
                  courseKey: normalizedCourseKey,
                  studentId: studentId,
                )(tbl)))
          .write(
        const PromptTemplatesCompanion(isActive: Value(false)),
      );
      return into(promptTemplates).insert(
        PromptTemplatesCompanion.insert(
          teacherId: teacherId,
          courseKey: Value(normalizedCourseKey),
          studentId: Value(studentId),
          promptName: promptName,
          content: content,
          isActive: const Value(true),
          createdAt: Value(normalizedCreatedAt),
        ),
      );
    });
    await _notifySyncRelevantUsers(_syncAffectedUsersForTeacherOnly(teacherId));
    return templateId;
  }

  Future<void> setActivePromptTemplate({
    required int teacherId,
    required String promptName,
    required int templateId,
    String? courseKey,
    int? studentId,
  }) async {
    final normalizedCourseKey = _normalizeCourseKey(courseKey);
    await transaction(() async {
      await (update(promptTemplates)
            ..where((tbl) =>
                tbl.teacherId.equals(teacherId) &
                tbl.promptName.equals(promptName) &
                _promptScopeMatch(
                  courseKey: normalizedCourseKey,
                  studentId: studentId,
                )(tbl)))
          .write(
        const PromptTemplatesCompanion(isActive: Value(false)),
      );
      await (update(promptTemplates)
            ..where((tbl) =>
                tbl.id.equals(templateId) &
                tbl.teacherId.equals(teacherId) &
                tbl.promptName.equals(promptName) &
                _promptScopeMatch(
                  courseKey: normalizedCourseKey,
                  studentId: studentId,
                )(tbl)))
          .write(
        const PromptTemplatesCompanion(isActive: Value(true)),
      );
    });
    await _notifySyncRelevantUsers(_syncAffectedUsersForTeacherOnly(teacherId));
  }

  Future<void> clearActivePromptTemplates({
    required int teacherId,
    required String promptName,
    String? courseKey,
    int? studentId,
  }) async {
    final normalizedCourseKey = _normalizeCourseKey(courseKey);
    await (update(promptTemplates)
          ..where((tbl) =>
              tbl.teacherId.equals(teacherId) &
              tbl.promptName.equals(promptName) &
              _promptScopeMatch(
                courseKey: normalizedCourseKey,
                studentId: studentId,
              )(tbl)))
        .write(
      const PromptTemplatesCompanion(isActive: Value(false)),
    );
    await _notifySyncRelevantUsers(_syncAffectedUsersForTeacherOnly(teacherId));
  }

  Future<StudentPromptProfile?> getStudentPromptProfile({
    required int teacherId,
    String? courseKey,
    int? studentId,
  }) {
    final normalizedCourseKey = _normalizeCourseKey(courseKey);
    return (select(studentPromptProfiles)
          ..where((tbl) =>
              tbl.teacherId.equals(teacherId) &
              _profileScopeMatch(
                tbl,
                courseKey: normalizedCourseKey,
                studentId: studentId,
              ))
          ..orderBy([
            (tbl) => OrderingTerm(
                  expression: tbl.updatedAt,
                  mode: OrderingMode.desc,
                ),
            (tbl) => OrderingTerm(
                  expression: tbl.createdAt,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<StudentPromptContext> resolveStudentPromptContext({
    required int teacherId,
    String? courseKey,
    int? studentId,
  }) async {
    final normalizedCourseKey = _normalizeCourseKey(courseKey);
    final systemProfile = await getStudentPromptProfile(
      teacherId: teacherId,
      courseKey: null,
      studentId: null,
    );
    final courseProfile = normalizedCourseKey == null
        ? null
        : await getStudentPromptProfile(
            teacherId: teacherId,
            courseKey: normalizedCourseKey,
            studentId: null,
          );
    final studentGlobalProfile = studentId == null
        ? null
        : await getStudentPromptProfile(
            teacherId: teacherId,
            courseKey: null,
            studentId: studentId,
          );
    final studentProfile = (normalizedCourseKey == null || studentId == null)
        ? null
        : await getStudentPromptProfile(
            teacherId: teacherId,
            courseKey: normalizedCourseKey,
            studentId: studentId,
          );
    final gradeLevel = _resolveStudentPromptField(
      studentProfile?.gradeLevel,
      studentGlobalProfile?.gradeLevel,
      courseProfile?.gradeLevel,
      systemProfile?.gradeLevel,
    );
    final readingLevel = _resolveStudentPromptField(
      studentProfile?.readingLevel,
      studentGlobalProfile?.readingLevel,
      courseProfile?.readingLevel,
      systemProfile?.readingLevel,
    );
    final preferredLanguage = _resolveStudentPromptField(
      studentProfile?.preferredLanguage,
      studentGlobalProfile?.preferredLanguage,
      courseProfile?.preferredLanguage,
      systemProfile?.preferredLanguage,
    );
    final interests = _resolveStudentPromptField(
      studentProfile?.interests,
      studentGlobalProfile?.interests,
      courseProfile?.interests,
      systemProfile?.interests,
    );
    final preferredTone = _resolveStudentPromptField(
      studentProfile?.preferredTone,
      studentGlobalProfile?.preferredTone,
      courseProfile?.preferredTone,
      systemProfile?.preferredTone,
    );
    final preferredPace = _resolveStudentPromptField(
      studentProfile?.preferredPace,
      studentGlobalProfile?.preferredPace,
      courseProfile?.preferredPace,
      systemProfile?.preferredPace,
    );
    final preferredFormat = _resolveStudentPromptField(
      studentProfile?.preferredFormat,
      studentGlobalProfile?.preferredFormat,
      courseProfile?.preferredFormat,
      systemProfile?.preferredFormat,
    );
    final supportNotes = _resolveStudentPromptField(
      studentProfile?.supportNotes,
      studentGlobalProfile?.supportNotes,
      courseProfile?.supportNotes,
      systemProfile?.supportNotes,
    );
    final profileLines = <String>[];
    if (gradeLevel != null) {
      profileLines.add('Grade level: $gradeLevel');
    }
    if (readingLevel != null) {
      profileLines.add('Reading level: $readingLevel');
    }
    if (preferredLanguage != null) {
      profileLines.add('Preferred language: $preferredLanguage');
    }
    if (interests != null) {
      profileLines.add('Interests: $interests');
    }
    if (supportNotes != null) {
      profileLines.add('Support notes: $supportNotes');
    }
    final preferenceLines = <String>[];
    if (preferredTone != null) {
      preferenceLines.add('Tone: $preferredTone');
    }
    if (preferredPace != null) {
      preferenceLines.add('Pace: $preferredPace');
    }
    if (preferredFormat != null) {
      preferenceLines.add('Format: $preferredFormat');
    }
    return StudentPromptContext(
      profileText: profileLines.join('\n'),
      preferencesText: preferenceLines.join('\n'),
    );
  }

  Future<void> upsertStudentPromptProfile({
    required int teacherId,
    String? courseKey,
    int? studentId,
    String? gradeLevel,
    String? readingLevel,
    String? preferredLanguage,
    String? interests,
    String? preferredTone,
    String? preferredPace,
    String? preferredFormat,
    String? supportNotes,
  }) async {
    final normalizedCourseKey = _normalizeCourseKey(courseKey);
    final normalizedGradeLevel = _normalizePromptField(gradeLevel);
    final normalizedReadingLevel = _normalizePromptField(readingLevel);
    final normalizedPreferredLanguage =
        _normalizePromptField(preferredLanguage);
    final normalizedInterests = _normalizePromptField(interests);
    final normalizedPreferredTone = _normalizePromptField(preferredTone);
    final normalizedPreferredPace = _normalizePromptField(preferredPace);
    final normalizedPreferredFormat = _normalizePromptField(preferredFormat);
    final normalizedSupportNotes = _normalizePromptField(supportNotes);
    final now = DateTime.now();
    final existing = await (select(studentPromptProfiles)
          ..where((tbl) =>
              tbl.teacherId.equals(teacherId) &
              _profileScopeMatch(
                tbl,
                courseKey: normalizedCourseKey,
                studentId: studentId,
              ))
          ..orderBy([
            (tbl) => OrderingTerm(
                  expression: tbl.updatedAt,
                  mode: OrderingMode.desc,
                ),
            (tbl) => OrderingTerm(
                  expression: tbl.createdAt,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(1))
        .getSingleOrNull();
    if (existing == null) {
      await into(studentPromptProfiles).insert(
        StudentPromptProfilesCompanion.insert(
          teacherId: teacherId,
          courseKey: Value(normalizedCourseKey),
          studentId: Value(studentId),
          gradeLevel: Value(normalizedGradeLevel),
          readingLevel: Value(normalizedReadingLevel),
          preferredLanguage: Value(normalizedPreferredLanguage),
          interests: Value(normalizedInterests),
          preferredTone: Value(normalizedPreferredTone),
          preferredPace: Value(normalizedPreferredPace),
          preferredFormat: Value(normalizedPreferredFormat),
          supportNotes: Value(normalizedSupportNotes),
          updatedAt: Value(now),
        ),
      );
      await _notifySyncRelevantUsers(
        _syncAffectedUsersForTeacherOnly(teacherId),
      );
      return;
    }
    await (update(studentPromptProfiles)
          ..where((tbl) => tbl.id.equals(existing.id)))
        .write(
      StudentPromptProfilesCompanion(
        gradeLevel: Value(normalizedGradeLevel),
        readingLevel: Value(normalizedReadingLevel),
        preferredLanguage: Value(normalizedPreferredLanguage),
        interests: Value(normalizedInterests),
        preferredTone: Value(normalizedPreferredTone),
        preferredPace: Value(normalizedPreferredPace),
        preferredFormat: Value(normalizedPreferredFormat),
        supportNotes: Value(normalizedSupportNotes),
        updatedAt: Value(now),
      ),
    );
    await _notifySyncRelevantUsers(_syncAffectedUsersForTeacherOnly(teacherId));
  }

  Future<void> importStudentPromptProfile({
    required int teacherId,
    String? courseKey,
    int? studentId,
    String? gradeLevel,
    String? readingLevel,
    String? preferredLanguage,
    String? interests,
    String? preferredTone,
    String? preferredPace,
    String? preferredFormat,
    String? supportNotes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) async {
    final normalizedCourseKey = _normalizeCourseKey(courseKey);
    final normalizedGradeLevel = _normalizePromptField(gradeLevel);
    final normalizedReadingLevel = _normalizePromptField(readingLevel);
    final normalizedPreferredLanguage =
        _normalizePromptField(preferredLanguage);
    final normalizedInterests = _normalizePromptField(interests);
    final normalizedPreferredTone = _normalizePromptField(preferredTone);
    final normalizedPreferredPace = _normalizePromptField(preferredPace);
    final normalizedPreferredFormat = _normalizePromptField(preferredFormat);
    final normalizedSupportNotes = _normalizePromptField(supportNotes);
    final normalizedCreatedAt =
        (createdAt ?? updatedAt ?? DateTime.now()).toUtc();
    final normalizedUpdatedAt =
        (updatedAt ?? createdAt ?? DateTime.now()).toUtc();
    final existing = await (select(studentPromptProfiles)
          ..where((tbl) =>
              tbl.teacherId.equals(teacherId) &
              _profileScopeMatch(
                tbl,
                courseKey: normalizedCourseKey,
                studentId: studentId,
              ))
          ..orderBy([
            (tbl) => OrderingTerm(
                  expression: tbl.updatedAt,
                  mode: OrderingMode.desc,
                ),
            (tbl) => OrderingTerm(
                  expression: tbl.createdAt,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(1))
        .getSingleOrNull();
    if (existing == null) {
      await into(studentPromptProfiles).insert(
        StudentPromptProfilesCompanion.insert(
          teacherId: teacherId,
          courseKey: Value(normalizedCourseKey),
          studentId: Value(studentId),
          gradeLevel: Value(normalizedGradeLevel),
          readingLevel: Value(normalizedReadingLevel),
          preferredLanguage: Value(normalizedPreferredLanguage),
          interests: Value(normalizedInterests),
          preferredTone: Value(normalizedPreferredTone),
          preferredPace: Value(normalizedPreferredPace),
          preferredFormat: Value(normalizedPreferredFormat),
          supportNotes: Value(normalizedSupportNotes),
          createdAt: Value(normalizedCreatedAt),
          updatedAt: Value(normalizedUpdatedAt),
        ),
      );
      await _notifySyncRelevantUsers(
        _syncAffectedUsersForTeacherOnly(teacherId),
      );
      return;
    }
    await (update(studentPromptProfiles)
          ..where((tbl) => tbl.id.equals(existing.id)))
        .write(
      StudentPromptProfilesCompanion(
        gradeLevel: Value(normalizedGradeLevel),
        readingLevel: Value(normalizedReadingLevel),
        preferredLanguage: Value(normalizedPreferredLanguage),
        interests: Value(normalizedInterests),
        preferredTone: Value(normalizedPreferredTone),
        preferredPace: Value(normalizedPreferredPace),
        preferredFormat: Value(normalizedPreferredFormat),
        supportNotes: Value(normalizedSupportNotes),
        createdAt: Value(normalizedCreatedAt),
        updatedAt: Value(normalizedUpdatedAt),
      ),
    );
    await _notifySyncRelevantUsers(_syncAffectedUsersForTeacherOnly(teacherId));
  }

  Future<void> deleteStudentPromptProfile({
    required int teacherId,
    String? courseKey,
    int? studentId,
  }) async {
    final normalizedCourseKey = _normalizeCourseKey(courseKey);
    await (delete(studentPromptProfiles)
          ..where((tbl) =>
              tbl.teacherId.equals(teacherId) &
              _profileScopeMatch(
                tbl,
                courseKey: normalizedCourseKey,
                studentId: studentId,
              )))
        .go();
    await _notifySyncRelevantUsers(_syncAffectedUsersForTeacherOnly(teacherId));
  }

  Future<StudentPassConfig?> getStudentPassConfig({
    required int courseVersionId,
    required int studentId,
  }) {
    return (select(studentPassConfigs)
          ..where((tbl) =>
              tbl.courseVersionId.equals(courseVersionId) &
              tbl.studentId.equals(studentId))
          ..limit(1))
        .getSingleOrNull();
  }

  Stream<StudentPassConfig?> watchStudentPassConfig({
    required int courseVersionId,
    required int studentId,
  }) {
    return (select(studentPassConfigs)
          ..where((tbl) =>
              tbl.courseVersionId.equals(courseVersionId) &
              tbl.studentId.equals(studentId))
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<ResolvedStudentPassRule> resolveStudentPassRule({
    required int courseVersionId,
    required int studentId,
  }) async {
    final config = await getStudentPassConfig(
      courseVersionId: courseVersionId,
      studentId: studentId,
    );
    return ResolvedStudentPassRule(
      easyWeight:
          config?.easyWeight ?? ResolvedStudentPassRule.defaultEasyWeight,
      mediumWeight:
          config?.mediumWeight ?? ResolvedStudentPassRule.defaultMediumWeight,
      hardWeight:
          config?.hardWeight ?? ResolvedStudentPassRule.defaultHardWeight,
      passThreshold:
          config?.passThreshold ?? ResolvedStudentPassRule.defaultPassThreshold,
    );
  }

  Stream<ResolvedStudentPassRule> watchResolvedStudentPassRule({
    required int courseVersionId,
    required int studentId,
  }) {
    return watchStudentPassConfig(
      courseVersionId: courseVersionId,
      studentId: studentId,
    ).map(
      (config) => ResolvedStudentPassRule(
        easyWeight:
            config?.easyWeight ?? ResolvedStudentPassRule.defaultEasyWeight,
        mediumWeight:
            config?.mediumWeight ?? ResolvedStudentPassRule.defaultMediumWeight,
        hardWeight:
            config?.hardWeight ?? ResolvedStudentPassRule.defaultHardWeight,
        passThreshold: config?.passThreshold ??
            ResolvedStudentPassRule.defaultPassThreshold,
      ),
    );
  }

  Future<void> upsertStudentPassConfig({
    required int courseVersionId,
    required int studentId,
    required double easyWeight,
    required double mediumWeight,
    required double hardWeight,
    required double passThreshold,
  }) async {
    final now = DateTime.now();
    final existing = await getStudentPassConfig(
      courseVersionId: courseVersionId,
      studentId: studentId,
    );
    if (existing == null) {
      await into(studentPassConfigs).insert(
        StudentPassConfigsCompanion.insert(
          courseVersionId: courseVersionId,
          studentId: studentId,
          easyWeight: Value(easyWeight),
          mediumWeight: Value(mediumWeight),
          hardWeight: Value(hardWeight),
          passThreshold: Value(passThreshold),
          updatedAt: Value(now),
        ),
      );
      await _notifySyncRelevantUsers(
        await _syncAffectedUsersForCourseTeacherOnly(courseVersionId),
      );
      return;
    }
    await (update(studentPassConfigs)
          ..where((tbl) => tbl.id.equals(existing.id)))
        .write(
      StudentPassConfigsCompanion(
        easyWeight: Value(easyWeight),
        mediumWeight: Value(mediumWeight),
        hardWeight: Value(hardWeight),
        passThreshold: Value(passThreshold),
        updatedAt: Value(now),
      ),
    );
    await _notifySyncRelevantUsers(
      await _syncAffectedUsersForCourseTeacherOnly(courseVersionId),
    );
  }

  Future<void> importStudentPassConfig({
    required int courseVersionId,
    required int studentId,
    required double easyWeight,
    required double mediumWeight,
    required double hardWeight,
    required double passThreshold,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) async {
    final normalizedCreatedAt =
        (createdAt ?? updatedAt ?? DateTime.now()).toUtc();
    final normalizedUpdatedAt =
        (updatedAt ?? createdAt ?? DateTime.now()).toUtc();
    final existing = await getStudentPassConfig(
      courseVersionId: courseVersionId,
      studentId: studentId,
    );
    if (existing == null) {
      await into(studentPassConfigs).insert(
        StudentPassConfigsCompanion.insert(
          courseVersionId: courseVersionId,
          studentId: studentId,
          easyWeight: Value(easyWeight),
          mediumWeight: Value(mediumWeight),
          hardWeight: Value(hardWeight),
          passThreshold: Value(passThreshold),
          createdAt: Value(normalizedCreatedAt),
          updatedAt: Value(normalizedUpdatedAt),
        ),
      );
      await _notifySyncRelevantUsers(
        await _syncAffectedUsersForCourseTeacherOnly(courseVersionId),
      );
      return;
    }
    await (update(studentPassConfigs)
          ..where((tbl) => tbl.id.equals(existing.id)))
        .write(
      StudentPassConfigsCompanion(
        easyWeight: Value(easyWeight),
        mediumWeight: Value(mediumWeight),
        hardWeight: Value(hardWeight),
        passThreshold: Value(passThreshold),
        createdAt: Value(normalizedCreatedAt),
        updatedAt: Value(normalizedUpdatedAt),
      ),
    );
    await _notifySyncRelevantUsers(
      await _syncAffectedUsersForCourseTeacherOnly(courseVersionId),
    );
  }

  Future<void> deleteStudentPassConfig({
    required int courseVersionId,
    required int studentId,
  }) async {
    await (delete(studentPassConfigs)
          ..where((tbl) =>
              tbl.courseVersionId.equals(courseVersionId) &
              tbl.studentId.equals(studentId)))
        .go();
    await _notifySyncRelevantUsers(
      await _syncAffectedUsersForCourseTeacherOnly(courseVersionId),
    );
  }

  Future<void> deleteStudentPassConfigsForCourse(int courseVersionId) async {
    await (delete(studentPassConfigs)
          ..where((tbl) => tbl.courseVersionId.equals(courseVersionId)))
        .go();
    await _notifySyncRelevantUsers(
      await _syncAffectedUsersForCourseTeacherOnly(courseVersionId),
    );
  }

  User _preferAuthCanonicalUser(User left, User right) {
    final leftPlaceholder = _isPlaceholderUser(left);
    final rightPlaceholder = _isPlaceholderUser(right);
    if (leftPlaceholder != rightPlaceholder) {
      return leftPlaceholder ? right : left;
    }
    return left.id <= right.id ? left : right;
  }

  User _preferMigrationCanonicalUser(List<User> matches) {
    final sorted = matches.toList()
      ..sort((left, right) {
        final leftPlaceholder = _isPlaceholderUser(left);
        final rightPlaceholder = _isPlaceholderUser(right);
        if (leftPlaceholder != rightPlaceholder) {
          return leftPlaceholder ? 1 : -1;
        }
        return left.id.compareTo(right.id);
      });
    return sorted.first;
  }

  bool _isPlaceholderUser(User user) {
    return user.pinHash == _remoteTeacherPlaceholderPinHash ||
        user.pinHash == _remoteStudentPlaceholderPinHash ||
        user.pinHash == _remoteUserPlaceholderPinHash;
  }

  String _preferCanonicalRole({
    required String primary,
    required String secondary,
  }) {
    final normalizedPrimary = primary.trim().toLowerCase();
    final normalizedSecondary = secondary.trim().toLowerCase();
    if (normalizedPrimary == normalizedSecondary) {
      return normalizedPrimary;
    }
    if (normalizedPrimary == 'admin' || normalizedSecondary == 'admin') {
      return normalizedPrimary == 'admin'
          ? normalizedPrimary
          : normalizedSecondary;
    }
    if (normalizedPrimary == 'teacher' || normalizedSecondary == 'teacher') {
      return normalizedPrimary == 'teacher'
          ? normalizedPrimary
          : normalizedSecondary;
    }
    return normalizedPrimary.isNotEmpty
        ? normalizedPrimary
        : normalizedSecondary;
  }

  String? _normalizeCourseKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return p.normalize(trimmed);
  }

  String? _normalizePromptField(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String? _resolveStudentPromptField(
    String? studentValue,
    String? studentGlobalValue,
    String? courseValue,
    String? systemValue,
  ) {
    final resolvedStudent = _normalizePromptField(studentValue);
    if (resolvedStudent != null) {
      return resolvedStudent;
    }
    final resolvedStudentGlobal = _normalizePromptField(studentGlobalValue);
    if (resolvedStudentGlobal != null) {
      return resolvedStudentGlobal;
    }
    final resolvedCourse = _normalizePromptField(courseValue);
    if (resolvedCourse != null) {
      return resolvedCourse;
    }
    final resolvedSystem = _normalizePromptField(systemValue);
    if (resolvedSystem != null) {
      return resolvedSystem;
    }
    return null;
  }

  Expression<bool> Function($PromptTemplatesTable) _promptScopeMatch({
    required String? courseKey,
    required int? studentId,
  }) {
    return (tbl) {
      final courseMatch = courseKey == null
          ? tbl.courseKey.isNull()
          : tbl.courseKey.equals(courseKey);
      final studentMatch = studentId == null
          ? tbl.studentId.isNull()
          : tbl.studentId.equals(studentId);
      return courseMatch & studentMatch;
    };
  }

  Expression<bool> _profileScopeMatch(
    $StudentPromptProfilesTable tbl, {
    required String? courseKey,
    required int? studentId,
  }) {
    final courseMatch = courseKey == null
        ? tbl.courseKey.isNull()
        : tbl.courseKey.equals(courseKey);
    final studentMatch = studentId == null
        ? tbl.studentId.isNull()
        : tbl.studentId.equals(studentId);
    return courseMatch & studentMatch;
  }

  String? _normalizeLevel(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == 'easy' ||
        normalized == 'medium' ||
        normalized == 'hard') {
      return normalized;
    }
    return null;
  }

  int _deriveLitPercentFromPassedCounts({
    required int easyPassedCount,
    required int mediumPassedCount,
    required int hardPassedCount,
    int fallbackPercent = 0,
  }) {
    if (hardPassedCount > 0) {
      return 100;
    }
    if (mediumPassedCount > 0) {
      return 66;
    }
    if (easyPassedCount > 0) {
      return 33;
    }
    return fallbackPercent.clamp(0, 100);
  }

  _NormalizedPassedCounts _normalizePassedCounts({
    required bool lit,
    required int litPercent,
    required String? questionLevel,
    required int easyPassedCount,
    required int mediumPassedCount,
    required int hardPassedCount,
    bool fallbackHardForLit = false,
  }) {
    var easy = easyPassedCount < 0 ? 0 : easyPassedCount;
    var medium = mediumPassedCount < 0 ? 0 : mediumPassedCount;
    var hard = hardPassedCount < 0 ? 0 : hardPassedCount;
    if (easy > 0 || medium > 0 || hard > 0) {
      return _NormalizedPassedCounts(
        easyPassedCount: easy,
        mediumPassedCount: medium,
        hardPassedCount: hard,
      );
    }
    final legacyLevel = _legacyBestPassedLevel(
      lit: lit,
      litPercent: litPercent,
      questionLevel: questionLevel,
      fallbackHardForLit: fallbackHardForLit,
    );
    switch (legacyLevel) {
      case 'hard':
        hard = 1;
        break;
      case 'medium':
        medium = 1;
        break;
      case 'easy':
        easy = 1;
        break;
    }
    return _NormalizedPassedCounts(
      easyPassedCount: easy,
      mediumPassedCount: medium,
      hardPassedCount: hard,
    );
  }

  String? _legacyBestPassedLevel({
    required bool lit,
    required int litPercent,
    required String? questionLevel,
    required bool fallbackHardForLit,
  }) {
    final normalizedLevel = _normalizeLevel(questionLevel);
    if (litPercent >= 100 || normalizedLevel == 'hard') {
      return 'hard';
    }
    if (litPercent >= 66 || normalizedLevel == 'medium') {
      return 'medium';
    }
    if (litPercent >= 33 || normalizedLevel == 'easy') {
      return 'easy';
    }
    if (lit && fallbackHardForLit) {
      return 'hard';
    }
    return null;
  }

  bool _shouldTakeIncomingProgressDetails({
    required ProgressEntry existing,
    required int incomingLitPercent,
    required String? incomingQuestionLevel,
    required DateTime incomingUpdatedAt,
  }) {
    final existingRank = existing.litPercent.clamp(0, 100);
    final incomingRank = incomingLitPercent.clamp(0, 100);
    if (incomingRank != existingRank) {
      return incomingRank > existingRank;
    }
    return incomingUpdatedAt.isAfter(existing.updatedAt);
  }
}

class _NormalizedPassedCounts {
  const _NormalizedPassedCounts({
    required this.easyPassedCount,
    required this.mediumPassedCount,
    required this.hardPassedCount,
  });

  final int easyPassedCount;
  final int mediumPassedCount;
  final int hardPassedCount;
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
    } else if (createdRaw is int) {
      if (createdRaw > 20000000000) {
        createdAt = DateTime.fromMillisecondsSinceEpoch(createdRaw);
      } else {
        createdAt = DateTime.fromMillisecondsSinceEpoch(createdRaw * 1000);
      }
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

class StudentPromptContext {
  StudentPromptContext({
    required this.profileText,
    required this.preferencesText,
  });

  final String profileText;
  final String preferencesText;
}

class ResolvedStudentPassRule {
  const ResolvedStudentPassRule({
    required this.easyWeight,
    required this.mediumWeight,
    required this.hardWeight,
    required this.passThreshold,
  });

  static const double defaultEasyWeight = 0.25;
  static const double defaultMediumWeight = 0.5;
  static const double defaultHardWeight = 1.0;
  static const double defaultPassThreshold = 1.0;

  final double easyWeight;
  final double mediumWeight;
  final double hardWeight;
  final double passThreshold;

  double scoreForCounts({
    required int easyCount,
    required int mediumCount,
    required int hardCount,
  }) {
    return easyCount * easyWeight +
        mediumCount * mediumWeight +
        hardCount * hardWeight;
  }

  bool litForCounts({
    required int easyCount,
    required int mediumCount,
    required int hardCount,
  }) {
    return scoreForCounts(
          easyCount: easyCount,
          mediumCount: mediumCount,
          hardCount: hardCount,
        ) >=
        passThreshold;
  }

  int litPercentForCounts({
    required int easyCount,
    required int mediumCount,
    required int hardCount,
  }) {
    if (passThreshold <= 0) {
      return 100;
    }
    final ratio = scoreForCounts(
          easyCount: easyCount,
          mediumCount: mediumCount,
          hardCount: hardCount,
        ) /
        passThreshold;
    final percent = (ratio * 100).round();
    if (percent < 0) {
      return 0;
    }
    if (percent > 100) {
      return 100;
    }
    return percent;
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
    required this.summaryText,
    required this.summaryLit,
  });

  final int sessionId;
  final String? sessionTitle;
  final DateTime startedAt;
  final int courseVersionId;
  final String? courseSubject;
  final String kpKey;
  final String? nodeTitle;
  final String? summaryText;
  final bool summaryLit;

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
      summaryText: row['summary_text'] as String?,
      summaryLit: row['summary_lit'] == true || row['summary_lit'] == 1,
    );
  }
}

class AssignedRemoteCourseInfo {
  AssignedRemoteCourseInfo({
    required this.courseVersionId,
    required this.remoteCourseId,
    required this.courseSubject,
  });

  final int courseVersionId;
  final int remoteCourseId;
  final String courseSubject;

  factory AssignedRemoteCourseInfo.fromRow(Map<String, Object?> row) {
    return AssignedRemoteCourseInfo(
      courseVersionId: row['course_version_id'] as int,
      remoteCourseId: row['remote_course_id'] as int,
      courseSubject: (row['course_subject'] as String?) ?? '',
    );
  }
}

class CourseStudentTreeInfo {
  CourseStudentTreeInfo({
    required this.courseVersionId,
    required this.courseSubject,
    required this.studentId,
    required this.studentUsername,
  });

  final int courseVersionId;
  final String courseSubject;
  final int studentId;
  final String studentUsername;

  factory CourseStudentTreeInfo.fromRow(Map<String, Object?> row) {
    return CourseStudentTreeInfo(
      courseVersionId: row['course_version_id'] as int,
      courseSubject: (row['course_subject'] as String?) ?? '',
      studentId: row['student_id'] as int,
      studentUsername: (row['student_username'] as String?) ?? '',
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final file = await DbPathProvider.getDatabaseFile();
    return NativeDatabase(file);
  });
}
