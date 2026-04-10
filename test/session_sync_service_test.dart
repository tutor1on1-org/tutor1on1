import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/services/artifact_sync_api_service.dart';
import 'package:tutor1on1/services/secure_storage_service.dart';
import 'package:tutor1on1/services/session_sync_service.dart';
import 'package:tutor1on1/services/student_kp_artifact_store_service.dart';

class _MemorySecureStorage extends SecureStorageService {
  _MemorySecureStorage();

  @override
  Future<String?> readAuthAccessToken() async => 'token';
}

class _CountingArtifactStoreService extends StudentKpArtifactStoreService {
  _CountingArtifactStoreService({
    required Future<Directory> Function() rootDirectoryProvider,
  }) : super(rootDirectoryProvider: rootDirectoryProvider);

  int saveManifestCalls = 0;

  @override
  Future<void> saveManifest(StudentKpArtifactManifest manifest) async {
    saveManifestCalls++;
    await super.saveManifest(manifest);
  }
}

class _ServerArtifact {
  _ServerArtifact({
    required this.item,
    required this.bytes,
  });

  final ArtifactState1Item item;
  final Uint8List bytes;
}

class _FakeArtifactSyncApiService extends ArtifactSyncApiService {
  _FakeArtifactSyncApiService()
      : _zipStore = StudentKpArtifactStoreService(
          rootDirectoryProvider: () async => Directory.systemTemp,
        ),
        super(
          secureStorage: _MemorySecureStorage(),
          baseUrl: 'https://example.com',
          client: MockClient((_) async => http.Response('{}', 200)),
        );

  final StudentKpArtifactStoreService _zipStore;
  final Map<String, ArtifactState1Item> _items = <String, ArtifactState1Item>{};
  final Map<String, Uint8List> _bytesByArtifactId = <String, Uint8List>{};

  int downloadCalls = 0;
  int downloadBatchCalls = 0;
  int uploadCalls = 0;
  int uploadBatchCalls = 0;
  int getState1Calls = 0;
  int getState2Calls = 0;
  final List<String> uploadedArtifactIds = <String>[];

  void seedServerArtifact(_ServerArtifact artifact) {
    _items[artifact.item.artifactId] = artifact.item;
    _bytesByArtifactId[artifact.item.artifactId] =
        Uint8List.fromList(artifact.bytes);
  }

