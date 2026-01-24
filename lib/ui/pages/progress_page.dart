import 'package:flutter/material.dart';
import 'package:family_teacher/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key, required this.courseVersion});

  final CourseVersion courseVersion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.progressTitle(courseVersion.subject)),
      ),
      body: FutureBuilder<List<_StudentProgress>>(
        future: _loadProgress(db),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) {
            return Center(child: Text(l10n.noAssignedStudents));
          }
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return ListTile(
                title: Text(row.username),
                subtitle: Text(
                  l10n.litCountLabel(row.litCount, row.totalNodes),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<List<_StudentProgress>> _loadProgress(AppDatabase db) async {
    final assignments = await db.getAssignmentsForCourse(courseVersion.id);
    final nodes = await db.getCourseNodes(courseVersion.id);
    final total = nodes.length;
    final results = <_StudentProgress>[];
    for (final assignment in assignments) {
      final student = await db.getUserById(assignment.studentId);
      if (student == null) {
        continue;
      }
      final litCount = await db.countLitNodes(
        studentId: student.id,
        courseVersionId: courseVersion.id,
      );
      results.add(
        _StudentProgress(
          username: student.username,
          litCount: litCount,
          totalNodes: total,
        ),
      );
    }
    return results;
  }
}

class _StudentProgress {
  _StudentProgress({
    required this.username,
    required this.litCount,
    required this.totalNodes,
  });

  final String username;
  final int litCount;
  final int totalNodes;
}
