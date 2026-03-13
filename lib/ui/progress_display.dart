import 'package:flutter/material.dart';

int resolveProgressDisplayPercent({
  required int litPercent,
  required bool lit,
  required String? questionLevel,
}) {
  if (lit) {
    return 100;
  }
  final normalizedLevel = questionLevel?.trim().toLowerCase();
  switch (normalizedLevel) {
    case 'hard':
      return 100;
    case 'medium':
      return 66;
    case 'easy':
      return 33;
    default:
      return litPercent.clamp(0, 100);
  }
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
