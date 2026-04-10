import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tutor1on1/constants.dart';
import 'package:tutor1on1/db/app_database.dart' hide SyncItemState;
import 'package:tutor1on1/llm/prompt_repository.dart';
import 'package:tutor1on1/security/hash_utils.dart';
import 'package:tutor1on1/security/pin_hasher.dart';
import 'package:tutor1on1/services/artifact_sync_api_service.dart';
import 'package:tutor1on1/services/auth_api_service.dart';
import 'package:tutor1on1/services/course_artifact_service.dart';
import 'package:tutor1on1/services/course_service.dart';
import 'package:tutor1on1/services/device_identity_service.dart';
import 'package:tutor1on1/services/enrollment_sync_service.dart';
import 'package:tutor1on1/services/home_sync_coordinator.dart';
import 'package:tutor1on1/services/marketplace_api_service.dart';
import 'package:tutor1on1/services/secure_storage_service.dart';
import 'package:tutor1on1/services/session_sync_service.dart';
import 'package:tutor1on1/services/settings_repository.dart';
import 'package:tutor1on1/services/student_kp_artifact_store_service.dart';
import 'package:tutor1on1/services/sync_log_repository.dart';
import 'package:tutor1on1/services/sync_progress.dart';

const List<_AccountSpec> _accounts = <_AccountSpec>[
  _AccountSpec(username: 'dennis', password: '0945'),
  _AccountSpec(username: 'albert', password: '1234'),
  _AccountSpec(username: 'charles', password: '1234'),
];

