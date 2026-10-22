import '../TeamPage/ViewPlayer/PlayerProfileData.dart';
import 'PlayersStatData.dart';
import 'RecordedPlayerStats.dart';

class ActivityCalculation {
  const ActivityCalculation(
    this.value,
    this.games,
    this.numerator,
    this.denominator,
  );
  final double value;
  final int games;
  final num numerator, denominator;
}

class PlayerActivityAnalysis {
  PlayerActivityAnalysis(Iterable<PlayerMatchData> source)
    : matches = source.toList()
        ..sort(
          (a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
        ) {
    records = [
      for (final m in matches) RecordedPlayerStats([m]),
    ];
  }
  final List<PlayerMatchData> matches;
  late final List<RecordedPlayerStats> records;

  ActivityCalculation? per90(PlayersStatMetric metric) => _ratio(
    (i) => records[i][metric],
    (i) => registeredPlayerMinutes(matches[i]),
    factor: 90,
  );

  ActivityCalculation? get goalParticipation => _ratio(
    (i) => records[i][PlayersStatMetric.goalsAssists],
    (i) => matches[i].row['playerTeamScore'] as num?,
    factor: 100,
    bounded: true,
  );

  ActivityCalculation? get conversion => _ratio(
    (i) => records[i][PlayersStatMetric.goals],
    (i) => records[i][PlayersStatMetric.shots],
    factor: 100,
    bounded: true,
  );

  ActivityCalculation? get startRate => _ratio(
    (i) => records[i][PlayersStatMetric.starts],
    (_) => 1,
    factor: 100,
  );

  ActivityCalculation? _ratio(
    num? Function(int) top,
    num? Function(int) base, {
    double factor = 1,
    bool bounded = false,
  }) {
    num numerator = 0, denominator = 0;
    var games = 0;
    for (var i = 0; i < matches.length; i++) {
      final n = top(i), d = base(i);
      if (n == null ||
          d == null ||
          !n.isFinite ||
          !d.isFinite ||
          n < 0 ||
          d <= 0 ||
          (bounded && n > d)) {
        continue;
      }
      numerator += n;
      denominator += d;
      games++;
    }
    return games == 0
        ? null
        : ActivityCalculation(
            numerator * factor / denominator,
            games,
            numerator,
            denominator,
          );
  }

  List<PlayerMatchData> get recent => matches.take(5).toList();
  List<PlayerMatchData> get previous => matches.skip(5).take(5).toList();
  double? averageRating(Iterable<PlayerMatchData> appearances) {
    final values = appearances
        .map((m) => m.performance.avgRating)
        .whereType<double>()
        .toList();
    return values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;
  }

  double? get ratingChange {
    final current = averageRating(recent), prior = averageRating(previous);
    return current == null || prior == null ? null : current - prior;
  }
}
