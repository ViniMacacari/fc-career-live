import 'dart:convert';

import '../ManagerCareer/Graphics/TeamAnalyticsData.dart';
import 'Season.dart';

const standingStats = <String, String>{
  'points': 'PTS',
  'matchesPlayed': 'J',
  'wins': 'V',
  'draws': 'E',
  'loses': 'D',
  'goalsFor': 'GP',
  'goalsAgainst': 'GC',
};

class SeasonStanding {
  const SeasonStanding({
    required this.teamId,
    required this.name,
    required this.position,
    this.leagueId,
    this.stats = const {},
  });
  final String teamId, name;
  final String? leagueId;
  final int position;
  final Map<String, int?> stats;
  int? get balance => stats['goalsFor'] == null || stats['goalsAgainst'] == null
      ? null
      : stats['goalsFor']! - stats['goalsAgainst']!;
  Map<String, Object?> toJson() => {
    'teamId': teamId,
    'name': name,
    'position': position,
    'leagueId': leagueId,
    'stats': stats,
  };
  factory SeasonStanding.fromJson(Map<String, dynamic> json) => SeasonStanding(
    teamId: '${json['teamId']}',
    name: '${json['name']}',
    position: (json['position'] as num).toInt(),
    leagueId: json['leagueId'] as String?,
    stats: {
      for (final e in (json['stats'] as Map).entries)
        '${e.key}': (e.value as num?)?.toInt(),
    },
  );
  factory SeasonStanding.fromRow(Map<String, Object?> row, String name) {
    final known = row['knownStats'] == null
        ? standingStats.keys.toSet()
        : (jsonDecode(row['knownStats'] as String) as List)
              .cast<String>()
              .toSet();
    return SeasonStanding(
      teamId: '${row['teamId']}',
      name: name,
      position: (row['position'] as num).toInt(),
      leagueId: row['leagueId'] as String?,
      stats: {
        for (final key in standingStats.keys)
          key: known.contains(key) ? (row[key] as num?)?.toInt() : null,
      },
    );
  }
}

class SeasonFinalTable {
  const SeasonFinalTable({
    required this.id,
    required this.tournamentId,
    required this.name,
    required this.rows,
    this.closedAt,
    this.ownTeamId,
  });
  final String id, tournamentId, name;
  final String? ownTeamId;
  final List<SeasonStanding> rows;
  final DateTime? closedAt;
  bool get isClosed => closedAt != null;
  void validate() {
    if (rows.isEmpty) {
      throw const FormatException('Adicione pelo menos seu time à tabela.');
    }
    final teams = <String>{}, positions = <int>{};
    for (final row in rows) {
      if (row.position < 1 || !positions.add(row.position)) {
        throw const FormatException(
          'Cada clube precisa ter uma posição positiva e diferente.',
        );
      }
      if (row.teamId.isEmpty || !teams.add(row.teamId)) {
        throw const FormatException(
          'Um clube não pode aparecer duas vezes na tabela.',
        );
      }
      if (row.stats.values.any((v) => v != null && v < 0)) {
        throw const FormatException('As estatísticas não podem ser negativas.');
      }
      final s = row.stats;
      if ([
            'matchesPlayed',
            'wins',
            'draws',
            'loses',
          ].every((k) => s[k] != null) &&
          s['matchesPlayed'] != s['wins']! + s['draws']! + s['loses']!) {
        throw FormatException('Em ${row.name}, J deve ser igual a V + E + D.');
      }
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'tournamentId': tournamentId,
    'name': name,
    'ownTeamId': ownTeamId,
    'closedAt': closedAt?.toIso8601String(),
    'rows': rows.map((r) => r.toJson()).toList(),
  };
  factory SeasonFinalTable.fromJson(Map<String, dynamic> json) =>
      SeasonFinalTable(
        id: '${json['id']}',
        tournamentId: '${json['tournamentId']}',
        name: '${json['name']}',
        ownTeamId: json['ownTeamId'] as String?,
        closedAt: DateTime.tryParse('${json['closedAt']}'),
        rows: (json['rows'] as List)
            .map(
              (r) =>
                  SeasonStanding.fromJson(Map<String, dynamic>.from(r as Map)),
            )
            .toList(),
      );
}

class SeasonReview {
  const SeasonReview({
    required this.season,
    required this.savedAt,
    required this.fixtures,
    required this.players,
    required this.competitions,
    required this.tables,
    required this.events,
    required this.teamNames,
    required this.careerName,
    required this.teamId,
  });
  final Season season;
  final DateTime savedAt;
  final String careerName, teamId;
  final List<AnalyticsRow> fixtures, players, competitions, events;
  final List<SeasonFinalTable> tables;
  final Map<String, String> teamNames;
  String get label => season.startDate.year == season.endDate.year
      ? '${season.startDate.year}'
      : '${season.startDate.year}/${season.endDate.year}';
  TeamAnalytics get analytics => TeamAnalytics.fromRows(fixtures);
  SeasonFinalTable draftTable(String tournamentId, {String? name}) {
    final comp = competitions.where((c) => c['id'] == tournamentId).firstOrNull;
    final matches = fixtures
        .where((f) => f['tournamentId'] == tournamentId)
        .toList();
    final own = matches.lastOrNull?['playerTeamId']?.toString() ?? teamId;
    final recordedPositions = matches
        .map((m) => (m['position'] as num?)?.toInt())
        .whereType<int>()
        .where((p) => p > 0);
    return SeasonFinalTable(
      id: '',
      tournamentId: tournamentId,
      name: name ?? '${comp?['name'] ?? tournamentId}',
      ownTeamId: own,
      rows: [
        SeasonStanding(
          teamId: own,
          name: teamName(own),
          leagueId: matches.lastOrNull?['playerTeamLeagueId'] as String?,
          position:
              recordedPositions.lastOrNull ??
              (comp?['position'] as num?)?.toInt() ??
              0,
          stats: const {},
        ),
      ],
    );
  }

