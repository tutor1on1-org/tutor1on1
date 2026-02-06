import 'package:flutter/material.dart';
import 'package:family_teacher/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../services/app_services.dart';
import '../../state/auth_controller.dart';
import '../tutor_session_page.dart';

class NodeDetailPage extends StatefulWidget {
  const NodeDetailPage({
    super.key,
    required this.courseVersionId,
    required this.kpKey,
  });

  final int courseVersionId;
  final String kpKey;

  @override
  State<NodeDetailPage> createState() => _NodeDetailPageState();
}

class _NodeDetailPageState extends State<NodeDetailPage> {
  CourseVersion? _courseVersion;
  CourseNode? _node;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    _courseVersion = await db.getCourseVersionById(widget.courseVersionId);
    _node = await db.getCourseNodeByKey(
      widget.courseVersionId,
      widget.kpKey,
    );
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_node == null || _courseVersion == null) {
      return Scaffold(body: Center(child: Text(l10n.nodeNotFound)));
    }
    final auth = context.read<AuthController>();
    final currentUser = auth.currentUser;
    final studentId = currentUser?.id ?? 0;
    final isStudent = currentUser?.role == 'student';
    final db = context.read<AppDatabase>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_node!.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_node!.description),
            const SizedBox(height: 12),
            FutureBuilder<ProgressEntry?>(
              future: db.getProgress(
                studentId: studentId,
                courseVersionId: _courseVersion!.id,
                kpKey: _node!.kpKey,
              ),
              builder: (context, snapshot) {
                final entry = snapshot.data;
                final percent = entry == null
                    ? 0
                    : (entry.litPercent == 0 && entry.lit
                        ? 100
                        : entry.litPercent);
                return Text(l10n.courseProgressStatus(percent, 100));
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              key: const Key('start_session_button'),
              onPressed: () async {
                final sessions = await db.getSessionsForNode(
                  studentId: studentId,
                  courseVersionId: _courseVersion!.id,
                  kpKey: _node!.kpKey,
                );
                final existing = sessions.isNotEmpty ? sessions.last : null;
                if (existing != null) {
                  await _openSession(existing.id);
                  return;
                }
                final sessionId = await context
                    .read<AppServices>()
                    .sessionService
                    .startSession(
                      studentId: studentId,
                      courseVersionId: _courseVersion!.id,
                      kpKey: _node!.kpKey,
                    );
                if (context.mounted) {
                  await _openSession(sessionId);
                }
              },
              child: Text(l10n.startContinueSession),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.sessionHistoryTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: FutureBuilder<ProgressEntry?>(
                future: db.getProgress(
                  studentId: studentId,
                  courseVersionId: _courseVersion!.id,
                  kpKey: _node!.kpKey,
                ),
                builder: (context, progressSnapshot) {
                  final sharedSummary = progressSnapshot.data?.summaryText;
                  return FutureBuilder<List<ChatSession>>(
                    future: db.getSessionsForNode(
                      studentId: studentId,
                      courseVersionId: _courseVersion!.id,
                      kpKey: _node!.kpKey,
                    ),
                    builder: (context, snapshot) {
                      final sessions = snapshot.data ?? [];
                      if (sessions.isEmpty) {
                        return Center(child: Text(l10n.noSessionsYet));
                      }
                      return ListView.builder(
                        itemCount: sessions.length,
                        itemBuilder: (context, index) {
                          final session = sessions[index];
                          final summary = sharedSummary ??
                              session.summaryText ??
                              l10n.noSummaryYet;
                          final sessionTitle =
                              (session.title ?? '').trim().isNotEmpty
                                  ? session.title!.trim()
                                  : l10n.sessionLabel(session.id);
                          return ListTile(
                            title: Text(sessionTitle),
                            subtitle: Text(summary),
                            trailing: Wrap(
                              spacing: 8,
                              children: [
                                if (isStudent)
                                  IconButton(
                                    tooltip: l10n.renameSessionButton,
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _renameSession(session),
                                  ),
                                TextButton(
                                  onPressed: () => _openSession(session.id),
                                  child: Text(l10n.continueButton),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameSession(ChatSession session) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: session.title ?? '');
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.renameSessionTitle),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: l10n.sessionNameLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.saveButton),
          ),
        ],
      ),
    );
    if (updated == null) {
      return;
    }
    final db = context.read<AppDatabase>();
    await db.renameSession(sessionId: session.id, title: updated);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openSession(int sessionId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatSessionPage(
          sessionId: sessionId,
          courseVersion: _courseVersion!,
          node: _node!,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }
}
