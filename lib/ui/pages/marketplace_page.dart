import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../../services/course_bundle_service.dart';
import '../../services/marketplace_api_service.dart';
import '../../state/auth_controller.dart';

class MarketplacePage extends StatefulWidget {
  const MarketplacePage({super.key});

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  static const List<String> _promptNames = [
    'learn_init',
    'learn_cont',
    'review_init',
    'review_cont',
    'summary',
    'learn',
    'review',
    'summarize',
  ];

  late final MarketplaceApiService _api;
  bool _studentActionsEnabled = false;
  bool _loading = true;
  String? _error;
  String? _stickyError;
  List<CatalogCourse> _courses = [];
  final Map<int, EnrollmentRequestSummary> _requestsByCourse = {};
  final Map<int, EnrollmentSummary> _enrollmentsByCourse = {};
  final Set<int> _enrolledCourseIds = {};
  final Set<int> _downloadingCourseIds = {};

  @override
  void initState() {
    super.initState();
    final services = context.read<AppServices>();
    _api = MarketplaceApiService(secureStorage: services.secureStorage);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final role = context.read<AuthController>().currentUser?.role;
      final isStudent = role == 'student';
      final allCourses = await _api.listCourses();
      final requestMap = <int, EnrollmentRequestSummary>{};
      final enrolledIds = <int>{};
      final enrollmentMap = <int, EnrollmentSummary>{};
      List<CatalogCourse> courses = allCourses;
      if (isStudent) {
        final enrollments = await _api.listEnrollments();
        final requests = await _api.listStudentRequests();
        final enrollmentCourseIds = <int>{
          for (final enrollment in enrollments) enrollment.courseId,
        };
        courses = _dedupeCoursesByTeacherAndName(
          allCourses,
          preferredCourseIds: enrollmentCourseIds,
        );
        final canonicalCourseIdByKey = <String, int>{
          for (final course in courses) _courseUniqKey(course): course.courseId,
        };
        final allCoursesById = <int, CatalogCourse>{
          for (final course in allCourses) course.courseId: course,
        };
        for (final request in requests) {
          final source = allCoursesById[request.courseId];
          final key = source == null ? null : _courseUniqKey(source);
          final canonicalCourseId = key == null
              ? request.courseId
              : (canonicalCourseIdByKey[key] ?? request.courseId);
          requestMap[canonicalCourseId] = request;
        }
        for (final enrollment in enrollments) {
          final source = allCoursesById[enrollment.courseId];
          final key = source == null ? null : _courseUniqKey(source);
          final canonicalCourseId = key == null
              ? enrollment.courseId
              : (canonicalCourseIdByKey[key] ?? enrollment.courseId);
          enrolledIds.add(canonicalCourseId);
          enrollmentMap[canonicalCourseId] = enrollment;
        }
      } else {
        courses = _dedupeCoursesByTeacherAndName(allCourses);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _courses = courses;
        _studentActionsEnabled = isStudent;
        _requestsByCourse
          ..clear()
          ..addAll(requestMap);
        _enrollmentsByCourse
          ..clear()
          ..addAll(enrollmentMap);
        _enrolledCourseIds
          ..clear()
          ..addAll(enrolledIds);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  List<CatalogCourse> _dedupeCoursesByTeacherAndName(
    List<CatalogCourse> courses, {
    Set<int> preferredCourseIds = const <int>{},
  }) {
    final dedupedByKey = <String, CatalogCourse>{};
    for (final course in courses) {
      final key = _courseUniqKey(course);
      final existing = dedupedByKey[key];
      if (existing == null) {
        dedupedByKey[key] = course;
        continue;
      }
      final isPreferred = preferredCourseIds.contains(course.courseId);
      final existingPreferred = preferredCourseIds.contains(existing.courseId);
      if (isPreferred && !existingPreferred) {
        dedupedByKey[key] = course;
      }
    }
    return dedupedByKey.values.toList(growable: false);
  }

  String _courseUniqKey(CatalogCourse course) {
    return '${course.teacherId}:${_normalizeCourseName(course.subject)}';
  }

  String _normalizeCourseName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.marketplaceTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_stickyError != null) _buildStickyError(context, l10n),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError(context, l10n)
                    : _courses.isEmpty
                        ? Center(child: Text(l10n.marketplaceNoCourses))
                        : ListView.builder(
                            itemCount: _courses.length,
                            itemBuilder: (context, index) {
                              final course = _courses[index];
                              return _buildCourseTile(context, l10n, course);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, AppLocalizations l10n) {
    final errorText = l10n.marketplaceLoadFailed(_error ?? '');
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(errorText),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: errorText));
              if (!mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.copySuccess)),
              );
            },
            icon: const Icon(Icons.copy),
            label: Text(l10n.copyTooltip),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _load,
            child: Text(l10n.retryButton),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyError(BuildContext context, AppLocalizations l10n) {
    final message = _stickyError!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
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
              Expanded(child: SelectableText(message)),
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
                    _stickyError = null;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCourseTile(
    BuildContext context,
    AppLocalizations l10n,
    CatalogCourse course,
  ) {
    if (!_studentActionsEnabled) {
      return Card(
        child: ListTile(
          title: Text(course.subject),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.marketplaceTeacherLine(course.teacherName)),
              if (course.grade.isNotEmpty)
                Text(l10n.marketplaceGradeLine(course.grade)),
              if (course.description.isNotEmpty) Text(course.description),
            ],
          ),
          isThreeLine: true,
        ),
      );
    }
    final request = _requestsByCourse[course.courseId];
    final enrolled = _enrolledCourseIds.contains(course.courseId);
    final enrollment = _enrollmentsByCourse[course.courseId];
    final isDownloading = _downloadingCourseIds.contains(course.courseId);
    String statusLabel = '';
    String buttonLabel = l10n.marketplaceRequestButton;
    bool canRequest = !enrolled;
    bool canDownload = false;
    if (enrolled) {
      statusLabel = l10n.marketplaceEnrolled;
      canRequest = false;
      canDownload = course.latestBundleVersionId != null;
    } else if (request != null) {
      if (request.status == 'pending') {
        statusLabel = l10n.marketplacePending;
        canRequest = false;
        buttonLabel = l10n.marketplacePending;
      } else if (request.status == 'rejected') {
        statusLabel = l10n.marketplaceRejected;
        canRequest = true;
        buttonLabel = l10n.marketplaceRequestButton;
      } else if (request.status == 'approved') {
        statusLabel = l10n.marketplaceApproved;
        canRequest = true;
        buttonLabel = l10n.marketplaceRequestButton;
      }
    }
    return Card(
      child: ListTile(
        title: Text(course.subject),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.marketplaceTeacherLine(course.teacherName)),
            if (course.grade.isNotEmpty)
              Text(l10n.marketplaceGradeLine(course.grade)),
            if (course.description.isNotEmpty) Text(course.description),
            if (statusLabel.isNotEmpty) Text(statusLabel),
            if (enrolled && !canDownload) Text(l10n.marketplaceBundleMissing),
          ],
        ),
        isThreeLine: true,
        trailing: enrolled
            ? SizedBox(
                width: 164,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: canDownload && !isDownloading
                          ? () => _downloadBundle(context, course)
                          : null,
                      child: Text(
                        isDownloading
                            ? l10n.marketplaceDownloadingLabel
                            : canDownload
                                ? l10n.marketplaceDownloadButton
                                : l10n.marketplaceNoBundleButton,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    TextButton(
                      onPressed: (enrollment != null && !isDownloading)
                          ? () => _requestQuitCourse(context, enrollment)
                          : null,
                      child: const Text('Request quit'),
                    ),
                  ],
                ),
              )
            : ElevatedButton(
                onPressed: canRequest
                    ? () => _requestEnrollment(context, course)
                    : null,
                child: Text(buttonLabel),
              ),
      ),
    );
  }

  Future<void> _requestQuitCourse(
    BuildContext context,
    EnrollmentSummary enrollment,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Request quit: ${enrollment.courseSubject}'),
        content: TextField(
          controller: controller,
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
    try {
      await _api.createQuitRequest(
        enrollmentId: enrollment.enrollmentId,
        reason: controller.text,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Quit request sent. Waiting for teacher approval.')),
      );
      await _load();
    } catch (error) {
      _setStickyError('Quit request failed: $error');
    }
  }

  Future<void> _requestEnrollment(
    BuildContext context,
    CatalogCourse course,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.marketplaceRequestTitle(course.subject)),
        content: TextField(
          controller: controller,
          decoration:
              InputDecoration(labelText: l10n.marketplaceRequestMessage),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.marketplaceRequestButton),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await _api.createEnrollmentRequest(
        courseId: course.courseId,
        message: controller.text,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.marketplaceRequestSent)),
      );
      await _load();
    } catch (error) {
      _setStickyError(l10n.marketplaceRequestFailed('$error'));
    }
  }

  Future<void> _downloadBundle(
    BuildContext context,
    CatalogCourse course,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final bundleVersionId = course.latestBundleVersionId;
    if (bundleVersionId == null || bundleVersionId <= 0) {
      _setStickyError(l10n.marketplaceBundleMissing);
      return;
    }
    final auth = context.read<AuthController>();
    final user = auth.currentUser;
    if (user == null) {
      _setStickyError(l10n.notLoggedInMessage);
      return;
    }

    setState(() {
      _downloadingCourseIds.add(course.courseId);
    });
    final services = context.read<AppServices>();
    final bundleService = CourseBundleService();
    File? bundleFile;
    try {
      final targetPath =
          await bundleService.createTempBundlePath(label: course.subject);
      bundleFile = await _api.downloadBundleToFile(
        bundleVersionId: bundleVersionId,
        targetPath: targetPath,
      );
      await bundleService.validateBundleForImport(bundleFile);
      final promptMetadata =
          await bundleService.readPromptMetadataFromBundleFile(bundleFile);
      final folderPath = await bundleService.extractBundleFromFile(
        bundleFile: bundleFile,
        courseName: course.subject,
      );
      final existingCourseVersionId =
          await services.db.getCourseVersionIdForRemoteCourse(course.courseId);
      final loadResult = await services.courseService.loadCourseFromFolder(
        teacherId: user.id,
        folderPath: folderPath,
        courseVersionId: existingCourseVersionId,
        courseNameOverride: course.subject,
      );
      if (!loadResult.success || loadResult.course == null) {
        var details = loadResult.message;
        if (details.contains('Missing file:')) {
          details =
              '$details\nThe course bundle is incomplete. Ask the teacher to reload and upload the course again.';
        }
        _setStickyError(l10n.marketplaceDownloadFailed(details));
        return;
      }
      await services.db.upsertCourseRemoteLink(
        courseVersionId: loadResult.course!.id,
        remoteCourseId: course.courseId,
      );
      await services.db.assignStudent(
        studentId: user.id,
        courseVersionId: loadResult.course!.id,
      );
      if (promptMetadata != null) {
        await _applyPromptMetadata(
          services: services,
          metadata: promptMetadata,
          course: loadResult.course!,
          user: user,
          remoteCourseId: course.courseId,
          bundleVersionId: bundleVersionId,
        );
      }
      final remoteUserId = user.remoteUserId;
      if (remoteUserId != null && remoteUserId > 0) {
        await services.secureStorage.writeInstalledCourseBundleVersion(
          remoteUserId: remoteUserId,
          remoteCourseId: course.courseId,
          versionId: bundleVersionId,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _stickyError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.marketplaceDownloadSuccess)),
      );
    } catch (error) {
      _setStickyError(l10n.marketplaceDownloadFailed('$error'));
    } finally {
      if (bundleFile != null && bundleFile.existsSync()) {
        await bundleFile.delete();
      }
      if (mounted) {
        setState(() {
          _downloadingCourseIds.remove(course.courseId);
        });
      }
    }
  }

  void _setStickyError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _stickyError = message;
    });
  }

  Future<void> _applyPromptMetadata({
    required AppServices services,
    required Map<String, dynamic> metadata,
    required CourseVersion course,
    required User user,
    required int remoteCourseId,
    required int bundleVersionId,
  }) async {
    final schema = (metadata['schema'] as String?)?.trim() ?? '';
    if (schema != 'family_teacher_prompt_bundle_v1') {
      return;
    }
    final remoteUserId = user.remoteUserId;
    if (remoteUserId != null && remoteUserId > 0 && remoteCourseId > 0) {
      final existingVersion =
          await services.secureStorage.readInstalledCourseBundleVersion(
        remoteUserId: remoteUserId,
        remoteCourseId: remoteCourseId,
      );
      if (existingVersion != null && bundleVersionId <= existingVersion) {
        return;
      }
    }

    final db = services.db;
    final teacherId = course.teacherId;
    final courseKey = course.sourcePath?.trim();
    if (courseKey == null || courseKey.isEmpty) {
      return;
    }

    for (final promptName in _promptNames) {
      await db.clearActivePromptTemplates(
        teacherId: teacherId,
        promptName: promptName,
        courseKey: null,
        studentId: null,
      );
      await db.clearActivePromptTemplates(
        teacherId: teacherId,
        promptName: promptName,
        courseKey: courseKey,
        studentId: null,
      );
      await db.clearActivePromptTemplates(
        teacherId: teacherId,
        promptName: promptName,
        courseKey: courseKey,
        studentId: user.id,
      );
    }

    await db.deleteStudentPromptProfile(
      teacherId: teacherId,
      courseKey: null,
      studentId: null,
    );
    await db.deleteStudentPromptProfile(
      teacherId: teacherId,
      courseKey: courseKey,
      studentId: null,
    );
    await db.deleteStudentPromptProfile(
      teacherId: teacherId,
      courseKey: courseKey,
      studentId: user.id,
    );

    final promptTemplates = metadata['prompt_templates'];
    if (promptTemplates is List) {
      for (final item in promptTemplates) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final promptName = (item['prompt_name'] as String?)?.trim() ?? '';
        final content = (item['content'] as String?)?.trim() ?? '';
        final scope = (item['scope'] as String?)?.trim() ?? '';
        if (promptName.isEmpty || content.isEmpty) {
          continue;
        }
        if (!_promptNames.contains(promptName)) {
          continue;
        }

        String? scopeCourseKey;
        int? scopeStudentId;
        if (scope == 'teacher') {
          scopeCourseKey = null;
          scopeStudentId = null;
        } else if (scope == 'course') {
          scopeCourseKey = courseKey;
          scopeStudentId = null;
        } else if (scope == 'student') {
          final targetRemoteUserId =
              (item['student_remote_user_id'] as num?)?.toInt();
          final targetUsername =
              (item['student_username'] as String?)?.trim() ?? '';
          final remoteMatched = remoteUserId != null &&
              targetRemoteUserId != null &&
              targetRemoteUserId > 0 &&
              remoteUserId == targetRemoteUserId;
          final usernameMatched = targetUsername.isNotEmpty &&
              targetUsername.toLowerCase() == user.username.toLowerCase();
          if (!remoteMatched && !usernameMatched) {
            continue;
          }
          scopeCourseKey = courseKey;
          scopeStudentId = user.id;
        } else {
          continue;
        }

        await db.insertPromptTemplate(
          teacherId: teacherId,
          promptName: promptName,
          content: content,
          courseKey: scopeCourseKey,
          studentId: scopeStudentId,
        );
      }
    }

    final profiles = metadata['student_prompt_profiles'];
    if (profiles is List) {
      for (final item in profiles) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final scope = (item['scope'] as String?)?.trim() ?? '';
        String? scopeCourseKey;
        int? scopeStudentId;

        if (scope == 'teacher') {
          scopeCourseKey = null;
          scopeStudentId = null;
        } else if (scope == 'course') {
          scopeCourseKey = courseKey;
          scopeStudentId = null;
        } else if (scope == 'student') {
          final targetRemoteUserId =
              (item['student_remote_user_id'] as num?)?.toInt();
          final targetUsername =
              (item['student_username'] as String?)?.trim() ?? '';
          final remoteMatched = remoteUserId != null &&
              targetRemoteUserId != null &&
              targetRemoteUserId > 0 &&
              remoteUserId == targetRemoteUserId;
          final usernameMatched = targetUsername.isNotEmpty &&
              targetUsername.toLowerCase() == user.username.toLowerCase();
          if (!remoteMatched && !usernameMatched) {
            continue;
          }
          scopeCourseKey = courseKey;
          scopeStudentId = user.id;
        } else {
          continue;
        }

        await db.upsertStudentPromptProfile(
          teacherId: teacherId,
          courseKey: scopeCourseKey,
          studentId: scopeStudentId,
          gradeLevel: item['grade_level'] as String?,
          readingLevel: item['reading_level'] as String?,
          preferredLanguage: item['preferred_language'] as String?,
          interests: item['interests'] as String?,
          preferredTone: item['preferred_tone'] as String?,
          preferredPace: item['preferred_pace'] as String?,
          preferredFormat: item['preferred_format'] as String?,
          supportNotes: item['support_notes'] as String?,
        );
      }
    }

    if (remoteUserId != null &&
        remoteUserId > 0 &&
        remoteCourseId > 0 &&
        bundleVersionId > 0) {
      await services.secureStorage.writeInstalledCourseBundleVersion(
        remoteUserId: remoteUserId,
        remoteCourseId: remoteCourseId,
        versionId: bundleVersionId,
      );
    }

    services.promptRepository.invalidatePromptCache();
  }
}