const String _enrollmentSyncDomainTeacher = 'enrollment_sync_teacher';
const String _enrollmentSyncDomainStudent = 'enrollment_sync_student';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'diagnose live login sync timings for dennis albert charles',
    (tester) async {
      WidgetsFlutterBinding.ensureInitialized();
      final report = <String, Object?>{
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'api_base_url': kAuthBaseUrl,
        'http_proxy': Platform.environment['HTTP_PROXY'],
        'https_proxy': Platform.environment['HTTPS_PROXY'],
        'all_proxy': Platform.environment['ALL_PROXY'],
        'results': <Object?>[],
      };

      final realSecureStorage = SecureStorageService();
      await realSecureStorage.ensureReadableOrReset();
      final deviceSnapshot =
          await DeviceIdentityService(realSecureStorage).snapshot();
      final secureSeed = await const FlutterSecureStorage().readAll();

      for (final account in _accounts) {
        final accountReport = await _runAccountDiagnosis(
          account: account,
          secureSeed: secureSeed,
          deviceSnapshot: deviceSnapshot,
        );
        (report['results'] as List<Object?>).add(accountReport);
      }

      final reportJson = const JsonEncoder.withIndent('  ').convert(report);
      final outFile = File(
        p.join(
          Directory.current.path,
          '.tmp',
          'live_sync_diagnose_report.json',
        ),
      );
      await outFile.parent.create(recursive: true);
      await outFile.writeAsString(reportJson, flush: true);
      // ignore: avoid_print
      print(reportJson);
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );

  testWidgets(
    'diagnose repeat login core sync timings for dennis and albert',
    (tester) async {
      WidgetsFlutterBinding.ensureInitialized();
      final report = <String, Object?>{
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'api_base_url': kAuthBaseUrl,
        'results': <Object?>[],
      };

      final realSecureStorage = SecureStorageService();
      await realSecureStorage.ensureReadableOrReset();
      final deviceSnapshot =
          await DeviceIdentityService(realSecureStorage).snapshot();
      final secureSeed = await const FlutterSecureStorage().readAll();

      for (final account in _accounts.where((it) {
        return it.username == 'dennis' || it.username == 'albert';
      })) {
        final accountReport = await _runRepeatLoginDiagnosis(
          account: account,
          secureSeed: secureSeed,
          deviceSnapshot: deviceSnapshot,
        );
        (report['results'] as List<Object?>).add(accountReport);
      }

      final reportJson = const JsonEncoder.withIndent('  ').convert(report);
      final outFile = File(
        p.join(
          Directory.current.path,
          '.tmp',
          'repeat_login_sync_report.json',
        ),
      );
      await outFile.parent.create(recursive: true);
      await outFile.writeAsString(reportJson, flush: true);
      // ignore: avoid_print
      print(reportJson);
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}

Future<Map<String, Object?>> _runAccountDiagnosis({
  required _AccountSpec account,
  required Map<String, String> secureSeed,
  required DeviceIdentitySnapshot deviceSnapshot,
}) async {
  final tempRoot = await Directory.systemTemp.createTemp(
    'live_sync_diagnose_${account.username}_',
  );
  final docsDir = Directory(p.join(tempRoot.path, 'documents'))
    ..createSync(recursive: true);
  final secureStorage = _SeededSecureStorage(secureSeed);
  final apiEvents = <Map<String, Object?>>[];
  final progressEvents = <Map<String, Object?>>[];
  final noteEvents = <Map<String, Object?>>[];

  AppDatabase? db;
  try {
    final liveDbFile = await _copyLiveDatabase(docsDir);
    await _copyLiveArtifacts(docsDir);
    PathProviderPlatform.instance = _TestPathProviderPlatform(tempRoot.path);

    db = AppDatabase.forTesting(NativeDatabase(liveDbFile));
    final promptRepository = PromptRepository(db: db);
    final courseArtifactService = CourseArtifactService();
    final courseService = CourseService(
      db,
      courseArtifactService: courseArtifactService,
    );
    final artifactApi = _ProfilingArtifactSyncApiService(
      secureStorage: secureStorage,
      events: apiEvents,
    );
    final marketplaceApi = _ProfilingMarketplaceApiService(
      secureStorage: secureStorage,
      events: apiEvents,
    );
    final enrollmentSyncService = EnrollmentSyncService(
      db: db,
      secureStorage: secureStorage,
      courseService: courseService,
      marketplaceApi: marketplaceApi,
      promptRepository: promptRepository,
      artifactApi: artifactApi,
      courseArtifactService: courseArtifactService,
    );
    final sessionSyncService = SessionSyncService(
      db: db,
      api: artifactApi,
      artifactStore: StudentKpArtifactStoreService(),
    );
    await promptRepository.backfillAssignmentPrompts();
    await sessionSyncService.ensureLocalCutoverInitialized();
    db.setSyncRelevantChangeCallback((change) async {
      await enrollmentSyncService.handleLocalSyncRelevantChange(change);
      await sessionSyncService.handleLocalSyncRelevantChange(change);
    });

    final authApi = AuthApiService(
      baseUrl: kAuthBaseUrl,
      allowInsecureTls: kAuthAllowInsecureTls,
    );

    final authTimer = Stopwatch()..start();
    final auth = await authApi.login(
      username: account.username,
      password: account.password,
      deviceKey: deviceSnapshot.deviceKey,
      deviceName: deviceSnapshot.deviceName,
      platform: deviceSnapshot.platform,
      timezoneName: deviceSnapshot.timezoneName,
      timezoneOffsetMinutes: deviceSnapshot.timezoneOffsetMinutes,
      appVersion: deviceSnapshot.appVersion,
    );
    authTimer.stop();
    await secureStorage.writeAuthTokens(
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
    );
    final currentUser = await db.upsertAuthenticatedUser(
      username: account.username,
      pinHash: PinHasher.hash(account.password),
      role: auth.role,
      remoteUserId: auth.userId,
    );

    final beforeStats = await _collectLocalStats(
      db: db,
      currentUser: currentUser,
      remoteUserId: auth.userId,
    );
    noteEvents.add(<String, Object?>{
      'step': 'before_stats',
      'stats': beforeStats,
    });

    await sessionSyncService.prepareForAutoSync(
      currentUser: currentUser,
      password: account.password,
    );

    final blockingStages = <Map<String, Object?>>[];
    try {
      if (currentUser.role == 'teacher') {
        await _timeStage(
          blockingStages,
          'enrollment_force_pull',
          () => enrollmentSyncService.forcePullFromServer(
            currentUser: currentUser,
          ),
        );
      } else {
        await _timeStage(
          blockingStages,
          'enrollment_force_pull',
          () => enrollmentSyncService.forcePullFromServer(
            currentUser: currentUser,
          ),
        );
        await _timeStage(
          blockingStages,
          'session_force_pull_download_only',
          () => sessionSyncService.forcePullFromServer(
            currentUser: currentUser,
            wipeLocalStudentData: true,
            onProgress: (progress) {
              progressEvents.add(_progressEvent(progress));
            },
            mode: SessionSyncMode.downloadOnly,
          ),
        );
      }
    } catch (_) {}

    final afterStats = await _collectLocalStats(
      db: db,
      currentUser: currentUser,
      remoteUserId: auth.userId,
    );
    noteEvents.add(<String, Object?>{
      'step': 'after_stats',
      'stats': afterStats,
    });

    return <String, Object?>{
      'username': account.username,
      'role': auth.role,
      'remote_user_id': auth.userId,
      'temp_root': tempRoot.path,
      'auth_ms': authTimer.elapsedMilliseconds,
      'blocking_stages': blockingStages,
      'teacher_background_sync_ms': null,
      'teacher_background_sync_error': null,
      'api_events': apiEvents,
      'progress_events': progressEvents,
      'notes': noteEvents,
    };
  } catch (error, stackTrace) {
    return <String, Object?>{
      'username': account.username,
      'temp_root': tempRoot.path,
      'fatal_error': error.toString(),
      'fatal_stack': stackTrace.toString(),
      'api_events': apiEvents,
      'progress_events': progressEvents,
      'notes': noteEvents,
    };
  } finally {
    await db?.close();
  }
}

Future<Map<String, Object?>> _runRepeatLoginDiagnosis({
  required _AccountSpec account,
  required Map<String, String> secureSeed,
  required DeviceIdentitySnapshot deviceSnapshot,
}) async {
  final tempRoot = await Directory.systemTemp.createTemp(
    'repeat_login_sync_${account.username}_',
  );
  final docsDir = Directory(p.join(tempRoot.path, 'documents'))
    ..createSync(recursive: true);
  final secureStorage = _SeededSecureStorage(secureSeed);

  AppDatabase? db;
  try {
    final liveDbFile = await _copyLiveDatabase(docsDir);
    await _copyLiveArtifacts(docsDir);
    PathProviderPlatform.instance = _TestPathProviderPlatform(tempRoot.path);

    db = AppDatabase.forTesting(NativeDatabase(liveDbFile));
    final promptRepository = PromptRepository(db: db);
    final courseArtifactService = CourseArtifactService();
    final courseService = CourseService(
      db,
      courseArtifactService: courseArtifactService,
    );
    final artifactApi = ArtifactSyncApiService(secureStorage: secureStorage);
    final marketplaceApi = MarketplaceApiService(secureStorage: secureStorage);
    final enrollmentSyncService = EnrollmentSyncService(
      db: db,
      secureStorage: secureStorage,
      courseService: courseService,
      marketplaceApi: marketplaceApi,
      promptRepository: promptRepository,
      artifactApi: artifactApi,
      courseArtifactService: courseArtifactService,
    );
    final sessionSyncService = SessionSyncService(
      db: db,
      api: artifactApi,
      artifactStore: StudentKpArtifactStoreService(),
    );
    final syncCoordinator = HomeSyncCoordinator(
      enrollmentSyncService: enrollmentSyncService,
      sessionSyncService: sessionSyncService,
      syncLogRepository: SyncLogRepository(SettingsRepository(db)),
    );
    await promptRepository.backfillAssignmentPrompts();
    await sessionSyncService.ensureLocalCutoverInitialized();
    db.setSyncRelevantChangeCallback((change) async {
      await enrollmentSyncService.handleLocalSyncRelevantChange(change);
      await sessionSyncService.handleLocalSyncRelevantChange(change);
    });

    final authApi = AuthApiService(
      baseUrl: kAuthBaseUrl,
      allowInsecureTls: kAuthAllowInsecureTls,
    );
    final auth = await authApi.login(
      username: account.username,
      password: account.password,
      deviceKey: deviceSnapshot.deviceKey,
      deviceName: deviceSnapshot.deviceName,
      platform: deviceSnapshot.platform,
      timezoneName: deviceSnapshot.timezoneName,
      timezoneOffsetMinutes: deviceSnapshot.timezoneOffsetMinutes,
      appVersion: deviceSnapshot.appVersion,
    );
    await secureStorage.writeAuthTokens(
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
    );
    final currentUser = await db.upsertAuthenticatedUser(
      username: account.username,
      pinHash: PinHasher.hash(account.password),
      role: auth.role,
      remoteUserId: auth.userId,
    );
    await sessionSyncService.prepareForAutoSync(
      currentUser: currentUser,
      password: account.password,
    );

    final stages = <Map<String, Object?>>[];
    await _timeStage(
      stages,
      'login_sync_1',
      () => syncCoordinator.runLoginSync(
        user: currentUser,
        trigger: 'login_1',
        onProgress: null,
        includeSessionSync: true,
        sessionSyncMode: SessionSyncMode.downloadOnly,
      ),
    );
    await secureStorage.writeSyncRunAt(
      remoteUserId: auth.userId,
      domain: currentUser.role == 'teacher'
          ? _enrollmentSyncDomainTeacher
          : _enrollmentSyncDomainStudent,
      runAt: DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
    );
    await _timeStage(
      stages,
      'login_sync_2',
      () => syncCoordinator.runLoginSync(
        user: currentUser,
        trigger: 'login_2',
        onProgress: null,
        includeSessionSync: true,
        sessionSyncMode: SessionSyncMode.downloadOnly,
      ),
    );

    return <String, Object?>{
      'username': account.username,
      'role': auth.role,
      'remote_user_id': auth.userId,
      'temp_root': tempRoot.path,
      'stages': stages,
      'local_stats': await _collectLocalStats(
        db: db,
        currentUser: currentUser,
        remoteUserId: auth.userId,
      ),
    };
  } catch (error, stackTrace) {
    return <String, Object?>{
      'username': account.username,
      'temp_root': tempRoot.path,
      'fatal_error': error.toString(),
      'fatal_stack': stackTrace.toString(),
    };
  } finally {
    await db?.close();
  }
}

Future<void> _timeStage(
  List<Map<String, Object?>> events,
  String name,
  Future<SyncRunStats> Function() action,
) async {
  final timer = Stopwatch()..start();
  try {
    final stats = await action();
    timer.stop();
    events.add(<String, Object?>{
      'stage': name,
      'ok': true,
      'ms': timer.elapsedMilliseconds,
      'downloaded_count': stats.downloadedCount,
      'downloaded_bytes': stats.downloadedBytes,
      'uploaded_count': stats.uploadedCount,
      'uploaded_bytes': stats.uploadedBytes,
    });
  } catch (error) {
    timer.stop();
    events.add(<String, Object?>{
      'stage': name,
      'ok': false,
      'ms': timer.elapsedMilliseconds,
      'error': error.toString(),
    });
    rethrow;
  }
}

Map<String, Object?> _progressEvent(SyncProgress progress) {
  return <String, Object?>{
    'at': DateTime.now().toUtc().toIso8601String(),
    'message': progress.message,
    'value': progress.value,
    'detail': progress.detail,
  };
}

Future<Map<String, Object?>> _collectLocalStats({
  required AppDatabase db,
  required User currentUser,
  required int remoteUserId,
}) async {
  final counts = await db.customSelect(
    '''
    SELECT
      (SELECT COUNT(*) FROM course_versions) AS course_count,
      (SELECT COUNT(*) FROM course_remote_links) AS remote_course_link_count,
      (SELECT COUNT(*) FROM student_course_assignments) AS assignment_count,
      (SELECT COUNT(*) FROM progress_entries) AS progress_count,
      (SELECT COUNT(*) FROM chat_sessions) AS session_count,
      (SELECT COUNT(*) FROM chat_messages) AS message_count
    ''',
  ).getSingle();
  final manifest = await StudentKpArtifactStoreService().loadManifest(
    remoteUserId,
  );
  final docsDir = await _TestPathProviderPlatform.currentDocumentsDirectory();
  final userArtifactsDir = Directory(
    p.join(
      docsDir.path,
      'sync_artifacts',
      'student_kp',
      '$remoteUserId',
      'artifacts',
    ),
  );
  final artifactFileCount = userArtifactsDir.existsSync()
      ? userArtifactsDir.listSync(followLinks: false).whereType<File>().length
      : 0;
  return <String, Object?>{
    'username': currentUser.username,
    'role': currentUser.role,
    'course_count': counts.read<int>('course_count'),
    'remote_course_link_count': counts.read<int>('remote_course_link_count'),
    'assignment_count': counts.read<int>('assignment_count'),
    'progress_count': counts.read<int>('progress_count'),
    'session_count': counts.read<int>('session_count'),
    'message_count': counts.read<int>('message_count'),
    'student_manifest_item_count': manifest.items.length,
    'student_manifest_state2': manifest.state2,
    'student_artifact_file_count': artifactFileCount,
  };
}

Future<File> _copyLiveDatabase(Directory targetDocumentsDir) async {
  final liveDocsDir = Directory(r'C:\Mac\Home\Documents');
  File? source;
  for (final fileName in <String>['tutor1on1.db', 'family_teacher.db']) {
    final candidate = File(p.join(liveDocsDir.path, fileName));
    if (await candidate.exists()) {
      source = candidate;
      break;
    }
  }
  if (source == null) {
    throw StateError('Live database not found in ${liveDocsDir.path}.');
  }
  final target = File(p.join(targetDocumentsDir.path, 'tutor1on1.db'));
  await source.copy(target.path);
  for (final suffix in const <String>['-wal', '-shm', '-journal']) {
    final sidecar = File('${source.path}$suffix');
    if (await sidecar.exists()) {
      await sidecar.copy('${target.path}$suffix');
    }
  }
  return target;
}

Future<void> _copyLiveArtifacts(Directory targetDocumentsDir) async {
  final source = Directory(p.join(r'C:\Mac\Home\Documents', 'sync_artifacts'));
  if (!source.existsSync()) {
    return;
  }
  await _copyDirectory(
    source,
    Directory(p.join(targetDocumentsDir.path, 'sync_artifacts')),
  );
}

Future<void> _copyDirectory(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entity
      in source.list(recursive: false, followLinks: false)) {
    final name = p.basename(entity.path);
    if (entity is Directory) {
      await _copyDirectory(entity, Directory(p.join(target.path, name)));
      continue;
    }
    if (entity is File) {
      await entity.copy(p.join(target.path, name));
    }
  }
}

