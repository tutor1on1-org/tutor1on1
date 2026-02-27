import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/app_database.dart';
import 'log_crypto_service.dart';
import 'settings_repository.dart';

class TtsLogEntry {
  TtsLogEntry({
    required this.createdAt,
    required this.event,
    required this.message,
    this.statusCode,
    this.baseUrl,
    this.model,
    this.voice,
    this.textSnippet,
    this.sessionId,
    this.teacherId,
    this.studentId,
    this.courseVersionId,
    this.textLength,
  });

  final DateTime createdAt;
  final String event;
  final String message;
  final int? statusCode;
  final String? baseUrl;
  final String? model;
  final String? voice;
  final String? textSnippet;
  final int? sessionId;
  final int? teacherId;
  final int? studentId;
  final int? courseVersionId;
  final int? textLength;

  factory TtsLogEntry.fromJson(Map<String, dynamic> json) {
    final createdRaw = json['created_at'];
    DateTime createdAt;
    if (createdRaw is String) {
      createdAt = DateTime.tryParse(createdRaw) ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }
    return TtsLogEntry(
      createdAt: createdAt,
      event: json['event'] as String? ?? 'error',
      message:
          json['message'] as String? ?? json['error_message'] as String? ?? '',
      statusCode: (json['status_code'] as num?)?.toInt(),
      baseUrl: json['base_url'] as String?,
      model: json['model'] as String?,
      voice: json['voice'] as String?,
      textSnippet: json['text_snippet'] as String?,
      sessionId: (json['session_id'] as num?)?.toInt(),
      teacherId: (json['teacher_id'] as num?)?.toInt(),
      studentId: (json['student_id'] as num?)?.toInt(),
      courseVersionId: (json['course_version_id'] as num?)?.toInt(),
      textLength: (json['text_length'] as num?)?.toInt(),
    );
  }
}

class TtsLogRepository {
  TtsLogRepository(
    this._settingsRepository, {
    AppDatabase? db,
    LogCryptoService? logCrypto,
  })  : _db = db,
        _logCrypto = logCrypto ?? LogCryptoService.instance;

  final SettingsRepository _settingsRepository;
  final AppDatabase? _db;
  final LogCryptoService _logCrypto;
  Future<void> _writeQueue = Future.value();

  Future<void> appendEvent({
    required String event,
    required String message,
    required String baseUrl,
    required String model,
    required String voice,
    String? textSnippet,
    int? textLength,
    int? statusCode,
    int? sessionId,
  }) async {
    _writeQueue = _writeQueue.then((_) async {
      try {
        final file = await _resolveFile();
        final scope = await _resolveScope(sessionId);
        final encryptedMessage =
            await _logCrypto.encryptForCurrentUser(_truncate(message, 800));
        final snippet = _truncate(textSnippet ?? '', 8000);
        final encryptedSnippet = snippet.isEmpty
            ? null
            : await _logCrypto.encryptForCurrentUser(snippet);
        final encryptedBaseUrl =
            await _logCrypto.encryptForCurrentUser(baseUrl);
        final encryptedModel = await _logCrypto.encryptForCurrentUser(model);
        final encryptedVoice = await _logCrypto.encryptForCurrentUser(voice);
        final payload = <String, dynamic>{
          'log_version': 2,
          'created_at': DateTime.now().toIso8601String(),
          'event': event,
          'message_enc': encryptedMessage,
          'status_code': statusCode,
          'base_url_enc': encryptedBaseUrl,
          'model_enc': encryptedModel,
          'voice_enc': encryptedVoice,
          'text_snippet_enc': encryptedSnippet,
          'session_id': sessionId,
          'teacher_id': scope.teacherId,
          'student_id': scope.studentId,
          'course_version_id': scope.courseVersionId,
          'owner_user_id': scope.ownerUserId,
          'owner_role': scope.ownerRole,
          'text_length': textLength,
        };
        await file.writeAsString(
          '${jsonEncode(payload)}\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {
        // Ignore logging failures to avoid blocking TTS output.
      }
    });
    return _writeQueue;
  }

  Future<void> appendError({
    required String message,
    required String baseUrl,
    required String model,
    required String voice,
    String? textSnippet,
    int? textLength,
    int? statusCode,
    int? sessionId,
  }) {
    return appendEvent(
      event: 'error',
      message: message,
      baseUrl: baseUrl,
      model: model,
      voice: voice,
      textSnippet: textSnippet,
      textLength: textLength,
      statusCode: statusCode,
      sessionId: sessionId,
    );
  }

  Future<List<TtsLogEntry>> loadEntries() async {
    if (!_logCrypto.hasActiveKey) {
      return [];
    }
    final file = await _resolveFile();
    if (!await file.exists()) {
      return [];
    }
    final bytes = await file.readAsBytes();
    final content = utf8.decode(bytes, allowMalformed: true);
    final lines = const LineSplitter().convert(content);
    final entries = <TtsLogEntry>[];
    final sessionScopeCache = <int, _LogScope>{};
    for (final line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('TTS log row is not a JSON object.');
      }
      final isV2 = (decoded['log_version'] as num?)?.toInt() == 2;
      if (isV2) {
        final teacherId = (decoded['teacher_id'] as num?)?.toInt();
        final studentId = (decoded['student_id'] as num?)?.toInt();
        final ownerUserId = (decoded['owner_user_id'] as num?)?.toInt();
        final ownerRole = (decoded['owner_role'] as String?)?.trim();
        if (!_isRelevantToActiveUser(
          teacherId: teacherId,
          studentId: studentId,
          ownerUserId: ownerUserId,
          ownerRole: ownerRole,
        )) {
          continue;
        }
        final message = await _logCrypto
            .decryptForCurrentUser(decoded['message_enc'] as String?);
        if (message == null) {
          continue;
        }
        final textSnippet = await _logCrypto.decryptForCurrentUser(
          decoded['text_snippet_enc'] as String?,
        );
        if (decoded['text_snippet_enc'] != null && textSnippet == null) {
          continue;
        }
        final baseUrl = await _logCrypto.decryptForCurrentUser(
          decoded['base_url_enc'] as String?,
        );
        if (baseUrl == null) {
          continue;
        }
        final model = await _logCrypto.decryptForCurrentUser(
          decoded['model_enc'] as String?,
        );
        if (model == null) {
          continue;
        }
        final voice = await _logCrypto.decryptForCurrentUser(
          decoded['voice_enc'] as String?,
        );
        if (voice == null) {
          continue;
        }
        entries.add(
          TtsLogEntry.fromJson(
            <String, dynamic>{
              'created_at': decoded['created_at'],
              'event': decoded['event'],
              'message': message,
              'status_code': decoded['status_code'],
              'base_url': baseUrl,
              'model': model,
              'voice': voice,
              'text_snippet': textSnippet,
              'session_id': decoded['session_id'],
              'teacher_id': decoded['teacher_id'],
              'student_id': decoded['student_id'],
              'course_version_id': decoded['course_version_id'],
              'text_length': decoded['text_length'],
            },
          ),
        );
        continue;
      }

      final sessionId = (decoded['session_id'] as num?)?.toInt();
      if (sessionId == null || sessionId <= 0) {
        continue;
      }
      final scope = await _resolveScope(sessionId, cache: sessionScopeCache);
      if (!_isRelevantToActiveUser(
        teacherId: scope.teacherId,
        studentId: scope.studentId,
        ownerUserId: null,
        ownerRole: null,
      )) {
        continue;
      }
      entries.add(TtsLogEntry.fromJson(decoded));
    }
    return entries.reversed.toList();
  }

