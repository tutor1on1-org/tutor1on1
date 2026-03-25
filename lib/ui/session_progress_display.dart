import '../db/app_database.dart';

int resolveSessionProgressPercent({
  required ResolvedStudentPassRule passRule,
  required int easyPassedCount,
  required int mediumPassedCount,
  required int hardPassedCount,
}) {
  if (passRule.passThreshold <= 0) {
    return 100;
  }
  final percent = (passRule.scoreForCounts(
            easyCount: easyPassedCount,
            mediumCount: mediumPassedCount,
            hardCount: hardPassedCount,
          ) /
          passRule.passThreshold *
          100)
      .round();
  if (percent < 0) {
    return 0;
  }
  return percent;
}

class SessionProgressDisplayValue {
  const SessionProgressDisplayValue({
    required this.easyPassedCount,
    required this.mediumPassedCount,
    required this.hardPassedCount,
    required this.percent,
  });

  factory SessionProgressDisplayValue.fromProgress({
    required ResolvedStudentPassRule passRule,
    ProgressEntry? progress,
  }) {
    final easyPassedCount = progress?.easyPassedCount ?? 0;
    final mediumPassedCount = progress?.mediumPassedCount ?? 0;
    final hardPassedCount = progress?.hardPassedCount ?? 0;
    return SessionProgressDisplayValue(
      easyPassedCount: easyPassedCount,
      mediumPassedCount: mediumPassedCount,
      hardPassedCount: hardPassedCount,
      percent: resolveSessionProgressPercent(
        passRule: passRule,
        easyPassedCount: easyPassedCount,
        mediumPassedCount: mediumPassedCount,
        hardPassedCount: hardPassedCount,
      ),
    );
  }

  final int easyPassedCount;
  final int mediumPassedCount;
  final int hardPassedCount;
  final int percent;

  String get compactLabel =>
      '$easyPassedCount/$mediumPassedCount/$hardPassedCount/$percent%';
}
