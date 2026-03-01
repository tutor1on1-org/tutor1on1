import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../../services/course_bundle_service.dart';
import '../../services/marketplace_api_service.dart';
import '../../services/remote_teacher_identity_service.dart';
import '../../state/auth_controller.dart';

class MarketplacePage extends StatefulWidget {
  const MarketplacePage({super.key});

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  static const int _pageSize = 10;
  static const _promptConflictPolicy =
      _PromptConflictPolicy.preserveLocalOnRedownload;
  static const List<String> _promptNames = [
    'learn_init',
    'learn_cont',
    'review_init',
    'review_cont',
    'summary',
  ];

  late final MarketplaceApiService _api;
  bool _studentActionsEnabled = false;
  bool _loading = true;
  String? _error;
  String? _persistentMessage;
  bool _persistentMessageIsError = false;
  List<CatalogCourse> _courses = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _gradeFilter = '';
  int _currentPage = 1;
  final Map<int, EnrollmentRequestSummary> _requestsByCourse = {};
  final Map<int, EnrollmentSummary> _enrollmentsByCourse = {};
  final Set<int> _enrolledCourseIds = {};
  final Set<int> _downloadingCourseIds = {};
  final RemoteTeacherIdentityService _remoteTeacherIdentity =
      const RemoteTeacherIdentityService();

