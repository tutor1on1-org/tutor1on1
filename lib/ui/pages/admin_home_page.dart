import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_services.dart';
import '../../services/marketplace_api_service.dart';
import '../../state/auth_controller.dart';
import '../app_close_button.dart';
import '../quit_app_flow.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  late final MarketplaceApiService _api;
  bool _loading = true;
  String? _error;
  List<AdminUserSummary> _users = [];
  List<AdminSubjectLabelSummary> _labels = [];
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
      final users = await _api.listAdminUsers();
      final labels = await _api.listAdminSubjectLabels();
      final teacherRequests = await _api.listAdminTeacherRegistrationRequests();
      final courseRequests = await _api.listAdminCourseUploadRequests();
      if (!mounted) {
        return;
      }
      setState(() {
        _users = users;
        _labels = labels;
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
    final auth = context.watch<AuthController>();
    final admin = auth.currentUser;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(admin == null ? 'Admin' : 'Admin - ${admin.username}'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Users'),
              Tab(text: 'Teacher Requests'),
              Tab(text: 'Course Uploads'),
              Tab(text: 'Subject Labels'),
            ],
          ),
          actions: buildAppBarActionsWithClose(
            context,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _load,
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  final confirmed =
                      await AppQuitFlow.confirmTeacherPinIfRequired(context);
                  if (!confirmed) {
                    return;
                  }
                  await auth.logout();
                },
              ),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: SelectableText(_error!))
                : TabBarView(
                    children: [
                      _buildUsers(),
                      _buildTeacherRequests(),
                      _buildCourseRequests(),
                      _buildSubjectLabels(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildUsers() {
    return ListView.builder(
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        final canDeleteTeacher = user.role == 'teacher';
        final subtitle = [
          user.email,
          if (user.teacherSubjectLabels.isNotEmpty)
            user.teacherSubjectLabels.map((label) => label.name).join(', '),
        ].join('\n');
        return Card(
          child: ListTile(
            title: Text('${user.username} (${user.role})'),
            subtitle: subtitle.isEmpty ? null : Text(subtitle),
            isThreeLine: subtitle.contains('\n'),
            trailing: canDeleteTeacher
                ? IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _deleteTeacher(user),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildTeacherRequests() {
    if (_teacherRequests.isEmpty) {
      return const Center(
          child: Text('No pending teacher registration requests.'));
    }
    return ListView.builder(
      itemCount: _teacherRequests.length,
      itemBuilder: (context, index) {
        final request = _teacherRequests[index];
        return Card(
          child: ListTile(
            title: Text(
              request.displayName.isEmpty
                  ? request.username
                  : '${request.displayName} (${request.username})',
            ),
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
      return const Center(child: Text('No pending course upload requests.'));
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

  Widget _buildSubjectLabels() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton(
              onPressed: _createSubjectLabel,
              child: const Text('Create Subject Label'),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _labels.length,
            itemBuilder: (context, index) {
              final label = _labels[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('${label.name} (${label.slug})'),
                          ),
                          TextButton(
                            onPressed: () => _editSubjectLabel(label),
                            child: const Text('Edit'),
                          ),
                          TextButton(
                            onPressed: () => _assignSubjectAdmin(label),
                            child: const Text('Assign Admin'),
                          ),
                        ],
                      ),
                      Text(
                        label.subjectAdmins.isEmpty
                            ? 'No subject admins'
                            : 'Subject admins: ${label.subjectAdmins.map((item) => item.username).join(', ')}',
                      ),
                      for (final admin in label.subjectAdmins)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => _removeSubjectAdmin(label, admin),
                            child: Text('Remove ${admin.username}'),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _deleteTeacher(AdminUserSummary user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete teacher ${user.username}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await _api.deleteAdminTeacher(user.userId);
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _decideTeacher(int requestId, {required bool approve}) async {
    try {
      if (approve) {
        await _api.approveAdminTeacherRegistration(requestId);
      } else {
        await _api.rejectAdminTeacherRegistration(requestId);
      }
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _decideCourse(int requestId, {required bool approve}) async {
    try {
      if (approve) {
        await _api.approveAdminCourseUpload(requestId);
      } else {
        await _api.rejectAdminCourseUpload(requestId);
      }
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _createSubjectLabel() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Subject Label'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (confirmed != true || controller.text.trim().isEmpty) {
      return;
    }
    try {
      await _api.createAdminSubjectLabel(name: controller.text.trim());
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _editSubjectLabel(AdminSubjectLabelSummary label) async {
    final controller = TextEditingController(text: label.name);
    var isActive = label.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Subject Label'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              SwitchListTile(
                value: isActive,
                title: const Text('Active'),
                onChanged: (value) {
                  setDialogState(() {
                    isActive = value;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || controller.text.trim().isEmpty) {
      return;
    }
    try {
      await _api.updateAdminSubjectLabel(
        subjectLabelId: label.subjectLabelId,
        name: controller.text.trim(),
        isActive: isActive,
      );
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _assignSubjectAdmin(AdminSubjectLabelSummary label) async {
    final teacherCandidates =
        _users.where((user) => user.role == 'teacher').toList();
    if (teacherCandidates.isEmpty) {
      _showError('No active teachers available.');
      return;
    }
    int? selectedUserId = teacherCandidates.first.userId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Assign Subject Admin - ${label.name}'),
          content: DropdownButtonFormField<int>(
            initialValue: selectedUserId,
            items: [
              for (final teacher in teacherCandidates)
                DropdownMenuItem<int>(
                  value: teacher.userId,
                  child: Text(teacher.username),
                ),
            ],
            onChanged: (value) {
              setDialogState(() {
                selectedUserId = value;
              });
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedUserId == null
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || selectedUserId == null) {
      return;
    }
    try {
      await _api.assignSubjectAdmin(
        subjectLabelId: label.subjectLabelId,
        teacherUserId: selectedUserId!,
      );
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _removeSubjectAdmin(
    AdminSubjectLabelSummary label,
    SubjectAdminAssignmentSummary admin,
  ) async {
    try {
      await _api.removeSubjectAdmin(
        subjectLabelId: label.subjectLabelId,
        teacherUserId: admin.userId,
      );
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$error')),
    );
  }

  String _labelSummary(List<SubjectLabelSummary> labels) {
    if (labels.isEmpty) {
      return 'No subject labels';
    }
    return labels.map((label) => label.name).join(', ');
  }
}
