import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../constants.dart';
import '../db/app_database.dart';
import '../security/pin_hasher.dart';
import 'secure_storage_service.dart';
import 'session_crypto_service.dart';
import 'session_sync_api_service.dart';
import 'user_key_service.dart';

class SessionSyncService {
  SessionSyncService({
    required AppDatabase db,
    required SecureStorageService secureStorage,
    required SessionSyncApiService api,
    required UserKeyService userKeyService,
    SessionCryptoService? crypto,
  })  : _db = db,
        _secureStorage = secureStorage,
        _api = api,
        _userKeyService = userKeyService,
        _crypto = crypto ?? SessionCryptoService();

  final AppDatabase _db;
  final SecureStorageService _secureStorage;
  final SessionSyncApiService _api;
  final UserKeyService _userKeyService;
  final SessionCryptoService _crypto;
  static final Uuid _uuid = Uuid();
  static final RegExp _versionSuffixPattern = RegExp(r'_(\d{10,})$');
  bool _syncing = false;

  Future<void> syncNow({
    required User currentUser,
    required String password,
  }) async {
    if (_syncing) {
      return;
    }
    _syncing = true;
    try {
      final remoteUserId = _requireRemoteUserId(currentUser);
      final keyPair = await _userKeyService.ensureUserKeyPair(
        remoteUserId: remoteUserId,
        password: password,
      );
      await _syncInternal(currentUser, remoteUserId, keyPair);
    } finally {
      _syncing = false;
    }
  }

