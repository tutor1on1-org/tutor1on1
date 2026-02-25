import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../../services/marketplace_api_service.dart';

class MarketplacePage extends StatefulWidget {
  const MarketplacePage({super.key});

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  late final MarketplaceApiService _api;
  bool _loading = true;
  String? _error;
  List<CatalogCourse> _courses = [];
  final Map<int, EnrollmentRequestSummary> _requestsByCourse = {};
  final Set<int> _enrolledCourseIds = {};

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
      final courses = await _api.listCourses();
      final requests = await _api.listStudentRequests();
      final enrollments = await _api.listEnrollments();
      final requestMap = <int, EnrollmentRequestSummary>{};
      for (final request in requests) {
        requestMap[request.courseId] = request;
      }
      final enrolledIds = enrollments.map((e) => e.courseId).toSet();
      if (!mounted) {
        return;
      }
      setState(() {
        _courses = courses;
        _requestsByCourse
          ..clear()
          ..addAll(requestMap);
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
      body: _loading
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
    CatalogCourse course,
  ) {
    final request = _requestsByCourse[course.courseId];
    final enrolled = _enrolledCourseIds.contains(course.courseId);
    String statusLabel = '';
    String buttonLabel = l10n.marketplaceRequestButton;
    bool canRequest = !enrolled;
    if (enrolled) {
      statusLabel = l10n.marketplaceEnrolled;
      canRequest = false;
      buttonLabel = l10n.marketplaceEnrolled;
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
        canRequest = false;
        buttonLabel = l10n.marketplaceApproved;
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
            if (course.description.isNotEmpty)
              Text(course.description),
            if (statusLabel.isNotEmpty) Text(statusLabel),
          ],
        ),
        isThreeLine: true,
        trailing: ElevatedButton(
          onPressed: canRequest ? () => _requestEnrollment(context, course) : null,
          child: Text(buttonLabel),
        ),
      ),
    );
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
          decoration: InputDecoration(labelText: l10n.marketplaceRequestMessage),
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
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.marketplaceRequestFailed('$error'))),
      );
    }
  }
}
