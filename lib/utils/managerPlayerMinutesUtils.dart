import '../models/ManagerFixturePlayerPerformance.dart';

int getManagerFixtureDurationMinutes({
  required bool extraTime,
  Iterable<int?> opponentGoalMinutes = const [],
  ManagerFixturePlayerPerformance? performance,
}) {
  if (extraTime) return 120;
  final minutes = <int?>[
    ...opponentGoalMinutes,
    if (performance != null)
      for (final list in <List<PerformanceTimeDetails>>[
        performance.goalDetails,
        performance.assistDetails,
        performance.yellowCardDetails,
        performance.redCardDetails,
        performance.substitutionDetails,
        performance.ownGoalDetails,
        performance.missedPenaltyDetails,
        performance.injuryDetails,
      ])
        for (final item in list) item.minute,
  ];
  return minutes.any((minute) => minute != null && minute > 90) ? 120 : 90;
}

int getManagerPlayerPlayedMinutes(
  ManagerFixturePlayerPerformance performance,
  int duration,
) {
  if (performance.recordedMinutes != null) return performance.recordedMinutes!;
  int? first(SubstitutionType type) {
    final item = performance.substitutionDetails
        .where((sub) => sub.type == type && sub.minute != null)
        .firstOrNull;
    return item == null ? null : item.minute! + (item.addedMinute ?? 0);
  }

  final start = (first(SubstitutionType.inGame) ?? 0).clamp(0, duration);
  final end = (first(SubstitutionType.outGame) ?? duration).clamp(0, duration);
  return end - start < 0 ? 0 : end - start;
}

String getMinutesPerActionLabel(int minutes, int actions) =>
    actions == 0 ? '-' : (minutes / actions).toStringAsFixed(2);
