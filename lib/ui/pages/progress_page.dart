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
                  l10n.litCountLabel(row.progressPercent, row.totalNodes),
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
    final nodeIds = nodes.map((node) => node.kpKey).toSet();
    final results = <_StudentProgress>[];
    for (final assignment in assignments) {
      final student = await db.getUserById(assignment.studentId);
      if (student == null) {
        continue;
      }
      final progress = await db.getProgressForCourse(
        studentId: student.id,
        courseVersionId: courseVersion.id,
      );
      final percent = _calculateProgressPercent(progress, nodeIds);
      results.add(
        _StudentProgress(
          username: student.username,
          progressPercent: percent,
          totalNodes: total,
        ),
      );
    }
    return results;
  }

  int _calculateProgressPercent(
    List<ProgressEntry> progress,
    Set<String> nodeIds,
  ) {
    if (nodeIds.isEmpty) {
      return 0;
    }
    var sum = 0;
    for (final entry in progress) {
      if (!nodeIds.contains(entry.kpKey)) {
        continue;
      }
      final percent = entry.litPercent;
      final clamped = percent.clamp(0, 100);
      sum += clamped;
    }
    final ratio = sum / (nodeIds.length * 100);
    return (ratio * 100).round();
  }
}

class _StudentProgress {
  _StudentProgress({
    required this.username,
    required this.progressPercent,
    required this.totalNodes,
  });

  final String username;
  final int progressPercent;
  final int totalNodes;
}
