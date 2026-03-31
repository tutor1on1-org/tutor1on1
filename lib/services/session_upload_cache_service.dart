import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/app_database.dart';
import 'background_json_service.dart';
import 'sync_semantic_hash.dart';

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

class SessionUploadChapterMember {
  SessionUploadChapterMember({
    required this.sessionId,
    required this.syncId,
    required this.syncUpdatedAt,
    required this.payloadHash,
  });

  final int sessionId;
  final String syncId;
  final DateTime syncUpdatedAt;
  final String payloadHash;

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'sync_id': syncId,
        'sync_updated_at': syncUpdatedAt.toUtc().toIso8601String(),
        'payload_hash': payloadHash,
      };

  factory SessionUploadChapterMember.fromJson(Map<String, dynamic> json) {
    return SessionUploadChapterMember(
      sessionId: (json['session_id'] as num?)?.toInt() ?? 0,
      syncId: (json['sync_id'] as String?) ?? '',
      syncUpdatedAt:
          DateTime.tryParse((json['sync_updated_at'] as String?) ?? '')
                  ?.toUtc() ??
              DateTime.now().toUtc(),
      payloadHash: (json['payload_hash'] as String?) ?? '',
    );
  }
}

class SessionUploadChapterSnapshot {
  SessionUploadChapterSnapshot({
    required this.courseVersionId,
    required this.chapterKey,
    required this.updatedAt,
    required this.contentHash,
    required this.members,
  });

  final int courseVersionId;
  final String chapterKey;
  final DateTime updatedAt;
  final String contentHash;
  final List<SessionUploadChapterMember> members;

  Map<String, dynamic> toJson() => {
        'course_version_id': courseVersionId,
        'chapter_key': chapterKey,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'content_hash': contentHash,
        'members': members.map((member) => member.toJson()).toList(),
      };

  factory SessionUploadChapterSnapshot.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'];
    final members = rawMembers is List
        ? rawMembers
            .whereType<Map<String, dynamic>>()
            .map(SessionUploadChapterMember.fromJson)
            .toList()
        : <SessionUploadChapterMember>[];
    return SessionUploadChapterSnapshot(
      courseVersionId: (json['course_version_id'] as num?)?.toInt() ?? 0,
      chapterKey: (json['chapter_key'] as String?) ?? '',
      updatedAt:
          DateTime.tryParse((json['updated_at'] as String?) ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      contentHash: (json['content_hash'] as String?) ?? '',
      members: members,
    );
  }
}

class SessionUploadCacheService {
  SessionUploadCacheService({
    required AppDatabase db,
    Future<Directory> Function()? cacheRootProvider,
    BackgroundJsonService? backgroundJsonService,
  })  : _db = db,
        _cacheRootProvider = cacheRootProvider,
        _backgroundJsonService =
            backgroundJsonService ?? const BackgroundJsonService();