class _AccountSpec {
  const _AccountSpec({
    required this.username,
    required this.password,
  });

  final String username;
  final String password;
}

class _ProfilingArtifactSyncApiService extends ArtifactSyncApiService {
  _ProfilingArtifactSyncApiService({
    required super.secureStorage,
    required this.events,
  });

  final List<Map<String, Object?>> events;

  @override
  Future<String> getState2({String? artifactClass}) async {
    return _time(
        'artifact_state2',
        () => super.getState2(
              artifactClass: artifactClass,
            ));
  }

  @override
  Future<ArtifactState1Result> getState1({
    String? artifactClass,
    int? studentUserId,
    int? courseId,
  }) async {
    return _time(
      'artifact_state1',
      () => super.getState1(
        artifactClass: artifactClass,
        studentUserId: studentUserId,
        courseId: courseId,
      ),
      extra: <String, Object?>{
        if ((artifactClass ?? '').trim().isNotEmpty)
          'artifact_class': artifactClass,
        if (studentUserId != null) 'student_user_id': studentUserId,
        if (courseId != null) 'course_id': courseId,
      },
      mapResult: (result) => <String, Object?>{
        'item_count': result.items.length,
        'state2': result.state2,
      },
    );
  }

  @override
  Future<DownloadedArtifact> downloadArtifact(String artifactId) async {
    return _time(
      'artifact_download',
      () => super.downloadArtifact(artifactId),
      extra: <String, Object?>{
        'artifact_id': artifactId,
      },
      mapResult: (result) => <String, Object?>{
        'bytes': result.bytes.length,
        'sha256': result.sha256,
      },
    );
  }

