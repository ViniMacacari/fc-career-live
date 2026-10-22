import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ManagerRosterView.dart';
import 'package:mcmanager/models/FixtureFormation.dart';
import 'package:mcmanager/utils/FootballFormations.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/SquadLineup.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

List<Map<String, Object?>> _eleven() => [
  for (final (i, role) in [
    '0',
    '25',
    '7',
    '5',
    '27',
    '10',
    '23',
    '3',
    '18',
    '5',
    '10',
  ].indexed)
    {'id': 'r$i', 'positionId': role},
];

Map<String, SquadSlot> _slots(Iterable<Map<String, Object?>> rows) => {
  for (final row in rows)
    '${row['id']}': (x: row['x'] as int, y: row['y'] as int),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  test('Formation changes match roles regardless of list ordering', () {
    final players = _eleven();
    final positions = squadPositions(players, '4-2-1-3', preserve: false);
    final shape = footballFormationShape('4-2-1-3');
    for (final p in players) {
      final s = positions[p['id']]!;
      expect(footballSlotPosition(shape, s.x, s.y), p['positionId']);
    }
    for (final label in footballFormations.keys) {
      final shape = footballFormationShape(label);
      final assigned = squadPositions(
        players.reversed.toList(),
        label,
        preserve: false,
      );
      expect(assigned, hasLength(11), reason: label);
      expect(assigned.values.toSet(), hasLength(11), reason: label);
      expect(assigned['r0'], (x: 0, y: shape.length - 1), reason: label);
      expect(assigned['r1']!.y, lessThan(shape.length - 2), reason: label);
      expect(assigned['r3']!.y, shape.length - 2, reason: label);
    }
  });

  test('Incomplete sides leave the missing keeper slot empty', () {
    final players = _eleven().skip(1).toList();
    for (final label in footballFormations.keys) {
      final slots = squadPositions(players, label, preserve: false);
      expect(
        slots.values.any(
          (s) => s.y == footballFormationShape(label).length - 1,
        ),
        isFalse,
        reason: label,
      );
    }
  });

  group('Saved squad', () {
    late Database db;
    late SqlService sql;
    final person = reviewPerson();
    final season = reviewSeason();

    setUp(() async {
      db = await SqlService.openCareerDatabase(inMemoryDatabasePath);
      sql = SqlService.withDatabase(db);
      await db.insert('Persons', person.toMap());
      await db.insert('Seasons', season.toMap());
      final positions = squadPositions(_eleven(), '4-2-1-3', preserve: false);
      for (final row in _eleven()) {
        final id = '${row['id']}';
        await db.insert('CustomCreatedPlayer', {
          'id': id,
          'personId': person.id,
          'name': 'Jogador $id',
          'positionId': row['positionId'],
          'overall': 75,
          'potential': 80,
          'realFace': 0,
          'fromRealPlayer': 0,
          'foot': 'right',
        });
        await db.insert('TeamPlayer', {
          'id': id,
          'playerId': id,
          'personId': person.id,
          'seasonId': season.id,
          'isBench': 0,
          'overall': 75,
          'x': positions[id]!.x,
          'y': positions[id]!.y,
        });
      }
    });
    tearDown(() => db.close());

    test('Legacy excess starters are trimmed before automatic placement, retaining the keeper', () async {
      await sql.getSquadFormation(person.id, season.id);
      await db.update('TeamPlayer', {'x': null, 'y': null});
      for (var i = 0; i < 3; i++) {
        await db.insert('CustomCreatedPlayer', {
          'id': 'extra$i',
          'personId': person.id,
          'name': 'Extra $i',
          'positionId': '25',
          'overall': 80,
          'potential': 80,
          'realFace': 0,
          'fromRealPlayer': 0,
          'foot': 'right',
        });
        await db.insert('TeamPlayer', {
          'id': 'extra$i',
          'personId': person.id,
          'playerId': 'extra$i',
          'seasonId': season.id,
          'isBench': 0,
          'overall': 80,
        });
      }
      final before = await sql.getTeamPlayers(
        person.id,
        season.id,
        prepareLineup: true,
      );
      expect(before, hasLength(14));
      expect(
        before.every((row) => row['x'] == null && row['y'] == null),
        isTrue,
      );
      await sql.trimStartingEleven(person.id, season.id);
      final prepared = await sql.getTeamPlayers(
        person.id,
        season.id,
        prepareLineup: true,
      );
      final starters = prepared.where((r) => r['isBench'] == 0).toList();
      expect(starters, hasLength(11));
      expect(_slots(starters).values.toSet(), hasLength(11));
      expect(starters.singleWhere((r) => r['id'] == 'r0')['y'], 4);
    });

    test('Import lookups retain coordinates; the squad initializes only its missing slots', () async {
      await db.update('TeamPlayer', {'x': null, 'y': null});
      final before = await db.query('TeamPlayer');
      await sql.getTeamPlayers(person.id, season.id);
      expect(await db.query('TeamPlayer'), before);
      final prepared = await sql.getTeamPlayers(
        person.id,
        season.id,
        prepareLineup: true,
      );
      expect(prepared, hasLength(11));
      expect(_slots(prepared).values.toSet(), hasLength(11));
      final saved = _slots(prepared);
      await sql.removeTeamPlayer(person.id, 'r3');
      final remaining = await sql.getTeamPlayers(
        person.id,
        season.id,
        prepareLineup: true,
      );
      expect(_slots(remaining), {...saved}..remove('r3'));
      expect(await sql.getSquadFormation(person.id, season.id), '4-2-1-3');
    });

    test('A departure captures the scheme before removal; reopening keeps every other slot', () async {
      final before = _slots(await db.query('TeamPlayer'));
      await sql.removeTeamPlayer(person.id, 'r3');
      final reopened = SqlService.withDatabase(db);
      final after = await reopened.getTeamPlayers(person.id, season.id);
      expect(await reopened.getSquadFormation(person.id, season.id), '4-2-1-3');
      expect(_slots(after), {...before}..remove('r3'));
      expect(
        squadPositions([
          for (final row in after)
            {...row, 'positionId': row['customPositionId']},
        ], '4-2-1-3'),
        _slots(after),
      );
      for (final row in after) {
        await sql.removeTeamPlayer(person.id, '${row['id']}');
      }
      expect(await reopened.getTeamPlayers(person.id, season.id), isEmpty);
      expect(await reopened.getSquadFormation(person.id, season.id), '4-2-1-3');
    });

    for (final type in ['sell', 'outLoan']) {
      test('$type leaves only the departing starter slot vacant', () async {
        final before = _slots(await db.query('TeamPlayer'));
        await sql.saveTeamTransfer({
          'id': 'sale',
          'personId': person.id,
          'seasonId': season.id,
          'playerInstanceId': 'r3',
          'fromTeamId': person.teamId,
          'toTeamId': 'other',
          'type': type,
          'date': season.startDate.toIso8601String(),
        });
        final rows = await sql.getTeamPlayers(person.id, season.id);
        expect(await sql.getSquadFormation(person.id, season.id), '4-2-1-3');
        expect(
          _slots(rows.where((r) => r['isBench'] == 0)),
          {...before}..remove('r3'),
        );
      });
    }

    test('Scheme is saved with coordinates, scoped to its season, and carried forward', () async {
      final next = squadPositions(_eleven(), '4-4-2', preserve: false);
      await sql.setLineupPositions(
        person.id,
        next,
        seasonId: season.id,
        formation: '4-4-2',
      );
      expect(await sql.getSquadFormation(person.id, season.id), '4-4-2');
      final newSeason = reviewSeason(id: 's2027', year: 2027);
      await sql.createSeason(newSeason);
      final copied = await sql.getTeamPlayers(person.id, newSeason.id);
      expect(await sql.getSquadFormation(person.id, newSeason.id), '4-4-2');
      for (final row in copied) {
        expect((x: row['x'], y: row['y']), next[row['playerId']]);
      }
      final snapshot = FixtureFormation.initial(
        roster: copied,
        names: const {},
        positions: const {},
        performances: const [],
      );
      expect(snapshot.formation, '4-4-2');
      await sql.setLineupPositions(
        person.id,
        {},
        seasonId: newSeason.id,
        formation: '3-5-2',
      );
      expect(await sql.getSquadFormation(person.id, season.id), '4-4-2');
    });

    test(
      'Benching a player keeps the exact formation and ten remaining slots',
      () async {
        final before = _slots(await db.query('TeamPlayer'));
        await sql.setTeamPlayerPlacement(
          personId: person.id,
          playerId: 'r3',
          reserve: true,
        );
        final rows = await sql.getTeamPlayers(person.id, season.id);
        expect(await sql.getSquadFormation(person.id, season.id), '4-2-1-3');
        expect(
          _slots(rows.where((r) => r['isBench'] == 0)),
          {...before}..remove('r3'),
        );
      },
    );
  });

  testWidgets(
    'Pitch immediately shows the new positions and a fresh incomplete view keeps its scheme',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final initial = squadPositions(_eleven(), '4-2-1-3', preserve: false);
      var rows = [
        for (final row in _eleven())
          {
            ...row,
            'customName': 'Jogador ${row['id']}',
            'customPositionId': row['positionId'],
            'isBench': 0,
            'x': initial[row['id']]!.x,
            'y': initial[row['id']]!.y,
          },
      ];
      Map<String, SquadSlot>? saved;
      Widget app(String formation, String key) => MaterialApp(
        home: Scaffold(
          body: ManagerRosterView(
            key: ValueKey(key),
            person: reviewPerson(),
            roster: rows,
            gamePlayers: const {},
            formation: formation,
            onAdd: () {},
            onPlayerTap: (_, _) {},
            onMove: (_, _, _, {targetPosition}) async {},
            onLineupChanged: (_) async {},
            onFormationChanged: (_, slots) async => saved = slots,
          ),
        ),
      );
      await tester.pumpWidget(app('4-2-1-3', 'first'));
      await tester.pumpAndSettle();
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .onChanged!('4-4-2');
      await tester.pumpAndSettle();
      expect(saved, hasLength(11));
      for (final entry in saved!.entries) {
        expect(
          find.descendant(
            of: find.byKey(
              ValueKey('lineup-slot-${entry.value.x}-${entry.value.y}'),
            ),
            matching: find.byKey(ValueKey('player-${entry.key}')),
          ),
          findsOneWidget,
        );
      }
      rows = [
        for (final row in rows.where((r) => r['id'] != 'r3'))
          {...row, 'x': saved![row['id']]!.x, 'y': saved![row['id']]!.y},
      ];
      await tester.pumpWidget(app('4-4-2', 'reopened'));
      await tester.pumpAndSettle();
      expect(find.text('4-4-2'), findsOneWidget);
      expect(find.byKey(const ValueKey('player-r3')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('lineup-slot-0-3')),
          matching: find.byKey(const ValueKey('player-r0')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'v42 migration keeps rows and recovers an incomplete non-default formation',
    () async {
      final directory = await Directory('build/test-databases')
          .create(recursive: true);
      final file = File(
        '${directory.path}/lineup-${DateTime.now().microsecondsSinceEpoch}.db',
      );
      Database? db;
      try {
        db = await SqlService.openCareerDatabase(file.path);
        await db.insert('Persons', reviewPerson().toMap());
        await db.insert('Seasons', reviewSeason().toMap());
        final slots = squadPositions(_eleven(), '4-2-1-3', preserve: false);
        for (final row in _eleven().where((p) => p['id'] != 'r3')) {
          final id = row['id'] as String;
          await db.insert('TeamPlayer', {
            'id': id,
            'personId': 'career',
            'seasonId': 's2026',
            'isBench': 0,
            'x': slots[id]!.x,
            'y': slots[id]!.y,
          });
        }
        final before = await db.query('TeamPlayer');
        await db.execute('DROP TABLE SquadLineup');
        await db.setVersion(42);
        await db.close();
        db = await SqlService.openCareerDatabase(file.path);
        expect(await db.getVersion(), 46);
        expect(await db.query('TeamPlayer'), before);
        final sql = SqlService.withDatabase(db);
        expect(await sql.getSquadFormation('career', 's2026'), '4-2-1-3');
        expect(await db.query('TeamPlayer'), before);
      } finally {
        await db?.close();
        if (await file.exists()) await file.delete();
      }
    },
  );
}
