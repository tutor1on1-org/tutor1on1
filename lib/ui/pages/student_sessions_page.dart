import 'package:flutter/material.dart';
import 'package:family_teacher/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';

class StudentSessionsPage extends StatefulWidget {
  const StudentSessionsPage({super.key, required this.student});

  final User student;

  @override
  State<StudentSessionsPage> createState() => _StudentSessionsPageState();
}

class _StudentSessionsPageState extends State<StudentSessionsPage> {
  late Future<List<StudentSessionInfo>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _sessionsFuture = _loadSessions();
  }

  Future<List<StudentSessionInfo>> _loadSessions() {
    final db = context.read<AppDatabase>();
    return db.getSessionsForStudent(widget.student.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.studentSessionsTitle(widget.student.username)),
      ),
      body: FutureBuilder<List<StudentSessionInfo>>(
        future: _sessionsFuture,
        builder: (context, snapshot) {
          final sessions = snapshot.data ?? [];
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (sessions.isEmpty) {
            return Center(child: Text(l10n.noStudentSessions));
          }
          return ListView.builder(
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              final title = (session.sessionTitle ?? '').trim().isNotEmpty
                  ? session.sessionTitle!.trim()
                  : l10n.sessionLabel(session.sessionId);
              final subtitleParts = <String>[
                if ((session.courseSubject ?? '').trim().isNotEmpty)
                  l10n.sessionCourseLabel(session.courseSubject!.trim()),
                if ((session.nodeTitle ?? '').trim().isNotEmpty)
                  l10n.sessionNodeLabel(session.nodeTitle!.trim()),
                l10n.sessionStartedLabel(_formatDate(session.startedAt)),
              ];
              return ListTile(
                title: Text(title),
                subtitle: Text(subtitleParts.join(' • ')),
                trailing: IconButton(
                  tooltip: l10n.deleteSessionButton,
                  icon: const Icon(Icons.delete),
                  onPressed: () => _confirmDelete(session),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(StudentSessionInfo session) async {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    final title = (session.sessionTitle ?? '').trim().isNotEmpty
        ? session.sessionTitle!.trim()
        : l10n.sessionLabel(session.sessionId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteSessionTitle(title)),
        content: Text(l10n.deleteSessionMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await db.deleteSession(session.sessionId);
    if (!mounted) {
      return;
    }
    setState(() => _sessionsFuture = _loadSessions());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.deleteSessionSuccess)),
    );
  }

  String _formatDate(DateTime value) {
    final date =
        '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    final time =
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}