  int get titles => competitions.where((c) => c['won'] == true).length;
  String teamName(Object? id) => id == null || '$id'.isEmpty
      ? 'Clube não informado'
      : teamNames['$id'] ?? '$id';
  AnalyticsRow? get bestWin => _extreme(true);
  AnalyticsRow? get worstLoss => _extreme(false);
  AnalyticsRow? _extreme(bool best) {
    final matches =
        analytics.matches
            .where((m) => best ? m.points == 3 : m.points == 0)
            .toList()
          ..sort((a, b) {
            final d = (b.scored - b.conceded).compareTo(a.scored - a.conceded);
            return best ? d : -d;
          });
    return matches.firstOrNull?.row;
  }

  int get longestWinning {
    var streak = 0, best = 0;
    for (final m in analytics.matches) {
      streak = m.points == 3 ? streak + 1 : 0;
      if (streak > best) best = streak;
    }
    return best;
  }

  List<AnalyticsRow> leaders(String metric) => [...players]
    ..sort(
      (a, b) =>
          ((b[metric] as num?) ?? -1).compareTo((a[metric] as num?) ?? -1),
    );
  String encode() => jsonEncode({
    'schema': 1,
    'season': {...season.toMap(), 'recapJson': null},
    'savedAt': savedAt.toIso8601String(),
    'careerName': careerName,
    'teamId': teamId,
    'fixtures': fixtures,
    'players': players,
    'competitions': competitions,
    'tables': tables.map((t) => t.toJson()).toList(),
    'events': events,
    'teamNames': teamNames,
  });
  factory SeasonReview.decode(String source) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    List<AnalyticsRow> rows(String key) => (j[key] as List)
        .map((r) => Map<String, Object?>.from(r as Map))
        .toList();
    return SeasonReview(
      season: Season.fromMap(Map<String, Object?>.from(j['season'] as Map)),
      savedAt: DateTime.parse(j['savedAt'] as String),
      careerName: '${j['careerName']}',
      teamId: '${j['teamId']}',
      fixtures: rows('fixtures'),
      players: rows('players'),
      competitions: rows('competitions'),
      events: rows('events'),
      teamNames: Map<String, String>.from(j['teamNames'] as Map),
      tables: (j['tables'] as List)
          .map(
            (t) =>
                SeasonFinalTable.fromJson(Map<String, dynamic>.from(t as Map)),
          )
          .toList(),
    );
  }
}
