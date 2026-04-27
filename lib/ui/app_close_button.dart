import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'quit_app_flow.dart';

List<Widget> buildAppBarActionsWithClose(
  BuildContext context, {
  Iterable<Widget> actions = const <Widget>[],
  bool closeEnabled = true,
  String? disabledCloseTooltip,
}) {
  final closeTooltip = AppLocalizations.of(context)?.closeButton ?? 'Close';
  return <Widget>[
    ...actions,
    IconButton(
      tooltip:
          closeEnabled ? closeTooltip : (disabledCloseTooltip ?? closeTooltip),
      icon: const Icon(Icons.close),
      onPressed: closeEnabled ? () => AppQuitFlow.handleQuit(context) : null,
    ),
  ];
}