  @override
  Future<List<DownloadedArtifact>> downloadArtifactBatch(
    List<String> artifactIds,
  ) async {
    return _time(
      'artifact_download_batch',
      () => super.downloadArtifactBatch(artifactIds),
      extra: <String, Object?>{
        'artifact_count': artifactIds.length,
      },
      mapResult: (result) => <String, Object?>{
        'downloaded_count': result.length,
        'downloaded_bytes': result.fold<int>(
          0,
          (sum, item) => sum + item.bytes.length,
        ),
      },
    );
  }

  Future<T> _time<T>(
    String op,
    Future<T> Function() action, {
    Map<String, Object?> extra = const <String, Object?>{},
    Map<String, Object?> Function(T result)? mapResult,
  }) async {
    final timer = Stopwatch()..start();
    try {
      final result = await action();
      timer.stop();
      events.add(<String, Object?>{
        'op': op,
        'ok': true,
        'ms': timer.elapsedMilliseconds,
        ...extra,
        ...?mapResult?.call(result),
      });
      return result;
    } catch (error) {
      timer.stop();
      events.add(<String, Object?>{
        'op': op,
        'ok': false,
        'ms': timer.elapsedMilliseconds,
        'error': error.toString(),
        ...extra,
      });
      rethrow;
    }
  }
}