  @override
  Future<String> getState2({String? artifactClass}) async {
    getState2Calls++;
    final items = _stateItems(artifactClass ?? '');
    final builder = StringBuffer();
    for (final item in items) {
      builder
        ..write(item.artifactId)
        ..write('|')
        ..write(item.sha256)
        ..write('\n');
    }
    return 'artifact_state2_v1:${crypto.sha256.convert(
      utf8.encode(builder.toString()),
    )}';
  }

  @override
  Future<ArtifactState1Result> getState1({
    String? artifactClass,
    int? studentUserId,
    int? courseId,
  }) async {
    getState1Calls++;
    final items = _stateItems(
      artifactClass ?? '',
      studentUserId: studentUserId,
      courseId: courseId,
    );
    return ArtifactState1Result(
      state2: 'artifact_state2_v1:${crypto.sha256.convert(
        utf8.encode(_state2DigestInput(items)),
      )}',
      items: items,
    );
  }

  String _state2DigestInput(List<ArtifactState1Item> items) {
    final builder = StringBuffer();
    for (final item in items) {
      builder
        ..write(item.artifactId)
        ..write('|')
        ..write(item.sha256)
        ..write('\n');
    }
    return builder.toString();
  }

  @override
  Future<DownloadedArtifact> downloadArtifact(String artifactId) async {
    downloadCalls++;
    final item = _items[artifactId];
    final bytes = _bytesByArtifactId[artifactId];
    if (item == null || bytes == null) {
      throw StateError('Missing server artifact $artifactId.');
    }
    return DownloadedArtifact(
      artifactId: item.artifactId,
      artifactClass: item.artifactClass,
      sha256: item.sha256,
      lastModified: item.lastModified,
      bytes: Uint8List.fromList(bytes),
    );
  }

  @override
  Future<List<DownloadedArtifact>> downloadArtifactBatch(
    List<String> artifactIds,
  ) async {
    downloadBatchCalls++;
    final downloaded = <DownloadedArtifact>[];
    for (final artifactId in artifactIds) {
      final item = _items[artifactId];
      final bytes = _bytesByArtifactId[artifactId];
      if (item == null || bytes == null) {
        throw StateError('Missing server artifact $artifactId.');
      }
      downloaded.add(
        DownloadedArtifact(
          artifactId: item.artifactId,
          artifactClass: item.artifactClass,
          sha256: item.sha256,
          lastModified: item.lastModified,
          bytes: Uint8List.fromList(bytes),
        ),
      );
    }
    return downloaded;
  }

  @override
  Future<UploadArtifactResult> uploadArtifact({
    required String artifactId,
    required String sha256,
    required Uint8List bytes,
    required String baseSha256,
    required bool overwriteServer,
  }) async {
    final current = _items[artifactId];
    final normalizedBase = baseSha256.trim();
    if (!overwriteServer) {
      if (current == null && normalizedBase.isNotEmpty) {
        throw ArtifactConflictException(
          message: 'Artifact conflict: server_missing',
          serverSha256: '',
          expectedBaseSha256: normalizedBase,
        );
      }
      if (current != null && current.sha256.trim() != normalizedBase) {
        throw ArtifactConflictException(
          message: 'Artifact conflict: server_changed',
          serverSha256: current.sha256,
          expectedBaseSha256: normalizedBase,
        );
      }
    }
    final result = _storeUploadedArtifact(
      artifactId: artifactId,
      sha256: sha256,
      bytes: bytes,
    );
    uploadCalls++;
    uploadedArtifactIds.add(artifactId);
    return result;
  }

  @override
  Future<void> uploadArtifactBatch(List<PendingArtifactUpload> uploads) async {
    uploadBatchCalls++;
    for (final upload in uploads) {
      final current = _items[upload.artifactId];
      final normalizedBase = upload.baseSha256.trim();
      if (!upload.overwriteServer) {
        if (current == null && normalizedBase.isNotEmpty) {
          throw ArtifactConflictException(
            message: 'Artifact conflict: server_missing',
            serverSha256: '',
            expectedBaseSha256: normalizedBase,
          );
        }
        if (current != null && current.sha256.trim() != normalizedBase) {
          throw ArtifactConflictException(
            message: 'Artifact conflict: server_changed',
            serverSha256: current.sha256,
            expectedBaseSha256: normalizedBase,
          );
        }
      }
      _storeUploadedArtifact(
        artifactId: upload.artifactId,
        sha256: upload.sha256,
        bytes: upload.bytes,
      );
      uploadedArtifactIds.add(upload.artifactId);
    }
  }

  List<ArtifactState1Item> _stateItems(
    String artifactClass, {
    int? studentUserId,
    int? courseId,
  }) {
    final normalizedArtifactClass = artifactClass.trim();
    final items = _items.values
        .where((item) =>
            normalizedArtifactClass.isEmpty ||
            item.artifactClass == normalizedArtifactClass)
        .where((item) =>
            studentUserId == null || item.studentUserId == studentUserId)
        .where((item) => courseId == null || item.courseId == courseId)
        .toList(growable: false)
      ..sort((left, right) => left.artifactId.compareTo(right.artifactId));
    return items;
  }

  void _assertServerCompatiblePayload(Map<String, dynamic> payload) {
    final sessions = payload['sessions'];
    if (sessions is! List) {
      throw StateError('student artifact invalid');
    }
    for (final rawSession in sessions) {
      if (rawSession is! Map<String, dynamic>) {
        throw StateError('student artifact invalid');
      }
      final control = rawSession['control_state_json'];
      if (control != null && control is! String) {
        throw StateError('student artifact invalid');
      }
      final evidence = rawSession['evidence_state_json'];
      if (evidence != null && evidence is! String) {
        throw StateError('student artifact invalid');
      }
      final messages = rawSession['messages'];
      if (messages is! List) {
        throw StateError('student artifact invalid');
      }
      for (final rawMessage in messages) {
        if (rawMessage is! Map<String, dynamic>) {
          throw StateError('student artifact invalid');
        }
        final parsed = rawMessage['parsed_json'];
        if (parsed != null && parsed is! String) {
          throw StateError('student artifact invalid');
        }
      }
    }
  }

  UploadArtifactResult _storeUploadedArtifact({
    required String artifactId,
    required String sha256,
    required Uint8List bytes,
  }) {
    final payload = _zipStore.readPayload(bytes);
    _assertServerCompatiblePayload(payload);
    final item = ArtifactState1Item(
      artifactId: artifactId,
      artifactClass: 'student_kp',
      courseId: (payload['course_id'] as num?)?.toInt() ?? 0,
      teacherUserId: (payload['teacher_remote_user_id'] as num?)?.toInt() ?? 0,
      studentUserId: (payload['student_remote_user_id'] as num?)?.toInt() ?? 0,
      kpKey: (payload['kp_key'] as String?)?.trim() ?? '',
      bundleVersionId: 0,
      sha256: sha256.trim(),
      lastModified: (payload['updated_at'] as String?)?.trim() ?? '',
    );
    _items[artifactId] = item;
    _bytesByArtifactId[artifactId] = Uint8List.fromList(bytes);
    return UploadArtifactResult(
      artifactId: artifactId,
      sha256: sha256.trim(),
      bundleVersionId: 0,
      state2: 'artifact_state2_v1:${crypto.sha256.convert(
        utf8.encode(_state2DigestInput(_stateItems('student_kp'))),
      )}',
    );
  }
}

Future<_ServerArtifact> _buildServerArtifact({
  required StudentKpArtifactStoreService store,
  required int remoteStudentUserId,
  required int remoteCourseId,
  required int teacherRemoteUserId,
  required String courseSubject,
  required String kpKey,
  required String updatedAt,
  required List<Map<String, dynamic>> sessions,
  Map<String, dynamic>? progress,
  String studentUsername = 'student_remote',
}) async {
  final artifactId = 'student_kp:$remoteStudentUserId:$remoteCourseId:$kpKey';
  final build = store.buildArtifact(
    LocalArtifactBuildInput(
      artifactId: artifactId,
      lastModified: DateTime.parse(updatedAt).toUtc(),
      payload: <String, dynamic>{
        'schema': 'student_kp_artifact_v1',
        'course_id': remoteCourseId,
        'course_subject': courseSubject,
        'kp_key': kpKey,
        'teacher_remote_user_id': teacherRemoteUserId,
        'student_remote_user_id': remoteStudentUserId,
        'student_username': studentUsername,
        'updated_at': updatedAt,
        if (progress != null) 'progress': progress,
        'sessions': sessions,
      },
    ),
  );
  return _ServerArtifact(
    item: ArtifactState1Item(
      artifactId: artifactId,
      artifactClass: 'student_kp',
      courseId: remoteCourseId,
      teacherUserId: teacherRemoteUserId,
      studentUserId: remoteStudentUserId,
      kpKey: kpKey,
      bundleVersionId: 0,
      sha256: build.sha256,
      lastModified: build.lastModified,
    ),
    bytes: Uint8List.fromList(build.bytes),
  );
}

