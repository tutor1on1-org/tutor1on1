import 'package:flutter/material.dart';

int resolveProgressDisplayPercent({
  required bool lit,
  required int easyPassedCount,
  required int mediumPassedCount,
  required int hardPassedCount,
}) {
  if (hardPassedCount > 0) {
    return 100;
  }
  if (mediumPassedCount > 0) {
    return 66;
  }
  if (easyPassedCount > 0) {
    return 33;
  }
  return lit ? 100 : 0;
}

Color resolveProgressDisplayColor({
  required double ratio,
  required bool isLit,
}) {
  final clamped = ratio.clamp(0.0, 1.0);
  if (isLit) {
    return Colors.green.shade300;
  }
  return Color.lerp(
        Colors.grey.shade300,
        Colors.orange.shade300,
        clamped,
      ) ??
      Colors.grey.shade300;
}
