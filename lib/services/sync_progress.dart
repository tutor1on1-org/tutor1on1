class SyncProgress {
  const SyncProgress({
    required this.message,
    this.completed,
    this.total,
    this.forcePaint = false,
  });

  final String message;
  final int? completed;
  final int? total;
  final bool forcePaint;

  double? get value {
    final completedValue = completed;
    final totalValue = total;
    if (completedValue == null || totalValue == null || totalValue <= 0) {
      return null;
    }
    final normalizedCompleted = completedValue.clamp(0, totalValue);
    return normalizedCompleted / totalValue;
  }

  String? get detail {
    final completedValue = completed;
    final totalValue = total;
    if (completedValue == null || totalValue == null || totalValue <= 0) {
      return null;
    }
    return '$completedValue / $totalValue';
  }
}

typedef SyncProgressCallback = void Function(SyncProgress progress);