  @override
  void initState() {
    super.initState();
    final services = context.read<AppServices>();
    _api = MarketplaceApiService(secureStorage: services.secureStorage);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
        _currentPage = 1;
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

  List<String> _gradeFilterOptions(List<CatalogCourse> courses) {
    final grades = <String>{};
    for (final course in courses) {
      final grade = course.grade.trim();
      if (grade.isNotEmpty) {
        grades.add(grade);
      }
    }
    final sorted = grades.toList()..sort();
    return sorted;
  }

  List<CatalogCourse> _applySearchAndFilters(List<CatalogCourse> courses) {
    final query = _searchQuery.trim().toLowerCase();
    final gradeFilter = _gradeFilter.trim().toLowerCase();
    final filtered = <CatalogCourse>[];
    for (final course in courses) {
      final grade = course.grade.trim().toLowerCase();
      if (gradeFilter.isNotEmpty && grade != gradeFilter) {
        continue;
      }
      if (query.isNotEmpty) {
        final haystack =
            '${course.subject}\n${course.teacherName}\n${course.description}\n${course.grade}'
                .toLowerCase();
        if (!haystack.contains(query)) {
          continue;
        }
      }
      filtered.add(course);
    }
    filtered.sort((a, b) {
      final subject =
          a.subject.toLowerCase().compareTo(b.subject.toLowerCase());
      if (subject != 0) {
        return subject;
      }
      return a.teacherName.toLowerCase().compareTo(b.teacherName.toLowerCase());
    });
    return filtered;
  }

  void _updateSearchQuery(String value) {
    if (_searchQuery == value) {
      return;
    }
    setState(() {
      _searchQuery = value;
      _currentPage = 1;
    });
  }

  void _updateGradeFilter(String value) {
    if (_gradeFilter == value) {
      return;
    }
    setState(() {
      _gradeFilter = value;
      _currentPage = 1;
    });
  }

  void _clearSearchAndFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _gradeFilter = '';
      _currentPage = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final filteredCourses = _applySearchAndFilters(_courses);
    final totalPages = filteredCourses.isEmpty
        ? 1
        : ((filteredCourses.length - 1) ~/ _pageSize) + 1;
    final currentPage = _currentPage.clamp(1, totalPages);
    final start = (currentPage - 1) * _pageSize;
    final end = (start + _pageSize).clamp(0, filteredCourses.length);
    final pageCourses = start >= filteredCourses.length
        ? <CatalogCourse>[]
        : filteredCourses.sublist(start, end);
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
          _buildSearchAndFilterControls(
            l10n: l10n,
            courses: _courses,
            filteredCount: filteredCourses.length,
          ),
          if (_persistentMessage != null)
            _buildPersistentMessage(context, l10n),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError(context, l10n)
                    : filteredCourses.isEmpty
                        ? Center(
                            child: Text(
                              _courses.isEmpty
                                  ? l10n.marketplaceNoCourses
                                  : 'No courses match the current filters.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: pageCourses.length,
                            itemBuilder: (context, index) {
                              final course = pageCourses[index];
                              return _buildCourseTile(context, l10n, course);
                            },
                          ),
          ),
          if (!_loading && _error == null && filteredCourses.isNotEmpty)
            _buildPaginationBar(
              currentPage: currentPage,
              totalPages: totalPages,
              totalItems: filteredCourses.length,
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

  Widget _buildPersistentMessage(BuildContext context, AppLocalizations l10n) {
    final message = _persistentMessage!;
    final color = _persistentMessageIsError
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.primaryContainer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        color: color,
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
                    _persistentMessage = null;
                    _persistentMessageIsError = false;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilterControls({
    required AppLocalizations l10n,
    required List<CatalogCourse> courses,
    required int filteredCount,
  }) {
    final gradeOptions = _gradeFilterOptions(courses);
    final selectedGrade = gradeOptions.any(
            (grade) => grade.toLowerCase() == _gradeFilter.trim().toLowerCase())
        ? _gradeFilter
        : '';
    final hasFilters =
        _searchQuery.trim().isNotEmpty || _gradeFilter.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _updateSearchQuery,
                  decoration: const InputDecoration(
                    labelText: 'Search marketplace',
                    hintText: 'Subject / teacher / description',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 180,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: l10n.gradeLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selectedGrade.isEmpty ? '' : selectedGrade,
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('All grades'),
                        ),
                        ...gradeOptions.map(
                          (grade) => DropdownMenuItem<String>(
                            value: grade.toLowerCase(),
                            child: Text(grade),
                          ),
                        ),
                      ],
                      onChanged: (value) => _updateGradeFilter(value ?? ''),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: hasFilters ? _clearSearchAndFilters : null,
                child: Text(l10n.clearButton),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '$filteredCount result(s)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationBar({
    required int currentPage,
    required int totalPages,
    required int totalItems,
  }) {
    final pageStart = ((currentPage - 1) * _pageSize) + 1;
    final pageEnd = (pageStart + _pageSize - 1).clamp(1, totalItems);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: [
          Text(
            'Showing $pageStart-$pageEnd of $totalItems',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Previous page',
            onPressed: currentPage > 1
                ? () {
                    setState(() {
                      _currentPage = currentPage - 1;
                    });
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('Page $currentPage / $totalPages'),
          IconButton(
            tooltip: 'Next page',
            onPressed: currentPage < totalPages
                ? () {
                    setState(() {
                      _currentPage = currentPage + 1;
                    });
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
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
      _setPersistentMessage(
        'Quit request sent. Waiting for teacher approval.',
      );
      await _load();
    } catch (error) {
      _setPersistentMessage('Quit request failed: $error', isError: true);
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
      _setPersistentMessage(l10n.marketplaceRequestSent);
      await _load();
    } catch (error) {
      _setPersistentMessage(
        l10n.marketplaceRequestFailed('$error'),
        isError: true,
      );
    }
  }

  Future<void> _downloadBundle(
    BuildContext context,
    CatalogCourse course,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final bundleVersionId = course.latestBundleVersionId;
    if (bundleVersionId == null || bundleVersionId <= 0) {
      _setPersistentMessage(l10n.marketplaceBundleMissing, isError: true);
      return;
    }
    final auth = context.read<AuthController>();
    final user = auth.currentUser;
    if (user == null) {
      _setPersistentMessage(l10n.notLoggedInMessage, isError: true);
      return;
    }

    setState(() {
      _downloadingCourseIds.add(course.courseId);
    });
    final services = context.read<AppServices>();
    final bundleService = CourseBundleService();
    final enrollment = _enrollmentsByCourse[course.courseId];
    if (enrollment == null) {
      _setPersistentMessage(
        'Cannot download course: enrollment metadata not found. Refresh marketplace and try again.',
        isError: true,
      );
      return;
    }
    if (enrollment.teacherId <= 0) {
      _setPersistentMessage(
        'Cannot download course: enrollment is missing teacher identity.',
        isError: true,
      );
      return;
    }
    File? bundleFile;
    try {
      final localTeacherId =
          await _remoteTeacherIdentity.resolveOrCreateLocalTeacherId(
        db: services.db,
        remoteTeacherId: enrollment.teacherId,
      );
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
        teacherId: localTeacherId,
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
        _setPersistentMessage(
          l10n.marketplaceDownloadFailed(details),
          isError: true,
        );
        return;
      }
      await services.db.updateCourseVersionTeacherId(
        id: loadResult.course!.id,
        teacherId: localTeacherId,
      );
      await services.db.upsertCourseRemoteLink(
        courseVersionId: loadResult.course!.id,
        remoteCourseId: course.courseId,
      );
      await services.db.assignStudent(
        studentId: user.id,
        courseVersionId: loadResult.course!.id,
      );
      var successMessage = l10n.marketplaceDownloadSuccess;
      if (promptMetadata != null) {
        final metadataApplyResult = await _applyPromptMetadata(
          services: services,
          metadata: promptMetadata,
          course: loadResult.course!,
          user: user,
          remoteCourseId: course.courseId,
          bundleVersionId: bundleVersionId,
        );
        if (metadataApplyResult.skippedDueToLocalConflict) {
          successMessage =
              'Course downloaded. Local prompt/profile changes were preserved; remote prompt metadata was not applied.';
        }
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
      _setPersistentMessage(successMessage);
    } catch (error) {
      _setPersistentMessage(
        l10n.marketplaceDownloadFailed('$error'),
        isError: true,
      );
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

  void _setPersistentMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      _persistentMessage = message;
      _persistentMessageIsError = isError;
    });
  }

  Future<_PromptMetadataApplyResult> _applyPromptMetadata({
    required AppServices services,
    required Map<String, dynamic> metadata,
    required CourseVersion course,
    required User user,
    required int remoteCourseId,
    required int bundleVersionId,
  }) async {
    final schema = (metadata['schema'] as String?)?.trim() ?? '';
    if (schema != 'family_teacher_prompt_bundle_v1') {
      return const _PromptMetadataApplyResult.noop();
    }
    final remoteUserId = user.remoteUserId;
    int? existingVersion;
    if (remoteUserId != null && remoteUserId > 0 && remoteCourseId > 0) {
      existingVersion =
          await services.secureStorage.readInstalledCourseBundleVersion(
        remoteUserId: remoteUserId,
        remoteCourseId: remoteCourseId,
      );
      if (existingVersion != null && bundleVersionId <= existingVersion) {
        return const _PromptMetadataApplyResult.noop();
      }
    }

    final db = services.db;
    final teacherId = course.teacherId;
    final courseKey = course.sourcePath?.trim();
    if (courseKey == null || courseKey.isEmpty) {
      return const _PromptMetadataApplyResult.noop();
    }
    if (remoteUserId != null &&
        remoteUserId > 0 &&
        remoteCourseId > 0 &&
        existingVersion != null &&
        existingVersion > 0 &&
        _promptConflictPolicy ==
            _PromptConflictPolicy.preserveLocalOnRedownload) {
      final appliedAt =
          await services.secureStorage.readPromptMetadataAppliedAt(
        remoteUserId: remoteUserId,
        remoteCourseId: remoteCourseId,
      );
      final hasLocalEdits = await _hasManagedPromptLocalEditsSinceLastApply(
        db: db,
        teacherId: teacherId,
        courseKey: courseKey,
        studentId: user.id,
        appliedAt: appliedAt,
      );
      if (hasLocalEdits) {
        await services.secureStorage.writeInstalledCourseBundleVersion(
          remoteUserId: remoteUserId,
          remoteCourseId: remoteCourseId,
          versionId: bundleVersionId,
        );
        return const _PromptMetadataApplyResult.skippedDueToLocalConflict();
      }
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
      await services.secureStorage.writePromptMetadataAppliedAt(
        remoteUserId: remoteUserId,
        remoteCourseId: remoteCourseId,
        appliedAt: DateTime.now(),
      );
    }

    services.promptRepository.invalidatePromptCache();
    return const _PromptMetadataApplyResult.applied();
  }

  Future<bool> _hasManagedPromptLocalEditsSinceLastApply({
    required AppDatabase db,
    required int teacherId,
    required String courseKey,
    required int studentId,
    required DateTime? appliedAt,
  }) async {
    if (appliedAt == null) {
      return false;
    }
    final templates = await (db.select(db.promptTemplates)
          ..where((tbl) => tbl.teacherId.equals(teacherId)))
        .get();
    for (final template in templates) {
      if (!_isManagedPromptTemplateScope(
        template: template,
        courseKey: courseKey,
        studentId: studentId,
      )) {
        continue;
      }
      if (template.createdAt.isAfter(appliedAt)) {
        return true;
      }
    }
    final profiles = await (db.select(db.studentPromptProfiles)
          ..where((tbl) => tbl.teacherId.equals(teacherId)))
        .get();
    for (final profile in profiles) {
      if (!_isManagedProfileScope(
        profile: profile,
        courseKey: courseKey,
        studentId: studentId,
      )) {
        continue;
      }
      final changedAt = profile.updatedAt ?? profile.createdAt;
      if (changedAt.isAfter(appliedAt)) {
        return true;
      }
    }
    return false;
  }

  bool _isManagedPromptTemplateScope({
    required PromptTemplate template,
    required String courseKey,
    required int studentId,
  }) {
    final normalizedKey = (template.courseKey ?? '').trim();
    if (template.courseKey == null && template.studentId == null) {
      return true;
    }
    if (normalizedKey == courseKey && template.studentId == null) {
      return true;
    }
    if (normalizedKey == courseKey && template.studentId == studentId) {
      return true;
    }
    return false;
  }

  bool _isManagedProfileScope({
    required StudentPromptProfile profile,
    required String courseKey,
    required int studentId,
  }) {
    final normalizedKey = (profile.courseKey ?? '').trim();
    if (profile.courseKey == null && profile.studentId == null) {
      return true;
    }
    if (normalizedKey == courseKey && profile.studentId == null) {
      return true;
    }
    if (normalizedKey == courseKey && profile.studentId == studentId) {
      return true;
    }
    return false;
  }
}

enum _PromptConflictPolicy {
  preserveLocalOnRedownload,
}

class _PromptMetadataApplyResult {
  const _PromptMetadataApplyResult._({
    required this.applied,
    required this.skippedDueToLocalConflict,
  });

  const _PromptMetadataApplyResult.noop()
      : this._(
          applied: false,
          skippedDueToLocalConflict: false,
        );

  const _PromptMetadataApplyResult.applied()
      : this._(
          applied: true,
          skippedDueToLocalConflict: false,
        );

  const _PromptMetadataApplyResult.skippedDueToLocalConflict()
      : this._(
          applied: false,
          skippedDueToLocalConflict: true,
        );

  final bool applied;
  final bool skippedDueToLocalConflict;
}
