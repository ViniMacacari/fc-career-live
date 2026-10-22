import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'data_frames.dart';

import 'package:mcmanager/FcScore/CareerCompetitionsPage.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/FcScore/FcScoreRepository.dart';
import 'package:mcmanager/FcScore/FcScoreCareerIdentity.dart';
import 'package:mcmanager/FcScore/CareerCompetitionWidgets.dart';
import 'package:mcmanager/utils/Components/TeamLogo.dart';
import 'package:mcmanager/RootPage/DrawerItem.dart';
import 'package:mcmanager/RootPage/managerCareerMenuItems.dart';
import 'package:mcmanager/RootPage/playerCareerMenuItems.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fcscore_fixture.dart';
import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';
import 'fcscore_competition_structure_test.dart' as structure;

class _MeasuredDatabase implements Database {
  _MeasuredDatabase(this.delegate);
  final Database delegate;
  int playerReads = 0, largestPlayerPage = 0, playerBytes = 0;

  List<Map<String, Object?>> record(
    String source,
    List<Map<String, Object?>> rows,
  ) {
    if (source.contains('FcScoreWorldPlayer')) {
      playerReads++;
      if (rows.length > largestPlayerPage) largestPlayerPage = rows.length;
      playerBytes += utf8.encode(jsonEncode(rows)).length;
    }
    return rows;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async => record(sql, await delegate.rawQuery(sql, arguments));

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async => record(
    table,
    await delegate.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FcJson _snapshot() {
  final path = Platform.environment['FC_SCORE_CLASSIFICATION_SNAPSHOT'];
  if (path != null) return fcObject(jsonDecode(File(path).readAsStringSync()));
  final teams = [
    for (var i = 0; i < 146; i++)
      {
        'id': i + 1,
        'name': 'Equipe ${i + 1}',
        'league': {'id': i < 20 ? 80 : 1003},
        'overall': 75,
        'roster': [
          for (var j = 0; j < (i < 133 ? 28 : 27); j++)
            {
              'id': i * 100 + j + 1,
              'name': 'Jogador ${i * 100 + j + 1}',
              'positions': ['ST'],
              'overall': 75,
              'leagueGoals': j % 12,
              'leagueAppearances': 20,
              'details': List.filled(200, 'x').join(),
            },
        ],
      },
  ];
  FcJson row(int i) => {
    ...fcList(
      fcList(fcList(apiTable()['stages']).first['groups']).first['rows'],
    ).first,
    'team': {'id': i + 1, 'name': 'Equipe ${i + 1}'},
  };
  return {
    'teams': teams,
    'fixtures': <FcJson>[],
    'competitions': [
      {
        'competition': {'id': 1528, 'name': 'Brasileirão', 'code': 'C80'},
        'stages': [
          {
            'name': 'Liga',
            'groups': [
              {
                'code': 'A',
                'rows': [for (var i = 0; i < 20; i++) row(i)],
              },
            ],
          },
        ],
      },
      {
        'competition': {'id': 1257, 'name': 'Libertadores', 'code': 'C1003'},
        'stages': [
          {
            'name': 'Grupos',
            'groups': [
              for (var g = 0; g < 40; g++)
                {
                  'code': '$g',
                  'rows': [for (var j = 0; j < 4; j++) row((g * 4 + j) % 146)],
                },
            ],
          },
        ],
      },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late _MeasuredDatabase measured;
  late FcScoreRepository repo;
  late FcJson snapshot;
  final person = reviewPerson();
  final boundary = GlobalKey();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async =>
              Directory('build/fcscore-classification-docs').absolute.path,
        );
    await loadPreviewFonts();
    await GameCatalog.load();
    snapshot = _snapshot();
  });
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqlService.ensureCompatibleSchema(db);
    await SqlService.ensureSeasonClosureSchema(db);
    await db.insert('Persons', person.toMap());
    await db.insert('Seasons', reviewSeason(id: 's2028', year: 2028).toMap());
    final batch = db.batch();
    for (final c in fcList(snapshot['competitions'])) {
      final ref = fcObject(c['competition']);
      batch.insert('FcScoreCompetition', {
        'personId': person.id,
        'seasonId': 's2028',
        'remoteId': fcId(ref['id']),
        'tournamentId': 't-${ref['id']}',
        'saveId': 'test-save',
        'name': ref['name'],
        'code': ref['code'],
        'currentDate': '2028-08-20',
        'importedAt': '2026-10-12',
        'rawJson': jsonEncode(c),
      });
    }
    for (final t in fcList(snapshot['teams'])) {
      batch.insert('FcScoreWorldTeam', {
        'personId': person.id,
        'seasonId': 's2028',
        'remoteId': fcId(t['id']),
        'teamId': 'test-${t['id']}',
        'rawJson': jsonEncode(t),
      });
      for (final p in fcList(t['roster'])) {
        batch.insert('FcScoreWorldPlayer', {
          'personId': person.id,
          'seasonId': 's2028',
          'remoteTeamId': fcId(t['id']),
          'remotePlayerId': fcId(p['id']),
          'playerId': '',
          'rawJson': jsonEncode(p),
        });
      }
    }
    for (final f in fcList(snapshot['fixtures'])) {
      batch.insert('FcScoreWorldFixture', {
        'personId': person.id,
        'seasonId': 's2028',
        'remoteKey': fcId(f['id']),
        'competitionId': fcId(fcObject(f['competition'])['id']),
        'tournamentId': 't-${fcObject(f['competition'])['id']}',
        'homeTeamId': fcId(fcObject(fcObject(f['home'])['team'])['id']),
        'awayTeamId': fcId(fcObject(fcObject(f['away'])['team'])['id']),
        'date': f['date'],
        'played': f['played'] == true ? 1 : 0,
        'rawJson': jsonEncode(f),
      });
    }
    await batch.commit(noResult: true);
    measured = _MeasuredDatabase(db);
    repo = FcScoreRepository(sql: SqlService.withDatabase(measured));
  });
  tearDown(() async => db.close());

