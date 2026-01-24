import 'package:flutter/material.dart';
import 'package:family_teacher/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';

class LlmLogsPage extends StatefulWidget {
  const LlmLogsPage({super.key});

  @override
  State<LlmLogsPage> createState() => _LlmLogsPageState();
}

class _LlmLogsPageState extends State<LlmLogsPage> {
  Future<List<LlmLogEntry>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final db = context.read<AppDatabase>();
    _future = db.getLlmLogEntries();
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
      body: FutureBuilder<List<LlmLogEntry>>(
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
                              l10n.llmLogEntrySubtitle(
                                entry.model,
                                entry.mode,
                                _statusLabel(entry, l10n),
                              ),
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

  Map<String, Map<String, Map<String, List<LlmLogEntry>>>> _groupEntries(
    List<LlmLogEntry> entries,
    AppLocalizations l10n,
  ) {
    final grouped = <String, Map<String, Map<String, List<LlmLogEntry>>>>{};
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
    LlmLogEntry entry,
    AppLocalizations l10n,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.llmCallDetailsTitle),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.llmTimeLabel(entry.createdAt.toIso8601String())),
                Text(l10n.llmPromptLabel(entry.promptName)),
                Text(l10n.llmModeValueLabel(entry.mode)),
                Text(l10n.llmModelLabel(entry.model)),
                Text(l10n.llmBaseUrlLabel(entry.baseUrl)),
                Text(l10n.llmLatencyLabel('${entry.latencyMs ?? 0}')),
                Text(l10n.llmCallHashLabel(entry.callHash)),
                Text(_teacherLabel(entry, l10n)),
                Text(_studentLabel(entry, l10n)),
                if ((entry.kpKey ?? '').isNotEmpty)
                  Text(l10n.llmKpLabel(entry.kpKey!)),
                if ((entry.action ?? '').isNotEmpty)
                  Text(l10n.llmActionLabel(entry.action!)),
                const SizedBox(height: 12),
                Text(l10n.llmRenderedPromptLabel),
                SelectableText(entry.renderedPrompt),
                const SizedBox(height: 12),
                Text(l10n.llmResponseLabel),
                SelectableText(entry.responseText ?? ''),
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

  String _teacherLabel(LlmLogEntry entry, AppLocalizations l10n) {
    if (entry.teacherName != null && entry.teacherName!.isNotEmpty) {
      return l10n.llmTeacherLabel(entry.teacherName!);
    }
    if (entry.teacherId != null) {
      return l10n.llmTeacherIdLabel('${entry.teacherId}');
    }
    return l10n.llmTeacherUnknown;
  }

  String _studentLabel(LlmLogEntry entry, AppLocalizations l10n) {
    if (entry.studentId == null) {
      return l10n.llmStudentNone;
    }
    final name = entry.studentName?.isNotEmpty == true
        ? entry.studentName
        : null;
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

  String _statusLabel(LlmLogEntry entry, AppLocalizations l10n) {
    if (entry.parseValid == null) {
      return l10n.llmStatusUnknown;
    }
    return entry.parseValid == true ? l10n.llmStatusOk : l10n.llmStatusError;
  }
}