class _ProfilingMarketplaceApiService extends MarketplaceApiService {
  _ProfilingMarketplaceApiService({
    required super.secureStorage,
    required this.events,
  });

  final List<Map<String, Object?>> events;

  @override
  Future<List<EnrollmentSummary>> listEnrollments() async {
    return _time(
      'marketplace_list_enrollments',
      () => super.listEnrollments(),
      mapResult: (result) => <String, Object?>{
        'count': result.length,
      },
    );
  }

  @override
  Future<List<TeacherCourseSummary>> listTeacherCourses() async {
    return _time(
      'marketplace_list_teacher_courses',
      () => super.listTeacherCourses(),
      mapResult: (result) => <String, Object?>{
        'count': result.length,
      },
    );
  }

  @override
  Future<List<SubjectLabelSummary>> listSubjectLabels() async {
    return _time(
      'marketplace_list_subject_labels',
      () => super.listSubjectLabels(),
      mapResult: (result) => <String, Object?>{
        'count': result.length,
      },
    );
  }

  Future<T> _time<T>(
    String op,
    Future<T> Function() action, {
    Map<String, Object?> Function(T result)? mapResult,
  }) async {
    final timer = Stopwatch()..start();
    try {
      final result = await action();
      timer.stop();
      events.add(<String, Object?>{
        'op': op,
        'ok': true,
        'ms': timer.elapsedMilliseconds,
        ...?mapResult?.call(result),
      });
      return result;
    } catch (error) {
      timer.stop();
      events.add(<String, Object?>{
        'op': op,
        'ok': false,
        'ms': timer.elapsedMilliseconds,
        'error': error.toString(),
      });
      rethrow;
    }
  }
}

