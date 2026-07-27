class SyncProgress {
  const SyncProgress({
    required this.message,
    this.completed,
    this.total,
    this.completedBytes,
    this.totalBytes,
    this.forcePaint = false,
  });

  final String message;
  final int? completed;
  final int? total;
  final int? completedBytes;
  final int? totalBytes;
  final bool forcePaint;

  double? get value {
    final completedValue = completed;
    final totalValue = total;
    if (completedValue == null || totalValue == null || totalValue <= 0) {
      final completedByteValue = completedBytes;
      final totalByteValue = totalBytes;
      if (completedByteValue == null ||
          totalByteValue == null ||
          totalByteValue <= 0) {
        return null;
      }
      final normalizedCompleted =
          completedByteValue.clamp(0, totalByteValue).toDouble();
      return normalizedCompleted / totalByteValue;
    }
    final normalizedCompleted = completedValue.clamp(0, totalValue);
    return normalizedCompleted / totalValue;
  }

  String? get detail {
    final parts = <String>[];
    final completedValue = completed;
    final totalValue = total;
    if (completedValue != null && totalValue != null && totalValue > 0) {
      parts.add('$completedValue / $totalValue');
    }
    final completedByteValue = completedBytes;
    final totalByteValue = totalBytes;
    if (completedByteValue != null && completedByteValue >= 0) {
      if (totalByteValue != null && totalByteValue > 0) {
        parts.add(
          '${_formatMegabytes(completedByteValue)} / '
          '${_formatMegabytes(totalByteValue)}',
        );
      } else {
        parts.add(_formatMegabytes(completedByteValue));
      }
    }
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' | ');
  }

  static String _formatMegabytes(int bytes) {
    final megabytes = bytes / (1024 * 1024);
    return '${megabytes.toStringAsFixed(1)} MB';
  }
}

typedef SyncProgressCallback = void Function(SyncProgress progress);
