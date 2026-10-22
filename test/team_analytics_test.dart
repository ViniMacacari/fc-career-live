import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/Graphics/TeamAnalyticsData.dart';

AnalyticsRow fixture(
  String id,
  String date,
  int scored,
  int conceded, {
  String season = 's1',
  String club = 'club',
  String competition = 'league',
  String location = 'home',
  double? possession,
}) => {
  'id': id,
  'date': date,
  'playerTeamScore': scored,
  'oppositeTeamScore': conceded,
  'seasonId': season,
  'playerTeamId': club,
  'tournamentId': competition,
  'location': location,
  'teamPossession': possession,
};

void main() {
  final rows = [
    fixture('b', '2026-01-10T20:00:00', 1, 1, possession: 60),
    fixture('a', '2026-01-01T15:00:00', 3, 0, possession: 50),
    fixture('c', '2026-02-01T23:59:00', 0, 2, season: 's2', location: 'away'),
    fixture(
      'd',
      '2026-02-03T15:00:00',
      2,
      0,
      season: 's2',
      club: 'other',
      competition: 'cup',
    ),
  ];
  test('chronological totals, rates, streaks and clean sheets', () {
    final data = TeamAnalytics.fromRows(rows);
    expect(data.matches.map((m) => m.id), ['a', 'b', 'c', 'd']);
    expect((data.wins, data.draws, data.losses), (2, 1, 1));
    expect((data.goalsFor, data.goalsAgainst, data.balance), (6, 3, 3));
    expect(data.efficiency, closeTo(7 / 12 * 100, .001));
    expect(data.longestUnbeaten, 2);
    expect(data.cleanSheets, 2);
  });
  test('filters intersect and include the last day regardless of time', () {
    final data = TeamAnalytics.fromRows(
      rows,
      filter: AnalyticsFilter(
        seasonId: 's2',
        teamId: 'club',
        competitionId: 'league',
        location: 'away',
        from: DateTime(2026, 2, 1),
        to: DateTime(2026, 2, 1),
      ),
    );
    expect(data.matches.single.id, 'c');
    expect(data.efficiency, 0);
    final excluded = TeamAnalytics.fromRows(
      rows,
      filter: const AnalyticsFilter(teamId: 'none'),
    );
    expect(excluded.played, 0);
    expect(excluded.efficiency, 0);
    expect(excluded.scoredPerGame, 0);
  });
  test('missing stats remain absent and real zeros count as observations', () {
    final data = TeamAnalytics.fromRows([
      ...rows,
      fixture('e', '2026-03-01', 0, 0, possession: 0),
    ]);
    expect(data.samples((m) => m.possession), 3);
    expect(data.mean((m) => m.possession), closeTo(110 / 3, .001));
    expect(data.evolution(AnalyticsMetric.possession).map((p) => p.value), [
      50,
      60,
      null,
      null,
      0,
    ]);
    expect(data.mean((m) => m.accuracy), isNull);
  });
  test(
    'monthly and season groups keep counts and rolling means use the recorte',
    () {
      final data = TeamAnalytics.fromRows(rows);
      expect(data.months.map((k, v) => MapEntry(k, v.played)), {
        '2026-01': 2,
        '2026-02': 2,
      });
      expect(data.seasons.map((k, v) => MapEntry(k, v.played)), {
        's1': 2,
        's2': 2,
      });
      expect(data.evolution(AnalyticsMetric.balance).map((p) => p.value), [
        3,
        3,
        1,
        3,
      ]);
      final filtered = TeamAnalytics.fromRows(
        rows,
        filter: const AnalyticsFilter(seasonId: 's2'),
      );
      expect(filtered.evolution(AnalyticsMetric.goals).first.value, 0);
      expect(filtered.evolution(AnalyticsMetric.form).last.value, 50);
    },
  );
  test('rolling five-game form compares independent adjacent windows', () {
    final data = TeamAnalytics.fromRows([
      for (var i = 0; i < 10; i++)
        fixture(
          '$i',
          DateTime(2026, 1, i + 1).toIso8601String(),
          i < 5 ? 0 : 2,
          1,
        ),
    ]);
    expect(data.formChange, 100);
    expect(data.evolution(AnalyticsMetric.form).last.value, 100);
    expect(data.recent.played, 5);
  });
}
