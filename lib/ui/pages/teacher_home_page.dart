import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:family_teacher/l10n/app_localizations.dart';

import '../../db/app_database.dart';
import '../../services/app_services.dart';
import '../../services/course_bundle_service.dart';
import '../../services/marketplace_api_service.dart';
import '../../state/auth_controller.dart';
import '../app_settings_page.dart';
import 'course_version_page.dart';
import 'marketplace_page.dart';
import 'prompt_settings_page.dart';
import 'skill_tree_page.dart';
import 'student_sessions_page.dart';
import 'teacher_enrollment_requests_page.dart';

class TeacherHomePage extends StatefulWidget {
  const TeacherHomePage({super.key});

  @override
  State<TeacherHomePage> createState() => _TeacherHomePageState();
}

class _TeacherHomePageState extends State<TeacherHomePage> {
  bool _syncStarted = false;
  final Set<int> _uploadingCourseIds = {};
  String? _persistentError;
  late MarketplaceApiService _marketplaceApi;

  @override
  void initState() {
    super.initState();
    final services = context.read<AppServices>();
    _marketplaceApi =
        MarketplaceApiService(secureStorage: services.secureStorage);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSync());
  }

  Future<void> _startSync() async {
    if (_syncStarted || !mounted) {
      return;
    }
    _syncStarted = true;
    final l10n = AppLocalizations.of(context)!;
    final auth = context.read<AuthController>();
    final user = auth.currentUser;
    if (user == null) {
      return;
    }
    final services = context.read<AppServices>();
    try {
      await services.sessionSyncService.syncIfReady(currentUser: user);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sessionSyncFailed('$error'))),
      );
    }
  }

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
            icon: const Icon(Icons.store),
            tooltip: l10n.marketplaceTitle,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MarketplacePage()),
              );
            },
          ),
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
            if (_persistentError != null) ...[
              _buildPersistentErrorCard(l10n),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
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
                  key: const Key('enrollment_requests_button'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TeacherEnrollmentRequestsPage(),
                      ),
                    );
                  },
                  child: Text(l10n.enrollmentRequestsButton),
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
                        trailing: IconButton(
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
                      return _CourseTile(
                        course: course,
                        isLoaded: isLoaded,
                        isUploading: _uploadingCourseIds.contains(course.id),
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
                        onUpload: isLoaded
                            ? () => _uploadCourseToMarketplace(teacher, course)
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Course / Student / Tree',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: StreamBuilder<List<CourseStudentTreeInfo>>(
                stream: db.watchCourseStudentTrees(teacher.id),
                builder: (context, snapshot) {
                  final rows = snapshot.data ?? [];
                  if (rows.isEmpty) {
                    return const Center(child: Text('No rows yet.'));
                  }
                  return ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return ListTile(
                        title: Text(
                            '${row.courseSubject} / ${row.studentUsername}'),
                        trailing: TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SkillTreePage(
                                  courseVersionId: row.courseVersionId,
                                  isTeacherView: true,
                                  teacherStudentId: row.studentId,
                                ),
                              ),
                            );
                          },
                          child: Text(l10n.treeButton),
                        ),
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

  Future<void> _uploadCourseToMarketplace(
    User teacher,
    CourseVersion course,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final sourcePath = (course.sourcePath ?? '').trim();
    if (sourcePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.courseFolderRequired)),
      );
      return;
    }
    if (_uploadingCourseIds.contains(course.id)) {
      return;
    }

    final services = context.read<AppServices>();
    final db = services.db;

    final preview = await services.courseService.previewCourseLoad(
      folderPath: sourcePath,
      courseVersionId: course.id,
    );
    if (!preview.success) {
      _setPersistentError(
        'Upload blocked: local course folder is invalid.\n${preview.message}',
      );
      return;
    }

    setState(() {
      _uploadingCourseIds.add(course.id);
    });

    File? bundleFile;
    try {
      var remoteCourseId = await db.getRemoteCourseId(course.id);
      if (remoteCourseId == null || remoteCourseId <= 0) {
        final created = await _marketplaceApi.createTeacherCourse(
          subject: course.subject,
          grade: '',
          description: 'Uploaded from Family Teacher app.',
        );
        remoteCourseId = created.courseId;
        await db.upsertCourseRemoteLink(
          courseVersionId: course.id,
          remoteCourseId: remoteCourseId,
        );
      }

      final bundleId = await _marketplaceApi.ensureBundle(remoteCourseId);
      final bundleService = CourseBundleService();
      final baseVersion = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      for (var attempt = 0; attempt < 3; attempt++) {
        final versionId = baseVersion + attempt;
        final promptMetadata = await _buildPromptBundleMetadata(
          teacher: teacher,
          course: course,
          remoteCourseId: remoteCourseId,
          versionId: versionId,
        );

        bundleFile = await bundleService.createBundleFromFolder(
          sourcePath,
          promptMetadata: promptMetadata,
        );

        try {
          await _marketplaceApi.uploadBundle(
            bundleId: bundleId,
            version: versionId,
            bundleFile: bundleFile,
          );
          await _marketplaceApi.updateCourseVisibility(
            courseId: remoteCourseId,
            visibility: 'public',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.marketplaceUploadSuccess)),
            );
          }
          break;
        } on MarketplaceApiException catch (error) {
          if (bundleFile.existsSync()) {
            await bundleFile.delete();
          }
          bundleFile = null;
          if (error.statusCode == 409 && attempt < 2) {
            continue;
          }
          rethrow;
        }
      }
    } catch (error) {
      _setPersistentError(l10n.marketplaceUploadFailed('$error'));
    } finally {
      if (bundleFile != null && bundleFile.existsSync()) {
        await bundleFile.delete();
      }
      if (mounted) {
        setState(() {
          _uploadingCourseIds.remove(course.id);
        });
      }
    }
  }

  void _setPersistentError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _persistentError = message;
    });
  }

  Widget _buildPersistentErrorCard(AppLocalizations l10n) {
    final message = _persistentError!;
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.error_outline),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(message),
            ),
            IconButton(
              tooltip: l10n.copyTooltip,
              icon: const Icon(Icons.copy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: message));
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.copySuccess)),
                );
              },
            ),
            IconButton(
              tooltip: l10n.clearButton,
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _persistentError = null;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _buildPromptBundleMetadata({
    required User teacher,
    required CourseVersion course,
    required int remoteCourseId,
    required int versionId,
  }) async {
    final db = context.read<AppDatabase>();
    final courseKey = (course.sourcePath ?? '').trim();
    if (courseKey.isEmpty) {
      throw StateError('Course path missing.');
    }

    final scopeTemplates = <PromptTemplate>[];
    final systemTemplates = await (db.select(db.promptTemplates)
          ..where((tbl) =>
              tbl.teacherId.equals(teacher.id) &
              tbl.isActive.equals(true) &
              tbl.courseKey.isNull() &
              tbl.studentId.isNull())
          ..orderBy([
            (tbl) =>
                OrderingTerm(expression: tbl.createdAt, mode: OrderingMode.desc)
          ]))
        .get();
    scopeTemplates.addAll(systemTemplates);

    final courseTemplates = await (db.select(db.promptTemplates)
          ..where((tbl) =>
              tbl.teacherId.equals(teacher.id) &
              tbl.isActive.equals(true) &
              tbl.courseKey.equals(courseKey))
          ..orderBy([
            (tbl) =>
                OrderingTerm(expression: tbl.createdAt, mode: OrderingMode.desc)
          ]))
        .get();
    scopeTemplates.addAll(courseTemplates);

    final dedupedByScope = <String, PromptTemplate>{};
    for (final template in scopeTemplates) {
      final key = [
        template.promptName,
        template.courseKey ?? '',
        template.studentId?.toString() ?? '',
      ].join('::');
      dedupedByScope.putIfAbsent(key, () => template);
    }

    final studentCache = <int, User?>{};
    final promptTemplatesPayload = <Map<String, dynamic>>[];
    for (final template in dedupedByScope.values) {
      final studentId = template.studentId;
      User? student;
      if (studentId != null) {
        student = studentCache[studentId];
        student ??= await db.getUserById(studentId);
        studentCache[studentId] = student;
      }

      String scope = 'teacher';
      if (template.courseKey != null && template.studentId == null) {
        scope = 'course';
      } else if (template.courseKey != null && template.studentId != null) {
        scope = 'student';
      }

      promptTemplatesPayload.add({
        'prompt_name': template.promptName,
        'scope': scope,
        'content': template.content,
        'student_remote_user_id': student?.remoteUserId,
        'student_username': student?.username,
        'created_at': template.createdAt.toUtc().toIso8601String(),
      });
    }

    final profilesPayload = <Map<String, dynamic>>[];
    final systemProfile = await db.getStudentPromptProfile(
      teacherId: teacher.id,
      courseKey: null,
      studentId: null,
    );
    if (systemProfile != null) {
      profilesPayload.add(
        _profileToJson(systemProfile, scope: 'teacher'),
      );
    }

    final courseProfile = await db.getStudentPromptProfile(
      teacherId: teacher.id,
      courseKey: courseKey,
      studentId: null,
    );
    if (courseProfile != null) {
      profilesPayload.add(
        _profileToJson(courseProfile, scope: 'course'),
      );
    }

    final studentProfileRows = await (db.select(db.studentPromptProfiles)
          ..where((tbl) =>
              tbl.teacherId.equals(teacher.id) &
              tbl.courseKey.equals(courseKey) &
              tbl.studentId.isNotNull())
          ..orderBy([
            (tbl) => OrderingTerm(
                  expression: tbl.updatedAt,
                  mode: OrderingMode.desc,
                ),
            (tbl) => OrderingTerm(
                  expression: tbl.createdAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();

    final studentIds = <int>{};
    for (final row in studentProfileRows) {
      final studentId = row.studentId;
      if (studentId != null) {
        studentIds.add(studentId);
      }
    }

    for (final studentId in studentIds) {
      final profile = await db.getStudentPromptProfile(
        teacherId: teacher.id,
        courseKey: courseKey,
        studentId: studentId,
      );
      if (profile == null) {
        continue;
      }
      var student = studentCache[studentId];
      student ??= await db.getUserById(studentId);
      studentCache[studentId] = student;
      profilesPayload.add(
        _profileToJson(
          profile,
          scope: 'student',
          studentRemoteUserId: student?.remoteUserId,
          studentUsername: student?.username,
        ),
      );
    }

    return {
      'schema': 'family_teacher_prompt_bundle_v1',
      'version_id': versionId,
      'remote_course_id': remoteCourseId,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'teacher_username': teacher.username,
      'prompt_templates': promptTemplatesPayload,
      'student_prompt_profiles': profilesPayload,
    };
  }

  Map<String, dynamic> _profileToJson(
    StudentPromptProfile profile, {
    required String scope,
    int? studentRemoteUserId,
    String? studentUsername,
  }) {
    return {
      'scope': scope,
      'student_remote_user_id': studentRemoteUserId,
      'student_username': studentUsername,
      'grade_level': profile.gradeLevel,
      'reading_level': profile.readingLevel,
      'preferred_language': profile.preferredLanguage,
      'interests': profile.interests,
      'preferred_tone': profile.preferredTone,
      'preferred_pace': profile.preferredPace,
      'preferred_format': profile.preferredFormat,
      'support_notes': profile.supportNotes,
      'updated_at':
          (profile.updatedAt ?? profile.createdAt).toUtc().toIso8601String(),
    };
  }

  Future<void> _confirmDeleteCourse(
    BuildContext context,
    CourseVersion course,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    final phrase =
        'I understand students ${course.subject} progress will be deleted';
    final inputController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.deleteCourseTitle(course.subject)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This deletes local and marketplace course data for this course. '
                'Students may lose progress linked to this course.',
              ),
              const SizedBox(height: 8),
              SelectableText(phrase),
              const SizedBox(height: 8),
              TextField(
                controller: inputController,
                decoration: const InputDecoration(
                  labelText: 'Type confirmation text',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancelButton),
            ),
            ElevatedButton(
              onPressed: inputController.text.trim() == phrase
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: Text(l10n.deleteButton),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }

    final remoteCourseId = await db.getRemoteCourseId(course.id);
    if (remoteCourseId != null && remoteCourseId > 0) {
      try {
        await _marketplaceApi.deleteTeacherCourse(remoteCourseId);
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete marketplace course: $error'),
            ),
          );
        }
        return;
      }
    }

    await db.deleteCourseVersion(course.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.deleteCourseSuccess)),
      );
    }
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({
    required this.course,
    required this.isLoaded,
    required this.isUploading,
    required this.onReload,
    required this.onDelete,
    required this.onUpload,
  });

  final CourseVersion course;
  final bool isLoaded;
  final bool isUploading;
  final VoidCallback onReload;
  final VoidCallback onDelete;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                course.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: Key('course_edit_${course.id}'),
              onPressed: onReload,
              child: Text(l10n.reloadCourseButton),
            ),
            IconButton(
              tooltip: l10n.deleteCourseButton,
              icon: const Icon(Icons.delete),
              onPressed: onDelete,
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: isUploading ? null : onUpload,
              child: Text(
                isUploading
                    ? l10n.marketplaceUploadingLabel
                    : l10n.marketplaceUploadButton,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
