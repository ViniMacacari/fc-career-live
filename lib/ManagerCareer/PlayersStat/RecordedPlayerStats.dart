import '../TeamPage/ViewPlayer/PlayerProfileData.dart';
import 'PlayersStatData.dart';

int? registeredPlayerMinutes(PlayerMatchData match) {
  final p = match.performance;
  if (p.recordedMinutes != null) return p.recordedMinutes;
  final apiMinutes = p.apiStats['minutesPlayed'];
  if (apiMinutes is num && apiMinutes.isFinite && apiMinutes >= 0) {
    return apiMinutes.toInt();
  }
  return p.substitutionDetails.any((s) => s.minute != null && s.type != null)
      ? match.minutes
      : null;
}

const playerActivityMetricGroups = <(String, List<PlayersStatMetric>)>[
  (
    'Participação',
    [
      PlayersStatMetric.matches,
      PlayersStatMetric.minutes,
      PlayersStatMetric.starts,
      PlayersStatMetric.rating,
      PlayersStatMetric.motm,
      PlayersStatMetric.captainMatches,
      PlayersStatMetric.captainStarts,
    ],
  ),
  (
    'Ataque',
    [
      PlayersStatMetric.goals,
      PlayersStatMetric.penalties,
      PlayersStatMetric.shots,
      PlayersStatMetric.shotAccuracy,
      PlayersStatMetric.hatTricks,
    ],
  ),
  (
    'Criação e posse',
    [
      PlayersStatMetric.assists,
      PlayersStatMetric.goalsAssists,
      PlayersStatMetric.keyPasses,
      PlayersStatMetric.passes,
      PlayersStatMetric.passAccuracy,
      PlayersStatMetric.dribbles,
      PlayersStatMetric.dribbleAccuracy,
    ],
  ),
  (
    'Defesa e disciplina',
    [
      PlayersStatMetric.tackles,
      PlayersStatMetric.tackleAccuracy,
      PlayersStatMetric.yellowCards,
      PlayersStatMetric.redCards,
      PlayersStatMetric.ownGoals,
      PlayersStatMetric.saves,
      PlayersStatMetric.penaltySaves,
      PlayersStatMetric.cleanSheets,
    ],
  ),
];

