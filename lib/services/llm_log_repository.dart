import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'log_crypto_service.dart';
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
  LlmLogRepository(
    this._settingsRepository, {
    LogCryptoService? logCrypto,
  }) : _logCrypto = logCrypto ?? LogCryptoService.instance;

  final SettingsRepository _settingsRepository;
  final LogCryptoService _logCrypto;
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
    String? reasoningText,
    bool? dbWriteOk,
    bool? uiCommitOk,
  }) async {
    _writeQueue = _writeQueue.then((_) async {
      try {
        final file = await _resolveFile();
        final encryptedPromptName =
            await _logCrypto.encryptForCurrentUser(promptName);
        final encryptedModel = await _logCrypto.encryptForCurrentUser(model);
        final encryptedBaseUrl =
            await _logCrypto.encryptForCurrentUser(baseUrl);
        final encryptedMode = await _logCrypto.encryptForCurrentUser(mode);
        final encryptedStatus = await _logCrypto.encryptForCurrentUser(status);
        final encryptedCallHash = callHash == null
            ? null
            : await _logCrypto.encryptForCurrentUser(callHash);
        final encryptedParseError = parseError == null
            ? null
            : await _logCrypto.encryptForCurrentUser(parseError);
        final encryptedAction = action == null
            ? null
            : await _logCrypto.encryptForCurrentUser(action);
        final encryptedRetryReason = retryReason == null
            ? null
            : await _logCrypto.encryptForCurrentUser(retryReason);
        final encryptedReasoningText = reasoningText == null
            ? null
            : await _logCrypto.encryptForCurrentUser(reasoningText);
        final payload = <String, dynamic>{
          'log_version': 2,
          'created_at': DateTime.now().toIso8601String(),
          'prompt_name_enc': encryptedPromptName,
          'model_enc': encryptedModel,
          'base_url_enc': encryptedBaseUrl,
          'mode_enc': encryptedMode,
          'status_enc': encryptedStatus,
          'call_hash_enc': encryptedCallHash,
          'latency_ms': latencyMs,
          'parse_valid': parseValid,
          'parse_error_enc': encryptedParseError,
          'teacher_id': teacherId,
          'student_id': studentId,
          'course_version_id': courseVersionId,
          'session_id': sessionId,
          'kp_key': kpKey,
          'action_enc': encryptedAction,
          'attempt': attempt,
          'retry_reason_enc': encryptedRetryReason,
          'backoff_ms': backoffMs,
          'rendered_chars': renderedChars,
          'response_chars': responseChars,
          'reasoning_text_enc': encryptedReasoningText,
          'db_write_ok': dbWriteOk,
          'ui_commit_ok': uiCommitOk,
          'owner_user_id': _logCrypto.activeUserId,
          'owner_role': _logCrypto.activeRole,
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
    final entries = <LlmLogEntry>[];
    for (final line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('LLM log row is not a JSON object.');
      }
      final isV2 = (decoded['log_version'] as num?)?.toInt() == 2;
      if (isV2) {
        if (!_isRelevantToActiveUser(decoded)) {
          continue;
        }
        final promptName = await _logCrypto.decryptForCurrentUser(
          decoded['prompt_name_enc'] as String?,
        );
        if (promptName == null) {
          continue;
        }
        final model = await _logCrypto.decryptForCurrentUser(
          decoded['model_enc'] as String?,
        );
        if (model == null) {
          continue;
        }
        final baseUrl = await _logCrypto.decryptForCurrentUser(
          decoded['base_url_enc'] as String?,
        );
        if (baseUrl == null) {
          continue;
        }
        final mode = await _logCrypto.decryptForCurrentUser(
          decoded['mode_enc'] as String?,
        );
        if (mode == null) {
          continue;
        }
        final status = await _logCrypto.decryptForCurrentUser(
          decoded['status_enc'] as String?,
        );
        if (status == null) {
          continue;
        }
        final callHash = await _logCrypto.decryptForCurrentUser(
          decoded['call_hash_enc'] as String?,
        );
        if (decoded['call_hash_enc'] != null && callHash == null) {
          continue;
        }
        final parseError = await _logCrypto.decryptForCurrentUser(
          decoded['parse_error_enc'] as String?,
        );
        if (decoded['parse_error_enc'] != null && parseError == null) {
          continue;
        }
        final action = await _logCrypto.decryptForCurrentUser(
          decoded['action_enc'] as String?,
        );
        if (decoded['action_enc'] != null && action == null) {
          continue;
        }
        final retryReason = await _logCrypto.decryptForCurrentUser(
          decoded['retry_reason_enc'] as String?,
        );
        if (decoded['retry_reason_enc'] != null && retryReason == null) {
          continue;
        }
        entries.add(
          LlmLogEntry.fromJson(
            <String, dynamic>{
              'created_at': decoded['created_at'],
              'prompt_name': promptName,
              'model': model,
              'base_url': baseUrl,
              'mode': mode,
              'status': status,
              'call_hash': callHash,
              'latency_ms': decoded['latency_ms'],
              'parse_valid': decoded['parse_valid'],
              'parse_error': parseError,
              'teacher_id': decoded['teacher_id'],
              'student_id': decoded['student_id'],
              'course_version_id': decoded['course_version_id'],
              'session_id': decoded['session_id'],
              'kp_key': decoded['kp_key'],
              'action': action,
              'attempt': decoded['attempt'],
              'retry_reason': retryReason,
              'backoff_ms': decoded['backoff_ms'],
              'rendered_chars': decoded['rendered_chars'],
              'response_chars': decoded['response_chars'],
              'db_write_ok': decoded['db_write_ok'],
              'ui_commit_ok': decoded['ui_commit_ok'],
            },
          ),
        );
        continue;
      }
      if (_isRelevantToActiveUser(decoded)) {
        entries.add(LlmLogEntry.fromJson(decoded));
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

  bool _isRelevantToActiveUser(Map<String, dynamic> row) {
    final activeUserId = _logCrypto.activeUserId;
    final activeRole = _logCrypto.activeRole;
    if (activeUserId == null || activeRole == null) {
      return false;
    }
    final teacherId = (row['teacher_id'] as num?)?.toInt();
    final studentId = (row['student_id'] as num?)?.toInt();
    final ownerUserId = (row['owner_user_id'] as num?)?.toInt();
    final ownerRole = (row['owner_role'] as String?)?.trim().toLowerCase();
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
