import 'dart:async';
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
import '../../services/sync_log_repository.dart';
import '../../services/teacher_marketplace_upload_service.dart';
import '../../state/auth_controller.dart';
import '../app_close_button.dart';
import '../app_settings_page.dart';
import 'course_version_page.dart';
import 'marketplace_page.dart';
import 'prompt_settings_page.dart';
import 'skill_tree_page.dart';
import 'student_sessions_page.dart';
import 'subject_admin_page.dart';
import 'teacher_enrollment_requests_page.dart';
import '../widgets/server_sync_overlay.dart';

class TeacherHomePage extends StatefulWidget {
  const TeacherHomePage({super.key});

  @override
  State<TeacherHomePage> createState() => _TeacherHomePageState();
}

class _TeacherHomePageState extends State<TeacherHomePage> {
  static const Duration _autoSyncInterval = Duration(seconds: 60);
  bool _syncStarted = false;
  bool _syncInProgress = false;
  bool _syncingFromServer = false;
  String _syncProgressMessage = '';
  Timer? _autoSyncTimer;
  final Set<int> _uploadingCourseIds = {};
  String? _persistentMessage;
  bool _persistentMessageIsError = false;
  late MarketplaceApiService _marketplaceApi;
  late TeacherMarketplaceUploadService _uploadService;
  List<TeacherCourseSummary> _remoteTeacherCourses = [];
  List<SubjectLabelSummary> _subjectLabels = [];

  @override
  void initState() {
    super.initState();
    final services = context.read<AppServices>();
    _marketplaceApi =
        MarketplaceApiService(secureStorage: services.secureStorage);
    _uploadService = TeacherMarketplaceUploadService(
      db: services.db,
      marketplaceApi: _marketplaceApi,
      syncLogRepository: services.syncLogRepository,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshMarketplaceState();
      await _startSync();
      _startAutoSync();
    });
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> _startSync() async {
    if (_syncStarted || !mounted) {
      return;
    }
    _syncStarted = true;
    await _runSyncCycle(showOverlay: true);
  }