class RecordedPlayerStats {
  RecordedPlayerStats(Iterable<PlayerMatchData> source)
    : matches = source.toList() {
    values[PlayersStatMetric.matches] = matches.length;
    for (final m in matches) {
      final p = m.performance;
      num? events(num? count, int length) =>
          count ?? (length > 0 ? length : null);
      final goals = events(p.goalsCount, p.goalDetails.length);
      final assists = events(p.assistsCount, p.assistDetails.length);
      void add(PlayersStatMetric metric, num? value) {
        if (value == null) return;
        values[metric] = (values[metric] ?? 0) + value;
        coverage[metric] = (coverage[metric] ?? 0) + 1;
      }

      add(PlayersStatMetric.goals, goals);
      add(PlayersStatMetric.assists, assists);
      add(
        PlayersStatMetric.goalsAssists,
        goals != null && assists != null ? goals + assists : null,
      );
      add(PlayersStatMetric.minutes, registeredPlayerMinutes(m));
      add(
        PlayersStatMetric.starts,
        p.recordedStarted == null
            ? null
            : p.recordedStarted!
            ? 1
            : 0,
      );
      add(
        PlayersStatMetric.motm,
        m.row['isPotmFromMyTeam'] == null || m.row['playerOfTheMatchId'] == null
            ? null
            : m.manOfTheMatch
            ? 1
            : 0,
      );
      add(
        PlayersStatMetric.hatTricks,
        goals == null
            ? null
            : goals >= 3
            ? 1
            : 0,
      );
      add(
        PlayersStatMetric.penalties,
        goals == 0
            ? 0
            : m.row['goalDetails'] != null &&
                  p.goalDetails.isNotEmpty &&
                  (goals == null || p.goalDetails.length >= goals)
            ? p.goalDetails.where((g) => g.isPenalty).length
            : null,
      );
      add(
        PlayersStatMetric.yellowCards,
        events(p.yellowCards, p.yellowCardDetails.length),
      );
      add(
        PlayersStatMetric.redCards,
        events(p.redCards, p.redCardDetails.length),
      );
      add(
        PlayersStatMetric.ownGoals,
        p.ownGoalDetails.isEmpty ? null : p.ownGoalDetails.length,
      );
      add(PlayersStatMetric.shots, p.shotsCount);
      add(PlayersStatMetric.passes, p.passes);
      add(PlayersStatMetric.keyPasses, p.keyPasses);
      add(PlayersStatMetric.dribbles, p.dribbles);
      add(PlayersStatMetric.tackles, p.tackles);
      add(PlayersStatMetric.saves, p.saves);
      add(PlayersStatMetric.penaltySaves, p.penaltySaves);
      add(
        PlayersStatMetric.cleanSheets,
        m.row['oppositeTeamScore'] == null
            ? null
            : m.row['oppositeTeamScore'] == 0
            ? 1
            : 0,
      );
      add(PlayersStatMetric.rating, p.avgRating);
      if (m.captaincy.isRecorded) {
        add(PlayersStatMetric.captainMatches, m.wasCaptain ? 1 : 0);
        add(PlayersStatMetric.captainStarts, m.startedCaptain ? 1 : 0);
      }
    }
    if (coverage[PlayersStatMetric.rating] case final int count
        when count > 0) {
      values[PlayersStatMetric.rating] =
          values[PlayersStatMetric.rating]! / count;
    }
    _accuracy(
      PlayersStatMetric.shotAccuracy,
      'shotsOnTarget',
      'shots',
      (m) => m.performance.shotAccuracy,
    );
    _accuracy(
      PlayersStatMetric.passAccuracy,
      'passesCompleted',
      'passes',
      (m) => m.performance.passAccuracy,
    );
    _accuracy(
      PlayersStatMetric.dribbleAccuracy,
      'dribblesCompleted',
      'dribbles',
      (m) => m.performance.dribblesAccuracy,
    );
    _accuracy(
      PlayersStatMetric.tackleAccuracy,
      'tacklesWon',
      'tackles',
      (m) => m.performance.tacklesAccuracy,
    );
  }
  final List<PlayerMatchData> matches;
  final values = <PlayersStatMetric, num>{};
  final coverage = <PlayersStatMetric, int>{};
  final averagedPercentages = <PlayersStatMetric>{};
  num? operator [](PlayersStatMetric metric) => values[metric];
  String format(PlayersStatMetric metric) =>
      metric.format(values[metric]).replaceAll('.', ',');
  String label(PlayersStatMetric metric) => switch (metric) {
    PlayersStatMetric.matches => 'Jogos',
    PlayersStatMetric.goals => 'Gols',
    PlayersStatMetric.rating => 'Nota média',
    PlayersStatMetric.minutes => 'Minutos em campo',
    PlayersStatMetric.starts => 'Titularidades registradas',
    PlayersStatMetric.shots => 'Finalizações',
    PlayersStatMetric.cleanSheets => 'Jogos sem sofrer gols',
    _ =>
      averagedPercentages.contains(metric)
          ? '${metric.label} · média'
          : metric.label,
  };

  void _accuracy(
    PlayersStatMetric metric,
    String numerator,
    String denominator,
    num? Function(PlayerMatchData) fallback,
  ) {
    num top = 0, base = 0;
    var count = 0;
    for (final match in matches) {
      final raw = match.performance.apiStats;
      final n = raw[numerator], d = raw[denominator];
      if (n is num &&
          d is num &&
          n.isFinite &&
          d.isFinite &&
          n >= 0 &&
          d > 0 &&
          n <= d) {
        top += n;
        base += d;
        count++;
      }
    }
    if (count > 0) {
      values[metric] = top * 100 / base;
      coverage[metric] = count;
    } else {
      final known = matches
          .map(fallback)
          .whereType<num>()
          .where((v) => v >= 0 && v <= 100)
          .toList();
      if (known.isNotEmpty) {
        values[metric] = known.reduce((a, b) => a + b) / known.length;
        coverage[metric] = known.length;
        averagedPercentages.add(metric);
      }
    }
  }
}
