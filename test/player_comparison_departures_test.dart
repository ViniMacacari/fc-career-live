import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mcmanager/ManagerCareer/Fixtures/SelectTeamPlayerPage.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/ComparePlayers/ComparePlayers.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileData.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data_frames.dart';
import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  final person = reviewPerson();
  final season = reviewSeason(id: 's2028', year: 2028);
  late Database db;
  late SqlService sql;

  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    await loadPreviewFonts();
    await GameCatalog.load();
  });

  Future<void> seed() async {
    db = await SqlService.openCareerDatabase(inMemoryDatabasePath);
    sql = SqlService.withDatabase(db);
    await db.insert('Persons', person.toMap());
    await db.insert('Seasons', season.toMap());
    for (final (id, name) in [
      ('stays', 'Continua no clube'),
      ('sold', 'Saiu em julho'),
      ('legacy', 'Saída antiga'),
      ('other-season', 'Só em 2029'),
      ('unrelated', 'Sem passagem no clube'),
    ]) {
      await db.insert('CustomCreatedPlayer', {
        'id': id,
        'personId': person.id,
        'name': name,
        'positionId': '25',
        'overall': 78,
        'potential': 85,
        'realFace': 0,
        'fromRealPlayer': 0,
        'foot': 'Right',
      });
    }
    for (final id in ['stays', 'sold']) {
      await db.insert('TeamPlayer', {
        'id': 'roster-$id',
        'playerId': id,
        'personId': person.id,
        'seasonId': season.id,
        'isBench': 1,
        'overall': 78,
        'marketValue': 5000000,
        'wage': 2500,
        'shirtNumber': 9,
      });
    }
    for (var i = 0; i < 2; i++) {
      await db.insert('ManagerFixtures', {
        ...reviewFixture(i, season: season.id),
        'date': '2028-0${i + 5}-10',
      });
      for (final id in ['sold', 'legacy']) {
        await db.insert('ManagerFixturePlayerPerformances', {
          'id': 'p-$id-$i',
          'personId': person.id,
          'fixtureId': 'f$i',
          'playerInstanceId': id,
          'goalsCount': i + 1,
          'assistsCount': 1,
          'avgRating': 8.0,
          'apiStats': '{"npkExpectedGoals":1.25,"expectedAssists":0.4}',
        });
      }
    }
    await sql.saveTeamTransfer({
      'id': 'sale',
      'personId': person.id,
      'seasonId': season.id,
      'playerInstanceId': 'sold',
      'type': 'sell',
      'date': '2028-07-01',
      'fromTeamId': person.teamId,
      'toTeamId': 'other',
    });
    await db.insert('Seasons', reviewSeason(id: 's2029', year: 2029).toMap());
    await db.insert('TeamPlayer', {
      'id': 'roster-2029',
      'playerId': 'other-season',
      'personId': person.id,
      'seasonId': 's2029',
      'isBench': 1,
      'overall': 80,
    });
  }

  test('Season comparison includes a July sale, its archived values and legacy appearances', () async {
    await seed();
    addTearDown(db.close);
    final before = await db.query('TeamPlayer');
    final rows = await sql.getComparisonPlayerRows(person.id);
    expect(
      rows
          .where((r) => r['seasonId'] == season.id)
          .map((r) => r['playerId'])
          .toSet(),
      {'stays', 'sold', 'legacy'},
    );
    final former = rows.singleWhere((r) => r['playerId'] == 'sold');
    expect(former['customName'], 'Saiu em julho');
    expect(former['marketValue'], 5000000);
    expect(former['wage'], 2500);
    expect(former['shirtNumber'], 9);
    expect(former['departureDate'], isNotNull);
    expect(rows.any((r) => r['playerId'] == 'unrelated'), isFalse);
    final profile = await PlayerProfileData.load(person, 'sold', sql: sql);
    final total = profile.totals(seasonId: season.id);
    expect(total.matches, 2);
    expect(total.goals, 3);
    expect(total.assists, 2);
    expect(total.rating, 8);
    expect(
      profile
          .filtered(seasonId: season.id)
          .first
          .performance
          .apiStats['expectedAssists'],
      .4,
    );
    expect(
      await db.query('TeamPlayer'),
      before,
      reason: 'Comparison never rebuilds the current squad',
    );
  });

  test(
    'Returning player has one candidate per season and retains all appearances',
    () async {
      await seed();
      addTearDown(db.close);
      await db.insert('TeamPlayer', {
        'id': 'returned',
        'playerId': 'sold',
        'personId': person.id,
        'seasonId': season.id,
        'isBench': 1,
        'overall': 80,
        'marketValue': 9000000,
      });
      final rows = await sql.getComparisonPlayerRows(person.id);
      final former = rows
          .where((r) => r['playerId'] == 'sold' && r['seasonId'] == season.id)
          .toList();
      expect(former, hasLength(1));
      expect(former.single['rosterId'], 'returned');
      expect(former.single['marketValue'], 9000000);
      expect(
        (await sql.getManagerPlayerStatistics(
          person.id,
          seasonId: season.id,
        )).singleWhere((r) => r['playerId'] == 'sold')['goals'],
        3,
      );
    },
  );

  testWidgets(
    'Comparison selector includes former players only in the chosen season and adds their statistics',
    (tester) async {
      await tester.runAsync(seed);
      addTearDown(db.close);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: managerDarkTheme,
          home: ComparePlayersPage(
            person: person,
            sql: sql,
            initialSeasonId: season.id,
            initialPlayer: const {'playerId': 'stays'},
          ),
        ),
      );
      await settleDataFrames(tester);
      await tester.tap(find.byKey(const ValueKey('compare-add')));
      await settleDataFrames(tester);
      final selector = tester.widget<SelectTeamPlayerPage>(
        find.byType(SelectTeamPlayerPage),
      );
      expect(selector.roster.map((r) => r['playerId']).toSet(), {
        'stays',
        'sold',
        'legacy',
      });
      expect(find.text('Saiu em julho'), findsOneWidget);
      expect(find.text('Saída antiga'), findsOneWidget);
      expect(find.text('Só em 2029'), findsNothing);
      expect(selector.usedIds, {'stays'});
      await tester.tap(find.text('Saiu em julho'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await settleDataFrames(tester);
      expect(find.byType(SelectTeamPlayerPage), findsNothing);
      expect(find.text('Saiu em julho'), findsWidgets);
      expect(find.byTooltip('Trocar jogador'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
