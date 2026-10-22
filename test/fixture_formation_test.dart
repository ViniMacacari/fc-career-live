import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/FcScore/FcScoreModels.dart' show fcKnownPositionId;
import 'package:mcmanager/utils/databaseUtils.dart';
import 'package:mcmanager/models/FixtureFormation.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/models/Person.dart';
import 'package:mcmanager/utils/FootballFormations.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final roster = [
    for (var i = 0; i < 14; i++)
      {
        'id': 'team-$i',
        'playerId': 'p$i',
        'customName': 'Jogador $i',
        'customPositionId': i == 10
            ? '0'
            : i < 3
            ? '25'
            : i < 6
            ? '14'
            : '5',
        'shirtNumber': i + 1,
        'isBench': i >= 11 ? 1 : 0,
        if (i < 11)
          'x': i < 3
              ? i
              : i < 6
              ? i - 3
              : i < 10
              ? i - 6
              : 0,
        if (i < 11)
          'y': i < 3
              ? 0
              : i < 6
              ? 1
              : i < 10
              ? 2
              : 3,
      },
  ];
  FixtureFormation initial({
    List<ManagerFixturePlayerPerformance> perfs = const [],
  }) => FixtureFormation.initial(
    roster: roster,
    names: const {},
    positions: const {},
    performances: perfs,
  );

  test('Every catalog shape has 10 outfield players and a goalkeeper', () {
    expect(footballFormations.length, greaterThan(30));
    for (final label in footballFormations.keys) {
      final next = initial().withFormation(label);
      expect(next.shape.fold<int>(0, (a, b) => a + b), 11, reason: label);
      expect(next.shape.last, 1, reason: label);
      expect(next.starters, hasLength(11), reason: label);
      expect(next.starters.values.toSet(), hasLength(11), reason: label);
      expect(next.starters['p10'], (
        x: 0,
        y: next.shape.length - 1,
      ), reason: label);
      expect(next.bench, ['p11', 'p12', 'p13'], reason: label);
    }
  });

  test('Custom shapes validate number of lines, positive counts and total', () {
    expect(customFootballFormation(' 4 – 2 – 3 – 1 '), [1, 3, 2, 4, 1]);
    expect(customFootballFormation('6-3-1'), [1, 3, 6, 1]);
    expect(customFootballFormation('9-1'), [1, 9, 1]);
    for (final invalid in [
      '10',
      '4-3-2',
      '4-4-3',
      '0-5-5',
      '-1-5-6',
      'x-4-6',
      '1-1-1-1-1-5',
    ]) {
      expect(customFootballFormation(invalid), isNull, reason: invalid);
    }
  });

  test(
    'Snapshot preserves roster slots, shirt numbers and identity on round trip',
    () {
      final before = initial();
      final saved = FixtureFormation.decode(before.encode())!;
      expect(saved.starters, before.starters);
      expect(saved.players['p0']?['name'], 'Jogador 0');
      expect(saved.players['p0']?['shirtNumber'], 1);
      expect(saved.bench, ['p11', 'p12', 'p13']);
      roster.first['customName'] = 'Nome atualizado no elenco';
      expect(saved.players['p0']?['name'], 'Jogador 0');
      roster.first['customName'] = 'Jogador 0';
    },
  );

  test(
    'Moving starters swaps slots; a reserve replaces a starter into the bench',
    () {
      final before = initial();
      final moved = before.place('p0', before.starters['p1']!);
      expect(moved.starters['p1'], before.starters['p0']);
      expect(moved.starters['p0'], before.starters['p1']);
      expect(before.starters['p0'], (x: 0, y: 0));
      final replaced = moved.place('p11', moved.starters['p0']!);
      expect(replaced.starters, hasLength(11));
      expect(replaced.bench, ['p12', 'p13', 'p0']);
      expect(replaced.starters.containsKey('p0'), isFalse);
      expect(replaced.relateBench(['p0', 'p0', 'p1', 'unknown']).bench, ['p0']);
      expect(before.place('unknown', (x: 0, y: 0)), same(before));
      expect(before.place('p0', (x: 100, y: 0)), same(before));
    },
  );

  test('Participation infers starters from earliest substitution and keeps historical players', () {
    ManagerFixturePlayerPerformance p(
      String id,
      List<PerformanceSubstitutionDetails> subs,
    ) => ManagerFixturePlayerPerformance(
      personId: 'career',
      fixtureId: 'match',
      playerInstanceId: id,
      substitutionDetails: subs,
    );
    final result = initial(
      perfs: [
        p('p0', [
          PerformanceSubstitutionDetails(
            minute: 60,
            type: SubstitutionType.outGame,
          ),
        ]),
        p('p11', [
          PerformanceSubstitutionDetails(
            minute: 80,
            type: SubstitutionType.outGame,
          ),
          PerformanceSubstitutionDetails(
            minute: 60,
            type: SubstitutionType.inGame,
          ),
        ]),
        p('transferred', []),
        p('p10', []),
      ],
    );
    expect(result.starters.keys.toSet(), {'p0', 'p10', 'transferred'});
    expect(result.bench, ['p11']);
    expect(result.players.containsKey('transferred'), isTrue);
    expect(result.starters['p10'], (x: 0, y: 3));
    expect(result.starters.containsKey('p1'), isFalse);
  });

  test('Match pitch places every line like the squad manager', () {
    String role(FixtureFormation f, String id) {
      final slot = f.starters[id]!;
      return canonicalPositionId(
        footballSlotPosition(f.shape, slot.x, slot.y),
      )!;
    }

    FixtureFormation place(String formation, Map<String, String> positions) =>
        FixtureFormation(
          formation: formation,
          players: {
            for (final e in positions.entries)
              e.key: {'id': e.key, 'name': e.key, 'positionId': e.value},
          },
          starters: {},
          bench: [],
        ).withFormation(formation, starting: positions.keys.toList());
    final own = place('4-2-3-1', {
      'gk': '0',
      'rb': '3',
      'cb1': '5',
      'cb2': '5',
      'lb': '7',
      'cdm1': '10',
      'cdm2': '10',
      'cam': '18',
      'lw1': '27',
      'st': '25',
      'lw2': '27',
    });
    expect(role(own, 'gk'), '0');
    expect({role(own, 'cb1'), role(own, 'cb2')}, {'5'});
    expect({role(own, 'cdm1'), role(own, 'cdm2')}, {'10'});
    expect(role(own, 'st'), '25');
    expect(role(own, 'cam'), '18');
    final rival = place('4-4-2', {
      'gk': '0',
      'rb': '3',
      'cb': '5',
      'lcb': '6',
      'lb': '7',
      'rcm': '13',
      'lcm': '15',
      'cam': '18',
      'rm': '12',
      'rs': '24',
      'st': '25',
    });
    expect(role(rival, 'lcb'), '5');
    expect({role(rival, 'rcm'), role(rival, 'lcm')}, {'14'});
    expect({role(rival, 'rs'), role(rival, 'st')}, {'25'});
    expect(positionShortName('13'), positionShortName('14'));
    expect(fcKnownPositionId(['RCB']), '5');
  });

  test(
    'Malformed snapshots are ignored and duplicate/invalid slots are discarded',
    () {
      expect(FixtureFormation.decode('not-json'), isNull);
      expect(FixtureFormation.decode('{}'), isNull);
      final raw = jsonDecode(initial().encode()) as Map<String, dynamic>;
      raw['starters']['p1'] = raw['starters']['p0'];
      raw['starters']['p2'] = {'x': 90, 'y': 0};
      raw['bench'] = ['p0', 'p11', 'p11', 'unknown'];
      final saved = FixtureFormation.decode(jsonEncode(raw))!;
      expect(saved.starters.values.toSet().length, saved.starters.length);
      expect(saved.starters.containsKey('p1'), isFalse);
      expect(saved.starters.containsKey('p2'), isFalse);
      expect(saved.bench, ['p11']);
    },
  );

  for (final category in PersonCategory.values) {
    test(
      'SQLite migrates and persists formation without altering match stats (${category.name})',
      () async {
        final db = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        addTearDown(db.close);
        await SqlService.ensureCompatibleSchema(db);
        final table = category == PersonCategory.manager
            ? 'ManagerFixtures'
            : 'PlayerFixtures';
        final fixture =
            {
              ...reviewFixture(1),
              if (category == PersonCategory.player) ...{
                'goalsCount': 0,
                'assistsCount': 0,
                'savesCount': 0,
                'yellowCards': 0,
                'redCards': 0,
                'isInjured': 0,
              },
              'id': 'match',
              'personId': 'career',
              'seasonId': 'season',
              'date': '2026-10-09',
              'playerTeamScore': 2,
              'oppositeTeamScore': 0,
              'position': 3,
            }..removeWhere(
              (key, _) =>
                  category == PersonCategory.player &&
                  (key == 'teamPossession' || key == 'passAccuracy'),
            );
        await db.insert(table, fixture);
        await SqlService.ensureFixtureFormationSchema(db);
        await SqlService.ensureFixtureFormationSchema(db);
        final service = SqlService.withDatabase(db);
        final lineup = initial().withFormation('3-4-1-2').relateBench(['p13']);
        await service.saveFixtureFormation(
          category,
          'wrong-career',
          'match',
          lineup,
        );
        expect((await db.query(table)).single['matchLineup'], isNull);
        await service.saveFixtureFormation(category, 'career', 'match', lineup);
        final stored = (await db.query(table)).single;
        expect(stored['playerTeamScore'], 2);
        expect(stored['position'], 3);
        expect(FixtureFormation.decode(stored['matchLineup'])!.bench, ['p13']);
        expect(
          FixtureFormation.decode(stored['matchLineup'])!.formation,
          '3-4-1-2',
        );
        await service.updateFixtureFields(category, 'career', 'match', {
          'position': 4,
        });
        expect(
          FixtureFormation.decode(
            (await db.query(table)).single['matchLineup'],
          )!.formation,
          '3-4-1-2',
        );
        expect(await db.query('TeamPlayer'), isEmpty);
        expect(await db.query('ManagerFixturePlayerPerformances'), isEmpty);
      },
    );
  }
}