  Future<void> syncIfReady({required User currentUser}) async {
    if (_syncing) {
      return;
    }
    final remoteUserId = currentUser.remoteUserId;
    if (remoteUserId == null || remoteUserId <= 0) {
      return;
    }
    final keyPair = await _userKeyService.tryLoadLocalKeyPair(remoteUserId);
    if (keyPair == null) {
      return;
    }
    _syncing = true;
    try {
      await _syncInternal(currentUser, remoteUserId, keyPair);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncInternal(
    User currentUser,
    int remoteUserId,
    SimpleKeyPair keyPair,
  ) async {
    await _uploadPendingProgress(currentUser, remoteUserId);
    await _uploadPendingSessions(currentUser, remoteUserId, keyPair);
    await _downloadSessions(currentUser, remoteUserId, keyPair);
    await _downloadProgress(currentUser, remoteUserId, keyPair);
  }

  Future<void> _uploadPendingProgress(
    User currentUser,
    int remoteUserId,
  ) async {
    if (currentUser.role != 'student') {
      return;
    }
    final entries = await (_db.select(_db.progressEntries)
          ..where((tbl) => tbl.studentId.equals(currentUser.id)))
        .get();
    if (entries.isEmpty) {
      return;
    }
    final keysByCourse = <int, CourseKeyBundle>{};
    final uploads = <ProgressUploadEntry>[];
    for (final entry in entries) {
      if (entry.kpKey == kTreeViewStateKpKey) {
        continue;
      }
      final remoteCourseId = await _db.getRemoteCourseId(entry.courseVersionId);
      if (remoteCourseId == null || remoteCourseId <= 0) {
        continue;
      }
      var resolvedKeys = keysByCourse[remoteCourseId];
      resolvedKeys ??= await _api.getCourseKeys(
        courseId: remoteCourseId,
        studentUserId: remoteUserId,
      );
      keysByCourse[remoteCourseId] = resolvedKeys;
      final payload = _buildProgressPayload(
        entry: entry,
        remoteCourseId: remoteCourseId,
        teacherUserId: resolvedKeys.teacherUserId,
        studentUserId: resolvedKeys.studentUserId,
      );
      final envelope = await _crypto.encryptPayload(
        payload: payload,
        recipients: [
          RecipientPublicKey(
            userId: resolvedKeys.teacherUserId,
            publicKey: _crypto.decodePublicKey(resolvedKeys.teacherPublicKey),
          ),
          RecipientPublicKey(
            userId: resolvedKeys.studentUserId,
            publicKey: _crypto.decodePublicKey(resolvedKeys.studentPublicKey),
          ),
        ],
      );
      final envelopeJson = jsonEncode(envelope.toJson());
      uploads.add(
        ProgressUploadEntry(
          courseId: remoteCourseId,
          kpKey: entry.kpKey,
          updatedAt: entry.updatedAt.toUtc().toIso8601String(),
          envelope: base64Encode(utf8.encode(envelopeJson)),
          envelopeHash: _hashEnvelope(envelopeJson),
        ),
      );
    }
    if (uploads.isEmpty) {
      return;
    }
    await _api.uploadProgressBatch(uploads);
  }

  Future<void> _uploadPendingSessions(
    User currentUser,
    int remoteUserId,
    SimpleKeyPair keyPair,
  ) async {
    final sessions = await (_db.select(_db.chatSessions)
          ..where((tbl) =>
              tbl.syncUpdatedAt.isNotNull() &
              (tbl.syncUploadedAt.isNull() |
                  tbl.syncUploadedAt.isSmallerThan(tbl.syncUpdatedAt))))
        .get();
    if (sessions.isEmpty) {
      return;
    }
    final keysByCourse = <int, CourseKeyBundle>{};
    for (final session in sessions) {
      if (session.studentId != currentUser.id) {
        continue;
      }
      final syncSession = await _ensureSessionSyncMeta(session);
      final remoteCourseId =
          await _db.getRemoteCourseId(syncSession.courseVersionId);
      if (remoteCourseId == null || remoteCourseId <= 0) {
        continue;
      }
      var resolvedKeys = keysByCourse[remoteCourseId];
      resolvedKeys ??= await _api.getCourseKeys(
        courseId: remoteCourseId,
        studentUserId: remoteUserId,
      );
      keysByCourse[remoteCourseId] = resolvedKeys;
      final courseVersion =
          await _db.getCourseVersionById(syncSession.courseVersionId);
      if (courseVersion == null) {
        continue;
      }
      final node = await _db.getCourseNodeByKey(
          syncSession.courseVersionId, syncSession.kpKey);
      final messages = await _db.getMessagesForSession(syncSession.id);
      final payload = _buildPayload(
        session: syncSession,
        courseVersion: courseVersion,
        node: node,
        messages: messages,
        remoteCourseId: remoteCourseId,
        teacherUserId: resolvedKeys.teacherUserId,
        studentUserId: resolvedKeys.studentUserId,
        studentUsername: currentUser.username,
        updatedAt: syncSession.syncUpdatedAt ?? DateTime.now(),
      );
      final envelope = await _crypto.encryptPayload(
        payload: payload,
        recipients: [
          RecipientPublicKey(
            userId: resolvedKeys.teacherUserId,
            publicKey: _crypto.decodePublicKey(resolvedKeys.teacherPublicKey),
          ),
          RecipientPublicKey(
            userId: resolvedKeys.studentUserId,
            publicKey: _crypto.decodePublicKey(resolvedKeys.studentPublicKey),
          ),
        ],
      );
      final envelopeJson = jsonEncode(envelope.toJson());
      final envelopeBase64 = base64Encode(utf8.encode(envelopeJson));
      await _api.uploadSession(
        sessionSyncId: payload['session_sync_id'] as String,
        courseId: remoteCourseId,
        studentUserId: resolvedKeys.studentUserId,
        updatedAt: (payload['updated_at'] as String?) ??
            DateTime.now().toUtc().toIso8601String(),
        envelope: envelopeBase64,
        envelopeHash: _hashEnvelope(envelopeJson),
      );
      await (_db.update(_db.chatSessions)
            ..where((tbl) => tbl.id.equals(syncSession.id)))
          .write(
        ChatSessionsCompanion(
          syncUploadedAt: Value(syncSession.syncUpdatedAt ?? DateTime.now()),
        ),
      );
    }
  }

  Future<void> _downloadSessions(
    User currentUser,
    int remoteUserId,
    SimpleKeyPair keyPair,
  ) async {
    final cursor = await _secureStorage.readSessionSyncCursor(remoteUserId);
    final items = await _api.listSessions(since: cursor);
    if (items.isEmpty) {
      return;
    }
    DateTime? latest;
    for (final item in items) {
      final payload = await _decryptItem(item, remoteUserId, keyPair);
      await _importPayload(currentUser, payload);
      final updatedAt =
          DateTime.tryParse(payload['updated_at'] as String? ?? '');
      if (updatedAt != null) {
        if (latest == null || updatedAt.isAfter(latest)) {
          latest = updatedAt;
        }
      }
    }
    if (latest != null) {
      await _secureStorage.writeSessionSyncCursor(
        remoteUserId,
        latest.toUtc().toIso8601String(),
      );
    }
  }

  Future<void> _downloadProgress(
    User currentUser,
    int remoteUserId,
    SimpleKeyPair keyPair,
  ) async {
    if (currentUser.role != 'student') {
      return;
    }
    final cursor = await _secureStorage.readProgressSyncCursor(remoteUserId);
    final items = await _api.listProgress(since: cursor);
    if (items.isEmpty) {
      return;
    }
    DateTime? latest;
    for (final item in items) {
      final resolved = await _resolveProgressPayload(
        item: item,
        remoteUserId: remoteUserId,
        keyPair: keyPair,
      );
      var courseVersionId =
          await _db.getCourseVersionIdForRemoteCourse(resolved.courseId);
      if (courseVersionId == null) {
        courseVersionId = await _db.createCourseVersion(
          teacherId: currentUser.id,
          subject: resolved.courseSubject.trim().isEmpty
              ? 'Course'
              : resolved.courseSubject.trim(),
          granularity: 1,
          textbookText: '',
          sourcePath: null,
        );
        await _db.upsertCourseRemoteLink(
          courseVersionId: courseVersionId,
          remoteCourseId: resolved.courseId,
        );
      }
      await _db.assignStudent(
        studentId: currentUser.id,
        courseVersionId: courseVersionId,
      );
      final updatedAt = DateTime.tryParse(resolved.updatedAt) ?? DateTime.now();
      await _db.upsertProgressFromSync(
        studentId: currentUser.id,
        courseVersionId: courseVersionId,
        kpKey: resolved.kpKey,
        lit: resolved.lit,
        litPercent: resolved.litPercent,
        questionLevel:
            resolved.questionLevel.isEmpty ? null : resolved.questionLevel,
        summaryText: resolved.summaryText.isEmpty ? null : resolved.summaryText,
        summaryRawResponse: resolved.summaryRawResponse.isEmpty
            ? null
            : resolved.summaryRawResponse,
        summaryValid: resolved.summaryValid,
        updatedAt: updatedAt,
      );
      if (latest == null || updatedAt.isAfter(latest)) {
        latest = updatedAt;
      }
    }
    if (latest != null) {
      await _secureStorage.writeProgressSyncCursor(
        remoteUserId,
        latest.toUtc().toIso8601String(),
      );
    }
  }

  Future<Map<String, dynamic>> _decryptItem(
    SessionSyncItem item,
    int remoteUserId,
    SimpleKeyPair keyPair,
  ) async {
    if (item.envelope.trim().isEmpty) {
      throw StateError('Session sync envelope missing.');
    }
    final envelopeJson = utf8.decode(base64Decode(item.envelope));
    if (item.envelopeHash.trim().isNotEmpty) {
      final computed = _hashEnvelope(envelopeJson);
      if (computed != item.envelopeHash.trim()) {
        throw StateError('Session sync envelope hash mismatch.');
      }
    }
    final decoded = jsonDecode(envelopeJson);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Session sync envelope invalid.');
    }
    final envelope = EncryptedEnvelope.fromJson(decoded);
    return _crypto.decryptEnvelope(
      envelope: envelope,
      userKeyPair: keyPair,
      userId: remoteUserId,
    );
  }

  Future<void> _importPayload(
    User currentUser,
    Map<String, dynamic> payload,
  ) async {
    final sessionSyncId = (payload['session_sync_id'] as String?) ?? '';
    if (sessionSyncId.trim().isEmpty) {
      throw StateError('Session sync id missing.');
    }
    final courseId = (payload['course_id'] as num?)?.toInt() ?? 0;
    final studentRemoteId =
        (payload['student_remote_user_id'] as num?)?.toInt() ?? 0;
    final studentUsername = (payload['student_username'] as String?)?.trim();
    final courseSubject = (payload['course_subject'] as String?)?.trim() ?? '';
    final kpKey = (payload['kp_key'] as String?)?.trim() ?? '';
    final kpTitle = (payload['kp_title'] as String?)?.trim();
    final title = (payload['session_title'] as String?)?.trim();
    final summary = (payload['summary_text'] as String?)?.trim();
    final startedAt = DateTime.tryParse(payload['started_at'] as String? ?? '');
    final endedAt = DateTime.tryParse(payload['ended_at'] as String? ?? '');
    final updatedAt =
        DateTime.tryParse(payload['updated_at'] as String? ?? '') ??
            DateTime.now();
    final messages = _parseMessages(payload['messages']);
    if (courseId <= 0 || studentRemoteId <= 0) {
      throw StateError('Session payload missing course or student id.');
    }

    final localStudentId = await _resolveLocalStudentId(
      currentUser: currentUser,
      studentRemoteId: studentRemoteId,
      studentUsername: studentUsername,
    );

    var courseVersionId = await _db.getCourseVersionIdForRemoteCourse(courseId);
    if (courseVersionId == null) {
      courseVersionId = await _findLocalCourseVersionBySubject(
        teacherId: currentUser.id,
        subject: courseSubject,
      );
    }
    if (courseVersionId == null) {
      courseVersionId = await _db.createCourseVersion(
        teacherId: currentUser.id,
        subject: courseSubject.isNotEmpty ? courseSubject : 'Course',
        granularity: 1,
        textbookText: '',
        sourcePath: null,
      );
    }
    await _db.upsertCourseRemoteLink(
      courseVersionId: courseVersionId,
      remoteCourseId: courseId,
    );
    if (courseSubject.isNotEmpty) {
      await _ensureCourseSubject(
        courseVersionId: courseVersionId,
        expectedSubject: courseSubject,
      );
    }
    if (kpKey.isNotEmpty) {
      final existingNode = await _db.getCourseNodeByKey(courseVersionId, kpKey);
      if (existingNode == null) {
        await _db.into(_db.courseNodes).insert(
              CourseNodesCompanion.insert(
                courseVersionId: courseVersionId,
                kpKey: kpKey,
                title: kpTitle ?? kpKey,
                description: kpTitle ?? kpKey,
                orderIndex: 0,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    }

    if (currentUser.role == 'student') {
      await _db.assignStudent(
        studentId: localStudentId,
        courseVersionId: courseVersionId,
      );
    }

    final existing = await (_db.select(_db.chatSessions)
          ..where((tbl) => tbl.syncId.equals(sessionSyncId)))
        .getSingleOrNull();
    await _db.transaction(() async {
      int sessionId;
      if (existing == null) {
        sessionId = await _db.into(_db.chatSessions).insert(
              ChatSessionsCompanion.insert(
                studentId: localStudentId,
                courseVersionId: courseVersionId!,
                kpKey: kpKey.isNotEmpty ? kpKey : 'session',
                title: Value(title),
                status: const Value('active'),
                startedAt: Value(startedAt ?? updatedAt),
                endedAt: Value(endedAt),
                summaryText: Value(summary),
                syncId: Value(sessionSyncId),
                syncUpdatedAt: Value(updatedAt),
                syncUploadedAt: Value(updatedAt),
              ),
            );
      } else {
        sessionId = existing.id;
        await (_db.update(_db.chatSessions)
              ..where((tbl) => tbl.id.equals(existing.id)))
            .write(
          ChatSessionsCompanion(
            studentId: Value(localStudentId),
            courseVersionId: Value(courseVersionId!),
            kpKey: Value(kpKey.isNotEmpty ? kpKey : existing.kpKey),
            title: Value(title),
            startedAt: Value(startedAt ?? existing.startedAt),
            endedAt: Value(endedAt),
            summaryText: Value(summary),
            syncUpdatedAt: Value(updatedAt),
            syncUploadedAt: Value(updatedAt),
          ),
        );
        await (_db.delete(_db.chatMessages)
              ..where((tbl) => tbl.sessionId.equals(existing.id)))
            .go();
      }

      for (final message in messages) {
        await _db.into(_db.chatMessages).insert(
              ChatMessagesCompanion.insert(
                sessionId: sessionId,
                role: message.role,
                content: message.content,
                createdAt: Value(message.createdAt),
              ),
            );
      }
    });
  }

  Future<int> _resolveLocalStudentId({
    required User currentUser,
    required int studentRemoteId,
    required String? studentUsername,
  }) async {
    if (currentUser.remoteUserId == studentRemoteId) {
      return currentUser.id;
    }
    final existing = await _db.findUserByRemoteId(studentRemoteId);
    if (existing != null) {
      return existing.id;
    }
    final username = (studentUsername ?? '').trim();
    final resolvedUsername =
        username.isNotEmpty ? username : 'student_$studentRemoteId';
    return _db.createUser(
      username: resolvedUsername,
      pinHash: PinHasher.hash('remote_user_placeholder'),
      role: 'student',
      teacherId: currentUser.role == 'teacher' ? currentUser.id : null,
      remoteUserId: studentRemoteId,
    );
  }

  List<_SyncMessage> _parseMessages(Object? raw) {
    if (raw is! List) {
      return [];
    }
    final messages = <_SyncMessage>[];
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final role = (entry['role'] as String?)?.trim();
      final content = (entry['content'] as String?)?.trim();
      if (role == null || role.isEmpty || content == null || content.isEmpty) {
        continue;
      }
      final createdAt =
          DateTime.tryParse(entry['created_at'] as String? ?? '') ??
              DateTime.now();
      messages.add(
        _SyncMessage(
          role: role,
          content: content,
          createdAt: createdAt,
        ),
      );
    }
    return messages;
  }

  Map<String, dynamic> _buildPayload({
    required ChatSession session,
    required CourseVersion courseVersion,
    required CourseNode? node,
    required List<ChatMessage> messages,
    required int remoteCourseId,
    required int teacherUserId,
    required int studentUserId,
    required String studentUsername,
    required DateTime updatedAt,
  }) {
    final syncId = session.syncId ?? _uuid.v4();
    return {
      'version': 1,
      'session_sync_id': syncId,
      'course_id': remoteCourseId,
      'course_subject': courseVersion.subject,
      'kp_key': session.kpKey,
      'kp_title': node?.title ?? '',
      'session_title': session.title ?? '',
      'started_at': session.startedAt.toUtc().toIso8601String(),
      'ended_at': session.endedAt?.toUtc().toIso8601String(),
      'summary_text': session.summaryText ?? '',
      'student_remote_user_id': studentUserId,
      'student_username': studentUsername,
      'teacher_remote_user_id': teacherUserId,
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'messages': messages
          .map(
            (message) => {
              'role': message.role,
              'content': message.content,
              'created_at': message.createdAt.toUtc().toIso8601String(),
            },
          )
          .toList(),
    };
  }

  Map<String, dynamic> _buildProgressPayload({
    required ProgressEntry entry,
    required int remoteCourseId,
    required int teacherUserId,
    required int studentUserId,
  }) {
    return {
      'version': 1,
      'course_id': remoteCourseId,
      'kp_key': entry.kpKey,
      'lit': entry.lit,
      'lit_percent': entry.litPercent,
      'question_level': entry.questionLevel ?? '',
      'summary_text': entry.summaryText ?? '',
      'summary_raw_response': entry.summaryRawResponse ?? '',
      'summary_valid': entry.summaryValid,
      'teacher_remote_user_id': teacherUserId,
      'student_remote_user_id': studentUserId,
      'updated_at': entry.updatedAt.toUtc().toIso8601String(),
    };
  }

  Future<_ResolvedProgressPayload> _resolveProgressPayload({
    required ProgressSyncItem item,
    required int remoteUserId,
    required SimpleKeyPair keyPair,
  }) async {
    if (item.studentUserId != remoteUserId) {
      throw StateError('Progress payload student mismatch.');
    }
    if (item.envelope.trim().isEmpty) {
      final kpKey = item.kpKey.trim();
      if (item.courseId <= 0 || kpKey.isEmpty) {
        throw StateError('Progress payload missing course_id or kp_key.');
      }
      return _ResolvedProgressPayload(
        courseId: item.courseId,
        courseSubject: item.courseSubject,
        kpKey: kpKey,
        lit: item.lit,
        litPercent: item.litPercent.clamp(0, 100).toInt(),
        questionLevel: item.questionLevel,
        summaryText: item.summaryText,
        summaryRawResponse: item.summaryRawResponse,
        summaryValid: item.summaryValid,
        updatedAt: item.updatedAt,
      );
    }

    final envelopeJson = utf8.decode(base64Decode(item.envelope));
    if (item.envelopeHash.trim().isNotEmpty) {
      final computed = _hashEnvelope(envelopeJson);
      if (computed != item.envelopeHash.trim()) {
        throw StateError('Progress sync envelope hash mismatch.');
      }
    }
    final decoded = jsonDecode(envelopeJson);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Progress sync envelope invalid.');
    }
    final envelope = EncryptedEnvelope.fromJson(decoded);
    final payload = await _crypto.decryptEnvelope(
      envelope: envelope,
      userKeyPair: keyPair,
      userId: remoteUserId,
    );

    final payloadStudentID = _parsePayloadInt(
      payload['student_remote_user_id'],
      field: 'student_remote_user_id',
    );
    if (payloadStudentID != remoteUserId) {
      throw StateError('Progress payload student mismatch.');
    }
    final litPercentRaw = _parsePayloadInt(
      payload['lit_percent'],
      field: 'lit_percent',
    );
    return _ResolvedProgressPayload(
      courseId: _parsePayloadInt(payload['course_id'], field: 'course_id'),
      courseSubject: _parsePayloadString(payload['course_subject'],
              field: 'course_subject')
          .trim(),
      kpKey: _parsePayloadString(payload['kp_key'], field: 'kp_key').trim(),
      lit: _parsePayloadBool(payload['lit'], field: 'lit'),
      litPercent: litPercentRaw.clamp(0, 100).toInt(),
      questionLevel: _parsePayloadString(payload['question_level'],
          field: 'question_level'),
      summaryText:
          _parsePayloadString(payload['summary_text'], field: 'summary_text'),
      summaryRawResponse: _parsePayloadString(
        payload['summary_raw_response'],
        field: 'summary_raw_response',
      ),
      summaryValid: _parsePayloadNullableBool(
        payload['summary_valid'],
        field: 'summary_valid',
      ),
      updatedAt:
          _parsePayloadString(payload['updated_at'], field: 'updated_at'),
    );
  }

  Future<ChatSession> _ensureSessionSyncMeta(ChatSession session) async {
    var syncId = session.syncId;
    var updatedAt = session.syncUpdatedAt;
    if (syncId == null || syncId.trim().isEmpty) {
      syncId = _uuid.v4();
    }
    if (updatedAt == null) {
      updatedAt = session.startedAt;
    }
    if (syncId != session.syncId || updatedAt != session.syncUpdatedAt) {
      await (_db.update(_db.chatSessions)
            ..where((tbl) => tbl.id.equals(session.id)))
          .write(
        ChatSessionsCompanion(
          syncId: Value(syncId),
          syncUpdatedAt: Value(updatedAt),
        ),
      );
      final refreshed = await _db.getSession(session.id);
      if (refreshed != null) {
        return refreshed;
      }
    }
    return session;
  }

  int _requireRemoteUserId(User user) {
    final remoteId = user.remoteUserId;
    if (remoteId == null || remoteId <= 0) {
      throw StateError('Remote user id missing.');
    }
    return remoteId;
  }

  String _hashEnvelope(String json) {
    final sum = sha256.convert(utf8.encode(json));
    return sum.toString();
  }

  int _parsePayloadInt(
    Object? value, {
    required String field,
  }) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
    throw StateError('Progress payload field "$field" invalid.');
  }

  bool _parsePayloadBool(
    Object? value, {
    required String field,
  }) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      if (value == 1) {
        return true;
      }
      if (value == 0) {
        return false;
      }
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    throw StateError('Progress payload field "$field" invalid.');
  }

