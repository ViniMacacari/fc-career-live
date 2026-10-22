import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../utils/BackgroundData.dart';
import '../../utils/InjuryStatus.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/SqlService.dart';
import '../PlayersStat/PlayersStatData.dart';
import '../PlayersStat/RecordedPlayerStats.dart';
import '../TeamPage/ViewPlayer/PlayerProfileData.dart';

class TeamCenterData {
  const TeamCenterData({
    required this.season,
    required this.date,
    required this.roster,
    required this.academy,
    required this.injuries,
    required this.fixtures,
    required this.catalog,
    required this.statistics,
  });
  final Season? season;
  final DateTime? date;
  final List<Map<String, Object?>> roster, academy, injuries, fixtures;
  final GameCatalog catalog;
  final PlayersStatData statistics;
  int get injuredPlayers => injuries.map((i) => i['playerId']).toSet().length;
  int get available => roster.length - injuredPlayers;
  int get starters => roster.where((p) => p['isBench'] == 0).length;
  double? get averageOverall {
    final values = roster.map((p) => p['overall']).whereType<num>().toList();
    return values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;
  }

  List<PlayersStatEntry> leaders(Person person, PlayersStatMetric metric) {
    final filtered = PlayersStatFilters(
      seasonId: season?.id,
      teamId: person.teamId,
    );
    final entries = statistics
        .entries(person, filtered, const PlayersStatSort())
        .where((p) => !p.departed)
        .toList();
    final totals = {
      for (final e in entries)
        e.id: RecordedPlayerStats(statistics.activity(e.id, filtered)),
    };
    entries.removeWhere(
      (e) => totals[e.id]![metric] == null || totals[e.id]![metric]! <= 0,
    );
    entries.sort(
      (a, b) => totals[b.id]![metric]!.compareTo(totals[a.id]![metric]!),
    );
    return entries;
  }

  static List<PlayerMatchData> _matches(List<Map<String, Object?>> rows) {
    final unique = <String, Map<String, Object?>>{};
    for (final row in rows) {
      unique.putIfAbsent(
        '${row['fixtureId']}:${row['playerInstanceId']}',
        () => row,
      );
    }
    return unique.values.map(PlayerMatchData.new).toList();
  }

  static Future<TeamCenterData> load(Person person, {SqlService? sql}) async {
    final service = sql ?? SqlService.instance;
    final catalog = await GameCatalog.load();
    final seasons = await service.getSeasons(person.id);
    final season = seasons.firstOrNull;
    final date = await service.getCareerDate(person.id);
    await service.syncMatchInjuries(person.id);
    final results = await Future.wait<Object>([
      if (season != null)
        service.getTeamPlayers(person.id, season.id)
      else
        Future.value(<Map<String, Object?>>[]),
      service.getAcademyPlayers(person.id),
      service.getInjuries(person.id),
      if (season != null)
        service.getFixtures(
          person.id,
          PersonCategory.manager,
          seasonId: season.id,
        )
      else
        Future.value(<Map<String, Object?>>[]),
      if (season != null)
        service.getManagerStatisticsMatchRows(person.id, seasonId: season.id)
      else
        Future.value(<Map<String, Object?>>[]),
    ]);
    final roster = (results[0] as List<Map<String, Object?>>)
        .where((p) => p['playerId'] != null)
        .toList();
    final rosterIds = roster.map((p) => p['playerId']).toSet();
    final injuries =
        (results[2] as List<Map<String, Object?>>)
            .where(
              (i) =>
                  date != null &&
                  rosterIds.contains(i['playerId']) &&
                  i['teamId'] == person.teamId &&
                  isActiveInjury(i, date),
            )
            .toList()
          ..sort((a, b) => '${b['startDate']}'.compareTo('${a['startDate']}'));
    final matchRows = (results[4] as List<Map<String, Object?>>)
        .where((m) => m['playerTeamId'] == person.teamId)
        .toList();
    final players = await service.getCustomPlayers(
      person.id,
      playerIds: {
        for (final row in roster) '${row['playerId']}',
        for (final row in matchRows) '${row['playerInstanceId']}',
      },
    );
    final names = {
      for (final t in await catalog.tournaments(person.fifaVersion))
        t.id: t.label,
      for (final l in catalog.leagues(person.fifaVersion))
        'league:${l.id}': l.label,
      for (final t in await service.getCustomTournaments(person.fifaVersion))
        t.id: t.name,
    };
    return TeamCenterData(
      season: season,
      date: date,
      roster: roster,
      academy: (results[1] as List<Map<String, Object?>>)
          .where((p) => p['isHistorical'] != 1 && p['teamId'] == person.teamId)
          .toList(),
      injuries: injuries,
      fixtures: (results[3] as List<Map<String, Object?>>)
          .where((f) => f['playerTeamId'] == person.teamId)
          .toList(),
      catalog: catalog,
      statistics: PlayersStatData(
        seasons: seasons,
        players: {for (final p in players) '${p['id']}': p},
        matches: await BackgroundData.run(
          _matches,
          matchRows,
          label: 'squad activity',
          background: matchRows.length >= 128,
        ),
        roster: roster,
        transfers: const [],
        catalog: catalog,
        tournamentNames: names,
        realPlayers: const {},
        careerDate: date,
      ),
    );
  }
}
