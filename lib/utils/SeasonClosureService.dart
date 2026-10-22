import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/Person.dart';
import '../models/Season.dart';
import '../models/SeasonReview.dart';
import '../models/TournamentResult.dart';
import '../models/Trophy.dart';
import 'GameCatalog.dart';
import 'SqlService.dart';
import 'competitions/CompetitionFormats.dart';
import 'competitions/TournamentOutcomes.dart';

class SeasonReviewLabels {
  const SeasonReviewLabels({
    this.teams = const {},
    this.competitions = const {},
    this.formats = const {},
  });
  final Map<String, String> teams, competitions, formats;
  CompetitionFormat format(String id, String version) =>
      CompetitionFormat.of(id, version, customFormat: formats[id]);
  static Future<SeasonReviewLabels> load(
    Person person,
    DatabaseExecutor db,
  ) async {
    final catalog = await GameCatalog.load();
    final custom = await db.query('Tournament');
    return SeasonReviewLabels(
      teams: {for (final t in catalog.teams(person.fifaVersion)) t.id: t.label},
      competitions: {
        for (final t in await catalog.tournaments(person.fifaVersion))
          t.id: t.label,
        for (final l in catalog.leagues(person.fifaVersion))
          'league:${l.id}': l.label,
        for (final t in custom) '${t['id']}': '${t['name']}',
      },
      formats: {
        for (final t in custom)
          if (t['format'] is String) '${t['id']}': t['format'] as String,
      },
    );
  }
}

class SeasonClosureService {
  SeasonClosureService({Future<Database> Function()? database, this.labels})
    : _database = database ?? (() => SqlService.instance.database);
  final Future<Database> Function() _database;
  final SeasonReviewLabels? labels;

  Future<Season> _season(DatabaseExecutor db, Person person, String id) async {
    final rows = await db.query(
      'Seasons',
      where: 'id = ? AND personId = ?',
      whereArgs: [id, person.id],
    );
    if (rows.isEmpty) {
      throw StateError('Temporada não encontrada nesta carreira.');
    }
    return Season.fromMap(rows.single);
  }

  Future<SeasonReview> load(
    Person person,
    Season season, {
    bool live = false,
  }) async {
    final db = await _database();
    final existing = await _season(db, person, season.id);
    if (!live && existing.isClosed && existing.recapJson != null) {
      return SeasonReview.decode(existing.recapJson!);
    }
    final names = labels ?? await SeasonReviewLabels.load(person, db);
    return db.transaction((tx) async {
      final current = await _season(tx, person, season.id);
      if (!live && current.isClosed && current.recapJson != null) {
        return SeasonReview.decode(current.recapJson!);
      }
      return _capture(tx, person, current, names);
    });
  }

  Future<SeasonReview> close(
    Person person,
    Season season, {
    List<SeasonFinalTable> tables = const [],
  }) async {
    for (final t in tables) {
      t.validate();
    }
    final db = await _database();
    final names = labels ?? await SeasonReviewLabels.load(person, db);
    return db.transaction((tx) async {
      final current = await _season(tx, person, season.id);
      if (current.isClosed && current.recapJson != null) {
        return SeasonReview.decode(current.recapJson!);
      }
      for (final table in tables) {
        await _saveTable(tx, person, current, table, names);
      }
      final closed = Season(
        id: current.id,
        personId: person.id,
        startDate: current.startDate,
        endDate: current.endDate,
        createdAt: current.createdAt,
        closedAt: current.closedAt ?? DateTime.now(),
      );
      await _finalizeResults(tx, person, closed, names);
      final review = await _capture(tx, person, closed, names);
      await tx.update(
        'Seasons',
        {
          'closedAt': closed.closedAt!.toIso8601String(),
          'recapJson': review.encode(),
        },
        where: 'id = ? AND personId = ?',
        whereArgs: [season.id, person.id],
      );
      return review;
    });
  }