  bool? _parsePayloadNullableBool(
    Object? value, {
    required String field,
  }) {
    if (value == null) {
      return null;
    }
    return _parsePayloadBool(value, field: field);
  }

  String _parsePayloadString(
    Object? value, {
    required String field,
  }) {
    if (value is String) {
      return value;
    }
    throw StateError('Progress payload field "$field" invalid.');
  }

  Future<int?> _findLocalCourseVersionBySubject({
    required int teacherId,
    required String subject,
  }) async {
    final normalizedTarget = _normalizeCourseName(_stripVersionSuffix(subject));
    if (normalizedTarget.isEmpty) {
      return null;
    }
    final courses = await _db.getCourseVersionsForTeacher(teacherId);
    for (final course in courses) {
      final normalizedCourse =
          _normalizeCourseName(_stripVersionSuffix(course.subject));
      if (normalizedCourse == normalizedTarget) {
        return course.id;
      }
    }
    return null;
  }

  Future<void> _ensureCourseSubject({
    required int courseVersionId,
    required String expectedSubject,
  }) async {
    final normalizedExpected = expectedSubject.trim();
    if (normalizedExpected.isEmpty) {
      return;
    }
    final course = await _db.getCourseVersionById(courseVersionId);
    if (course == null) {
      return;
    }
    if (course.subject.trim() == normalizedExpected) {
      return;
    }
    await _db.updateCourseVersionSubject(
      id: courseVersionId,
      subject: normalizedExpected,
    );
  }

  String _normalizeCourseName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _stripVersionSuffix(String value) {
    return value.trim().replaceFirst(_versionSuffixPattern, '');
  }
}

class _SyncMessage {
  _SyncMessage({
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String role;
  final String content;
  final DateTime createdAt;
}

class _ResolvedProgressPayload {
  _ResolvedProgressPayload({
    required this.courseId,
    required this.courseSubject,
    required this.kpKey,
    required this.lit,
    required this.litPercent,
    required this.questionLevel,
    required this.summaryText,
    required this.summaryRawResponse,
    required this.summaryValid,
    required this.updatedAt,
  });

  final int courseId;
  final String courseSubject;
  final String kpKey;
  final bool lit;
  final int litPercent;
  final String questionLevel;
  final String summaryText;
  final String summaryRawResponse;
  final bool? summaryValid;
  final String updatedAt;
}
