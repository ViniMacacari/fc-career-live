import 'package:sqflite/sqflite.dart';

import '../models/Person.dart';
import '../utils/competitions/CompetitionFormats.dart';
import '../utils/competitions/TournamentOutcomes.dart';
import 'TwitterCareerSummary.dart';
import 'TwitterStore.dart';

class TwitterMatchOccasion {
  static Future<SocialRow> load(
    Database db,
    Person person,
    SocialRow fixture,
    TwitterCareerSummary summary,
  ) async {
    final seasonId = fixture['seasonId'], team = fixture['playerTeamId'];
    if (seasonId == null || team == null) return {};
    final season = summary.seasons.where((s) => s.id == seasonId).firstOrNull;
    final table = person.category == PersonCategory.manager
        ? 'ManagerFixtures'
        : 'PlayerFixtures';
    final all = await db.query(
      table,
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [person.id, seasonId],
      orderBy: 'julianday(date), id',
    );
    final club = all.where((f) => f['playerTeamId'] == team).toList();
    final date = DateTime.parse('${fixture['date']}');
    final through = club
        .where(
          (f) => !(DateTime.tryParse('${f['date']}')?.isAfter(date) ?? true),
        )
        .toList();
    final custom = {
      for (final row in await db.query('Tournament')) '${row['id']}': row,
    };
    CompetitionFormat format(String id) => CompetitionFormat.of(
      id,
      person.fifaVersion,
      customFormat: custom[id]?['format'] as String?,
    );
    String label(String id) =>
        summary.tournaments[id] ?? custom[id]?['name']?.toString() ?? id;
    final positionsFromTable = <Object?>{};
    for (var i = 0; i < through.length; i++) {
      final match = through[i], f = format('${through[i]['tournamentId']}');
      final round = f.parse(match['stage']?.toString())?.round;
      final position = match['position'] as num?;
      if (f.kind != CompetitionKind.league ||
          f.playoffsDecideTitle ||
          f.rounds <= 0 ||
          round != f.rounds ||
          (position != null && position > 0)) {
        continue;
      }
      final rank = await _completedTablePosition(
        db,
        person.id,
        seasonId,
        match,
        f.rounds,
      );
      if (rank != null) {
        through[i] = {...match, 'position': rank};
        positionsFromTable.add(match['id']);
      }
    }
    final atLast = club.isNotEmpty && club.last['id'] == fixture['id'];
    final closed =
        season != null &&
        (season.isClosed ||
            await db
                .rawQuery(
                  'SELECT id FROM $table WHERE personId = ? AND julianday(date) > julianday(?) LIMIT 1',
                  [person.id, season.endDate.toIso8601String()],
                )
                .then((r) => r.isNotEmpty));
    final outcomes = TournamentOutcome.compute(
      through,
      formatOf: format,
      seasonOver: closed && atLast,
    );
    final current = outcomes
        .where((o) => o.tournamentId == fixture['tournamentId'])
        .firstOrNull;
    final decisive = current?.decisive?['id'] == fixture['id'];
    var champion = decisive && current!.won;
    var opponentChampion =
        decisive && current!.status == OutcomeStatus.runnerUp;
    final sameCompetition = all
        .where((f) => f['tournamentId'] == fixture['tournamentId'])
        .toList();
    final lastCompetition = sameCompetition.lastOrNull?['id'] == fixture['id'];
    final recorded = await db.query(
      'TournamentResult',
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [person.id, seasonId],
    );
    final manual = recorded
        .where(
          (r) =>
              r['tournamentId'] == fixture['tournamentId'] &&
              r['isWinner'] != null &&
              r['youParticipatedIn'] != 0 &&
              !'${r['id']}'.startsWith('auto:'),
        )
        .firstOrNull;
    final parsedStage = format('${fixture['tournamentId']}')
        .parse(fixture['stage']?.toString());
    if (lastCompetition &&
        manual != null &&
        parsedStage?.leg != StageLeg.first) {
      champion = manual['isWinner'] == 1;
      if (champion) opponentChampion = false;
    }
    final titles = <String>{
      for (final o in outcomes.where(
        (o) =>
            o.won &&
            !recorded.any(
              (r) =>
                  r['tournamentId'] == o.tournamentId &&
                  r['isWinner'] == 0 &&
                  !'${r['id']}'.startsWith('auto:'),
            ),
      ))
        label(o.tournamentId),
    };
    for (final r in recorded.where(
      (r) => r['isWinner'] == 1 && r['youParticipatedIn'] != 0,
    )) {
      final matches = all
          .where((f) => f['tournamentId'] == r['tournamentId'])
          .toList();
      final last = matches.lastOrNull;
      if (last != null &&
          last['playerTeamId'] == team &&
          !(DateTime.tryParse('${last['date']}')?.isAfter(date) ?? true)) {
        titles.add(label('${r['tournamentId']}'));
      }
    }
    var futureCalendar = false;
    if ((await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'FcScoreWorldFixture'",
    )).isNotEmpty) {
      futureCalendar = (await db.rawQuery(
        '''SELECT remoteKey FROM FcScoreWorldFixture
        WHERE personId = ? AND seasonId = ? AND (homeTeamId = ? OR awayTeamId = ?)
        AND julianday(date) > julianday(?) LIMIT 1''',
        [person.id, seasonId, team, team, fixture['date']],
      )).isNotEmpty;
    }
    final allFinished =
        outcomes.isNotEmpty &&
        outcomes.every((o) => o.definitive) &&
        outcomes.any(
          (o) =>
              o.format.kind == CompetitionKind.league &&
              o.format.rounds > 0 &&
              o.furthest?.round != null &&
              o.furthest!.round! >= o.format.rounds,
        );
    final atEndDate =
        season != null &&
        !DateTime(date.year, date.month, date.day).isBefore(
          DateTime(
            season.endDate.year,
            season.endDate.month,
            season.endDate.day,
          ),
        );
    final finale =
        atLast && !futureCalendar && (closed || atEndDate || allFinished);
    if (!champion && !opponentChampion && !finale) return {};
    return {
      'careerChampion': champion,
      'opponentChampion': opponentChampion,
      'competition': label('${fixture['tournamentId']}'),
      if (champion || opponentChampion)
        'titleEvidence': manual != null && champion
            ? 'resultado de campeão registrado pelo usuário'
            : positionsFromTable.contains(fixture['id'])
            ? 'última rodada da liga e classificação final completa: 1º lugar'
            : current?.format.kind == CompetitionKind.league &&
                  parsedStage?.round != null
            ? 'última rodada da liga e posição final registrada: 1º lugar'
            : 'confronto decisivo e resultado da competição',
      if (current?.format.kind == CompetitionKind.league) ...{
        'leagueRound': parsedStage?.round,
        'leagueRounds': current!.format.rounds,
        'finalPosition': through
            .where((f) => f['id'] == fixture['id'])
            .firstOrNull?['position'],
      },
      'lastMatchOfSeason': finale,
      if (finale) ...{
        'season': summary.seasonLabel(seasonId),
        'seasonConclusionEvidence': closed
            ? 'temporada encerrada'
            : atEndDate
            ? 'data final da temporada'
            : 'liga completa e competições registradas decididas, sem jogos posteriores no calendário',
        'seasonRecord': {
          'games': through.length,
          'wins': through
              .where((f) => TwitterStore.fixtureOutcome(f).startsWith('win'))
              .length,
          'draws': through
              .where((f) => TwitterStore.fixtureOutcome(f) == 'draw')
              .length,
          'losses': through
              .where((f) => TwitterStore.fixtureOutcome(f).startsWith('loss'))
              .length,
        },
        'seasonTitles': titles.toList(),
      },
    };
  }

  static Future<int?> _completedTablePosition(
    Database db,
    String personId,
    Object seasonId,
    SocialRow fixture,
    int rounds,
  ) async {
    final tables = await db.rawQuery(
      '''SELECT t.id FROM TournamentResultTable t
      JOIN TournamentResult r ON r.id = t.tournamentResultId AND r.personId = t.personId
      WHERE t.personId = ? AND t.seasonId = ? AND r.seasonId = ? AND r.tournamentId = ?''',
      [personId, seasonId, seasonId, fixture['tournamentId']],
    );
    final ranks = <int>{};
    for (final table in tables) {
      final rows = await db.query(
        'TournamentResultTableItem',
        where: 'personId = ? AND seasonId = ? AND tournamentResultTableId = ?',
        whereArgs: [personId, seasonId, table['id']],
      );
      if (rows.length < 3 ||
          rows.any((r) => (r['matchesPlayed'] as num? ?? 0) < rounds)) {
        continue;
      }
      final own = rows
          .where((r) => r['teamId'] == fixture['playerTeamId'])
          .firstOrNull;
      final rank = (own?['position'] as num?)?.toInt();
      if (rank != null &&
          rank > 0 &&
          rank <= rows.length &&
          rows.where((r) => r['position'] == rank).length == 1) {
        ranks.add(rank);
      }
    }
    return ranks.length == 1 ? ranks.single : null;
  }
}