  Future<File> _resolveFile() async {
    final settings = await _settingsRepository.load();
    final resolvedPath = (settings.ttsLogPath ?? '').trim();
    final filePath = resolvedPath.isNotEmpty
        ? resolvedPath
        : p.join(Directory.current.path, 'tts_logs.jsonl');
    final dir = Directory(p.dirname(filePath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(filePath);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return file;
  }

  String _truncate(String value, int max) {
    if (value.length <= max) {
      return value;
    }
    return value.substring(0, max);
  }

  Future<_LogScope> _resolveScope(
    int? sessionId, {
    Map<int, _LogScope>? cache,
  }) async {
    final activeUserId = _logCrypto.activeUserId;
    final activeRole = _logCrypto.activeRole;
    if (sessionId != null && sessionId > 0) {
      final cached = cache?[sessionId];
      if (cached != null) {
        return cached;
      }
      int? teacherId;
      int? studentId;
      int? courseVersionId;
      if (_db != null) {
        final session = await _db.getSession(sessionId);
        if (session != null) {
          studentId = session.studentId;
          courseVersionId = session.courseVersionId;
          final course = await _db.getCourseVersionById(courseVersionId);
          teacherId = course?.teacherId;
        }
      }
      if (activeUserId != null && activeRole != null) {
        if (activeRole == 'teacher') {
          teacherId ??= activeUserId;
        } else if (activeRole == 'student') {
          studentId ??= activeUserId;
        }
      }
      final scope = _LogScope(
        teacherId: teacherId,
        studentId: studentId,
        courseVersionId: courseVersionId,
        ownerUserId: activeUserId,
        ownerRole: activeRole,
      );
      cache?[sessionId] = scope;
      return scope;
    }

    int? teacherId;
    int? studentId;
    if (activeUserId != null && activeRole != null) {
      if (activeRole == 'teacher') {
        teacherId = activeUserId;
      } else if (activeRole == 'student') {
        studentId = activeUserId;
      }
    }
    return _LogScope(
      teacherId: teacherId,
      studentId: studentId,
      courseVersionId: null,
      ownerUserId: activeUserId,
      ownerRole: activeRole,
    );
  }

  bool _isRelevantToActiveUser({
    required int? teacherId,
    required int? studentId,
    required int? ownerUserId,
    required String? ownerRole,
  }) {
    final activeUserId = _logCrypto.activeUserId;
    final activeRole = _logCrypto.activeRole;
    if (activeUserId == null || activeRole == null) {
      return false;
    }
    if (activeRole == 'teacher') {
      return teacherId == activeUserId ||
          (ownerRole == 'teacher' && ownerUserId == activeUserId);
    }
    if (activeRole == 'student') {
      return studentId == activeUserId ||
          (ownerRole == 'student' && ownerUserId == activeUserId);
    }
    return false;
  }
}

class _LogScope {
  _LogScope({
    required this.teacherId,
    required this.studentId,
    required this.courseVersionId,
    required this.ownerUserId,
    required this.ownerRole,
  });

  final int? teacherId;
  final int? studentId;
  final int? courseVersionId;
  final int? ownerUserId;
  final String? ownerRole;
}
