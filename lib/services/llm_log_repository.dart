import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'settings_repository.dart';

class LlmLogEntry {
  LlmLogEntry({
    required this.createdAt,
    required this.promptName,
    required this.model,
    required this.baseUrl,
    required this.mode,
    required this.status,
    this.callHash,
    this.latencyMs,
    this.parseValid,
    this.parseError,
    this.teacherId,
    this.studentId,
    this.courseVersionId,
    this.sessionId,
    this.kpKey,
    this.action,
    this.attempt,
    this.retryReason,
    this.backoffMs,
    this.renderedChars,
    this.responseChars,
    this.dbWriteOk,
    this.uiCommitOk,
  });

  final DateTime createdAt;
  final String promptName;
  final String model;
  final String baseUrl;
  final String mode;
  final String status;
  final String? callHash;
  final int? latencyMs;
  final bool? parseValid;
  final String? parseError;
  final int? teacherId;
  final int? studentId;
  final int? courseVersionId;
  final int? sessionId;
  final String? kpKey;
  final String? action;
  final int? attempt;
  final String? retryReason;
  final int? backoffMs;
  final int? renderedChars;
  final int? responseChars;
  final bool? dbWriteOk;
  final bool? uiCommitOk;

  factory LlmLogEntry.fromJson(Map<String, dynamic> json) {
    final createdRaw = json['created_at'];
    DateTime createdAt;
    if (createdRaw is String) {
      createdAt = DateTime.tryParse(createdRaw) ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }
    return LlmLogEntry(
      createdAt: createdAt,
      promptName: json['prompt_name'] as String? ?? '',
      model: json['model'] as String? ?? '',
      baseUrl: json['base_url'] as String? ?? '',
      mode: json['mode'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      callHash: json['call_hash'] as String?,
      latencyMs: json['latency_ms'] as int?,
      parseValid: json['parse_valid'] as bool?,
      parseError: json['parse_error'] as String?,
      teacherId: json['teacher_id'] as int?,
      studentId: json['student_id'] as int?,
      courseVersionId: json['course_version_id'] as int?,
      sessionId: json['session_id'] as int?,
      kpKey: json['kp_key'] as String?,
      action: json['action'] as String?,
      attempt: json['attempt'] as int?,
      retryReason: json['retry_reason'] as String?,
      backoffMs: json['backoff_ms'] as int?,
      renderedChars: json['rendered_chars'] as int?,
      responseChars: json['response_chars'] as int?,
      dbWriteOk: json['db_write_ok'] as bool?,
      uiCommitOk: json['ui_commit_ok'] as bool?,
    );
  }
}

class LlmLogRepository {
  LlmLogRepository(this._settingsRepository);

  final SettingsRepository _settingsRepository;
  Future<void> _writeQueue = Future.value();

  Future<void> appendEntry({
    required String promptName,
    required String model,
    required String baseUrl,
    required String mode,
    required String status,
    String? callHash,
    int? latencyMs,
    bool? parseValid,
    String? parseError,
    int? teacherId,
    int? studentId,
    int? courseVersionId,
    int? sessionId,
    String? kpKey,
    String? action,
    int? attempt,
    String? retryReason,
    int? backoffMs,
    int? renderedChars,
    int? responseChars,
    bool? dbWriteOk,
    bool? uiCommitOk,
  }) async {
    _writeQueue = _writeQueue.then((_) async {
      try {
        final file = await _resolveFile();
        final payload = <String, dynamic>{
          'created_at': DateTime.now().toIso8601String(),
          'prompt_name': promptName,
          'model': model,
          'base_url': baseUrl,
          'mode': mode,
          'status': status,
          'call_hash': callHash,
          'latency_ms': latencyMs,
          'parse_valid': parseValid,
          'parse_error': parseError,
          'teacher_id': teacherId,
          'student_id': studentId,
          'course_version_id': courseVersionId,
          'session_id': sessionId,
          'kp_key': kpKey,
          'action': action,
          'attempt': attempt,
          'retry_reason': retryReason,
          'backoff_ms': backoffMs,
          'rendered_chars': renderedChars,
          'response_chars': responseChars,
          'db_write_ok': dbWriteOk,
          'ui_commit_ok': uiCommitOk,
        };
        await file.writeAsString(
          '${jsonEncode(payload)}\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {
        // Ignore logging failures to avoid blocking LLM calls.
      }
    });
    return _writeQueue;
  }

  Future<List<LlmLogEntry>> loadEntries() async {
    final file = await _resolveFile();
    if (!await file.exists()) {
      return [];
    }
    final bytes = await file.readAsBytes();
    final content = utf8.decode(bytes, allowMalformed: true);
    final lines = const LineSplitter().convert(content);
    final entries = <LlmLogEntry>[];
    for (final line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) {
          entries.add(LlmLogEntry.fromJson(decoded));
        }
      } catch (_) {
        // Skip malformed lines.
      }
    }
    return entries.reversed.toList();
  }

  Future<File> _resolveFile() async {
    final settings = await _settingsRepository.load();
    final resolvedPath = (settings.llmLogPath ?? '').trim();
    final filePath = resolvedPath.isNotEmpty
        ? resolvedPath
        : p.join(Directory.current.path, 'llm_logs.jsonl');
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
}
