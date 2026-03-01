import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
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
  Future<String?> readProgressSyncCursor(int remoteUserId) async {
    return _progressCursorByRemote[remoteUserId];
  }

  @override
  Future<void> writeProgressSyncCursor(int remoteUserId, String value) async {
    _progressCursorByRemote[remoteUserId] = value.trim();
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
}

class _TestSessionSyncApiService extends SessionSyncApiService {
  _TestSessionSyncApiService({
    required SecureStorageService secureStorage,
    required this.sessionItems,
    required this.progressItems,
  }) : super(
          secureStorage: secureStorage,
          baseUrl: 'https://example.com',
          client: MockClient(
            (_) async => http.Response('[]', 200),
          ),
        );

  final List<SessionSyncItem> sessionItems;
  final List<ProgressSyncItem> progressItems;

  @override
  Future<SyncListResult<SessionSyncItem>> listSessionsDelta({
    String? since,
    int? sinceId,
    int? limit,
    String? ifNoneMatch,
  }) async {
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
    return SyncListResult<ProgressSyncItem>(
      items: progressItems,
      etag: 'progress-etag',
      notModified: false,
    );
  }

  @override
  Future<void> uploadProgressBatch(List<ProgressUploadEntry> entries) async {
    throw StateError('Unexpected uploadProgressBatch call in this test.');
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
    throw StateError('Unexpected uploadSession call in this test.');
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
}
