import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/SelectRealPlayerPage.dart';
import 'package:mcmanager/ManagerCareer/TeamTransfers/SelectTransferPlayerPage.dart';
import 'package:mcmanager/FcScore/FcScoreWidgets.dart';
import 'package:mcmanager/FcScore/FcScoreDataPage.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/utils/Components/PlayerSearchCard.dart';
import 'package:mcmanager/utils/Components/TeamLogo.dart';
import 'package:mcmanager/utils/PlayerClubLookup.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/GamePlayers.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';
import 'fcscore_fixture.dart';

class _SearchTranslations extends AssetLoader {
  const _SearchTranslations(this.values);
  final Map<String, dynamic> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late SqlService sql;
  final person = reviewPerson();
  final season = reviewSeason(id: 's2028', year: 2028);
  late GamePlayer messi, mbappe;
  late Map<String, dynamic> translations;
  final capture = GlobalKey();
  setUpAll(() async {
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory('build/player-search-docs').absolute.path,
        );
    await EasyLocalization.ensureInitialized();
    translations = jsonDecode(
      await rootBundle.loadString('assets/translations/pt_BR.json'),
    ) as Map<String, dynamic>;
    await GameCatalog.load();
    final players = await GamePlayers.load('FC26');
    messi = players.singleWhere((p) => p.id == '158023');
    mbappe = players.singleWhere((p) => p.id == '231747');
    await loadPreviewFonts();
  });
  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    await SqlService.ensureCompatibleSchema(db);
    await SqlService.ensureSeasonClosureSchema(db);
    await SqlService.ensureTransferReleaseSchema(db);
    await db.insert('Persons', person.toMap());
    await db.insert('Seasons', season.toMap());
    sql = SqlService.withDatabase(db);
  });
  tearDown(() => db.close());

  Future<void> linkPlayer({bool roster = false}) async {
    await db.insert('CustomCreatedPlayer', {
      'id': 'linked',
      'personId': person.id,
      'name': 'Lionel Messi',
      'realPlayerId': messi.id,
      'positionId': '23',
      'overall': 92,
      'potential': 93,
      'foot': 'Left',
      'realFace': 1,
      'fromRealPlayer': 1,
    });
    if (roster) {
      await db.insert('TeamPlayer', {
        'id': 'roster',
        'personId': person.id,
        'seasonId': season.id,
        'playerId': 'linked',
        'isBench': 0,
        'overall': 92,
      });
    }
  }

  test(
    'Resolves source IDs to edition-specific club names and logos',
    () async {
      final clubs = await PlayerClubLookup.load(
        sql: sql,
        person: person,
        seasonId: season.id,
      );
      expect(clubs.club(player: messi)?.label, 'Inter Miami CF');
      expect(clubs.club(player: messi)?.imageUrl, contains('Miami'));
      expect(clubs.club(player: mbappe)?.label, 'Real Madrid');
      expect(clubs.club(player: mbappe)?.id, '32-14');
    },
  );

  test('Career roster, API club, pending moves and departures override the catalog', () async {
    await linkPlayer(roster: true);
    var clubs = await PlayerClubLookup.load(
      sql: sql,
      person: person,
      seasonId: season.id,
    );
    expect(clubs.club(player: messi)?.id, person.teamId);
    await db.delete('TeamPlayer');
    await db.insert('FcScoreWorldTeam', {
      'personId': person.id,
      'seasonId': season.id,
      'remoteId': '200',
      'teamId': '32-14',
      'rawJson': '{}',
    });
    await db.insert('FcScoreWorldPlayer', {
      'personId': person.id,
      'seasonId': season.id,
      'remoteTeamId': '200',
      'remotePlayerId': messi.id,
      'playerId': 'linked',
      'rawJson': '{}',
    });
    clubs = await PlayerClubLookup.load(
      sql: sql,
      person: person,
      seasonId: season.id,
    );
    expect(clubs.club(player: messi)?.label, 'Real Madrid');
    await db.insert('TeamTransferItem', {
      'id': 'future',
      'personId': person.id,
      'seasonId': season.id,
      'playerInstanceId': 'linked',
      'fromTeamId': '32-14',
      'toTeamId': person.teamId,
      'type': 'buy',
      'date': '2028-01-01',
      'releaseDate': '2029-01-01',
      'movementApplied': 0,
    });
    clubs = await PlayerClubLookup.load(
      sql: sql,
      person: person,
      seasonId: season.id,
    );
    expect(clubs.club(player: messi)?.label, 'Real Madrid');
    await db.update('TeamTransferItem', {
      'movementApplied': 1,
      'toTeamId': null,
      'type': 'endOfContract',
    });
    clubs = await PlayerClubLookup.load(
      sql: sql,
      person: person,
      seasonId: season.id,
    );
    expect(clubs.club(player: messi)?.label, 'Sem clube');
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(seconds: 11));
    }
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester,
    Widget home, {
    bool light = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('pt', 'BR')],
        startLocale: const Locale('pt', 'BR'),
        path: 'assets/translations',
        assetLoader: _SearchTranslations(translations),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            debugShowCheckedModeBanner: false,
            theme: light ? managerLightTheme : managerDarkTheme,
            builder: (context, child) =>
                RepaintBoundary(key: capture, child: child!),
            home: home,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> preview(WidgetTester tester, String name) async {
    final directory = Platform.environment['PLAYER_SEARCH_PREVIEW_DIR'];
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

  for (final light in [false, true]) {
    testWidgets(
      'Catalog selection shows photos and career club, keeping keyboard focus ($light)',
      (tester) async {
        await tester.runAsync(() => linkPlayer(roster: true));
        await mount(
          tester,
          SelectRealPlayerPage.pick(person: person, sql: sql),
          light: light,
        );
        final search = find.byType(TextField);
        await tester.enterText(search, messi.id);
        await settle(tester);
        expect(find.byType(PlayerSearchCard), findsOneWidget);
        expect(find.text('Sao Paulo'), findsOneWidget);
        expect(find.textContaining('92'), findsOneWidget);
        final field = tester.element(search);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pump();
        expect(identical(field, tester.element(search)), isTrue);
        expect(tester.widget<TextField>(search).controller!.text, messi.id);
        expect(find.byType(TeamLogo), findsOneWidget);
        await preview(tester, 'catalog-${light ? 'light' : 'dark'}');
        expect(tester.takeException(), isNull);
        await unmount(tester);
      },
    );
  }

  testWidgets(
    'Transfer selection preserves its layout and adds the club name and badge',
    (tester) async {
      TransferPlayerChoice? selected;
      await tester.runAsync(() => linkPlayer(roster: true));
      await mount(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await Navigator.push<TransferPlayerChoice>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SelectTransferPlayerPage(
                      person: person,
                      season: season,
                      rosterIds: const {'linked'},
                      sql: sql,
                    ),
                  ),
                );
              },
              child: const Text('Abrir busca'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir busca'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Lionel Messi');
      await settle(tester);
      expect(find.text('Lionel Messi', skipOffstage: true), findsNWidgets(2));
      expect(find.text('Sao Paulo'), findsOneWidget);
      expect(find.byType(PlayerClubCaption), findsOneWidget);
      await preview(tester, 'transfer-dark');
      await tester.tap(
        find.ancestor(
          of: find.byType(PlayerClubCaption),
          matching: find.byType(ListTile),
        ),
      );
      await settle(tester);
      expect(selected?.id, 'linked');
      expect(selected?.realPlayer, isNull);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets('Live API squad search shows photo cards and the linked club', (
    tester,
  ) async {
    final api = fakeApi(fcScoreAddress('192.168.0.20'));
    addTearDown(api.close);
    await mount(
      tester,
      FcScoreDataPage(
        api: api,
        remote: apiCareer(),
        kind: FcScoreView.squad,
        onMatch: (_) async {},
      ),
    );
    await tester.enterText(find.byType(TextField), 'Pedro');
    await settle(tester);
    expect(find.byType(PlayerSearchCard), findsOneWidget);
    expect(find.text('Pedro Silva'), findsOneWidget);
    expect(find.text('Sao Paulo'), findsOneWidget);
    await preview(tester, 'live-api-squad-dark');
    await unmount(tester);
  });

  testWidgets(
    'API player picker uses photo cards and returns the same player ID',
    (tester) async {
      String? selected;
      await mount(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await fcPick(
                  context,
                  title: 'Jogadores',
                  items: const [CatalogItem('local', 'Lionel Messi')],
                  playerVersion: 'FC26',
                  playerRows: {
                    'local': {'realPlayerId': messi.id, 'overall': 86},
                  },
                  playerClub: const CatalogItem(
                    'miami',
                    'Inter Miami',
                    leagueId: '39',
                  ),
                );
              },
              child: const Text('Selecionar'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Selecionar'));
      await settle(tester);
      expect(find.byType(PlayerSearchCard), findsOneWidget);
      expect(find.text('Inter Miami'), findsOneWidget);
      await preview(tester, 'api-picker-dark');
      await tester.tap(find.text('Lionel Messi'));
      await settle(tester);
      expect(selected, 'local');
      await unmount(tester);
    },
  );
}