  final AppDatabase _db;
  final Future<Directory> Function()? _cacheRootProvider;
  final BackgroundJsonService _backgroundJsonService;
  static final RegExp _secondLevelChapterPattern = RegExp(r'^(\d+\.\d+)');

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
    await _upsertChapterSnapshot(snapshot);
  }

  Future<SessionUploadCacheSnapshot?> readSession({
    required int sessionId,
    required DateTime syncUpdatedAt,
  }) async {
    final file = await _resolveSessionFile(sessionId);
    if (!file.existsSync()) {
      return null;
    }
    final decoded = await _backgroundJsonService.decode(
      await file.readAsString(encoding: utf8),
    );
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
    SessionUploadCacheSnapshot? existingSnapshot;
    if (file.existsSync()) {
      final decoded = await _backgroundJsonService.decode(
        await file.readAsString(encoding: utf8),
      );
      if (decoded is! Map<String, dynamic>) {
        throw StateError(
          'Session upload cache is invalid for session $sessionId.',
        );
      }
      existingSnapshot = SessionUploadCacheSnapshot.fromJson(decoded);
    }
    if (file.existsSync()) {
      await file.delete();
    }
    if (existingSnapshot != null) {
      await _removeFromChapterSnapshot(existingSnapshot);
    }
  }

  Future<SessionUploadChapterSnapshot?> readChapter({
    required int courseVersionId,
    required String chapterKey,
  }) async {
    final file = await _resolveChapterFile(courseVersionId, chapterKey);
    if (!file.existsSync()) {
      return null;
    }
    final decoded = await _backgroundJsonService.decode(
      await file.readAsString(encoding: utf8),
    );
    if (decoded is! Map<String, dynamic>) {
      throw StateError(
        'Session upload chapter cache is invalid for courseVersionId='
        '$courseVersionId chapterKey="$chapterKey".',
      );
    }
    final snapshot = SessionUploadChapterSnapshot.fromJson(decoded);
    return _normalizeChapterSnapshot(snapshot);
  }

  Future<List<SessionUploadChapterSnapshot>> listChapters() async {
    final root = await _resolveChapterRoot();
    if (!root.existsSync()) {
      return const <SessionUploadChapterSnapshot>[];
    }
    final chapters = <SessionUploadChapterSnapshot>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }
      final decoded = await _backgroundJsonService.decode(
        await entity.readAsString(encoding: utf8),
      );
      if (decoded is! Map<String, dynamic>) {
        throw StateError(
          'Session upload chapter cache file is invalid: ${entity.path}',
        );
      }
      final snapshot = SessionUploadChapterSnapshot.fromJson(decoded);
      final normalized = await _normalizeChapterSnapshot(snapshot);
      if (normalized != null) {
        chapters.add(normalized);
      }
    }
    chapters.sort((left, right) {
      final courseCompare =
          left.courseVersionId.compareTo(right.courseVersionId);
      if (courseCompare != 0) {
        return courseCompare;
      }
      return left.chapterKey.compareTo(right.chapterKey);
    });
    return chapters;
  }

  Future<List<SessionUploadChapterSnapshot>> listChaptersForKeys(
    Iterable<String> courseChapterKeys,
  ) async {
    final chapters = <SessionUploadChapterSnapshot>[];
    final requested = courseChapterKeys.toSet();
    for (final rawKey in requested) {
      final separatorIndex = rawKey.indexOf(':');
      if (separatorIndex <= 0 || separatorIndex >= rawKey.length - 1) {
        continue;
      }
      final courseVersionId = int.tryParse(rawKey.substring(0, separatorIndex));
      if (courseVersionId == null || courseVersionId <= 0) {
        continue;
      }
      final chapterKey = rawKey.substring(separatorIndex + 1).trim();
      if (chapterKey.isEmpty) {
        continue;
      }
      final snapshot = await readChapter(
        courseVersionId: courseVersionId,
        chapterKey: chapterKey,
      );
      if (snapshot != null) {
        chapters.add(snapshot);
      }
    }
    chapters.sort((left, right) {
      final courseCompare =
          left.courseVersionId.compareTo(right.courseVersionId);
      if (courseCompare != 0) {
        return courseCompare;
      }
      return left.chapterKey.compareTo(right.chapterKey);
    });
    return chapters;
  }

  Future<File> _resolveSessionFile(int sessionId) async {
    final root = await _resolveSessionRoot();
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

  Future<Directory> _resolveSessionRoot() async {
    final root = await _resolveRoot();
    final dir = Directory(p.join(root.path, 'sessions'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<Directory> _resolveChapterRoot() async {
    final root = await _resolveRoot();
    final dir = Directory(p.join(root.path, 'chapters'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<File> _resolveChapterFile(
      int courseVersionId, String chapterKey) async {
    final root = await _resolveChapterRoot();
    final safeChapterKey = chapterKey.replaceAll('.', '_');
    return File(
      p.join(
          root.path, 'course_${courseVersionId}__chapter_$safeChapterKey.json'),
    );
  }

  Future<void> _upsertChapterSnapshot(
      SessionUploadCacheSnapshot snapshot) async {
    final chapterKey = _extractSecondLevelChapter(snapshot.kpKey);
    final existing = await readChapter(
      courseVersionId: snapshot.courseVersionId,
      chapterKey: chapterKey,
    );
    final payloadHash = _hashSessionSnapshot(snapshot);
    final members = <SessionUploadChapterMember>[
      ...(existing?.members ?? const <SessionUploadChapterMember>[])
          .where((member) => member.sessionId != snapshot.sessionId),
      SessionUploadChapterMember(
        sessionId: snapshot.sessionId,
        syncId: snapshot.syncId,
        syncUpdatedAt: snapshot.syncUpdatedAt,
        payloadHash: payloadHash,
      ),
    ]..sort((left, right) => left.sessionId.compareTo(right.sessionId));
    final chapterSnapshot = _buildChapterSnapshot(
      courseVersionId: snapshot.courseVersionId,
      chapterKey: chapterKey,
      members: members,
    );
    final file =
        await _resolveChapterFile(snapshot.courseVersionId, chapterKey);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(chapterSnapshot.toJson()),
      encoding: utf8,
    );
  }

  Future<void> _removeFromChapterSnapshot(
    SessionUploadCacheSnapshot snapshot,
  ) async {
    final chapterKey = _extractSecondLevelChapter(snapshot.kpKey);
    final existing = await readChapter(
      courseVersionId: snapshot.courseVersionId,
      chapterKey: chapterKey,
    );
    if (existing == null) {
      return;
    }
    final members = existing.members
        .where((member) => member.sessionId != snapshot.sessionId)
        .toList(growable: false);
    final file =
        await _resolveChapterFile(snapshot.courseVersionId, chapterKey);
    if (members.isEmpty) {
      if (file.existsSync()) {
        await file.delete();
      }
      return;
    }
    final chapterSnapshot = _buildChapterSnapshot(
      courseVersionId: snapshot.courseVersionId,
      chapterKey: chapterKey,
      members: members,
    );
    await file.writeAsString(
      jsonEncode(chapterSnapshot.toJson()),
      encoding: utf8,
    );
  }

  Future<SessionUploadChapterSnapshot?> _normalizeChapterSnapshot(
    SessionUploadChapterSnapshot snapshot,
  ) async {
    final sessionRoot = await _resolveSessionRoot();
    final normalizedMembers = snapshot.members
        .where(
          (member) =>
              member.sessionId > 0 &&
              member.syncId.trim().isNotEmpty &&
              File(
                p.join(
                  sessionRoot.path,
                  'session_${member.sessionId}.json',
                ),
              ).existsSync(),
        )
        .toList(growable: false);
    final file = await _resolveChapterFile(
      snapshot.courseVersionId,
      snapshot.chapterKey,
    );
    if (normalizedMembers.isEmpty) {
      if (file.existsSync()) {
        await file.delete();
      }
      return null;
    }
    final rebuilt = _buildChapterSnapshot(
      courseVersionId: snapshot.courseVersionId,
      chapterKey: snapshot.chapterKey,
      members: normalizedMembers,
    );
    if (rebuilt.contentHash != snapshot.contentHash ||
        rebuilt.updatedAt.toUtc() != snapshot.updatedAt.toUtc() ||
        rebuilt.members.length != snapshot.members.length) {
      await file.writeAsString(
        jsonEncode(rebuilt.toJson()),
        encoding: utf8,
      );
    }
    return rebuilt;
  }

  SessionUploadChapterSnapshot _buildChapterSnapshot({
    required int courseVersionId,
    required String chapterKey,
    required List<SessionUploadChapterMember> members,
  }) {
    final sortedMembers = members.toList(growable: false)
      ..sort((left, right) => left.sessionId.compareTo(right.sessionId));
    final updatedAt =
        sortedMembers.map((member) => member.syncUpdatedAt).reduce(
              (left, right) => left.isAfter(right) ? left : right,
            );
    final contentHash = _hashChapterMembers(sortedMembers);
    return SessionUploadChapterSnapshot(
      courseVersionId: courseVersionId,
      chapterKey: chapterKey,
      updatedAt: updatedAt,
      contentHash: contentHash,
      members: sortedMembers,
    );
  }

  String _hashSessionSnapshot(SessionUploadCacheSnapshot snapshot) {
    return hashSessionSemanticContent(
      kpKey: snapshot.kpKey,
      sessionTitle: snapshot.sessionTitle,
      summaryText: snapshot.summaryText,
      controlStateJson: snapshot.controlStateJson,
      evidenceStateJson: snapshot.evidenceStateJson,
      messages: snapshot.messages
          .map(
            (message) => SessionSemanticMessageInput(
              role: message.role,
              content: message.content,
              rawContent: message.rawContent,
              parsedJson: message.parsedJson,
              action: message.action,
            ),
          )
          .toList(growable: false),
    );
  }

  String _hashChapterMembers(List<SessionUploadChapterMember> members) {
    return hashSessionChapterSemanticContent(
      members
          .map(
            (member) => SessionChapterSemanticMemberInput(
              syncId: member.syncId,
              contentHash: member.payloadHash,
            ),
          )
          .toList(growable: false),
    );
  }

  String _extractSecondLevelChapter(String kpKey) {
    final trimmed = kpKey.trim();
    if (trimmed.isEmpty) {
      return 'ungrouped';
    }
    final match = _secondLevelChapterPattern.firstMatch(trimmed);
    if (match != null) {
      final value = match.group(1);
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    final parts = trimmed.split('.');
    if (parts.length >= 2) {
      return '${parts[0].trim()}.${parts[1].trim()}';
    }
    return trimmed;
  }
}
