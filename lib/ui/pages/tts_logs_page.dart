import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tutor1on1/l10n/app_localizations.dart';

import '../../services/app_services.dart';
import '../../services/tts_log_repository.dart';
import '../app_close_button.dart';

class TtsLogsPage extends StatefulWidget {
  const TtsLogsPage({super.key});

  @override
  State<TtsLogsPage> createState() => _TtsLogsPageState();
}

class _TtsLogsPageState extends State<TtsLogsPage> {
  Future<List<TtsLogEntry>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final repo = context.read<AppServices>().ttsLogRepository;
    _future = repo.loadEntries();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ttsLogsTitle),
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
      body: FutureBuilder<List<TtsLogEntry>>(
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
            return Center(child: Text(l10n.noTtsLogs));
          }
          final groups = _groupEntries(entries);
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return ListTile(
                title: Text(
                  l10n.ttsLogEntryTitle(
                    group.eventSummary,
                    _formatTime(group.time),
                  ),
                ),
                subtitle: Text(
                  l10n.ttsLogEntrySubtitle(
                    group.statusCode?.toString() ?? l10n.ttsStatusUnknown,
                  ),
                ),
                onTap: () => _showDetails(group, l10n),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showDetails(
    _TtsLogGroup group,
    AppLocalizations l10n,
  ) async {
    final ordered = group.orderedEntries;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.ttsLogDetailsTitle),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.ttsTimeLabel(group.time.toIso8601String())),
                Text(l10n.ttsEventLabel(group.eventSummary)),
                Text(l10n.ttsStatusLabel(
                  group.statusCode?.toString() ?? l10n.ttsStatusUnknown,
                )),
                if ((group.model ?? '').isNotEmpty)
                  Text(l10n.ttsModelLabel(group.model!)),
                if ((group.voice ?? '').isNotEmpty)
                  Text(l10n.ttsVoiceLabel(group.voice!)),
                if ((group.baseUrl ?? '').isNotEmpty)
                  Text(l10n.ttsBaseUrlLabel(group.baseUrl!)),
                if (group.sessionId != null)
                  Text(l10n.ttsSessionIdLabel('${group.sessionId}')),
                const SizedBox(height: 12),
                Text(l10n.ttsMessageLabel),
                ...ordered.map((entry) {
                  final status =
                      entry.statusCode?.toString() ?? l10n.ttsStatusUnknown;
                  final text =
                      '[${_formatTime(entry.createdAt)}] ${entry.event} ($status) ${entry.message}';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SelectableText(text),
                  );
                }),
                if ((group.snippet ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(l10n.ttsSnippetLabel),
                  SelectableText(group.snippet!),
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

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  List<_TtsLogGroup> _groupEntries(List<TtsLogEntry> entries) {
    const window = Duration(minutes: 2);
    final groups = <_TtsLogGroup>[];
    for (final entry in entries) {
      final snippet = (entry.textSnippet ?? '').trim();
      final hasSnippet = snippet.isNotEmpty;
      final last = groups.isNotEmpty ? groups.last : null;
      final canGroup = last != null &&
          hasSnippet &&
          last.snippet == snippet &&
          last.sessionId == entry.sessionId &&
          last.time.difference(entry.createdAt).abs() <= window;
      if (canGroup) {
        last.entries.add(entry);
      } else {
        groups.add(
          _TtsLogGroup(
            time: entry.createdAt,
            snippet: hasSnippet ? snippet : null,
            sessionId: entry.sessionId,
            model: entry.model,
            voice: entry.voice,
            baseUrl: entry.baseUrl,
            entries: [entry],
          ),
        );
      }
    }
    return groups;
  }
}

class _TtsLogGroup {
  _TtsLogGroup({
    required this.time,
    required this.entries,
    required this.sessionId,
    required this.snippet,
    required this.model,
    required this.voice,
    required this.baseUrl,
  });

  final DateTime time;
  final List<TtsLogEntry> entries;
  final int? sessionId;
  final String? snippet;
  final String? model;
  final String? voice;
  final String? baseUrl;

  int? get statusCode {
    for (final entry in orderedEntries.reversed) {
      if (entry.statusCode != null) {
        return entry.statusCode;
      }
    }
    return null;
  }

  String get eventSummary {
    final ordered = orderedEntries;
    final seen = <String>{};
    final parts = <String>[];
    for (final entry in ordered) {
      if (seen.add(entry.event)) {
        parts.add(entry.event);
      }
    }
    return parts.join(' -> ');
  }

  List<TtsLogEntry> get orderedEntries {
    final ordered = List<TtsLogEntry>.from(entries);
    ordered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return ordered;
  }
}
