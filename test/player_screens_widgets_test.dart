import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/ComparePlayers/ComparePlayers.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/ViewPlayerPage.dart';
import 'package:mcmanager/models/ManagerFixture.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data_frames.dart';
import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';

class _Translations extends AssetLoader {
  const _Translations(this.values);
  final Map<String, dynamic> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

const _players = [
  ('brenner', 'Brenner', '25', 9),
  ('calleri', 'Calleri', '25', 10),
  ('lucas', 'Lucas Moura', '18', 7),
  ('arboleda', 'Arboleda', '5', 5),
  ('rafael', 'Rafael', '0', 1),
];

Future<void> _seed(Database db, SqlService sql) async {
  final person = reviewPerson();
  await db.insert('Persons', person.toMap());
  final opponents = GameCatalog.current!
      .teams(person.fifaVersion)
      .where((t) => t.leagueId == '1014' && t.id != person.teamId)
      .take(8)
      .toList();
  for (final (id, name, position, shirt) in _players) {
    await db.insert('CustomCreatedPlayer', {
      'id': id,
      'personId': person.id,
      'name': name,
      'positionId': position,
      'overall': 80,
      'potential': 86,
      'realFace': 0,
      'fromRealPlayer': 0,
      'foot': 'Right',
      'height': 180 + shirt,
      'weight': 75 + shirt,
      'firstSeasonAge': 20 + shirt,
    });
  }
  final performances = <ManagerFixturePlayerPerformance>[];
  for (final (season, year) in [('s2027', 2027), ('s2028', 2028)]) {
    await db.insert('Seasons', reviewSeason(id: season, year: year).toMap());
    for (final (index, (id, _, _, shirt)) in _players.indexed) {
      await db.insert('TeamPlayer', {
        'id': 'roster-$season-$id',
        'playerId': id,
        'personId': person.id,
        'seasonId': season,
        'isBench': 0,
        'overall': 76 + index + (year - 2027) * 3,
        'marketValue': (8 + index * 2 + (year - 2027) * 6) * 1000000,
        'wage': 20000 + index * 5000,
        'shirtNumber': shirt,
      });
    }
    for (var i = 0; i < 12; i++) {
      final fixtureId = '$season-f$i';
      final date = DateTime(year, 2, 4).add(Duration(days: i * 21));
      final opponent = opponents[i % opponents.length];
      final played = i != 4 && i != 9;
      final goals = played ? const [0, 1, 2, 0, 0, 1, 3, 0, 1, 0, 2, 1][i] : 0;
      final assists = played
          ? const [1, 0, 0, 1, 0, 1, 0, 0, 0, 0, 1, 0][i]
          : 0;
      final others = (i + year) % 3;
      final conceded = const [1, 0, 2, 1, 2, 1, 0, 3, 1, 1, 0, 2][i];
      final scored = goals + others;
      await db.insert('ManagerFixtures', {
        ...reviewFixture(i, season: season),
        'id': fixtureId,
        'date': date.toIso8601String(),
        'tournamentId': i % 4 == 3 ? '86' : 'league:1014',
        'oppositeTeamId': opponent.id,
        'oppositeTeamLeagueId': opponent.leagueId,
        'location': i.isEven ? 'home' : 'away',
        'playerTeamScore': scored,
        'oppositeTeamScore': conceded,
        'playerOfTheMatchId': played && goals >= 2 ? 'brenner' : null,
        'isPotmFromMyTeam': played && goals >= 2 ? 1 : null,
        'captaincy': i % 3 == 0 && played
            ? jsonEncode({'initialPlayerId': 'brenner'})
            : null,
        'opponentGoalDetails': encodeOpponentGoals([
          for (var g = 0; g < conceded; g++)
            OpponentGoalDetails(scorerName: 'Rival', minute: 20 + g * 31),
        ]),
      });
      if (played) {
        final subbedOff = i % 4 == 1;
        final cameOn = i == 7;
        performances.add(
          ManagerFixturePlayerPerformance(
            personId: person.id,
            fixtureId: fixtureId,
            playerInstanceId: 'brenner',
            goalsCount: goals,
            assistsCount: assists,
            avgRating: 6.2 + ((i * 7 + year) % 30) / 10,
            shotsCount: goals + 2 + i % 3,
            shotAccuracy: 40 + (i * 9) % 50,
            passes: 18 + i * 2,
            passAccuracy: 70 + (i * 3) % 25,
            keyPasses: i % 4,
            dribbles: 2 + i % 5,
            dribblesAccuracy: 45 + (i * 7) % 40,
            tackles: i % 3,
            tacklesAccuracy: 50 + (i * 5) % 40,
            yellowCardDetails: i == 5
                ? [PerformanceTimeDetails(minute: 62)]
                : null,
            apiStats: i.isEven
                ? {
                    'npkExpectedGoals': .35 + i * .08,
                    'expectedAssists': .1 + i * .03,
                    'shotsOnTarget': goals + 1,
                    'shots': goals + 2 + i % 3,
                    'passesCompleted': 14 + i,
                    'passes': 18 + i * 2,
                  }
                : const {},
            goalDetails: [
              for (var g = 0; g < goals; g++)
                PerformanceGoalDetails(
                  minute: 9 + g * 27 + i * 3,
                  assistantId: g == 0 ? 'lucas' : 'calleri',
                  type: [
                    if (g == 1 && i == 6)
                      GoalType.penalty
                    else if (g == 0 && i.isOdd)
                      GoalType.header
                    else
                      GoalType.openplay,
                  ],
                  fieldLocation: GoalShotLocation(
                    .35 + ((i + g) % 4) * .1,
                    .78 + ((i * g) % 3) * .06,
                  ),
                  goalLocation: GoalShotLocation(
                    ((i + g * 2) % 3) * .4 + .1,
                    ((i + g) % 3) * .3 + .1,
                  ),
                ),
            ],
            assistDetails: [
              for (var a = 0; a < assists; a++)
                PerformanceAssistDetails(
                  minute: 30 + i * 4,
                  goalscorerId: 'calleri',
                ),
            ],
            substitutionDetails: [
              if (subbedOff)
                PerformanceSubstitutionDetails(
                  minute: 70,
                  type: SubstitutionType.outGame,
                ),
              if (cameOn)
                PerformanceSubstitutionDetails(
                  minute: 58,
                  type: SubstitutionType.inGame,
                ),
            ],
          ),
        );
      }
      performances.add(
        ManagerFixturePlayerPerformance(
          personId: person.id,
          fixtureId: fixtureId,
          playerInstanceId: 'calleri',
          goalsCount: others > 0 ? 1 : 0,
          assistsCount: goals > 0 ? 1 : 0,
          avgRating: 6.4 + ((i * 5 + year) % 22) / 10,
          shotsCount: 2 + i % 4,
          shotAccuracy: 35 + (i * 11) % 45,
          passes: 22 + i,
          passAccuracy: 72 + (i * 5) % 20,
          keyPasses: (i + 1) % 3,
          tackles: 1 + i % 2,
          goalDetails: [if (others > 0) PerformanceGoalDetails(minute: 50 + i)],
          assistDetails: [
            if (goals > 0)
              PerformanceAssistDetails(minute: 20 + i, goalscorerId: 'brenner'),
          ],
        ),
      );
    }
  }
  await sql.saveManagerPerformances(performances);
  for (final (table, field, rows) in [
    (
      'Overall',
      'overall',
      [
        ('2027-01-01', 76),
        ('2027-07-01', 78),
        ('2028-01-01', 81),
        ('2028-06-01', 83),
      ],
    ),
    (
      'MarketValue',
      'value',
      [
        ('2027-01-01', 8000000),
        ('2027-08-01', 12500000),
        ('2028-01-01', 16000000),
        ('2028-07-01', 23000000),
      ],
    ),
    ('ContractItem', 'wage', [('2027-01-01', 25000), ('2028-03-01', 42000)]),
  ]) {
    for (final (i, (date, value)) in rows.indexed) {
      await sql.addPlayerHistory(table, {
        'id': '$table-$i',
        'personId': person.id,
        'customPlayerId': 'brenner',
        'date': date,
        'createdAt': date,
        field: value,
        if (table == 'ContractItem') 'endDate': '2031-12-31',
        if (table == 'ContractItem') 'squadRole': 'Titular',
      });
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  late Map<String, dynamic> translations;
  late Database db;
  late SqlService sql;
  final capture = GlobalKey();
  final person = reviewPerson();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory('build/player-screens-docs').absolute.path,
        );
    await EasyLocalization.ensureInitialized();
    await initializeDateFormatting('pt_BR');
    translations = jsonDecode(
      await rootBundle.loadString('assets/translations/pt_BR.json'),
    ) as Map<String, dynamic>;
    await loadPreviewFonts();
    await GameCatalog.load();
  });

