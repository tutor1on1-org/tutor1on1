import 'dart:convert';

import 'package:tutor1on1/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart' as db;
import '../../services/app_services.dart';
import '../../services/log_crypto_service.dart';
import '../../services/llm_log_repository.dart' as filelog;
import '../../state/auth_controller.dart';
import '../app_close_button.dart';
import 'llm_log_view_data.dart';

typedef _ViewLlmLogEntry = LlmLogViewEntry;

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
    final usernamesById = await _loadUsernamesById(
      database,
      _collectRelevantUserIds(
        dbEntries: dbEntries,
        fileEntries: fileEntries,
        current: current,
      ),
    );

    final resolvedDb = <LlmLogDbAttemptInput>[];
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
      final responseJson =
          await LogCryptoService.instance.decryptForCurrentUser(
        entry.responseJson,
      );
      if (entry.responseJson != null && responseJson == null) {
        continue;
      }
      final parseError = await LogCryptoService.instance.decryptForCurrentUser(
        entry.parseError,
      );
      if (entry.parseError != null && parseError == null) {
        continue;
      }
      resolvedDb.add(
        LlmLogDbAttemptInput(
          callHash: entry.callHash,
          promptName: entry.promptName,
          renderedPrompt: renderedPrompt,
          model: entry.model,
          baseUrl: entry.baseUrl,
          responseText: responseText,
          responseJson: responseJson,
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
          teacherName: _resolveUsername(
            existingName: entry.teacherName,
            fallbackName: usernamesById[entry.teacherId],
          ),
          studentName: _resolveUsername(
            existingName: entry.studentName,
            fallbackName: usernamesById[entry.studentId],
          ),
        ),
      );
    }

    final resolvedFileEntries = fileEntries
        .map(
          (entry) => LlmLogFileEventInput(
            createdAt: entry.createdAt,
            promptName: entry.promptName,
            model: entry.model,
            baseUrl: entry.baseUrl,
            mode: entry.mode,
            status: entry.status,
            callHash: entry.callHash,
            parseValid: entry.parseValid,
            parseError: entry.parseError,
            teacherId: entry.teacherId,
            studentId: entry.studentId,
            teacherName: usernamesById[entry.teacherId],
            studentName: usernamesById[entry.studentId],
            courseVersionId: entry.courseVersionId,
            sessionId: entry.sessionId,
            kpKey: entry.kpKey,
            action: entry.action,
            metadata: _buildMetadata(entry),
          ),
        )
        .toList(growable: false);

    return buildLlmLogViewEntries(
      dbAttempts: resolvedDb,
      fileEvents: resolvedFileEntries,
    );
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

  Set<int> _collectRelevantUserIds({
    required List<db.LlmLogEntry> dbEntries,
    required List<filelog.LlmLogEntry> fileEntries,
    required db.User current,
  }) {
    final ids = <int>{};
    for (final entry in dbEntries) {
      if (!_isRelevantDbEntry(entry, current)) {
        continue;
      }
      if (entry.teacherId != null) {
        ids.add(entry.teacherId!);
      }
      if (entry.studentId != null) {
        ids.add(entry.studentId!);
      }
    }
    for (final entry in fileEntries) {
      if (entry.teacherId != null) {
        ids.add(entry.teacherId!);
      }
      if (entry.studentId != null) {
        ids.add(entry.studentId!);
      }
    }
    return ids;
  }

  Future<Map<int, String>> _loadUsernamesById(
    db.AppDatabase database,
    Set<int> ids,
  ) async {
    final usernamesById = <int, String>{};
    for (final id in ids) {
      final user = await database.getUserById(id);
      final username = user?.username.trim() ?? '';
      if (username.isEmpty) {
        continue;
      }
      usernamesById[id] = username;
    }
    return usernamesById;
  }

  String? _resolveUsername({
    required String? existingName,
    required String? fallbackName,
  }) {
    final normalizedExisting = existingName?.trim();
    if (normalizedExisting != null && normalizedExisting.isNotEmpty) {
      return normalizedExisting;
    }
    final normalizedFallback = fallbackName?.trim();
    if (normalizedFallback != null && normalizedFallback.isNotEmpty) {
      return normalizedFallback;
    }
    return null;
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
        actions: buildAppBarActionsWithClose(
          context,
          actions: [
            IconButton(
              onPressed: () => setState(_load),
              icon: const Icon(Icons.refresh),
              tooltip: l10n.refreshTooltip,
            ),
          ],
        ),
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
                              '${entry.model} - ${entry.modeSummary} - ${_statusLabel(entry, l10n)}',
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
      grouped.putIfAbsent(
        teacherKey,
        () => <String, Map<String, List<_ViewLlmLogEntry>>>{},
      );
      grouped[teacherKey]!.putIfAbsent(
        studentKey,
        () => <String, List<_ViewLlmLogEntry>>{},
      );
      grouped[teacherKey]![studentKey]!
          .putIfAbsent(dateKey, () => <_ViewLlmLogEntry>[]);
      grouped[teacherKey]![studentKey]![dateKey]!.add(entry);
    }
    return grouped;
  }

  Future<void> _showDetails(
    _ViewLlmLogEntry entry,
    AppLocalizations l10n,
  ) async {
    final displayText = _prettyJson(
      entry.toExchangeRecord(),
      expandEscapedNewlines: true,
    );
    final rawLogText = _prettyJson(entry.toJsonRecord());
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
                Text(l10n.llmModeValueLabel(entry.modeSummary)),
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
                SelectableText(displayText),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: rawLogText));
              if (!mounted) {
                return;
              }
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(content: Text(l10n.copySuccess)),
              );
            },
            icon: const Icon(Icons.copy),
            label: Text(l10n.copyTooltip),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.closeButton),
          ),
        ],
      ),
    );
  }

  String _prettyJson(
    Map<String, dynamic> value, {
    bool expandEscapedNewlines = false,
  }) {
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
    final encoded = const JsonEncoder.withIndent('  ').convert(cleaned);
    return expandEscapedNewlines
        ? expandEscapedNewlinesForLlmLogDisplay(encoded)
        : encoded;
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
    final status = entry.status?.trim();
    if (status != null && status.isNotEmpty) {
      return status;
    }
    if (entry.parseValid == null) {
      return l10n.llmStatusUnknown;
    }
    return entry.parseValid == true ? l10n.llmStatusOk : l10n.llmStatusError;
  }
}
