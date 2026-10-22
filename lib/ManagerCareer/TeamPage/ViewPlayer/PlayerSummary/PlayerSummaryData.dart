import 'dart:convert';
import 'dart:math' as math;

import '../../../../Common/FixtureResultTile.dart'
    show FixtureResult, fixtureResult;
import '../../../../models/ManagerFixture.dart' show decodeOpponentGoals;
import '../../../../models/ManagerFixturePlayerPerformance.dart';
import '../../../../models/Person.dart';
import '../../../../utils/SqlService.dart';
import '../../../../utils/managerPlayerMinutesUtils.dart';
import '../PlayerProfileData.dart';

class PlayerSummarySource {
  const PlayerSummarySource({
    this.fixtures = const [],
    this.teamGoals = const {},
    this.names = const {},
  });

  final List<Map<String, Object?>> fixtures;

  final Map<String, List<PerformanceGoalDetails>> teamGoals;

  final Map<String, String> names;

  static Future<PlayerSummarySource> load(
    Person person,
    PlayerProfileData data, {
    SqlService? sql,
  }) async {
    final db = sql ?? SqlService.instance;
    final seasonIds = {for (final m in data.matches) m.seasonId}..remove('');
    final [fixtures, goals] = await Future.wait([
      db.getSummaryFixtures(person.id, seasonIds.toList()),
      db.getSummaryGoalRows(person.id, seasonIds.toList()),
    ]);
    final players = await db.getCustomPlayers(
      person.id,
      playerIds: {
        for (final row in goals) row['playerInstanceId'] as String,
        for (final m in data.matches) ...[
          for (final g in m.performance.goalDetails) ?g.assistantId,
          for (final a in m.performance.assistDetails) ?a.goalscorerId,
        ],
      },
      includeCurrentOverall: false,
    );
    final teamGoals = <String, List<PerformanceGoalDetails>>{};
    for (final row in goals) {
      (teamGoals[row['fixtureId'].toString()] ??= []).addAll(_goals(row));
    }
    return PlayerSummarySource(
      fixtures: fixtures,
      teamGoals: teamGoals,
      names: {
        for (final row in players)
          row['id'].toString(): row['name']?.toString() ?? '',
      },
    );
  }

  static List<PerformanceGoalDetails> _goals(Map<String, Object?> row) {
    final raw = row['goalDetails'];
    if (raw == null) {
      final count = (row['goalsCount'] as num?)?.toInt() ?? 0;
      return List.generate(count, (_) => PerformanceGoalDetails());
    }
    final decoded = raw is String ? jsonDecode(raw) : raw;
    return [
      if (decoded is List)
        for (final item in decoded)
          if (item is Map)
            PerformanceGoalDetails.fromMap(Map<String, dynamic>.from(item)),
    ];
  }
}

class TeamRecord {
  int games = 0, wins = 0, draws = 0, losses = 0;
  int goalsFor = 0, goalsAgainst = 0;

  void add(Map<String, Object?> fixture) {
    games++;
    switch (fixtureResult(fixture)) {
      case FixtureResult.win:
        wins++;
      case FixtureResult.draw:
        draws++;
      case FixtureResult.lose:
        losses++;
    }
    goalsFor += _int(fixture['playerTeamScore']);
    goalsAgainst += _int(fixture['oppositeTeamScore']);
  }

  double? get pointsShare =>
      games == 0 ? null : (wins * 3 + draws) * 100 / (games * 3);
  double? perGame(int value) => games == 0 ? null : value / games;
}

class DecisiveMatch {
  const DecisiveMatch(this.match, this.points, {required this.won});
  final PlayerMatchData match;

  final int points;

  final bool won;
}

const summaryMinuteBands = [
  '1–15',
  '16–30',
  '31–45+',
  '46–60',
  '61–75',
  '76–90+',
  'Prorr.',
];

const summaryRatingBands = [
  'Abaixo de 6',
  '6 a 6,9',
  '7 a 7,9',
  '8 a 8,9',
  '9 ou mais',
];

int _int(Object? value) => value is num ? value.toInt() : 0;

