import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:family_teacher/db/app_database.dart' hide SyncItemState;
import 'package:family_teacher/services/secure_storage_service.dart';
import 'package:family_teacher/services/session_crypto_service.dart';
import 'package:family_teacher/services/session_sync_api_service.dart';
import 'package:family_teacher/services/session_sync_service.dart';
import 'package:family_teacher/services/sync_state_repository.dart';
import 'package:family_teacher/services/user_key_service.dart';

class _MemorySecureStorage extends SecureStorageService
    implements SyncStateRepository {
  _MemorySecureStorage({String? accessToken}) : _accessToken = accessToken;

  final String? _accessToken;
  final Map<int, String> _privateKeys = <int, String>{};
  final Map<int, String> _publicKeys = <int, String>{};
  final Map<int, String> _sessionCursorByRemote = <int, String>{};
  final Map<int, String> _progressCursorByRemote = <int, String>{};
  final Map<String, SyncItemState> _syncItemStateByKey =
      <String, SyncItemState>{};
  final Map<String, String> _etagByKey = <String, String>{};
  final Map<String, DateTime> _runAtByKey = <String, DateTime>{};

  String _syncStateKey({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) {
    return '$remoteUserId::$domain::$scopeKey';
  }

  String _etagKey({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) {
    return '$remoteUserId::$domain::$scopeKey';
  }

  String _runAtKey({
    required int remoteUserId,
    required String domain,
  }) {
    return '$remoteUserId::$domain';
  }

  @override
  Future<String?> readAuthAccessToken() async => _accessToken;

  @override
  Future<String?> readUserPrivateKey(int remoteUserId) async {
    return _privateKeys[remoteUserId];
  }

  @override
  Future<void> writeUserPrivateKey(int remoteUserId, String value) async {
    _privateKeys[remoteUserId] = value.trim();
  }

  @override
  Future<String?> readUserPublicKey(int remoteUserId) async {
    return _publicKeys[remoteUserId];
  }

  @override
  Future<void> writeUserPublicKey(int remoteUserId, String value) async {
    _publicKeys[remoteUserId] = value.trim();
  }

  @override
  Future<String?> readSessionSyncCursor(int remoteUserId) async {
    return _sessionCursorByRemote[remoteUserId];
  }

  @override
  Future<void> writeSessionSyncCursor(int remoteUserId, String value) async {
    _sessionCursorByRemote[remoteUserId] = value.trim();
  }

  @override
  Future<void> deleteSessionSyncCursor(int remoteUserId) async {
    _sessionCursorByRemote.remove(remoteUserId);
  }

  @override
  Future<String?> readProgressSyncCursor(int remoteUserId) async {
    return _progressCursorByRemote[remoteUserId];
  }

  @override
  Future<void> writeProgressSyncCursor(int remoteUserId, String value) async {
    _progressCursorByRemote[remoteUserId] = value.trim();
  }

  @override
  Future<void> deleteProgressSyncCursor(int remoteUserId) async {
    _progressCursorByRemote.remove(remoteUserId);
  }

  @override
  Future<SyncItemState?> readSyncItemState({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) async {
    return _syncItemStateByKey[_syncStateKey(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
    )];
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
    _syncItemStateByKey[_syncStateKey(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
    )] = SyncItemState(
      contentHash: contentHash.trim(),
      lastChangedAt: lastChangedAt.toUtc(),
      lastSyncedAt: lastSyncedAt.toUtc(),
    );
  }

  @override
  Future<String?> readSyncListEtag({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) async {
    return _etagByKey[_etagKey(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
    )];
  }

  @override
  Future<void> writeSyncListEtag({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
    required String etag,
  }) async {
    _etagByKey[_etagKey(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
    )] = etag.trim();
  }

  @override
  Future<DateTime?> readSyncRunAt({
    required int remoteUserId,
    required String domain,
  }) async {
    return _runAtByKey[_runAtKey(
      remoteUserId: remoteUserId,
      domain: domain,
    )];
  }

  @override
  Future<void> writeSyncRunAt({
    required int remoteUserId,
    required String domain,
    required DateTime runAt,
  }) async {
    _runAtByKey[_runAtKey(
      remoteUserId: remoteUserId,
      domain: domain,
    )] = runAt.toUtc();
  }

  @override
  Future<void> clearSyncDomainState({
    required int remoteUserId,
    required String domain,
    bool clearItemStates = true,
    bool clearListEtags = true,
    bool clearRunAt = true,
    bool clearCursors = false,
  }) async {
    final normalizedDomain = domain.trim().toLowerCase();
    if (clearItemStates) {
      _syncItemStateByKey.removeWhere(
          (key, _) => key.startsWith('$remoteUserId::$normalizedDomain::'));
    }
    if (clearListEtags) {
      _etagByKey.removeWhere(
          (key, _) => key.startsWith('$remoteUserId::$normalizedDomain::'));
    }
    if (clearRunAt) {
      _runAtByKey
          .removeWhere((key, _) => key == '$remoteUserId::$normalizedDomain');
    }
  }
}

class _TestSessionSyncApiService extends SessionSyncApiService {
  _TestSessionSyncApiService({
    required SecureStorageService secureStorage,
    required this.sessionItems,
    required this.progressItems,
    this.listSessionsDeltaHandler,
    this.listProgressDeltaHandler,
    this.listProgressChunksDeltaHandler,
    this.uploadProgressChunkBatchHandler,
    this.downloadManifestHandler,
    this.fetchDownloadPayloadHandler,
    Map<int, CourseKeyBundle>? courseKeysByCourse,
  }) : super(
          secureStorage: secureStorage,
          baseUrl: 'https://example.com',
          client: MockClient(
            (_) async => http.Response('[]', 200),
          ),
        ) {
    _courseKeysByCourse = courseKeysByCourse ?? <int, CourseKeyBundle>{};
  }

  final List<SessionSyncItem> sessionItems;
  final List<ProgressSyncItem> progressItems;
  final SyncListResult<SessionSyncItem> Function({
    String? since,
    int? sinceId,
    int? limit,
    String? ifNoneMatch,
  })? listSessionsDeltaHandler;
  final SyncListResult<ProgressSyncItem> Function({
    String? since,
    int? sinceId,
    int? limit,
    String? ifNoneMatch,
  })? listProgressDeltaHandler;
  final SyncListResult<ProgressSyncChunkItem> Function({
    String? since,
    int? sinceId,
    int? limit,
    String? ifNoneMatch,
  })? listProgressChunksDeltaHandler;
  final Future<void> Function(List<ProgressChunkUploadEntry> entries)?
      uploadProgressChunkBatchHandler;
  final SyncDownloadManifestResult Function({
    bool includeProgress,
    String? ifNoneMatch,
  })? downloadManifestHandler;
  final Future<SyncDownloadFetchResult> Function(
    SyncDownloadFetchRequest request,
  )? fetchDownloadPayloadHandler;
  late final Map<int, CourseKeyBundle> _courseKeysByCourse;
  final List<ProgressUploadEntry> uploadedProgressEntries =
      <ProgressUploadEntry>[];
  final List<ProgressChunkUploadEntry> uploadedProgressChunkEntries =
      <ProgressChunkUploadEntry>[];
  final List<Map<String, dynamic>> uploadedSessions = <Map<String, dynamic>>[];

  @override
  Future<SyncListResult<SessionSyncItem>> listSessionsDelta({
    String? since,
    int? sinceId,
    int? limit,
    String? ifNoneMatch,
  }) async {
    if (listSessionsDeltaHandler != null) {
      return listSessionsDeltaHandler!(
        since: since,
        sinceId: sinceId,
        limit: limit,
        ifNoneMatch: ifNoneMatch,
      );
    }
    return SyncListResult<SessionSyncItem>(
      items: sessionItems,
      etag: 'sessions-etag',
      notModified: false,
    );
  }

  @override
  Future<SyncDownloadManifestResult> getDownloadManifest({
    required bool includeProgress,
    String? ifNoneMatch,
  }) async {
    if (downloadManifestHandler != null) {
      return downloadManifestHandler!(
        includeProgress: includeProgress,
        ifNoneMatch: ifNoneMatch,
      );
    }
    return SyncDownloadManifestResult(
      sessions: sessionItems
          .map(
            (item) => SessionSyncManifestItem(
              sessionSyncId: item.sessionSyncId,
              updatedAt: item.updatedAt,
              envelopeHash: item.envelopeHash,
            ),
          )
          .toList(growable: false),
      progressChunks: const <ProgressSyncChunkManifestItem>[],
      progressRows: includeProgress
          ? progressItems
              .map(
                (item) => ProgressSyncManifestItem(
                  studentUserId: item.studentUserId,
                  courseId: item.courseId,
                  kpKey: item.kpKey,
                  updatedAt: item.updatedAt,
                  envelopeHash: item.envelopeHash,
                ),
              )
              .toList(growable: false)
          : const <ProgressSyncManifestItem>[],
      etag: 'download-manifest-etag',
      notModified: false,
    );
  }

  @override
  Future<SyncDownloadFetchResult> fetchDownloadPayload({
    required SyncDownloadFetchRequest request,
  }) async {
    if (fetchDownloadPayloadHandler != null) {
      return fetchDownloadPayloadHandler!(request);
    }
    final sessionIds = request.sessionSyncIds.toSet();
    final progressRowKeys = request.progressRows
        .map((item) => '${item.studentUserId}:${item.courseId}:${item.kpKey}')
        .toSet();
    return SyncDownloadFetchResult(
      sessions: sessionItems
          .where((item) => sessionIds.contains(item.sessionSyncId))
          .toList(growable: false),
      progressChunks: const <ProgressSyncChunkItem>[],
      progressRows: progressItems
          .where((item) => progressRowKeys.contains(
                '${item.studentUserId}:${item.courseId}:${item.kpKey}',
              ))
          .toList(growable: false),
    );
  }

  @override
  Future<SyncListResult<ProgressSyncItem>> listProgressDelta({
    String? since,
    int? sinceId,
    int? limit,
    String? ifNoneMatch,
  }) async {
    if (listProgressDeltaHandler != null) {
      return listProgressDeltaHandler!(
        since: since,
        sinceId: sinceId,
        limit: limit,
        ifNoneMatch: ifNoneMatch,
      );
    }
    return SyncListResult<ProgressSyncItem>(
      items: progressItems,
      etag: 'progress-etag',
      notModified: false,
    );
  }

  @override
  Future<SyncListResult<ProgressSyncChunkItem>> listProgressChunksDelta({
    String? since,
    int? sinceId,
    int? limit,
    String? ifNoneMatch,
  }) async {
    if (listProgressChunksDeltaHandler != null) {
      return listProgressChunksDeltaHandler!(
        since: since,
        sinceId: sinceId,
        limit: limit,
        ifNoneMatch: ifNoneMatch,
      );
    }
    return SyncListResult<ProgressSyncChunkItem>(
      items: const <ProgressSyncChunkItem>[],
      etag: 'progress-chunk-etag-empty',
      notModified: false,
    );
  }

  @override
  Future<void> uploadProgressBatch(List<ProgressUploadEntry> entries) async {
    uploadedProgressEntries.addAll(entries);
  }

  @override
  Future<void> uploadProgressChunkBatch(
    List<ProgressChunkUploadEntry> entries,
  ) async {
    if (uploadProgressChunkBatchHandler != null) {
      await uploadProgressChunkBatchHandler!(entries);
      return;
    }
    uploadedProgressChunkEntries.addAll(entries);
  }

  @override
  Future<void> uploadSession({
    required String sessionSyncId,
    required int courseId,
    required int studentUserId,
    String chapterKey = '',
    required String updatedAt,
    required String envelope,
    String? envelopeHash,
  }) async {
    uploadedSessions.add(<String, dynamic>{
      'session_sync_id': sessionSyncId,
      'course_id': courseId,
      'student_user_id': studentUserId,
      'chapter_key': chapterKey,
      'updated_at': updatedAt,
      'envelope': envelope,
      'envelope_hash': envelopeHash ?? '',
    });
  }

  @override
  Future<void> uploadSessionBatch(List<SessionUploadEntry> entries) async {
    for (final entry in entries) {
      uploadedSessions.add(<String, dynamic>{
        'session_sync_id': entry.sessionSyncId,
        'course_id': entry.courseId,
        'student_user_id': entry.studentUserId,
        'chapter_key': entry.chapterKey,
        'updated_at': entry.updatedAt,
        'envelope': entry.envelope,
        'envelope_hash': entry.envelopeHash,
      });
    }
  }

  @override
  Future<CourseKeyBundle> getCourseKeys({
    required int courseId,
    required int studentUserId,
  }) async {
    final configured = _courseKeysByCourse[courseId];
    if (configured != null) {
      return configured;
    }
    throw StateError('Unexpected getCourseKeys call in this test.');
  }
}

class _EnvelopeFixture {
  _EnvelopeFixture({
    required this.base64Envelope,
    required this.hash,
  });

  final String base64Envelope;
  final String hash;
}

Future<_EnvelopeFixture> _encryptForUser({
  required SessionCryptoService crypto,
  required Map<String, dynamic> payload,
  required int recipientUserId,
  required SimplePublicKey recipientPublicKey,
}) async {
  final envelope = await crypto.encryptPayload(
    payload: payload,
    recipients: <RecipientPublicKey>[
      RecipientPublicKey(
        userId: recipientUserId,
        publicKey: recipientPublicKey,
      ),
    ],
  );
  final jsonText = jsonEncode(envelope.toJson());
  return _EnvelopeFixture(
    base64Envelope: base64Encode(utf8.encode(jsonText)),
    hash: sha256.convert(utf8.encode(jsonText)).toString(),
  );
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'session/progress sync reuses teacher-owned local course and preserves canonical remote link',
    () async {
      final crypto = SessionCryptoService();
      final secureStorage = _MemorySecureStorage(accessToken: 'token');

      final localTeacherId = await db.createUser(
        username: 'teacher_local',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 901,
      );
      final localStudentId = await db.createUser(
        username: 'student_local',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 3001,
      );

      final localCourseVersionId = await db.createCourseVersion(
        teacherId: localTeacherId,
        subject: 'Algebra',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\algebra',
      );
      await db.assignStudent(
        studentId: localStudentId,
        courseVersionId: localCourseVersionId,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: localCourseVersionId,
        remoteCourseId: 200,
      );

      final student = await db.getUserById(localStudentId);
      expect(student, isNotNull);
      final remoteStudentId = student!.remoteUserId!;

      final studentKeyPair = await crypto.generateKeyPair();
      final studentPublicKey = await crypto.extractPublicKey(studentKeyPair);
      await secureStorage.writeUserPrivateKey(
        remoteStudentId,
        await crypto.encodePrivateKey(studentKeyPair),
      );
      await secureStorage.writeUserPublicKey(
        remoteStudentId,
        crypto.encodePublicKey(studentPublicKey),
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_progress_upload',
        runAt: DateTime.now().toUtc(),
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_session_upload',
        runAt: DateTime.now().toUtc(),
      );

      final sessionPayload = <String, dynamic>{
        'version': 1,
        'session_sync_id': 'sync-session-1',
        'course_id': 100,
        'course_subject': 'Algebra',
        'kp_key': '1.1',
        'kp_title': 'Fractions',
        'session_title': 'Fractions Intro',
        'started_at': '2026-03-01T10:00:00Z',
        'ended_at': null,
        'summary_text': 'Session summary',
        'student_remote_user_id': remoteStudentId,
        'student_username': student.username,
        'teacher_remote_user_id': 901,
        'updated_at': '2026-03-01T10:05:00Z',
        'messages': <Map<String, String>>[
          <String, String>{
            'role': 'assistant',
            'content': 'Let us review fractions.',
            'created_at': '2026-03-01T10:00:10Z',
          },
        ],
      };
      final sessionEnvelope = await _encryptForUser(
        crypto: crypto,
        payload: sessionPayload,
        recipientUserId: remoteStudentId,
        recipientPublicKey: studentPublicKey,
      );

      final progressPayload = <String, dynamic>{
        'version': 1,
        'course_id': 100,
        'course_subject': 'Algebra',
        'kp_key': '1.1',
        'lit': true,
        'lit_percent': 80,
        'question_level': 'medium',
        'summary_text': 'Progress summary',
        'summary_raw_response': '',
        'summary_valid': true,
        'teacher_remote_user_id': 901,
        'student_remote_user_id': remoteStudentId,
        'updated_at': '2026-03-01T10:06:00Z',
      };
      final progressEnvelope = await _encryptForUser(
        crypto: crypto,
        payload: progressPayload,
        recipientUserId: remoteStudentId,
        recipientPublicKey: studentPublicKey,
      );

      final api = _TestSessionSyncApiService(
        secureStorage: secureStorage,
        sessionItems: <SessionSyncItem>[
          SessionSyncItem(
            cursorId: 1,
            sessionSyncId: 'sync-session-1',
            courseId: 100,
            teacherUserId: 901,
            studentUserId: remoteStudentId,
            senderUserId: remoteStudentId,
            updatedAt: '2026-03-01T10:05:00Z',
            envelope: sessionEnvelope.base64Envelope,
            envelopeHash: sessionEnvelope.hash,
          ),
        ],
        progressItems: <ProgressSyncItem>[
          ProgressSyncItem(
            cursorId: 2,
            courseId: 100,
            courseSubject: 'Algebra',
            teacherUserId: 901,
            studentUserId: remoteStudentId,
            kpKey: '1.1',
            lit: false,
            litPercent: 0,
            questionLevel: '',
            summaryText: '',
            summaryRawResponse: '',
            summaryValid: null,
            updatedAt: '2026-03-01T10:06:00Z',
            envelope: progressEnvelope.base64Envelope,
            envelopeHash: progressEnvelope.hash,
          ),
        ],
      );

      final userKeyService = UserKeyService(
        secureStorage: secureStorage,
        api: api,
        crypto: crypto,
      );
      final syncService = SessionSyncService(
        db: db,
        secureStorage: secureStorage,
        api: api,
        userKeyService: userKeyService,
        crypto: crypto,
      );

      await syncService.syncIfReady(currentUser: student);

      final sessions = await db.getSessionsForStudent(localStudentId);
      expect(sessions, hasLength(1));
      expect(sessions.single.courseVersionId, equals(localCourseVersionId));

      final progressRows = await db.getProgressForCourse(
        studentId: localStudentId,
        courseVersionId: localCourseVersionId,
      );
      expect(progressRows, hasLength(1));
      expect(progressRows.single.kpKey, equals('1.1'));
      expect(progressRows.single.litPercent, equals(80));

      final remoteId = await db.getRemoteCourseId(localCourseVersionId);
      expect(remoteId, equals(200));
      final staleRemoteLink = await db.getCourseVersionIdForRemoteCourse(100);
      expect(staleRemoteLink, isNull);

      final studentOwnedCourses = await db.getCourseVersionsForTeacher(
        localStudentId,
      );
      expect(studentOwnedCourses, isEmpty);
    },
  );

  test(
    'empty local state clears stale cursors and re-downloads full session/progress history',
    () async {
      final crypto = SessionCryptoService();
      final secureStorage = _MemorySecureStorage(accessToken: 'token');

      final localTeacherId = await db.createUser(
        username: 'teacher_bootstrap',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 902,
      );
      final localStudentId = await db.createUser(
        username: 'student_bootstrap',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 3002,
      );
      final localCourseVersionId = await db.createCourseVersion(
        teacherId: localTeacherId,
        subject: 'Geometry',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\geometry',
      );
      await db.assignStudent(
        studentId: localStudentId,
        courseVersionId: localCourseVersionId,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: localCourseVersionId,
        remoteCourseId: 110,
      );

      final student = await db.getUserById(localStudentId);
      expect(student, isNotNull);
      final remoteStudentId = student!.remoteUserId!;

      final studentKeyPair = await crypto.generateKeyPair();
      final studentPublicKey = await crypto.extractPublicKey(studentKeyPair);
      await secureStorage.writeUserPrivateKey(
        remoteStudentId,
        await crypto.encodePrivateKey(studentKeyPair),
      );
      await secureStorage.writeUserPublicKey(
        remoteStudentId,
        crypto.encodePublicKey(studentPublicKey),
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_progress_upload',
        runAt: DateTime.now().toUtc(),
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_session_upload',
        runAt: DateTime.now().toUtc(),
      );

      await secureStorage.writeSessionSyncCursor(
        remoteStudentId,
        '2026-03-05T00:00:00Z|999',
      );
      await secureStorage.writeProgressSyncCursor(
        remoteStudentId,
        '2026-03-05T00:00:00Z|999',
      );
      await secureStorage.writeSyncListEtag(
        remoteUserId: remoteStudentId,
        domain: 'session_download',
        scopeKey: 'since:2026-03-05T00:00:00Z|999',
        etag: 'stale-session-etag',
      );
      await secureStorage.writeSyncListEtag(
        remoteUserId: remoteStudentId,
        domain: 'progress_download',
        scopeKey: 'since:2026-03-05T00:00:00Z|999',
        etag: 'stale-progress-etag',
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_session_download',
        runAt: DateTime.now().toUtc(),
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_progress_download',
        runAt: DateTime.now().toUtc(),
      );

      final sessionPayload = <String, dynamic>{
        'version': 1,
        'session_sync_id': 'bootstrap-session-1',
        'course_id': 110,
        'course_subject': 'Geometry',
        'kp_key': '1.1',
        'kp_title': 'Angles',
        'session_title': 'Angles Warmup',
        'started_at': '2026-03-01T08:00:00Z',
        'ended_at': null,
        'summary_text': 'Bootstrap summary',
        'student_remote_user_id': remoteStudentId,
        'student_username': student.username,
        'teacher_remote_user_id': 902,
        'updated_at': '2026-03-01T08:10:00Z',
        'messages': <Map<String, String>>[
          <String, String>{
            'role': 'assistant',
            'content': 'Angle basics',
            'created_at': '2026-03-01T08:00:10Z',
          },
        ],
      };
      final sessionEnvelope = await _encryptForUser(
        crypto: crypto,
        payload: sessionPayload,
        recipientUserId: remoteStudentId,
        recipientPublicKey: studentPublicKey,
      );
      final sessionItem = SessionSyncItem(
        cursorId: 10,
        sessionSyncId: 'bootstrap-session-1',
        courseId: 110,
        teacherUserId: 902,
        studentUserId: remoteStudentId,
        senderUserId: remoteStudentId,
        updatedAt: '2026-03-01T08:10:00Z',
        envelope: sessionEnvelope.base64Envelope,
        envelopeHash: sessionEnvelope.hash,
      );

      final progressPayload = <String, dynamic>{
        'version': 1,
        'course_id': 110,
        'course_subject': 'Geometry',
        'kp_key': '1.1',
        'lit': true,
        'lit_percent': 70,
        'question_level': 'medium',
        'summary_text': 'Bootstrap progress',
        'summary_raw_response': '',
        'summary_valid': true,
        'teacher_remote_user_id': 902,
        'student_remote_user_id': remoteStudentId,
        'updated_at': '2026-03-01T08:20:00Z',
      };
      final progressEnvelope = await _encryptForUser(
        crypto: crypto,
        payload: progressPayload,
        recipientUserId: remoteStudentId,
        recipientPublicKey: studentPublicKey,
      );
      final progressItem = ProgressSyncItem(
        cursorId: 11,
        courseId: 110,
        courseSubject: 'Geometry',
        teacherUserId: 902,
        studentUserId: remoteStudentId,
        kpKey: '1.1',
        lit: false,
        litPercent: 0,
        questionLevel: '',
        summaryText: '',
        summaryRawResponse: '',
        summaryValid: null,
        updatedAt: '2026-03-01T08:20:00Z',
        envelope: progressEnvelope.base64Envelope,
        envelopeHash: progressEnvelope.hash,
      );

      String? observedSessionSince;
      int? observedSessionSinceId;
      String? observedProgressSince;
      int? observedProgressSinceId;

      bool _isAfterCursor({
        required String value,
        required String? since,
        required int? sinceId,
        required int cursorId,
      }) {
        if ((since ?? '').trim().isEmpty) {
          return true;
        }
        final sinceTime = DateTime.parse(since!).toUtc();
        final valueTime = DateTime.parse(value).toUtc();
        if (valueTime.isAfter(sinceTime)) {
          return true;
        }
        if (valueTime.isAtSameMomentAs(sinceTime)) {
          return cursorId > (sinceId ?? 0);
        }
        return false;
      }

      final api = _TestSessionSyncApiService(
        secureStorage: secureStorage,
        sessionItems: <SessionSyncItem>[sessionItem],
        progressItems: <ProgressSyncItem>[progressItem],
        listSessionsDeltaHandler: ({
          String? since,
          int? sinceId,
          int? limit,
          String? ifNoneMatch,
        }) {
          observedSessionSince = since;
          observedSessionSinceId = sinceId;
          final include = _isAfterCursor(
            value: sessionItem.updatedAt,
            since: since,
            sinceId: sinceId,
            cursorId: sessionItem.cursorId,
          );
          return SyncListResult<SessionSyncItem>(
            items:
                include ? <SessionSyncItem>[sessionItem] : <SessionSyncItem>[],
            etag: 'sessions-etag-bootstrap',
            notModified: false,
          );
        },
        listProgressDeltaHandler: ({
          String? since,
          int? sinceId,
          int? limit,
          String? ifNoneMatch,
        }) {
          observedProgressSince = since;
          observedProgressSinceId = sinceId;
          final include = _isAfterCursor(
            value: progressItem.updatedAt,
            since: since,
            sinceId: sinceId,
            cursorId: progressItem.cursorId,
          );
          return SyncListResult<ProgressSyncItem>(
            items: include
                ? <ProgressSyncItem>[progressItem]
                : <ProgressSyncItem>[],
            etag: 'progress-etag-bootstrap',
            notModified: false,
          );
        },
      );

      final userKeyService = UserKeyService(
        secureStorage: secureStorage,
        api: api,
        crypto: crypto,
      );
      final syncService = SessionSyncService(
        db: db,
        secureStorage: secureStorage,
        api: api,
        userKeyService: userKeyService,
        crypto: crypto,
      );

      await syncService.syncIfReady(currentUser: student);

      expect((observedSessionSince ?? '').trim(), isEmpty);
      expect(observedSessionSinceId == null || observedSessionSinceId == 0,
          isTrue);
      expect((observedProgressSince ?? '').trim(), isEmpty);
      expect(observedProgressSinceId == null || observedProgressSinceId == 0,
          isTrue);

      final sessions = await db.getSessionsForStudent(localStudentId);
      expect(sessions, hasLength(1));
      final importedSession = await db.getSession(sessions.single.sessionId);
      expect(importedSession, isNotNull);
      expect(importedSession!.syncId, equals('bootstrap-session-1'));

      final progressRows = await db.getProgressForCourse(
        studentId: localStudentId,
        courseVersionId: localCourseVersionId,
      );
      expect(progressRows, hasLength(1));
      expect(progressRows.single.kpKey, equals('1.1'));
      expect(progressRows.single.litPercent, equals(70));
    },
  );

  test(
    'teacher sync downloads student sessions and progress into teacher-visible student records',
    () async {
      final crypto = SessionCryptoService();
      final secureStorage = _MemorySecureStorage(accessToken: 'token');

      final localTeacherId = await db.createUser(
        username: 'teacher_sync',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 901,
      );
      final localCourseVersionId = await db.createCourseVersion(
        teacherId: localTeacherId,
        subject: 'Geometry',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\geometry',
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: localCourseVersionId,
        remoteCourseId: 100,
      );

      final teacher = await db.getUserById(localTeacherId);
      expect(teacher, isNotNull);
      final remoteTeacherId = teacher!.remoteUserId!;

      final teacherKeyPair = await crypto.generateKeyPair();
      final teacherPublicKey = await crypto.extractPublicKey(teacherKeyPair);
      await secureStorage.writeUserPrivateKey(
        remoteTeacherId,
        await crypto.encodePrivateKey(teacherKeyPair),
      );
      await secureStorage.writeUserPublicKey(
        remoteTeacherId,
        crypto.encodePublicKey(teacherPublicKey),
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteTeacherId,
        domain: 'session_sync_run_progress_upload',
        runAt: DateTime.now().toUtc(),
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteTeacherId,
        domain: 'session_sync_run_session_upload',
        runAt: DateTime.now().toUtc(),
      );

      const remoteStudentId = 3001;
      final sessionPayload = <String, dynamic>{
        'version': 1,
        'session_sync_id': 'teacher-download-session-1',
        'course_id': 100,
        'course_subject': 'Geometry',
        'kp_key': '2.1',
        'kp_title': 'Triangles',
        'session_title': 'Triangle Basics',
        'started_at': '2026-03-01T10:00:00Z',
        'ended_at': null,
        'summary_text': 'Teacher reviewable session',
        'student_remote_user_id': remoteStudentId,
        'student_username': 'student_remote',
        'teacher_remote_user_id': remoteTeacherId,
        'updated_at': '2026-03-01T10:05:00Z',
        'messages': <Map<String, String>>[
          <String, String>{
            'role': 'assistant',
            'content': 'Let us review triangles.',
            'created_at': '2026-03-01T10:00:10Z',
          },
        ],
      };
      final sessionEnvelope = await _encryptForUser(
        crypto: crypto,
        payload: sessionPayload,
        recipientUserId: remoteTeacherId,
        recipientPublicKey: teacherPublicKey,
      );

      final progressPayload = <String, dynamic>{
        'version': 1,
        'course_id': 100,
        'course_subject': 'Geometry',
        'kp_key': '2.1',
        'lit': true,
        'lit_percent': 91,
        'question_level': 'medium',
        'summary_text': 'Teacher reviewable progress',
        'summary_raw_response': '',
        'summary_valid': true,
        'teacher_remote_user_id': remoteTeacherId,
        'student_remote_user_id': remoteStudentId,
        'updated_at': '2026-03-01T10:06:00Z',
      };
      final progressEnvelope = await _encryptForUser(
        crypto: crypto,
        payload: progressPayload,
        recipientUserId: remoteTeacherId,
        recipientPublicKey: teacherPublicKey,
      );

      final api = _TestSessionSyncApiService(
        secureStorage: secureStorage,
        sessionItems: <SessionSyncItem>[
          SessionSyncItem(
            cursorId: 1,
            sessionSyncId: 'teacher-download-session-1',
            courseId: 100,
            teacherUserId: remoteTeacherId,
            studentUserId: remoteStudentId,
            senderUserId: remoteStudentId,
            updatedAt: '2026-03-01T10:05:00Z',
            envelope: sessionEnvelope.base64Envelope,
            envelopeHash: sessionEnvelope.hash,
          ),
        ],
        progressItems: <ProgressSyncItem>[
          ProgressSyncItem(
            cursorId: 2,
            courseId: 100,
            courseSubject: 'Geometry',
            teacherUserId: remoteTeacherId,
            studentUserId: remoteStudentId,
            kpKey: '2.1',
            lit: false,
            litPercent: 0,
            questionLevel: '',
            summaryText: '',
            summaryRawResponse: '',
            summaryValid: null,
            updatedAt: '2026-03-01T10:06:00Z',
            envelope: progressEnvelope.base64Envelope,
            envelopeHash: progressEnvelope.hash,
          ),
        ],
      );

      final userKeyService = UserKeyService(
        secureStorage: secureStorage,
        api: api,
        crypto: crypto,
      );
      final syncService = SessionSyncService(
        db: db,
        secureStorage: secureStorage,
        api: api,
        userKeyService: userKeyService,
        crypto: crypto,
      );

      await syncService.syncIfReady(currentUser: teacher);

      final students = await db.watchStudents(localTeacherId).first;
      expect(students, hasLength(1));
      final localStudentId = students.single.id;
      expect(students.single.remoteUserId, equals(remoteStudentId));

      final sessions = await db.getSessionsForStudent(localStudentId);
      expect(sessions, hasLength(1));
      expect(sessions.single.courseVersionId, equals(localCourseVersionId));

      final progressRows = await db.getProgressForCourse(
        studentId: localStudentId,
        courseVersionId: localCourseVersionId,
      );
      expect(progressRows, hasLength(1));
      expect(progressRows.single.kpKey, equals('2.1'));
      expect(progressRows.single.litPercent, equals(91));
    },
  );

  test(
    'session/progress conflict resolution uses last-modified winner',
    () async {
      final crypto = SessionCryptoService();
      final secureStorage = _MemorySecureStorage(accessToken: 'token');

      final teacherId = await db.createUser(
        username: 'teacher_conflict',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 903,
      );
      final studentId = await db.createUser(
        username: 'student_conflict',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 3003,
      );
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Chemistry',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\chemistry',
      );
      await db.assignStudent(
          studentId: studentId, courseVersionId: courseVersionId);
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 120,
      );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);
      final remoteStudentId = student!.remoteUserId!;

      final studentKeyPair = await crypto.generateKeyPair();
      final studentPublicKey = await crypto.extractPublicKey(studentKeyPair);
      await secureStorage.writeUserPrivateKey(
        remoteStudentId,
        await crypto.encodePrivateKey(studentKeyPair),
      );
      await secureStorage.writeUserPublicKey(
        remoteStudentId,
        crypto.encodePublicKey(studentPublicKey),
      );

      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_progress_upload',
        runAt: DateTime.now().toUtc(),
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_session_upload',
        runAt: DateTime.now().toUtc(),
      );

      final localSessionNewerId = await db.into(db.chatSessions).insert(
            ChatSessionsCompanion.insert(
              studentId: studentId,
              courseVersionId: courseVersionId,
              kpKey: '1.1',
              title: const Value('Local Newer'),
              status: const Value('active'),
              startedAt: Value(DateTime.parse('2026-03-02T09:00:00Z')),
              syncId: const Value('conflict-session-local-newer'),
              syncUpdatedAt: Value(DateTime.parse('2026-03-02T09:05:00Z')),
              syncUploadedAt: Value(DateTime.parse('2026-03-02T09:05:00Z')),
            ),
          );
      await db.into(db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: localSessionNewerId,
              role: 'assistant',
              content: 'LOCAL_NEWER_MESSAGE',
              createdAt: Value(DateTime.parse('2026-03-02T09:00:10Z')),
            ),
          );

      final localSessionOlderId = await db.into(db.chatSessions).insert(
            ChatSessionsCompanion.insert(
              studentId: studentId,
              courseVersionId: courseVersionId,
              kpKey: '1.2',
              title: const Value('Local Older'),
              status: const Value('active'),
              startedAt: Value(DateTime.parse('2026-03-01T09:00:00Z')),
              syncId: const Value('conflict-session-local-older'),
              syncUpdatedAt: Value(DateTime.parse('2026-03-01T09:05:00Z')),
              syncUploadedAt: Value(DateTime.parse('2026-03-01T09:05:00Z')),
            ),
          );
      await db.into(db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: localSessionOlderId,
              role: 'assistant',
              content: 'LOCAL_OLDER_MESSAGE',
              createdAt: Value(DateTime.parse('2026-03-01T09:00:10Z')),
            ),
          );

      await db.upsertProgressFromSync(
        studentId: studentId,
        courseVersionId: courseVersionId,
        kpKey: '1.1',
        lit: true,
        litPercent: 95,
        questionLevel: 'hard',
        summaryText: 'local newer progress',
        summaryRawResponse: '',
        summaryValid: true,
        updatedAt: DateTime.parse('2026-03-02T10:00:00Z'),
      );
      await db.upsertProgressFromSync(
        studentId: studentId,
        courseVersionId: courseVersionId,
        kpKey: '1.2',
        lit: false,
        litPercent: 20,
        questionLevel: 'easy',
        summaryText: 'local older progress',
        summaryRawResponse: '',
        summaryValid: false,
        updatedAt: DateTime.parse('2026-03-01T10:00:00Z'),
      );

      Future<SessionSyncItem> buildSessionItem({
        required String syncId,
        required String kpKey,
        required String updatedAt,
        required String messageContent,
        required int cursorId,
      }) async {
        final payload = <String, dynamic>{
          'version': 1,
          'session_sync_id': syncId,
          'course_id': 120,
          'course_subject': 'Chemistry',
          'kp_key': kpKey,
          'kp_title': kpKey,
          'session_title': 'Remote $kpKey',
          'started_at': updatedAt,
          'ended_at': null,
          'summary_text': 'remote',
          'student_remote_user_id': remoteStudentId,
          'student_username': student.username,
          'teacher_remote_user_id': 903,
          'updated_at': updatedAt,
          'messages': <Map<String, String>>[
            <String, String>{
              'role': 'assistant',
              'content': messageContent,
              'created_at': updatedAt,
            },
          ],
        };
        final envelope = await _encryptForUser(
          crypto: crypto,
          payload: payload,
          recipientUserId: remoteStudentId,
          recipientPublicKey: studentPublicKey,
        );
        return SessionSyncItem(
          cursorId: cursorId,
          sessionSyncId: syncId,
          courseId: 120,
          teacherUserId: 903,
          studentUserId: remoteStudentId,
          senderUserId: remoteStudentId,
          updatedAt: updatedAt,
          envelope: envelope.base64Envelope,
          envelopeHash: envelope.hash,
        );
      }

      Future<ProgressSyncItem> buildProgressItem({
        required String kpKey,
        required String updatedAt,
        required int litPercent,
        required int cursorId,
      }) async {
        final payload = <String, dynamic>{
          'version': 1,
          'course_id': 120,
          'course_subject': 'Chemistry',
          'kp_key': kpKey,
          'lit': litPercent >= 60,
          'lit_percent': litPercent,
          'question_level': 'medium',
          'summary_text': 'remote $kpKey',
          'summary_raw_response': '',
          'summary_valid': true,
          'teacher_remote_user_id': 903,
          'student_remote_user_id': remoteStudentId,
          'updated_at': updatedAt,
        };
        final envelope = await _encryptForUser(
          crypto: crypto,
          payload: payload,
          recipientUserId: remoteStudentId,
          recipientPublicKey: studentPublicKey,
        );
        return ProgressSyncItem(
          cursorId: cursorId,
          courseId: 120,
          courseSubject: 'Chemistry',
          teacherUserId: 903,
          studentUserId: remoteStudentId,
          kpKey: kpKey,
          lit: litPercent >= 60,
          litPercent: litPercent,
          questionLevel: 'medium',
          summaryText: 'remote $kpKey',
          summaryRawResponse: '',
          summaryValid: true,
          updatedAt: updatedAt,
          envelope: envelope.base64Envelope,
          envelopeHash: envelope.hash,
        );
      }

      final api = _TestSessionSyncApiService(
        secureStorage: secureStorage,
        sessionItems: <SessionSyncItem>[
          await buildSessionItem(
            syncId: 'conflict-session-local-newer',
            kpKey: '1.1',
            updatedAt: '2026-03-01T08:00:00Z',
            messageContent: 'REMOTE_OLDER_MESSAGE',
            cursorId: 21,
          ),
          await buildSessionItem(
            syncId: 'conflict-session-local-older',
            kpKey: '1.2',
            updatedAt: '2026-03-02T08:00:00Z',
            messageContent: 'REMOTE_NEWER_MESSAGE',
            cursorId: 22,
          ),
        ],
        progressItems: <ProgressSyncItem>[
          await buildProgressItem(
            kpKey: '1.1',
            updatedAt: '2026-03-01T08:10:00Z',
            litPercent: 40,
            cursorId: 31,
          ),
          await buildProgressItem(
            kpKey: '1.2',
            updatedAt: '2026-03-02T08:10:00Z',
            litPercent: 75,
            cursorId: 32,
          ),
        ],
      );

      final userKeyService = UserKeyService(
        secureStorage: secureStorage,
        api: api,
        crypto: crypto,
      );
      final syncService = SessionSyncService(
        db: db,
        secureStorage: secureStorage,
        api: api,
        userKeyService: userKeyService,
        crypto: crypto,
      );

      await syncService.syncIfReady(currentUser: student);

      final refreshedNewer = await db.getSession(localSessionNewerId);
      expect(refreshedNewer, isNotNull);
      final newerMessages = await db.getMessagesForSession(localSessionNewerId);
      expect(newerMessages.single.content, equals('LOCAL_NEWER_MESSAGE'));

      final refreshedOlder = await db.getSession(localSessionOlderId);
      expect(refreshedOlder, isNotNull);
      final olderMessages = await db.getMessagesForSession(localSessionOlderId);
      expect(olderMessages.single.content, equals('REMOTE_NEWER_MESSAGE'));

      final progressRows = await db.getProgressForCourse(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );
      final byKey = <String, ProgressEntry>{
        for (final row in progressRows) row.kpKey: row,
      };
      expect(byKey['1.1']!.litPercent, equals(95));
      expect(byKey['1.2']!.litPercent, equals(75));
    },
  );

  test(
    'session download fetches all manifest-selected items in one sync run',
    () async {
      final crypto = SessionCryptoService();
      final secureStorage = _MemorySecureStorage(accessToken: 'token');

      final teacherId = await db.createUser(
        username: 'teacher_pagination',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 905,
      );
      final studentId = await db.createUser(
        username: 'student_pagination',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 3005,
      );
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Physics',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\physics',
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 140,
      );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);
      final remoteStudentId = student!.remoteUserId!;

      final studentKeyPair = await crypto.generateKeyPair();
      final studentPublicKey = await crypto.extractPublicKey(studentKeyPair);
      await secureStorage.writeUserPrivateKey(
        remoteStudentId,
        await crypto.encodePrivateKey(studentKeyPair),
      );
      await secureStorage.writeUserPublicKey(
        remoteStudentId,
        crypto.encodePublicKey(studentPublicKey),
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_progress_upload',
        runAt: DateTime.now().toUtc(),
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_session_upload',
        runAt: DateTime.now().toUtc(),
      );

      final manifestItems = List<SessionSyncManifestItem>.generate(5000, (
        index,
      ) {
        final sessionSyncId = 'sync-${index + 1}';
        return SessionSyncManifestItem(
          sessionSyncId: sessionSyncId,
          updatedAt: '2026-03-01T08:00:00Z',
          envelopeHash: 'hash-$sessionSyncId',
        );
      });

      var manifestCalls = 0;
      var fetchCalls = 0;
      final api = _TestSessionSyncApiService(
        secureStorage: secureStorage,
        sessionItems: const <SessionSyncItem>[],
        progressItems: const <ProgressSyncItem>[],
        downloadManifestHandler: (
            {bool includeProgress = false, String? ifNoneMatch}) {
          manifestCalls++;
          expect(includeProgress, isTrue);
          expect(ifNoneMatch, isNull);
          return SyncDownloadManifestResult(
            sessions: manifestItems,
            progressChunks: const <ProgressSyncChunkManifestItem>[],
            progressRows: const <ProgressSyncManifestItem>[],
            etag: 'download-manifest-page-1',
            notModified: false,
          );
        },
        fetchDownloadPayloadHandler: (request) async {
          fetchCalls++;
          expect(request.sessionSyncIds, hasLength(5000));
          expect(
            request.sessionSyncIds.first,
            equals(manifestItems.first.sessionSyncId),
          );
          expect(
            request.sessionSyncIds.last,
            equals(manifestItems.last.sessionSyncId),
          );
          expect(request.progressChunks, isEmpty);
          expect(request.progressRows, isEmpty);
          return SyncDownloadFetchResult(
            sessions: const <SessionSyncItem>[],
            progressChunks: const <ProgressSyncChunkItem>[],
            progressRows: const <ProgressSyncItem>[],
          );
        },
      );

      final userKeyService = UserKeyService(
        secureStorage: secureStorage,
        api: api,
        crypto: crypto,
      );
      final syncService = SessionSyncService(
        db: db,
        secureStorage: secureStorage,
        api: api,
        userKeyService: userKeyService,
        crypto: crypto,
      );

      await syncService.syncIfReady(currentUser: student);

      expect(manifestCalls, equals(1));
      expect(fetchCalls, equals(1));
    },
  );

  test(
    'progress upload batches chapter chunks when chunk endpoint is available',
    () async {
      final crypto = SessionCryptoService();
      final secureStorage = _MemorySecureStorage(accessToken: 'token');

      final teacherId = await db.createUser(
        username: 'teacher_chunk_upload',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 906,
      );
      final studentId = await db.createUser(
        username: 'student_chunk_upload',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 3006,
      );
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Math',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\math',
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 150,
      );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);
      final remoteStudentId = student!.remoteUserId!;

      final studentKeyPair = await crypto.generateKeyPair();
      final studentPublicKey = await crypto.extractPublicKey(studentKeyPair);
      await secureStorage.writeUserPrivateKey(
        remoteStudentId,
        await crypto.encodePrivateKey(studentKeyPair),
      );
      await secureStorage.writeUserPublicKey(
        remoteStudentId,
        crypto.encodePublicKey(studentPublicKey),
      );

      final teacherKeyPair = await crypto.generateKeyPair();
      final teacherPublicKey = await crypto.extractPublicKey(teacherKeyPair);

      await db.upsertProgressFromSync(
        studentId: studentId,
        courseVersionId: courseVersionId,
        kpKey: '1.1.1',
        lit: true,
        litPercent: 80,
        questionLevel: 'medium',
        summaryText: 'a',
        summaryRawResponse: '',
        summaryValid: true,
        updatedAt: DateTime.parse('2026-03-02T10:00:00Z'),
      );
      await db.upsertProgressFromSync(
        studentId: studentId,
        courseVersionId: courseVersionId,
        kpKey: '1.1.2',
        lit: false,
        litPercent: 20,
        questionLevel: 'easy',
        summaryText: 'b',
        summaryRawResponse: '',
        summaryValid: false,
        updatedAt: DateTime.parse('2026-03-02T10:01:00Z'),
      );
      await db.upsertProgressFromSync(
        studentId: studentId,
        courseVersionId: courseVersionId,
        kpKey: '2.1.1',
        lit: true,
        litPercent: 60,
        questionLevel: 'medium',
        summaryText: 'c',
        summaryRawResponse: '',
        summaryValid: true,
        updatedAt: DateTime.parse('2026-03-02T10:02:00Z'),
      );

      final api = _TestSessionSyncApiService(
        secureStorage: secureStorage,
        sessionItems: const <SessionSyncItem>[],
        progressItems: const <ProgressSyncItem>[],
        courseKeysByCourse: <int, CourseKeyBundle>{
          150: CourseKeyBundle(
            courseId: 150,
            teacherUserId: 906,
            teacherPublicKey: crypto.encodePublicKey(teacherPublicKey),
            studentUserId: remoteStudentId,
            studentPublicKey: crypto.encodePublicKey(studentPublicKey),
          ),
        },
      );
      final userKeyService = UserKeyService(
        secureStorage: secureStorage,
        api: api,
        crypto: crypto,
      );
      final syncService = SessionSyncService(
        db: db,
        secureStorage: secureStorage,
        api: api,
        userKeyService: userKeyService,
        crypto: crypto,
      );

      await syncService.syncIfReady(currentUser: student);

      expect(api.uploadedProgressEntries, isEmpty);
      expect(api.uploadedProgressChunkEntries, hasLength(2));
      final itemCountByChapter = <String, int>{
        for (final entry in api.uploadedProgressChunkEntries)
          entry.chapterKey: entry.itemCount,
      };
      expect(itemCountByChapter['1.1'], equals(2));
      expect(itemCountByChapter['2.1'], equals(1));
    },
  );

  test(
    'progress upload falls back to legacy row batch when chunk upload returns 404',
    () async {
      final crypto = SessionCryptoService();
      final secureStorage = _MemorySecureStorage(accessToken: 'token');

      final teacherId = await db.createUser(
        username: 'teacher_chunk_fallback',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 907,
      );
      final studentId = await db.createUser(
        username: 'student_chunk_fallback',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 3007,
      );
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Physics',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\physics',
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 160,
      );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);
      final remoteStudentId = student!.remoteUserId!;

      final studentKeyPair = await crypto.generateKeyPair();
      final studentPublicKey = await crypto.extractPublicKey(studentKeyPair);
      await secureStorage.writeUserPrivateKey(
        remoteStudentId,
        await crypto.encodePrivateKey(studentKeyPair),
      );
      await secureStorage.writeUserPublicKey(
        remoteStudentId,
        crypto.encodePublicKey(studentPublicKey),
      );

      final teacherKeyPair = await crypto.generateKeyPair();
      final teacherPublicKey = await crypto.extractPublicKey(teacherKeyPair);

      await db.upsertProgressFromSync(
        studentId: studentId,
        courseVersionId: courseVersionId,
        kpKey: '1.1.1',
        lit: true,
        litPercent: 85,
        questionLevel: 'medium',
        summaryText: 'fallback',
        summaryRawResponse: '',
        summaryValid: true,
        updatedAt: DateTime.parse('2026-03-02T11:00:00Z'),
      );

      final api = _TestSessionSyncApiService(
        secureStorage: secureStorage,
        sessionItems: const <SessionSyncItem>[],
        progressItems: const <ProgressSyncItem>[],
        listProgressChunksDeltaHandler: ({
          String? since,
          int? sinceId,
          int? limit,
          String? ifNoneMatch,
        }) {
          return SyncListResult<ProgressSyncChunkItem>(
            items: const <ProgressSyncChunkItem>[],
            etag: 'chunk-empty',
            notModified: false,
          );
        },
        uploadProgressChunkBatchHandler: (
          List<ProgressChunkUploadEntry> _,
        ) async {
          throw SessionSyncApiException(
            'not found',
            statusCode: 404,
          );
        },
        courseKeysByCourse: <int, CourseKeyBundle>{
          160: CourseKeyBundle(
            courseId: 160,
            teacherUserId: 907,
            teacherPublicKey: crypto.encodePublicKey(teacherPublicKey),
            studentUserId: remoteStudentId,
            studentPublicKey: crypto.encodePublicKey(studentPublicKey),
          ),
        },
      );
      final userKeyService = UserKeyService(
        secureStorage: secureStorage,
        api: api,
        crypto: crypto,
      );
      final syncService = SessionSyncService(
        db: db,
        secureStorage: secureStorage,
        api: api,
        userKeyService: userKeyService,
        crypto: crypto,
      );

      await syncService.syncIfReady(currentUser: student);

      expect(api.uploadedProgressChunkEntries, isEmpty);
      expect(api.uploadedProgressEntries, hasLength(1));
      expect(api.uploadedProgressEntries.single.kpKey, equals('1.1.1'));
    },
  );

  test(
    'progress upload skips when no local progress changed since last successful upload run',
    () async {
      final crypto = SessionCryptoService();
      final secureStorage = _MemorySecureStorage(accessToken: 'token');

      final teacherId = await db.createUser(
        username: 'teacher_upload_skip',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 908,
      );
      final studentId = await db.createUser(
        username: 'student_upload_skip',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 3008,
      );
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Chemistry',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\chemistry',
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 170,
      );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);
      final remoteStudentId = student!.remoteUserId!;

      final studentKeyPair = await crypto.generateKeyPair();
      final studentPublicKey = await crypto.extractPublicKey(studentKeyPair);
      await secureStorage.writeUserPrivateKey(
        remoteStudentId,
        await crypto.encodePrivateKey(studentKeyPair),
      );
      await secureStorage.writeUserPublicKey(
        remoteStudentId,
        crypto.encodePublicKey(studentPublicKey),
      );

      final progressUpdatedAt = DateTime.parse('2026-03-02T11:00:00Z');
      await db.upsertProgressFromSync(
        studentId: studentId,
        courseVersionId: courseVersionId,
        kpKey: '1.1.1',
        lit: true,
        litPercent: 90,
        questionLevel: 'hard',
        summaryText: 'stable',
        summaryRawResponse: '',
        summaryValid: true,
        updatedAt: progressUpdatedAt,
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_progress_upload',
        runAt: progressUpdatedAt.add(const Duration(seconds: 30)),
      );

      final api = _TestSessionSyncApiService(
        secureStorage: secureStorage,
        sessionItems: const <SessionSyncItem>[],
        progressItems: const <ProgressSyncItem>[],
      );
      final userKeyService = UserKeyService(
        secureStorage: secureStorage,
        api: api,
        crypto: crypto,
      );
      final syncService = SessionSyncService(
        db: db,
        secureStorage: secureStorage,
        api: api,
        userKeyService: userKeyService,
        crypto: crypto,
      );

      await syncService.syncIfReady(currentUser: student);

      expect(api.uploadedProgressChunkEntries, isEmpty);
      expect(api.uploadedProgressEntries, isEmpty);
    },
  );

  test(
    'progress row download skips decrypt when local timestamp is already up-to-date',
    () async {
      final crypto = SessionCryptoService();
      final secureStorage = _MemorySecureStorage(accessToken: 'token');

      final teacherId = await db.createUser(
        username: 'teacher_download_skip',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 909,
      );
      final studentId = await db.createUser(
        username: 'student_download_skip',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 3009,
      );
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'History',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\history',
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 180,
      );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);
      final remoteStudentId = student!.remoteUserId!;

      final studentKeyPair = await crypto.generateKeyPair();
      final studentPublicKey = await crypto.extractPublicKey(studentKeyPair);
      await secureStorage.writeUserPrivateKey(
        remoteStudentId,
        await crypto.encodePrivateKey(studentKeyPair),
      );
      await secureStorage.writeUserPublicKey(
        remoteStudentId,
        crypto.encodePublicKey(studentPublicKey),
      );

      final localUpdatedAt = DateTime.parse('2026-03-02T12:00:00Z');
      await db.upsertProgressFromSync(
        studentId: studentId,
        courseVersionId: courseVersionId,
        kpKey: '2.1.3',
        lit: true,
        litPercent: 75,
        questionLevel: 'medium',
        summaryText: 'local',
        summaryRawResponse: '',
        summaryValid: true,
        updatedAt: localUpdatedAt,
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_progress_upload',
        runAt: localUpdatedAt.add(const Duration(seconds: 30)),
      );

      var manifestCalls = 0;
      var fetchCalls = 0;
      final api = _TestSessionSyncApiService(
        secureStorage: secureStorage,
        sessionItems: const <SessionSyncItem>[],
        progressItems: const <ProgressSyncItem>[],
        downloadManifestHandler: (
            {bool includeProgress = false, String? ifNoneMatch}) {
          manifestCalls++;
          expect(includeProgress, isTrue);
          expect(ifNoneMatch, isNull);
          return SyncDownloadManifestResult(
            sessions: const <SessionSyncManifestItem>[],
            progressChunks: const <ProgressSyncChunkManifestItem>[],
            progressRows: <ProgressSyncManifestItem>[
              ProgressSyncManifestItem(
                studentUserId: remoteStudentId,
                courseId: 180,
                kpKey: '2.1.3',
                updatedAt: '2026-03-02T12:00:00Z',
                envelopeHash: 'same-row',
              ),
            ],
            etag: 'progress-manifest-stale-row',
            notModified: false,
          );
        },
        fetchDownloadPayloadHandler: (request) async {
          fetchCalls++;
          return SyncDownloadFetchResult(
            sessions: const <SessionSyncItem>[],
            progressChunks: const <ProgressSyncChunkItem>[],
            progressRows: const <ProgressSyncItem>[],
          );
        },
      );
      final userKeyService = UserKeyService(
        secureStorage: secureStorage,
        api: api,
        crypto: crypto,
      );
      final syncService = SessionSyncService(
        db: db,
        secureStorage: secureStorage,
        api: api,
        userKeyService: userKeyService,
        crypto: crypto,
      );

      await syncService.syncIfReady(currentUser: student);

      final progress = await db.getProgress(
        studentId: studentId,
        courseVersionId: courseVersionId,
        kpKey: '2.1.3',
      );
      expect(progress, isNotNull);
      expect(progress!.updatedAt.toUtc(), equals(localUpdatedAt.toUtc()));
      expect(manifestCalls, equals(1));
      expect(fetchCalls, equals(0));
    },
  );

  test(
    'local sync mock: no-change sync completes quickly for large progress set',
    () async {
      final crypto = SessionCryptoService();
      final secureStorage = _MemorySecureStorage(accessToken: 'token');

      final teacherId = await db.createUser(
        username: 'teacher_noop_perf',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 910,
      );
      final studentId = await db.createUser(
        username: 'student_noop_perf',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 3010,
      );
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Perf',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\perf',
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 190,
      );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);
      final remoteStudentId = student!.remoteUserId!;

      final studentKeyPair = await crypto.generateKeyPair();
      final studentPublicKey = await crypto.extractPublicKey(studentKeyPair);
      await secureStorage.writeUserPrivateKey(
        remoteStudentId,
        await crypto.encodePrivateKey(studentKeyPair),
      );
      await secureStorage.writeUserPublicKey(
        remoteStudentId,
        crypto.encodePublicKey(studentPublicKey),
      );

      final baseUpdatedAt = DateTime.parse('2026-03-02T13:00:00Z');
      for (var i = 0; i < 3127; i++) {
        await db.upsertProgressFromSync(
          studentId: studentId,
          courseVersionId: courseVersionId,
          kpKey: '1.1.$i',
          lit: i.isEven,
          litPercent: i % 101,
          questionLevel: 'medium',
          summaryText: 'p$i',
          summaryRawResponse: '',
          summaryValid: true,
          updatedAt: baseUpdatedAt.add(Duration(milliseconds: i)),
        );
      }
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_progress_upload',
        runAt: baseUpdatedAt.add(const Duration(seconds: 5)),
      );

      final api = _TestSessionSyncApiService(
        secureStorage: secureStorage,
        sessionItems: const <SessionSyncItem>[],
        progressItems: const <ProgressSyncItem>[],
        listSessionsDeltaHandler: ({
          String? since,
          int? sinceId,
          int? limit,
          String? ifNoneMatch,
        }) {
          return SyncListResult<SessionSyncItem>(
            items: const <SessionSyncItem>[],
            etag: 's304',
            notModified: true,
          );
        },
        listProgressChunksDeltaHandler: ({
          String? since,
          int? sinceId,
          int? limit,
          String? ifNoneMatch,
        }) {
          return SyncListResult<ProgressSyncChunkItem>(
            items: const <ProgressSyncChunkItem>[],
            etag: 'pc304',
            notModified: true,
          );
        },
        listProgressDeltaHandler: ({
          String? since,
          int? sinceId,
          int? limit,
          String? ifNoneMatch,
        }) {
          return SyncListResult<ProgressSyncItem>(
            items: const <ProgressSyncItem>[],
            etag: 'p304',
            notModified: true,
          );
        },
      );
      final userKeyService = UserKeyService(
        secureStorage: secureStorage,
        api: api,
        crypto: crypto,
      );
      final syncService = SessionSyncService(
        db: db,
        secureStorage: secureStorage,
        api: api,
        userKeyService: userKeyService,
        crypto: crypto,
      );

      final stopwatch = Stopwatch()..start();
      await syncService.syncIfReady(currentUser: student);
      stopwatch.stop();

      expect(stopwatch.elapsed.inMilliseconds, lessThan(1000));
      expect(api.uploadedProgressChunkEntries, isEmpty);
      expect(api.uploadedProgressEntries, isEmpty);
    },
  );

  test(
    'local sync mock: stale-cursor 3127 progress rows skip decrypt/import quickly',
    () async {
      final crypto = SessionCryptoService();
      final secureStorage = _MemorySecureStorage(accessToken: 'token');

      final teacherId = await db.createUser(
        username: 'teacher_stale_perf',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 911,
      );
      final studentId = await db.createUser(
        username: 'student_stale_perf',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 3011,
      );
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'StalePerf',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\stale_perf',
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 191,
      );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);
      final remoteStudentId = student!.remoteUserId!;

      final studentKeyPair = await crypto.generateKeyPair();
      final studentPublicKey = await crypto.extractPublicKey(studentKeyPair);
      await secureStorage.writeUserPrivateKey(
        remoteStudentId,
        await crypto.encodePrivateKey(studentKeyPair),
      );
      await secureStorage.writeUserPublicKey(
        remoteStudentId,
        crypto.encodePublicKey(studentPublicKey),
      );

      final baseUpdatedAt = DateTime.parse('2026-03-02T14:00:00Z');
      for (var i = 0; i < 3127; i++) {
        await db.upsertProgressFromSync(
          studentId: studentId,
          courseVersionId: courseVersionId,
          kpKey: '2.1.$i',
          lit: i.isEven,
          litPercent: i % 101,
          questionLevel: 'medium',
          summaryText: 'local-$i',
          summaryRawResponse: '',
          summaryValid: true,
          updatedAt: baseUpdatedAt.add(Duration(seconds: i)),
        );
      }
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_progress_upload',
        runAt: baseUpdatedAt
            .add(const Duration(seconds: 3127))
            .add(const Duration(minutes: 1)),
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_session_upload',
        runAt: DateTime.now().toUtc(),
      );

      final manifestItems = List<ProgressSyncManifestItem>.generate(3127, (
        index,
      ) {
        final updatedAt = baseUpdatedAt.add(Duration(seconds: index));
        return ProgressSyncManifestItem(
          studentUserId: remoteStudentId,
          courseId: 191,
          kpKey: '2.1.$index',
          updatedAt: updatedAt.toUtc().toIso8601String(),
          envelopeHash: 'row-hash-$index',
        );
      });

      var manifestCalls = 0;
      var fetchCalls = 0;
      final api = _TestSessionSyncApiService(
        secureStorage: secureStorage,
        sessionItems: const <SessionSyncItem>[],
        progressItems: const <ProgressSyncItem>[],
        downloadManifestHandler: (
            {bool includeProgress = false, String? ifNoneMatch}) {
          manifestCalls++;
          expect(includeProgress, isTrue);
          return SyncDownloadManifestResult(
            sessions: const <SessionSyncManifestItem>[],
            progressChunks: const <ProgressSyncChunkManifestItem>[],
            progressRows: manifestItems,
            etag: 'progress-manifest',
            notModified: false,
          );
        },
        fetchDownloadPayloadHandler: (request) async {
          fetchCalls++;
          return SyncDownloadFetchResult(
            sessions: const <SessionSyncItem>[],
            progressChunks: const <ProgressSyncChunkItem>[],
            progressRows: const <ProgressSyncItem>[],
          );
        },
      );
      final userKeyService = UserKeyService(
        secureStorage: secureStorage,
        api: api,
        crypto: crypto,
      );
      final syncService = SessionSyncService(
        db: db,
        secureStorage: secureStorage,
        api: api,
        userKeyService: userKeyService,
        crypto: crypto,
      );

      final stopwatch = Stopwatch()..start();
      await syncService.syncIfReady(currentUser: student);
      stopwatch.stop();

      expect(manifestCalls, equals(1));
      expect(fetchCalls, equals(0));
      expect(stopwatch.elapsed.inMilliseconds, lessThan(2000));
      final progressRows = await db.getProgressForCourse(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );
      expect(progressRows, hasLength(3127));
      expect(api.uploadedProgressChunkEntries, isEmpty);
      expect(api.uploadedProgressEntries, isEmpty);
    },
  );

  test(
    'local sync mock: one changed session uploads quickly with large unchanged session set',
    () async {
      final crypto = SessionCryptoService();
      final secureStorage = _MemorySecureStorage(accessToken: 'token');

      final teacherId = await db.createUser(
        username: 'teacher_one_session_change',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 912,
      );
      final studentId = await db.createUser(
        username: 'student_one_session_change',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 3012,
      );
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'SessionPerf',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\session_perf',
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 192,
      );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);
      final remoteStudentId = student!.remoteUserId!;

      final studentKeyPair = await crypto.generateKeyPair();
      final studentPublicKey = await crypto.extractPublicKey(studentKeyPair);
      await secureStorage.writeUserPrivateKey(
        remoteStudentId,
        await crypto.encodePrivateKey(studentKeyPair),
      );
      await secureStorage.writeUserPublicKey(
        remoteStudentId,
        crypto.encodePublicKey(studentPublicKey),
      );
      final teacherKeyPair = await crypto.generateKeyPair();
      final teacherPublicKey = await crypto.extractPublicKey(teacherKeyPair);

      final unchangedTime = DateTime.parse('2026-03-02T15:00:00Z');
      for (var i = 0; i < 3127; i++) {
        await db.into(db.chatSessions).insert(
              ChatSessionsCompanion.insert(
                studentId: studentId,
                courseVersionId: courseVersionId,
                kpKey: '3.1.$i',
                title: Value('Session $i'),
                status: const Value('active'),
                startedAt: Value(unchangedTime.add(Duration(seconds: i))),
                syncId: Value('session-perf-$i'),
                syncUpdatedAt: Value(unchangedTime.add(Duration(seconds: i))),
                syncUploadedAt: Value(unchangedTime.add(Duration(seconds: i))),
              ),
            );
      }

      final changedSessionUpdatedAt = DateTime.parse('2026-03-02T16:30:00Z');
      final changedSessionId = await db.into(db.chatSessions).insert(
            ChatSessionsCompanion.insert(
              studentId: studentId,
              courseVersionId: courseVersionId,
              kpKey: '3.2.1',
              title: const Value('Changed Session'),
              status: const Value('active'),
              startedAt: Value(changedSessionUpdatedAt),
              syncId: const Value('session-perf-changed'),
              syncUpdatedAt: Value(changedSessionUpdatedAt),
              syncUploadedAt: Value(
                  changedSessionUpdatedAt.subtract(const Duration(hours: 2))),
            ),
          );
      await db.into(db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: changedSessionId,
              role: 'assistant',
              content: 'changed session payload',
              createdAt: Value(changedSessionUpdatedAt),
            ),
          );

      final nowUtc = DateTime.now().toUtc();
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_session_download',
        runAt: nowUtc,
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_progress_download',
        runAt: nowUtc,
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: remoteStudentId,
        domain: 'session_sync_run_progress_upload',
        runAt: nowUtc,
      );

      final api = _TestSessionSyncApiService(
        secureStorage: secureStorage,
        sessionItems: const <SessionSyncItem>[],
        progressItems: const <ProgressSyncItem>[],
        courseKeysByCourse: <int, CourseKeyBundle>{
          192: CourseKeyBundle(
            courseId: 192,
            teacherUserId: 912,
            teacherPublicKey: crypto.encodePublicKey(teacherPublicKey),
            studentUserId: remoteStudentId,
            studentPublicKey: crypto.encodePublicKey(studentPublicKey),
          ),
        },
      );
      final userKeyService = UserKeyService(
        secureStorage: secureStorage,
        api: api,
        crypto: crypto,
      );
      final syncService = SessionSyncService(
        db: db,
        secureStorage: secureStorage,
        api: api,
        userKeyService: userKeyService,
        crypto: crypto,
      );

      final stopwatch = Stopwatch()..start();
      await syncService.syncIfReady(currentUser: student);
      stopwatch.stop();

      print(
          'one_changed_session_elapsed_ms=${stopwatch.elapsed.inMilliseconds}');
      expect(stopwatch.elapsed.inMilliseconds, lessThan(1000));
      expect(api.uploadedSessions, hasLength(1));
      expect(
        api.uploadedSessions.single['session_sync_id'],
        equals('session-perf-changed'),
      );
      final changedSession = await db.getSession(changedSessionId);
      expect(changedSession, isNotNull);
      expect(
        changedSession!.syncUploadedAt!.toUtc(),
        equals(changedSessionUpdatedAt.toUtc()),
      );
    },
  );

  test(
    'force pull from server replaces local student data without uploads',
    () async {
      final crypto = SessionCryptoService();
      final secureStorage = _MemorySecureStorage(accessToken: 'token');

      final teacherId = await db.createUser(
        username: 'teacher_force_pull',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 904,
      );
      final studentId = await db.createUser(
        username: 'student_force_pull',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 3004,
      );
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Biology',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\biology',
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 130,
      );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);
      final remoteStudentId = student!.remoteUserId!;

      final studentKeyPair = await crypto.generateKeyPair();
      final studentPublicKey = await crypto.extractPublicKey(studentKeyPair);
      await secureStorage.writeUserPrivateKey(
        remoteStudentId,
        await crypto.encodePrivateKey(studentKeyPair),
      );
      await secureStorage.writeUserPublicKey(
        remoteStudentId,
        crypto.encodePublicKey(studentPublicKey),
      );

      final localSessionId = await db.into(db.chatSessions).insert(
            ChatSessionsCompanion.insert(
              studentId: studentId,
              courseVersionId: courseVersionId,
              kpKey: '1.1',
              title: const Value('Local Session'),
              status: const Value('active'),
              startedAt: Value(DateTime.parse('2026-03-02T09:00:00Z')),
              syncId: const Value('local-force-session'),
              syncUpdatedAt: Value(DateTime.parse('2026-03-02T09:00:00Z')),
              syncUploadedAt: Value(DateTime.parse('2026-03-02T09:00:00Z')),
            ),
          );
      await db.into(db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: localSessionId,
              role: 'assistant',
              content: 'LOCAL_MESSAGE',
              createdAt: Value(DateTime.parse('2026-03-02T09:00:10Z')),
            ),
          );
      await db.upsertProgressFromSync(
        studentId: studentId,
        courseVersionId: courseVersionId,
        kpKey: '1.1',
        lit: true,
        litPercent: 100,
        questionLevel: 'hard',
        summaryText: 'local progress',
        summaryRawResponse: '',
        summaryValid: true,
        updatedAt: DateTime.parse('2026-03-02T09:10:00Z'),
      );

      final remoteSessionPayload = <String, dynamic>{
        'version': 1,
        'session_sync_id': 'server-force-session',
        'course_id': 130,
        'course_subject': 'Biology',
        'kp_key': '1.1',
        'kp_title': 'Cell',
        'session_title': 'Server Session',
        'started_at': '2026-03-01T08:00:00Z',
        'ended_at': null,
        'summary_text': 'server summary',
        'student_remote_user_id': remoteStudentId,
        'student_username': student.username,
        'teacher_remote_user_id': 904,
        'updated_at': '2026-03-01T08:05:00Z',
        'messages': <Map<String, String>>[
          <String, String>{
            'role': 'assistant',
            'content': 'SERVER_MESSAGE',
            'created_at': '2026-03-01T08:00:10Z',
          },
        ],
      };
      final remoteSessionEnvelope = await _encryptForUser(
        crypto: crypto,
        payload: remoteSessionPayload,
        recipientUserId: remoteStudentId,
        recipientPublicKey: studentPublicKey,
      );
      final remoteSessionItem = SessionSyncItem(
        cursorId: 51,
        sessionSyncId: 'server-force-session',
        courseId: 130,
        teacherUserId: 904,
        studentUserId: remoteStudentId,
        senderUserId: remoteStudentId,
        updatedAt: '2026-03-01T08:05:00Z',
        envelope: remoteSessionEnvelope.base64Envelope,
        envelopeHash: remoteSessionEnvelope.hash,
      );

      final remoteProgressPayload = <String, dynamic>{
        'version': 1,
        'course_id': 130,
        'course_subject': 'Biology',
        'kp_key': '1.1',
        'lit': true,
        'lit_percent': 66,
        'question_level': 'medium',
        'summary_text': 'server progress',
        'summary_raw_response': '',
        'summary_valid': true,
        'teacher_remote_user_id': 904,
        'student_remote_user_id': remoteStudentId,
        'updated_at': '2026-03-01T08:06:00Z',
      };
      final remoteProgressEnvelope = await _encryptForUser(
        crypto: crypto,
        payload: remoteProgressPayload,
        recipientUserId: remoteStudentId,
        recipientPublicKey: studentPublicKey,
      );
      final remoteProgressItem = ProgressSyncItem(
        cursorId: 61,
        courseId: 130,
        courseSubject: 'Biology',
        teacherUserId: 904,
        studentUserId: remoteStudentId,
        kpKey: '1.1',
        lit: true,
        litPercent: 66,
        questionLevel: 'medium',
        summaryText: 'server progress',
        summaryRawResponse: '',
        summaryValid: true,
        updatedAt: '2026-03-01T08:06:00Z',
        envelope: remoteProgressEnvelope.base64Envelope,
        envelopeHash: remoteProgressEnvelope.hash,
      );

      final api = _TestSessionSyncApiService(
        secureStorage: secureStorage,
        sessionItems: <SessionSyncItem>[remoteSessionItem],
        progressItems: <ProgressSyncItem>[remoteProgressItem],
      );
      final userKeyService = UserKeyService(
        secureStorage: secureStorage,
        api: api,
        crypto: crypto,
      );
      final syncService = SessionSyncService(
        db: db,
        secureStorage: secureStorage,
        api: api,
        userKeyService: userKeyService,
        crypto: crypto,
      );

      await syncService.forcePullFromServer(
        currentUser: student,
        wipeLocalStudentData: true,
      );

      final sessions = await db.getSessionsForStudent(studentId);
      expect(sessions, hasLength(1));
      final imported = await db.getSession(sessions.single.sessionId);
      expect(imported, isNotNull);
      expect(imported!.syncId, equals('server-force-session'));
      final messages = await db.getMessagesForSession(imported.id);
      expect(messages, hasLength(1));
      expect(messages.single.content, equals('SERVER_MESSAGE'));

      final progressRows = await db.getProgressForCourse(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );
      expect(progressRows, hasLength(1));
      expect(progressRows.single.litPercent, equals(66));

      expect(api.uploadedProgressEntries, isEmpty);
      expect(api.uploadedSessions, isEmpty);
    },
  );
}
