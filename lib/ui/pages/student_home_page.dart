import 'dart:async';

import 'package:flutter/material.dart';
import 'package:family_teacher/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../models/skill_tree.dart';
import '../../services/app_services.dart';
import '../../services/marketplace_api_service.dart';
import '../../services/sync_log_repository.dart';
import '../../state/auth_controller.dart';
import '../app_settings_page.dart';
import 'marketplace_page.dart';
import 'skill_tree_page.dart';
import '../widgets/server_sync_overlay.dart';

class StudentHomePage extends StatefulWidget {
  const StudentHomePage({super.key});

  @override
  State<StudentHomePage> createState() => _StudentHomePageState();
}

class _StudentHomePageState extends State<StudentHomePage> {
  static const Duration _autoSyncInterval = Duration(seconds: 60);
  bool _syncStarted = false;
  bool _syncInProgress = false;
  bool _syncingFromServer = false;
  String _syncProgressMessage = '';
  Timer? _autoSyncTimer;
  late final MarketplaceApiService _marketplaceApi;
  final Map<int, int> _remoteCourseIdByLocalCourseId = {};
  final Map<int, EnrollmentSummary> _enrollmentsByRemoteCourseId = {};
  final Set<int> _pendingQuitRemoteCourseIds = {};
  final Set<int> _submittingQuitCourseIds = {};
  String? _persistentMessage;
  bool _persistentMessageIsError = false;

