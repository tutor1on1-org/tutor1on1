import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../services/app_services.dart';
import '../../state/auth_controller.dart';
import '../app_close_button.dart';
import '../tutor_session_page.dart';

class MistakeBookPage extends StatefulWidget {
  const MistakeBookPage({
    super.key,
    required this.studentId,
    this.courseVersionId,
    this.readOnly = false,
  });

  final int studentId;
  final int? courseVersionId;
  final bool readOnly;

  @override
  State<MistakeBookPage> createState() => _MistakeBookPageState();
}

class _MistakeBookPageState extends State<MistakeBookPage> {
  String _statusFilter = 'open';
  bool _materializeStarted = false;
  Object? _materializeError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_materializeStarted && widget.readOnly) {
      _materializeStarted = true;
      _materializeTeacherArtifacts();
    }
  }

  Future<void> _materializeTeacherArtifacts() async {
    final currentUser = context.read<AuthController>().currentUser;
    if (currentUser == null || currentUser.role != 'teacher') {
      return;
    }
    try {
      await context
          .read<AppServices>()
          .sessionSyncService
          .materializeTeacherArtifactsForView(
            currentUser: currentUser,
            localStudentId: widget.studentId,
            courseVersionId: widget.courseVersionId,
          );
    } catch (error) {
      if (mounted) {
        setState(() => _materializeError = error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mistake Book'),
        actions: buildAppBarActionsWithClose(context),
      ),
      body: Column(
        children: [
          if (_materializeError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: MaterialBanner(
                content: Text('Could not refresh mistakes: $_materializeError'),
                actions: [
                  TextButton(
                    onPressed: () {
                      setState(() => _materializeError = null);
                      _materializeTeacherArtifacts();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _statusFilter,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'open', child: Text('Open')),
                      DropdownMenuItem(
                        value: 'dismissed',
                        child: Text('Dismissed'),
                      ),
                      DropdownMenuItem(value: 'all', child: Text('All')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _statusFilter = value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<MistakeEntry>>(
              stream: db.watchMistakeEntriesForStudent(
                widget.studentId,
                courseVersionId: widget.courseVersionId,
              ),
              builder: (context, snapshot) {
                final entries = _filterEntries(snapshot.data ?? []);
                if (entries.isEmpty) {
                  return const Center(child: Text('No mistakes yet.'));
                }
                return FutureBuilder<_MistakeBookLookups>(
                  future: _loadLookups(db, entries),
                  builder: (context, lookupSnapshot) {
                    final lookups = lookupSnapshot.data;
                    return ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final courseTitle =
                            lookups?.courseTitles[entry.courseVersionId] ??
                                'Course ${entry.courseVersionId}';
                        final nodeTitle =
                            lookups?.nodeTitles[_nodeLookupKey(entry)] ??
                                entry.kpKey;
                        return _MistakeTile(
                          entry: entry,
                          courseTitle: courseTitle,
                          nodeTitle: nodeTitle,
                          readOnly: widget.readOnly,
                          onReview: widget.readOnly
                              ? null
                              : () => _openReviewSession(entry),
                          onToggleDismissed: widget.readOnly
                              ? null
                              : () => _toggleDismissed(entry),
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
    );
  }

  List<MistakeEntry> _filterEntries(List<MistakeEntry> entries) {
    final filtered = entries.where((entry) {
      switch (_statusFilter) {
        case 'open':
          return entry.status == 'open' && !entry.dismissed;
        case 'dismissed':
          return entry.dismissed || entry.status == 'dismissed';
        default:
          return true;
      }
    }).toList(growable: false);
    filtered.sort((left, right) => right.lastSeenAt.compareTo(left.lastSeenAt));
    return filtered;
  }

  Future<_MistakeBookLookups> _loadLookups(
    AppDatabase db,
    List<MistakeEntry> entries,
  ) async {
    final courseTitles = <int, String>{};
    final nodeTitles = <String, String>{};
    for (final entry in entries) {
      courseTitles[entry.courseVersionId] ??=
          (await db.getCourseVersionById(entry.courseVersionId))
                  ?.subject
                  .trim() ??
              'Course ${entry.courseVersionId}';
      final nodeKey = _nodeLookupKey(entry);
      if (!nodeTitles.containsKey(nodeKey)) {
        final node = await db.getCourseNodeByKey(
          entry.courseVersionId,
          entry.kpKey,
        );
        nodeTitles[nodeKey] =
            node == null ? entry.kpKey : '${entry.kpKey}: ${node.title.trim()}';
      }
    }
    return _MistakeBookLookups(
      courseTitles: courseTitles,
      nodeTitles: nodeTitles,
    );
  }

  Future<void> _openReviewSession(MistakeEntry entry) async {
    final db = context.read<AppDatabase>();
    final course = await db.getCourseVersionById(entry.courseVersionId);
    final node =
        await db.getCourseNodeByKey(entry.courseVersionId, entry.kpKey);
    if (!mounted) {
      return;
    }
    if (course == null || node == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Course data is missing.')),
      );
      return;
    }
    final sessionService = context.read<AppServices>().sessionService;
    final sessionId = await sessionService.startSession(
      studentId: widget.studentId,
      courseVersionId: entry.courseVersionId,
      kpKey: entry.kpKey,
      title: 'Review: ${entry.mistakeTagRaw}',
    );
    sessionService.setPendingMistakeFocusTag(
      sessionId: sessionId,
      tag: entry.mistakeTagRaw,
    );
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatSessionPage(
          sessionId: sessionId,
          courseVersion: course,
          node: node,
          startInReview: true,
        ),
      ),
    );
  }

  Future<void> _toggleDismissed(MistakeEntry entry) async {
    final dismiss = !entry.dismissed && entry.status != 'dismissed';
    if (dismiss) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Dismiss mistake?'),
          content: Text(entry.mistakeTagRaw),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
    await context.read<AppDatabase>().setMistakeEntryStatus(
          id: entry.id,
          status: dismiss ? 'dismissed' : 'open',
          dismissed: dismiss,
        );
  }

  String _nodeLookupKey(MistakeEntry entry) {
    return '${entry.courseVersionId}:${entry.kpKey}';
  }
}

class _MistakeTile extends StatelessWidget {
  const _MistakeTile({
    required this.entry,
    required this.courseTitle,
    required this.nodeTitle,
    required this.readOnly,
    required this.onReview,
    required this.onToggleDismissed,
  });

  final MistakeEntry entry;
  final String courseTitle;
  final String nodeTitle;
  final bool readOnly;
  final VoidCallback? onReview;
  final VoidCallback? onToggleDismissed;

  @override
  Widget build(BuildContext context) {
    final note = (entry.mistakeNote ?? '').trim();
    final question = (entry.questionExcerpt ?? '').trim();
    return ListTile(
      leading: const Icon(Icons.error_outline),
      title: Text(entry.mistakeTagRaw),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$courseTitle - $nodeTitle'),
          Text('Seen ${entry.occurrences} time(s)'),
          if (note.isNotEmpty) Text(note),
          if (question.isNotEmpty)
            Text(
              question,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: readOnly
          ? null
          : Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: 'Review',
                  icon: const Icon(Icons.play_arrow),
                  onPressed: onReview,
                ),
                IconButton(
                  tooltip: entry.dismissed ? 'Reopen' : 'Dismiss',
                  icon: Icon(
                    entry.dismissed ? Icons.undo : Icons.check_circle_outline,
                  ),
                  onPressed: onToggleDismissed,
                ),
              ],
            ),
    );
  }
}

class _MistakeBookLookups {
  const _MistakeBookLookups({
    required this.courseTitles,
    required this.nodeTitles,
  });

  final Map<int, String> courseTitles;
  final Map<String, String> nodeTitles;
}
