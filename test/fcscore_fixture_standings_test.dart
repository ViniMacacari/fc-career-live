import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/FcScore/FcScoreRepository.dart';
import 'package:mcmanager/models/ManagerFixture.dart';
import 'package:mcmanager/models/PlayerFixture.dart' show GameLocation;
import 'package:mcmanager/utils/SqlService.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

FcJson _row(int id, int position, int points, int played) => {
  'position': position,
  'team': {'id': id},
  'points': points,
  'played': played,
};

FcJson _table() => {
  'competition': {'id': 1528},
  'stages': [
    {
      'id': 1,
      'name': 'Liga',
      'groups': [
        {
          'rows': [_row(598, 1, 6, 2), _row(200, 2, 3, 2), _row(300, 3, 0, 2)],
        },
      ],
    },
  ],
};

FcJson _game(int id, String date, int home, int away, int hg, int ag) => {
  'id': id,
  'date': date,
  'competition': {'id': 1528},
  'stage': 'League',
  'played': true,
  'home': {
    'team': {'id': home},
    'goals': hg,
  },
  'away': {
    'team': {'id': away},
    'goals': ag,
  },
};

final _games = [
  _game(1, '2028-06-01', 200, 300, 3, 0),
  _game(2, '2028-06-02', 598, 300, 1, 0),
  _game(3, '2028-06-10', 598, 200, 2, 0),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('Positions at a match date', () {
    FcStandingPositions at(
      String? date, {
      List<FcJson>? games,
      bool later = false,
      bool require = false,
      String snapshot = '2028-06-12',
    }) => fcStandingPositionsAt(
      competition: _table(),
      fixtures: games ?? _games,
      ownId: '598',
      opponentId: '200',
      date: date == null ? null : DateTime.parse(date),
      snapshotDate: DateTime.parse(snapshot),
      laterOwnMatch: later,
      requireMatchDay: require,
    );

    test('The latest match uses the imported table', () {
      final positions = at('2028-06-10');
      expect(positions.own, 1);
      expect(positions.opponent, 2);
      expect(at(null).own, 1);
    });

    test('An earlier match is ranked from the results until that day', () {
      final positions = at('2028-06-02');
      expect(positions.own, 2);
      expect(positions.opponent, 1);
    });

    test('A stale calendar keeps the fresh table for the latest match', () {
      final positions = at('2028-06-10', games: _games.take(2).toList());
      expect(positions.own, 1);
    });

    test('Without the result of that day nothing is invented', () {
      expect(
        at('2028-06-05', later: true, require: true, games: _games).isEmpty,
        isTrue,
      );
      expect(
        at('2028-06-20', snapshot: '2028-06-12', require: true).isEmpty,
        isTrue,
      );
    });

    test('Knockout pairs and unknown clubs have no position', () {
      final cup = {
        'stages': [
          {
            'name': 'Final',
            'groups': [
              {
                'rows': [_row(598, 1, 0, 0), _row(200, 2, 0, 0)],
              },
            ],
          },
        ],
      };
      expect(
        fcStandingPositionsAt(
          competition: cup,
          fixtures: const [],
          ownId: '598',
        ).isEmpty,
        isTrue,
      );
      expect(
        fcStandingPositionsAt(
          competition: _table(),
          fixtures: _games,
          ownId: '999',
        ).isEmpty,
        isTrue,
      );
    });
  });

  group('Imported matches', () {
    late Database db;
    late FcScoreRepository repo;
    final person = reviewPerson();
    final season = reviewSeason(id: 's2028', year: 2028);

    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      await SqlService.ensureCompatibleSchema(db);
      await SqlService.ensureSeasonClosureSchema(db);
      await db.execute(
        'ALTER TABLE ManagerFixtures ADD COLUMN opponentStats TEXT',
      );
      await db.insert('Persons', person.toMap());
      await db.insert('Seasons', season.toMap());
      repo = FcScoreRepository(sql: SqlService.withDatabase(db));
      await db.insert('FcScoreCompetition', {
        'personId': person.id,
        'seasonId': season.id,
        'remoteId': '1528',
        'tournamentId': 'league:1014',
        'saveId': 'save-A',
        'name': 'Brasileirão',
        'currentDate': '2028-06-12',
        'importedAt': 'now',
        'rawJson': jsonEncode(_table()),
      });
      for (final (remote, local) in [
        ('598', person.teamId),
        ('200', 'rival'),
        ('300', 'third'),
      ]) {
        await db.insert('FcScoreWorldTeam', {
          'personId': person.id,
          'seasonId': season.id,
          'remoteId': remote,
          'teamId': local,
          'rawJson': '{}',
        });
      }
      for (final game in _games) {
        await db.insert('FcScoreWorldFixture', {
          'personId': person.id,
          'seasonId': season.id,
          'remoteKey': 'game-${game['id']}',
          'competitionId': '1528',
          'tournamentId': 'league:1014',
          'homeTeamId': 'home',
          'awayTeamId': 'away',
          'date': game['date'],
          'played': 1,
          'rawJson': jsonEncode(game),
        });
      }
    });
    tearDown(() => db.close());

    Future<void> fixture(
      String id,
      String date,
      String opponent, {
      bool linked = true,
      int? position,
    }) async {
      await db.insert(
        'ManagerFixtures',
        ManagerFixture(
          id: id,
          personId: person.id,
          date: DateTime.parse(date),
          fifaVersion: person.fifaVersion,
          playerTeamScore: 1,
          oppositeTeamScore: 0,
          playerTeamId: person.teamId,
          playerTeamLeagueId: person.leagueId,
          oppositeTeamId: opponent,
          tournamentId: 'league:1014',
          seasonId: season.id,
          location: GameLocation.home,
          createdAt: DateTime(2028),
          updatedAt: DateTime(2028),
          position: position,
        ).toMap(),
      );
      if (linked) {
        await db.insert('FcScoreImport', {
          'personId': person.id,
          'remoteKey': 'key-$id',
          'fixtureId': id,
          'saveId': 'save-A',
          'rawJson': '{}',
          'createdAt': 'now',
        });
      }
    }

    test('Each imported match receives the table of its own date', () async {
      await fixture('early', '2028-06-02', 'third');
      await fixture('late', '2028-06-10', 'rival');
      await fixture('typed', '2028-06-02', 'third', position: 7);
      await fixture('manual', '2028-06-10', 'rival', linked: false);
      expect(await repo.syncFixtureStandings(person), 3);
      final rows = {
        for (final row in await db.query('ManagerFixtures')) row['id']: row,
      };
      expect(rows['early']!['position'], 2);
      expect(OpponentStats.decode(rows['early']!['opponentStats']).position, 3);
      expect(rows['late']!['position'], 1);
      expect(OpponentStats.decode(rows['late']!['opponentStats']).position, 2);
      expect(rows['typed']!['position'], 7);
      expect(rows['manual']!['position'], isNull);
      expect(await repo.syncFixtureStandings(person), 0);
    });

    test('A new match is offered the current positions', () async {
      final positions = await repo.fixtureStandingPositions(
        person,
        seasonId: season.id,
        tournamentId: 'league:1014',
        ownTeamId: person.teamId,
        opponentTeamId: 'rival',
        date: DateTime(2028, 6, 14),
      );
      expect(positions.own, 1);
      expect(positions.opponent, 2);
      final other = await repo.fixtureStandingPositions(
        person,
        seasonId: season.id,
        tournamentId: 'another',
        ownTeamId: person.teamId,
      );
      expect(other.isEmpty, isTrue);
    });
  });
}