  void _startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(_autoSyncInterval, (_) async {
      await _runSyncCycle(showOverlay: false);
    });
  }

  Future<void> _runSyncCycle({required bool showOverlay}) async {
    if (!mounted || _syncInProgress) {
      return;
    }
    _syncInProgress = true;
    _setSyncState(
      syncing: showOverlay,
      message: showOverlay ? 'Syncing enrollments from server...' : '',
    );
    final l10n = AppLocalizations.of(context)!;
    final auth = context.read<AuthController>();
    final user = auth.currentUser;
    if (user == null) {
      _setSyncState(syncing: false, message: '');
      _syncInProgress = false;
      return;
    }
    final services = context.read<AppServices>();
    final stats = SyncRunStats();
    final trigger = showOverlay ? 'login' : 'timer';
    Object? syncError;
    try {
      stats.absorb(
        await services.enrollmentSyncService.syncIfReady(currentUser: user),
      );
      _setSyncState(
        syncing: showOverlay,
        message: showOverlay ? 'Syncing sessions from server...' : '',
      );
      stats.absorb(
        await services.sessionSyncService.syncIfReady(currentUser: user),
      );
      await _refreshMarketplaceState();
    } catch (error) {
      syncError = error;
    } finally {
      _setSyncState(syncing: false, message: '');
      _syncInProgress = false;
    }
    if (syncError != null) {
      var reportedError = '$syncError';
      try {
        await services.syncLogRepository.appendRunEvent(
          trigger: trigger,
          actorRole: user.role,
          actorUserId: user.id,
          stats: stats,
          success: false,
          error: reportedError,
        );
      } catch (logError) {
        reportedError = '$reportedError; sync log write failed: $logError';
      }
      if (!mounted) {
        return;
      }
      _setPersistentMessage(
        l10n.sessionSyncFailed(reportedError),
        isError: true,
      );
      return;
    }
    try {
      await services.syncLogRepository.appendRunEvent(
        trigger: trigger,
        actorRole: user.role,
        actorUserId: user.id,
        stats: stats,
        success: true,
      );
    } catch (logError) {
      if (!mounted) {
        return;
      }
      _setPersistentMessage(
        l10n.sessionSyncFailed('Sync log write failed: $logError'),
        isError: true,
      );
    }
  }

  Future<void> _refreshMarketplaceState() async {
    try {
      final teacherCourses = await _marketplaceApi.listTeacherCourses();
      final subjectLabels = await _marketplaceApi.listSubjectLabels();
      if (!mounted) {
        return;
      }
      setState(() {
        _remoteTeacherCourses = teacherCourses;
        _subjectLabels = subjectLabels;
      });
    } catch (_) {
      // Keep the teacher home usable even if marketplace metadata refresh fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthController>();
    final teacher = auth.currentUser!;
    final db = context.read<AppDatabase>();

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(l10n.teacherTitle(teacher.username)),
            actions: buildAppBarActionsWithClose(
              context,
              actions: [
                IconButton(
                  icon: const Icon(Icons.store),
                  tooltip: l10n.marketplaceTitle,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const MarketplacePage()),
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
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_persistentMessage != null) ...[
                  _buildPersistentMessageCard(l10n),
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
                            builder: (_) =>
                                const TeacherEnrollmentRequestsPage(),
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
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SubjectAdminPage(),
                          ),
                        );
                      },
                      child: const Text('Subject Admin'),
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
                            remoteCourse: _findRemoteCourse(course.subject),
                            isLoaded: isLoaded,
                            isUploading:
                                _uploadingCourseIds.contains(course.id),
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
                            onDelete: () =>
                                _confirmDeleteCourse(context, course),
                            onVersions: () => _openBundleVersionsPage(course),
                            onEditLabels: () =>
                                _editCourseSubjectLabels(course),
                            onUpload: isLoaded
                                ? () =>
                                    _uploadCourseToMarketplace(teacher, course)
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
                            onTap: () async {
                              final student =
                                  await db.getUserById(row.studentId);
                              if (!mounted || student == null) {
                                return;
                              }
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => StudentSessionsPage(
                                    student: student,
                                    initialCourseVersionId: row.courseVersionId,
                                  ),
                                ),
                              );
                            },
                            title: Text(
                                '${_stripVersionSuffix(row.courseSubject)} / ${row.studentUsername}'),
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
        ),
        if (_syncingFromServer)
          ServerSyncOverlay(message: _syncProgressMessage),
      ],
    );
  }

  void _setSyncState({
    required bool syncing,
    String message = '',
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      _syncingFromServer = syncing;
      _syncProgressMessage = message;
    });
  }

  Future<void> _uploadCourseToMarketplace(
    User teacher,
    CourseVersion course,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final sourcePath = (course.sourcePath ?? '').trim();
    if (sourcePath.isEmpty) {
      _setPersistentMessage(
        l10n.courseFolderRequired,
        isError: true,
      );
      return;
    }
    if (_uploadingCourseIds.contains(course.id)) {
      return;
    }

    final services = context.read<AppServices>();

    final preview = await services.courseService.previewCourseLoad(
      folderPath: sourcePath,
      courseVersionId: course.id,
    );
    if (!preview.success) {
      _setPersistentMessage(
        'Upload blocked: local course folder is invalid.\n${preview.message}',
        isError: true,
      );
      return;
    }

    setState(() {
      _uploadingCourseIds.add(course.id);
    });

    File? bundleFile;
    try {
      final target = await _uploadService.resolveUploadTarget(
        courseVersionId: course.id,
        courseSubject: course.subject,
        subjectLabelIds: _resolveRemoteCourse(course.subject)
                ?.subjectLabels
                .map((label) => label.subjectLabelId)
                .toList(growable: false) ??
            const <int>[],
      );
      final remoteCourseId = target.remoteCourseId;
      final bundleService = CourseBundleService();
      final promptMetadata = await _buildPromptBundleMetadata(
        teacher: teacher,
        course: course,
        remoteCourseId: remoteCourseId,
      );
      var cachedArtifacts =
          await services.courseArtifactService.readCourseArtifacts(course.id);
      if (cachedArtifacts == null) {
        await services.courseArtifactService.rebuildCourseArtifacts(
          courseVersionId: course.id,
          folderPath: sourcePath,
        );
        cachedArtifacts =
            await services.courseArtifactService.readCourseArtifacts(course.id);
      }
      if (cachedArtifacts == null) {
        throw StateError(
          'Cached course artifacts are missing for "${course.subject}".',
        );
      }
      final prepared = await services.courseArtifactService.prepareUploadBundle(
        courseVersionId: course.id,
        promptMetadata: promptMetadata,
        bundleLabel: course.subject,
      );
      bundleFile = prepared.bundleFile;
      final localSemanticHash = prepared.hash;
      final remoteVersions = await _marketplaceApi.listTeacherBundleVersions(
        remoteCourseId,
      );
      final latestRemoteVersion =
          remoteVersions.isNotEmpty ? remoteVersions.first : null;
      if (latestRemoteVersion != null &&
          latestRemoteVersion.hash.isNotEmpty &&
          latestRemoteVersion.hash == localSemanticHash) {
        _setPersistentMessage(
          'No file changes detected compared with latest version hash. No upload needed.',
          isError: false,
        );
        return;
      }
      if (latestRemoteVersion != null) {
        final kpDiff = await _buildKpDiffAgainstLatestBundle(
          bundleService: bundleService,
          sourcePath: sourcePath,
          latestBundleVersionId: latestRemoteVersion.bundleVersionId,
          courseSubject: course.subject,
        );
        final confirmed = await _confirmUploadWithKpDiff(
          courseSubject: course.subject,
          diff: kpDiff,
        );
        if (!confirmed) {
          _setPersistentMessage(
            'Upload cancelled by teacher.',
            isError: false,
          );
          return;
        }
      }

      final uploadResponse = await _uploadService.uploadBundleAndPublish(
        target: target,
        courseSubject: course.subject,
        bundleFile: bundleFile,
        actorUserId: teacher.id,
        actorRole: teacher.role,
        visibility: 'public',
      );
      final uploadedStatus =
          (uploadResponse['status'] as String?) ?? 'uploaded';
      if (mounted) {
        if (uploadedStatus == 'unchanged') {
          _setPersistentMessage(
            'No file changes detected. No upload needed.',
            isError: false,
          );
        } else {
          final approvalStatus =
              (uploadResponse['approval_status'] as String?) ?? '';
          if (approvalStatus == 'pending') {
            _setPersistentMessage(
              'Upload saved. Waiting for subject-admin approval before the course can be public.',
              isError: false,
            );
          } else {
            _setPersistentMessage(
              l10n.marketplaceUploadSuccess,
              isError: false,
            );
          }
        }
        await _refreshMarketplaceState();
      }
    } catch (error) {
      _setPersistentMessage(l10n.marketplaceUploadFailed('$error'));
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

  TeacherCourseSummary? _findRemoteCourse(String subject) {
    final normalized = _normalizeCourseName(_stripVersionSuffix(subject));
    for (final course in _remoteTeacherCourses) {
      final remoteNormalized =
          _normalizeCourseName(_stripVersionSuffix(course.subject));
      if (remoteNormalized == normalized) {
        return course;
      }
    }
    return null;
  }

  TeacherCourseSummary? _resolveRemoteCourse(String subject) {
    return _findRemoteCourse(subject);
  }

  Future<void> _editCourseSubjectLabels(CourseVersion course) async {
    final existing = _resolveRemoteCourse(course.subject);
    final availableLabels = _subjectLabels;
    if (availableLabels.isEmpty) {
      _setPersistentMessage(
        'No subject labels available. Ask admin to create labels first.',
        isError: true,
      );
      return;
    }
    final selected = <int>{
      for (final label
          in existing?.subjectLabels ?? const <SubjectLabelSummary>[])
        label.subjectLabelId,
    };
    if (selected.isEmpty) {
      final others = availableLabels.where((label) => label.slug == 'others');
      if (others.isNotEmpty) {
        selected.add(others.first.subjectLabelId);
      }
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Subject labels - ${course.subject}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final label in availableLabels)
                    CheckboxListTile(
                      value: selected.contains(label.subjectLabelId),
                      title: Text(label.name),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (checked) {
                        setDialogState(() {
                          if (checked == true) {
                            selected.add(label.subjectLabelId);
                          } else {
                            selected.remove(label.subjectLabelId);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      final target = existing ??
          await _marketplaceApi.createTeacherCourse(
            subject: course.subject,
            grade: '',
            description: 'Uploaded from Tutor1on1.',
            subjectLabelIds: selected.toList(growable: false),
          );
      await context.read<AppDatabase>().upsertCourseRemoteLink(
            courseVersionId: course.id,
            remoteCourseId: target.courseId,
          );
      await _marketplaceApi.updateCourseSubjectLabels(
        courseId: target.courseId,
        subjectLabelIds: selected.toList(growable: false),
      );
      await _refreshMarketplaceState();
      _setPersistentMessage(
        'Course subject labels updated.',
        isError: false,
      );
    } catch (error) {
      _setPersistentMessage('Failed to update subject labels: $error');
    }
  }

  Future<CourseKpDiffSummary> _buildKpDiffAgainstLatestBundle({
    required CourseBundleService bundleService,
    required String sourcePath,
    required int latestBundleVersionId,
    required String courseSubject,
  }) async {
    final targetPath = await bundleService.createTempBundlePath(
      label: 'latest_$courseSubject',
    );
    final targetFile = File(targetPath);
    try {
      final latestBundle = await _marketplaceApi.downloadBundleToFile(
        bundleVersionId: latestBundleVersionId,
        targetPath: targetPath,
      );
      final diff = await bundleService.compareCourseFolderWithBundle(
        folderPath: sourcePath,
        bundleFile: latestBundle,
      );
      return diff;
    } finally {
      if (targetFile.existsSync()) {
        await targetFile.delete();
      }
    }
  }

  Future<bool> _confirmUploadWithKpDiff({
    required String courseSubject,
    required CourseKpDiffSummary diff,
  }) async {
    if (!mounted) {
      return false;
    }
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Course Upload'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Course: $courseSubject'),
            const SizedBox(height: 8),
            Text('KP added: ${diff.addedCount}'),
            Text('KP deleted: ${diff.removedCount}'),
            Text('KP updated: ${diff.updatedCount}'),
            const SizedBox(height: 8),
            Text(
              diff.hasChanges
                  ? 'Detected changes against the latest server version.'
                  : 'No KP changes detected. Only non-KP metadata changed.',
            ),
            const SizedBox(height: 8),
            const Text('Upload this as a new version?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.marketplaceUploadButton),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _openBundleVersionsPage(CourseVersion course) async {
    final db = context.read<AppDatabase>();
    var remoteCourseId = await db.getRemoteCourseId(course.id);
    if (remoteCourseId == null || remoteCourseId <= 0) {
      final teacherCourses = await _marketplaceApi.listTeacherCourses();
      final courseBaseName =
          _normalizeCourseName(_stripVersionSuffix(course.subject));
      for (final remoteCourse in teacherCourses) {
        final remoteBaseName =
            _normalizeCourseName(_stripVersionSuffix(remoteCourse.subject));
        if (remoteBaseName != courseBaseName) {
          continue;
        }
        remoteCourseId = remoteCourse.courseId;
        await db.upsertCourseRemoteLink(
          courseVersionId: course.id,
          remoteCourseId: remoteCourseId,
        );
        break;
      }
    }
    if (remoteCourseId == null || remoteCourseId <= 0) {
      _setPersistentMessage(
        'No remote bundle found for "${course.subject}". Upload bundle first.',
        isError: false,
      );
      return;
    }
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _BundleVersionsPage(
          api: _marketplaceApi,
          remoteCourseId: remoteCourseId!,
          courseSubject: course.subject,
        ),
      ),
    );
  }

  void _setPersistentMessage(String message, {bool isError = true}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _persistentMessage = message;
      _persistentMessageIsError = isError;
    });
  }

  Widget _buildPersistentMessageCard(AppLocalizations l10n) {
    final message = _persistentMessage!;
    final cardColor = _persistentMessageIsError
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.secondaryContainer;
    return Card(
      color: cardColor,
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
                  _persistentMessage = null;
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
      'remote_course_id': remoteCourseId,
      'teacher_username': teacher.username,
      'prompt_templates': promptTemplatesPayload,
      'student_prompt_profiles': profilesPayload,
    };
  }

  String _normalizeCourseName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _stripVersionSuffix(String value) {
    return value.trim().replaceFirst(RegExp(r'_(\d{10,})$'), '');
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
          _setPersistentMessage(
            'Failed to delete marketplace course: $error',
            isError: true,
          );
        }
        return;
      }
    }

    await db.deleteCourseVersion(course.id);
    if (context.mounted) {
      _setPersistentMessage(
        l10n.deleteCourseSuccess,
        isError: false,
      );
    }
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({
    required this.course,
    required this.remoteCourse,
    required this.isLoaded,
    required this.isUploading,
    required this.onReload,
    required this.onDelete,
    required this.onVersions,
    required this.onEditLabels,
    required this.onUpload,
  });

  final CourseVersion course;
  final TeacherCourseSummary? remoteCourse;
  final bool isLoaded;
  final bool isUploading;
  final VoidCallback onReload;
  final VoidCallback onDelete;
  final VoidCallback onVersions;
  final VoidCallback onEditLabels;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final displaySubject =
        course.subject.trim().replaceFirst(RegExp(r'_(\d{10,})$'), '');
    final labelText =
        remoteCourse == null || remoteCourse!.subjectLabels.isEmpty
            ? 'No subject labels'
            : remoteCourse!.subjectLabels.map((label) => label.name).join(', ');
    final approvalText =
        remoteCourse == null || remoteCourse!.approvalStatus.isEmpty
            ? ''
            : 'Approval: ${remoteCourse!.approvalStatus}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              displaySubject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text('Labels: $labelText'),
            if (approvalText.isNotEmpty) Text(approvalText),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  key: Key('course_edit_${course.id}'),
                  onPressed: onReload,
                  child: Text(l10n.reloadCourseButton),
                ),
                TextButton(
                  onPressed: onEditLabels,
                  child: const Text('Subject Labels'),
                ),
                TextButton(
                  onPressed: onVersions,
                  child: const Text('Bundle Versions'),
                ),
                IconButton(
                  tooltip: l10n.deleteCourseButton,
                  icon: const Icon(Icons.delete),
                  onPressed: onDelete,
                ),
                const Spacer(),
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
          ],
        ),
      ),
    );
  }
}

