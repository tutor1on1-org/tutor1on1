import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:tutor1on1/l10n/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../services/app_services.dart';
import '../../services/course_import_service.dart';
import '../../services/course_service.dart';
import '../app_close_button.dart';
import '../pages/skill_tree_page.dart';

class CourseVersionPage extends StatefulWidget {
  const CourseVersionPage({
    super.key,
    required this.teacherId,
    this.courseVersionId,
  });

  final int teacherId;
  final int? courseVersionId;

  @override
  State<CourseVersionPage> createState() => _CourseVersionPageState();
}

class _CourseVersionPageState extends State<CourseVersionPage> {
  final _folderController = TextEditingController();
  bool _loading = true;
  bool _loadingCourse = false;
  CourseVersion? _course;
  String? _courseName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    if (widget.courseVersionId != null) {
      _course = await db.getCourseVersionById(widget.courseVersionId!);
      if (_course != null) {
        _folderController.text = _initialReloadFolderPath(_course!);
        _courseName = _course!.subject;
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _folderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          actions: buildAppBarActionsWithClose(context),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.createCourseTitle,
        ),
        actions: buildAppBarActionsWithClose(context),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(l10n.courseFolderLabel),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('course_folder'),
                    controller: _folderController,
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: l10n.courseFolderHint,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  key: const Key('browse_course_folder'),
                  onPressed: _loadingCourse ? null : _browseFolder,
                  child: Text(l10n.browseButton),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_courseName != null)
              Text(
                l10n.courseNameLabel(_courseName!),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton(
                  key: const Key('load_course_button'),
                  onPressed: _loadingCourse ? null : _loadCourse,
                  child: Text(
                    _loadingCourse
                        ? l10n.loadingLabel
                        : (_course == null
                            ? l10n.loadCourseButton
                            : l10n.reloadCourseButton),
                  ),
                ),
                const SizedBox(width: 12),
                if (_course != null &&
                    _course!.sourcePath != null &&
                    _course!.sourcePath!.trim().isNotEmpty)
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SkillTreePage(
                            courseVersionId: _course!.id,
                            isTeacherView: true,
                          ),
                        ),
                      );
                    },
                    child: Text(l10n.viewTreeButton),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadCourse() async {
    final l10n = AppLocalizations.of(context)!;
    final folderPath = _folderController.text.trim();

    if (folderPath.isEmpty) {
      await _showErrorDialog(
        title: l10n.courseLoadFailedTitle,
        message: l10n.courseFolderRequired,
      );
      return;
    }

    setState(() => _loadingCourse = true);
    final service = context.read<AppServices>().courseService;
    try {
      final preview = await service.previewCourseLoad(
        folderPath: folderPath,
        courseVersionId: widget.courseVersionId ?? _course?.id,
      );
      if (!preview.success) {
        await _showErrorDialog(
          title: l10n.courseLoadFailedTitle,
          message: preview.message,
        );
        return;
      }
      final mode = await _resolveReloadMode(preview);
      if (mode == null) {
        return;
      }
      final result = await service.applyCourseLoad(
        teacherId: widget.teacherId,
        preview: preview,
        mode: mode,
      );
      if (!mounted) {
        return;
      }
      if (result.success) {
        _course = result.course ?? _course;
        if (_course != null) {
          _courseName = _course!.subject;
          _folderController.text = _course!.sourcePath ?? folderPath;
        }
        _showMessage(l10n.courseLoadedMessage);
      } else {
        await _showErrorDialog(
          title: l10n.courseLoadFailedTitle,
          message: result.message,
        );
      }
    } catch (e) {
      if (mounted) {
        await _showErrorDialog(
          title: l10n.courseLoadFailedTitle,
          message: e.toString(),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingCourse = false);
      }
    }
  }

  Future<CourseReloadMode?> _resolveReloadMode(
      CourseLoadPreview preview) async {
    if (!preview.hasExisting) {
      return CourseReloadMode.fresh;
    }
    final choice = await _showReloadChoiceDialog();
    if (choice == null) {
      return null;
    }
    if (choice == CourseReloadMode.wipe) {
      final confirmed = await _confirmDeleteDialog();
      return confirmed ? CourseReloadMode.wipe : null;
    }
    if (choice == CourseReloadMode.override &&
        preview.deletedEntries.isNotEmpty) {
      final confirmed = await _confirmDeletedNodesDialog(
        preview.deletedEntries,
      );
      return confirmed ? CourseReloadMode.override : null;
    }
    return choice;
  }

  Future<void> _browseFolder() async {
    final l10n = AppLocalizations.of(context)!;
    String? path;
    try {
      if (Platform.isAndroid) {
        path = await CourseImportService.pickAndImportCourseFolder();
      } else {
        path = await FilePicker.platform.getDirectoryPath(
          dialogTitle: l10n.courseFolderPickerTitle,
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      await _showErrorDialog(
        title: l10n.courseLoadFailedTitle,
        message: e.toString(),
      );
      return;
    }
    final resolvedPath = path?.trim();
    if (resolvedPath == null || resolvedPath.isEmpty) {
      return;
    }
    setState(() {
      _folderController.text = resolvedPath;
      _courseName = _course?.subject ?? p.basename(p.normalize(resolvedPath));
    });
  }

  Future<CourseReloadMode?> _showReloadChoiceDialog() {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<CourseReloadMode>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text(l10n.courseReloadTitle),
        content: Text(l10n.courseReloadBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancelButton),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(CourseReloadMode.override),
            child: Text(l10n.courseReloadOverride),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(CourseReloadMode.wipe),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDeleteDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text(l10n.courseReloadDeleteConfirmTitle),
        content: Text(l10n.courseReloadDeleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<bool> _confirmDeletedNodesDialog(
    List<CourseReloadEntry> deletedEntries,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final size = MediaQuery.of(context).size;
    final totalSessionDeletes = deletedEntries.fold<int>(
      0,
      (sum, entry) => sum + entry.sessionCount,
    );
    final lines = deletedEntries.map((entry) {
      final raw = entry.rawLine.trim();
      final sessionSuffix = entry.sessionCount > 0
          ? ' (sessions deleted: ${entry.sessionCount})'
          : '';
      if (raw.isNotEmpty) {
        return '$raw$sessionSuffix';
      }
      final signature = entry.signature.trim();
      if (signature.isNotEmpty) {
        return '${entry.id} $signature$sessionSuffix';
      }
      return '${entry.id}$sessionSuffix';
    }).join('\n');
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Text(
                  l10n.courseReloadDeletedTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText(
                    totalSessionDeletes > 0
                        ? '${l10n.courseReloadDeletedMessage}\n\n'
                            'This reload will delete $totalSessionDeletes linked sessions.\n\n$lines'
                        : '${l10n.courseReloadDeletedMessage}\n\n$lines',
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(l10n.cancelButton),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(l10n.okButton),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return confirmed ?? false;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _showErrorDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 480),
          child: SingleChildScrollView(
            child: SelectableText(message),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppLocalizations.of(context)!.closeButton),
          ),
        ],
      ),
    );
  }

  String _initialReloadFolderPath(CourseVersion course) {
    final sourcePath = (course.sourcePath ?? '').trim();
    if (sourcePath.isEmpty) {
      return '';
    }
    final normalizedPath = p.normalize(sourcePath);
    if (normalizedPath.contains('downloaded_courses')) {
      return '';
    }
    return sourcePath;
  }
}
