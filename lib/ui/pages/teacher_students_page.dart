import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tutor1on1/l10n/app_localizations.dart';

import '../../db/app_database.dart';
import '../app_close_button.dart';
import 'mistake_book_page.dart';
import 'skill_tree_page.dart';
import 'student_sessions_page.dart';

class TeacherStudentsPage extends StatefulWidget {
  const TeacherStudentsPage({
    super.key,
    required this.teacherId,
  });

  final int teacherId;

  @override
  State<TeacherStudentsPage> createState() => _TeacherStudentsPageState();
}

class _TeacherStudentsPageState extends State<TeacherStudentsPage> {
  int? _selectedStudentId;
  int? _selectedCourseVersionId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.studentsSection),
        actions: buildAppBarActionsWithClose(context),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<List<User>>(
          stream: db.watchStudents(widget.teacherId),
          builder: (context, studentSnapshot) {
            final students = studentSnapshot.data ?? [];
            if (students.isEmpty) {
              return Center(child: Text(l10n.noStudents));
            }
            final selectedStudent = _resolveSelectedStudent(students);
            return StreamBuilder<List<CourseStudentTreeInfo>>(
              stream: db.watchCourseStudentTrees(widget.teacherId),
              builder: (context, treeSnapshot) {
                final rows = (treeSnapshot.data ?? [])
                    .where((row) => row.studentId == selectedStudent.id)
                    .toList();
                final selectedCourse = _resolveSelectedCourse(rows);
                return Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: const Key('teacher_students_student_dropdown'),
                            initialValue: selectedStudent.id,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Student',
                              border: OutlineInputBorder(),
                            ),
                            items: students
                                .map(
                                  (student) => DropdownMenuItem<int>(
                                    value: student.id,
                                    child: Text(student.username),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _selectedStudentId = value;
                                _selectedCourseVersionId = null;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: const Key('teacher_students_course_dropdown'),
                            initialValue: selectedCourse?.courseVersionId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Course',
                              border: OutlineInputBorder(),
                            ),
                            items: rows
                                .map(
                                  (row) => DropdownMenuItem<int>(
                                    value: row.courseVersionId,
                                    child: Text(
                                      _stripVersionSuffix(row.courseSubject),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: rows.isEmpty
                                ? null
                                : (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setState(() {
                                      _selectedCourseVersionId = value;
                                    });
                                  },
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 56,
                          child: OutlinedButton.icon(
                            key: const Key('teacher_students_sessions_button'),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => StudentSessionsPage(
                                    student: selectedStudent,
                                    initialCourseVersionId:
                                        selectedCourse?.courseVersionId,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.history),
                            label: Text(l10n.studentSessionsButton),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 56,
                          width: 56,
                          child: Tooltip(
                            message: 'Mistake Book',
                            child: IconButton.outlined(
                              key: const Key(
                                'teacher_students_mistake_book_button',
                              ),
                              onPressed: selectedCourse == null
                                  ? null
                                  : () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => MistakeBookPage(
                                            studentId: selectedStudent.id,
                                            courseVersionId:
                                                selectedCourse.courseVersionId,
                                            readOnly: true,
                                          ),
                                        ),
                                      );
                                    },
                              icon: const Icon(Icons.menu_book_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: selectedCourse == null
                          ? const Center(
                              child: Text('No assigned courses yet.'),
                            )
                          : SkillTreePage(
                              key: ValueKey(
                                'teacher_student_tree_'
                                '${selectedStudent.id}_'
                                '${selectedCourse.courseVersionId}',
                              ),
                              courseVersionId: selectedCourse.courseVersionId,
                              isTeacherView: true,
                              teacherStudentId: selectedStudent.id,
                              titleOverride: _stripVersionSuffix(
                                  selectedCourse.courseSubject),
                              embedded: true,
                            ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  User _resolveSelectedStudent(List<User> students) {
    final selectedId = _selectedStudentId;
    final selected = selectedId == null
        ? null
        : students.where((student) => student.id == selectedId).firstOrNull;
    if (selected != null) {
      return selected;
    }
    final fallback = students.first;
    _selectedStudentId = fallback.id;
    return fallback;
  }

  CourseStudentTreeInfo? _resolveSelectedCourse(
    List<CourseStudentTreeInfo> rows,
  ) {
    final selectedId = _selectedCourseVersionId;
    final selected = selectedId == null
        ? null
        : rows.where((row) => row.courseVersionId == selectedId).firstOrNull;
    if (selected != null) {
      return selected;
    }
    final fallback = rows.firstOrNull;
    _selectedCourseVersionId = fallback?.courseVersionId;
    return fallback;
  }
}

String _stripVersionSuffix(String value) {
  return value.trim().replaceFirst(RegExp(r'_(\d{10,})$'), '');
}
