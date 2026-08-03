import 'package:flutter/material.dart';

List<Widget> buildAppBarActionsWithClose(
  BuildContext context, {
  Iterable<Widget> actions = const <Widget>[],
  bool closeEnabled = true,
  String? disabledCloseTooltip,
}) {
  return actions.toList(growable: false);
}
