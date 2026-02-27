import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../../services/course_bundle_service.dart';
import '../../services/marketplace_api_service.dart';

class TeacherMarketplaceCoursesPage extends StatefulWidget {
  const TeacherMarketplaceCoursesPage({super.key});

  @override
  State<TeacherMarketplaceCoursesPage> createState() =>
      _TeacherMarketplaceCoursesPageState();
}

class _TeacherMarketplaceCoursesPageState
    extends State<TeacherMarketplaceCoursesPage> {
  late final MarketplaceApiService _api;
  bool _loading = true;
  bool _deletingAll = false;
  String? _error;
  String? _stickyMessage;
  bool _stickyMessageIsError = false;
  List<TeacherCourseSummary> _courses = [];
  final Set<int> _uploadingCourseIds = {};

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
      final courses = await _api.listTeacherCourses();
      if (!mounted) {
        return;
      }
      setState(() {
        _courses = courses;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.teacherMarketplaceTitle),
        actions: [
          IconButton(
            icon: _deletingAll
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Delete all uploaded server courses',
            onPressed: _loading || _deletingAll || _courses.isEmpty
                ? null
                : () => _deleteAllServerCourses(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createCourse(context),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(context, l10n)
              : Column(
                  children: [
                    if (_stickyMessage != null)
                      _buildStickyMessage(context, l10n),
                    Expanded(
                      child: _courses.isEmpty
                          ? Center(child: Text(l10n.teacherMarketplaceEmpty))
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.marketplaceLoadFailed(_error ?? '')),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _load,
            child: Text(l10n.retryButton),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyMessage(BuildContext context, AppLocalizations l10n) {
    final message = _stickyMessage!;
    final color = _stickyMessageIsError
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.secondaryContainer;
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
                child: Icon(Icons.info_outline),
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
                  _setStickyMessage(l10n.copySuccess, isError: false);
                },
              ),
              IconButton(
                tooltip: l10n.clearButton,
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _stickyMessage = null;
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
    TeacherCourseSummary course,
  ) {
    final isUploading = _uploadingCourseIds.contains(course.courseId);
    final bundleStatus = course.latestBundleVersionId == null
        ? l10n.marketplaceBundleMissing
        : l10n.marketplaceBundleUploaded;
    return Card(
      child: ListTile(
        title: Text(course.subject),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (course.grade.isNotEmpty)
              Text(l10n.marketplaceGradeLine(course.grade)),
            if (course.description.isNotEmpty) Text(course.description),
            Text(l10n.marketplaceVisibilityLine(course.visibility)),
            Text(bundleStatus),
          ],
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<String>(
              value:
                  course.visibility.isNotEmpty ? course.visibility : 'private',
              items: [
                DropdownMenuItem(
                  value: 'public',
                  child: Text(l10n.marketplaceVisibilityPublic),
                ),
                DropdownMenuItem(
                  value: 'unlisted',
                  child: Text(l10n.marketplaceVisibilityUnlisted),
                ),
                DropdownMenuItem(
                  value: 'private',
                  child: Text(l10n.marketplaceVisibilityPrivate),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                _updateVisibility(context, course, value);
              },
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 140,
              child: ElevatedButton(
                onPressed:
                    isUploading ? null : () => _uploadBundle(context, course),
                child: Text(
                  isUploading
                      ? l10n.marketplaceUploadingLabel
                      : l10n.marketplaceUploadButton,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createCourse(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final subjectController = TextEditingController();
    final gradeController = TextEditingController();
    final descriptionController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.teacherMarketplaceCreateTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: subjectController,
              decoration: InputDecoration(labelText: l10n.subjectLabel),
            ),
            TextField(
              controller: gradeController,
              decoration: InputDecoration(labelText: l10n.gradeLabel),
            ),
            TextField(
              controller: descriptionController,
              decoration: InputDecoration(labelText: l10n.descriptionLabel),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.createButton),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final subject = subjectController.text.trim();
    if (subject.isEmpty) {
      _setStickyMessage(l10n.subjectRequired, isError: true);
      return;
    }
    try {
      final created = await _api.createTeacherCourse(
        subject: subject,
        grade: gradeController.text,
        description: descriptionController.text,
      );
      if (!mounted) {
        return;
      }
      if (created.status == 'existing') {
        _setStickyMessage(
          'Course already exists for this teacher. Reusing existing course.',
          isError: false,
        );
      } else {
        _setStickyMessage(l10n.teacherMarketplaceCreated, isError: false);
      }
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _setStickyMessage(l10n.marketplaceRequestFailed('$error'));
    }
  }

  Future<void> _updateVisibility(
    BuildContext context,
    TeacherCourseSummary course,
    String visibility,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await _api.updateCourseVisibility(
        courseId: course.courseId,
        visibility: visibility,
      );
      if (!mounted) {
        return;
      }
      _setStickyMessage(l10n.marketplaceVisibilityUpdated, isError: false);
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _setStickyMessage(l10n.marketplaceRequestFailed('$error'));
    }
  }

  Future<void> _uploadBundle(
    BuildContext context,
    TeacherCourseSummary course,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final folderPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: l10n.courseFolderPickerTitle,
    );
    if (folderPath == null || folderPath.trim().isEmpty) {
      return;
    }

    final services = context.read<AppServices>();
    final preview = await services.courseService.previewCourseLoad(
      folderPath: folderPath,
    );
    if (!preview.success) {
      if (!mounted) {
        return;
      }
      _setStickyMessage(preview.message);
      return;
    }

    setState(() {
      _uploadingCourseIds.add(course.courseId);
    });

    final bundleService = CourseBundleService();
    File? bundleFile;
    try {
      bundleFile = await bundleService.createBundleFromFolder(folderPath);
      final localSemanticHash =
          await bundleService.computeBundleSemanticHash(bundleFile);
      final versions = await _api.listTeacherBundleVersions(course.courseId);
      final latestVersion = versions.isNotEmpty ? versions.first : null;
      if (latestVersion != null &&
          latestVersion.hash.isNotEmpty &&
          latestVersion.hash == localSemanticHash) {
        _setStickyMessage(
          'No file changes detected compared with latest version hash. No upload needed.',
          isError: false,
        );
        return;
      }
      if (latestVersion != null) {
        final diff = await _buildKpDiffAgainstLatestBundle(
          bundleService: bundleService,
          folderPath: folderPath,
          latestBundleVersionId: latestVersion.bundleVersionId,
          courseSubject: course.subject,
        );
        final confirmed = await _confirmUploadWithKpDiff(
          courseSubject: course.subject,
          diff: diff,
        );
        if (!confirmed) {
          _setStickyMessage('Upload cancelled by teacher.', isError: false);
          return;
        }
      }
      final ensured = await _api.ensureBundle(
        course.courseId,
        courseName: course.subject,
      );
      final bundleId = ensured.bundleId;
      final uploaded = await _api.uploadBundle(
        bundleId: bundleId,
        courseName: course.subject,
        bundleFile: bundleFile,
      );
      if (!mounted) {
        return;
      }
      final status = (uploaded['status'] as String?) ?? 'uploaded';
      if (status == 'unchanged') {
        _setStickyMessage(
          'No file changes detected. No upload needed.',
          isError: false,
        );
      } else {
        _setStickyMessage(l10n.marketplaceUploadSuccess, isError: false);
      }
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _setStickyMessage(l10n.marketplaceUploadFailed('$error'));
    } finally {
      if (bundleFile != null && bundleFile.existsSync()) {
        await bundleFile.delete();
      }
      if (mounted) {
        setState(() {
          _uploadingCourseIds.remove(course.courseId);
        });
      }
    }
  }

  Future<CourseKpDiffSummary> _buildKpDiffAgainstLatestBundle({
    required CourseBundleService bundleService,
    required String folderPath,
    required int latestBundleVersionId,
    required String courseSubject,
  }) async {
    final targetPath = await bundleService.createTempBundlePath(
      label: 'latest_$courseSubject',
    );
    final targetFile = File(targetPath);
    try {
      final latestBundle = await _api.downloadBundleToFile(
        bundleVersionId: latestBundleVersionId,
        targetPath: targetPath,
      );
      final diff = await bundleService.compareCourseFolderWithBundle(
        folderPath: folderPath,
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

  Future<void> _deleteAllServerCourses(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmController = TextEditingController();
    final confirmPhrase = 'DELETE ALL SERVER COURSES';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Delete all server courses'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This deletes every uploaded marketplace course for this teacher account on the server.',
              ),
              const SizedBox(height: 8),
              SelectableText(confirmPhrase),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                decoration: const InputDecoration(
                  labelText: 'Type confirmation text',
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancelButton),
            ),
            ElevatedButton(
              onPressed: confirmController.text.trim() == confirmPhrase
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

    setState(() {
      _deletingAll = true;
    });
    final snapshot = List<TeacherCourseSummary>.from(_courses);
    var deleted = 0;
    try {
      for (final course in snapshot) {
        await _api.deleteTeacherCourse(course.courseId);
        deleted++;
      }
      if (!mounted) {
        return;
      }
      _setStickyMessage(
        'Deleted $deleted server course(s).',
        isError: false,
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _setStickyMessage(
        'Bulk delete stopped after $deleted course(s): $error',
      );
      await _load();
    } finally {
      if (mounted) {
        setState(() {
          _deletingAll = false;
        });
      }
    }
  }

  void _setStickyMessage(String message, {bool isError = true}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _stickyMessage = message;
      _stickyMessageIsError = isError;
    });
  }
}
