import 'dart:convert';

import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/models/Tournament.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

Future<Database> createHubFixture() async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await SqlService.ensureCompatibleSchema(db);
  await db.execute('ALTER TABLE Tournament ADD COLUMN format TEXT');
  await SqlService.ensureSeasonClosureSchema(db);
  await SqlService.ensureFixtureFormationSchema(db);
  await SqlService.ensureTransferReleaseSchema(db);
  final person = reviewPerson();
  await db.insert('Persons', person.toMap());
  for (final year in [2027, 2028]) {
    await db.insert('Seasons', reviewSeason(id: 's$year', year: year).toMap());
  }
  for (final (id, name) in [
    ('cup', 'Copa da Carreira'),
    ('other', 'Outra Copa'),
  ]) {
    await db.insert(
      'Tournament',
      Tournament(id: id, name: name, fifaVersions: 'FC26').toMap(),
    );
  }
  for (final (id, name, position) in [
    ('p1', 'Arthur Silva', '25'),
    ('p2', 'Bruno Costa', '0'),
    ('p3', 'Caio Santos', '5'),
  ]) {
    await db.insert('CustomCreatedPlayer', {
      'id': id,
      'personId': person.id,
      'name': name,
      'positionId': position,
      'overall': id == 'p1' ? 84 : 80,
      'potential': 90,
      'foot': 'Right',
      'realFace': 0,
      'fromRealPlayer': 0,
    });
  }
  for (final id in ['p1', 'p2']) {
    await db.insert('TeamPlayer', {
      'id': 'roster-$id',
      'personId': person.id,
      'seasonId': 's2028',
      'playerId': id,
      'isBench': 0,
      'overall': id == 'p1' ? 84 : 80,
    });
  }
  final fixtures = <String, Map<String, Object?>>{
    'round': {
      ...reviewFixture(0, season: 's2028', tournament: 'cup'),
      'date': '2028-06-01',
      'stage': 'Semifinal',
      'playerTeamScore': 2,
      'oppositeTeamScore': 1,
    },
    'final': {
      ...reviewFixture(1, season: 's2028', tournament: 'cup'),
      'date': '2028-06-03',
      'stage': 'Final',
      'playerTeamScore': 1,
      'oppositeTeamScore': 0,
    },
    'after': {
      ...reviewFixture(2, season: 's2028', tournament: 'cup'),
      'date': '2028-06-04',
    },
    'other-cup': {
      ...reviewFixture(3, season: 's2028', tournament: 'other'),
      'date': '2028-06-02',
    },
    'old': {
      ...reviewFixture(4, season: 's2027', tournament: 'cup'),
      'date': '2027-06-01',
    },
    'other-club': {
      ...reviewFixture(5, season: 's2028', tournament: 'cup'),
      'date': '2028-06-02',
      'playerTeamId': 'other-club',
    },
  };
  for (final f in fixtures.entries) {
    await db.insert('ManagerFixtures', {...f.value, 'id': f.key});
  }
  for (final (id, goals, rating, minutes) in [
    ('round', 2, 8.0, 90),
    ('final', 1, 9.0, 80),
    ('after', 4, 7.0, 90),
    ('other-cup', 8, 9.5, 90),
    ('old', 10, 9.0, 90),
    ('other-club', 12, 9.0, 90),
  ]) {
    await db.insert(
      'ManagerFixturePlayerPerformances',
      ManagerFixturePlayerPerformance(
        id: 'perf-$id',
        personId: person.id,
        fixtureId: id,
        playerInstanceId: 'p1',
        goalsCount: goals,
        assistsCount: 1,
        avgRating: rating,
        recordedMinutes: minutes,
        recordedStarted: true,
        shotsCount: id == 'round' ? 4 : 3,
        keyPasses: 1,
        tackles: 2,
        yellowCards: id == 'round' ? 1 : 0,
        redCards: 0,
        passes: id == 'round' ? 10 : 40,
        passAccuracy: id == 'round' ? 90 : 50,
        apiStats: {
          'passesCompleted': id == 'round' ? 9 : 20,
          'passes': id == 'round' ? 10 : 40,
          'npkExpectedGoals': .7,
          'expectedAssists': .3,
        },
      ).toMap(),
    );
  }
  await db.insert(
    'ManagerFixturePlayerPerformances',
    ManagerFixturePlayerPerformance(
      id: 'keeper',
      personId: person.id,
      fixtureId: 'round',
      playerInstanceId: 'p2',
      goalsCount: 0,
      assistsCount: 0,
      avgRating: 7,
      recordedMinutes: 90,
      recordedStarted: true,
      saves: 4,
    ).toMap(),
  );
  for (final row in [
    {
      'id': 'legacy',
      'seasonId': 's2027',
      'awardId': 'competition:FC26:cup',
      'count': 2,
      'date': '2027-06-01',
    },
    {
      'id': 'auto:s2028:cup',
      'seasonId': 's2028',
      'awardId': 'competition:FC26:cup',
      'count': 1,
      'date': '2028-06-03',
      'fixtureId': 'final',
    },
    {
      'id': 'unlinked',
      'seasonId': 'missing',
      'awardId': '-1',
      'count': 1,
      'description': 'Taça sem vínculo',
    },
  ]) {
    await db.insert('Trophies', {
      'personId': person.id,
      'teamId': person.teamId,
      'leagueId': person.leagueId,
      'isNational': 0,
      ...row,
    });
  }
  for (final (id, player, start, end) in [
    ('active', 'p1', '2028-05-20', null),
    ('recovered', 'p2', '2028-05-01', '2028-05-10'),
    ('future', 'p2', '2028-07-01', null),
    ('departed', 'p3', '2028-05-20', null),
    ('older-active', 'p1', '2027-12-30', null),
  ]) {
    await db.insert('Injury', {
      'id': id,
      'personId': person.id,
      'seasonId': id == 'older-active' ? 's2027' : 's2028',
      'playerId': player,
      'teamId': person.teamId,
      'leagueId': person.leagueId,
      'startDate': start,
      'endDate': end,
      'description': 'Lesão muscular',
      'expectedRecoveryDays': 14,
      'createdAt': start,
    });
  }
  await db.insert('AcademyPlayer', {
    'id': 'young',
    'personId': person.id,
    'name': 'Daniel Souza',
    'positionId': '14',
    'overall': 65,
    'potentialStart': 80,
    'potentialEnd': 92,
    'teamId': person.teamId,
    'leagueId': person.leagueId,
    'foot': 'Right',
    'isHistorical': 0,
  });
  await db.insert('FcScoreCompetition', {
    'personId': person.id,
    'seasonId': 's2028',
    'remoteId': 'remote',
    'tournamentId': 'other',
    'saveId': 'save',
    'name': 'Outra Copa',
    'currentDate': '2028-06-05',
    'importedAt': '2028-06-05',
    'rawJson': jsonEncode({}),
  });
  return db;
}
