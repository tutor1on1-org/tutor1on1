import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_controller.dart';
import '../app_close_button.dart';
import '../quit_app_flow.dart';

class TeacherPendingPage extends StatelessWidget {
  const TeacherPendingPage({
    super.key,
    required this.role,
  });

  final String role;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.currentUser;
    final isRejected = role == 'teacher_rejected';
    final title = isRejected
        ? 'Teacher Registration Rejected'
        : 'Teacher Registration Pending';
    final message = isRejected
        ? 'Your teacher account is currently rejected. Ask the admin or a matching subject admin to review it again after updating the subject labels.'
        : 'Your teacher account is waiting for approval. Admin or a matching subject admin can approve it.';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: buildAppBarActionsWithClose(
          context,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => AppQuitFlow.handleLogout(context),
            ),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user == null ? title : 'Hello, ${user.username}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(message),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