void main() {
  late AppDatabase db;
  late Directory artifactRoot;
  late StudentKpArtifactStoreService artifactStore;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    artifactRoot = await Directory.systemTemp.createTemp('session_sync_test_');
    artifactStore = StudentKpArtifactStoreService(
      rootDirectoryProvider: () async => artifactRoot,
    );
  });

  tearDown(() async {
    await db.close();
    if (artifactRoot.existsSync()) {
      await artifactRoot.delete(recursive: true);
    }
  });

  test('force pull imports remote per-kp artifact and next sync is clean',
      () async {
    final teacherId = await db.createUser(
      username: 'teacher',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 901,
    );
    final studentId = await db.createUser(
      username: 'student',
      pinHash: 'hash',
      role: 'student',
      remoteUserId: 3001,
    );
    final courseVersionId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Biology',
      granularity: 1,
      textbookText: '',
    );
    await db.upsertCourseRemoteLink(
      courseVersionId: courseVersionId,
      remoteCourseId: 200,
    );
    await db.assignStudent(
        studentId: studentId, courseVersionId: courseVersionId);
    await db.into(db.courseNodes).insert(
          CourseNodesCompanion.insert(
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            title: 'Cells',
            description: '',
            orderIndex: 1,
          ),
        );

    final api = _FakeArtifactSyncApiService();
    api.seedServerArtifact(
      await _buildServerArtifact(
        store: artifactStore,
        remoteStudentUserId: 3001,
        remoteCourseId: 200,
        teacherRemoteUserId: 901,
        courseSubject: 'Biology',
        kpKey: '1.1',
        updatedAt: '2026-04-01T08:05:00Z',
        progress: <String, dynamic>{
          'course_id': 200,
          'course_subject': 'Biology',
          'kp_key': '1.1',
          'lit': true,
          'lit_percent': 80,
          'easy_passed_count': 0,
          'medium_passed_count': 0,
          'hard_passed_count': 0,
          'teacher_remote_user_id': 901,
          'student_remote_user_id': 3001,
          'updated_at': '2026-04-01T08:05:00Z',
        },
        sessions: <Map<String, dynamic>>[
          <String, dynamic>{
            'session_sync_id': 'remote-session-1',
            'course_id': 200,
            'course_subject': 'Biology',
            'kp_key': '1.1',
            'kp_title': 'Cells',
            'session_title': 'Remote Session',
            'started_at': '2026-04-01T08:00:00Z',
            'summary_text': 'server summary',
            'student_remote_user_id': 3001,
            'student_username': 'student',
            'teacher_remote_user_id': 901,
            'updated_at': '2026-04-01T08:05:00Z',
            'messages': <Map<String, dynamic>>[
              <String, dynamic>{
                'role': 'assistant',
                'content': 'server message',
                'created_at': '2026-04-01T08:00:10Z',
              },
            ],
          },
        ],
      ),
    );

    final service = SessionSyncService(
      db: db,
      api: api,
      artifactStore: artifactStore,
    );
    final student = (await db.getUserById(studentId))!;

    final firstStats = await service.forcePullFromServer(
      currentUser: student,
      wipeLocalStudentData: true,
    );
    expect(firstStats.downloadedCount, 1);
    expect(firstStats.uploadedCount, 0);
    expect(api.downloadCalls, 1);
    expect(api.uploadCalls, 0);

    final sessions = await db.getSessionsForStudent(studentId);
    expect(sessions, hasLength(1));
    final importedSession = await db.getSession(sessions.single.sessionId);
    expect(importedSession, isNotNull);
    expect(importedSession!.syncId, 'remote-session-1');
    final messages = await db.getMessagesForSession(importedSession.id);
    expect(messages.single.content, 'server message');
    final progress = await db.getProgress(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
    );
    expect(progress, isNotNull);
    expect(progress!.litPercent, 66);

    final secondStats = await service.syncIfReady(currentUser: student);
    expect(secondStats.downloadedCount, 0);
    expect(secondStats.uploadedCount, 0);
    expect(api.downloadCalls, 1);
    expect(api.uploadCalls, 0);
  });

  test('upload-only session sync uploads local changes without downloads',
      () async {
    final teacherId = await db.createUser(
      username: 'teacher',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 901,
    );
    final studentId = await db.createUser(
      username: 'student',
      pinHash: 'hash',
      role: 'student',
      remoteUserId: 3001,
    );
    final courseVersionId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Math',
      granularity: 1,
      textbookText: '',
    );
    await db.upsertCourseRemoteLink(
      courseVersionId: courseVersionId,
      remoteCourseId: 200,
    );
    await db.assignStudent(
        studentId: studentId, courseVersionId: courseVersionId);
    await db.into(db.courseNodes).insert(
          CourseNodesCompanion.insert(
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            title: 'Fractions',
            description: '',
            orderIndex: 1,
          ),
        );

    final service = SessionSyncService(
      db: db,
      api: _FakeArtifactSyncApiService(),
      artifactStore: artifactStore,
    );
    await service.ensureLocalCutoverInitialized();

    final firstSessionId = await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            title: const Value('Local A'),
            startedAt: Value(DateTime.parse('2026-04-01T09:00:00Z')),
            syncId: const Value('local-session-a'),
            syncUpdatedAt: Value(DateTime.parse('2026-04-01T09:05:00Z')),
          ),
        );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: firstSessionId,
            role: 'assistant',
            content: 'first message',
            createdAt: Value(DateTime.parse('2026-04-01T09:00:10Z')),
          ),
        );
    final secondSessionId = await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            title: const Value('Local B'),
            startedAt: Value(DateTime.parse('2026-04-01T09:10:00Z')),
            syncId: const Value('local-session-b'),
            syncUpdatedAt: Value(DateTime.parse('2026-04-01T09:12:00Z')),
          ),
        );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: secondSessionId,
            role: 'assistant',
            content: 'second message',
            createdAt: Value(DateTime.parse('2026-04-01T09:10:10Z')),
          ),
        );
    await db.upsertProgressFromSync(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
      lit: true,
      litPercent: 60,
      updatedAt: DateTime.parse('2026-04-01T09:12:30Z'),
      mergeWithLocal: false,
    );

    await service.handleLocalSyncRelevantChange(
      SyncRelevantChange(localUserIds: <int>{studentId}),
    );

    final api = _FakeArtifactSyncApiService();
    final uploadService = SessionSyncService(
      db: db,
      api: api,
      artifactStore: artifactStore,
    );
    final student = (await db.getUserById(studentId))!;

    final stats = await uploadService.syncIfReady(
      currentUser: student,
      mode: SessionSyncMode.uploadOnly,
    );
    expect(stats.uploadedCount, 1);
    expect(stats.downloadedCount, 0);
    expect(api.uploadCalls, 1);
    expect(api.uploadedArtifactIds, <String>['student_kp:3001:200:1.1']);
    expect(api.downloadCalls, 0);
    expect(api.downloadBatchCalls, 0);
    expect(api.getState2Calls, 0);
    expect(api.getState1Calls, 1);

    final uploaded = await api.downloadArtifact('student_kp:3001:200:1.1');
    final payload = artifactStore.readPayload(uploaded.bytes);
    expect((payload['sessions'] as List), hasLength(2));

    final secondStats = await uploadService.syncIfReady(
      currentUser: student,
      mode: SessionSyncMode.uploadOnly,
    );
    expect(secondStats.uploadedCount, 0);
    expect(api.uploadCalls, 1);
  });

  test('enrollment db callbacks do not rebuild session artifacts inline',
      () async {
    final teacherId = await db.createUser(
      username: 'teacher',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 901,
    );
    final studentId = await db.createUser(
      username: 'student',
      pinHash: 'hash',
      role: 'student',
      remoteUserId: 3001,
    );
    final courseVersionId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Physics',
      granularity: 1,
      textbookText: '',
    );
    await db.upsertCourseRemoteLink(
      courseVersionId: courseVersionId,
      remoteCourseId: 200,
    );
    await db.into(db.courseNodes).insert(
          CourseNodesCompanion.insert(
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            title: 'Motion',
            description: '',
            orderIndex: 1,
          ),
        );
    final sessionService = SessionSyncService(
      db: db,
      api: _FakeArtifactSyncApiService(),
      artifactStore: artifactStore,
    );
    await sessionService.ensureLocalCutoverInitialized();
    db.setSyncRelevantChangeCallback((change) async {
      await sessionService.handleLocalSyncRelevantChange(change);
    });

    final sessionId = await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            title: const Value('Existing Local Session'),
            startedAt: Value(DateTime.parse('2026-04-09T09:00:00Z')),
            syncId: const Value('local-session-existing'),
            syncUpdatedAt: Value(DateTime.parse('2026-04-09T09:05:00Z')),
          ),
        );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: sessionId,
            role: 'assistant',
            content: 'existing local message',
            createdAt: Value(DateTime.parse('2026-04-09T09:00:10Z')),
          ),
        );
    await db.upsertProgressFromSync(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
      lit: true,
      litPercent: 70,
      updatedAt: DateTime.parse('2026-04-09T09:05:30Z'),
      mergeWithLocal: false,
    );

    final before = await artifactStore.loadManifest(3001);
    expect(before.items, isEmpty);

    await db.assignStudent(
      studentId: studentId,
      courseVersionId: courseVersionId,
    );

    final after = await artifactStore.loadManifest(3001);
    expect(after.items, isEmpty);
  });

  test('local json text fields upload as server-compatible strings', () async {
    final teacherId = await db.createUser(
      username: 'teacher',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 901,
    );
    final studentId = await db.createUser(
      username: 'student',
      pinHash: 'hash',
      role: 'student',
      remoteUserId: 3001,
    );
    final courseVersionId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Physics',
      granularity: 1,
      textbookText: '',
    );
    await db.upsertCourseRemoteLink(
      courseVersionId: courseVersionId,
      remoteCourseId: 200,
    );
    await db.assignStudent(
      studentId: studentId,
      courseVersionId: courseVersionId,
    );
    await db.into(db.courseNodes).insert(
          CourseNodesCompanion.insert(
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            title: 'Motion',
            description: '',
            orderIndex: 1,
          ),
        );

    final service = SessionSyncService(
      db: db,
      api: _FakeArtifactSyncApiService(),
      artifactStore: artifactStore,
    );
    await service.ensureLocalCutoverInitialized();

    final sessionId = await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            title: const Value('Local JSON'),
            startedAt: Value(DateTime.parse('2026-04-06T09:00:00Z')),
            syncId: const Value('local-session-json'),
            syncUpdatedAt: Value(DateTime.parse('2026-04-06T09:05:00Z')),
            controlStateJson: const Value('{"step":2,"mode":"review"}'),
            controlStateUpdatedAt:
                Value(DateTime.parse('2026-04-06T09:05:00Z')),
            evidenceStateJson:
                const Value('{"mistakes":["units"],"score":0.5}'),
            evidenceStateUpdatedAt:
                Value(DateTime.parse('2026-04-06T09:05:30Z')),
          ),
        );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: sessionId,
            role: 'assistant',
            content: 'structured reply',
            parsedJson: const Value('{"hint":"draw a free-body diagram"}'),
            createdAt: Value(DateTime.parse('2026-04-06T09:00:10Z')),
          ),
        );

    await service.handleLocalSyncRelevantChange(
      SyncRelevantChange(localUserIds: <int>{studentId}),
    );

    final api = _FakeArtifactSyncApiService();
    final uploadService = SessionSyncService(
      db: db,
      api: api,
      artifactStore: artifactStore,
    );
    final student = (await db.getUserById(studentId))!;

    final stats = await uploadService.syncIfReady(currentUser: student);
    expect(stats.uploadedCount, 1);
    expect(api.uploadCalls, 1);

    final uploaded = await api.downloadArtifact('student_kp:3001:200:1.1');
    final payload = artifactStore.readPayload(uploaded.bytes);
    final sessions = payload['sessions'] as List<dynamic>;
    final uploadedSession = sessions.single as Map<String, dynamic>;
    expect(uploadedSession['control_state_json'], isA<String>());
    expect(uploadedSession['evidence_state_json'], isA<String>());
    final messages = uploadedSession['messages'] as List<dynamic>;
    final uploadedMessage = messages.single as Map<String, dynamic>;
    expect(uploadedMessage['parsed_json'], isA<String>());
  });

  test('teacher sync downloads student artifact and creates local student copy',
      () async {
    final teacherId = await db.createUser(
      username: 'teacher',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 901,
    );
    final courseVersionId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'History',
      granularity: 1,
      textbookText: '',
    );
    await db.upsertCourseRemoteLink(
      courseVersionId: courseVersionId,
      remoteCourseId: 200,
    );
    await db.into(db.courseNodes).insert(
          CourseNodesCompanion.insert(
            courseVersionId: courseVersionId,
            kpKey: '2.1',
            title: 'Ancient Rome',
            description: '',
            orderIndex: 1,
          ),
        );

    final api = _FakeArtifactSyncApiService();
    api.seedServerArtifact(
      await _buildServerArtifact(
        store: artifactStore,
        remoteStudentUserId: 3001,
        remoteCourseId: 200,
        teacherRemoteUserId: 901,
        courseSubject: 'History',
        kpKey: '2.1',
        updatedAt: '2026-04-01T10:05:00Z',
        progress: <String, dynamic>{
          'course_id': 200,
          'course_subject': 'History',
          'kp_key': '2.1',
          'lit': false,
          'lit_percent': 35,
          'easy_passed_count': 1,
          'medium_passed_count': 0,
          'hard_passed_count': 0,
          'teacher_remote_user_id': 901,
          'student_remote_user_id': 3001,
          'updated_at': '2026-04-01T10:05:00Z',
        },
        sessions: <Map<String, dynamic>>[
          <String, dynamic>{
            'session_sync_id': 'teacher-visible-session',
            'course_id': 200,
            'course_subject': 'History',
            'kp_key': '2.1',
            'kp_title': 'Ancient Rome',
            'session_title': 'Student Session',
            'started_at': '2026-04-01T10:00:00Z',
            'student_remote_user_id': 3001,
            'student_username': 'remote_student',
            'teacher_remote_user_id': 901,
            'updated_at': '2026-04-01T10:05:00Z',
            'messages': <Map<String, dynamic>>[
              <String, dynamic>{
                'role': 'assistant',
                'content': 'teacher can read this',
                'created_at': '2026-04-01T10:00:10Z',
              },
            ],
          },
        ],
      ),
    );

    final service = SessionSyncService(
      db: db,
      api: api,
      artifactStore: artifactStore,
    );
    final teacher = (await db.getUserById(teacherId))!;

    final stats = await service.syncIfReady(currentUser: teacher);
    expect(stats.downloadedCount, 1);
    expect(stats.uploadedCount, 0);

    final localStudent = await db.findUserByRemoteId(3001);
    expect(localStudent, isNotNull);
    final assignedCourses =
        await db.getAssignedCoursesForStudent(localStudent!.id);
    expect(
        assignedCourses.map((course) => course.id), contains(courseVersionId));
    expect(await db.getSessionsForStudent(localStudent.id), isEmpty);

    await service.materializeTeacherArtifactsForView(
      currentUser: teacher,
      localStudentId: localStudent.id,
      courseVersionId: courseVersionId,
    );
    final sessions = await db.getSessionsForStudent(localStudent.id);
    expect(sessions, hasLength(1));
    expect(sessions.single.sessionTitle, 'Student Session');
  });

  test('downloads batch zip when more than three artifacts are needed',
      () async {
    final teacherId = await db.createUser(
      username: 'teacher',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 901,
    );
    final studentId = await db.createUser(
      username: 'student',
      pinHash: 'hash',
      role: 'student',
      remoteUserId: 3001,
    );
    final courseVersionId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Science',
      granularity: 1,
      textbookText: '',
    );
    await db.upsertCourseRemoteLink(
      courseVersionId: courseVersionId,
      remoteCourseId: 200,
    );
    await db.assignStudent(
      studentId: studentId,
      courseVersionId: courseVersionId,
    );
    final api = _FakeArtifactSyncApiService();
    for (final kp in const <String>['1.1', '1.2', '1.3', '1.4']) {
      await db.into(db.courseNodes).insert(
            CourseNodesCompanion.insert(
              courseVersionId: courseVersionId,
              kpKey: kp,
              title: 'Node $kp',
              description: '',
              orderIndex: int.parse(kp.split('.').last),
            ),
          );
      api.seedServerArtifact(
        await _buildServerArtifact(
          store: artifactStore,
          remoteStudentUserId: 3001,
          remoteCourseId: 200,
          teacherRemoteUserId: 901,
          courseSubject: 'Science',
          kpKey: kp,
          updatedAt: '2026-04-01T08:05:00Z',
          progress: <String, dynamic>{
            'course_id': 200,
            'course_subject': 'Science',
            'kp_key': kp,
            'lit': true,
            'lit_percent': 80,
            'easy_passed_count': 1,
            'medium_passed_count': 0,
            'hard_passed_count': 0,
            'teacher_remote_user_id': 901,
            'student_remote_user_id': 3001,
            'updated_at': '2026-04-01T08:05:00Z',
          },
          sessions: <Map<String, dynamic>>[
            <String, dynamic>{
              'session_sync_id': 'remote-session-$kp',
              'course_id': 200,
              'course_subject': 'Science',
              'kp_key': kp,
              'kp_title': 'Node $kp',
              'session_title': 'Remote Session $kp',
              'started_at': '2026-04-01T08:00:00Z',
              'student_remote_user_id': 3001,
              'student_username': 'student',
              'teacher_remote_user_id': 901,
              'updated_at': '2026-04-01T08:05:00Z',
              'messages': <Map<String, dynamic>>[
                <String, dynamic>{
                  'role': 'assistant',
                  'content': 'server message $kp',
                  'created_at': '2026-04-01T08:00:10Z',
                },
              ],
            },
          ],
        ),
      );
    }

    final service = SessionSyncService(
      db: db,
      api: api,
      artifactStore: artifactStore,
    );
    final student = (await db.getUserById(studentId))!;

    final stats = await service.forcePullFromServer(
      currentUser: student,
      wipeLocalStudentData: true,
    );
    expect(stats.downloadedCount, 4);
    expect(api.downloadBatchCalls, 1);
    expect(api.downloadCalls, 0);
  });

  test('uploads artifact batch when more than three local artifacts changed',
      () async {
    final teacherId = await db.createUser(
      username: 'teacher',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 901,
    );
    final studentId = await db.createUser(
      username: 'student',
      pinHash: 'hash',
      role: 'student',
      remoteUserId: 3001,
    );
    final courseVersionId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Science',
      granularity: 1,
      textbookText: '',
    );
    await db.upsertCourseRemoteLink(
      courseVersionId: courseVersionId,
      remoteCourseId: 200,
    );
    await db.assignStudent(
      studentId: studentId,
      courseVersionId: courseVersionId,
    );

    final seedService = SessionSyncService(
      db: db,
      api: _FakeArtifactSyncApiService(),
      artifactStore: artifactStore,
    );
    await seedService.ensureLocalCutoverInitialized();

    for (final kp in const <String>['1.1', '1.2', '1.3', '1.4']) {
      await db.into(db.courseNodes).insert(
            CourseNodesCompanion.insert(
              courseVersionId: courseVersionId,
              kpKey: kp,
              title: 'Node $kp',
              description: '',
              orderIndex: int.parse(kp.split('.').last),
            ),
          );
      final sessionId = await db.into(db.chatSessions).insert(
            ChatSessionsCompanion.insert(
              studentId: studentId,
              courseVersionId: courseVersionId,
              kpKey: kp,
              title: Value('Local $kp'),
              startedAt: Value(DateTime.parse('2026-04-01T09:00:00Z')),
              syncId: Value('local-session-$kp'),
              syncUpdatedAt: Value(DateTime.parse('2026-04-01T09:05:00Z')),
            ),
          );
      await db.into(db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: sessionId,
              role: 'assistant',
              content: 'local message $kp',
              createdAt: Value(DateTime.parse('2026-04-01T09:00:10Z')),
            ),
          );
      await db.upsertProgressFromSync(
        studentId: studentId,
        courseVersionId: courseVersionId,
        kpKey: kp,
        lit: true,
        litPercent: 60,
        updatedAt: DateTime.parse('2026-04-01T09:12:30Z'),
        mergeWithLocal: false,
      );
    }

    await seedService.handleLocalSyncRelevantChange(
      SyncRelevantChange(localUserIds: <int>{studentId}),
    );

    final api = _FakeArtifactSyncApiService();
    final uploadService = SessionSyncService(
      db: db,
      api: api,
      artifactStore: artifactStore,
    );
    final student = (await db.getUserById(studentId))!;

    final stats = await uploadService.syncIfReady(
      currentUser: student,
      mode: SessionSyncMode.uploadOnly,
    );

    expect(stats.uploadedCount, 4);
    expect(stats.downloadedCount, 0);
    expect(api.uploadBatchCalls, 1);
    expect(api.uploadCalls, 0);
    expect(api.getState1Calls, 1);
    expect(api.downloadCalls, 0);
    expect(api.downloadBatchCalls, 0);
    expect(
      api.uploadedArtifactIds,
      containsAll(const <String>[
        'student_kp:3001:200:1.1',
        'student_kp:3001:200:1.2',
        'student_kp:3001:200:1.3',
        'student_kp:3001:200:1.4',
      ]),
    );
  });

  test('syncNow refreshes latest local student artifacts before final upload',
      () async {
    final teacherId = await db.createUser(
      username: 'teacher',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 901,
    );
    final studentId = await db.createUser(
      username: 'student',
      pinHash: 'hash',
      role: 'student',
      remoteUserId: 3001,
    );
    final courseVersionId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Chemistry',
      granularity: 1,
      textbookText: '',
    );
    await db.upsertCourseRemoteLink(
      courseVersionId: courseVersionId,
      remoteCourseId: 200,
    );
    await db.assignStudent(
      studentId: studentId,
      courseVersionId: courseVersionId,
    );
    await db.into(db.courseNodes).insert(
          CourseNodesCompanion.insert(
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            title: 'Atoms',
            description: '',
            orderIndex: 1,
          ),
        );

    final api = _FakeArtifactSyncApiService();
    final service = SessionSyncService(
      db: db,
      api: api,
      artifactStore: artifactStore,
    );
    await service.ensureLocalCutoverInitialized();

    final sessionId = await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            title: const Value('Unsynced Local Session'),
            startedAt: Value(DateTime.parse('2026-04-10T09:00:00Z')),
            syncId: const Value('local-session-exit'),
            syncUpdatedAt: Value(DateTime.parse('2026-04-10T09:05:00Z')),
          ),
        );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: sessionId,
            role: 'assistant',
            content: 'latest local message',
            createdAt: Value(DateTime.parse('2026-04-10T09:00:10Z')),
          ),
        );
    await db.upsertProgressFromSync(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
      lit: true,
      litPercent: 75,
      updatedAt: DateTime.parse('2026-04-10T09:05:30Z'),
      mergeWithLocal: false,
    );

    final student = (await db.getUserById(studentId))!;
    final stats = await service.syncNow(
      currentUser: student,
      password: 'unused',
      mode: SessionSyncMode.full,
    );

    expect(stats.uploadedCount, 1);
    expect(stats.downloadedCount, 0);
    expect(api.uploadCalls, 1);
    expect(
      api.uploadedArtifactIds,
      equals(<String>['student_kp:3001:200:1.1']),
    );
  });

  test('full sync downloads newer server artifact during periodic sync',
      () async {
    final teacherId = await db.createUser(
      username: 'teacher',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 901,
    );
    final studentId = await db.createUser(
      username: 'student',
      pinHash: 'hash',
      role: 'student',
      remoteUserId: 3001,
    );
    final courseVersionId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Biology',
      granularity: 1,
      textbookText: '',
    );
    await db.upsertCourseRemoteLink(
      courseVersionId: courseVersionId,
      remoteCourseId: 200,
    );
    await db.assignStudent(
      studentId: studentId,
      courseVersionId: courseVersionId,
    );
    await db.into(db.courseNodes).insert(
          CourseNodesCompanion.insert(
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            title: 'Cells',
            description: '',
            orderIndex: 1,
          ),
        );

    final api = _FakeArtifactSyncApiService();
    api.seedServerArtifact(
      await _buildServerArtifact(
        store: artifactStore,
        remoteStudentUserId: 3001,
        remoteCourseId: 200,
        teacherRemoteUserId: 901,
        courseSubject: 'Biology',
        kpKey: '1.1',
        updatedAt: '2026-04-10T08:05:00Z',
        progress: <String, dynamic>{
          'course_id': 200,
          'course_subject': 'Biology',
          'kp_key': '1.1',
          'lit': true,
          'lit_percent': 60,
          'easy_passed_count': 0,
          'medium_passed_count': 0,
          'hard_passed_count': 0,
          'teacher_remote_user_id': 901,
          'student_remote_user_id': 3001,
          'updated_at': '2026-04-10T08:05:00Z',
        },
        sessions: <Map<String, dynamic>>[
          <String, dynamic>{
            'session_sync_id': 'remote-session-1',
            'course_id': 200,
            'course_subject': 'Biology',
            'kp_key': '1.1',
            'kp_title': 'Cells',
            'session_title': 'Remote Session',
            'started_at': '2026-04-10T08:00:00Z',
            'student_remote_user_id': 3001,
            'student_username': 'student',
            'teacher_remote_user_id': 901,
            'updated_at': '2026-04-10T08:05:00Z',
            'messages': <Map<String, dynamic>>[
              <String, dynamic>{
                'role': 'assistant',
                'content': 'server v1',
                'created_at': '2026-04-10T08:00:10Z',
              },
            ],
          },
        ],
      ),
    );

    final service = SessionSyncService(
      db: db,
      api: api,
      artifactStore: artifactStore,
    );
    final student = (await db.getUserById(studentId))!;
    await service.forcePullFromServer(
      currentUser: student,
      wipeLocalStudentData: true,
      mode: SessionSyncMode.downloadOnly,
    );

    api.seedServerArtifact(
      await _buildServerArtifact(
        store: artifactStore,
        remoteStudentUserId: 3001,
        remoteCourseId: 200,
        teacherRemoteUserId: 901,
        courseSubject: 'Biology',
        kpKey: '1.1',
        updatedAt: '2026-04-10T09:05:00Z',
        progress: <String, dynamic>{
          'course_id': 200,
          'course_subject': 'Biology',
          'kp_key': '1.1',
          'lit': true,
          'lit_percent': 90,
          'easy_passed_count': 1,
          'medium_passed_count': 0,
          'hard_passed_count': 0,
          'teacher_remote_user_id': 901,
          'student_remote_user_id': 3001,
          'updated_at': '2026-04-10T09:05:00Z',
        },
        sessions: <Map<String, dynamic>>[
          <String, dynamic>{
            'session_sync_id': 'remote-session-1',
            'course_id': 200,
            'course_subject': 'Biology',
            'kp_key': '1.1',
            'kp_title': 'Cells',
            'session_title': 'Remote Session Updated',
            'started_at': '2026-04-10T08:00:00Z',
            'student_remote_user_id': 3001,
            'student_username': 'student',
            'teacher_remote_user_id': 901,
            'updated_at': '2026-04-10T09:05:00Z',
            'messages': <Map<String, dynamic>>[
              <String, dynamic>{
                'role': 'assistant',
                'content': 'server v2',
                'created_at': '2026-04-10T09:00:10Z',
              },
            ],
          },
        ],
      ),
    );

    final stats = await service.syncIfReady(
      currentUser: student,
      mode: SessionSyncMode.full,
    );

    expect(stats.downloadedCount, 1);
    expect(stats.uploadedCount, 0);
    expect(api.downloadCalls + api.downloadBatchCalls, greaterThan(0));
  });

  test(
      'teacher batch sync downloads artifact bytes once and materialize stays local',
      () async {
    final teacherId = await db.createUser(
      username: 'teacher',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 901,
    );
    final courseVersionId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Science',
      granularity: 1,
      textbookText: '',
    );
    await db.upsertCourseRemoteLink(
      courseVersionId: courseVersionId,
      remoteCourseId: 200,
    );
    final api = _FakeArtifactSyncApiService();
    for (final kp in const <String>['1.1', '1.2', '1.3', '1.4']) {
      await db.into(db.courseNodes).insert(
            CourseNodesCompanion.insert(
              courseVersionId: courseVersionId,
              kpKey: kp,
              title: 'Node $kp',
              description: '',
              orderIndex: int.parse(kp.split('.').last),
            ),
          );
      api.seedServerArtifact(
        await _buildServerArtifact(
          store: artifactStore,
          remoteStudentUserId: 3001,
          remoteCourseId: 200,
          teacherRemoteUserId: 901,
          courseSubject: 'Science',
          kpKey: kp,
          updatedAt: '2026-04-01T08:05:00Z',
          progress: <String, dynamic>{
            'course_id': 200,
            'course_subject': 'Science',
            'kp_key': kp,
            'lit': true,
            'lit_percent': 80,
            'easy_passed_count': 1,
            'medium_passed_count': 0,
            'hard_passed_count': 0,
            'teacher_remote_user_id': 901,
            'student_remote_user_id': 3001,
            'updated_at': '2026-04-01T08:05:00Z',
          },
          sessions: <Map<String, dynamic>>[
            <String, dynamic>{
              'session_sync_id': 'remote-session-$kp',
              'course_id': 200,
              'course_subject': 'Science',
              'kp_key': kp,
              'kp_title': 'Node $kp',
              'session_title': 'Remote Session $kp',
              'started_at': '2026-04-01T08:00:00Z',
              'student_remote_user_id': 3001,
              'student_username': 'student',
              'teacher_remote_user_id': 901,
              'updated_at': '2026-04-01T08:05:00Z',
              'messages': <Map<String, dynamic>>[
                <String, dynamic>{
                  'role': 'assistant',
                  'content': 'server message $kp',
                  'created_at': '2026-04-01T08:00:10Z',
                },
              ],
            },
          ],
        ),
      );
    }

    final service = SessionSyncService(
      db: db,
      api: api,
      artifactStore: artifactStore,
    );
    final teacher = (await db.getUserById(teacherId))!;

    final stats = await service.syncIfReady(currentUser: teacher);
    expect(stats.downloadedCount, 4);
    expect(api.downloadBatchCalls, 1);
    expect(api.downloadCalls, 0);

    final localStudent = await db.findUserByRemoteId(3001);
    expect(localStudent, isNotNull);
    expect(await db.getSessionsForStudent(localStudent!.id), isEmpty);

    await service.materializeTeacherArtifactsForView(
      currentUser: teacher,
      localStudentId: localStudent.id,
      courseVersionId: courseVersionId,
    );

    expect(api.downloadBatchCalls, 1);
    final sessions = await db.getSessionsForStudent(localStudent.id);
    expect(sessions, hasLength(4));
  });

  test(
      'batch downloads checkpoint manifest instead of rewriting it per artifact',
      () async {
    final teacherId = await db.createUser(
      username: 'teacher',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 901,
    );
    final studentId = await db.createUser(
      username: 'student',
      pinHash: 'hash',
      role: 'student',
      remoteUserId: 3001,
    );
    final courseVersionId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Science',
      granularity: 1,
      textbookText: '',
    );
    await db.upsertCourseRemoteLink(
      courseVersionId: courseVersionId,
      remoteCourseId: 200,
    );
    await db.assignStudent(
      studentId: studentId,
      courseVersionId: courseVersionId,
    );
    final countingStore = _CountingArtifactStoreService(
      rootDirectoryProvider: () async => artifactRoot,
    );
    final api = _FakeArtifactSyncApiService();
    for (final kp in const <String>['1.1', '1.2', '1.3', '1.4']) {
      await db.into(db.courseNodes).insert(
            CourseNodesCompanion.insert(
              courseVersionId: courseVersionId,
              kpKey: kp,
              title: 'Node $kp',
              description: '',
              orderIndex: int.parse(kp.split('.').last),
            ),
          );
      api.seedServerArtifact(
        await _buildServerArtifact(
          store: artifactStore,
          remoteStudentUserId: 3001,
          remoteCourseId: 200,
          teacherRemoteUserId: 901,
          courseSubject: 'Science',
          kpKey: kp,
          updatedAt: '2026-04-01T08:05:00Z',
          progress: <String, dynamic>{
            'course_id': 200,
            'course_subject': 'Science',
            'kp_key': kp,
            'lit': true,
            'lit_percent': 80,
            'easy_passed_count': 1,
            'medium_passed_count': 0,
            'hard_passed_count': 0,
            'teacher_remote_user_id': 901,
            'student_remote_user_id': 3001,
            'updated_at': '2026-04-01T08:05:00Z',
          },
          sessions: <Map<String, dynamic>>[
            <String, dynamic>{
              'session_sync_id': 'remote-session-$kp',
              'course_id': 200,
              'course_subject': 'Science',
              'kp_key': kp,
              'kp_title': 'Node $kp',
              'session_title': 'Remote Session $kp',
              'started_at': '2026-04-01T08:00:00Z',
              'student_remote_user_id': 3001,
              'student_username': 'student',
              'teacher_remote_user_id': 901,
              'updated_at': '2026-04-01T08:05:00Z',
              'messages': <Map<String, dynamic>>[
                <String, dynamic>{
                  'role': 'assistant',
                  'content': 'server message $kp',
                  'created_at': '2026-04-01T08:00:10Z',
                },
              ],
            },
          ],
        ),
      );
    }

    final service = SessionSyncService(
      db: db,
      api: api,
      artifactStore: countingStore,
    );
    final student = (await db.getUserById(studentId))!;

    await service.forcePullFromServer(
      currentUser: student,
      wipeLocalStudentData: true,
    );

    expect(countingStore.saveManifestCalls, 2);
    final manifest = await countingStore.loadManifest(3001);
    expect(
      manifest.items.values.every((item) => item.storageFile.trim().isNotEmpty),
      isTrue,
    );
    final artifactsDir =
        Directory(p.join(artifactRoot.path, '3001', 'artifacts'));
    final artifactFiles = artifactsDir.existsSync()
        ? artifactsDir
            .listSync(followLinks: false)
            .whereType<File>()
            .toList(growable: false)
        : const <File>[];
    expect(artifactFiles, isNotEmpty);
  });
}
