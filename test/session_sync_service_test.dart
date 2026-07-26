import 'dart:async';
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
  int deleteCalls = 0;
  int getState1Calls = 0;
  int getState2Calls = 0;
  Completer<void>? _blockNextGetState2Started;
  Completer<void>? _blockNextGetState2Release;
  final List<String> uploadedArtifactIds = <String>[];
  final List<bool> uploadedOverwriteServerFlags = <bool>[];
  final List<String> deletedArtifactIds = <String>[];
  final List<bool> deletedOverwriteServerFlags = <bool>[];
  int teacherSessionDeleteCalls = 0;
  final List<String> teacherDeletedArtifactIds = <String>[];
  final List<String> teacherDeletedSessionSyncIds = <String>[];
  final List<String> teacherDeleteBaseSha256Values = <String>[];
  Object? teacherSessionDeleteError;
  bool teacherSessionDeleteThrowsAfterMutation = false;
  Object? downloadArtifactError;
  int? uploadBatchFailAfterCommittedItems;
  Object? uploadBatchFailure;
  Object? uploadArtifactError;

  void seedServerArtifact(_ServerArtifact artifact) {
    _items[artifact.item.artifactId] = artifact.item;
    _bytesByArtifactId[artifact.item.artifactId] =
        Uint8List.fromList(artifact.bytes);
  }

  void removeServerArtifact(String artifactId) {
    _items.remove(artifactId);
    _bytesByArtifactId.remove(artifactId);
  }

  void blockNextGetState2() {
    _blockNextGetState2Started = Completer<void>();
    _blockNextGetState2Release = Completer<void>();
  }

  Future<void> waitForBlockedGetState2() {
    final started = _blockNextGetState2Started;
    if (started == null) {
      throw StateError('No blocked getState2 call is configured.');
    }
    return started.future;
  }

  void releaseBlockedGetState2() {
    final release = _blockNextGetState2Release;
    if (release == null) {
      throw StateError('No blocked getState2 call is configured.');
    }
    _blockNextGetState2Release = null;
    release.complete();
  }

  @override
  Future<String> getState2({String? artifactClass}) async {
    getState2Calls++;
    final started = _blockNextGetState2Started;
    final release = _blockNextGetState2Release;
    if (started != null && release != null) {
      _blockNextGetState2Started = null;
      started.complete();
      await release.future;
      if (identical(_blockNextGetState2Release, release)) {
        _blockNextGetState2Release = null;
      }
    }
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
    final error = downloadArtifactError;
    if (error != null) {
      throw error;
    }
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
    final error = downloadArtifactError;
    if (error != null) {
      throw error;
    }
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
      if (current != null &&
          current.sha256.trim() != normalizedBase &&
          current.sha256.trim() != sha256.trim()) {
        throw ArtifactConflictException(
          message: 'Artifact conflict: server_changed',
          serverSha256: current.sha256,
          expectedBaseSha256: normalizedBase,
        );
      }
    }
    final uploadError = uploadArtifactError;
    if (uploadError != null) {
      throw uploadError;
    }
    final result = _storeUploadedArtifact(
      artifactId: artifactId,
      sha256: sha256,
      bytes: bytes,
    );
    uploadCalls++;
    uploadedArtifactIds.add(artifactId);
    uploadedOverwriteServerFlags.add(overwriteServer);
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
        if (current != null &&
            current.sha256.trim() != normalizedBase &&
            current.sha256.trim() != upload.sha256.trim()) {
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
      uploadedOverwriteServerFlags.add(upload.overwriteServer);
      final failAfter = uploadBatchFailAfterCommittedItems;
      if (failAfter != null &&
          uploadedArtifactIds.length >= failAfter &&
          uploadBatchFailure != null) {
        throw uploadBatchFailure!;
      }
    }
  }

  @override
  Future<void> deleteArtifact({
    required String artifactId,
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
    _items.remove(artifactId);
    _bytesByArtifactId.remove(artifactId);
    deleteCalls++;
    deletedArtifactIds.add(artifactId);
    deletedOverwriteServerFlags.add(overwriteServer);
  }

  @override
  Future<void> deleteStudentSessionAsTeacher({
    required String artifactId,
    required String sessionSyncId,
    required String baseSha256,
  }) async {
    teacherSessionDeleteCalls++;
    teacherDeletedArtifactIds.add(artifactId);
    teacherDeletedSessionSyncIds.add(sessionSyncId);
    teacherDeleteBaseSha256Values.add(baseSha256);
    final error = teacherSessionDeleteError;
    if (error != null && !teacherSessionDeleteThrowsAfterMutation) {
      throw error;
    }
    final currentItem = _items[artifactId];
    final currentBytes = _bytesByArtifactId[artifactId];
    if (currentItem == null || currentBytes == null) {
      throw StateError('Missing server artifact $artifactId.');
    }
    if (currentItem.sha256 != baseSha256.trim()) {
      throw ArtifactConflictException(
        message: 'Artifact conflict: server_changed',
        serverSha256: currentItem.sha256,
        expectedBaseSha256: baseSha256.trim(),
      );
    }
    final payload = _zipStore.readPayload(currentBytes);
    final rawSessions = payload['sessions'];
    if (rawSessions is! List) {
      throw StateError('Server artifact sessions are invalid.');
    }
    var found = false;
    final remainingSessions = <dynamic>[];
    for (final rawSession in rawSessions) {
      if (rawSession is! Map<String, dynamic>) {
        throw StateError('Server artifact session is invalid.');
      }
      if ((rawSession['session_sync_id'] as String?)?.trim() ==
          sessionSyncId.trim()) {
        found = true;
      } else {
        remainingSessions.add(rawSession);
      }
    }
    if (!found) {
      throw StateError('Missing server session $sessionSyncId.');
    }
    payload
      ..remove('progress')
      ..['sessions'] = remainingSessions
      ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
    final mistakes = payload['mistakes'];
    final hasMistakes = mistakes is List && mistakes.isNotEmpty;
    if (remainingSessions.isEmpty && !hasMistakes) {
      _items.remove(artifactId);
      _bytesByArtifactId.remove(artifactId);
      return;
    }
    final build = _zipStore.buildArtifact(
      LocalArtifactBuildInput(
        artifactId: artifactId,
        lastModified: DateTime.now().toUtc(),
        payload: payload,
      ),
    );
    _items[artifactId] = ArtifactState1Item(
      artifactId: artifactId,
      artifactClass: 'student_kp',
      courseId: currentItem.courseId,
      teacherUserId: currentItem.teacherUserId,
      studentUserId: currentItem.studentUserId,
      kpKey: currentItem.kpKey,
      bundleVersionId: 0,
      sha256: build.sha256,
      lastModified: build.lastModified,
    );
    _bytesByArtifactId[artifactId] = Uint8List.fromList(build.bytes);
    if (error != null && teacherSessionDeleteThrowsAfterMutation) {
      throw error;
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
  List<Map<String, dynamic>>? mistakes,
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
        if (mistakes != null) 'mistakes': mistakes,
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

class _StudentMissingArtifactFixture {
  const _StudentMissingArtifactFixture({
    required this.service,
    required this.api,
    required this.student,
    required this.studentId,
    required this.courseVersionId,
    required this.artifactId,
  });

  final SessionSyncService service;
  final _FakeArtifactSyncApiService api;
  final User student;
  final int studentId;
  final int courseVersionId;
  final String artifactId;
}

Future<_StudentMissingArtifactFixture> _createStudentMissingArtifactFixture({
  required AppDatabase db,
  required StudentKpArtifactStoreService artifactStore,
}) async {
  final teacherId = await db.createUser(
    username: 'teacher_missing',
    pinHash: 'hash',
    role: 'teacher',
    remoteUserId: 901,
  );
  final studentId = await db.createUser(
    username: 'student_missing',
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
  final artifact = await _buildServerArtifact(
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
      'easy_passed_count': 1,
      'medium_passed_count': 0,
      'hard_passed_count': 0,
      'teacher_remote_user_id': 901,
      'student_remote_user_id': 3001,
      'updated_at': '2026-04-01T08:05:00Z',
    },
    sessions: <Map<String, dynamic>>[
      <String, dynamic>{
        'session_sync_id': 'remote-session-missing',
        'course_id': 200,
        'course_subject': 'Biology',
        'kp_key': '1.1',
        'kp_title': 'Cells',
        'session_title': 'Remote Session',
        'started_at': '2026-04-01T08:00:00Z',
        'student_remote_user_id': 3001,
        'student_username': 'student_missing',
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
  );
  api.seedServerArtifact(artifact);
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
  return _StudentMissingArtifactFixture(
    service: service,
    api: api,
    student: student,
    studentId: studentId,
    courseVersionId: courseVersionId,
    artifactId: artifact.item.artifactId,
  );
}

class _TeacherSessionDeleteFixture {
  const _TeacherSessionDeleteFixture({
    required this.service,
    required this.teacher,
    required this.localStudentId,
    required this.courseVersionId,
    required this.targetSessionId,
    required this.siblingSessionId,
    required this.artifactId,
    required this.baseSha256,
  });

  final SessionSyncService service;
  final User teacher;
  final int localStudentId;
  final int courseVersionId;
  final int targetSessionId;
  final int siblingSessionId;
  final String artifactId;
  final String baseSha256;
}

Future<_TeacherSessionDeleteFixture> _createTeacherSessionDeleteFixture({
  required AppDatabase db,
  required StudentKpArtifactStoreService artifactStore,
  required _FakeArtifactSyncApiService api,
}) async {
  final teacherId = await db.createUser(
    username: 'teacher_delete',
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
  final serverArtifact = await _buildServerArtifact(
    store: artifactStore,
    remoteStudentUserId: 3001,
    remoteCourseId: 200,
    teacherRemoteUserId: 901,
    courseSubject: 'History',
    kpKey: '2.1',
    updatedAt: '2026-04-01T10:10:00Z',
    progress: <String, dynamic>{
      'course_id': 200,
      'course_subject': 'History',
      'kp_key': '2.1',
      'lit': true,
      'lit_percent': 100,
      'easy_passed_count': 1,
      'medium_passed_count': 1,
      'hard_passed_count': 1,
      'teacher_remote_user_id': 901,
      'student_remote_user_id': 3001,
      'updated_at': '2026-04-01T10:10:00Z',
    },
    mistakes: <Map<String, dynamic>>[
      <String, dynamic>{
        'mistake_tag': 'date confusion',
        'mistake_tag_key': 'date confusion',
        'mistake_note': 'Mixed up two dates.',
        'evidence_json': '{"source":"server"}',
        'occurrences': 2,
        'first_seen_at': '2026-04-01T10:01:00Z',
        'last_seen_at': '2026-04-01T10:09:00Z',
      },
    ],
    sessions: <Map<String, dynamic>>[
      <String, dynamic>{
        'session_sync_id': 'target-session',
        'course_id': 200,
        'course_subject': 'History',
        'kp_key': '2.1',
        'kp_title': 'Ancient Rome',
        'session_title': 'Delete Me',
        'started_at': '2026-04-01T10:00:00Z',
        'student_remote_user_id': 3001,
        'student_username': 'albert',
        'teacher_remote_user_id': 901,
        'updated_at': '2026-04-01T10:05:00Z',
        'messages': <Map<String, dynamic>>[
          <String, dynamic>{
            'role': 'assistant',
            'content': 'target message',
            'created_at': '2026-04-01T10:00:10Z',
          },
        ],
      },
      <String, dynamic>{
        'session_sync_id': 'sibling-session',
        'course_id': 200,
        'course_subject': 'History',
        'kp_key': '2.1',
        'kp_title': 'Ancient Rome',
        'session_title': 'Keep Me',
        'started_at': '2026-04-01T10:06:00Z',
        'student_remote_user_id': 3001,
        'student_username': 'albert',
        'teacher_remote_user_id': 901,
        'updated_at': '2026-04-01T10:10:00Z',
        'messages': <Map<String, dynamic>>[
          <String, dynamic>{
            'role': 'assistant',
            'content': 'sibling message',
            'created_at': '2026-04-01T10:06:10Z',
          },
        ],
      },
    ],
  );
  api.seedServerArtifact(serverArtifact);
  final service = SessionSyncService(
    db: db,
    api: api,
    artifactStore: artifactStore,
  );
  final teacher = (await db.getUserById(teacherId))!;
  await service.syncIfReady(currentUser: teacher);
  final localStudent = await db.findUserByRemoteId(3001);
  if (localStudent == null) {
    throw StateError('Teacher sync did not create the local student.');
  }
  await service.materializeTeacherArtifactsForView(
    currentUser: teacher,
    localStudentId: localStudent.id,
    courseVersionId: courseVersionId,
  );
  final sessions = await db.getSessionsForNode(
    studentId: localStudent.id,
    courseVersionId: courseVersionId,
    kpKey: '2.1',
  );
  final target = sessions.singleWhere(
    (session) => session.syncId == 'target-session',
  );
  final sibling = sessions.singleWhere(
    (session) => session.syncId == 'sibling-session',
  );
  const artifactId = 'student_kp:3001:200:2.1';
  final manifest = await artifactStore.loadManifest(901);
  final manifestItem = manifest.items[artifactId];
  if (manifestItem == null) {
    throw StateError('Teacher manifest item missing.');
  }
  await artifactStore.saveManifest(
    StudentKpArtifactManifest.empty(3001).copyWith(
      items: <String, StudentKpArtifactManifestItem>{
        artifactId: manifestItem.copyWith(storageFile: ''),
      },
    ),
  );
  return _TeacherSessionDeleteFixture(
    service: service,
    teacher: teacher,
    localStudentId: localStudent.id,
    courseVersionId: courseVersionId,
    targetSessionId: target.id,
    siblingSessionId: sibling.id,
    artifactId: artifactId,
    baseSha256: manifestItem.baseSha256,
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
        mistakes: <Map<String, dynamic>>[
          <String, dynamic>{
            'mistake_tag': 'sign error',
            'mistake_tag_key': 'sign error',
            'mistake_note': 'Missed the negative sign.',
            'question_excerpt': 'Solve -2x = 4',
            'difficulty': 'easy',
            'evidence_json': '{"ok":true}',
            'occurrences': 2,
            'first_seen_at': '2026-04-01T08:01:00Z',
            'last_seen_at': '2026-04-01T08:04:00Z',
          },
        ],
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
    final mistakes = await db.getMistakeEntriesForScope(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
    );
    expect(mistakes, hasLength(1));
    expect(mistakes.single.mistakeTagRaw, 'sign error');
    expect(mistakes.single.occurrences, 2);

    final manifestBeforeRetryRecovery = await artifactStore.loadManifest(3001);
    final artifactId = manifestBeforeRetryRecovery.items.keys.single;
    final itemBeforeRetryRecovery =
        manifestBeforeRetryRecovery.items[artifactId]!;
    await artifactStore.saveManifest(
      manifestBeforeRetryRecovery.copyWith(
        items: <String, StudentKpArtifactManifestItem>{
          artifactId: itemBeforeRetryRecovery.copyWith(
            baseSha256: 'stale-base-before-committed-upload',
          ),
        },
      ),
    );
    final state1CallsBeforeRetryRecovery = api.getState1Calls;
    final secondStats = await service.syncIfReady(currentUser: student);
    expect(secondStats.downloadedCount, 0);
    expect(secondStats.uploadedCount, 0);
    expect(api.downloadCalls, 1);
    expect(api.uploadCalls, 0);
    expect(api.getState1Calls, state1CallsBeforeRetryRecovery + 2);
    final manifestAfterRetryRecovery = await artifactStore.loadManifest(3001);
    expect(
      manifestAfterRetryRecovery.items[artifactId]!.baseSha256,
      itemBeforeRetryRecovery.sha256,
    );
    expect(
      await service.hasPendingCanonicalManifestChanges(currentUser: student),
      isFalse,
    );

    await artifactStore.saveManifest(
      manifestAfterRetryRecovery.copyWith(
        items: <String, StudentKpArtifactManifestItem>{
          artifactId: manifestAfterRetryRecovery.items[artifactId]!.copyWith(
            baseSha256: 'stale-base-before-login-recovery',
          ),
        },
      ),
    );
    expect(
      await service.hasPendingCanonicalManifestChanges(currentUser: student),
      isTrue,
    );
    final canonicalState1 = await api.getState1(
      artifactClass: 'student_kp',
    );
    final canonicalStats = await service.syncFromCanonicalState1(
      currentUser: student,
      visibleItems: canonicalState1.items,
      mode: SessionSyncMode.downloadOnly,
    );
    expect(canonicalStats.downloadedCount, 0);
    expect(canonicalStats.uploadedCount, 0);
    final manifestAfterLoginRecovery = await artifactStore.loadManifest(3001);
    expect(
      manifestAfterLoginRecovery.items[artifactId]!.baseSha256,
      itemBeforeRetryRecovery.sha256,
    );

    await db.setMistakeEntryStatus(
      id: mistakes.single.id,
      status: 'dismissed',
      dismissed: true,
    );
    api.seedServerArtifact(
      await _buildServerArtifact(
        store: artifactStore,
        remoteStudentUserId: 3001,
        remoteCourseId: 200,
        teacherRemoteUserId: 901,
        courseSubject: 'Biology',
        kpKey: '1.1',
        updatedAt: '2026-04-01T09:05:00Z',
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
          'updated_at': '2026-04-01T09:05:00Z',
        },
        mistakes: <Map<String, dynamic>>[
          <String, dynamic>{
            'mistake_tag': 'sign error',
            'mistake_tag_key': 'sign error',
            'mistake_note': 'Server updated note.',
            'question_excerpt': 'Solve -2x = 4',
            'difficulty': 'easy',
            'evidence_json': '{"ok":true,"updated":true}',
            'occurrences': 3,
            'first_seen_at': '2026-04-01T08:01:00Z',
            'last_seen_at': '2026-04-01T09:04:00Z',
          },
        ],
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
            'updated_at': '2026-04-01T09:05:00Z',
            'messages': <Map<String, dynamic>>[
              <String, dynamic>{
                'role': 'assistant',
                'content': 'server message updated',
                'created_at': '2026-04-01T09:00:10Z',
              },
            ],
          },
        ],
      ),
    );
    final thirdStats = await service.syncIfReady(currentUser: student);
    expect(thirdStats.downloadedCount, 1);
    final replacedMistakes = await db.getMistakeEntriesForScope(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
    );
    expect(replacedMistakes.single.dismissed, isTrue);
    expect(replacedMistakes.single.status, 'dismissed');
    expect(replacedMistakes.single.occurrences, 3);
  });

  test('canonical download removes a clean student artifact missing on server',
      () async {
    final fixture = await _createStudentMissingArtifactFixture(
      db: db,
      artifactStore: artifactStore,
    );
    final manifestBeforeDelete = await artifactStore.loadManifest(3001);
    final cachedItem = manifestBeforeDelete.items[fixture.artifactId]!;
    expect(await db.getSessionsForStudent(fixture.studentId), hasLength(1));
    expect(
      await db.getProgress(
        studentId: fixture.studentId,
        courseVersionId: fixture.courseVersionId,
        kpKey: '1.1',
      ),
      isNotNull,
    );
    expect(
      await artifactStore.readArtifactBytes(
        remoteUserId: 3001,
        item: cachedItem,
      ),
      isNotNull,
    );

    fixture.api.removeServerArtifact(fixture.artifactId);
    final state1 = await fixture.api.getState1(
      artifactClass: 'student_kp',
    );
    final stats = await fixture.service.syncFromCanonicalState1(
      currentUser: fixture.student,
      visibleItems: state1.items,
      mode: SessionSyncMode.downloadOnly,
    );

    expect(stats.downloadedCount, 0);
    expect(stats.uploadedCount, 0);
    expect(await db.getSessionsForStudent(fixture.studentId), isEmpty);
    expect(
      await db.getProgress(
        studentId: fixture.studentId,
        courseVersionId: fixture.courseVersionId,
        kpKey: '1.1',
      ),
      isNull,
    );
    expect(
      (await artifactStore.loadManifest(3001)).items,
      isNot(contains(fixture.artifactId)),
    );
    expect(
      await artifactStore.readArtifactBytes(
        remoteUserId: 3001,
        item: cachedItem,
      ),
      isNull,
    );
  });

  test('full sync accepts a clean student artifact deleted on server', () async {
    final fixture = await _createStudentMissingArtifactFixture(
      db: db,
      artifactStore: artifactStore,
    );
    fixture.api.removeServerArtifact(fixture.artifactId);

    final stats = await fixture.service.syncIfReady(
      currentUser: fixture.student,
      mode: SessionSyncMode.full,
    );

    expect(stats.downloadedCount, 0);
    expect(stats.uploadedCount, 0);
    expect(fixture.api.uploadCalls, 0);
    expect(await db.getSessionsForStudent(fixture.studentId), isEmpty);
    expect(
      await db.getProgress(
        studentId: fixture.studentId,
        courseVersionId: fixture.courseVersionId,
        kpKey: '1.1',
      ),
      isNull,
    );
    expect((await artifactStore.loadManifest(3001)).items, isEmpty);
  });

  test('download preserves divergent and new student artifacts missing on server',
      () async {
    final fixture = await _createStudentMissingArtifactFixture(
      db: db,
      artifactStore: artifactStore,
    );
    final existingSession =
        (await db.getSessionsForStudent(fixture.studentId)).single;
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: existingSession.sessionId,
            role: 'student',
            content: 'locally divergent answer',
            createdAt: Value(DateTime.parse('2026-04-01T08:06:00Z')),
          ),
        );
    await db.into(db.courseNodes).insert(
          CourseNodesCompanion.insert(
            courseVersionId: fixture.courseVersionId,
            kpKey: '1.2',
            title: 'Cell division',
            description: '',
            orderIndex: 2,
          ),
        );
    final newSessionId = await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            studentId: fixture.studentId,
            courseVersionId: fixture.courseVersionId,
            kpKey: '1.2',
            title: const Value('New Local Session'),
            startedAt: Value(DateTime.parse('2026-04-01T09:00:00Z')),
            syncId: const Value('local-new-session'),
            syncUpdatedAt: Value(DateTime.parse('2026-04-01T09:05:00Z')),
          ),
        );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: newSessionId,
            role: 'assistant',
            content: 'new local message',
            createdAt: Value(DateTime.parse('2026-04-01T09:00:10Z')),
          ),
        );
    await fixture.service.handleLocalSyncRelevantChange(
      SyncRelevantChange(localUserIds: <int>{fixture.studentId}),
    );

    const newArtifactId = 'student_kp:3001:200:1.2';
    final divergentManifest = await artifactStore.loadManifest(3001);
    final divergentItem = divergentManifest.items[fixture.artifactId]!;
    final newItem = divergentManifest.items[newArtifactId]!;
    expect(divergentItem.sha256, isNot(divergentItem.baseSha256));
    expect(divergentItem.baseSha256, isNotEmpty);
    expect(newItem.baseSha256, isEmpty);

    fixture.api.removeServerArtifact(fixture.artifactId);
    final state1 = await fixture.api.getState1(
      artifactClass: 'student_kp',
    );
    await fixture.service.syncFromCanonicalState1(
      currentUser: fixture.student,
      visibleItems: state1.items,
      mode: SessionSyncMode.downloadOnly,
    );

    final preservedManifest = await artifactStore.loadManifest(3001);
    expect(preservedManifest.items, contains(fixture.artifactId));
    expect(preservedManifest.items, contains(newArtifactId));
    expect(await db.getSessionsForStudent(fixture.studentId), hasLength(2));
    expect(
      await db.getProgress(
        studentId: fixture.studentId,
        courseVersionId: fixture.courseVersionId,
        kpKey: '1.1',
      ),
      isNotNull,
    );
    expect(
      (await db.getMessagesForSession(existingSession.sessionId))
          .map((message) => message.content),
      contains('locally divergent answer'),
    );
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
    final firstMessageId = await db.into(db.chatMessages).insert(
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
    await db.upsertMistakeEvidence(
      studentId: studentId,
      courseVersionId: courseVersionId,
      kpKey: '1.1',
      sessionId: firstSessionId,
      messageId: firstMessageId,
      mistakeTag: 'denominator mismatch',
      mistakeNote: 'Mixed unlike denominators.',
      questionExcerpt: '1/2 + 1/3',
      difficulty: 'medium',
      evidenceJson: '{"source":"test"}',
      seenAt: DateTime.parse('2026-04-01T09:13:00Z'),
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
    final mistakes = payload['mistakes'] as List<dynamic>;
    expect(mistakes, hasLength(1));
    final mistake = mistakes.single as Map<String, dynamic>;
    expect(mistake['mistake_tag'], 'denominator mismatch');
    expect(mistake.containsKey('next_review_at'), isFalse);
    expect(mistake.containsKey('dismissed'), isFalse);

    final secondStats = await uploadService.syncIfReady(
      currentUser: student,
      mode: SessionSyncMode.uploadOnly,
    );
    expect(secondStats.uploadedCount, 0);
    expect(api.uploadCalls, 1);
  });

  test('force push local overwrites changed server artifact', () async {
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
        studentId: studentId, courseVersionId: courseVersionId);
    await db.into(db.courseNodes).insert(
          CourseNodesCompanion.insert(
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            title: 'Motion',
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
            title: const Value('Local'),
            startedAt: Value(DateTime.parse('2026-04-01T09:00:00Z')),
            syncId: const Value('local-session'),
            syncUpdatedAt: Value(DateTime.parse('2026-04-01T09:05:00Z')),
          ),
        );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: sessionId,
            role: 'assistant',
            content: 'local base',
            createdAt: Value(DateTime.parse('2026-04-01T09:00:10Z')),
          ),
        );

    final student = (await db.getUserById(studentId))!;
    await service.handleLocalSyncRelevantChange(
      SyncRelevantChange(localUserIds: <int>{studentId}),
    );
    await service.syncIfReady(
      currentUser: student,
      mode: SessionSyncMode.uploadOnly,
    );

    api.seedServerArtifact(
      await _buildServerArtifact(
        store: artifactStore,
        remoteStudentUserId: 3001,
        remoteCourseId: 200,
        teacherRemoteUserId: 901,
        courseSubject: 'Physics',
        kpKey: '1.1',
        updatedAt: '2026-04-01T09:10:00Z',
        sessions: <Map<String, dynamic>>[
          <String, dynamic>{
            'session_sync_id': 'remote-session',
            'course_id': 200,
            'kp_key': '1.1',
            'started_at': '2026-04-01T09:00:00Z',
            'student_remote_user_id': 3001,
            'teacher_remote_user_id': 901,
            'updated_at': '2026-04-01T09:10:00Z',
            'messages': <Map<String, dynamic>>[
              <String, dynamic>{
                'role': 'assistant',
                'content': 'server changed',
                'created_at': '2026-04-01T09:00:10Z',
              },
            ],
          },
        ],
      ),
    );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: sessionId,
            role: 'assistant',
            content: 'local wins',
            createdAt: Value(DateTime.parse('2026-04-01T09:06:10Z')),
          ),
        );
    await service.handleLocalSyncRelevantChange(
      SyncRelevantChange(localUserIds: <int>{studentId}),
    );

    final stats = await service.forcePushLocalToServer(currentUser: student);

    expect(stats.uploadedCount, 1);
    expect(api.uploadedArtifactIds.last, 'student_kp:3001:200:1.1');
    expect(api.uploadedOverwriteServerFlags.last, isTrue);
    final uploaded = await api.downloadArtifact('student_kp:3001:200:1.1');
    final payload = artifactStore.readPayload(uploaded.bytes);
    final sessions = payload['sessions'] as List<dynamic>;
    final messages =
        (sessions.single as Map<String, dynamic>)['messages'] as List<dynamic>;
    expect(
      messages.map((message) => message['content']).toList(),
      contains('local wins'),
    );
  });

  test('force push local deletes server artifact removed on this device',
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
    await db.assignStudent(
        studentId: studentId, courseVersionId: courseVersionId);
    await db.into(db.courseNodes).insert(
          CourseNodesCompanion.insert(
            courseVersionId: courseVersionId,
            kpKey: '1.1',
            title: 'Motion',
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
            title: const Value('Local'),
            startedAt: Value(DateTime.parse('2026-04-01T09:00:00Z')),
            syncId: const Value('local-session'),
            syncUpdatedAt: Value(DateTime.parse('2026-04-01T09:05:00Z')),
          ),
        );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            sessionId: sessionId,
            role: 'assistant',
            content: 'local base',
            createdAt: Value(DateTime.parse('2026-04-01T09:00:10Z')),
          ),
        );

    final student = (await db.getUserById(studentId))!;
    await service.handleLocalSyncRelevantChange(
      SyncRelevantChange(localUserIds: <int>{studentId}),
    );
    await service.syncIfReady(
      currentUser: student,
      mode: SessionSyncMode.uploadOnly,
    );
    db.setSyncRelevantChangeCallback(service.handleLocalSyncRelevantChange);
    await db.deleteSession(sessionId);
    final manifestAfterDelete = await artifactStore.loadManifest(3001);
    final deletedItem = manifestAfterDelete.items['student_kp:3001:200:1.1'];
    expect(deletedItem, isNotNull);
    expect(deletedItem!.deleted, isTrue);
    expect(deletedItem.storageFile, isEmpty);

    final stats = await service.forcePushLocalToServer(currentUser: student);

    expect(stats.uploadedCount, 1);
    expect(api.deleteCalls, 1);
    expect(api.deletedArtifactIds, <String>['student_kp:3001:200:1.1']);
    expect(api.deletedOverwriteServerFlags, <bool>[true]);
    await expectLater(
      api.downloadArtifact('student_kp:3001:200:1.1'),
      throwsA(isA<StateError>()),
    );
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

  test(
      'teacher session delete is server-first and resets only the target KP progress',
      () async {
    final api = _FakeArtifactSyncApiService();
    final fixture = await _createTeacherSessionDeleteFixture(
      db: db,
      artifactStore: artifactStore,
      api: api,
    );

    await fixture.service.deleteSessionAndResetKpProgress(
      currentUser: fixture.teacher,
      sessionId: fixture.targetSessionId,
    );

    expect(api.teacherSessionDeleteCalls, 1);
    expect(api.teacherDeletedArtifactIds, <String>[fixture.artifactId]);
    expect(api.teacherDeletedSessionSyncIds, <String>['target-session']);
    expect(
      api.teacherDeleteBaseSha256Values,
      <String>[fixture.baseSha256],
    );
    expect(await db.getSession(fixture.targetSessionId), isNull);
    final remainingSessions = await db.getSessionsForNode(
      studentId: fixture.localStudentId,
      courseVersionId: fixture.courseVersionId,
      kpKey: '2.1',
    );
    expect(
      remainingSessions.map((session) => session.syncId),
      <String?>['sibling-session'],
    );
    expect(
      await db.getProgress(
        studentId: fixture.localStudentId,
        courseVersionId: fixture.courseVersionId,
        kpKey: '2.1',
      ),
      isNull,
    );
    final mistakes = await db.getMistakeEntriesForScope(
      studentId: fixture.localStudentId,
      courseVersionId: fixture.courseVersionId,
      kpKey: '2.1',
    );
    expect(mistakes, hasLength(1));
    expect(mistakes.single.mistakeTagKey, 'date confusion');
    final teacherManifest = await artifactStore.loadManifest(901);
    final refreshedTeacherItem = teacherManifest.items[fixture.artifactId];
    expect(refreshedTeacherItem, isNotNull);
    expect(refreshedTeacherItem!.baseSha256, isNot(fixture.baseSha256));
    final studentManifest = await artifactStore.loadManifest(3001);
    expect(studentManifest.items, isNot(contains(fixture.artifactId)));
  });

  test('teacher session delete conflict preserves all local canonical data',
      () async {
    final api = _FakeArtifactSyncApiService();
    final fixture = await _createTeacherSessionDeleteFixture(
      db: db,
      artifactStore: artifactStore,
      api: api,
    );
    final conflict = ArtifactConflictException(
      message: 'Artifact conflict: server_changed',
      serverSha256: 'server-v2',
      expectedBaseSha256: fixture.baseSha256,
    );
    api.teacherSessionDeleteError = conflict;

    await expectLater(
      fixture.service.deleteSessionAndResetKpProgress(
        currentUser: fixture.teacher,
        sessionId: fixture.targetSessionId,
      ),
      throwsA(same(conflict)),
    );

    expect(api.teacherSessionDeleteCalls, 1);
    expect(
      api.teacherDeleteBaseSha256Values,
      <String>[fixture.baseSha256],
    );
    final reconciledSessions = await db.getSessionsForNode(
      studentId: fixture.localStudentId,
      courseVersionId: fixture.courseVersionId,
      kpKey: '2.1',
    );
    expect(
      reconciledSessions.map((session) => session.syncId).toSet(),
      <String?>{'target-session', 'sibling-session'},
    );
    final reconciledTarget = reconciledSessions.singleWhere(
      (session) => session.syncId == 'target-session',
    );
    expect(
      await db.getMessagesForSession(reconciledTarget.id),
      hasLength(1),
    );
    expect(
      await db.getProgress(
        studentId: fixture.localStudentId,
        courseVersionId: fixture.courseVersionId,
        kpKey: '2.1',
      ),
      isNotNull,
    );
    expect(
      await db.getMistakeEntriesForScope(
        studentId: fixture.localStudentId,
        courseVersionId: fixture.courseVersionId,
        kpKey: '2.1',
      ),
      hasLength(1),
    );
    final teacherManifest = await artifactStore.loadManifest(901);
    expect(teacherManifest.items, contains(fixture.artifactId));
    final studentManifest = await artifactStore.loadManifest(3001);
    expect(studentManifest.items, contains(fixture.artifactId));
  });

  test('teacher session delete reconciles a committed response loss', () async {
    final api = _FakeArtifactSyncApiService();
    final fixture = await _createTeacherSessionDeleteFixture(
      db: db,
      artifactStore: artifactStore,
      api: api,
    );
    api
      ..teacherSessionDeleteError =
          ArtifactSyncApiException('Connection closed before response.')
      ..teacherSessionDeleteThrowsAfterMutation = true;

    await fixture.service.deleteSessionAndResetKpProgress(
      currentUser: fixture.teacher,
      sessionId: fixture.targetSessionId,
    );

    expect(api.teacherSessionDeleteCalls, 1);
    final reconciledSessions = await db.getSessionsForNode(
      studentId: fixture.localStudentId,
      courseVersionId: fixture.courseVersionId,
      kpKey: '2.1',
    );
    expect(
      reconciledSessions.map((session) => session.syncId),
      <String?>['sibling-session'],
    );
    expect(
      await db.getProgress(
        studentId: fixture.localStudentId,
        courseVersionId: fixture.courseVersionId,
        kpKey: '2.1',
      ),
      isNull,
    );
    final studentManifest = await artifactStore.loadManifest(3001);
    expect(studentManifest.items, isNot(contains(fixture.artifactId)));
  });

  test('teacher session delete reports local refresh failure and can reconcile',
      () async {
    final api = _FakeArtifactSyncApiService();
    final fixture = await _createTeacherSessionDeleteFixture(
      db: db,
      artifactStore: artifactStore,
      api: api,
    );
    api.downloadArtifactError = StateError('download interrupted');

    await expectLater(
      fixture.service.deleteSessionAndResetKpProgress(
        currentUser: fixture.teacher,
        sessionId: fixture.targetSessionId,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('deleted on the server'),
        ),
      ),
    );

    expect(api.teacherSessionDeleteCalls, 1);
    expect(await db.getSession(fixture.targetSessionId), isNotNull);
    expect(
      await db.getProgress(
        studentId: fixture.localStudentId,
        courseVersionId: fixture.courseVersionId,
        kpKey: '2.1',
      ),
      isNotNull,
    );

    api.downloadArtifactError = null;
    await fixture.service.materializeTeacherArtifactsForView(
      currentUser: fixture.teacher,
      localStudentId: fixture.localStudentId,
      courseVersionId: fixture.courseVersionId,
    );

    final reconciledSessions = await db.getSessionsForNode(
      studentId: fixture.localStudentId,
      courseVersionId: fixture.courseVersionId,
      kpKey: '2.1',
    );
    expect(
      reconciledSessions.map((session) => session.syncId),
      <String?>['sibling-session'],
    );
    expect(
      await db.getProgress(
        studentId: fixture.localStudentId,
        courseVersionId: fixture.courseVersionId,
        kpKey: '2.1',
      ),
      isNull,
    );
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

  test('recovers manifest bases after a partially committed artifact batch',
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
    final partialBatchFailure =
        ArtifactSyncApiException('Batch response ended after one commit.');
    api
      ..uploadBatchFailAfterCommittedItems = 1
      ..uploadBatchFailure = partialBatchFailure;
    final uploadService = SessionSyncService(
      db: db,
      api: api,
      artifactStore: artifactStore,
    );
    final student = (await db.getUserById(studentId))!;

    await expectLater(
      uploadService.syncIfReady(
        currentUser: student,
        mode: SessionSyncMode.uploadOnly,
      ),
      throwsA(same(partialBatchFailure)),
    );

    expect(api.uploadBatchCalls, 1);
    expect(api.uploadCalls, 0);
    expect(api.getState1Calls, 1);
    expect(api.downloadCalls, 0);
    expect(api.downloadBatchCalls, 0);
    expect(api.uploadedArtifactIds, hasLength(1));
    final committedArtifactId = api.uploadedArtifactIds.single;
    final manifestAfterPartialBatch = await artifactStore.loadManifest(3001);
    expect(
      manifestAfterPartialBatch.items[committedArtifactId]!.baseSha256,
      isEmpty,
    );

    final laterConflict =
        ArtifactSyncApiException('Later upload still needs retry.');
    api
      ..uploadBatchFailAfterCommittedItems = null
      ..uploadBatchFailure = null
      ..uploadArtifactError = laterConflict;
    await expectLater(
      uploadService.syncIfReady(
        currentUser: student,
        mode: SessionSyncMode.uploadOnly,
      ),
      throwsA(same(laterConflict)),
    );

    final manifestAfterReconciliation = await artifactStore.loadManifest(3001);
    final committedItem =
        manifestAfterReconciliation.items[committedArtifactId]!;
    expect(committedItem.baseSha256, committedItem.sha256);
    for (final item in manifestAfterReconciliation.items.values) {
      if (item.artifactId != committedArtifactId) {
        expect(item.baseSha256, isEmpty);
      }
    }

    api.uploadArtifactError = null;
    final recoveredStats = await uploadService.syncIfReady(
      currentUser: student,
      mode: SessionSyncMode.uploadOnly,
    );
    expect(recoveredStats.uploadedCount, 3);
    expect(recoveredStats.downloadedCount, 0);
    expect(api.uploadBatchCalls, 1);
    expect(api.uploadCalls, 3);
    expect(api.getState1Calls, 3);
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

  test('syncNow waits for active periodic sync before final upload', () async {
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
    api.blockNextGetState2();
    final periodicSync = service.syncIfReady(currentUser: student);
    await api.waitForBlockedGetState2();

    var finalCompleted = false;
    final finalSync = service
        .syncNow(
      currentUser: student,
      password: 'unused',
      mode: SessionSyncMode.full,
    )
        .then((stats) {
      finalCompleted = true;
      return stats;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(finalCompleted, isFalse);

    api.releaseBlockedGetState2();
    final periodicStats = await periodicSync;
    expect(periodicStats.uploadedCount, 0);

    final stats = await finalSync;
    expect(finalCompleted, isTrue);
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