  Future<void> _finalizeResults(
    DatabaseExecutor db,
    Person person,
    Season season,
    SeasonReviewLabels names,
  ) async {
    final fixtures = await db.query(
      person.category == PersonCategory.manager
          ? 'ManagerFixtures'
          : 'PlayerFixtures',
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [person.id, season.id],
    );
    final results = await db.query(
      'TournamentResult',
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [person.id, season.id],
    );
    for (final o in TournamentOutcome.compute(
      fixtures,
      formatOf: (id) => names.format(id, person.fifaVersion),
      seasonOver: true,
    )) {
      if (!o.definitive ||
          results.any(
            (r) =>
                r['tournamentId'] == o.tournamentId &&
                !'${r['id']}'.startsWith('auto:'),
          )) {
        continue;
      }
      final id = 'season-close:${person.id}:${season.id}:${o.tournamentId}';
      final priorResult = results
          .where((r) => r['tournamentId'] == o.tournamentId)
          .firstOrNull;
      await db.insert(
        'TournamentResult',
        TournamentResult(
          id: id,
          personId: person.id,
          seasonId: season.id,
          fifaVersion: person.fifaVersion,
          tournamentId: o.tournamentId,
          result: o.resultText,
          youParticipatedIn: true,
          isWinner: o.won,
          playerOfTheTournamentId:
              priorResult?['playerOfTheTournamentId'] as String?,
          playerOfTheTournamentTeamId:
              priorResult?['playerOfTheTournamentTeamId'] as String?,
          playerOfTheTournamentLeagueId:
              priorResult?['playerOfTheTournamentLeagueId'] as String?,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final r in results.where(
        (r) => r['tournamentId'] == o.tournamentId,
      )) {
        await db.update(
          'TournamentResultTable',
          {'tournamentResultId': id},
          where: 'personId = ? AND seasonId = ? AND tournamentResultId = ?',
          whereArgs: [person.id, season.id, r['id']],
        );
      }
      if (!o.won) continue;
      final award = o.format.awardId ?? '-1';
      final name = names.competitions[o.tournamentId] ?? o.tournamentId;
      final trophies = await db.query(
        'Trophies',
        where: 'personId = ? AND seasonId = ? AND awardId = ?',
        whereArgs: [person.id, season.id, award],
      );
      if (trophies.any((t) => award != '-1' || t['description'] == name)) {
        continue;
      }
      final last = o.decisive ?? o.fixtures.last;
      await db.insert(
        'Trophies',
        Trophy(
          id: 'season-title:${person.id}:${season.id}:${o.tournamentId}',
          personId: person.id,
          seasonId: season.id,
          teamId: '${last['playerTeamId']}',
          leagueId: last['playerTeamLeagueId'] as String?,
          isNational: o.format.national,
          awardId: award,
          count: 1,
          date: DateTime.tryParse('${last['date']}'),
          description: award == '-1' ? name : null,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<SeasonReview> saveTable(
    Person person,
    Season season,
    SeasonFinalTable table,
  ) async {
    table.validate();
    final db = await _database();
    final names = labels ?? await SeasonReviewLabels.load(person, db);
    return db.transaction((tx) async {
      final current = await _season(tx, person, season.id);
      await _saveTable(tx, person, current, table, names);
      final review = await _capture(tx, person, current, names);
      if (current.isClosed) {
        await tx.update(
          'Seasons',
          {'recapJson': review.encode()},
          where: 'id = ? AND personId = ?',
          whereArgs: [season.id, person.id],
        );
      }
      return review;
    });
  }

  Future<SeasonReview> refresh(Person person, Season season) async {
    final db = await _database();
    final names = labels ?? await SeasonReviewLabels.load(person, db);
    return db.transaction((tx) async {
      final current = await _season(tx, person, season.id);
      final review = await _capture(tx, person, current, names);
      if (current.isClosed) {
        await tx.update(
          'Seasons',
          {'recapJson': review.encode()},
          where: 'id = ? AND personId = ?',
          whereArgs: [season.id, person.id],
        );
      }
      return review;
    });
  }

  Future<void> _saveTable(
    DatabaseExecutor db,
    Person person,
    Season season,
    SeasonFinalTable table,
    SeasonReviewLabels names,
  ) async {
    final fixtures = await db.query(
      person.category == PersonCategory.manager
          ? 'ManagerFixtures'
          : 'PlayerFixtures',
      where: 'personId = ? AND seasonId = ? AND tournamentId = ?',
      whereArgs: [person.id, season.id, table.tournamentId],
      orderBy: 'date ASC',
    );
    final ownTeam =
        table.ownTeamId ??
        fixtures.lastOrNull?['playerTeamId']?.toString() ??
        person.teamId;
    final own = table.rows.where((r) => r.teamId == ownTeam).firstOrNull;
    if (own == null) {
      throw const FormatException('Inclua o seu time na classificação final.');
    }
    final saved = await db.query(
      'TournamentResult',
      where: 'personId = ? AND seasonId = ? AND tournamentId = ?',
      whereArgs: [person.id, season.id, table.tournamentId],
    );
    final manual = saved
        .where((r) => !'${r['id']}'.startsWith('auto:'))
        .firstOrNull;
    final resultId =
        manual?['id']?.toString() ??
        'season-close:${person.id}:${season.id}:${table.tournamentId}';
    final previousResult = manual ?? saved.firstOrNull;
    final winner = own.position == 1;
    await db.insert(
      'TournamentResult',
      TournamentResult(
        id: resultId,
        personId: person.id,
        seasonId: season.id,
        fifaVersion: person.fifaVersion,
        tournamentId: table.tournamentId,
        result: winner ? 'Campeão · 1º lugar' : '${own.position}º lugar',
        youParticipatedIn: true,
        isWinner: winner,
        playerOfTheTournamentId:
            previousResult?['playerOfTheTournamentId'] as String?,
        playerOfTheTournamentTeamId:
            previousResult?['playerOfTheTournamentTeamId'] as String?,
        playerOfTheTournamentLeagueId:
            previousResult?['playerOfTheTournamentLeagueId'] as String?,
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    for (final r in saved.where((r) => r['id'] != resultId)) {
      await db.update(
        'TournamentResultTable',
        {'tournamentResultId': resultId},
        where: 'personId = ? AND seasonId = ? AND tournamentResultId = ?',
        whereArgs: [person.id, season.id, r['id']],
      );
    }
    final tableId =
        'season-table:${person.id}:${season.id}:${table.tournamentId}';
    final previous = await db.query(
      'TournamentResultTable',
      where: 'personId = ? AND seasonId = ? AND id = ?',
      whereArgs: [person.id, season.id, table.id],
    );
    final id = previous.isNotEmpty ? table.id : tableId;
    final now = DateTime.now().toIso8601String();
    await db.insert('TournamentResultTable', {
      'id': id,
      'name': table.name,
      'fifaVersion': person.fifaVersion,
      'seasonId': season.id,
      'personId': person.id,
      'tournamentResultId': resultId,
      'ownTeamId': ownTeam,
      'position': 0,
      'createdAt': previous.firstOrNull?['createdAt'] ?? now,
      'updatedAt': now,
      'closedAt': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.delete(
      'TournamentResultTableItem',
      where: 'personId = ? AND tournamentResultTableId = ?',
      whereArgs: [person.id, id],
    );
    for (final row in table.rows) {
      await db.insert('TournamentResultTableItem', {
        'id': '$id:${row.teamId}',
        'tournamentResultTableId': id,
        'fifaVersion': person.fifaVersion,
        'seasonId': season.id,
        'personId': person.id,
        'teamId': row.teamId,
        'leagueId': row.leagueId,
        'position': row.position,
        for (final key in standingStats.keys) key: row.stats[key] ?? 0,
        'knownStats': jsonEncode(
          standingStats.keys.where((key) => row.stats[key] != null).toList(),
        ),
        'createdAt': now,
        'updatedAt': now,
      });
    }
    if (winner) {
      final format = names.format(table.tournamentId, person.fifaVersion);
      final award = format.awardId ?? '-1';
      final trophies = await db.query(
        'Trophies',
        where: 'personId = ? AND seasonId = ? AND awardId = ?',
        whereArgs: [person.id, season.id, award],
      );
      if (!trophies.any(
        (t) => award != '-1' || t['description'] == table.name,
      )) {
        await db.insert(
          'Trophies',
          Trophy(
            id: 'season-title:${person.id}:${season.id}:${table.tournamentId}',
            personId: person.id,
            seasonId: season.id,
            teamId: ownTeam,
            leagueId: own.leagueId,
            isNational: format.national,
            awardId: award,
            count: 1,
            date: season.endDate,
            description: award == '-1' ? table.name : null,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } else {
      await db.delete(
        'Trophies',
        where: 'id IN (?, ?) AND personId = ?',
        whereArgs: [
          'season-title:${person.id}:${season.id}:${table.tournamentId}',
          'auto:${season.id}:${table.tournamentId}',
          person.id,
        ],
      );
    }
  }

  Future<SeasonReview> _capture(
    DatabaseExecutor db,
    Person person,
    Season season,
    SeasonReviewLabels names,
  ) async {
    final fixtureTable = person.category == PersonCategory.manager
        ? 'ManagerFixtures'
        : 'PlayerFixtures';
    final fixtures = await db.query(
      fixtureTable,
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [person.id, season.id],
      orderBy: 'date ASC, id ASC',
    );
    final saved = await db.query(
      'TournamentResult',
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [person.id, season.id],
    );
    final outcomes = TournamentOutcome.compute(
      fixtures,
      formatOf: (id) => names.format(id, person.fifaVersion),
      seasonOver: season.isClosed,
    );
    final competitions = <Map<String, Object?>>[];
    for (final id in {
      ...outcomes.map((o) => o.tournamentId),
      ...saved.map((s) => '${s['tournamentId']}'),
    }) {
      final matches = outcomes.where((o) => o.tournamentId == id).firstOrNull;
      final rows = saved.where((s) => s['tournamentId'] == id);
      final result =
          rows.where((s) => !'${s['id']}'.startsWith('auto:')).firstOrNull ??
          rows.firstOrNull;
      final finalKnown = matches?.definitive ?? false;
      competitions.add({
        'id': id,
        'name': names.competitions[id] ?? id,
        'result':
            result?['result'] ??
            (finalKnown
                ? matches!.resultText
                : season.isClosed
                ? 'Encerrada · resultado não informado'
                : matches?.resultText ?? 'Sem jogos'),
        'won': result != null ? result['isWinner'] == 1 : matches?.won ?? false,
        'kind': names.format(id, person.fifaVersion).kind.name,
        'games': matches?.games ?? 0,
        'position': matches?.position,
        'goalsFor': matches?.goalsFor ?? 0,
        'goalsAgainst': matches?.goalsAgainst ?? 0,
        'path': matches?.path ?? <String>[],
      });
    }
    final tables = <SeasonFinalTable>[];
    for (final t in await db.query(
      'TournamentResultTable',
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [person.id, season.id],
    )) {
      final result = saved
          .where((r) => r['id'] == t['tournamentResultId'])
          .firstOrNull;
      if (result == null) continue;
      final rows = await db.query(
        'TournamentResultTableItem',
        where: 'personId = ? AND seasonId = ? AND tournamentResultTableId = ?',
        whereArgs: [person.id, season.id, t['id']],
        orderBy: 'position ASC',
      );
      tables.add(
        SeasonFinalTable(
          id: '${t['id']}',
          tournamentId: '${result['tournamentId']}',
          name: '${t['name']}',
          ownTeamId: t['ownTeamId'] as String?,
          closedAt: DateTime.tryParse('${t['closedAt']}'),
          rows: rows
              .map(
                (r) => SeasonStanding.fromRow(
                  r,
                  names.teams['${r['teamId']}'] ?? '${r['teamId']}',
                ),
              )
              .toList(),
        ),
      );
    }
    final players = person.category == PersonCategory.manager
        ? await db.rawQuery(
            '''
      SELECT p.playerInstanceId AS playerId, cp.name, COUNT(DISTINCT p.fixtureId) AS matches,
        SUM(p.goalsCount) AS goals, SUM(p.assistsCount) AS assists,
        SUM(p.yellowCards) AS yellowCards, SUM(p.redCards) AS redCards,
        AVG(p.avgRating) AS rating, COUNT(p.avgRating) AS ratings,
        SUM(p.shotsCount) AS shots, SUM(p.passes) AS passes, SUM(p.keyPasses) AS keyPasses,
        SUM(p.tackles) AS tackles, SUM(p.saves) AS saves
      FROM ManagerFixturePlayerPerformances p
      JOIN ManagerFixtures f ON f.id = p.fixtureId AND f.personId = p.personId
      LEFT JOIN CustomCreatedPlayer cp ON cp.id = p.playerInstanceId AND cp.personId = p.personId
      WHERE p.personId = ? AND f.seasonId = ?
        AND p.rowid = (SELECT MAX(d.rowid) FROM ManagerFixturePlayerPerformances d
          WHERE d.personId = p.personId AND d.fixtureId = p.fixtureId AND d.playerInstanceId = p.playerInstanceId)
      GROUP BY p.playerInstanceId
    ''',
            [person.id, season.id],
          )
        : await db.rawQuery(
            '''
      SELECT ? AS name, COUNT(*) AS matches, SUM(goalsCount) AS goals,
        SUM(assistsCount) AS assists, AVG(rating) AS rating, COUNT(rating) AS ratings,
        SUM(minsPlayed) AS minutes, SUM(savesCount) AS saves,
        SUM(yellowCards) AS yellowCards, SUM(redCards) AS redCards
      FROM PlayerFixtures WHERE personId = ? AND seasonId = ? HAVING COUNT(*) > 0
    ''',
            [person.name, person.id, season.id],
          );
    final events = <Map<String, Object?>>[];
    if (person.category == PersonCategory.manager) {
      for (final t in await db.rawQuery(
        '''SELECT t.*, cp.name FROM TeamTransferItem t
        LEFT JOIN CustomCreatedPlayer cp ON cp.id = t.playerInstanceId AND cp.personId = t.personId
        WHERE t.personId = ? AND t.seasonId = ?''',
        [person.id, season.id],
      )) {
        events.add({
          'type': 'transfer',
          'date': t['date'],
          'name': t['name'] ?? 'Jogador',
          'movement': t['type'],
          'value': t['transferValue'],
          'from': t['fromTeamId'],
          'to': t['toTeamId'],
        });
      }
      for (final i in await db.rawQuery(
        '''SELECT i.*, cp.name FROM Injury i
        LEFT JOIN CustomCreatedPlayer cp ON cp.id = i.playerId AND cp.personId = i.personId
        WHERE i.personId = ? AND i.seasonId = ?''',
        [person.id, season.id],
      )) {
        events.add({
          'type': 'injury',
          'date': i['startDate'],
          'name': i['name'] ?? 'Jogador',
          'description': i['description'],
          'days': i['expectedRecoveryDays'],
        });
      }
    }
    events.sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    final clubFixtures = fixtures.where(
      (f) => f['playerTeamLeagueId'] != GameCatalog.nationalLeagueId,
    );
    final referencedTeams = {
      person.teamId,
      for (final f in fixtures) ...[
        '${f['playerTeamId']}',
        '${f['oppositeTeamId']}',
      ],
      for (final t in tables) ...t.rows.map((r) => r.teamId),
      for (final e in events) ...['${e['from']}', '${e['to']}'],
    };
    return SeasonReview(
      season: season,
      savedAt: DateTime.now(),
      careerName: person.name,
      teamId:
          clubFixtures.lastOrNull?['playerTeamId']?.toString() ??
          fixtures.lastOrNull?['playerTeamId']?.toString() ??
          person.teamId,
      fixtures: fixtures,
      players: players,
      competitions: competitions,
      tables: tables,
      events: events,
      teamNames: {
        for (final id in referencedTeams)
          if (names.teams.containsKey(id)) id: names.teams[id]!,
      },
    );
  }
}