class _SeededSecureStorage extends SecureStorageService {
  _SeededSecureStorage(Map<String, String> seed)
      : _values = Map<String, String>.from(seed);

  final Map<String, String> _values;
  static final String _syncRunDeviceHash =
      SecureStorageService.syncRunDeviceHash;

  @override
  Future<void> ensureReadableOrReset() async {}

  @override
  Future<void> clearLegacySyncCompatibilityState() async {}

  @override
  Future<String?> readAuthAccessToken() async => _values['auth_access_token'];

  @override
  Future<String?> readAuthRefreshToken() async => _values['auth_refresh_token'];

  @override
  Future<void> writeAuthTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _values['auth_access_token'] = accessToken.trim();
    _values['auth_refresh_token'] = refreshToken.trim();
  }

  @override
  Future<void> deleteAuthTokens() async {
    _values.remove('auth_access_token');
    _values.remove('auth_refresh_token');
  }

  @override
  Future<int?> readInstalledCourseBundleVersion({
    required int remoteUserId,
    required int remoteCourseId,
  }) async {
    final raw = _values[
        'installed_course_bundle_version:$remoteUserId:$remoteCourseId'];
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return int.tryParse(raw.trim());
  }

  @override
  Future<void> writeInstalledCourseBundleVersion({
    required int remoteUserId,
    required int remoteCourseId,
    required int versionId,
  }) async {
    _values['installed_course_bundle_version:$remoteUserId:$remoteCourseId'] =
        versionId.toString();
  }

  @override
  Future<SyncItemState?> readSyncItemState({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) async {
    final raw = _values[_syncItemStateKey(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
    )];
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final hash = (decoded['hash'] as String?)?.trim() ?? '';
    final changedAt =
        DateTime.tryParse((decoded['last_changed_at'] as String?) ?? '');
    final syncedAt =
        DateTime.tryParse((decoded['last_synced_at'] as String?) ?? '');
    if (hash.isEmpty || changedAt == null || syncedAt == null) {
      return null;
    }
    return SyncItemState(
      contentHash: hash,
      lastChangedAt: changedAt,
      lastSyncedAt: syncedAt,
    );
  }

  @override
  Future<void> writeSyncItemState({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
    required String contentHash,
    required DateTime lastChangedAt,
    required DateTime lastSyncedAt,
  }) async {
    _values[_syncItemStateKey(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
    )] = jsonEncode(<String, String>{
      'hash': contentHash.trim(),
      'last_changed_at': lastChangedAt.toUtc().toIso8601String(),
      'last_synced_at': lastSyncedAt.toUtc().toIso8601String(),
    });
  }

  @override
  Future<String?> readLocalSyncState2({
    required int remoteUserId,
    required String domain,
  }) async {
    return _values[_localSyncState2Key(
      remoteUserId: remoteUserId,
      domain: domain,
    )];
  }

  @override
  Future<void> writeLocalSyncState2({
    required int remoteUserId,
    required String domain,
    required String state2,
  }) async {
    _values[_localSyncState2Key(
      remoteUserId: remoteUserId,
      domain: domain,
    )] = state2.trim();
  }

  @override
  Future<void> deleteLocalSyncState2({
    required int remoteUserId,
    required String domain,
  }) async {
    _values.remove(_localSyncState2Key(
      remoteUserId: remoteUserId,
      domain: domain,
    ));
  }

  @override
  Future<DateTime?> readSyncRunAt({
    required int remoteUserId,
    required String domain,
  }) async {
    final raw = _values[_syncRunAtKey(
      remoteUserId: remoteUserId,
      domain: domain,
    )];
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw.trim());
  }

  @override
  Future<void> writeSyncRunAt({
    required int remoteUserId,
    required String domain,
    required DateTime runAt,
  }) async {
    _values[_syncRunAtKey(
      remoteUserId: remoteUserId,
      domain: domain,
    )] = runAt.toUtc().toIso8601String();
  }

  @override
  Future<void> clearSyncDomainState({
    required int remoteUserId,
    required String domain,
    bool clearItemStates = true,
    bool clearListEtags = true,
    bool clearRunAt = true,
  }) async {
    final normalizedDomain = domain.trim().toLowerCase();
    final itemPrefix = 'sync_item_state:$remoteUserId:$normalizedDomain:';
    final etagPrefix = 'sync_list_etag:$remoteUserId:$normalizedDomain:';
    final runPrefix = 'sync_run_at:$remoteUserId:$normalizedDomain:';
    final keys = _values.keys.toList(growable: false);
    for (final key in keys) {
      if (clearItemStates && key.startsWith(itemPrefix)) {
        _values.remove(key);
        continue;
      }
      if (clearListEtags && key.startsWith(etagPrefix)) {
        _values.remove(key);
        continue;
      }
      if (clearRunAt && key.startsWith(runPrefix)) {
        _values.remove(key);
      }
    }
  }

  @override
  Future<DateTime?> readPromptMetadataAppliedAt({
    required int remoteUserId,
    required int remoteCourseId,
  }) async {
    final raw =
        _values['prompt_metadata_applied_at:$remoteUserId:$remoteCourseId'];
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final millis = int.tryParse(raw.trim());
    if (millis == null || millis <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  @override
  Future<void> writePromptMetadataAppliedAt({
    required int remoteUserId,
    required int remoteCourseId,
    required DateTime appliedAt,
  }) async {
    _values['prompt_metadata_applied_at:$remoteUserId:$remoteCourseId'] =
        appliedAt.millisecondsSinceEpoch.toString();
  }

  String _syncItemStateKey({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) {
    final normalizedDomain = domain.trim().toLowerCase();
    final normalizedScope = scopeKey.trim();
    final scopeHash = sha256Hex(normalizedScope);
    return 'sync_item_state:$remoteUserId:$normalizedDomain:$scopeHash';
  }

  String _localSyncState2Key({
    required int remoteUserId,
    required String domain,
  }) {
    final normalizedDomain = domain.trim().toLowerCase();
    return 'local_sync_state2:$remoteUserId:$normalizedDomain';
  }

  String _syncRunAtKey({
    required int remoteUserId,
    required String domain,
  }) {
    final normalizedDomain = domain.trim().toLowerCase();
    return 'sync_run_at:$remoteUserId:$normalizedDomain:$_syncRunDeviceHash';
  }
}

class _TestPathProviderPlatform extends PathProviderPlatform {
  _TestPathProviderPlatform(this.rootPath);

  final String rootPath;
  static String? _currentRootPath;

  static Future<Directory> currentDocumentsDirectory() async {
    final root = _currentRootPath;
    if (root == null || root.trim().isEmpty) {
      throw StateError('Test path provider root is not initialized.');
    }
    final dir = Directory(p.join(root, 'documents'));
    await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<String?> getTemporaryPath() async {
    _currentRootPath = rootPath;
    final dir = Directory(p.join(rootPath, 'temp'));
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    _currentRootPath = rootPath;
    final dir = Directory(p.join(rootPath, 'documents'));
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    _currentRootPath = rootPath;
    final dir = Directory(p.join(rootPath, 'support'));
    await dir.create(recursive: true);
    return dir.path;
  }
}
