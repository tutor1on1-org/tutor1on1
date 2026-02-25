import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
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
  String? _error;
  List<TeacherCourseSummary> _courses = [];

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
              : _courses.isEmpty
                  ? Center(child: Text(l10n.teacherMarketplaceEmpty))
                  : ListView.builder(
                      itemCount: _courses.length,
                      itemBuilder: (context, index) {
                        final course = _courses[index];
                        return _buildCourseTile(context, l10n, course);
                      },
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

  Widget _buildCourseTile(
    BuildContext context,
    AppLocalizations l10n,
    TeacherCourseSummary course,
  ) {
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
          ],
        ),
        trailing: DropdownButton<String>(
          value: course.visibility.isNotEmpty ? course.visibility : 'private',
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.subjectRequired)),
      );
      return;
    }
    try {
      await _api.createTeacherCourse(
        subject: subject,
        grade: gradeController.text,
        description: descriptionController.text,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.teacherMarketplaceCreated)),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.marketplaceRequestFailed('$error'))),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.marketplaceVisibilityUpdated)),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.marketplaceRequestFailed('$error'))),
      );
    }
  }
}