class _BundleVersionsPage extends StatefulWidget {
  const _BundleVersionsPage({
    required this.api,
    required this.remoteCourseId,
    required this.courseSubject,
  });

  final MarketplaceApiService api;
  final int remoteCourseId;
  final String courseSubject;

  @override
  State<_BundleVersionsPage> createState() => _BundleVersionsPageState();
}

class _BundleVersionsPageState extends State<_BundleVersionsPage> {
  bool _loading = true;
  String? _error;
  int? _deletingVersionId;
  List<TeacherBundleVersionSummary> _versions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final versions = await widget.api.listTeacherBundleVersions(
        widget.remoteCourseId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _versions = versions;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _deleteVersion(TeacherBundleVersionSummary version) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bundle Version'),
        content: Text('Delete version ${version.version}?'),
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

    setState(() {
      _deletingVersionId = version.bundleVersionId;
    });
    try {
      await widget.api.deleteTeacherBundleVersion(
        courseId: widget.remoteCourseId,
        bundleVersionId: version.bundleVersionId,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted version ${version.version}.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _deletingVersionId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bundle Versions - ${widget.courseSubject}'),
        actions: buildAppBarActionsWithClose(
          context,
          actions: [
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Auto keep latest 5 versions after each upload.'),
            const SizedBox(height: 8),
            if (_error != null) ...[
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(_error!),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _versions.isEmpty
                      ? const Center(child: Text('No bundle versions yet.'))
                      : ListView.builder(
                          itemCount: _versions.length,
                          itemBuilder: (context, index) {
                            final version = _versions[index];
                            final deleting =
                                _deletingVersionId == version.bundleVersionId;
                            final hashDisplay = version.hash.length > 12
                                ? version.hash.substring(0, 12)
                                : version.hash;
                            return ListTile(
                              title: Text(
                                'v${version.version}'
                                '${version.isLatest ? ' (latest)' : ''}',
                              ),
                              subtitle: Text(
                                'id=${version.bundleVersionId}, hash=$hashDisplay, '
                                'size=${version.sizeBytes} bytes, created=${version.createdAt}'
                                '${version.fileMissing ? ' [file missing]' : ''}',
                              ),
                              trailing: IconButton(
                                icon: deleting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.delete_outline),
                                onPressed: deleting
                                    ? null
                                    : () => _deleteVersion(version),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
