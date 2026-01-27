import 'package:flutter/material.dart';
import 'package:family_teacher/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../models/skill_tree.dart';
import '../../security/pin_hasher.dart';
import '../../services/app_services.dart';
import '../../state/auth_controller.dart';
import 'course_version_page.dart';
import 'prompt_settings_page.dart';
import '../app_settings_page.dart';
import 'skill_tree_page.dart';
import 'student_sessions_page.dart';

class TeacherHomePage extends StatelessWidget {
  const TeacherHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthController>();
    final teacher = auth.currentUser!;
    final db = context.read<AppDatabase>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.teacherTitle(teacher.username)),
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  key: const Key('create_student_button'),
                  onPressed: () =>
                      _showCreateStudentDialog(context, teacher.id),
                  child: Text(l10n.createStudentButton),
                ),
                ElevatedButton(
                  key: const Key('create_course_button'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            CourseVersionPage(teacherId: teacher.id),
                      ),
                    );
                  },
                  child: Text(l10n.createCourseButton),
                ),
                ElevatedButton(
                  key: const Key('create_teacher_button'),
                  onPressed: () => _showCreateTeacherDialog(context),
                  child: Text(l10n.createTeacherButton),
                ),
                ElevatedButton(
                  key: const Key('prompt_settings_button'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PromptSettingsPage(
                          teacherId: teacher.id,
                        ),
                      ),
                    );
                  },
                  child: Text(l10n.promptTemplatesButton),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              l10n.studentsSection,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: StreamBuilder<List<User>>(
                stream: db.watchStudents(teacher.id),
                builder: (context, snapshot) {
                  final students = snapshot.data ?? [];
                  if (students.isEmpty) {
                    return Center(child: Text(l10n.noStudents));
                  }
                  return ListView.builder(
                    itemCount: students.length,
                    itemBuilder: (context, index) {
                      final student = students[index];
                      return ListTile(
                        title: Text(student.username),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            IconButton(
                              tooltip: l10n.resetPinButton,
                              icon: const Icon(Icons.lock_reset),
                              onPressed: () => _showResetStudentPinDialog(
                                context,
                                student,
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.studentSessionsButton,
                              icon: const Icon(Icons.history),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        StudentSessionsPage(student: student),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              tooltip: l10n.deleteStudentButton,
                              icon: const Icon(Icons.delete),
                              onPressed: () =>
                                  _confirmDeleteStudent(context, student),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.coursesSection,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: StreamBuilder<List<CourseVersion>>(
                stream: db.watchCourseVersions(teacher.id),
                builder: (context, snapshot) {
                  final courses = snapshot.data ?? [];
                  if (courses.isEmpty) {
                    return Center(child: Text(l10n.noCourses));
                  }
                  return ListView.builder(
                    itemCount: courses.length,
                    itemBuilder: (context, index) {
                      final course = courses[index];
                      final isLoaded = course.sourcePath != null &&
                          course.sourcePath!.trim().isNotEmpty;
                      return _CourseAssignmentTile(
                        course: course,
                        teacherId: teacher.id,
                        isLoaded: isLoaded,
                        onReload: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CourseVersionPage(
                                teacherId: teacher.id,
                                courseVersionId: course.id,
                              ),
                            ),
                          );
                        },
                        onDelete: () => _confirmDeleteCourse(context, course),
                        onViewTree: isLoaded
                            ? () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => SkillTreePage(
                                      courseVersionId: course.id,
                                      isTeacherView: true,
                                    ),
                                  ),
                                );
                              }
                            : null,
                        onAssign: isLoaded
                            ? () => _showAssignDialog(
                                  context,
                                  course.id,
                                  teacher.id,
                                )
                            : null,
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

  Future<void> _showCreateStudentDialog(
    BuildContext context,
    int teacherId,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final usernameController = TextEditingController();
    final pinController = TextEditingController();
    final db = context.read<AppDatabase>();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.createStudentDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: usernameController,
              decoration: InputDecoration(labelText: l10n.usernameLabel),
            ),
            TextField(
              controller: pinController,
              decoration: InputDecoration(labelText: l10n.pinLabel),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () async {
              final username = usernameController.text.trim();
              final pin = pinController.text.trim();
              if (username.isEmpty || pin.isEmpty) {
                return;
              }
              try {
                await db.createUser(
                  username: username,
                  pinHash: PinHasher.hash(pin),
                  role: 'student',
                  teacherId: teacherId,
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.createFailedMessage('$e'))),
                  );
                }
                return;
              }
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Text(l10n.createDialogCreate),
          ),
        ],
      ),
    );
  }

  Future<void> _showAssignDialog(
    BuildContext context,
    int courseVersionId,
    int teacherId,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    final students = await db.watchStudents(teacherId).first;
    if (students.isEmpty) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.assignDialogNoStudents)),
      );
      return;
    }
    int? selectedId = students.first.id;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.assignDialogTitle),
        content: DropdownButton<int>(
          value: selectedId,
          items: students
              .map(
                (student) => DropdownMenuItem(
                  value: student.id,
                  child: Text(student.username),
                ),
              )
              .toList(),
          onChanged: (value) => selectedId = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () async {
              if (selectedId == null) {
                return;
              }
              await db.assignStudent(
                studentId: selectedId!,
                courseVersionId: courseVersionId,
              );
              final services = context.read<AppServices>();
              await services.promptRepository.ensureAssignmentPrompts(
                teacherId: teacherId,
                studentId: selectedId!,
                courseVersionId: courseVersionId,
              );
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Text(l10n.assignConfirmButton),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateTeacherDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final usernameController = TextEditingController();
    final pinController = TextEditingController();
    final db = context.read<AppDatabase>();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.createTeacherDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: usernameController,
              decoration: InputDecoration(labelText: l10n.usernameLabel),
            ),
            TextField(
              controller: pinController,
              decoration: InputDecoration(labelText: l10n.pinLabel),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () async {
              final username = usernameController.text.trim();
              final pin = pinController.text.trim();
              if (username.isEmpty || pin.isEmpty) {
                return;
              }
              try {
                await db.createUser(
                  username: username,
                  pinHash: PinHasher.hash(pin),
                  role: 'teacher',
                  teacherId: null,
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.createFailedMessage('$e'))),
                  );
                }
                return;
              }
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.teacherCreatedMessage)),
                );
              }
            },
            child: Text(l10n.createDialogCreate),
          ),
        ],
      ),
    );
  }

  Future<void> _showResetStudentPinDialog(
    BuildContext context,
    User student,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final pinController = TextEditingController();
    final db = context.read<AppDatabase>();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.resetPinDialogTitle(student.username)),
        content: TextField(
          controller: pinController,
          decoration: InputDecoration(labelText: l10n.pinLabel),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () async {
              final pin = pinController.text.trim();
              if (pin.isEmpty) {
                return;
              }
              await db.updateUserPin(
                userId: student.id,
                pinHash: PinHasher.hash(pin),
              );
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.pinUpdatedMessage)),
                );
              }
            },
            child: Text(l10n.confirmButton),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteStudent(
    BuildContext context,
    User student,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteStudentTitle(student.username)),
        content: Text(l10n.deleteStudentMessage),
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
    await db.deleteStudent(student.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.deleteStudentSuccess)),
      );
    }
  }

  Future<void> _confirmDeleteCourse(
    BuildContext context,
    CourseVersion course,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteCourseTitle(course.subject)),
        content: Text(l10n.deleteCourseMessage),
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
    await db.deleteCourseVersion(course.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.deleteCourseSuccess)),
      );
    }
  }
}

