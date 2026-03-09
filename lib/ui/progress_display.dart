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

Color resolveProgressDisplayColor(double ratio) {
  final clamped = ratio.clamp(0.0, 1.0);
  return Color.lerp(
        Colors.grey.shade300,
        Colors.green.shade300,
        clamped,
      ) ??
      Colors.grey.shade300;
}
