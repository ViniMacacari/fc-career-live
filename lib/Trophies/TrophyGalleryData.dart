import '../Common/FixtureResultTile.dart';
import '../models/ManagerFixturePlayerPerformance.dart';
import '../models/Person.dart';
import '../utils/CompetitionTrophies.dart';
import '../utils/GameCatalog.dart';
import '../utils/SqlService.dart';
import '../utils/Components/SelectionSearchField.dart';
import '../utils/competitions/CompetitionFormats.dart';

class TrophyEdition {
  const TrophyEdition(this.row, this.competitionId, this.year);
  final Map<String, Object?> row;
  final String? competitionId;
  final String year;
  int get count => (row['count'] as num?)?.toInt() ?? 1;
}

class TrophyCompetitionGroup {
  TrophyCompetitionGroup(this.id, this.name, this.picture);
  final String id, name;
  final AwardCatalogItem? picture;
  final editions = <TrophyEdition>[];
  int get count => editions.fold(0, (n, e) => n + e.count);
}

class TrophyGalleryData {
  const TrophyGalleryData(this.catalog, this.groups, this.names);
  final GameCatalog catalog;
  final List<TrophyCompetitionGroup> groups;
  final Map<String, String> names;
  int get count => groups.fold(0, (n, g) => n + g.count);

  static Future<TrophyGalleryData> load(
    Person person, {
    SqlService? sql,
  }) async {
    final service = sql ?? SqlService.instance;
    final catalog = await GameCatalog.load();
    final rows = await service.getTrophies(person.id);
    final seasons = {
      for (final s in await service.getSeasons(person.id)) s.id: s,
    };
    final awards = {for (final a in await catalog.awards()) a.id: a};
    final custom = await service.getCustomTournaments(person.fifaVersion);
    final names = <String, String>{
      for (final t in await catalog.tournaments(person.fifaVersion))
        t.id: t.label,
      for (final l in catalog.leagues(person.fifaVersion))
        'league:${l.id}': l.label,
      for (final t in custom) t.id: t.name,
    };
    final db = await service.database;
    final fixtures = {
      for (final f in await db.query(
        person.category == PersonCategory.manager
            ? 'ManagerFixtures'
            : 'PlayerFixtures',
        columns: ['id', 'tournamentId', 'seasonId', 'playerTeamId'],
        where: 'personId = ?',
        whereArgs: [person.id],
      ))
        '${f['id']}': f,
    };
    final linked = {
      for (final t in await CompetitionTrophies.all(database: db))
        if (t.version == person.fifaVersion) t.competitionId: t.awardId,
    };
    final awardCompetitions = <String, List<String>>{};
    for (final id in {
      ...names.keys,
      ...fixtures.values.map((f) => '${f['tournamentId']}'),
    }) {
      final award =
          linked[id] ??
          CompetitionFormat.of(
            id,
            person.fifaVersion,
            customFormat: custom.where((t) => t.id == id).firstOrNull?.format,
          ).awardId;
      if (award != null) (awardCompetitions[award] ??= []).add(id);
    }
    final grouped = <String, TrophyCompetitionGroup>{};
    for (final row in rows) {
      final awardId = '${row['awardId']}';
      final prefix = 'auto:${row['seasonId']}:';
      final trophyPrefix = 'competition:${person.fifaVersion}:';
      String? competition = '${row['id']}'.startsWith(prefix)
          ? '${row['id']}'.substring(prefix.length)
          : awardId.startsWith(trophyPrefix)
          ? awardId.substring(trophyPrefix.length)
          : fixtures[row['fixtureId']]?['tournamentId']?.toString();
      final description = row['description']?.toString().trim() ?? '';
      if (competition == null && awardId == '-1' && description.isNotEmpty) {
        final candidates = names.entries
            .where(
              (e) =>
                  selectionSearchKey(e.value) ==
                  selectionSearchKey(description),
            )
            .toList();
        if (candidates.length == 1) competition = candidates.single.key;
      }
      if (competition == null) {
        final candidates = awardCompetitions[awardId] ?? [];
        final played = candidates
            .where(
              (id) => fixtures.values.any(
                (f) =>
                    f['seasonId'] == row['seasonId'] &&
                    f['tournamentId'] == id &&
                    f['playerTeamId'] == row['teamId'],
              ),
            )
            .toList();
        if (played.length == 1) {
          competition = played.single;
        } else if (candidates.length == 1) {
          competition = candidates.single;
        }
      }
      final name =
          names[competition] ??
          (awardId == '-1' && description.isNotEmpty
              ? description
              : awards[awardId]?.label ?? 'Troféu');
      final key =
          competition ??
          'award:$awardId:${awardId == '-1' ? selectionSearchKey(description) : ''}';
      final season = seasons[row['seasonId']];
      final date = DateTime.tryParse('${row['date']}');
      final year = season != null
          ? season.startDate.year == season.endDate.year
                ? '${season.startDate.year}'
                : '${season.startDate.year}/${season.endDate.year}'
          : date == null
          ? 'Ano não informado'
          : '${date.year}';
      (grouped.putIfAbsent(
        key,
        () => TrophyCompetitionGroup(key, name, awards[awardId]),
      )).editions.add(TrophyEdition(row, competition, year));
    }
    final groups = grouped.values.toList()
      ..sort(
        (a, b) => b.count.compareTo(a.count) != 0
            ? b.count.compareTo(a.count)
            : a.name.compareTo(b.name),
      );
    for (final group in groups) {
      group.editions.sort((a, b) => b.year.compareTo(a.year));
    }
    return TrophyGalleryData(catalog, groups, names);
  }
}