  Future<void> settle(WidgetTester tester) async {
    await settleDataFrames(tester);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final dir = Platform.environment['FC_SCORE_PREVIEW_DIR'];
    if (dir == null) return;
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$dir/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  test('Manager menu starts with fixtures, squad, classification and coach; player order is preserved', () {
    final manager = managerCareerMenuItems(person)
        .whereType<DrawerItem>()
        .toList();
    expect(manager.take(4).map((e) => e.id), [
      'fixtures',
      'teamCenter',
      'careerCompetitions',
      'myManager',
    ]);
    expect(manager.skip(4).map((e) => e.id), [
      'playerStatistics',
      'otherPlayers',
      'transfers',
      'twitter',
      'fcScore',
      'careerPath',
      'careerStatistics',
      'teamAnalytics',
      'seasonArchive',
      'tournamentResults',
      'trophies',
      'streaks',
    ]);
    final player = playerCareerMenuItems(person)
        .whereType<DrawerItem>()
        .toList();
    expect(player[1].id, 'careerCompetitions');
    expect(manager[2].titleKey, 'Classificação');
  });

  test('Team summaries release roster JSON while individual rosters stay available', () async {
    final teams = await repo.careerTeams(
      person.id,
      's2028',
      includeRosters: false,
    );
    expect(teams, hasLength(146));
    expect(utf8.encode(jsonEncode(teams)).length, lessThan(100000));
    expect(
      teams.every(
        (t) => t['rawJson'] == null && fcObject(t['data'])['roster'] == null,
      ),
      isTrue,
    );
    final id = fcId(teams.first['remoteId']);
    final source = fcList(snapshot['teams'])
        .firstWhere((t) => fcId(t['id']) == id);
    expect(teams.first['rosterCount'], fcList(source['roster']).length);
    expect(
      await repo.careerRoster(person.id, 's2028', id),
      hasLength(fcList(source['roster']).length),
    );
  });

  test(
    'Existing imports use app competition names and current customizations',
    () async {
      await db.update(
        'FcScoreCompetition',
        {'tournamentId': 'league:1014'},
        where: 'remoteId = ?',
        whereArgs: ['1528'],
      );
      final native = (await GameCatalog.load()).league(
        person.fifaVersion,
        '1014',
      )!;
      final imported = (await repo.careerCompetitions(person.id))
          .firstWhere((c) => c['remoteId'] == '1528');
      expect(imported['name'], native.label);
      expect(fcObject(imported['data'])['competition']['name'], 'Brasileirão');
      await db.insert('Tournament', {
        'id': 'local-cup',
        'name': 'Taça do aplicativo',
        'fifaVersions': 'FC26,FC25',
      });
      await db.update(
        'FcScoreCompetition',
        {'tournamentId': 'local-cup'},
        where: 'remoteId = ?',
        whereArgs: ['1257'],
      );
      expect(
        (await repo.careerCompetitions(person.id))
            .firstWhere((c) => c['remoteId'] == '1257')['name'],
        'Taça do aplicativo',
      );
      await db.insert('ClubCustomizationModel', {
        'id': 'club',
        'clubName': 'Tricolor do aplicativo',
        'originalTeamId': '40-13',
        'originalLeagueId': '1014',
        'fifaVersion': person.fifaVersion,
        'imagePath': '/team_customizations/club/logo.png',
      });
      final identity = await FcScoreCareerIdentity.load(repo.sql, person);
      expect(identity.club('40-13', '1014')!.label, 'Tricolor do aplicativo');
      expect(
        identity.club('40-13', '1014')!.imagePath,
        '/team_customizations/club/logo.png',
      );
      await db.insert('CustomLeague', {
        'id': 'destination',
        'label': 'Liga do de-para',
        'fifaVersion': 'FC26, FC25',
      });
      await db.insert('CustomClub', {
        'id': 'multi-club',
        'label': 'Clube do de-para',
        'leagueId': 'destination',
        'fifaVersion': 'FC26, FC25',
        'personId': '',
      });
      final multi = await FcScoreCareerIdentity.load(repo.sql, person);
      expect(
        multi.competitions['league:destination']!.label,
        'Liga do de-para',
      );
      expect(
        multi.club('multi-club', 'destination')!.label,
        'Clube do de-para',
      );
    },
  );

  testWidgets(
    'Season selection is in the app bar and retains the local competition names',
    (tester) async {
      tester.view.physicalSize = const Size(390, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await db.insert('Tournament', {
          'id': 'local-cup',
          'name': 'Taça do aplicativo',
          'fifaVersions': person.fifaVersion,
        });
        await db.update(
          'FcScoreCompetition',
          {'tournamentId': 'local-cup'},
          where: 'remoteId = ?',
          whereArgs: ['1257'],
        );
        await db.insert(
          'Seasons',
          reviewSeason(id: 's2027', year: 2027).toMap(),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: managerDarkTheme,
          home: RepaintBoundary(
            key: boundary,
            child: CareerCompetitionsPage(person: person, repository: repo),
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Taça do aplicativo'), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Classificação'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byKey(const Key('classification-season')),
        ),
        findsOneWidget,
      );
      await capture(tester, 'classification-overview');
      await tester.tap(find.byKey(const Key('classification-season')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '2027'));
      await tester.pumpAndSettle();
      expect(find.text('Temporada 2027'), findsOneWidget);
      expect(
        find.textContaining('Nenhuma competição nesta temporada'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      await tester.pump(const Duration(seconds: 11));
    },
  );

  for (final dark in [true, false]) {
    testWidgets(
      'All standings columns scroll and qualification zones remain visible ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final zones = <FcJson>[
          {
            'type': 'champion',
            'positions': [1],
          },
          {
            'type': 'continental',
            'positions': [1, 2],
            'entry': 1,
            'competition': {'id': 1, 'name': 'Libertadores'},
          },
          {
            'type': 'continental',
            'positions': [3],
            'entry': 2,
            'competition': {'id': 1, 'name': 'Libertadores'},
          },
          {
            'type': 'continental',
            'positions': [4],
            'entry': 1,
            'competition': {'id': 2, 'name': 'Sudamericana'},
          },
          {
            'type': 'continental',
            'positions': [5],
            'entry': 1,
            'competition': {'id': 3, 'name': 'Conference League'},
          },
          {
            'type': 'relegation',
            'positions': [6],
            'league': {'id': 83, 'name': 'K League 1'},
          },
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? managerDarkTheme : managerLightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Scaffold(
              body: RepaintBoundary(
                key: boundary,
                child: ListView(
                  children: [
                    CareerStandingsTable(
                      rows: [
                        for (var i = 1; i <= 6; i++)
                          {
                            'team': {'id': i},
                            'position': i,
                            'points': 20 - i,
                            'played': 10,
                            'wins': 5,
                            'draws': 2,
                            'losses': 3,
                            'goalsFor': 23,
                            'goalsAgainst': 12,
                            'goalDifference': 11,
                            'form': ['W', 'W', 'D', 'L', 'W'],
                          },
                      ],
                      zones: zones,
                      name: (id) => 'Equipe $id',
                      logo: (id, size) =>
                          Icon(Icons.shield_outlined, size: size),
                      isOwn: (id) => id == '1',
                      onTeam: (_) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final header in [
          'PTS',
          'PJ',
          'V',
          'E',
          'D',
          'GP',
          'GC',
          'SG',
          'Forma',
        ]) {
          expect(find.text(header), findsWidgets);
        }
        final gp = find.text('GP');
        expect(tester.getTopLeft(gp).dx, greaterThan(320));
        Color bar(int team, String key) => tester
            .widget<Container>(
              find.byKey(ValueKey('competition-zone-$team-$key')),
            )
            .color!;
        final champion = bar(1, 'champion:::'),
            first = bar(1, 'continental:1:1:'),
            preliminary = bar(3, 'continental:1:2:'),
            second = bar(4, 'continental:2:1:'),
            third = bar(5, 'continental:3:1:'),
            relegation = bar(6, 'relegation:::83');
        expect(
          {
            champion,
            first,
            second,
            third,
            relegation,
          }.map((c) => c.toARGB32()).toSet(),
          hasLength(5),
        );
        expect(preliminary.a, lessThan(first.a));
        expect(preliminary.withValues(alpha: 1), first);
        await capture(tester, 'standings-zones-${dark ? 'dark' : 'light'}');
        await tester.drag(
          find.byKey(const Key('competition-table-horizontal')),
          const Offset(-900, 0),
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.text('Classificação')).dx, lessThan(320));
        expect(find.text('Libertadores · fase preliminar'), findsWidgets);
        expect(find.text('Rebaixamento'), findsWidgets);
        expect(find.textContaining('K League 1'), findsNothing);
        await capture(tester, 'standings-columns-${dark ? 'dark' : 'light'}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'Cup uses app names/logos, excludes setup and renders home/away knockout ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final logo = File('assets/images/clubLogos/sao-paulo.png')
            .absolute
            .path;
        final raw = {
          'competition': {'id': 1257, 'name': 'Nome da API'},
          'stages': [
            structure.stage('Setup Stage', [
              structure.group([
                structure.row(1, played: 6),
                structure.row(2, played: 6),
              ]),
            ]),
            structure.stage('Round 1', [
              structure.group([
                structure.row(1, played: 2, goals: 3),
                structure.row(2, played: 2, goals: 2),
              ]),
            ]),
            structure.stage('Final', [
              structure.group([structure.row(1), structure.row(2)]),
            ]),
          ],
        };
        await tester.runAsync(() async {
          await db.insert('Tournament', {
            'id': 'local-cup',
            'name': 'Taça do aplicativo',
            'fifaVersions': person.fifaVersion,
            'imagePath': logo,
          });
          await db.update(
            'FcScoreCompetition',
            {'tournamentId': 'local-cup', 'rawJson': jsonEncode(raw)},
            where: 'remoteId = ?',
            whereArgs: ['1257'],
          );
          await db.update(
            'FcScoreWorldTeam',
            {'teamId': '40-13', 'leagueId': '1014'},
            where: 'remoteId = ?',
            whereArgs: ['1'],
          );
          await db.update(
            'FcScoreWorldTeam',
            {'teamId': '40-1', 'leagueId': '1014'},
            where: 'remoteId = ?',
            whereArgs: ['2'],
          );
          await db.insert('ClubCustomizationModel', {
            'id': 'club',
            'clubName': 'Tricolor do aplicativo',
            'originalTeamId': '40-13',
            'originalLeagueId': '1014',
            'fifaVersion': person.fifaVersion,
            'imagePath': logo,
          });
          for (final (index, f) in [
            structure.game('Round 1', 1, 2, homeGoals: 1, awayGoals: 0),
            structure.game(
              'Round 1',
              2,
              1,
              date: '2028-06-08',
              homeGoals: 2,
              awayGoals: 2,
            ),
          ].indexed) {
            await db.insert('FcScoreWorldFixture', {
              'personId': person.id,
              'seasonId': 's2028',
              'competitionId': '1257',
              'remoteKey': 'leg$index',
              'tournamentId': 'local-cup',
              'homeTeamId': 'home',
              'awayTeamId': 'away',
              'played': 1,
              'date': f['date'],
              'rawJson': jsonEncode(f),
            });
          }
        });
        final cup = (await tester.runAsync(
          () => repo.careerCompetitions(person.id),
        ))!.firstWhere((c) => c['remoteId'] == '1257');
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? managerDarkTheme : managerLightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.3)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: boundary,
              child: CareerCompetitionPage(
                person: person,
                repository: repo,
                competition: cup,
              ),
            ),
          ),
        );
        await settle(tester);
        expect(
          find.widgetWithText(AppBar, 'Taça do aplicativo'),
          findsOneWidget,
        );
        expect(find.text('Setup Stage'), findsNothing);
        expect(find.byType(CareerKnockoutCard), findsOneWidget);
        expect(find.byType(DataTable), findsNothing);
        expect(find.text('Tricolor do aplicativo'), findsOneWidget);
        expect(
          tester
              .widgetList<TeamLogo>(find.byType(TeamLogo))
              .any((l) => l.imagePath == logo),
          isTrue,
        );
        expect(find.textContaining('Ida'), findsOneWidget);
        expect(find.textContaining('Volta'), findsOneWidget);
        await capture(tester, 'knockout-${dark ? 'dark' : 'light'}');
        await tester.tap(find.text('Partidas'));
        await settle(tester);
        expect(find.byType(CareerCompetitionMatchCard), findsWidgets);
        expect(find.text('Tricolor do aplicativo'), findsWidgets);
        await capture(tester, 'cup-matches-${dark ? 'dark' : 'light'}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
        await tester.pump(const Duration(seconds: 11));
      },
    );
  }

  for (final cid in ['1528', '1257']) {
    test('Scorers for $cid use bounded responses with 4075 players', () async {
      final c = (await repo.careerCompetitions(person.id))
          .firstWhere((c) => c['remoteId'] == cid);
      final scorers = await repo.competitionScorers(person, c);
      final participants = <String>{
        for (final s in fcList(fcObject(c['data'])['stages']))
          for (final g in fcList(s['groups']))
            for (final r in fcList(g['rows'])) fcId(fcObject(r['team'])['id']),
        for (final f in fcList(snapshot['fixtures']))
          if (fcId(fcObject(f['competition'])['id']) == cid)
            for (final side in ['home', 'away'])
              fcId(fcObject(fcObject(f[side])['team'])['id']),
      };
      final league = fcId(c['code']).substring(1);
      final expected = <String>{
        for (final t in fcList(snapshot['teams']))
          if (participants.contains(fcId(t['id'])) &&
              fcId(fcObject(t['league'])['id']) == league)
            for (final p in fcList(t['roster']))
              if ((fcInt(p['leagueGoals']) ?? 0) > 0) fcId(p['id']),
      };
      expect(scorers.players.map((p) => fcId(p['id'])).toSet(), expected);
      expect(measured.playerReads, greaterThan(0));
      expect(measured.largestPlayerPage, lessThanOrEqualTo(256));
      expect(measured.playerBytes, lessThan(4000000));
    });
  }

  for (final dark in [true, false]) {
    testWidgets(
      'Brazil and Libertadores open at 320px without eager scorers ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final competitions = await tester.runAsync(
          () => repo.careerCompetitions(person.id),
        );
        for (final cid in ['1528', '1257']) {
          measured.playerReads = 0;
          final c = competitions!.firstWhere((c) => c['remoteId'] == cid);
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? managerDarkTheme : managerLightTheme,
              home: RepaintBoundary(
                key: boundary,
                child: CareerCompetitionPage(
                  key: ValueKey(cid),
                  person: person,
                  repository: repo,
                  competition: c,
                ),
              ),
            ),
          );
          await settle(tester);
          expect(find.text('PTS'), findsWidgets);
          expect(measured.playerReads, 0);
          expect(find.byType(DataTable).evaluate().length, lessThan(6));
          await capture(
            tester,
            'classification-$cid-${dark ? 'dark' : 'light'}',
          );
          await tester.tap(find.text('Artilharia'));
          await settle(tester);
          expect(measured.playerReads, greaterThan(0));
          final league = fcId(c['code']).substring(1);
          final hasGoals = fcList(snapshot['teams']).any(
            (t) =>
                fcId(fcObject(t['league'])['id']) == league &&
                fcList(t['roster'])
                    .any((p) => (fcInt(p['leagueGoals']) ?? 0) > 0),
          );
          if (hasGoals) {
            expect(find.text('gols'), findsWidgets);
          } else {
            expect(
              find.text('Nenhum gol registrado nos dados disponíveis.'),
              findsOneWidget,
            );
          }
          expect(find.byType(ListTile).evaluate().length, lessThan(40));
          expect(tester.takeException(), isNull);
          await capture(tester, 'scorers-$cid-${dark ? 'dark' : 'light'}');
        }
      },
    );
  }
}
