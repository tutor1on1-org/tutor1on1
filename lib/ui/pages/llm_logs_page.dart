import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:family_teacher/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart' as db;
import '../../services/app_services.dart';
import '../../services/log_crypto_service.dart';
import '../../services/llm_log_repository.dart' as filelog;
import '../../state/auth_controller.dart';

class LlmLogsPage extends StatefulWidget {
  const LlmLogsPage({super.key});

  @override
  State<LlmLogsPage> createState() => _LlmLogsPageState();
}

class _LlmLogsPageState extends State<LlmLogsPage> {
  Future<List<_ViewLlmLogEntry>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _loadEntries();
  }

  Future<List<_ViewLlmLogEntry>> _loadEntries() async {
    final auth = context.read<AuthController>();
    final current = auth.currentUser;
    if (current == null) {
      return <_ViewLlmLogEntry>[];
    }
    final database = context.read<db.AppDatabase>();
    final services = context.read<AppServices>();
    final dbEntries = await database.getLlmLogEntries();
    final fileEntries = await services.llmLogRepository.loadEntries();

    final resolvedDb = <_DbAttempt>[];
    for (final entry in dbEntries) {
      if (!_isRelevantDbEntry(entry, current)) {
        continue;
      }
      final renderedPrompt =
          await LogCryptoService.instance.decryptForCurrentUser(
        entry.renderedPrompt,
      );
      if (renderedPrompt == null) {
        continue;
      }
      final responseText =
          await LogCryptoService.instance.decryptForCurrentUser(
        entry.responseText,
      );
      if (entry.responseText != null && responseText == null) {
        continue;
      }
      final parseError = await LogCryptoService.instance.decryptForCurrentUser(
        entry.parseError,
      );
      if (entry.parseError != null && parseError == null) {
        continue;
      }
      resolvedDb.add(
        _DbAttempt(
          id: entry.id,
          callHash: entry.callHash,
          promptName: entry.promptName,
          renderedPrompt: renderedPrompt,
          model: entry.model,
          baseUrl: entry.baseUrl,
          responseText: responseText,
          responseJson: entry.responseJson,
          parseValid: entry.parseValid,
          parseError: parseError,
          latencyMs: entry.latencyMs,
          teacherId: entry.teacherId,
          studentId: entry.studentId,
          courseVersionId: entry.courseVersionId,
          sessionId: entry.sessionId,
          kpKey: entry.kpKey,
          action: entry.action,
          createdAt: entry.createdAt,
          mode: entry.mode,
          teacherName: entry.teacherName,
          studentName: entry.studentName,
        ),
      );
    }

    final dbAttemptsByHash = <String, List<_DbAttempt>>{};
    final dbIdentityByHash = <String, _DbAttempt>{};
    final unmatchedDb = <_DbAttempt>[];
    for (final entry in resolvedDb) {
      final hash = entry.callHash.trim();
      if (hash.isEmpty) {
        unmatchedDb.add(entry);
        continue;
      }
      dbAttemptsByHash.putIfAbsent(hash, () => <_DbAttempt>[]).add(entry);
      dbIdentityByHash.putIfAbsent(hash, () => entry);
    }
    for (final attempts in dbAttemptsByHash.values) {
      attempts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    final sortedFileEntries = [...fileEntries]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final combined = <_ViewLlmLogEntry>[];
    for (final entry in sortedFileEntries) {
      final matchedDb = _isModelAttempt(entry)
          ? _takeNextDbAttempt(
              dbAttemptsByHash,
              entry.callHash,
            )
          : null;
      final identityDb = _lookupDbIdentity(
        dbIdentityByHash,
        entry.callHash,
      );
      combined.add(
        _ViewLlmLogEntry(
          createdAt: entry.createdAt,
          promptName: matchedDb?.promptName ?? entry.promptName,
          model: matchedDb?.model ?? entry.model,
          baseUrl: matchedDb?.baseUrl ?? entry.baseUrl,
          mode: matchedDb?.mode ?? entry.mode,
          callHash: entry.callHash ?? matchedDb?.callHash ?? '',
          teacherId:
              matchedDb?.teacherId ?? identityDb?.teacherId ?? entry.teacherId,
          studentId:
              matchedDb?.studentId ?? identityDb?.studentId ?? entry.studentId,
          courseVersionId: matchedDb?.courseVersionId ?? entry.courseVersionId,
          sessionId: matchedDb?.sessionId ?? entry.sessionId,
          kpKey: matchedDb?.kpKey ?? entry.kpKey,
          action: matchedDb?.action ?? entry.action,
          teacherName: matchedDb?.teacherName ?? identityDb?.teacherName,
          studentName: matchedDb?.studentName ?? identityDb?.studentName,
          renderedPrompt: matchedDb?.renderedPrompt,
          responseText: matchedDb?.responseText,
          responseJson: matchedDb?.responseJson,
          parseValid: matchedDb?.parseValid ?? entry.parseValid,
          parseError: matchedDb?.parseError ?? entry.parseError,
          metadata: _buildMetadata(entry),
        ),
      );
    }

    for (final attempts in dbAttemptsByHash.values) {
      unmatchedDb.addAll(attempts);
    }
    unmatchedDb.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final entry in unmatchedDb) {
      combined.add(
        _ViewLlmLogEntry(
          createdAt: entry.createdAt,
          promptName: entry.promptName,
          model: entry.model,
          baseUrl: entry.baseUrl,
          mode: entry.mode,
          callHash: entry.callHash,
          teacherId: entry.teacherId,
          studentId: entry.studentId,
          courseVersionId: entry.courseVersionId,
          sessionId: entry.sessionId,
          kpKey: entry.kpKey,
          action: entry.action,
          teacherName: entry.teacherName,
          studentName: entry.studentName,
          renderedPrompt: entry.renderedPrompt,
          responseText: entry.responseText,
          responseJson: entry.responseJson,
          parseValid: entry.parseValid,
          parseError: entry.parseError,
          metadata: <String, dynamic>{
            'source': 'llm_calls_only',
            'latency_ms': entry.latencyMs,
          },
        ),
      );
    }

    combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return combined;
  }

  bool _isRelevantDbEntry(db.LlmLogEntry entry, db.User current) {
    if (current.role == 'teacher') {
      return entry.teacherId == current.id;
    }
    if (current.role == 'student') {
      return entry.studentId == current.id;
    }
    return false;
  }

  bool _isModelAttempt(filelog.LlmLogEntry entry) {
    return entry.latencyMs != null ||
        entry.parseValid != null ||
        (entry.reasoningText?.trim().isNotEmpty ?? false) ||
        (entry.status.trim().toLowerCase() == 'ok');
  }

  _DbAttempt? _takeNextDbAttempt(
    Map<String, List<_DbAttempt>> attemptsByHash,
    String? callHash,
  ) {
    final hash = (callHash ?? '').trim();
    if (hash.isEmpty) {
      return null;
    }
    final queue = attemptsByHash[hash];
    if (queue == null || queue.isEmpty) {
      return null;
    }
    return queue.removeAt(0);
  }

  _DbAttempt? _lookupDbIdentity(
    Map<String, _DbAttempt> attemptsByHash,
    String? callHash,
  ) {
    final hash = (callHash ?? '').trim();
    if (hash.isEmpty) {
      return null;
    }
    return attemptsByHash[hash];
  }

  Map<String, dynamic> _buildMetadata(filelog.LlmLogEntry entry) {
    return <String, dynamic>{
      'source': 'llm_jsonl',
      'log_version': entry.logVersion,
      'status': entry.status,
      'attempt': entry.attempt,
      'retry_reason': entry.retryReason,
      'backoff_ms': entry.backoffMs,
      'latency_ms': entry.latencyMs,
      'rendered_chars': entry.renderedChars,
      'response_chars': entry.responseChars,
      'reasoning_text': entry.reasoningText,
      'db_write_ok': entry.dbWriteOk,
      'ui_commit_ok': entry.uiCommitOk,
      'owner_user_id': entry.ownerUserId,
      'owner_role': entry.ownerRole,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.llmLogsTitle),
        actions: [
          IconButton(
            onPressed: () => setState(_load),
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refreshTooltip,
          ),
        ],
      ),
      body: FutureBuilder<List<_ViewLlmLogEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(l10n.loadLogsFailed('${snapshot.error}')),
            );
          }
          final entries = snapshot.data ?? [];
          if (entries.isEmpty) {
            return Center(child: Text(l10n.noLlmLogs));
          }

          final grouped = _groupEntries(entries, l10n);
          return ListView(
            padding: const EdgeInsets.all(12),
            children: grouped.entries.map((teacherEntry) {
              return ExpansionTile(
                title: Text(teacherEntry.key),
                children: teacherEntry.value.entries.map((studentEntry) {
                  return ExpansionTile(
                    title: Text(studentEntry.key),
                    children: studentEntry.value.entries.map((dateEntry) {
                      return ExpansionTile(
                        title: Text(dateEntry.key),
                        children: dateEntry.value.map((entry) {
                          return ListTile(
                            title: Text(
                              l10n.llmLogEntryTitle(
                                _formatTime(entry.createdAt),
                                entry.promptName,
                              ),
                            ),
                            subtitle: Text(
                              '${entry.model} • ${entry.mode} • ${_statusLabel(entry, l10n)}',
                            ),
                            onTap: () => _showDetails(entry, l10n),
                          );
                        }).toList(),
                      );
                    }).toList(),
                  );
                }).toList(),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Map<String, Map<String, Map<String, List<_ViewLlmLogEntry>>>> _groupEntries(
    List<_ViewLlmLogEntry> entries,
    AppLocalizations l10n,
  ) {
    final grouped =
        <String, Map<String, Map<String, List<_ViewLlmLogEntry>>>>{};
    for (final entry in entries) {
      final teacherKey = _teacherLabel(entry, l10n);
      final studentKey = _studentLabel(entry, l10n);
      final dateKey = _formatDate(entry.createdAt);
      grouped.putIfAbsent(teacherKey, () => {});
      grouped[teacherKey]!.putIfAbsent(studentKey, () => {});
      grouped[teacherKey]![studentKey]!.putIfAbsent(dateKey, () => []);
      grouped[teacherKey]![studentKey]![dateKey]!.add(entry);
    }
    return grouped;
  }

  Future<void> _showDetails(
    _ViewLlmLogEntry entry,
    AppLocalizations l10n,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.llmCallDetailsTitle),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.llmTimeLabel(entry.createdAt.toIso8601String())),
                Text(l10n.llmPromptLabel(entry.promptName)),
                Text(l10n.llmModeValueLabel(entry.mode)),
                Text(l10n.llmModelLabel(entry.model)),
                Text(l10n.llmBaseUrlLabel(entry.baseUrl)),
                if (entry.callHash.isNotEmpty)
                  Text(l10n.llmCallHashLabel(entry.callHash)),
                Text(_teacherLabel(entry, l10n)),
                Text(_studentLabel(entry, l10n)),
                if ((entry.kpKey ?? '').isNotEmpty)
                  Text(l10n.llmKpLabel(entry.kpKey!)),
                if ((entry.action ?? '').isNotEmpty)
                  Text(l10n.llmActionLabel(entry.action!)),
                const SizedBox(height: 12),
                const Text('Metadata'),
                SelectableText(_prettyJson(entry.metadata)),
                if ((entry.renderedPrompt ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(l10n.llmRenderedPromptLabel),
                  SelectableText(entry.renderedPrompt!),
                ],
                if ((entry.responseText ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(l10n.llmResponseLabel),
                  SelectableText(entry.responseText!),
                ],
                if ((entry.responseJson ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Response JSON'),
                  SelectableText(entry.responseJson!),
                ],
                if ((entry.parseError ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(l10n.llmParseErrorLabel),
                  SelectableText(entry.parseError!),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.closeButton),
          ),
        ],
      ),
    );
  }

  String _prettyJson(Map<String, dynamic> value) {
    final cleaned = <String, dynamic>{};
    value.forEach((key, dynamic fieldValue) {
      if (fieldValue == null) {
        return;
      }
      if (fieldValue is String && fieldValue.trim().isEmpty) {
        return;
      }
      cleaned[key] = fieldValue;
    });
    return const JsonEncoder.withIndent('  ').convert(cleaned);
  }

  String _teacherLabel(_ViewLlmLogEntry entry, AppLocalizations l10n) {
    if (entry.teacherName != null && entry.teacherName!.isNotEmpty) {
      return l10n.llmTeacherLabel(entry.teacherName!);
    }
    if (entry.teacherId != null) {
      return l10n.llmTeacherIdLabel('${entry.teacherId}');
    }
    return l10n.llmTeacherUnknown;
  }

  String _studentLabel(_ViewLlmLogEntry entry, AppLocalizations l10n) {
    if (entry.studentId == null) {
      return l10n.llmStudentNone;
    }
    final name =
        entry.studentName?.isNotEmpty == true ? entry.studentName : null;
    return name != null
        ? l10n.llmStudentLabel(name)
        : l10n.llmStudentIdLabel('${entry.studentId}');
  }

  String _formatDate(DateTime dateTime) {
    final year = dateTime.year.toString().padLeft(4, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String _statusLabel(_ViewLlmLogEntry entry, AppLocalizations l10n) {
    final status = (entry.metadata['status'] as String?)?.trim();
    if (status != null && status.isNotEmpty) {
      return status;
    }
    if (entry.parseValid == null) {
      return l10n.llmStatusUnknown;
    }
    return entry.parseValid == true ? l10n.llmStatusOk : l10n.llmStatusError;
  }
}

class _ViewLlmLogEntry {
  _ViewLlmLogEntry({
    required this.createdAt,
    required this.promptName,
    required this.model,
    required this.baseUrl,
    required this.mode,
    required this.callHash,
    required this.metadata,
    this.teacherId,
    this.studentId,
    this.courseVersionId,
    this.sessionId,
    this.kpKey,
    this.action,
    this.teacherName,
    this.studentName,
    this.renderedPrompt,
    this.responseText,
    this.responseJson,
    this.parseValid,
    this.parseError,
  });

  final DateTime createdAt;
  final String promptName;
  final String model;
  final String baseUrl;
  final String mode;
  final String callHash;
  final int? teacherId;
  final int? studentId;
  final int? courseVersionId;
  final int? sessionId;
  final String? kpKey;
  final String? action;
  final String? teacherName;
  final String? studentName;
  final String? renderedPrompt;
  final String? responseText;
  final String? responseJson;
  final bool? parseValid;
  final String? parseError;
  final Map<String, dynamic> metadata;
}

class _DbAttempt {
  _DbAttempt({
    required this.id,
    required this.callHash,
    required this.promptName,
    required this.renderedPrompt,
    required this.model,
    required this.baseUrl,
    required this.responseText,
    required this.responseJson,
    required this.parseValid,
    required this.parseError,
    required this.latencyMs,
    required this.teacherId,
    required this.studentId,
    required this.courseVersionId,
    required this.sessionId,
    required this.kpKey,
    required this.action,
    required this.createdAt,
    required this.mode,
    required this.teacherName,
    required this.studentName,
  });

  final int id;
  final String callHash;
  final String promptName;
  final String renderedPrompt;
  final String model;
  final String baseUrl;
  final String? responseText;
  final String? responseJson;
  final bool? parseValid;
  final String? parseError;
  final int? latencyMs;
  final int? teacherId;
  final int? studentId;
  final int? courseVersionId;
  final int? sessionId;
  final String? kpKey;
  final String? action;
  final DateTime createdAt;
  final String mode;
  final String? teacherName;
  final String? studentName;
}
