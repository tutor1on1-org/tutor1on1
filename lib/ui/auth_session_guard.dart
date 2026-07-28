import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/auth_controller.dart';

Future<bool> validateActiveAuthSession(BuildContext context) async {
  final auth = context.read<AuthController>();
  try {
    return await auth.validateCurrentSession();
  } on Object catch (error) {
    if (context.mounted && auth.currentUser != null) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.sessionValidationFailedMessage('$error')),
        ),
      );
    }
    return false;
  }
}

Future<T?> runWithActiveAuthSession<T>(
  BuildContext context,
  Future<T> Function() action,
) async {
  if (!await validateActiveAuthSession(context) || !context.mounted) {
    return null;
  }
  return action();
}
