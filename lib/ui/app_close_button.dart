import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'quit_app_flow.dart';

List<Widget> buildAppBarActionsWithClose(
  BuildContext context, {
  Iterable<Widget> actions = const <Widget>[],
}) {
  return <Widget>[
    ...actions,
    IconButton(
      tooltip: AppLocalizations.of(context)!.closeButton,
      icon: const Icon(Icons.close),
      onPressed: () => AppQuitFlow.handleQuit(context),
    ),
  ];
}