  setUp(() async {
    db = await SqlService.openCareerDatabase(inMemoryDatabasePath);
    sql = SqlService.withDatabase(db);
    await _seed(db, sql);
  });
  tearDown(() => db.close());

  Future<void> mount(
    WidgetTester tester,
    Widget home, {
    bool dark = true,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('pt', 'BR')],
        startLocale: const Locale('pt', 'BR'),
        fallbackLocale: const Locale('pt', 'BR'),
        path: 'assets/translations',
        assetLoader: _Translations(translations),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? managerDarkTheme : managerLightTheme,
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: capture, child: child!),
            ),
            home: home,
          ),
        ),
      ),
    );
    await settleDataFrames(tester);
  }

  Future<void> preview(WidgetTester tester, String name) async {
    final directory = Platform.environment['PLAYER_PREVIEW_DIR'];
    if (directory == null) return;
    await tester.runAsync(() async {
      final render =
          capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Widget profile() => ViewPlayerPage(
    person: person,
    sql: sql,
    row: const {
      'id': 'roster-s2028-brenner',
      'personId': 'career',
      'playerId': 'brenner',
      'seasonId': 's2028',
      'customName': 'Brenner',
      'customPositionId': '25',
      'overall': 83,
      'shirtNumber': 9,
      'isBench': 0,
    },
  );

  for (final dark in [true, false]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('Player profile tabs read as one analysis ($theme)', (
      tester,
    ) async {
      await mount(tester, profile(), dark: dark, size: const Size(390, 4200));
      for (final (index, name) in [
        (1, 'temporada'),
        (2, 'resumo'),
        (0, 'detalhes'),
        (4, 'carreira'),
      ]) {
        await tester.tap(find.byType(Tab).at(index));
        await settleDataFrames(tester);
        await preview(tester, 'profile-$name-$theme');
        expect(tester.takeException(), isNull, reason: name);
      }
    });

    testWidgets('Comparison shows who is ahead ($theme)', (tester) async {
      await mount(
        tester,
        ComparePlayersPage(
          person: person,
          sql: sql,
          initialSeasonId: 's2028',
          initialPlayer: const {'playerId': 'brenner'},
        ),
        dark: dark,
        size: const Size(390, 4200),
      );
      await tester.tap(find.byKey(const ValueKey('compare-add')));
      await settleDataFrames(tester);
      await tester.tap(find.text('Calleri'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await settleDataFrames(tester);
      await preview(tester, 'compare-$theme');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Player screens fit 320px with larger text', (tester) async {
    await mount(tester, profile(), size: const Size(320, 4200), scale: 1.3);
    for (final index in [1, 2]) {
      await tester.tap(find.byType(Tab).at(index));
      await settleDataFrames(tester);
      await preview(tester, 'narrow-profile-$index');
      expect(tester.takeException(), isNull);
    }
  });
}
