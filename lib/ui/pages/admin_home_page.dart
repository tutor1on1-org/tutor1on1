import 'package:flutter/material.dart';
import 'package:family_teacher/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../state/auth_controller.dart';

class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthController>();
    final admin = auth.currentUser!;
    final db = context.read<AppDatabase>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminTitle(admin.username)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => auth.logout(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.teachersSection,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: StreamBuilder<List<User>>(
                stream: db.watchTeachers(),
                builder: (context, snapshot) {
                  final teachers = snapshot.data ?? [];
                  if (teachers.isEmpty) {
                    return Center(child: Text(l10n.noTeachers));
                  }
                  return ListView.builder(
                    itemCount: teachers.length,
                    itemBuilder: (context, index) {
                      final teacher = teachers[index];
                      return ListTile(
                        title: Text(teacher.username),
                        trailing: IconButton(
                          tooltip: l10n.deleteTeacherButton,
                          icon: const Icon(Icons.delete),
                          onPressed: () =>
                              _confirmDeleteTeacher(context, teacher),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteTeacher(
    BuildContext context,
    User teacher,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteTeacherTitle(teacher.username)),
        content: Text(l10n.deleteTeacherMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await db.deleteTeacher(teacher.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.deleteTeacherSuccess)),
      );
    }
  }
}
