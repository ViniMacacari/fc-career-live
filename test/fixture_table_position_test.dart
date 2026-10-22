import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Common/FixturePositionIndicator.dart';
import 'package:mcmanager/models/Person.dart';
import 'package:mcmanager/utils/FixtureTablePosition.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

Map<String, Object?> match(int day, {int? position, String? id}) => {
  ...reviewFixture(day),
  'id': id ?? 'match-$day',
  'date': DateTime(2026, 1, day).toIso8601String(),
  'createdAt': DateTime(2026, 1, day, 12).toIso8601String(),
  'position': position,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('Blank positions carry forward through a chain of older matches', () {
    final history = [
      match(4),
      match(3),
      match(2, position: 6),
      match(1, position: 9),
    ];
    final result = FixtureTablePosition.resolve(history.first, history);
    expect(result.position, 6);
    expect(result.previous, 6);
    expect(result.inherited, isTrue);
    expect(result.change, 0);
    expect(result.movement, 'Manteve a posição');
    expect(
      FixtureTablePosition.carryForward(history).map((f) => f['position']),
      [6, 6, 6, 9],
    );
    expect(history.first['position'], isNull);
  });

  test('Movement compares the preceding game of the same tournament', () {
    final first = match(1, position: 7);
    final otherCup = {...match(2, position: 1), 'tournamentId': 'cup'};
    final climbed = match(3, position: 5);
    final dropped = match(4, position: 6);
    final history = [dropped, climbed, otherCup, first];
    expect(FixtureTablePosition.resolve(climbed, history).change, 2);
    expect(
      FixtureTablePosition.resolve(dropped, history).movement,
      'Perdeu 1 posição',
    );
    expect(
      FixtureTablePosition.resolve(climbed, history).movement,
      'Ganhou 2 posições',
    );
  });

  test(
    'Other seasons, clubs, tournaments and careers cannot supply a position',
    () {
      final history = [
        {...match(1, position: 1, id: 'season'), 'seasonId': 'old'},
        {...match(1, position: 2, id: 'club'), 'playerTeamId': 'national'},
        {...match(1, position: 3, id: 'cup'), 'tournamentId': 'other'},
        {...match(1, position: 4, id: 'career'), 'personId': 'other'},
        match(3, position: 1),
      ];
      final result = FixtureTablePosition.resolve(match(2), history);
      expect(result.position, isNull);
      expect(result.change, isNull);
      final first = FixtureTablePosition.resolve(
        match(2, position: 8),
        history,
      );
      expect(first.previous, isNull);
      expect(first.movement, 'Primeira posição registrada');
    },
  );

  test('Same-day games respect creation order and editing excludes itself', () {
    final earlier = {
      ...match(1, position: 8, id: 'early'),
      'createdAt': '2026-01-02T10:00:00',
    };
    final later = {
      ...match(1, position: 6, id: 'late'),
      'createdAt': '2026-01-02T11:00:00',
    };
    final history = [later, earlier];
    expect(
      FixtureTablePosition.resolve({
        ...later,
        'position': null,
      }, history).position,
      8,
    );
    expect(FixtureTablePosition.resolve(earlier, history).previous, isNull);
    expect(
      FixtureTablePosition.resolve(
        {...later, 'createdAt': null, 'position': null},
        [
          {...later, 'createdAt': null},
          {...earlier, 'createdAt': null},
        ],
      ).position,
      8,
    );
  });

  for (final category in PersonCategory.values) {
    test(
      'SQLite carries positions on save, edit and legacy reads (${category.name})',
      () async {
        final db = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        addTearDown(db.close);
        await db.execute('CREATE TABLE Settings(activePersonId TEXT)');
        await SqlService.ensureCompatibleSchema(db);
        await db.execute(
          'ALTER TABLE TeamTransferItem ADD COLUMN releaseDate TEXT',
        );
        await db.execute(
          'ALTER TABLE TeamTransferItem ADD COLUMN movementApplied INTEGER NOT NULL DEFAULT 1',
        );
        final service = SqlService.withDatabase(db);
        final table = category == PersonCategory.player
            ? 'PlayerFixtures'
            : 'ManagerFixtures';
        Map<String, Object?> row(int day, {int? position}) =>
            {
              ...match(day, position: position),
              if (category == PersonCategory.player) ...{
                'goalsCount': 0,
                'assistsCount': 0,
                'savesCount': 0,
                'yellowCards': 0,
                'redCards': 0,
                'isInjured': 0,
              },
              if (category == PersonCategory.player) 'teamPossession': null,
              if (category == PersonCategory.player) 'passAccuracy': null,
            }..removeWhere(
              (key, _) =>
                  category == PersonCategory.player &&
                  (key == 'teamPossession' || key == 'passAccuracy'),
            );
        await service.createFixture(category, row(1, position: 7));
        await service.createFixture(category, row(3));
        expect(
          (await db.query(
            table,
            where: 'id = ?',
            whereArgs: ['match-3'],
          )).single['position'],
          7,
        );
        await service.createFixture(
          category,
          row(3, position: 4),
          update: true,
        );
        expect(
          (await service.getFixtureTablePosition(
            category,
            row(3, position: 4),
          )).change,
          3,
        );
        await service.createFixture(category, row(3), update: true);
        expect(
          (await db.query(
            table,
            where: 'id = ?',
            whereArgs: ['match-3'],
          )).single['position'],
          7,
        );
        await db.insert(table, row(4));
        expect(
          (await service.getFixture(
            category,
            'career',
            'match-4',
          ))?['position'],
          7,
        );
        expect(
          (await service.getFixtures('career', category)).first['position'],
          7,
        );
        await service.createFixture(category, row(2));
        expect(
          (await db.query(
            table,
            where: 'id = ?',
            whereArgs: ['match-2'],
          )).single['position'],
          7,
        );
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'Compact position indicator shows all directions in ${brightness.name}',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final position in [5, 7, 9]) {
          final value = FixtureTablePosition(position: position, previous: 7);
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.4),
                  ),
                  child: FixturePositionIndicator(value: value),
                ),
              ),
            ),
          );
          expect(
            find.byTooltip('${value.movement} · 7º → $positionº'),
            findsOneWidget,
          );
          expect(find.text('$position'), findsOneWidget);
          final icon = tester.widget<Icon>(
            find.byKey(const ValueKey('fixture-position-direction')),
          );
          expect(
            icon.icon,
            position == 7
                ? Icons.horizontal_rule_rounded
                : position < 7
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
          );
          expect(icon.size, lessThan(20));
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