class PlayerSummary {
  PlayerSummary({
    required List<PlayerMatchData> allMatches,
    required this.source,
    this.seasonId,
  }) {
    matches =
        allMatches
            .where((m) => seasonId == null || m.seasonId == seasonId)
            .toList()
          ..sort(
            (a, b) => (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0)),
          );
    totals = PlayerTotals(matches);
    _ratings();
    _minutes();
    _team();
    _decisive();
    _partners();
    _breakdowns();
  }

  final PlayerSummarySource source;
  final String? seasonId;

  late final List<PlayerMatchData> matches;
  late final PlayerTotals totals;

  int get contributions => totals.goals + totals.assists;
  double? get minutesPerContribution =>
      contributions == 0 ? null : totals.minutes / contributions;

  final ratingBands = List.filled(summaryRatingBands.length, 0);

  void _ratings() {
    for (final match in matches) {
      final rating = match.performance.avgRating;
      if (rating == null) continue;
      final band = rating < 6
          ? 0
          : rating < 7
          ? 1
          : rating < 8
          ? 2
          : rating < 9
          ? 3
          : 4;
      ratingBands[band]++;
    }
  }

  List<PlayerMatchData> get recentForm => matches
      .where((m) => m.performance.avgRating != null)
      .toList()
      .reversed
      .take(10)
      .toList()
      .reversed
      .toList();

  final goalsByBand = List.filled(summaryMinuteBands.length, 0);
  final assistsByBand = List.filled(summaryMinuteBands.length, 0);
  int goalsWithoutMinute = 0, assistsWithoutMinute = 0;

  static int? band(int? minute) {
    if (minute == null) return null;
    if (minute <= 15) return 0;
    if (minute <= 30) return 1;
    if (minute <= 45) return 2;
    if (minute <= 60) return 3;
    if (minute <= 75) return 4;
    if (minute <= 90) return 5;
    return 6;
  }

  void _minutes() {
    for (final match in matches) {
      for (final goal in match.performance.goalDetails) {
        final index = band(goal.minute);
        if (index == null) {
          goalsWithoutMinute++;
        } else {
          goalsByBand[index]++;
        }
      }
      for (final assist in match.performance.assistDetails) {
        final index = band(assist.minute);
        if (index == null) {
          assistsWithoutMinute++;
        } else {
          assistsByBand[index]++;
        }
      }
    }
  }

  final withHim = TeamRecord(), withoutHim = TeamRecord();

  int minutesOn = 0, minutesOff = 0;
  int forOn = 0, againstOn = 0, forOff = 0, againstOff = 0;

  int unassignedGoals = 0;

  double? per90(int goals, int minutes) =>
      minutes == 0 ? null : goals * 90 / minutes;

  void _team() {
    final mine = {for (final m in matches) m.fixtureId: m};
    final teams = <String, Set<String>>{};
    for (final m in matches) {
      final team = m.row['playerTeamId']?.toString();
      if (team != null) (teams[m.seasonId] ??= {}).add(team);
    }
    for (final fixture in source.fixtures) {
      final season = fixture['seasonId']?.toString() ?? '';
      if (seasonId != null && season != seasonId) continue;
      final id = fixture['id'].toString();
      final played = mine[id];
      if (played == null &&
          !(teams[season]?.contains(fixture['playerTeamId']) ?? false)) {
        continue;
      }
      (played == null ? withoutHim : withHim).add(fixture);
      _onOff(fixture, played);
    }
  }

  void _onOff(Map<String, Object?> fixture, PlayerMatchData? played) {
    final opponentGoals = decodeOpponentGoals(fixture['opponentGoalDetails']);
    final duration = math.max(
      played?.performance.recordedMinutes ?? 0,
      getManagerFixtureDurationMinutes(
        extraTime: fixture['extraTime'] == 1,
        opponentGoalMinutes: opponentGoals.map((g) => g.minute),
        performance: played?.performance,
      ),
    );
    var start = 0, end = 0;
    final recorded = played?.performance.recordedMinutes;
    final unknownInterval =
        recorded != null &&
        recorded > 0 &&
        recorded < duration &&
        !played!.performance.substitutionDetails.any((s) => s.minute != null);
    if (played != null) {
      int? first(Iterable<PerformanceTimeDetails> items) => items
          .map((i) => i.minute)
          .whereType<int>()
          .fold<int?>(null, (a, b) => a == null ? b : math.min(a, b));
      final subs = played.performance.substitutionDetails;
      start = (first(subs.where((s) => s.type == SubstitutionType.inGame)) ?? 0)
          .clamp(0, duration);
      final out = [
        first(subs.where((s) => s.type == SubstitutionType.outGame)),
        first(played.performance.redCardDetails),
      ].whereType<int>();
      end = (out.isEmpty ? duration : out.reduce(math.min)).clamp(
        start,
        duration,
      );
    }
    final onMinutes = recorded ?? end - start;
    minutesOn += onMinutes;
    minutesOff += duration - onMinutes;
    final whole = played != null && onMinutes >= duration;
    void add(int goals, {required bool on, required bool scored}) {
      if (scored && on) {
        forOn += goals;
      } else if (scored) {
        forOff += goals;
      } else if (on) {
        againstOn += goals;
      } else {
        againstOff += goals;
      }
    }

    void count(Iterable<int?> minutes, int total, {required bool scored}) {
      var known = 0;
      for (final minute in minutes.whereType<int>()) {
        known++;
        if (unknownInterval) {
          unassignedGoals++;
          continue;
        }
        add(
          1,
          on: played != null && minute >= start && minute <= end,
          scored: scored,
        );
      }
      final unknown = math.max(0, total - known);
      if (unknown == 0) return;
      if (played == null || whole) {
        add(unknown, on: whole, scored: scored);
      } else {
        unassignedGoals += unknown;
      }
    }

    count(
      (source.teamGoals[fixture['id'].toString()] ?? const []).map(
        (g) => g.minute,
      ),
      _int(fixture['playerTeamScore']),
      scored: true,
    );
    count(
      opponentGoals.map((g) => g.minute),
      _int(fixture['oppositeTeamScore']),
      scored: false,
    );
  }

  final decisive = <DecisiveMatch>[];

  int get decidedMatches => decisive.length;
  int get pointsSecured => decisive.fold(0, (sum, d) => sum + d.points);
  int get winsSecured => decisive.where((d) => d.won).length;
  int get drawsSaved => decisive.where((d) => !d.won).length;

  static int _points(int us, int them) => us > them
      ? 3
      : us == them
      ? 1
      : 0;

  void _decisive() {
    for (final match in matches) {
      final us = _int(match.row['playerTeamScore']);
      final them = _int(match.row['oppositeTeamScore']);
      final actual = _points(us, them);
      final without = _points(
        math.max(0, us - match.goals - match.assists),
        them,
      );
      if (actual > without) {
        decisive.add(DecisiveMatch(match, actual - without, won: actual == 3));
      }
    }
  }

  late final List<(String, int)> assistedBy, assistedTo;

  void _partners() {
    List<(String, int)> rank(Iterable<(String?, String?)> people) {
      final counts = <String, int>{};
      final labels = <String, String>{};
      for (final (id, name) in people) {
        final key = id ?? name;
        if (key == null || key.isEmpty) continue;
        counts[key] = (counts[key] ?? 0) + 1;
        labels[key] = source.names[id] ?? name ?? key;
      }
      final ranked = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return [for (final e in ranked.take(5)) (labels[e.key]!, e.value)];
    }

    assistedBy = rank([
      for (final m in matches)
        for (final g in m.performance.goalDetails)
          (g.assistantId, g.assistantName),
    ]);
    assistedTo = rank([
      for (final m in matches)
        for (final a in m.performance.assistDetails)
          (a.goalscorerId, a.goalscorerName),
    ]);
  }

  late final List<(GoalType, int)> goalTypes;

  late final List<(String, int, int, int)> competitions;

  late final List<(String, int, int, int, double?)> seasons;

  void _breakdowns() {
    final types = <GoalType, int>{};
    for (final m in matches) {
      for (final g in m.performance.goalDetails) {
        for (final type in g.type.toSet()) {
          types[type] = (types[type] ?? 0) + 1;
        }
      }
    }
    goalTypes = types.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));

    final byCompetition = <String, List<PlayerMatchData>>{};
    final bySeason = <String, List<PlayerMatchData>>{};
    for (final m in matches) {
      (byCompetition[m.tournamentId] ??= []).add(m);
      (bySeason[m.seasonId] ??= []).add(m);
    }
    competitions = [
      for (final MapEntry(:key, :value) in byCompetition.entries)
        (
          key,
          value.length,
          value.fold(0, (s, m) => s + m.goals),
          value.fold(0, (s, m) => s + m.assists),
        ),
    ]..sort((a, b) => (b.$3 + b.$4).compareTo(a.$3 + a.$4));
    seasons = [
      for (final MapEntry(:key, :value) in bySeason.entries)
        (
          key,
          value.length,
          value.fold(0, (s, m) => s + m.goals),
          value.fold(0, (s, m) => s + m.assists),
          PlayerTotals(value).rating,
        ),
    ];
  }
}
