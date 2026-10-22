import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database db;
  late SqlService sql;
  final old = reviewSeason(id: 's2028', year: 2028);
  final next = reviewSeason(id: 's2029', year: 2029);

  setUp(() async {
    db = await SqlService.openCareerDatabase(inMemoryDatabasePath);
    sql = SqlService.withDatabase(db);
    await db.insert('Persons', reviewPerson().toMap());
    await db.insert('Seasons', old.toMap());
    for (var i = 0; i < 3; i++) {
      await db.insert('CustomCreatedPlayer', {
        'id': 'p$i',
        'personId': 'career',
        'name': 'Jogador $i',
        'positionId': '25',
        'overall': 75,
        'potential': 80,
        'realFace': 0,
        'fromRealPlayer': 0,
        'foot': 'right',
      });
      await db.insert('TeamPlayer', {
        'id': 'roster$i',
        'personId': 'career',
        'seasonId': old.id,
        'playerId': 'p$i',
        'x': i * 20,
        'y': i * 30,
        'overall': 75,
        'shirtNumber': i + 1,
        'isBench': i == 2 ? 1 : 0,
        'wage': 1000,
        'yearlyWage': 52000,
        'marketValue': 500000,
        'loanStatus': i == 2 ? 'outLoan' : null,
      });
    }
    await db.insert('ManagerFixtures', {
      ...reviewFixture(0, season: old.id),
      'date': '2028-12-15',
    });
    await db.insert('ManagerFixturePlayerPerformances', {
      'id': 'perf',
      'personId': 'career',
      'fixtureId': 'f0',
      'playerInstanceId': 'p0',
      'goalsCount': 2,
    });
  });
  tearDown(() async => db.close());

  Future<void> evolution() async {
    for (final (id, date, value) in [
      ('late', '2028-11-20', 82),
      ('earlier', '2028-08-01', 79),
      ('future', '2030-01-01', 99),
    ]) {
      await db.insert('Overall', {
        'id': id,
        'personId': 'career',
        'customPlayerId': 'p0',
        'date': date,
        'createdAt': date,
        'overall': value,
      });
      await db.insert('MarketValue', {
        'id': id,
        'personId': 'career',
        'customPlayerId': 'p0',
        'date': date,
        'createdAt': date,
        'value': value * 100000,
      });
    }
  }

  test('Rollover carries the last recorded values at the season start, excluding future and other players', () async {
    await evolution();
    await sql.createSeason(next);
    final rows = await sql.getPlayerSeasonRows('career', 'p0');
    expect(rows.first['overall'], 82);
    expect(rows.first['marketValue'], 8200000);
    expect(rows.last['overall'], 75);
    expect(rows.last['marketValue'], 500000);
    final other = await sql.getPlayerSeasonRows('career', 'p1');
    expect(other.first['overall'], 75);
    expect(other.first['marketValue'], 500000);
  });

  test('Legacy copied values are repaired once, independently preserving edits to each field', () async {
    await evolution();
    await sql.createSeason(next);
    await db.update(
      'TeamPlayer',
      {'overall': 75, 'marketValue': 500000},
      where: 'seasonId = ?',
      whereArgs: [next.id],
    );
    await db.update(
      'TeamPlayer',
      {'overall': 76},
      where: 'playerId = ? AND seasonId = ?',
      whereArgs: ['p0', next.id],
    );
    await db.update(
      'SeasonRosterInitialization',
      {'valueRevision': 0},
      where: 'seasonId = ?',
      whereArgs: [next.id],
    );
    final rows = await sql.getPlayerSeasonRows('career', 'p0');
    expect(rows.first['overall'], 76);
    expect(rows.first['marketValue'], 8200000);
    await db.update(
      'TeamPlayer',
      {'marketValue': 500000},
      where: 'playerId = ? AND seasonId = ?',
      whereArgs: ['p0', next.id],
    );
    expect(
      (await sql.getPlayerSeasonRows('career', 'p0')).first['marketValue'],
      500000,
    );
  });

  test('New season keeps identities, formation and bench without altering old records', () async {
    final roster = await db.query('TeamPlayer');
    await sql.createSeason(next);
    final copied = await sql.getTeamPlayers('career', next.id);
    expect(copied, hasLength(3));
    for (final source in roster) {
      final row = copied.singleWhere(
        (r) => r['playerId'] == source['playerId'],
      );
      expect(row['id'], isNot(source['id']));
      for (final key in [
        'x',
        'y',
        'isBench',
        'shirtNumber',
        'loanStatus',
        'wage',
        'yearlyWage',
        'marketValue',
      ]) {
        expect(row[key], source[key], reason: key);
      }
    }
    expect(
      await db.query('TeamPlayer', where: 'seasonId = ?', whereArgs: [old.id]),
      roster,
    );
    expect(await db.query('CustomCreatedPlayer'), hasLength(3));
    expect(
      (await db.query('ManagerFixturePlayerPerformances')).single['goalsCount'],
      2,
    );
    expect(await sql.getTeamPlayers('career', next.id), hasLength(3));
  });

  test('Reading an already empty current season repairs it once and never resurrects removed players', () async {
    await db.insert('Seasons', next.toMap());
    expect(await sql.getTeamPlayers('career', next.id), hasLength(3));
    await db.delete('TeamPlayer', where: 'seasonId = ?', whereArgs: [next.id]);
    expect(await sql.getTeamPlayers('career', next.id), isEmpty);
    expect(
      await db.query('TeamPlayer', where: 'seasonId = ?', whereArgs: [old.id]),
      hasLength(3),
    );
  });

  test('A departure at the new year is excluded while a loaned out player stays on the bench', () async {
    await db.insert('TeamTransferItem', {
      'id': 'return',
      'personId': 'career',
      'seasonId': old.id,
      'playerInstanceId': 'p0',
      'fromTeamId': '40-13',
      'toTeamId': 'parent',
      'type': 'endOfLoan',
      'endOfLoanDirection': 'fromYourClub',
      'date': '2028-12-15',
      'releaseDate': '2029-01-01',
      'movementApplied': 0,
    });
    await sql.createSeason(next);
    final players = await sql.getTeamPlayers('career', next.id);
    expect(players.map((p) => p['playerId']), unorderedEquals(['p1', 'p2']));
    expect((await db.query('TeamTransferItem')).single['movementApplied'], 1);
    expect(
      await db.query('TeamPlayer', where: 'seasonId = ?', whereArgs: [old.id]),
      hasLength(3),
    );
  });

  test('An incoming loan return is applied at season start before the first new match', () async {
    await db.insert('TeamTransferItem', {
      'id': 'return',
      'personId': 'career',
      'seasonId': old.id,
      'playerInstanceId': 'p2',
      'fromTeamId': 'other',
      'toTeamId': '40-13',
      'type': 'endOfLoan',
      'endOfLoanDirection': 'toYouClub',
      'date': '2028-12-15',
      'releaseDate': '2029-01-01',
      'movementApplied': 0,
    });
    await sql.createSeason(next);
    final players = await sql.getTeamPlayers('career', next.id);
    expect(
      players.singleWhere((p) => p['playerId'] == 'p2')['loanStatus'],
      isNull,
    );
    expect((await db.query('TeamTransferItem')).single['movementApplied'], 1);
  });

  test('A populated season is preserved and historical empty seasons stay unchanged', () async {
    await db.insert('Seasons', next.toMap());
    await db.insert('TeamPlayer', {
      'id': 'manual',
      'personId': 'career',
      'seasonId': next.id,
      'playerId': 'p1',
      'isBench': 1,
    });
    expect(
      (await sql.getTeamPlayers('career', next.id)).single['id'],
      'manual',
    );
    final historical = reviewSeason(id: 's2027', year: 2027);
    await db.insert('Seasons', historical.toMap());
    expect(await sql.getTeamPlayers('career', historical.id), isEmpty);
  });

  test(
    'Changing clubs between seasons does not copy the former squad',
    () async {
      await db.update(
        'Persons',
        {'teamId': 'new-club'},
        where: 'id = ?',
        whereArgs: ['career'],
      );
      await db.insert('ManagerCareerHistoryItem', {
        'id': 'move',
        'personId': 'career',
        'date': '2029-01-01',
        'fifaVersion': 'FC26',
        'fromTeamId': '40-13',
        'toTeamId': 'new-club',
        'type': 'transfer',
      });
      await sql.createSeason(next);
      expect(await sql.getTeamPlayers('career', next.id), isEmpty);
    },
  );
}