class _CourseAssignmentTile extends StatefulWidget {
  const _CourseAssignmentTile({
    required this.course,
    required this.teacherId,
    required this.isLoaded,
    required this.onReload,
    required this.onDelete,
    required this.onViewTree,
    required this.onAssign,
  });

  final CourseVersion course;
  final int teacherId;
  final bool isLoaded;
  final VoidCallback onReload;
  final VoidCallback onDelete;
  final VoidCallback? onViewTree;
  final VoidCallback? onAssign;

  @override
  State<_CourseAssignmentTile> createState() => _CourseAssignmentTileState();
}

class _CourseAssignmentTileState extends State<_CourseAssignmentTile> {
  int _totalLeaves = 0;
  Set<String> _leafIds = const {};

  @override
  void initState() {
    super.initState();
    _computeLeafCount();
  }

  @override
  void didUpdateWidget(covariant _CourseAssignmentTile oldWidget) {
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
    final db = context.read<AppDatabase>();
    final l10n = AppLocalizations.of(context)!;
    return StreamBuilder<List<StudentCourseAssignment>>(
      stream: db.watchAssignmentsForCourse(widget.course.id),
      builder: (context, assignmentSnapshot) {
        final assignments = assignmentSnapshot.data ?? [];
        final assignment = assignments.isNotEmpty ? assignments.first : null;
        final assignedStudentId = assignment?.studentId;
        final assignEnabled =
            widget.isLoaded && assignedStudentId == null && widget.onAssign != null;
        return StreamBuilder<List<ProgressEntry>>(
          stream: assignedStudentId == null
              ? const Stream<List<ProgressEntry>>.empty()
              : db.watchProgressForCourse(
                  assignedStudentId,
                  widget.course.id,
                ),
          builder: (context, progressSnapshot) {
            final progress = progressSnapshot.data ?? [];
            final litCount = assignedStudentId == null
                ? 0
                : progress
                    .where((entry) => entry.lit)
                    .where((entry) => _leafIds.contains(entry.kpKey))
                    .length;
            return FutureBuilder<User?>(
              future: assignedStudentId == null
                  ? Future<User?>.value(null)
                  : db.getUserById(assignedStudentId),
              builder: (context, studentSnapshot) {
                final studentName = studentSnapshot.data?.username;
                final titleText = studentName == null
                    ? widget.course.subject
                    : '${widget.course.subject} • $studentName ($litCount/$_totalLeaves)';
                return Card(
                  child: ListTile(
                    key: Key('course_item_${widget.course.id}'),
                    title: Text(titleText),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          key: Key('course_edit_${widget.course.id}'),
                          onPressed: widget.onReload,
                          child: Text(
                            widget.isLoaded
                                ? l10n.reloadCourseButton
                                : l10n.loadCourseButton,
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.deleteCourseButton,
                          icon: const Icon(Icons.delete),
                          onPressed: widget.onDelete,
                        ),
                        TextButton(
                          style: widget.isLoaded
                              ? null
                              : TextButton.styleFrom(
                                  foregroundColor:
                                      Theme.of(context).disabledColor,
                                ),
                          onPressed: widget.onViewTree,
                          child: Text(l10n.treeButton),
                        ),
                        TextButton(
                          onPressed: assignEnabled ? widget.onAssign : null,
                          child: Text(l10n.assignButton),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
