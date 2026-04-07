import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'quit_app_flow.dart';

List<Widget> buildAppBarActionsWithClose(
  BuildContext context, {
  Iterable<Widget> actions = const <Widget>[],
}) {
  final closeTooltip = AppLocalizations.of(context)?.closeButton ?? 'Close';
  return <Widget>[
    ...actions,
    IconButton(
      tooltip: closeTooltip,
      icon: const Icon(Icons.close),
      onPressed: () => AppQuitFlow.handleQuit(context),
    ),
  ];
}
