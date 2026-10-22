import 'dart:math' as math;

typedef AnalyticsRow = Map<String, Object?>;

enum AnalyticsMetric {
  form('Aproveitamento'),
  goals('Gols'),
  balance('Saldo'),
  possession('Posse');

  const AnalyticsMetric(this.label);
  final String label;
}

class AnalyticsMatch {
  AnalyticsMatch(this.row) : date = DateTime.parse(row['date'] as String);
  final AnalyticsRow row;
  final DateTime date;
  String get id => '${row['id']}';
  String get seasonId => '${row['seasonId']}';
  String get teamId => '${row['playerTeamId']}';
  String get competitionId => '${row['tournamentId']}';
  String get location => '${row['location']}';
  int get scored => (row['playerTeamScore'] as num? ?? 0).toInt();
  int get conceded => (row['oppositeTeamScore'] as num? ?? 0).toInt();
  int get points => scored > conceded
      ? 3
      : scored == conceded
      ? 1
      : 0;
  String get result => points == 3
      ? 'V'
      : points == 1
      ? 'E'
      : 'D';
  double? get possession => (row['teamPossession'] as num?)?.toDouble();
  double? get accuracy => (row['passAccuracy'] as num?)?.toDouble();
  double? get shots =>
      ((row['playerTeamShoutsCount'] ?? row['playerTeamShotsCount']) as num?)
          ?.toDouble();
}

class AnalyticsFilter {
  const AnalyticsFilter({
    this.seasonId,
    this.teamId,
    this.competitionId,
    this.location,
    this.from,
    this.to,
  });
  final String? seasonId, teamId, competitionId, location;
  final DateTime? from, to;
  int get activeCount => [
    seasonId,
    teamId,
    competitionId,
    location,
    from,
  ].where((value) => value != null).length;

  bool includes(AnalyticsMatch match) {
    final day = DateTime(match.date.year, match.date.month, match.date.day);
    return (seasonId == null || match.seasonId == seasonId) &&
        (teamId == null || match.teamId == teamId) &&
        (competitionId == null || match.competitionId == competitionId) &&
        (location == null || match.location == location) &&
        (from == null ||
            !day.isBefore(DateTime(from!.year, from!.month, from!.day))) &&
        (to == null || !day.isAfter(DateTime(to!.year, to!.month, to!.day)));
  }
}

class AnalyticsPoint {
  const AnalyticsPoint(this.match, this.value, {this.other});
  final AnalyticsMatch match;
  final double? value, other;
}

class TeamAnalytics {
  TeamAnalytics(Iterable<AnalyticsMatch> matches)
    : matches = matches.toList()
        ..sort((a, b) {
          final order = a.date.compareTo(b.date);
          return order == 0 ? a.id.compareTo(b.id) : order;
        });
  factory TeamAnalytics.fromRows(
    List<AnalyticsRow> rows, {
    AnalyticsFilter filter = const AnalyticsFilter(),
  }) => TeamAnalytics(
    rows
        .where(
          (row) => DateTime.tryParse(row['date']?.toString() ?? '') != null,
        )
        .map(AnalyticsMatch.new)
        .where(filter.includes),
  );

  final List<AnalyticsMatch> matches;
  int get played => matches.length;
  int get wins => matches.where((m) => m.points == 3).length;
  int get draws => matches.where((m) => m.points == 1).length;
  int get losses => played - wins - draws;
  int get goalsFor => matches.fold(0, (sum, m) => sum + m.scored);
  int get goalsAgainst => matches.fold(0, (sum, m) => sum + m.conceded);
  int get balance => goalsFor - goalsAgainst;
  int get points => wins * 3 + draws;
  int get cleanSheets => matches.where((m) => m.conceded == 0).length;
  double get efficiency => played == 0 ? 0 : points / (played * 3) * 100;
  double get scoredPerGame => played == 0 ? 0 : goalsFor / played;
  double get concededPerGame => played == 0 ? 0 : goalsAgainst / played;
  double? mean(double? Function(AnalyticsMatch) read) {
    final values = matches.map(read).whereType<double>().toList();
    return values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;
  }

  int samples(double? Function(AnalyticsMatch) read) =>
      matches.where((m) => read(m) != null).length;

  int get longestUnbeaten {
    var best = 0, current = 0;
    for (final match in matches) {
      current = match.points == 0 ? 0 : current + 1;
      best = math.max(best, current);
    }
    return best;
  }

  TeamAnalytics get recent =>
      TeamAnalytics(matches.skip(math.max(0, played - 5)));
  double? get formChange {
    if (played < 10) return null;
    final before = TeamAnalytics(matches.skip(played - 10).take(5));
    return recent.efficiency - before.efficiency;
  }

  List<AnalyticsPoint> evolution(AnalyticsMetric metric) {
    var balance = 0;
    return [
      for (var i = 0; i < played; i++)
        (() {
          final match = matches[i];
          balance += match.scored - match.conceded;
          final window = TeamAnalytics(
            matches.sublist(math.max(0, i - 4), i + 1),
          );
          return switch (metric) {
            AnalyticsMetric.form => AnalyticsPoint(match, window.efficiency),
            AnalyticsMetric.goals => AnalyticsPoint(
              match,
              window.scoredPerGame,
              other: window.concededPerGame,
            ),
            AnalyticsMetric.balance => AnalyticsPoint(
              match,
              balance.toDouble(),
            ),
            AnalyticsMetric.possession => AnalyticsPoint(
              match,
              match.possession,
            ),
          };
        })(),
    ];
  }

  Map<String, TeamAnalytics> groupBy(String Function(AnalyticsMatch) key) {
    final groups = <String, List<AnalyticsMatch>>{};
    for (final match in matches) {
      (groups[key(match)] ??= []).add(match);
    }
    return {
      for (final entry in groups.entries) entry.key: TeamAnalytics(entry.value),
    };
  }

  Map<String, TeamAnalytics> get months => groupBy(
    (m) => '${m.date.year}-${m.date.month.toString().padLeft(2, '0')}',
  );
  Map<String, TeamAnalytics> get seasons => groupBy((m) => m.seasonId);
}
