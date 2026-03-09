int resolveProgressDisplayPercent({
  required int litPercent,
  required bool lit,
  required String? questionLevel,
}) {
  var resolved = litPercent.clamp(0, 100);
  final normalizedLevel = questionLevel?.trim().toLowerCase();
  switch (normalizedLevel) {
    case 'hard':
      if (resolved < 100) {
        resolved = 100;
      }
      break;
    case 'medium':
      if (resolved < 66) {
        resolved = 66;
      }
      break;
    case 'easy':
      if (resolved < 33) {
        resolved = 33;
      }
      break;
  }
  if (lit && resolved < 100) {
    resolved = 100;
  }
  return resolved;
}
