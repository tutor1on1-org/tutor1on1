import 'package:flutter/material.dart';
import 'package:family_teacher/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../models/skill_tree.dart';
import '../../state/auth_controller.dart';
import '../app_settings_page.dart';
import 'skill_tree_page.dart';

class StudentHomePage extends StatelessWidget {
  const StudentHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthController>();
    final student = auth.currentUser!;
    final db = context.read<AppDatabase>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.studentTitle(student.username)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => auth.logout(),
          ),
        ],
      ),
      body: StreamBuilder<List<CourseVersion>>(
        stream: db.watchAssignedCourses(student.id),
        builder: (context, snapshot) {
          final courses = snapshot.data ?? [];
          if (courses.isEmpty) {
            return Center(child: Text(l10n.noAssignedCourses));
          }
          return ListView.builder(
            itemCount: courses.length,
            itemBuilder: (context, index) {
              final course = courses[index];
              final isLoaded = course.sourcePath != null &&
                  course.sourcePath!.trim().isNotEmpty;
              return _CourseProgressTile(
                course: course,
                studentId: student.id,
                enabled: isLoaded,
                onTap: isLoaded
                    ? () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SkillTreePage(
                              courseVersionId: course.id,
                              isTeacherView: false,
                            ),
                          ),
                        );
                      }
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

class _CourseProgressTile extends StatefulWidget {
  const _CourseProgressTile({
    required this.course,
    required this.studentId,
    required this.enabled,
    required this.onTap,
  });

  final CourseVersion course;
  final int studentId;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  State<_CourseProgressTile> createState() => _CourseProgressTileState();
}

class _CourseProgressTileState extends State<_CourseProgressTile> {
  int _totalLeaves = 0;
  Set<String> _leafIds = const {};

  @override
  void initState() {
    super.initState();
    _computeLeafCount();
  }

  @override
  void didUpdateWidget(covariant _CourseProgressTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.course.textbookText != widget.course.textbookText) {
      _computeLeafCount();
    }
  }

  void _computeLeafCount() {
    var count = 0;
    var leafIds = <String>{};
    try {
      final parser = SkillTreeParser();
      final result = parser.parse(widget.course.textbookText);
      leafIds = result.nodes.values
          .where((node) => !node.isPlaceholder)
          .where((node) => node.children.isEmpty)
          .map((node) => node.id)
          .toSet();
      count = leafIds.length;
    } catch (_) {
      count = 0;
      leafIds = <String>{};
    }
    if (count == _totalLeaves && leafIds.length == _leafIds.length) {
      return;
    }
    setState(() {
      _totalLeaves = count;
      _leafIds = leafIds;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    return StreamBuilder<List<ProgressEntry>>(
      stream:
          db.watchProgressForCourse(widget.studentId, widget.course.id),
      builder: (context, snapshot) {
        final progress = snapshot.data ?? [];
        final litCount = progress
            .where((entry) => entry.lit)
            .where((entry) => _leafIds.contains(entry.kpKey))
            .length;
        return ListTile(
          key: Key('course_item_${widget.course.id}'),
          title: Text(widget.course.subject),
          subtitle: Text(
            l10n.courseProgressStatus(litCount, _totalLeaves),
          ),
          enabled: widget.enabled,
          onTap: widget.onTap,
        );
      },
    );
  }
}
