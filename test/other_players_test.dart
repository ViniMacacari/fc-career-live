import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/FcScore/FcScoreRepository.dart';
import 'package:mcmanager/ManagerCareer/OtherPlayers/OtherPlayersData.dart';
import 'package:mcmanager/ManagerCareer/OtherPlayers/OtherPlayersPage.dart';
import 'package:mcmanager/ManagerCareer/OtherPlayers/WorldStatsSync.dart';
import 'package:mcmanager/utils/PlayerClubLookup.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/GamePlayers.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data_frames.dart';
import 'fcscore_fixture.dart' show apiLink;
import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';

late Map<String, dynamic> translations;

class _Translations extends AssetLoader {
  const _Translations(this.values);
  final Map<String, dynamic> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

final person = reviewPerson();
late CatalogItem teamA, teamB;

Future<void> _seed(Database db) async {
  await db.insert('Persons', person.toMap());
  await db.insert('Seasons', reviewSeason(id: 's2027', year: 2027).toMap());
  await db.insert('Seasons', reviewSeason(id: 's2028', year: 2028).toMap());
  for (final (id, name, position, overall) in [
    ('brenner', 'Brenner', '25', 80),
    ('gabigol', 'Gabigol', '25', 82),
    ('pedro', 'Pedro', '0', 77),
    ('lucas', 'Lucas Moura', '18', 79),
  ]) {
    await db.insert('CustomCreatedPlayer', {
      'id': id,
      'personId': person.id,
      'realPlayerId': id == 'gabigol' ? 'r-gabi' : null,
      'name': name,
      'positionId': position,
      'overall': overall,
      'potential': overall + 3,
      'firstSeasonAge': 27,
      'nationalityId': '54',
      'realFace': 0,
      'fromRealPlayer': 0,
      'foot': 'Right',
    });
  }
  await db.insert('TeamPlayer', {
    'id': 'roster-brenner',
    'personId': person.id,
    'playerId': 'brenner',
    'seasonId': 's2028',
    'isBench': 0,
  });
  await db.insert('TeamPlayer', {
    'id': 'roster-lucas',
    'personId': person.id,
    'playerId': 'lucas',
    'seasonId': 's2027',
    'isBench': 0,
  });
  await db.insert('TeamTransferItem', {
    'id': 'sale-lucas',
    'personId': person.id,
    'seasonId': 's2027',
    'playerInstanceId': 'lucas',
    'fromTeamId': person.teamId,
    'fromLeagueId': person.leagueId,
    'toTeamId': teamB.id,
    'toLeagueId': teamB.leagueId,
    'transferValue': 12000000,
    'type': 'sell',
    'date': DateTime(2027, 8, 1).toIso8601String(),
    'movementApplied': 1,
  });
  await db.insert('FcScoreWorldTeam', {
    'personId': person.id,
    'seasonId': 's2028',
    'remoteId': 'rA',
    'teamId': teamA.id,
    'leagueId': teamA.leagueId,
    'rawJson': '{}',
  });
  await db.insert('FcScoreCompetition', {
    'personId': person.id,
    'seasonId': 's2028',
    'remoteId': 'c1',
    'tournamentId': 'league:1014',
    'saveId': 'save',
    'name': 'Brasileirão',
    'currentDate': '2028-06-30',
    'importedAt': '2028-06-30',
    'rawJson': '{}',
  });
  for (final (id, remote, goals) in [
    ('gabigol', 'r-gabi', 12),
    ('pedro', 'r-pedro', 0),
  ]) {
    await db.insert('FcScoreWorldPlayer', {
      'personId': person.id,
      'seasonId': 's2028',
      'remoteTeamId': 'rA',
      'remotePlayerId': remote,
      'playerId': id,
      'rawJson': jsonEncode({
        'id': remote,
        'seasonStats': {
          'competitions': [
            {
              'competition': {'id': 'c1', 'name': 'Brasileirão'},
              'team': {'id': 'rA'},
              'appearances': 20,
              'goals': goals,
              'assists': 3,
              'averageRating': 7.3,
              'minutes': 1650,
            },
          ],
        },
      }),
    });
  }
  final recorder = await WorldRosterRecorder.start(
    db,
    personId: person.id,
    ownTeamId: person.teamId,
  );
  for (final (id, shirt) in [('gabigol', 10), ('pedro', 1)]) {
    await recorder.record(
      playerId: id,
      teamId: teamA.id,
      leagueId: teamA.leagueId,
      date: DateTime(2028, 6, 30),
      shirtNumber: shirt,
    );
  }
}

String localLeague() => GameCatalog.current!
    .leagues(person.fifaVersion)
    .firstWhere((l) => l.id == '1014')
    .label;

List<GamePlayer> _catalog() => [
  GamePlayer(
    'c-a',
    'Reserva Antigo',
    'ST',
    70,
    positionIds: const ['25'],
    teamId: teamA.id,
    teamName: teamA.label,
  ),
  GamePlayer(
    'c-hulk',
    'Hulk',
    'ST',
    84,
    potential: 84,
    age: 38,
    positionIds: const ['25'],
    teamId: teamB.id,
    teamName: teamB.label,
    nationalityCode: '54',
  ),
  GamePlayer(
    'c-arana',
    'Arana',
    'LB',
    78,
    age: 27,
    positionIds: const ['7'],
    teamId: teamB.id,
    teamName: teamB.label,
  ),
  const GamePlayer('r-gabi', 'G. Barbosa', 'ST', 80),
  const GamePlayer(
    'c-free',
    'Livre Silva',
    'CM',
    66,
    positionIds: ['14'],
    teamId: '0',
  ),
];

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database db;
  late SqlService sql;
  late OtherPlayersRepository repo;
  final capture = GlobalKey();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory('build/other-players-docs').absolute.path,
        );
    await EasyLocalization.ensureInitialized();
    await initializeDateFormatting('pt_BR');
    translations = jsonDecode(
      await rootBundle.loadString('assets/translations/pt_BR.json'),
    ) as Map<String, dynamic>;
    await loadPreviewFonts();
    final catalog = await GameCatalog.load();
    final rivals = catalog
        .teams(person.fifaVersion)
        .where((t) => t.leagueId == '1014' && t.id != person.teamId)
        .toList();
    teamA = rivals[0];
    teamB = rivals[1];
  });

  setUp(() async {
    db = await SqlService.openCareerDatabase(inMemoryDatabasePath);
    sql = SqlService.withDatabase(db);
    repo = OtherPlayersRepository(sql: sql, catalogPlayers: _catalog());
    await _seed(db);
  });
  tearDown(() => db.close());

  test('Imported rosters turn club changes into transfers', () async {
    var recorder = await WorldRosterRecorder.start(
      db,
      personId: person.id,
      ownTeamId: person.teamId,
    );
    await recorder.record(
      playerId: 'gabigol',
      teamId: teamB.id,
      leagueId: teamB.leagueId,
      date: DateTime(2028, 8, 15),
    );
    await recorder.record(
      playerId: 'lucas',
      teamId: teamB.id,
      leagueId: teamB.leagueId,
      date: DateTime(2028, 8, 15),
    );
    var moves = await repo.transfers(person, 'gabigol');
    expect(moves, hasLength(1));
    expect(moves.single.source, 'api');
    expect(moves.single.fromTeamId, teamA.id);
    expect(moves.single.toTeamId, teamB.id);
    expect(moves.single.date, DateTime(2028, 8, 15));
    expect((await repo.transfers(person, 'lucas')).map((m) => m.source), [
      'club',
    ]);
    recorder = await WorldRosterRecorder.start(
      db,
      personId: person.id,
      ownTeamId: person.teamId,
    );
    await recorder.record(
      playerId: 'lucas',
      teamId: teamA.id,
      leagueId: teamA.leagueId,
      date: DateTime(2028, 9, 1),
    );
    final lucas = await repo.transfers(person, 'lucas');
    expect(lucas.map((m) => m.source), ['api', 'club']);
    expect(lucas.first.fromTeamId, teamB.id);
    await recorder.record(
      playerId: 'gabigol',
      teamId: person.teamId,
      date: DateTime(2028, 9, 1),
    );
    moves = await repo.transfers(person, 'gabigol');
    expect(moves.first.toTeamId, person.teamId);
    expect(await repo.worldRow(person, 'gabigol'), isNull);
    await recorder.record(
      playerId: 'pedro',
      teamId: teamA.id,
      leagueId: teamA.leagueId,
      date: DateTime(2028, 9, 1),
    );
    expect(await repo.transfers(person, 'pedro'), isEmpty);
  });

  test('A career imported before keeps only the downloaded squad', () async {
    await db.delete('WorldPlayer');
    final s = await repo.load(person);
    expect(s.teamOf(teamA.id)!.players.map((p) => p.name), [
      'Pedro',
      'Gabigol',
    ]);
    expect((await repo.worldRow(person, 'gabigol'))!['source'], 'api');
    expect((await repo.worldRow(person, 'gabigol'))!['since'], '2028-06-30');
  });

  test('Catalog clubs sharing an identity stay apart', () async {
    final fc26 = OtherPlayersRepository(sql: sql);
    await db.update('Persons', {'fifaVersion': 'FC26'});
    final s = await fc26.load(person);
    final sizes = [for (final t in s.teams) t.players.length];
    expect(sizes.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(45));
    final aek = s.teams.firstWhere((t) => t.label == 'AEK Athens');
    expect(
      aek.players.every((p) => p.catalog?.teamName == 'AEK Athens'),
      isTrue,
    );
    final bahia = s.teams.firstWhere((t) => t.label == 'Bahia');
    expect(bahia.players.every((p) => p.catalog?.teamName == 'Bahia'), isTrue);
  });

  test('Other squads join API rosters, departures and the catalog', () async {
    final s = await repo.load(person);
    final a = s.teamOf(teamA.id)!, b = s.teamOf(teamB.id)!;
    expect(a.imported, isTrue);
    expect(a.players.map((p) => p.name), ['Pedro', 'Gabigol']);
    expect(a.players.last.shirtNumber, 10);
    expect(b.players.map((p) => p.name), ['Arana', 'Lucas Moura', 'Hulk']);
    expect(
      b.players.firstWhere((p) => p.name == 'Lucas Moura').origin,
      OtherPlayerOrigin.departed,
    );
    expect(s.teamOf(null)!.players.single.name, 'Livre Silva');
    expect(s.players.any((p) => p.name == 'Brenner'), isFalse);
    expect(s.players.any((p) => p.name == 'G. Barbosa'), isFalse);
    expect(s.teams.first.league?.id, person.leagueId);
    expect(s.search('hulk', const OtherPlayersFilter()).single.name, 'Hulk');
    expect(
      s.search(teamB.label, const OtherPlayersFilter()).map((p) => p.name),
      containsAll(['Hulk', 'Arana', 'Lucas Moura']),
    );
    expect(
      s.search('', const OtherPlayersFilter(lines: {'GOL'})).map((p) => p.name),
      ['Pedro'],
    );
    expect(
      s
          .search('', const OtherPlayersFilter(careerOnly: true))
          .map((p) => p.name)
          .toSet(),
      {'Gabigol', 'Pedro', 'Lucas Moura'},
    );
    expect(
      s
          .search('', const OtherPlayersFilter(minOverall: 80, maxAge: 30))
          .map((p) => p.name),
      ['Gabigol'],
    );
  });

  test('Manual transfers move catalog players and keep history', () async {
    var s = await repo.load(person);
    final hulk = s.players.firstWhere((p) => p.name == 'Hulk');
    final id = await repo.materialize(person, hulk.catalog!, team: hulk.team);
    await repo.saveTransfer(
      person,
      id,
      date: DateTime(2028, 7, 10),
      type: 'loan',
      from: hulk.team,
      to: teamA,
      value: 500000,
    );
    s = await repo.load(person);
    expect(s.teamOf(teamA.id)!.players.map((p) => p.name), contains('Hulk'));
    expect(
      s.teamOf(teamB.id)!.players.map((p) => p.name),
      isNot(contains('Hulk')),
    );
    final lookup = await PlayerClubLookup.load(sql: sql, person: person);
    expect(lookup.club(playerId: id)?.id, teamA.id);
    final history = await repo.transfers(person, id);
    expect(history.single.type, 'loan');
    expect(history.single.value, 500000);
    await repo.saveTransfer(
      person,
      id,
      date: DateTime(2028, 8, 1),
      type: 'release',
      from: teamA,
    );
    expect(await repo.clubOf(person, playerId: id), isNull);
    expect(await repo.transfers(person, id), hasLength(2));
    await repo.hide(person, id);
    s = await repo.load(person);
    expect(s.players.any((p) => p.name == 'Hulk'), isFalse);
  });

  Map<String, Object> line(
    String competition,
    String team,
    String teamName,
    int apps,
  ) => {
    'competition': {'id': competition, 'name': competition},
    'team': {'id': team, 'name': teamName},
    'appearances': apps,
    'goals': 1,
    'averageRating': 7.2,
  };

  test(
    'Season lines use the newest numbers of every club and the national team',
    () async {
      await db.insert('WorldPlayerSeason', {
        'personId': person.id,
        'playerId': 'gabigol',
        'seasonId': 's2028',
        'statsJson': jsonEncode({
          'competitions': [
            line('c1', 'rA', teamA.label, 22),
            line('Eliminatórias', 'nat', 'Brasil', 4),
          ],
        }),
        'statsDate': '2028-07-15',
        'updatedAt': '2028-07-15',
      });
      var lines = (await repo.seasonLines(person, 'gabigol'))['s2028']!;
      expect(lines.map((l) => (l.name, l.teamName, l.appearances)), [
        (localLeague(), teamA.label, 22),
        ('Eliminatórias', 'Brasil', 4),
      ]);
      expect(CompetitionLine.total(lines).appearances, 26);
      expect(CompetitionLine.total(lines).date, DateTime(2028, 7, 15));
      expect(
        (await repo.seasonTotals(person, 's2028', [
          'gabigol',
        ], teamId: teamA.id))['gabigol']!.appearances,
        22,
      );
      final row = (await db.query(
        'FcScoreWorldPlayer',
        where: 'playerId = ?',
        whereArgs: ['gabigol'],
      )).single;
      final raw = jsonDecode(row['rawJson'] as String) as Map<String, dynamic>;
      ((raw['seasonStats'] as Map)['competitions'] as List)
              .first['appearances'] =
          25;
      await db.update(
        'FcScoreWorldPlayer',
        {
          'rawJson': jsonEncode({...raw, 'statsDate': '2028-08-01'}),
        },
        where: 'playerId = ?',
        whereArgs: ['gabigol'],
      );
      lines = (await repo.seasonLines(person, 'gabigol'))['s2028']!;
      expect(CompetitionLine.total(lines).appearances, 29);
    },
  );

  test('A player who changed clubs keeps one line per club', () async {
    await db.insert('FcScoreWorldTeam', {
      'personId': person.id,
      'seasonId': 's2028',
      'remoteId': 'rB',
      'teamId': teamB.id,
      'leagueId': teamB.leagueId,
      'rawJson': '{}',
    });
    await db.insert('FcScoreWorldPlayer', {
      'personId': person.id,
      'seasonId': 's2028',
      'remoteTeamId': 'rB',
      'remotePlayerId': 'r-gabi',
      'playerId': 'gabigol',
      'rawJson': jsonEncode({
        'id': 'r-gabi',
        'seasonStats': {
          'competitions': [line('c1', 'rB', teamB.label, 5)],
        },
      }),
    });
    final lines = (await repo.seasonLines(person, 'gabigol'))['s2028']!;
    expect(lines.map((l) => l.appearances), [20, 5]);
    expect(lines.map((l) => l.teamId), [teamA.id, teamB.id]);
  });

  test('Season numbers come from the API on demand', () async {
    addTearDown(() => WorldStatsSync.forget(person.id));
    final health = <String>[];
    FcScoreApi api(Uri uri) => FcScoreApi(
      uri,
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/health')) health.add(path);
        final Object value = path.endsWith('/health')
            ? {'status': 'ok'}
            : path.endsWith('/meta')
            ? {'gameVersion': 'FC 26'}
            : path.endsWith('/careers')
            ? [
                {'id': 'save-A', 'inGameName': 'Minha carreira'},
              ]
            : path.endsWith('/careers/save-A')
            ? {'currentDate': '2028-07-20'}
            : path.endsWith('/players/r-gabi')
            ? {
                'seasonStats': {
                  'competitions': [
                    line('c1', 'rA', teamA.label, 23),
                    line('Copa América', 'nat', 'Brasil', 3),
                    {
                      'competition': {'id': '1528', 'name': 'Brasileirão'},
                      'team': {'id': '598', 'name': 'São Paulo API'},
                      'appearances': 2,
                    },
                  ],
                },
              }
            : path.endsWith('/teams/rA')
            ? {
                'roster': [
                  {
                    'id': 'r-gabi',
                    'seasonStats': {
                      'competitions': [line('c1', 'rA', teamA.label, 23)],
                    },
                  },
                  {'id': 'r-new', 'seasonStats': <String, Object>{}},
                ],
              }
            : {
                'error': {'message': 'não encontrado'},
              };
        return http.Response(
          jsonEncode(value),
          value is Map && value.containsKey('error') ? 404 : 200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    WorldStatsSync.forget(person.id);
    await expectLater(
      WorldStatsSync(
        sql: sql,
        apiFactory: api,
      ).refreshPlayer(person, playerId: 'gabigol'),
      throwsA(isA<WorldStatsNotLinked>()),
    );
    await FcScoreRepository(sql: sql)
        .rememberCareerAddress(apiLink(), Uri.parse('http://pc:38291/api'));
    final sync = WorldStatsSync(sql: sql, apiFactory: api);
    final result = await sync.refreshPlayer(person, playerId: 'gabigol');
    expect(result!.seasonId, 's2028');
    expect(result.lines.map((l) => l.appearances), [23, 3, 2]);
    final mapped = result.lines.last;
    expect(mapped.tournamentId, 'league:1014');
    expect(mapped.name, localLeague());
    expect(
      mapped.teamName,
      GameCatalog.current!.teamLabel(person.fifaVersion, '40-13'),
    );
    expect(result.lines.any((l) => l.name == 'Brasileirão'), isFalse);
    final lines = (await repo.seasonLines(person, 'gabigol'))['s2028']!;
    expect(CompetitionLine.total(lines).appearances, 28);
    expect(lines.first.date, DateTime(2028, 7, 20));
    expect(await sync.refreshTeam(person, teamA.id), 1);
    expect(health, hasLength(1));
  });

  test('Season numbers merge the API with edits', () async {
    var lines = (await repo.seasonLines(person, 'gabigol'))['s2028']!;
    expect(lines.single.goals, 12);
    expect(lines.single.fromApi, isTrue);
    expect(lines.single.teamId, teamA.id);
    await repo.saveLine(
      person,
      'gabigol',
      's2028',
      CompetitionLine(
        key: lines.single.key,
        name: lines.single.name,
        tournamentId: lines.single.tournamentId,
        appearances: 21,
        goals: 14,
        assists: 3,
        rating: 7.4,
      ),
    );
    await repo.saveLine(
      person,
      'gabigol',
      's2028',
      CompetitionLine(
        key: 'cup',
        name: 'Copa do Brasil',
        tournamentId: 'cup',
        appearances: 4,
        goals: 3,
        rating: 7.9,
      ),
    );
    lines = (await repo.seasonLines(person, 'gabigol'))['s2028']!;
    final league = lines.firstWhere((l) => l.tournamentId == 'league:1014');
    expect(league.name, localLeague());
    expect(league.goals, 14);
    expect(league.overridesApi, isTrue);
    final total = CompetitionLine.total(lines);
    expect(total.goals, 17);
    expect(total.appearances, 25);
    expect(total.rating, closeTo((7.4 * 21 + 7.9 * 4) / 25, .001));
    await repo.deleteLine(person, league.manualId!);
    lines = (await repo.seasonLines(person, 'gabigol'))['s2028']!;
    expect(lines.firstWhere((l) => l.tournamentId == 'league:1014').goals, 12);
    final totals = await repo.seasonTotals(person, 's2028', ['gabigol']);
    expect(totals['gabigol']!.goals, 15);
  });

  Future<void> mount(
    WidgetTester tester,
    Widget home, {
    bool dark = true,
    Size size = const Size(390, 1400),
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
    final directory = Platform.environment['OTHER_PREVIEW_DIR'];
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

  for (final dark in [true, false]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('Squads open teams and player profiles ($theme)', (
      tester,
    ) async {
      await mount(
        tester,
        OtherPlayersPage(person: person, sql: sql, repository: repo),
        dark: dark,
      );
      expect(find.text('Outros jogadores'), findsOneWidget);
      await preview(tester, 'teams-$theme');
      await tester.tap(find.byKey(ValueKey('other-team/${teamA.id}')));
      await settleDataFrames(tester);
      expect(find.text('Goleiros · 1'), findsOneWidget);
      expect(find.text('20 J · 12 G · 3 A · nota 7,3'), findsOneWidget);
      await preview(tester, 'team-$theme');
      await tester.tap(find.byKey(const ValueKey('other-player/gabigol')));
      await settleDataFrames(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('player-club')),
          matching: find.text(teamA.label),
        ),
        findsOneWidget,
      );
      await preview(tester, 'profile-details-$theme');
      await tester.tap(find.text('Temporada'));
      await settleDataFrames(tester);
      expect(find.byKey(const ValueKey('player-world-season')), findsOneWidget);
      expect(find.text('Números do save em 30/06/2028'), findsOneWidget);
      await preview(tester, 'profile-season-$theme');
      await tester.tap(find.text('Transferências'));
      await settleDataFrames(tester);
      expect(find.text('Histórico de transferências'), findsOneWidget);
      await preview(tester, 'profile-transfers-$theme');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    });
  }

  testWidgets('Search, filters and a transfer from the profile', (
    tester,
  ) async {
    await mount(
      tester,
      OtherPlayersPage(person: person, sql: sql, repository: repo),
    );
    await tester.enterText(find.byKey(const ValueKey('other-search')), 'hul');
    await settleDataFrames(tester);
    expect(
      find.byKey(const ValueKey('other-player/catalog:c-hulk')),
      findsOneWidget,
    );
    await preview(tester, 'search');
    await tester.enterText(find.byKey(const ValueKey('other-search')), '');
    await tester.tap(find.byKey(const ValueKey('other-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-line/GOL')));
    await tester.pump();
    await preview(tester, 'filters');
    await tester.tap(find.byKey(const ValueKey('filter-apply')));
    await settleDataFrames(tester);
    expect(find.byKey(const ValueKey('other-player/pedro')), findsOneWidget);
    expect(find.byKey(const ValueKey('other-player/gabigol')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('other-player/pedro')));
    await settleDataFrames(tester);
    await tester.tap(find.byKey(const ValueKey('player-transfer')));
    await settleDataFrames(tester);
    await tester.tap(find.byKey(const ValueKey('transfer-type/loan')));
    await tester.pump();
    await preview(tester, 'transfer-sheet');
    await tester.tap(find.byKey(const ValueKey('transfer-save')));
    await tester.pump();
    expect(find.text('Escolha o clube de destino.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('Squads fit 320px with larger text', (tester) async {
    await mount(
      tester,
      OtherPlayersPage(person: person, sql: sql, repository: repo),
      size: const Size(320, 1400),
      scale: 1.3,
    );
    await preview(tester, 'narrow-teams');
    await tester.tap(find.byKey(ValueKey('other-team/${teamB.id}')));
    await settleDataFrames(tester);
    await preview(tester, 'narrow-team');
    await tester.tap(find.byKey(const ValueKey('other-player/lucas')));
    await settleDataFrames(tester);
    await preview(tester, 'narrow-profile');
    for (final tab in ['Temporada', 'Transferências', 'Carreira']) {
      await tester.tap(find.text(tab));
      await settleDataFrames(tester);
      await preview(tester, 'narrow-profile-$tab');
      expect(tester.takeException(), isNull, reason: tab);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}
