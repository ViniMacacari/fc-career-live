import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileData.dart';
import 'package:mcmanager/ManagerCareer/TeamTransfers/SelectTransferPlayerPage.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late SqlService sql;
  final person = reviewPerson();
  final player = <String, Object?>{
    'id': 'player',
    'personId': person.id,
    'name': 'Lucas',
    'positionId': '23',
    'overall': 60,
    'potential': 90,
    'foot': 'Right',
    'realFace': 0,
    'fromRealPlayer': 0,
  };
  Map<String, Object?> overall(
    String id,
    int value, {
    String date = '2027-10-10T00:00:00.000',
    String created = '2027-10-10T10:00:00.000',
    String career = 'career',
    String playerId = 'player',
  }) => {
    'id': id,
    'personId': career,
    'customPlayerId': playerId,
    'overall': value,
    'date': date,
    'createdAt': created,
  };

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    sql = SqlService.withDatabase(db);
    await SqlService.ensureCompatibleSchema(db);
    await SqlService.ensureSeasonClosureSchema(db);
    for (final (column, type) in [
      ('releaseDate', 'TEXT'),
      ('movementApplied', 'INTEGER'),
      ('keepInSquad', 'INTEGER'),
    ]) {
      await db.execute('ALTER TABLE TeamTransferItem ADD COLUMN $column $type');
    }
    await db.insert('Persons', person.toMap());
    await db.insert('CustomCreatedPlayer', player);
    for (final year in [2026, 2027]) {
      await db.insert(
        'Seasons',
        reviewSeason(id: 's$year', year: year).toMap(),
      );
      await db.insert('TeamPlayer', {
        'id': 'roster$year',
        'personId': person.id,
        'seasonId': 's$year',
        'playerId': 'player',
        'overall': year - 1960,
        'isBench': 0,
        'shirtNumber': 7,
      });
    }
    await db.insert('NationalTeamPlayer', {
      'id': 'national',
      'personId': person.id,
      'seasonId': 's2027',
      'nationalSquadId': 'brazil',
      'playerId': 'player',
      'overall': 70,
      'isBench': 0,
    });
  });
  tearDown(() => db.close());

  test('A newer edited season start wins over a prior-season manual update everywhere', () async {
    await sql.addPlayerHistory(
      'Overall',
      overall('prior', 75, date: '2026-08-20'),
    );
    await db.update(
      'TeamPlayer',
      {'overall': 76},
      where: 'id = ?',
      whereArgs: ['roster2027'],
    );
    final timeline = await sql.getPlayerHistory(person.id, 'player', 'Overall');
    expect(timeline.first['overall'], 76);
    expect(timeline.first['isSeasonInitial'], isTrue);
    expect(
      (await sql.getTeamPlayers(person.id, 's2027')).single['overall'],
      76,
    );
    final profile = PlayerProfileData(
      seasons: const [],
      matches: const [],
      overalls: timeline,
      marketValues: const [],
      contracts: const [],
      tournamentNames: const {},
    );
    expect(profile.latestOverall, 76);
    await sql.addPlayerHistory(
      'Overall',
      overall('later', 78, date: '2027-02-01'),
    );
    expect(
      (await sql.getTeamPlayers(person.id, 's2027')).single['overall'],
      78,
    );
    expect(
      (await sql.getPlayerSeasonRows(person.id, 'player')).first['overall'],
      76,
    );
  });

  test('Same-day explicit history wins regardless of date-only versus ISO formatting', () async {
    await sql.addPlayerHistory(
      'Overall',
      overall('same-day', 80, date: '2027-01-01'),
    );
    expect(
      (await sql.getPlayerHistory(
        person.id,
        'player',
        'Overall',
      )).first['overall'],
      80,
    );
    expect(
      (await sql.getTeamPlayers(person.id, 's2027')).single['overall'],
      80,
    );
  });

  Future<void> expectEverywhere(int expected) async {
    for (final year in [2026, 2027]) {
      final roster = await sql.getTeamPlayers(person.id, 's$year');
      expect(roster.single['overall'], expected, reason: 'elenco $year');
    }
    expect(
      (await sql.getNationalTeamPlayers(person.id, 's2027')).single['overall'],
      expected,
      reason: 'seleção',
    );
    final custom = (await sql.getCustomPlayers(person.id)).single;
    expect(custom['overall'], expected, reason: 'catálogo da carreira');
    expect(
      (await sql.getCustomPlayerById(person.id, 'player'))!['overall'],
      expected,
      reason: 'cadastro individual',
    );
    expect(
      TransferPlayerChoice(id: 'player', name: 'Lucas', custom: custom).overall,
      expected,
      reason: 'transferências',
    );
    expect(
      (await sql.getManagerStatisticsRoster(person.id))
          .map((r) => r['overall']),
      everyElement(expected),
      reason: 'estatísticas de todas as temporadas',
    );
    expect(
      (await sql.getComparisonPlayerRows(person.id)).map((r) => r['overall']),
      everyElement(expected),
      reason: 'comparação',
    );
    final profile = PlayerProfileData(
      seasons: const [],
      matches: const [],
      overalls: await sql.getPlayerHistory(person.id, 'player', 'Overall'),
      marketValues: const [],
      contracts: const [],
      tournamentNames: const {},
    );
    expect(profile.latestOverall, expected, reason: 'perfil');
    expect(
      (await sql.getPlayerSeasonRows(
        person.id,
        'player',
      )).map((r) => r['overall']),
      [67, 66],
    );
    expect((await db.query('CustomCreatedPlayer')).single['overall'], 60);
  }

  test(
    'all player displays use the latest manual overall across seasons',
    () async {
      await sql.addPlayerHistory('Overall', overall('latest', 85));
      await sql.addPlayerHistory(
        'Overall',
        overall('older', 78, date: '2025-12-31T00:00:00.000'),
      );
      await expectEverywhere(85);
    },
  );

  test(
    'ties use registration time then insertion order without mixing careers',
    () async {
      await sql.addPlayerHistory('Overall', overall('first', 82));
      await sql.addPlayerHistory(
        'Overall',
        overall('second', 83, created: '2027-10-10T11:00:00.000'),
      );
      await sql.addPlayerHistory(
        'Overall',
        overall('third', 84, created: '2027-10-10T11:00:00.000'),
      );
      await sql.addPlayerHistory(
        'Overall',
        overall(
          'other-career',
          99,
          career: 'another-career',
          date: '2030-01-01',
        ),
      );
      await sql.addPlayerHistory(
        'Overall',
        overall(
          'other-player',
          98,
          playerId: 'someone-else',
          date: '2030-01-01',
        ),
      );
      await expectEverywhere(84);
    },
  );

  test('editing and deleting the latest record refreshes every read', () async {
    await sql.addPlayerHistory('Overall', overall('previous', 81));
    await sql.addPlayerHistory(
      'Overall',
      overall('latest', 85, date: '2027-12-01T00:00:00.000'),
    );
    await sql.updatePlayerHistory(
      'Overall',
      person.id,
      overall('latest', 86, date: '2027-12-01T00:00:00.000'),
    );
    await expectEverywhere(86);
    await sql.deletePlayerHistory('Overall', person.id, 'latest');
    await expectEverywhere(81);
    await sql.deletePlayerHistory('Overall', person.id, 'previous');
    await expectEverywhere(67);
  });

  test(
    'former players retain the current overall and original season data',
    () async {
      await sql.addPlayerHistory('Overall', overall('latest', 85));
      await sql.removeTeamPlayer(person.id, 'roster2027');
      expect(await sql.getTeamPlayers(person.id, 's2027'), isEmpty);
      expect(
        (await sql.getManagerStatisticsRoster(person.id))
            .map((r) => r['overall']),
        [85, 85],
      );
      expect(
        (await sql.getCustomPlayerById(person.id, 'player'))!['overall'],
        85,
      );
      final archive = (await db.query('TeamPlayerDeparture')).single;
      expect(
        (jsonDecode(archive['rosterJson'] as String) as Map)['overall'],
        67,
      );
      await sql.deletePlayerHistory('Overall', person.id, 'latest');
      expect(
        (await sql.getCustomPlayerById(person.id, 'player'))!['overall'],
        67,
      );
      expect(
        (await sql.getPlayerSeasonRows(
          person.id,
          'player',
        )).map((r) => r['overall']),
        [67, 66],
      );
    },
  );

  test(
    'a player without history or a roster uses the registered base',
    () async {
      await db.delete('TeamPlayer');
      expect((await sql.getCustomPlayers(person.id)).single['overall'], 60);
      expect(
        (await sql.getCustomPlayerById(person.id, 'player'))!['overall'],
        60,
      );
      await sql.addPlayerHistory('Overall', overall('latest', 0));
      expect((await sql.getCustomPlayers(person.id)).single['overall'], 0);
    },
  );
}
