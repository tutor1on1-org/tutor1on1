import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:family_teacher/db/app_database.dart';
import 'package:family_teacher/services/secure_storage_service.dart';
import 'package:family_teacher/services/session_crypto_service.dart';
import 'package:family_teacher/services/session_sync_api_service.dart';
import 'package:family_teacher/services/session_sync_service.dart';
import 'package:family_teacher/services/user_key_service.dart';

class _MemorySecureStorage extends SecureStorageService {
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
  }) : super(
          secureStorage: secureStorage,
          baseUrl: 'https://example.com',
          client: MockClient(
            (_) async => http.Response('[]', 200),
          ),
        );

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
  final List<ProgressUploadEntry> uploadedProgressEntries =
      <ProgressUploadEntry>[];
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
  Future<void> uploadProgressBatch(List<ProgressUploadEntry> entries) async {
    uploadedProgressEntries.addAll(entries);
  }

  @override
  Future<void> uploadSession({
    required String sessionSyncId,
    required int courseId,
    required int studentUserId,
    required String updatedAt,
    required String envelope,
    String? envelopeHash,
  }) async {
    uploadedSessions.add(<String, dynamic>{
      'session_sync_id': sessionSyncId,
      'course_id': courseId,
      'student_user_id': studentUserId,
      'updated_at': updatedAt,
      'envelope': envelope,
      'envelope_hash': envelopeHash ?? '',
    });
  }

  @override
  Future<CourseKeyBundle> getCourseKeys({
    required int courseId,
    required int studentUserId,
  }) async {
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
    'session download drains paginated deltas in one sync run',
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

      final firstPage = List<SessionSyncItem>.generate(500, (index) {
        final cursorId = index + 1;
        return SessionSyncItem(
          cursorId: cursorId,
          sessionSyncId: '',
          courseId: 140,
          teacherUserId: 905,
          studentUserId: remoteStudentId,
          senderUserId: remoteStudentId,
          updatedAt: '2026-03-01T08:00:00Z',
          envelope: '',
          envelopeHash: '',
        );
      });

      var sessionListCalls = 0;
      String? secondSince;
      int? secondSinceId;
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
          sessionListCalls++;
          if (sessionListCalls == 1) {
            expect((since ?? '').trim(), isEmpty);
            expect(sinceId == null || sinceId == 0, isTrue);
            expect(limit, equals(500));
            return SyncListResult<SessionSyncItem>(
              items: firstPage,
              etag: 'session-page-1',
              notModified: false,
            );
          }
          secondSince = since;
          secondSinceId = sinceId;
          expect(limit, equals(500));
          return SyncListResult<SessionSyncItem>(
            items: const <SessionSyncItem>[],
            etag: 'session-page-2',
            notModified: false,
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
            etag: 'progress-empty',
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

      expect(sessionListCalls, equals(2));
      expect(secondSince, equals('2026-03-01T08:00:00.000Z'));
      expect(secondSinceId, equals(500));
      expect(
        await secureStorage.readSessionSyncCursor(remoteStudentId),
        equals('2026-03-01T08:00:00.000Z|500'),
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