class TrophyContributor {
  TrophyContributor(this.player);
  final Map<String, Object?> player;
  int goals = 0, assists = 0, games = 0, ratings = 0;
  double ratingSum = 0;
  double? get rating => ratings == 0 ? null : ratingSum / ratings;
}

class TrophyCampaignData {
  const TrophyCampaignData(
    this.fixtures,
    this.contributors,
    this.catalog, {
    this.linked = true,
  });
  final List<Map<String, Object?>> fixtures;
  final List<TrophyContributor> contributors;
  final GameCatalog catalog;
  final bool linked;
  int resultCount(FixtureResult result) =>
      fixtures.where((f) => fixtureResult(f) == result).length;
  int sum(String field) =>
      fixtures.fold(0, (n, f) => n + ((f[field] as num?)?.toInt() ?? 0));
  List<TrophyContributor> get scorers =>
      contributors.where((p) => p.goals > 0).toList()
        ..sort((a, b) => b.goals.compareTo(a.goals));
  List<TrophyContributor> get assistants =>
      contributors.where((p) => p.assists > 0).toList()
        ..sort((a, b) => b.assists.compareTo(a.assists));

  static Future<TrophyCampaignData> load(
    Person person,
    Map<String, Object?> trophy,
    String? competitionId, {
    SqlService? sql,
  }) async {
    final catalog = await GameCatalog.load();
    if (competitionId == null) {
      return TrophyCampaignData([], [], catalog, linked: false);
    }
    final service = sql ?? SqlService.instance,
        db = await (sql ?? SqlService.instance).database;
    final table = person.category == PersonCategory.manager
        ? 'ManagerFixtures'
        : 'PlayerFixtures';
    final all = await db.query(
      table,
      where: 'personId = ? AND seasonId = ? AND tournamentId = ? AND playerTeamId = ?',
      whereArgs: [
        person.id,
        trophy['seasonId'],
        competitionId,
        trophy['teamId'],
      ],
      orderBy: 'julianday(date), rowid',
    );
    final decisive = all
        .where((f) => f['id'] == trophy['fixtureId'])
        .firstOrNull;
    final until = DateTime.tryParse('${decisive?['date'] ?? trophy['date']}');
    final fixtures = <Map<String, Object?>>[];
    for (final f in all) {
      final date = DateTime.tryParse('${f['date']}');
      if (until == null || (date != null && !date.isAfter(until))) {
        fixtures.add(f);
      }
      if (decisive != null && f['id'] == decisive['id']) break;
    }
    final contributors = <TrophyContributor>[];
    if (person.category == PersonCategory.manager && fixtures.isNotEmpty) {
      final rows = <Map<String, Object?>>[];
      for (var offset = 0; offset < fixtures.length; offset += 300) {
        final ids = fixtures
            .skip(offset)
            .take(300)
            .map((f) => f['id'])
            .toList();
        rows.addAll(
          await db.query(
            'ManagerFixturePlayerPerformances',
            where:
                'personId = ? AND fixtureId IN (${List.filled(ids.length, '?').join(',')})',
            whereArgs: [person.id, ...ids],
            orderBy: 'rowid DESC',
          ),
        );
      }
      final players = {
        for (final p in await service.getCustomPlayers(
          person.id,
          playerIds: rows.map((p) => '${p['playerInstanceId']}').toSet(),
          includeCurrentOverall: false,
        ))
          '${p['id']}': p,
      };
      final byPlayer = <String, TrophyContributor>{};
      final seen = <String>{};
      for (final row in rows) {
        if (!seen.add('${row['fixtureId']}:${row['playerInstanceId']}')) {
          continue;
        }
        final p = ManagerFixturePlayerPerformance.fromMap(row);
        final contributor = byPlayer.putIfAbsent(
          p.playerInstanceId,
          () => TrophyContributor(
            players[p.playerInstanceId] ??
                {'id': p.playerInstanceId, 'name': 'Jogador sem cadastro'},
          ),
        );
        contributor.games++;
        contributor.goals += p.goalsCount ?? p.goalDetails.length;
        contributor.assists += p.assistsCount ?? p.assistDetails.length;
        if (p.avgRating != null) {
          contributor.ratings++;
          contributor.ratingSum += p.avgRating!;
        }
      }
      contributors.addAll(byPlayer.values);
    } else if (person.category == PersonCategory.player &&
        fixtures.isNotEmpty) {
      final player = TrophyContributor({'name': person.name});
      for (final f in fixtures) {
        player.games++;
        player.goals += (f['goalsCount'] as num?)?.toInt() ?? 0;
        player.assists += (f['assistsCount'] as num?)?.toInt() ?? 0;
        if (f['rating'] is num) {
          player.ratings++;
          player.ratingSum += (f['rating'] as num).toDouble();
        }
      }
      contributors.add(player);
    }
    return TrophyCampaignData(fixtures, contributors, catalog);
  }
}
