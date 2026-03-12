import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/app_database.dart';

class SessionUploadCacheMessage {
  SessionUploadCacheMessage({
    required this.role,
    required this.content,
    required this.rawContent,
    required this.parsedJson,
    required this.action,
    required this.createdAt,
  });

  final String role;
  final String content;
  final String? rawContent;
  final String? parsedJson;
  final String? action;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'raw_content': rawContent,
        'parsed_json': parsedJson,
        'action': action,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory SessionUploadCacheMessage.fromJson(Map<String, dynamic> json) {
    return SessionUploadCacheMessage(
      role: (json['role'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      rawContent: json['raw_content'] as String?,
      parsedJson: json['parsed_json'] as String?,
      action: json['action'] as String?,
      createdAt:
          DateTime.tryParse((json['created_at'] as String?) ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
    );
  }
}

class SessionUploadCacheSnapshot {
  SessionUploadCacheSnapshot({
    required this.sessionId,
    required this.syncId,
    required this.syncUpdatedAt,
    required this.courseVersionId,
    required this.courseSubject,
    required this.kpKey,
    required this.kpTitle,
    required this.sessionTitle,
    required this.startedAt,
    required this.endedAt,
    required this.summaryText,
    required this.controlStateJson,
    required this.controlStateUpdatedAt,
    required this.evidenceStateJson,
    required this.evidenceStateUpdatedAt,
    required this.messages,
  });

  final int sessionId;
  final String syncId;
  final DateTime syncUpdatedAt;
  final int courseVersionId;
  final String courseSubject;
  final String kpKey;
  final String kpTitle;
  final String sessionTitle;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String summaryText;
  final String controlStateJson;
  final DateTime? controlStateUpdatedAt;
  final String evidenceStateJson;
  final DateTime? evidenceStateUpdatedAt;
  final List<SessionUploadCacheMessage> messages;

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'sync_id': syncId,
        'sync_updated_at': syncUpdatedAt.toUtc().toIso8601String(),
        'course_version_id': courseVersionId,
        'course_subject': courseSubject,
        'kp_key': kpKey,
        'kp_title': kpTitle,
        'session_title': sessionTitle,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt?.toUtc().toIso8601String(),
        'summary_text': summaryText,
        'control_state_json': controlStateJson,
        'control_state_updated_at':
            controlStateUpdatedAt?.toUtc().toIso8601String(),
        'evidence_state_json': evidenceStateJson,
        'evidence_state_updated_at':
            evidenceStateUpdatedAt?.toUtc().toIso8601String(),
        'messages': messages.map((message) => message.toJson()).toList(),
      };

  factory SessionUploadCacheSnapshot.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    final messages = rawMessages is List
        ? rawMessages
            .whereType<Map<String, dynamic>>()
            .map(SessionUploadCacheMessage.fromJson)
            .toList()
        : <SessionUploadCacheMessage>[];
    return SessionUploadCacheSnapshot(
      sessionId: (json['session_id'] as num?)?.toInt() ?? 0,
      syncId: (json['sync_id'] as String?) ?? '',
      syncUpdatedAt:
          DateTime.tryParse((json['sync_updated_at'] as String?) ?? '')
                  ?.toUtc() ??
              DateTime.now().toUtc(),
      courseVersionId: (json['course_version_id'] as num?)?.toInt() ?? 0,
      courseSubject: (json['course_subject'] as String?) ?? '',
      kpKey: (json['kp_key'] as String?) ?? '',
      kpTitle: (json['kp_title'] as String?) ?? '',
      sessionTitle: (json['session_title'] as String?) ?? '',
      startedAt:
          DateTime.tryParse((json['started_at'] as String?) ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      endedAt: DateTime.tryParse((json['ended_at'] as String?) ?? '')?.toUtc(),
      summaryText: (json['summary_text'] as String?) ?? '',
      controlStateJson: (json['control_state_json'] as String?) ?? '',
      controlStateUpdatedAt: DateTime.tryParse(
        (json['control_state_updated_at'] as String?) ?? '',
      )?.toUtc(),
      evidenceStateJson: (json['evidence_state_json'] as String?) ?? '',
      evidenceStateUpdatedAt: DateTime.tryParse(
        (json['evidence_state_updated_at'] as String?) ?? '',
      )?.toUtc(),
      messages: messages,
    );
  }
}

class SessionUploadCacheService {
  SessionUploadCacheService({
    required AppDatabase db,
    Future<Directory> Function()? cacheRootProvider,
  })  : _db = db,
        _cacheRootProvider = cacheRootProvider;

  final AppDatabase _db;
  final Future<Directory> Function()? _cacheRootProvider;

  Future<void> captureSession(int sessionId) async {
    if (sessionId <= 0) {
      throw StateError('Session id must be positive.');
    }
    final session = await _db.getSession(sessionId);
    if (session == null) {
      await deleteSession(sessionId);
      return;
    }
    final syncId = (session.syncId ?? '').trim();
    if (syncId.isEmpty) {
      throw StateError('Session sync id is missing for session $sessionId.');
    }
    final updatedAt = (session.syncUpdatedAt ?? session.startedAt).toUtc();
    final courseVersion =
        await _db.getCourseVersionById(session.courseVersionId);
    if (courseVersion == null) {
      throw StateError(
        'Course version ${session.courseVersionId} is missing for session '
        '$sessionId.',
      );
    }
    final node = await _db.getCourseNodeByKey(
      session.courseVersionId,
      session.kpKey,
    );
    final messages = await _db.getMessagesForSession(sessionId);
    final snapshot = SessionUploadCacheSnapshot(
      sessionId: session.id,
      syncId: syncId,
      syncUpdatedAt: updatedAt,
      courseVersionId: courseVersion.id,
      courseSubject: courseVersion.subject,
      kpKey: session.kpKey,
      kpTitle: node?.title ?? '',
      sessionTitle: session.title ?? '',
      startedAt: session.startedAt.toUtc(),
      endedAt: session.endedAt?.toUtc(),
      summaryText: session.summaryText ?? '',
      controlStateJson: session.controlStateJson ?? '',
      controlStateUpdatedAt: session.controlStateUpdatedAt?.toUtc(),
      evidenceStateJson: session.evidenceStateJson ?? '',
      evidenceStateUpdatedAt: session.evidenceStateUpdatedAt?.toUtc(),
      messages: messages
          .map(
            (message) => SessionUploadCacheMessage(
              role: message.role,
              content: message.content,
              rawContent: message.rawContent,
              parsedJson: message.parsedJson,
              action: message.action,
              createdAt: message.createdAt.toUtc(),
            ),
          )
          .toList(growable: false),
    );
    final file = await _resolveSessionFile(sessionId);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(snapshot.toJson()),
      encoding: utf8,
    );
  }

  Future<SessionUploadCacheSnapshot?> readSession({
    required int sessionId,
    required DateTime syncUpdatedAt,
  }) async {
    final file = await _resolveSessionFile(sessionId);
    if (!file.existsSync()) {
      return null;
    }
    final decoded = jsonDecode(await file.readAsString(encoding: utf8));
    if (decoded is! Map<String, dynamic>) {
      throw StateError(
          'Session upload cache is invalid for session $sessionId.');
    }
    final snapshot = SessionUploadCacheSnapshot.fromJson(decoded);
    if (snapshot.syncUpdatedAt.toUtc() != syncUpdatedAt.toUtc()) {
      return null;
    }
    return snapshot;
  }

  Future<void> deleteSession(int sessionId) async {
    final file = await _resolveSessionFile(sessionId);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<File> _resolveSessionFile(int sessionId) async {
    final root = await _resolveRoot();
    return File(p.join(root.path, 'session_$sessionId.json'));
  }

  Future<Directory> _resolveRoot() async {
    if (_cacheRootProvider != null) {
      final root = await _cacheRootProvider();
      if (!root.existsSync()) {
        root.createSync(recursive: true);
      }
      return root;
    }
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'sync_artifacts', 'sessions'));
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }
    return root;
  }
}
