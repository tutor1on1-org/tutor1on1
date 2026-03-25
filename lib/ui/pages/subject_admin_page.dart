import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_services.dart';
import '../../services/marketplace_api_service.dart';
import '../app_close_button.dart';

class SubjectAdminPage extends StatefulWidget {
  const SubjectAdminPage({super.key});

  @override
  State<SubjectAdminPage> createState() => _SubjectAdminPageState();
}

class _SubjectAdminPageState extends State<SubjectAdminPage> {
  late final MarketplaceApiService _api;
  bool _loading = true;
  String? _error;
  List<TeacherRegistrationApprovalRequest> _teacherRequests = [];
  List<CourseUploadApprovalRequest> _courseRequests = [];

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
      final teacherRequests =
          await _api.listSubjectAdminTeacherRegistrationRequests();
      final courseRequests = await _api.listSubjectAdminCourseUploadRequests();
      if (!mounted) {
        return;
      }
      setState(() {
        _teacherRequests = teacherRequests;
        _courseRequests = courseRequests;
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Subject Admin'),
          actions: buildAppBarActionsWithClose(
            context,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _load,
              ),
            ],
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Teacher Requests'),
              Tab(text: 'Course Uploads'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: SelectableText(_error!))
                : TabBarView(
                    children: [
                      _buildTeacherRequests(),
                      _buildCourseRequests(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildTeacherRequests() {
    if (_teacherRequests.isEmpty) {
      return const Center(child: Text('No teacher requests for your labels.'));
    }
    return ListView.builder(
      itemCount: _teacherRequests.length,
      itemBuilder: (context, index) {
        final request = _teacherRequests[index];
        return Card(
          child: ListTile(
            title: Text(request.displayName.isEmpty
                ? request.username
                : '${request.displayName} (${request.username})'),
            subtitle: Text(_labelSummary(request.subjectLabels)),
            trailing: Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () =>
                      _decideTeacher(request.requestId, approve: false),
                  child: const Text('Reject'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      _decideTeacher(request.requestId, approve: true),
                  child: const Text('Approve'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCourseRequests() {
    if (_courseRequests.isEmpty) {
      return const Center(
          child: Text('No new course uploads for your labels.'));
    }
    return ListView.builder(
      itemCount: _courseRequests.length,
      itemBuilder: (context, index) {
        final request = _courseRequests[index];
        return Card(
          child: ListTile(
            title: Text(request.courseSubject),
            subtitle: Text(
              '${request.teacherName}\n${_labelSummary(request.subjectLabels)}',
            ),
            isThreeLine: true,
            trailing: Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () =>
                      _decideCourse(request.requestId, approve: false),
                  child: const Text('Reject'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      _decideCourse(request.requestId, approve: true),
                  child: const Text('Approve'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _decideTeacher(int requestId, {required bool approve}) async {
    try {
      if (approve) {
        await _api.approveSubjectAdminTeacherRegistration(requestId);
      } else {
        await _api.rejectSubjectAdminTeacherRegistration(requestId);
      }
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  Future<void> _decideCourse(int requestId, {required bool approve}) async {
    try {
      if (approve) {
        await _api.approveSubjectAdminCourseUpload(requestId);
      } else {
        await _api.rejectSubjectAdminCourseUpload(requestId);
      }
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  String _labelSummary(List<SubjectLabelSummary> labels) {
    if (labels.isEmpty) {
      return 'No subject labels';
    }
    return labels.map((label) => label.name).join(', ');
  }
}
