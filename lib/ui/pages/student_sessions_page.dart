import 'package:flutter/material.dart';
import 'package:family_teacher/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';

class StudentSessionsPage extends StatefulWidget {
  const StudentSessionsPage({
    super.key,
    required this.student,
    this.initialCourseVersionId,
  });

  final User student;
  final int? initialCourseVersionId;

  @override
  State<StudentSessionsPage> createState() => _StudentSessionsPageState();
}

class _StudentSessionsPageState extends State<StudentSessionsPage> {
  late Future<List<StudentSessionInfo>> _sessionsFuture;
  int? _selectedCourseVersionId;

  @override
  void initState() {
    super.initState();
    _selectedCourseVersionId = widget.initialCourseVersionId;
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
          final courseOptions = _buildCourseOptions(sessions);
          final selectedCourseVersionId =
              _resolveSelectedCourseVersionId(courseOptions);
          final filteredSessions = selectedCourseVersionId == null
              ? sessions
              : sessions
                  .where((session) =>
                      session.courseVersionId == selectedCourseVersionId)
                  .toList();

          return Column(
            children: [
              _buildFilterBar(
                courseOptions: courseOptions,
                filteredCount: filteredSessions.length,
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: filteredSessions.length,
                  itemBuilder: (context, index) {
                    final session = filteredSessions[index];
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
                    final summaryPreview = _summaryPreview(session.summaryText);
                    return ListTile(
                      title: Text(title),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(subtitleParts.join(' | ')),
                          Text('Summary LIT: ${session.summaryLit ? 'Yes' : 'No'}'),
                          if (summaryPreview.isNotEmpty)
                            Text(
                              'Summary: $summaryPreview',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                      trailing: IconButton(
                        tooltip: l10n.deleteSessionButton,
                        icon: const Icon(Icons.delete),
                        onPressed: () => _confirmDelete(session),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<_CourseFilterOption> _buildCourseOptions(
    List<StudentSessionInfo> sessions,
  ) {
    final byId = <int, _CourseFilterOption>{};
    for (final session in sessions) {
      byId.putIfAbsent(
        session.courseVersionId,
        () => _CourseFilterOption(
          courseVersionId: session.courseVersionId,
          courseSubject: (session.courseSubject ?? '').trim().isEmpty
              ? 'Course ${session.courseVersionId}'
              : session.courseSubject!.trim(),
        ),
      );
    }
    final options = byId.values.toList()
      ..sort((a, b) => a.courseSubject
          .toLowerCase()
          .compareTo(b.courseSubject.toLowerCase()));
    return options;
  }

  int? _resolveSelectedCourseVersionId(
      List<_CourseFilterOption> courseOptions) {
    if (_selectedCourseVersionId == null) {
      return null;
    }
    final exists = courseOptions.any(
      (option) => option.courseVersionId == _selectedCourseVersionId,
    );
    return exists ? _selectedCourseVersionId : null;
  }

  Widget _buildFilterBar({
    required List<_CourseFilterOption> courseOptions,
    required int filteredCount,
  }) {
    final selectedCourseVersionId =
        _resolveSelectedCourseVersionId(courseOptions);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          const Text('Course'),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<int?>(
              isExpanded: true,
              value: selectedCourseVersionId,
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('All courses'),
                ),
                ...courseOptions.map(
                  (option) => DropdownMenuItem<int?>(
                    value: option.courseVersionId,
                    child: Text(option.courseSubject),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedCourseVersionId = value;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Text('$filteredCount'),
        ],
      ),
    );
  }

  String _summaryPreview(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.length <= 220) {
      return trimmed;
    }
    return '${trimmed.substring(0, 220)}...';
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

class _CourseFilterOption {
  _CourseFilterOption({
    required this.courseVersionId,
    required this.courseSubject,
  });

  final int courseVersionId;
  final String courseSubject;
}
