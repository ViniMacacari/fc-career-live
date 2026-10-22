import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Common/FixtureResultTile.dart';
import 'package:mcmanager/ManagerCareer/PlayersStat/PlayersStatData.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/TeamPage.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileData.dart';
import 'package:mcmanager/ManagerCareer/TeamTransfers/CreateTeamTransferPage.dart';
import 'package:mcmanager/ManagerCareer/TeamTransfers/PlayerFarewellData.dart';
import 'package:mcmanager/ManagerCareer/TeamTransfers/PlayerFarewellDialog.dart';
import 'package:mcmanager/ManagerCareer/TeamTransfers/SelectTransferPlayerPage.dart';
import 'package:mcmanager/models/TeamTransferItem.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/GamePlayers.dart';
import 'package:mcmanager/utils/BackupService.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/SquadLineup.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';
import 'backup_storage_fixture.dart';

class _Translations extends AssetLoader {
  const _Translations(this.values);
  final Map<String, dynamic> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

void main() {
  final person = reviewPerson();
  final player = <String, Object?>{
    'id': 'player',
    'personId': person.id,
    'name': 'Lucas Moura',
    'positionId': '23',
    'overall': 82,
    'potential': 82,
    'foot': 'right',
    'realFace': 0,
    'fromRealPlayer': 0,
  };
  final sale = <String, Object?>{
    'id': 'sale',
    'personId': person.id,
    'seasonId': 's2026',
    'playerInstanceId': 'player',
    'type': 'sell',
    'fromTeamId': person.teamId,
    'fromLeagueId': person.leagueId,
    'toTeamId': 'destination',
    'date': '2026-10-10T00:00:00.000',
  };
  Map<String, Object?> match(
    int i, {
    int goals = 0,
    int assists = 0,
    double? rating,
  }) => {
    ...reviewFixture(i),
    'fixtureId': 'f$i',
    'playerInstanceId': 'player',
    'id': 'p$i',
    'goalsCount': goals,
    'assistsCount': assists,
    'avgRating': rating,
  };
  final rows = [
    match(0, goals: 1, assists: 1, rating: 7),
    {
      ...match(1, goals: 3, rating: 9),
      'playerOfTheMatchId': 'player',
      'isPotmFromMyTeam': 1,
    },
    {
      ...match(3),
      'playerTeamScore': 1,
      'oppositeTeamScore': 1,
      'playerTeamPenaltiesScore': 3,
      'oppositeTeamPenaltiesScore': 4,
    },
  ];
  PlayerFarewellData data({
    List<Map<String, Object?>>? matches,
    Map<String, Object?>? identity,
  }) => PlayerFarewellData.fromRecords(
    person: person,
    transfer: sale,
    player: identity ?? player,
    clubName: 'São Paulo',
    destinationName: 'Flamengo',
    matchRows: matches ?? rows,
    seasons: [reviewSeason()],
    teamNames: const {'fla': 'Flamengo'},
  );
  late Map<String, dynamic> translations;
  late GameCatalog catalog;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    mockBackupStorage();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory('build/farewell-test-docs').absolute.path,
        );
    await EasyLocalization.ensureInitialized();
    translations = jsonDecode(
      await rootBundle.loadString('assets/translations/pt_BR.json'),
    ) as Map<String, dynamic>;
    await loadPreviewFonts();
    catalog = await GameCatalog.load();
    await GamePlayers.load(person.fifaVersion);
  });

  test(
    'Club and agreement date isolate the retrospective across all seasons',
    () {
      final result = data(
        matches: [
          ...rows,
          rows.first,
          {...match(5, goals: 99), 'playerTeamId': 'another-club'},
          {...match(6, goals: 99), 'personId': 'another-career'},
          {...match(7, goals: 99), 'playerInstanceId': 'someone-else'},
          {...match(8, goals: 99), 'date': '2026-10-11T00:00:00.000'},
          {
            ...match(9, goals: 2),
            'date': '2025-03-01T00:00:00.000',
            'seasonId': 's2025',
          },
          {...match(10, goals: 1), 'date': '2026-10-10T23:59:00.000'},
        ],
      );
      expect(result.totals.matches, 5);
      expect(result.totals.goals, 7);
      expect(result.totals.assists, 1);
      expect(result.totals.rating, 8);
      expect(result.totals.motm, 1);
      expect(result.hatTricks, 1);
      expect(result.matches.first.seasonId, 's2025');
      expect(result.highlight?.fixtureId, 'f1');
      expect(result.bestSeason?.id, 's2026');
      expect(result.results[FixtureResult.lose], 2);
      expect(result.retrospective, contains('7 gols e 1 assistência'));
    },
  );

  test(
    'Unknown ratings, scores and absent matches never create achievements',
    () {
      final empty = data(matches: []);
      expect(empty.totals.rating, isNull);
      expect(empty.highlight, isNull);
      expect(empty.bestSeason, isNull);
      expect(empty.retrospective, contains('Ainda não há atuações'));
      final unknown = data(
        matches: [
          {...match(0), 'playerTeamScore': null},
        ],
      );
      expect(unknown.results.values.fold(0, (a, b) => a + b), 0);
      expect(unknown.highlight, isNull);
      final details = data(
        matches: [
          {
            ...match(0),
            'goalsCount': null,
            'goalDetails': jsonEncode([
              {'id': 'g', 'minute': 50},
            ]),
          },
        ],
      );
      expect(details.totals.goals, 1);
    },
  );

  test('Only club sales qualify, including a sale from a loan', () {
    for (final type in TeamTransferType.values) {
      expect(
        PlayerFarewellData.isClubSale({
          ...sale,
          'type': type.name,
        }, person.teamId),
        type == TeamTransferType.sell || type == TeamTransferType.sellFromLoan,
      );
    }
    expect(
      PlayerFarewellData.isClubSale({
        ...sale,
        'fromTeamId': 'other',
      }, person.teamId),
      isFalse,
    );
  });

  Future<Database> database() async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await SqlService.ensureCompatibleSchema(db);
    await SqlService.ensureSeasonClosureSchema(db);
    await SquadLineup.ensureSchema(db);
    for (final (name, type) in [
      ('releaseDate', 'TEXT'),
      ('movementApplied', 'INTEGER'),
      ('keepInSquad', 'INTEGER'),
    ]) {
      await db.execute('ALTER TABLE TeamTransferItem ADD COLUMN $name $type');
    }
    await db.insert('Persons', person.toMap());
    await db.insert('Seasons', reviewSeason().toMap());
    await db.insert('CustomCreatedPlayer', player);
    await db.insert('TeamPlayer', {
      'id': 'roster',
      'personId': person.id,
      'seasonId': 's2026',
      'playerId': 'player',
      'isBench': 0,
      'overall': 82,
      'shirtNumber': 7,
      'wage': 50000,
      'yearlyWage': 2600000,
      'marketValue': 18000000,
      'x': 50,
      'y': 32,
    });
    for (final row in rows) {
      await db.insert('ManagerFixtures', {
        ...reviewFixture(int.parse('${row['fixtureId']}'.substring(1))),
        'playerOfTheMatchId': row['playerOfTheMatchId'],
        'isPotmFromMyTeam': row['isPotmFromMyTeam'],
      });
      await db.insert('ManagerFixturePlayerPerformances', {
        for (final key in [
          'id',
          'personId',
          'fixtureId',
          'playerInstanceId',
          'goalsCount',
          'assistsCount',
          'avgRating',
        ])
          key: row[key],
      });
    }
    return db;
  }

  Map<String, Object?> pendingSale({String id = 'pending'}) => {
    ...sale,
    'id': id,
    'date': '2026-01-01T00:00:00.000',
    'releaseDate': '2026-08-01T00:00:00.000',
    'transferValue': 23000000,
    'movementApplied': 0,
    'keepInSquad': 0,
  };

  Future<PlayersStatData> statistics(SqlService sql) async => PlayersStatData(
    seasons: await sql.getSeasons(person.id),
    players: {
      for (final row in await sql.getCustomPlayers(person.id))
        row['id'] as String: row,
    },
    roster: await sql.getManagerStatisticsRoster(person.id),
    matches: (await sql.getManagerStatisticsMatchRows(person.id))
        .map(PlayerMatchData.new)
        .toList(),
    transfers: await sql.getTeamTransfers(person.id),
    catalog: catalog,
    realPlayers: const {},
    tournamentNames: const {},
  );

  test(
    'Manual departure archives every roster field and preserves player records',
    () async {
      final db = await database();
      addTearDown(db.close);
      final sql = SqlService.withDatabase(db);
      await db.update('CustomCreatedPlayer', {
        'customAvatarFilePath': 'players/lucas.png',
      });
      await db.insert('Seasons', reviewSeason(id: 's2025', year: 2025).toMap());
      await db.insert('TeamPlayer', {
        'id': 'older-roster',
        'personId': person.id,
        'seasonId': 's2025',
        'playerId': 'player',
        'isBench': 1,
        'overall': 78,
        'shirtNumber': 10,
      });
      final before = (await db.query(
        'TeamPlayer',
        where: 'id = ?',
        whereArgs: ['roster'],
      )).single;
      final identity = (await db.query('CustomCreatedPlayer')).single;
      final performances = await db.query('ManagerFixturePlayerPerformances');
      final departure = (await sql.removeTeamPlayer(person.id, 'roster'))!;
      expect(jsonDecode(departure['rosterJson'] as String), before);
      expect(departure['transferId'], isNull);
      expect(departure['departureDate'], '2026-04-10T00:00:00.000');
      expect(await db.query('TeamTransferItem'), isEmpty);
      expect(await db.query('CustomCreatedPlayer'), [identity]);
      expect(await db.query('ManagerFixturePlayerPerformances'), performances);
      expect((await db.query('TeamPlayer')).single['id'], 'older-roster');
      final seasons = await sql.getPlayerSeasonRows(person.id, 'player');
      expect(seasons.map((r) => r['seasonId']), ['s2026', 's2025']);
      for (final key in before.keys) {
        expect(seasons.first[key], before[key]);
      }
      final stats = await statistics(sql);
      final entry = stats
          .entries(person, const PlayersStatFilters(), const PlayersStatSort())
          .single;
      expect(entry.departed, isTrue);
      expect(transferCardLabel(entry.exit!), 'Saída do elenco');
      expect(entry.totals[PlayersStatMetric.matches], 3);
      expect(entry.totals[PlayersStatMetric.goals], 4);
      expect(stats.profileRow(entry, 's2026')['shirtNumber'], 7);
      expect(stats.profileRow(entry, 's2026')['wage'], 50000);
      expect(
        stats.profileRow(entry, 's2026')['customAvatarFilePath'],
        'players/lucas.png',
      );
      final farewell = await PlayerFarewellData.loadDeparture(
        person,
        departure,
        sql: sql,
        catalog: catalog,
      );
      expect(farewell.name, 'Lucas Moura');
      expect(farewell.photo, 'players/lucas.png');
      expect(farewell.destinationId, isNull);
      expect(farewell.totals.matches, 3);
      expect(farewell.totals.goals, 4);
      expect(await sql.removeTeamPlayer(person.id, 'roster'), isNull);
      expect(await db.query('TeamPlayerDeparture'), hasLength(1));
    },
  );

  test(
    'A departed player without appearances still appears in team statistics',
    () async {
      final db = await database();
      addTearDown(db.close);
      final sql = SqlService.withDatabase(db);
      await db.delete('ManagerFixturePlayerPerformances');
      await sql.removeTeamPlayer(person.id, 'roster');
      final stats = await statistics(sql);
      final entry = stats
          .entries(person, const PlayersStatFilters(), const PlayersStatSort())
          .single;
      expect(entry.name, 'Lucas Moura');
      expect(entry.departed, isTrue);
      expect(entry.totals[PlayersStatMetric.matches], 0);
      expect(entry.rosterRow?['overall'], 82);
    },
  );

  test(
    'Pending exits are restricted to the same player, career, club and season',
    () async {
      final db = await database();
      addTearDown(db.close);
      final sql = SqlService.withDatabase(db);
      final alternatives = [
        {'playerInstanceId': 'other-player'},
        {'personId': 'other-career'},
        {'fromTeamId': 'other-club'},
        {'seasonId': 'other-season'},
        {'toTeamId': person.teamId, 'type': 'buy'},
        {'movementApplied': 1},
        {'releaseDate': null},
        {'releaseDate': 'invalid'},
      ];
      await db.insert('TeamTransferItem', pendingSale());
      for (var i = 0; i < alternatives.length; i++) {
        await db.insert('TeamTransferItem', {
          ...pendingSale(id: 'invalid$i'),
          ...alternatives[i],
        });
      }
      expect(
        (await sql.getPendingPlayerTransfers(
          person,
          'player',
          seasonId: 's2026',
        )).map((r) => r['id']),
        ['pending'],
      );
      for (var i = 0; i < alternatives.length; i++) {
        await expectLater(
          sql.removeTeamPlayer(person.id, 'roster', transferId: 'invalid$i'),
          throwsStateError,
        );
      }
      expect(await db.query('TeamPlayer'), hasLength(1));
      expect(await db.query('TeamPlayerDeparture'), isEmpty);
    },
  );

  test(
    'Linking preserves the deal and includes games played after the agreement',
    () async {
      final db = await database();
      addTearDown(db.close);
      final sql = SqlService.withDatabase(db);
      await db.insert('TeamTransferItem', pendingSale());
      final departure = (await sql.removeTeamPlayer(
        person.id,
        'roster',
        transferId: 'pending',
      ))!;
      final linked = (await db.query('TeamTransferItem')).single;
      expect(linked['movementApplied'], 1);
      expect(linked['date'], pendingSale()['date']);
      expect(linked['releaseDate'], pendingSale()['releaseDate']);
      expect(linked['actualReleaseDate'], departure['departureDate']);
      expect(linked['transferValue'], 23000000);
      expect(departure['transferId'], 'pending');
      final farewell = await PlayerFarewellData.loadDeparture(
        person,
        departure,
        sql: sql,
        catalog: catalog,
      );
      expect(farewell.destinationId, 'destination');
      expect(farewell.totals.matches, 3);
      expect(farewell.totals.goals, 4);
      await sql.deleteTeamTransfer(person.id, 'pending');
      final stats = await statistics(sql);
      final entry = stats
          .entries(person, const PlayersStatFilters(), const PlayersStatSort())
          .single;
      expect(entry.exit?['toTeamId'], 'destination');
      expect(entry.exitValue, 23000000);
    },
  );

  test(
    'Archive failure rolls back both the linked transfer and roster deletion',
    () async {
      final db = await database();
      addTearDown(db.close);
      final sql = SqlService.withDatabase(db);
      await db.insert('TeamTransferItem', pendingSale());
      await db.execute(
        '''CREATE TRIGGER fail_archive BEFORE INSERT ON TeamPlayerDeparture
      BEGIN SELECT RAISE(ABORT, 'Archive unavailable'); END''',
      );
      await expectLater(
        sql.removeTeamPlayer(person.id, 'roster', transferId: 'pending'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('TeamPlayer'), hasLength(1));
      expect(await db.query('TeamPlayerDeparture'), isEmpty);
      final linked = (await db.query('TeamTransferItem')).single;
      expect(linked['movementApplied'], 0);
      expect(linked['actualReleaseDate'], isNull);
    },
  );

  test('Editing or reaching the scheduled date never removes a returned player again', () async {
    final db = await database();
    addTearDown(db.close);
    final sql = SqlService.withDatabase(db);
    await db.insert('TeamTransferItem', pendingSale());
    await sql.removeTeamPlayer(person.id, 'roster', transferId: 'pending');
    await sql.saveTeamTransfer({
      ...pendingSale(),
      'transferValue': 25000000,
    }, update: true);
    expect(
      await db.query('TeamPlayer'),
      isEmpty,
      reason: 'Editing must not restore the departed player',
    );
    await db.insert('TeamPlayer', {
      'id': 'returned',
      'personId': person.id,
      'seasonId': 's2026',
      'playerId': 'player',
      'isBench': 1,
      'overall': 84,
    });
    await sql.saveTeamTransfer({
      ...pendingSale(),
      'releaseDate': '2026-09-01T00:00:00.000',
    }, update: true);
    await db.insert('ManagerFixtures', reviewFixture(9));
    await sql.applyDueTeamTransfers(person.id);
    expect((await db.query('TeamPlayer')).single['id'], 'returned');
    final stats = await statistics(sql);
    final entry = stats
        .entries(person, const PlayersStatFilters(), const PlayersStatSort())
        .single;
    expect(entry.departed, isFalse);
    expect(entry.rosterRow?['overall'], 84);
    expect(await db.query('TeamPlayerDeparture'), hasLength(1));
  });

  test('Ordinary sales preserve the same full season snapshot', () async {
    final db = await database();
    addTearDown(db.close);
    final sql = SqlService.withDatabase(db);
    final original = (await db.query('TeamPlayer')).single;
    await sql.saveTeamTransfer(sale);
    final archive = (await db.query('TeamPlayerDeparture')).single;
    expect(jsonDecode(archive['rosterJson'] as String), original);
    expect(archive['transferId'], 'sale');
    expect(
      (await sql.getPlayerSeasonRows(
        person.id,
        'player',
      )).single['marketValue'],
      18000000,
    );
  });

  test(
    'Editing a purchase preserves the departure of its included player',
    () async {
      final db = await database();
      addTearDown(db.close);
      final sql = SqlService.withDatabase(db);
      await db.insert('CustomCreatedPlayer', {...player, 'id': 'incoming'});
      final purchase = {
        ...pendingSale(id: 'purchase'),
        'type': 'buy',
        'playerInstanceId': 'incoming',
        'fromTeamId': 'destination',
        'toTeamId': person.teamId,
      };
      final exchange = pendingSale(id: 'purchase:exchange');
      await sql.saveTeamTransfer(purchase, included: exchange);
      final departure = (await sql.removeTeamPlayer(
        person.id,
        'roster',
        transferId: 'purchase:exchange',
      ))!;
      await db.insert('TeamPlayer', {
        'id': 'returned',
        'personId': person.id,
        'seasonId': 's2026',
        'playerId': 'player',
        'isBench': 1,
      });
      await sql.saveTeamTransfer(purchase, included: exchange, update: true);
      final saved = (await sql.getTeamTransferExchange(person.id, 'purchase'))!;
      expect(saved['actualReleaseDate'], departure['departureDate']);
      expect(saved['movementApplied'], 1);
      await db.insert('ManagerFixtures', reviewFixture(9));
      await sql.applyDueTeamTransfers(person.id);
      final roster = await db.query('TeamPlayer');
      expect(
        roster.map((r) => r['playerId']),
        containsAll(['player', 'incoming']),
      );
      expect(await db.query('TeamPlayerDeparture'), hasLength(1));
    },
  );

  test(
    'Departure snapshots and linked dates survive backup restoration',
    () async {
      final db = await database();
      addTearDown(db.close);
      final sql = SqlService.withDatabase(db);
      await db.insert('TeamTransferItem', pendingSale());
      await sql.removeTeamPlayer(person.id, 'roster', transferId: 'pending');
      final before = (await db.query('TeamPlayerDeparture')).single;
      final lineup = await db.query('SquadLineup');
      final backup = await BackupService(database: () async => db)
          .generateBackup(includeImages: false);
      final restored = await database();
      addTearDown(restored.close);
      final report = await BackupService(database: () async => restored)
          .restoreBackup(backup);
      expect(report.skippedTables, isEmpty);
      expect(report.skippedRows, 0);
      expect(await restored.query('TeamPlayerDeparture'), [before]);
      expect(await restored.query('SquadLineup'), lineup);
      expect(await restored.query('TeamPlayer'), isEmpty);
      expect(
        (await restored.query('TeamTransferItem')).single['actualReleaseDate'],
        before['departureDate'],
      );
      expect(
        (await SqlService.withDatabase(
          restored,
        ).getPlayerSeasonRows(person.id, 'player')).single['overall'],
        82,
      );
    },
  );

  test('Saved sale preserves statistics after removal from roster and deduplicates backups', () async {
    final db = await database();
    addTearDown(db.close);
    final sql = SqlService.withDatabase(db);
    await db.insert('ManagerFixturePlayerPerformances', {
      ...{
        for (final key in [
          'personId',
          'fixtureId',
          'playerInstanceId',
          'goalsCount',
          'assistsCount',
          'avgRating',
        ])
          key: rows.first[key],
      },
      'id': 'newer-copy',
      'goalsCount': 2,
    });
    await sql.saveTeamTransfer(sale);
    expect(await db.query('TeamPlayer'), isEmpty);
    final saved = await PlayerFarewellData.load(
      person,
      'sale',
      sql: sql,
      catalog: catalog,
    );
    expect(saved?.totals.matches, 3);
    expect(saved?.totals.goals, 5);
    expect(saved?.name, 'Lucas Moura');
    await db.update('TeamTransferItem', {'id': 'purchase', 'type': 'buy'});
    expect(
      await PlayerFarewellData.load(
        person,
        'purchase',
        sql: sql,
        catalog: catalog,
      ),
      isNull,
    );
    await db.insert('TeamTransferItem', {...sale, 'id': 'purchase:exchange'});
    expect(
      (await PlayerFarewellData.load(
        person,
        'purchase',
        sql: sql,
        catalog: catalog,
      ))?.playerId,
      'player',
    );
  });

  Widget app(Widget child, {double scale = 1, bool reducedMotion = false}) =>
      EasyLocalization(
        supportedLocales: const [Locale('pt', 'BR')],
        startLocale: const Locale('pt', 'BR'),
        path: 'assets/translations',
        assetLoader: _Translations(translations),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: managerDarkTheme,
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: reducedMotion,
              ),
              child: child!,
            ),
            home: child,
          ),
        ),
      );
  void viewport(WidgetTester tester, double width, double height) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> preview(WidgetTester tester, GlobalKey key, String name) async {
    final path = Platform.environment['PROFILE_PREVIEW_DIR'];
    if (path == null) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(path).create(recursive: true);
      await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> settleSave(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(PlayerFarewellDialog).evaluate().isNotEmpty ||
          find.byType(CreateTeamTransferPage).evaluate().isEmpty ||
          find.text('Salvar').evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  for (final mode in ['linked', 'unlinked', 'no-transfer']) {
    testWidgets(
      'Roster removal $mode confirms the link and shows the farewell after commit',
      (tester) async {
        final compact = mode == 'no-transfer';
        viewport(tester, compact ? 320 : 390, compact ? 640 : 844);
        final db = (await tester.runAsync(database))!;
        addTearDown(db.close);
        final sql = SqlService.withDatabase(db);
        final destination = catalog
            .teams(person.fifaVersion)
            .firstWhere(
              (t) => t.leagueId == person.leagueId && t.id != person.teamId,
            );
        await tester.runAsync(() async {
          if (compact) await db.update('TeamPlayer', {'isBench': 1});
          if (mode != 'no-transfer') {
            await db.insert('TeamTransferItem', {
              ...pendingSale(),
              'toTeamId': destination.id,
              'toLeagueId': destination.leagueId,
            });
          }
        });
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: app(
              TeamPage(person: person, sql: sql),
              scale: compact ? 1.4 : 1,
            ),
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('player-roster')));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text('Remover jogador'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(
          find.text('Vincular a uma transferência em aberto?'),
          findsOneWidget,
        );
        expect(
          await tester.runAsync(() => db.query('TeamPlayerDeparture')),
          isEmpty,
        );
        if (mode == 'linked') {
          await tester.tap(find.byKey(const ValueKey('departure-transfer')));
          await tester.pumpAndSettle();
          await tester.tap(find.textContaining('01/08/2026').last);
          await tester.pumpAndSettle();
        } else if (!compact) {
          expect(find.text('Sem vínculo'), findsOneWidget);
        }
        await preview(tester, key, 'departure_confirmation_$mode');
        await tester.runAsync(() async {
          await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pump();
        expect(find.byType(PlayerFarewellDialog), findsOneWidget);
        expect(
          tester.binding.hasScheduledFrame,
          isTrue,
          reason: 'Farewell animates',
        );
        await tester.pumpAndSettle();
        final farewell = tester
            .widget<PlayerFarewellDialog>(find.byType(PlayerFarewellDialog))
            .data;
        expect(farewell.name, 'Lucas Moura');
        expect(farewell.totals.matches, 3);
        expect(farewell.totals.goals, 4);
        expect(
          farewell.destinationId,
          mode == 'linked' ? destination.id : null,
        );
        expect(await tester.runAsync(() => db.query('TeamPlayer')), isEmpty);
        final archives = (await tester.runAsync(
          () => db.query('TeamPlayerDeparture'),
        ))!;
        expect(
          archives.single['transferId'],
          mode == 'linked' ? 'pending' : null,
        );
        final transfers = (await tester.runAsync(
          () => db.query('TeamTransferItem'),
        ))!;
        if (!compact) {
          expect(transfers.single['movementApplied'], mode == 'linked' ? 1 : 0);
        } else {
          expect(transfers, isEmpty);
        }
        await preview(tester, key, 'departure_farewell_$mode');
        expect(
          find.byKey(const ValueKey('close-player-farewell')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('close-player-farewell')));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerFarewellDialog), findsNothing);
        expect(find.byKey(const ValueKey('player-roster')), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pump(const Duration(seconds: 11));
        }
      },
    );
  }

  for (final (width, height, scale) in [
    (390.0, 844.0, 1.0),
    (320.0, 640.0, 1.4),
  ]) {
    testWidgets('Farewell animates and scrolls without overflow at $width px', (
      tester,
    ) async {
      viewport(tester, width, height);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showPlayerFarewell(context, data()),
                  child: const Text('Abrir'),
                ),
              ),
            ),
            scale: scale,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final context = tester.element(find.byType(Scaffold));
        await precacheImage(
          const AssetImage('assets/branding/fc-career-live-icon.png'),
          context,
        );
        await precacheImage(
          const AssetImage('assets/images/clubLogos/sao-paulo.png'),
          context,
        );
      });
      await tester.tap(find.text('Abrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.byType(PlayerFarewellDialog), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpAndSettle();
      await preview(tester, key, 'farewell_$width');
      final scroll = find.byKey(const ValueKey('farewell-scroll'));
      await tester.dragUntilVisible(
        find.text('Momentos que ficam'),
        scroll,
        const Offset(0, -170),
      );
      await tester.pumpAndSettle();
      await preview(tester, key, 'farewell_memories_$width');
      expect(find.text('Temporada de destaque · 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('close-player-farewell')));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerFarewellDialog), findsNothing);
    });
  }

  testWidgets('Reduced motion shows final goalkeeper statistics immediately', (
    tester,
  ) async {
    viewport(tester, 390, 844);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: PlayerFarewellDialog(
            data: data(
              identity: {...player, 'positionId': '0'},
              matches: [
                {...match(0), 'saves': 8, 'penaltySaves': 1},
              ],
            ),
          ),
        ),
        reducedMotion: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Defesas'), findsOneWidget);
    expect(find.text('Pênaltis defendidos'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'New sale shows farewell once after commit; editing it does not replay',
    (tester) async {
      viewport(tester, 390, 844);
      final db = (await tester.runAsync(database))!;
      addTearDown(db.close);
      final sql = SqlService.withDatabase(db);
      Map<String, Object?>? existing;
      var notifications = 0;
      Object? returned;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Transferência'),
                onPressed: () async {
                  returned = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreateTeamTransferPage(
                        person: person,
                        season: reviewSeason(),
                        roster: [
                          {'playerId': 'player'},
                        ],
                        names: const {'player': 'Lucas Moura'},
                        existing: existing,
                        initialPlayer: TransferPlayerChoice(
                          id: 'player',
                          name: 'Lucas Moura',
                          custom: player,
                        ),
                        sql: sql,
                        transferNotifier: (_, _) async {
                          notifications++;
                          if (notifications == 1) {
                            throw StateError('Notification unavailable');
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transferência'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comprar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vender'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transferido Para'));
      await tester.pumpAndSettle();
      final destination = catalog
          .teams(person.fifaVersion)
          .firstWhere(
            (t) => t.leagueId == person.leagueId && t.id != person.teamId,
          );
      await tester.enterText(find.byType(TextField), destination.label);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, destination.label));
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('save-team-transfer'));
      await tester.dragUntilVisible(
        save,
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.runAsync(
        () => db.execute('''CREATE TRIGGER fail_sale
        BEFORE INSERT ON TeamTransferItem BEGIN
          SELECT RAISE(ABORT, 'Save failed'); END'''),
      );
      await tester.runAsync(() async {
        await tester.tap(save);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(PlayerFarewellDialog), findsNothing);
      expect(
        await tester.runAsync(() => db.query('TeamTransferItem')),
        isEmpty,
      );
      expect(notifications, 0);
      expect(
        find.textContaining('Erro ao salvar transferência:'),
        findsOneWidget,
      );
      await tester.runAsync(() => db.execute('DROP TRIGGER fail_sale'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(save);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await settleSave(tester);
      expect(find.byType(PlayerFarewellDialog), findsOneWidget);
      existing = (await tester.runAsync(() => db.query('TeamTransferItem')))!
          .single;
      expect(existing['type'], 'sell');
      expect(notifications, 1);
      expect(returned, isNull);
      expect(await tester.runAsync(() => db.query('TeamPlayer')), isEmpty);
      await tester.tap(find.byKey(const ValueKey('close-player-farewell')));
      await settleSave(tester);
      expect(returned, true);
      await tester.runAsync(() async {
        await tester.tap(find.text('Transferência'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await settleSave(tester);
      await tester.dragUntilVisible(
        save,
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.runAsync(() async {
        await tester.tap(save);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await settleSave(tester);
      expect(find.byType(PlayerFarewellDialog), findsNothing);
      expect(notifications, 2);
      expect(
        (await tester.runAsync(() => db.query('TeamTransferItem')))!,
        hasLength(1),
      );
      existing = null;
      await tester.tap(find.text('Transferência'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transferido De'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), destination.label);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, destination.label));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        save,
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.runAsync(() async {
        await tester.tap(save);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PlayerFarewellDialog), findsNothing);
      await tester.tap(find.byKey(const ValueKey('skip-previous-club-stats')));
      await settleSave(tester);
      expect(find.byType(CreateTeamTransferPage), findsNothing);
      expect(notifications, 3);
      expect(
        (await tester.runAsync(() => db.query('TeamTransferItem')))!,
        hasLength(2),
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 11));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    },
  );
}