  @override
  void initState() {
    super.initState();
    final services = context.read<AppServices>();
    _marketplaceApi =
        MarketplaceApiService(secureStorage: services.secureStorage);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _startSync();
      _startAutoSync();
    });
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshRemoteEnrollmentState() async {
    if (!mounted) {
      return;
    }
    final auth = context.read<AuthController>();
    final user = auth.currentUser;
    if (user == null || user.role != 'student') {
      return;
    }
    final remoteUserId = user.remoteUserId;
    if (remoteUserId == null || remoteUserId <= 0) {
      return;
    }
    final services = context.read<AppServices>();
    try {
      final assignedRemoteCourses =
          await services.db.getAssignedRemoteCoursesForStudent(user.id);
      final enrollments = await _marketplaceApi.listEnrollments();
      final quitRequests = await _marketplaceApi.listStudentQuitRequests();
      if (!mounted) {
        return;
      }
      final remoteByLocal = <int, int>{};
      for (final item in assignedRemoteCourses) {
        remoteByLocal[item.courseVersionId] = item.remoteCourseId;
      }
      final enrollmentByRemote = <int, EnrollmentSummary>{};
      for (final enrollment in enrollments) {
        enrollmentByRemote[enrollment.courseId] = enrollment;
      }
      final pendingQuitRemoteCourses = <int>{};
      for (final request in quitRequests) {
        if (request.status == 'pending') {
          pendingQuitRemoteCourses.add(request.courseId);
        }
      }
      setState(() {
        _remoteCourseIdByLocalCourseId
          ..clear()
          ..addAll(remoteByLocal);
        _enrollmentsByRemoteCourseId
          ..clear()
          ..addAll(enrollmentByRemote);
        _pendingQuitRemoteCourseIds
          ..clear()
          ..addAll(pendingQuitRemoteCourses);
      });
    } catch (error) {
      _setPersistentMessage('Failed to load enrollment state: $error');
    }
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
        message: showOverlay ? 'Syncing sessions/progress from server...' : '',
      );
      stats.absorb(
        await services.sessionSyncService.syncIfReady(currentUser: user),
      );
    } catch (error) {
      syncError = error;
    } finally {
      _setSyncState(
        syncing: showOverlay,
        message: showOverlay ? 'Refreshing enrollment status...' : '',
      );
      await _refreshRemoteEnrollmentState();
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
      _setPersistentMessage(l10n.sessionSyncFailed(reportedError));
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
      _setPersistentMessage(
        l10n.sessionSyncFailed('Sync log write failed: $logError'),
      );
    }
  }

  Future<void> _takeServerCopy() async {
    if (!mounted || _syncInProgress) {
      return;
    }
    final auth = context.read<AuthController>();
    final user = auth.currentUser;
    if (user == null || user.role != 'student') {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Take server copy'),
        content: const Text(
          'This will replace this device\'s local session/progress data '
          'with a forced server download. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Take server copy'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final services = context.read<AppServices>();
    _syncInProgress = true;
    _setSyncState(
      syncing: true,
      message: 'Taking server copy: syncing enrollments...',
    );
    try {
      await services.enrollmentSyncService.forcePullFromServer(
        currentUser: user,
      );
      _setSyncState(
        syncing: true,
        message: 'Taking server copy: downloading sessions/progress...',
      );
      await services.sessionSyncService.forcePullFromServer(
        currentUser: user,
        wipeLocalStudentData: true,
      );
      await _refreshRemoteEnrollmentState();
      _setPersistentMessage(
        'Server copy completed. Local session/progress now matches server data.',
        isError: false,
      );
    } catch (error) {
      _setPersistentMessage('Take server copy failed: $error');
    } finally {
      _setSyncState(syncing: false, message: '');
      _syncInProgress = false;
    }
  }

  Future<void> _requestQuitCourse(CourseVersion course) async {
    if (_submittingQuitCourseIds.contains(course.id)) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final auth = context.read<AuthController>();
    final user = auth.currentUser;
    if (user == null) {
      _setPersistentMessage(l10n.notLoggedInMessage);
      return;
    }

    final db = context.read<AppDatabase>();
    final remoteCourseId = _remoteCourseIdByLocalCourseId[course.id] ??
        await db.getRemoteCourseId(course.id);
    if (remoteCourseId == null || remoteCourseId <= 0) {
      _setPersistentMessage(
        'Cannot request quit: this course is not linked to the server.',
      );
      return;
    }
    if (_pendingQuitRemoteCourseIds.contains(remoteCourseId)) {
      _setPersistentMessage(
        'Quit request already pending for "${course.subject}".',
        isError: false,
      );
      return;
    }

    var enrollment = _enrollmentsByRemoteCourseId[remoteCourseId];
    if (enrollment == null) {
      await _refreshRemoteEnrollmentState();
      enrollment = _enrollmentsByRemoteCourseId[remoteCourseId];
    }
    if (enrollment == null || enrollment.enrollmentId <= 0) {
      _setPersistentMessage(
        'Cannot request quit: no active server enrollment found for "${course.subject}".',
      );
      return;
    }

    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Request quit: ${course.subject}'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _submittingQuitCourseIds.add(course.id);
    });
    try {
      await _marketplaceApi.createQuitRequest(
        enrollmentId: enrollment.enrollmentId,
        reason: reasonController.text,
      );
      if (!mounted) {
        return;
      }
      _setPersistentMessage(
        'Quit request sent for "${course.subject}". Waiting for teacher approval.',
        isError: false,
      );
      await _refreshRemoteEnrollmentState();
    } catch (error) {
      _setPersistentMessage('Quit request failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _submittingQuitCourseIds.remove(course.id);
        });
      }
    }
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
    final color = _persistentMessageIsError
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.secondaryContainer;
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.info_outline),
            ),
            const SizedBox(width: 8),
            Expanded(child: SelectableText(message)),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthController>();
    final student = auth.currentUser!;
    final db = context.read<AppDatabase>();

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(l10n.studentTitle(student.username)),
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
          body: Column(
            children: [
              if (_persistentMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _buildPersistentMessageCard(l10n),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _syncInProgress ? null : _takeServerCopy,
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Take Server Copy'),
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<CourseVersion>>(
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
                        final remoteCourseId =
                            _remoteCourseIdByLocalCourseId[course.id];
                        final hasPendingQuit = remoteCourseId != null &&
                            _pendingQuitRemoteCourseIds
                                .contains(remoteCourseId);
                        final hasServerEnrollment = remoteCourseId != null &&
                            _enrollmentsByRemoteCourseId
                                .containsKey(remoteCourseId);
                        final isLoaded = course.sourcePath != null &&
                            course.sourcePath!.trim().isNotEmpty;
                        return _CourseProgressTile(
                          course: course,
                          studentId: student.id,
                          enabled: isLoaded,
                          quitPending: hasPendingQuit,
                          quitBusy:
                              _submittingQuitCourseIds.contains(course.id),
                          onRequestQuit: hasServerEnrollment
                              ? () => _requestQuitCourse(course)
                              : null,
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
              ),
            ],
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
}

class _CourseProgressTile extends StatefulWidget {
  const _CourseProgressTile({
    required this.course,
    required this.studentId,
    required this.enabled,
    required this.quitPending,
    required this.quitBusy,
    required this.onRequestQuit,
    required this.onTap,
  });

  final CourseVersion course;
  final int studentId;
  final bool enabled;
  final bool quitPending;
  final bool quitBusy;
  final VoidCallback? onRequestQuit;
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

  String _displayCourseName(String value) {
    return value.trim().replaceFirst(RegExp(r'_(\d{10,})$'), '');
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
      stream: db.watchProgressForCourse(widget.studentId, widget.course.id),
      builder: (context, snapshot) {
        final progress = snapshot.data ?? [];
        final progressPercent = _calculateProgressPercent(progress, _leafIds);
        return ListTile(
          key: Key('course_item_${widget.course.id}'),
          title: Text(_displayCourseName(widget.course.subject)),
          subtitle: Text(
            l10n.courseProgressStatus(progressPercent, _totalLeaves),
          ),
          trailing: TextButton(
            onPressed: widget.quitBusy || widget.quitPending
                ? null
                : widget.onRequestQuit,
            child: Text(
              widget.quitBusy
                  ? 'Sending...'
                  : widget.quitPending
                      ? 'Quit Pending'
                      : 'Request Quit',
            ),
          ),
          enabled: widget.enabled,
          onTap: widget.onTap,
        );
      },
    );
  }

  int _calculateProgressPercent(
    List<ProgressEntry> progress,
    Set<String> leafIds,
  ) {
    if (leafIds.isEmpty) {
      return 0;
    }
    var sum = 0;
    for (final entry in progress) {
      if (!leafIds.contains(entry.kpKey)) {
        continue;
      }
      final percent = entry.litPercent;
      final clamped = percent.clamp(0, 100);
      sum += clamped;
    }
    final ratio = sum / (leafIds.length * 100);
    return (ratio * 100).round();
  }
}
