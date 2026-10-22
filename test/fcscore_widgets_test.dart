import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'data_frames.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/FcScore/FcScoreConnectionPage.dart';
import 'package:mcmanager/FcScore/FcScoreDataPage.dart';
import 'package:mcmanager/FcScore/FcScoreHubPage.dart';
import 'package:mcmanager/FcScore/FcScoreImportPage.dart';
import 'package:mcmanager/FcScore/FcScoreMappingPage.dart';
import 'package:mcmanager/FcScore/FcScoreModels.dart';
import 'package:mcmanager/FcScore/FcScoreRepository.dart';
import 'package:mcmanager/FcScore/FcScoreWidgets.dart';
import 'package:mcmanager/FcScore/FcScoreWorldImportPage.dart';
import 'package:mcmanager/FcScore/FcScoreWorldData.dart';
import 'package:mcmanager/FcScore/FcScoreCareerUpdate.dart';
import 'package:mcmanager/FcScore/FcScoreUpdateOptions.dart';
import 'package:mcmanager/FcScore/FcScoreClubCatalog.dart';
import 'package:mcmanager/FcScore/FcScoreClubMappingWidgets.dart';
import 'package:mcmanager/utils/Components/TeamLogo.dart';
import 'package:mcmanager/FcScore/FcScoreWorldMatchesPage.dart';
import 'package:mcmanager/FcScore/CareerCompetitionsPage.dart';
import 'package:mcmanager/FcScore/CareerCompetitionWidgets.dart';
import 'package:mcmanager/Common/FixtureDetailsPage.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/GamePlayers.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:mcmanager/models/Person.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fcscore_fixture.dart';
import 'fcscore_world_fixture.dart';
import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late FcScoreRepository repo;
  final person = reviewPerson();
  final boundary = GlobalKey();
  setUpAll(() async {
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory('build/fcscore-widget-docs').absolute.path,
        );
    await loadPreviewFonts();
    await GameCatalog.load();
    await GamePlayers.load(person.fifaVersion);
  });
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqlService.ensureCompatibleSchema(db);
    await SqlService.ensureSeasonClosureSchema(db);
    await SqlService.ensureFixtureFormationSchema(db);
    await SqlService.ensureOpponentLineupSchema(db);
    await db.execute(
      'ALTER TABLE ManagerFixtures ADD COLUMN opponentStats TEXT',
    );
    await db.insert('Persons', person.toMap());
    await db.insert('Seasons', reviewSeason(id: 's2028', year: 2028).toMap());
    repo = FcScoreRepository(sql: SqlService.withDatabase(db));
  });
  tearDown(() async => db.close());
  Future<void> settle(WidgetTester tester) async {
    await settleDataFrames(tester, minimumFrames: 40);
  }

  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    bool dark = true,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? managerDarkTheme : managerLightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: boundary, child: child!),
        ),
        home: page,
      ),
    );
    await settle(tester);
  }

  Future<void> reviewWorld(WidgetTester tester) async {
    final primary = find.byKey(const Key('fc-world-primary'));
    await tester.scrollUntilVisible(primary, 250);
    await tester.pumpAndSettle();
    if (find
        .descendant(of: primary, matching: find.text('Atualizar carreira'))
        .evaluate()
        .isNotEmpty) {
      return;
    }
    await tester.tap(primary);
    await settle(tester);
    for (var i = 0; i < 4; i++) {
      if (find
          .byKey(const Key('fc-world-confirm-mapping'))
          .evaluate()
          .isEmpty) {
        return;
      }
      await tester.tap(find.byKey(const Key('fc-world-confirm-mapping')));
      await settle(tester);
      if (find.byType(Dialog).evaluate().isNotEmpty) return;
    }
  }

  Future<void> prepareWorld(
    WidgetTester tester, {
    bool updateOwn = true,
    bool personalize = true,
  }) async {
    final customize = find.byKey(const Key('fc-world-customize'));
    if (personalize &&
        find
            .widgetWithText(AppBar, 'Atualizar carreira')
            .evaluate()
            .isNotEmpty) {
      await tester.scrollUntilVisible(customize, 200);
      await tester.pumpAndSettle();
      await tester.tap(customize);
      await settle(tester);
    }
    if (updateOwn) {
      final own = find.byKey(const Key('fc-update-own-players'));
      await tester.scrollUntilVisible(own, 200);
      await tester.pumpAndSettle();
      final tile = tester.widget<SwitchListTile>(own);
      if (!tile.value) await tester.tap(own);
      await tester.pumpAndSettle();
    }
    final prepare = find.textContaining('Preparar ');
    await tester.scrollUntilVisible(prepare, 200);
    await tester.pumpAndSettle();
    await tester.tap(prepare);
    await settle(tester);
    await reviewWorld(tester);
  }

  Future<void> preview(WidgetTester tester, String name) async {
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

  testWidgets(
    'Binding alone identifies an update and skips the full de-para on the first world download',
    (tester) async {
      final initial = apiLink()..teams['200'] = '40-1';
      final saved = (await tester.runAsync(
        () => repo.bind(
          link: initial,
          remote: apiCareer(),
          season: reviewSeason(id: 's2028', year: 2028),
          bringSquad: false,
        ),
      ))!;
      expect(saved.worldSync, isEmpty);
      final api = worldApi();
      await mount(
        tester,
        FcScoreWorldImportPage(
          api: api,
          remote: apiCareer(),
          repository: repo,
          person: person,
          link: saved,
        ),
      );
      expect(find.text('Importar para carreira'), findsNothing);
      final update = find.byKey(const Key('fc-world-update'));
      await tester.scrollUntilVisible(update, 150);
      await tester.tap(update);
      await settle(tester);
      expect(find.text('Atualização concluída'), findsOneWidget);
      expect(find.textContaining('De-para ·'), findsNothing);
      expect(
        (await tester.runAsync(() => db.query('FcScoreCompetition')))!.length,
        1,
      );
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      api.close();
    },
  );
  testWidgets(
    'Personalized review shows only a new player and reveals configured players on request',
    (tester) async {
      final stale = apiLink()
        ..teams['200'] = '40-1'
        ..teams['300'] = 'new:Terceiro FC';
      final confirmed = stale.copy();
      await tester.runAsync(
        () => repo.importWorld(
          person: person,
          link: confirmed,
          data: worldData(),
          importOwnMatches: false,
        ),
      );
      final before = await tester.runAsync(() => db.query('FcScoreCareerLink'));
      stale.players['20'] = 'new';
      final data = worldData();
      (data.teams.last['roster'] as List).add(
        apiPlayer(111, 'Nova contratação'),
      );
      (data.teams[1]['roster'] as List).first['name'] = 'Nome alterado na API';
      final api = worldApi(snapshot: data);
      await mount(
        tester,
        FcScoreWorldImportPage(
          api: api,
          remote: apiCareer(),
          repository: repo,
          person: person,
          link: stale,
        ),
      );
      await prepareWorld(tester);
      expect(find.textContaining('De-para ·'), findsNothing);
      final players = find.widgetWithText(ListTile, 'Jogadores');
      await tester.scrollUntilVisible(players, -200);
      await tester.tap(players);
      await settle(tester);
      expect(
        find.byKey(const ValueKey('fc-world-mapping-111')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('fc-world-mapping-20')), findsNothing);
      expect(find.byKey(const Key('fc-world-show-configured')), findsOneWidget);
      await preview(tester, 'only-new-bindings');
      await tester.tap(find.byKey(const Key('fc-world-show-configured')));
      await tester.pumpAndSettle();
      final savedPlayer = find.byKey(const ValueKey('fc-world-mapping-20'));
      await tester.scrollUntilVisible(
        savedPlayer,
        150,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(savedPlayer, findsOneWidget);
      expect(
        await tester.runAsync(() => db.query('FcScoreCareerLink')),
        before,
      );
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      api.close();
    },
  );
  testWidgets(
    'New season and a renamed save reuse confirmed team/player mappings without restarting review',
    (tester) async {
      final link = apiLink()
        ..teams['200'] = '40-1'
        ..teams['300'] = 'new:Terceiro FC';
      await tester.runAsync(
        () => repo.importWorld(
          person: person,
          link: link,
          data: worldData(),
          importOwnMatches: false,
          preserveOwnPlayers: true,
          updateOveralls: false,
        ),
      );
      final season = reviewSeason(id: 's2029', year: 2029);
      await tester.runAsync(() => db.insert('Seasons', season.toMap()));
      final incoming = FcScoreLink.fromMap({
        ...link.toMap(),
        'saveId': 'save-NEW',
      });
      final remote = apiCareer(saveId: 'save-NEW');
      remote.overview['currentDate'] = '2029-06-30';
      final data = worldData(date: '2029-06-30');
      for (final f in data.fixtures) {
        f['date'] = '2029-06-25';
      }
      final api = worldApi(snapshot: data);
      await mount(
        tester,
        FcScoreWorldImportPage(
          api: api,
          remote: remote,
          repository: repo,
          person: person,
          link: incoming,
        ),
      );
      final update = find.byKey(const Key('fc-world-update'));
      await tester.scrollUntilVisible(update, 150);
      await tester.tap(update);
      await settle(tester);
      expect(find.text('Atualização concluída'), findsOneWidget);
      expect(find.textContaining('De-para ·'), findsNothing);
      final saved = (await tester.runAsync(() => repo.linkFor(person.id)))!;
      expect(saved.seasonId, 's2029');
      expect(saved.teams['200'], link.teams['200']);
      for (final e in link.players.entries) {
        expect(saved.players[e.key], e.value);
      }
      expect(
        (await tester.runAsync(() => db.query('CustomCreatedPlayer')))!.length,
        2,
      );
      expect(saved.worldSync['s2029']!.updateOveralls, isFalse);
      expect(saved.worldSync['s2028']!.ignoredMatchKeys.length, 1);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      api.close();
    },
  );
  testWidgets(
    'Saved binding offers an optional review and the hub/data shortcuts consistently say update',
    (tester) async {
      final link = apiLink()..teams['200'] = '40-1';
      await tester.runAsync(() => repo.moveLink(link, 'save-OLD'));
      final api = fakeApi(fcScoreAddress('pc'));
      await mount(
        tester,
        FcScoreMappingPage(
          remote: apiCareer(),
          repository: repo,
          initialPerson: person,
        ),
      );
      expect(find.byKey(const Key('fc-resume-binding')), findsOneWidget);
      expect(find.byKey(const Key('fc-bind')), findsNothing);
      await tester.tap(find.byKey(const Key('fc-review-saved-binding')));
      await settle(tester);
      final full = find.byKey(const Key('fc-bind'));
      await tester.scrollUntilVisible(full, 200);
      expect(full, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      await mount(
        tester,
        FcScoreHubPage(
          api: api,
          remote: apiCareer(),
          repository: repo,
          person: person,
          link: link,
        ),
      );
      final update = find.text('Atualizar carreira');
      await tester.scrollUntilVisible(update, 150);
      expect(find.text('Importar para carreira'), findsNothing);
      final classification = find.widgetWithText(InkWell, 'Classificação');
      await tester.scrollUntilVisible(classification, 150);
      await tester.tap(classification);
      await settle(tester);
      expect(find.widgetWithText(AppBar, 'Classificação'), findsOneWidget);
      expect(find.text('Atualizar carreira'), findsOneWidget);
      expect(find.text('Importar para carreira'), findsNothing);
      await preview(tester, 'update-from-career-data');
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      api.close();
    },
  );
  testWidgets(
    'Reconnecting from the general API menu follows a renamed save without showing the binding form',
    (tester) async {
      final link = apiLink()..teams['200'] = '40-1';
      await tester.runAsync(() => repo.moveLink(link, 'save-OLD'));
      await mount(
        tester,
        FcScoreConnectionPage(repository: repo, apiFactory: fakeApi),
      );
      await tester.enterText(find.byKey(const Key('fc-ip')), '192.168.0.20');
      await tester.tap(find.byKey(const Key('fc-connect')));
      await settle(tester);
      await tester.tap(find.text('Minha carreira'));
      await settle(tester);
      expect(find.text('Vincular carreira'), findsNothing);
      final update = find.text('Atualizar carreira');
      await tester.scrollUntilVisible(update, 150);
      expect(update, findsOneWidget);
      expect(
        (await tester.runAsync(() => repo.linkFor(person.id)))!.saveId,
        'save-A',
      );
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'Refreshing the open hub follows a renamed file and preserves configured links',
    (tester) async {
      final original = FcScoreLink.fromMap({
        ...apiLink().toMap(),
        'saveId': 'save-OLD',
      });
      await tester.runAsync(() => repo.moveLink(original, original.saveId));
      final delegate = fakeApi(fcScoreAddress('pc'));
      final requests = <String>[];
      final api = FcScoreApi(
        fcScoreAddress('pc'),
        client: MockClient((r) async {
          final path = r.url.path.substring('/api/'.length);
          requests.add(path);
          if (path.startsWith('careers/save-OLD')) {
            return http.Response('{}', 404);
          }
          final list = path == 'careers' || path.endsWith('/competitions');
          final payload = list
              ? await delegate.list(path)
              : await delegate.object(path);
          return http.Response(
            jsonEncode(payload),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await mount(
        tester,
        FcScoreHubPage(
          api: api,
          remote: apiCareer(saveId: 'save-OLD'),
          repository: repo,
          person: person,
          link: original,
        ),
      );
      await tester.tap(find.byTooltip('Atualizar dados do save'));
      await settle(tester);
      final saved = (await tester.runAsync(() => repo.linkFor(person.id)))!;
      expect(saved.saveId, 'save-A');
      expect(saved.teams, original.teams);
      expect(saved.competitions, original.competitions);
      expect(requests, contains('careers/save-OLD'));
      expect(requests, contains('careers/save-A'));
      expect(await tester.runAsync(() => db.query('ManagerFixtures')), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      api.close();
      delegate.close();
    },
  );

  for (final dark in [true, false]) {
    testWidgets(
      'Imported competition tabs work offline at 320px ${dark ? 'dark' : 'light'}',
      (tester) async {
        final link = apiLink()..teams['300'] = 'new:Terceiro FC';
        await tester.runAsync(
          () => repo.importWorld(person: person, link: link, data: worldData()),
        );
        final competitions = await tester.runAsync(
          () => repo.careerCompetitions(person.id),
        );
        await mount(
          tester,
          CareerCompetitionPage(
            person: person,
            repository: repo,
            competition: competitions!.single,
          ),
          dark: dark,
          width: 320,
          scale: 1.15,
        );
        expect(find.text('PTS'), findsOneWidget);
        expect(
          tester.getRect(find.byType(TabBar)).left,
          greaterThanOrEqualTo(0),
        );
        await preview(tester, 'competition-table-${dark ? 'dark' : 'light'}');
        await tester.tap(find.text('Partidas'));
        await settle(tester);
        expect(find.text('Resultados'), findsOneWidget);
        await preview(tester, 'competition-matches-${dark ? 'dark' : 'light'}');
        await tester.tap(find.text('Artilharia'));
        await settle(tester);
        expect(find.text('João Souza'), findsOneWidget);
        expect(find.text('18'), findsOneWidget);
        await preview(tester, 'competition-scorers-${dark ? 'dark' : 'light'}');
        await tester.tap(find.text('Equipes'));
        await settle(tester);
        expect(find.text('Terceiro FC'), findsOneWidget);
        await tester.tap(find.text('Terceiro FC'));
        await settle(tester);
        expect(find.text('30. Lucas Paiva'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'paiva');
        await tester.showKeyboard(find.byType(TextField));
        await settle(tester);
        expect(tester.testTextInput.isVisible, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
      },
    );
    for (final width in [320.0, 390.0]) {
      testWidgets(
        'Connection uses existing theme with margins at $width ${dark ? 'dark' : 'light'}',
        (tester) async {
          await mount(
            tester,
            FcScoreConnectionPage(repository: repo),
            dark: dark,
            width: width,
            scale: 1.15,
          );
          expect(find.text('Conecte seu PC'), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(
            tester.getRect(find.byKey(const Key('fc-ip'))).left,
            greaterThanOrEqualTo(20),
          );
          if (dark && width == 390) await preview(tester, 'connection-dark');
          await tester.pumpWidget(const SizedBox());
          await settle(tester);
        },
      );
    }
  }
  for (final dark in [true, false]) {
    testWidgets(
      'New season rankings and roster statistics follow the existing UI ${dark ? 'dark' : 'light'}',
      (tester) async {
        final link = apiLink()..teams['300'] = 'new:Terceiro FC';
        await tester.runAsync(
          () => repo.importWorld(
            person: person,
            link: link,
            data: worldStatistics(),
          ),
        );
        final competition = (await tester.runAsync(
          () => repo.careerCompetitions(person.id),
        ))!.single;
        await mount(
          tester,
          CareerCompetitionPage(
            person: person,
            repository: repo,
            competition: competition,
          ),
          dark: dark,
          width: 320,
          scale: 1.3,
        );
        await tester.tap(find.text('Artilharia'));
        await settle(tester);
        expect(find.text('14'), findsOneWidget);
        await preview(tester, 'season-goals-${dark ? 'dark' : 'light'}');
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Assistências').last);
        await tester.pumpAndSettle();
        expect(find.text('6'), findsOneWidget);
        await preview(tester, 'season-assists-${dark ? 'dark' : 'light'}');
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Jogos sem sofrer gols (goleiros)').last);
        await tester.pumpAndSettle();
        expect(find.text('Lucas Paiva'), findsOneWidget);
        expect(find.text('Pedro Silva'), findsNothing);
        await tester.tap(find.text('Lucas Paiva'));
        await settle(tester);
        await tester.tap(find.textContaining('Lucas Paiva'));
        await tester.pumpAndSettle();
        final detailsScroll = find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text('Estatísticas da temporada'),
          150,
          scrollable: detailsScroll,
        );
        await tester.pumpAndSettle();
        expect(find.text('Estatísticas da temporada'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await preview(tester, 'season-player-${dark ? 'dark' : 'light'}');
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
        await tester.pump(const Duration(seconds: 11));
      },
    );
  }
  for (final dark in [true, false]) {
    testWidgets(
      'Team conflict names the teams, can be cancelled and opens only those bindings ${dark ? 'dark' : 'light'}',
      (tester) async {
        final link = apiLink()
          ..teams['200'] = '40-1'
          ..teams['300'] = 'new:Terceiro FC';
        await tester.runAsync(
          () => repo.importWorld(person: person, link: link, data: worldData()),
        );
        final original = await tester.runAsync(
          () => db.query('FcScoreWorldTeam'),
        );
        link.teams['300'] = '40-1';
        final api = worldApi();
        await mount(
          tester,
          FcScoreWorldImportPage(
            api: api,
            remote: apiCareer(),
            repository: repo,
            person: person,
            link: link,
          ),
          dark: dark,
          width: 320,
          scale: 1.2,
        );
        final update = find.byKey(const Key('fc-world-update'));
        await tester.scrollUntilVisible(update, 200);
        await tester.tap(update);
        await settle(tester);
        if (find.byType(AlertDialog).evaluate().isEmpty) {
          final save = find.byKey(const Key('fc-world-primary'));
          await tester.scrollUntilVisible(save, 200);
          await tester.tap(save);
          await settle(tester);
        }
        final dialog = find.byType(AlertDialog);
        expect(
          find.descendant(
            of: dialog,
            matching: find.textContaining('Rival FC'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialog,
            matching: find.textContaining('Terceiro FC'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.textContaining('200')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.textContaining('300')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await preview(tester, 'team-conflict-${dark ? 'dark' : 'light'}');
        await tester.tap(find.text('Agora não'));
        await settle(tester);
        expect(
          await tester.runAsync(() => db.query('FcScoreWorldTeam')),
          original,
        );
        final correct = find.byKey(const Key('fc-review-mapping-issues'));
        await tester.scrollUntilVisible(correct, -200);
        await tester.tap(correct);
        await settle(tester);
        await tester.tap(find.byKey(const Key('fc-correct-mapping')));
        await settle(tester);
        expect(find.text('De-para · Equipes'), findsOneWidget);
        expect(find.byKey(const Key('fc-world-mapping-598')), findsNothing);
        expect(find.byKey(const Key('fc-world-mapping-200')), findsOneWidget);
        final third = find.byKey(const Key('fc-world-mapping-300'));
        await tester.scrollUntilVisible(
          third,
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(third);
        await settle(tester);
        await tester.tap(find.text('Criar novo cadastro'));
        await settle(tester);
        await tester.tap(find.text('Usar este nome'));
        await settle(tester);
        await tester.tap(find.byKey(const Key('fc-world-confirm-mapping')));
        await settle(tester);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byKey(const Key('fc-review-mapping-issues')), findsNothing);
        final save = find.byKey(const Key('fc-world-update'));
        await tester.scrollUntilVisible(save, 200);
        await tester.tap(save);
        await settle(tester);
        expect(find.textContaining('concluída'), findsOneWidget);
        expect(link.teams['200'], '40-1');
        expect(link.teams['300'], isNot('40-1'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
        api.close();
      },
    );
  }

  testWidgets(
    'Whole competition import wizard reviews bindings and opens career data',
    (tester) async {
      final api = worldApi();
      final link = apiLink();
      await mount(
        tester,
        FcScoreWorldImportPage(
          api: api,
          remote: apiCareer(),
          repository: repo,
          person: person,
          link: link,
        ),
      );
      expect(find.text('Brasileirão'), findsOneWidget);
      await prepareWorld(tester);
      await tester.scrollUntilVisible(find.text('Jogadores nos elencos'), -250);
      await tester.pumpAndSettle();
      expect(find.text('Jogadores nos elencos'), findsOneWidget);
      await preview(tester, 'world-import-review-dark');
      await tester.tap(find.widgetWithText(ListTile, 'Equipes'));
      await settle(tester);
      expect(find.text('De-para · Equipes'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'terceiro');
      await settle(tester);
      expect(find.text('Terceiro FC'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      await reviewWorld(tester);
      final button = find.widgetWithText(
        FilledButton,
        'Importar para carreira',
      );
      await tester.scrollUntilVisible(button, 300);
      await tester.tap(button);
      await settle(tester);
      expect(find.textContaining('concluída'), findsOneWidget);
      final see = find.text('Ver competições da carreira');
      await tester.scrollUntilVisible(see, 200);
      await tester.tap(see);
      await settle(tester);
      expect(find.text('Classificação'), findsOneWidget);
      expect(find.textContaining('Atualizada em 30/06/2028'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      api.close();
    },
  );
  for (final dark in [true, false]) {
    testWidgets(
      'Repeated import updates only new games without repeating the full de-para ${dark ? 'dark' : 'light'}',
      (tester) async {
        final link = apiLink()
          ..teams['200'] = '40-1'
          ..teams['300'] = 'new:Terceiro FC';
        await tester.runAsync(
          () => repo.importWorld(
            person: person,
            link: link,
            data: worldData(),
            importOwnMatches: false,
            preserveOwnPlayers: true,
            updateOveralls: false,
          ),
        );
        final data = worldData(date: '2028-07-15');
        data.fixtures.last['played'] = true;
        data.fixtures.last['home'] = {
          ...fcObject(data.fixtures.last['home']),
          'goals': 0,
        };
        data.fixtures.last['away'] = {
          ...fcObject(data.fixtures.last['away']),
          'goals': 1,
        };
        final remote = FcScoreRemoteCareer(
          overview: {...apiCareer().overview, 'currentDate': data.currentDate},
          squad: apiCareer().squad,
          competitions: apiCareer().competitions,
          gameVersion: 'FC26',
        );
        final api = worldApi(snapshot: data);
        await mount(
          tester,
          FcScoreWorldImportPage(
            api: api,
            remote: remote,
            repository: repo,
            person: person,
            link: link,
          ),
          dark: dark,
          width: 320,
          scale: 1.3,
        );
        final update = find.byKey(const Key('fc-world-update'));
        await tester.scrollUntilVisible(update, 200);
        await tester.pumpAndSettle();
        expect(find.text('Preparar importação'), findsNothing);
        expect(find.byKey(const Key('fc-world-customize')), findsOneWidget);
        await preview(tester, 'quick-update-${dark ? 'dark' : 'light'}');
        await tester.tap(update);
        await settle(tester);
        expect(find.textContaining('concluída'), findsOneWidget);
        expect(find.textContaining('De-para ·'), findsNothing);
        final fixtures = await tester.runAsync(
          () => db.query('ManagerFixtures'),
        );
        expect(fixtures!.length, 1);
        expect(fixtures.single['date'], startsWith('2028-07-15'));
        final saved = (await tester.runAsync(() => repo.linkFor(person.id)))!;
        expect(saved.worldSync['s2028']!.ignoredMatchKeys.length, 1);
        expect(saved.worldSync['s2028']!.updateOveralls, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
        api.close();
      },
    );
  }
  testWidgets(
    'Personalize revisits ignored games and preserves saved own-squad and overall choices',
    (tester) async {
      final link = apiLink()
        ..teams['200'] = '40-1'
        ..teams['300'] = 'new:Terceiro FC';
      await tester.runAsync(
        () => repo.importWorld(
          person: person,
          link: link,
          data: worldData(),
          importOwnMatches: false,
          preserveOwnPlayers: true,
          updateOveralls: false,
        ),
      );
      final api = worldApi();
      await mount(
        tester,
        FcScoreWorldImportPage(
          api: api,
          remote: apiCareer(),
          repository: repo,
          person: person,
          link: link,
        ),
      );
      final customize = find.byKey(const Key('fc-world-customize'));
      await tester.scrollUntilVisible(customize, 200);
      await tester.tap(customize);
      await settle(tester);
      await prepareWorld(tester, updateOwn: false, personalize: false);
      final review = find.widgetWithText(ListTile, 'Revisar partidas');
      await tester.scrollUntilVisible(review, 200);
      await tester.tap(review);
      await settle(tester);
      expect(find.text('Ignorada anteriormente'), findsOneWidget);
      expect(find.text('Confirmar seleção · 0'), findsOneWidget);
      await tester.tap(find.text('Selecionar novos'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmar seleção · 0'), findsOneWidget);
      await tester.tap(find.text('Ignoradas'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Ignorada anteriormente'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(FcScoreWorldMatchesPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar seleção · 1'));
      await settle(tester);
      final save = find.byKey(const Key('fc-world-primary'));
      await tester.scrollUntilVisible(save, 250);
      await tester.tap(save);
      await settle(tester);
      expect(find.textContaining('concluída'), findsOneWidget);
      expect(
        (await tester.runAsync(() => db.query('ManagerFixtures')))!.length,
        1,
      );
      expect(link.worldSync['s2028']!.ignoredMatchKeys, isEmpty);
      expect(link.worldSync['s2028']!.preserveOwnPlayers, isTrue);
      expect(link.worldSync['s2028']!.updateOveralls, isFalse);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      api.close();
    },
  );
  testWidgets(
    'Quick update shows only a new player conflict and cancellation saves nothing',
    (tester) async {
      final link = apiLink()
        ..teams['200'] = '40-1'
        ..teams['300'] = 'new:Terceiro FC';
      await tester.runAsync(
        () => repo.importWorld(
          person: person,
          link: link,
          data: worldData(),
          importOwnMatches: false,
          preserveOwnPlayers: true,
        ),
      );
      final before = await tester.runAsync(() => db.query('FcScoreCareerLink'));
      final data = worldData();
      (data.teams.last['roster'] as List).add({
        ...apiPlayer(111, ''),
        'overall': null,
      });
      final api = worldApi(snapshot: data);
      await mount(
        tester,
        FcScoreWorldImportPage(
          api: api,
          remote: apiCareer(),
          repository: repo,
          person: person,
          link: link,
        ),
      );
      final update = find.byKey(const Key('fc-world-update'));
      await tester.scrollUntilVisible(update, 200);
      await tester.tap(update);
      await settle(tester);
      expect(find.text('Corrigir vínculos'), findsOneWidget);
      expect(find.text('Etapa 1 de 1'), findsOneWidget);
      expect(find.textContaining('De-para ·'), findsNothing);
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      expect(
        await tester.runAsync(() => db.query('FcScoreCareerLink')),
        before,
      );
      expect(await tester.runAsync(() => db.query('ManagerFixtures')), isEmpty);
      expect(find.byKey(const Key('fc-world-customize')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      api.close();
    },
  );
  for (final dark in [true, false]) {
    testWidgets(
      'Required de-para generates other clubs and preserves the current squad ${dark ? 'dark' : 'light'}',
      (tester) async {
        await tester.runAsync(() async {
          await db.insert('CustomCreatedPlayer', {
            'id': 'nicolas',
            'personId': person.id,
            'name': 'Nicolas',
            'overall': 71,
            'realPlayerId': '10',
            'positionId': '25',
            'potential': 76,
            'realFace': 0,
            'fromRealPlayer': 0,
            'foot': 'Right',
            'customAvatarFilePath': 'photo.png',
          });
          await db.insert('TeamPlayer', {
            'id': 'roster-nicolas',
            'personId': person.id,
            'seasonId': 's2028',
            'playerId': 'nicolas',
            'overall': 71,
            'shirtNumber': 9,
            'wage': 1234,
            'isBench': 0,
          });
          await db.insert('CustomClub', {
            'id': 'third-existing',
            'label': 'Terceiro FC',
            'fifaVersion': 'FC26',
            'personId': '',
            'leagueId': '1014',
          });
        });
        final before = await tester.runAsync(() => db.query('TeamPlayer'));
        final data = worldData();
        final own = (data.teams.first['roster'] as List).first as Map;
        own['name'] = 'Nicolas';
        own['overall'] = 99;
        (data.teams.first['roster'] as List).add({
          ...apiPlayer(98163, ''),
          'overall': null,
        });
        for (final t in data.teams.skip(1)) {
          final p = (t['roster'] as List).first as Map;
          p['name'] = '';
          p['overall'] = null;
        }
        final api = worldApi(snapshot: data),
            link = apiLink()..teams['300'] = 'new:Terceiro FC';
        await mount(
          tester,
          FcScoreWorldImportPage(
            api: api,
            remote: apiCareer(),
            repository: repo,
            person: person,
            link: link,
          ),
          dark: dark,
          width: 320,
          scale: 1.3,
        );
        final ownOption = find.byKey(const Key('fc-update-own-players'));
        await tester.scrollUntilVisible(ownOption, 200);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(ownOption).value, isFalse);
        await tester.scrollUntilVisible(find.text('Preparar importação'), 200);
        await tester.tap(find.text('Preparar importação'));
        await settle(tester);
        expect(find.byType(Dialog), findsNothing);
        expect(
          find.widgetWithText(FilledButton, 'Importar para carreira'),
          findsNothing,
        );
        final primary = find.byKey(const Key('fc-world-primary'));
        await tester.scrollUntilVisible(primary, 200);
        await tester.pumpAndSettle();
        await tester.tap(primary);
        await settle(tester);
        expect(find.text('De-para · Competições'), findsOneWidget);
        await tester.pageBack();
        await settle(tester);
        expect(
          find.widgetWithText(FilledButton, 'Importar para carreira'),
          findsNothing,
        );
        await tester.tap(primary);
        await settle(tester);
        await tester.tap(find.byKey(const Key('fc-world-confirm-mapping')));
        await settle(tester);
        expect(find.text('De-para · Equipes'), findsOneWidget);
        final third = find.byKey(const Key('fc-world-mapping-300'));
        expect(tester.widget<FcChoice>(third).value, 'Terceiro FC');
        await tester.tap(find.byKey(const Key('fc-world-confirm-mapping')));
        await settle(tester);
        await tester.tap(find.byKey(const Key('fc-world-confirm-mapping')));
        await settle(tester);
        expect(find.text('De-para · Jogadores'), findsOneWidget);
        await tester.tap(find.text('Meu clube'));
        await tester.pumpAndSettle();
        expect(find.text('Preservado · Nicolas'), findsOneWidget);
        expect(
          tester
              .widget<ListTile>(
                find.descendant(
                  of: find.byKey(const Key('fc-world-mapping-10')),
                  matching: find.byType(ListTile),
                ),
              )
              .onTap,
          isNull,
        );
        await preview(
          tester,
          'v0.9.6-player-review-${dark ? 'dark' : 'light'}',
        );
        await tester.enterText(find.byType(TextField), 'Nicolas');
        await tester.showKeyboard(find.byType(TextField));
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isTrue);
        expect(tester.takeException(), isNull);
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        tester.view.resetViewInsets();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Outros clubes'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('fc-generate-other-clubs')));
        await tester.pumpAndSettle();
        await preview(tester, 'v0.9.6-generated-${dark ? 'dark' : 'light'}');
        expect(find.textContaining('Criar:'), findsNWidgets(2));
        expect(find.byType(Dialog), findsNothing);
        expect(
          (await tester.runAsync(() => db.query('CustomCreatedPlayer')))!
              .length,
          1,
        );
        await tester.tap(find.byKey(const Key('fc-world-confirm-mapping')));
        await settle(tester);
        await tester.scrollUntilVisible(primary, 200);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(FilledButton, 'Importar para carreira'),
          findsOneWidget,
        );
        await tester.tap(primary);
        await settle(tester);
        expect(find.textContaining('concluída'), findsOneWidget);
        expect(link.players['10'], 'nicolas');
        expect(link.teams['300'], 'third-existing');
        expect(await tester.runAsync(() => db.query('TeamPlayer')), before);
        expect(
          (await tester.runAsync(() => db.query('CustomCreatedPlayer')))!
              .length,
          3,
        );
        expect(
          await tester.runAsync(
            () => db.query(
              'Overall',
              where: 'customPlayerId = ?',
              whereArgs: ['nicolas'],
            ),
          ),
          isEmpty,
        );
        expect(
          (await tester.runAsync(() => db.query('CustomClub')))!.length,
          1,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
        api.close();
      },
    );
  }
  testWidgets(
    'Botafogo pending creation is linked to the existing catalog entry before review',
    (tester) async {
      final data = worldData();
      data.teams[1]['name'] = 'Botafogo';
      final api = worldApi(snapshot: data);
      final link = apiLink()..teams['200'] = 'new:Botafogo';
      await mount(
        tester,
        FcScoreWorldImportPage(
          api: api,
          remote: apiCareer(),
          repository: repo,
          person: person,
          link: link,
        ),
      );
      await tester.scrollUntilVisible(find.text('Preparar importação'), 200);
      await tester.tap(find.text('Preparar importação'));
      await settle(tester);
      final teams = find.widgetWithText(ListTile, 'Equipes');
      await tester.scrollUntilVisible(teams, 200);
      await tester.tap(teams);
      await settle(tester);
      expect(
        tester
            .widget<FcChoice>(find.byKey(const Key('fc-world-mapping-200')))
            .value,
        'Botafogo',
      );
      expect(find.text('Criar: Botafogo'), findsNothing);
      expect(await tester.runAsync(() => db.query('CustomClub')), isEmpty);
      await preview(tester, 'botafogo-linked-before-import');
      await tester.pageBack();
      await settle(tester);
      await reviewWorld(tester);
      final save = find.byKey(const Key('fc-world-primary'));
      await tester.scrollUntilVisible(save, 200);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await settle(tester);
      expect(find.textContaining('concluída'), findsOneWidget);
      expect(link.teams['200'], '40-1');
      expect(
        await tester.runAsync(
          () => db.query(
            'CustomClub',
            where: 'label = ?',
            whereArgs: ['Botafogo'],
          ),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      api.close();
    },
  );
  testWidgets(
    'World wizard imports tables while an unchecked match stays out of Partidas',
    (tester) async {
      final api = worldApi(), link = apiLink();
      await mount(
        tester,
        FcScoreWorldImportPage(
          api: api,
          remote: apiCareer(),
          repository: repo,
          person: person,
          link: link,
        ),
      );
      await prepareWorld(tester);
      final review = find.widgetWithText(ListTile, 'Revisar partidas');
      await tester.scrollUntilVisible(review, 250);
      await tester.tap(review);
      await settle(tester);
      expect(find.text('Selecionar partidas'), findsOneWidget);
      expect(find.text('Importar partida'), findsOneWidget);
      await tester.tap(find.text('Desmarcar todos'));
      await tester.pumpAndSettle();
      expect(find.text('Não importar partida'), findsOneWidget);
      await preview(tester, 'world-match-selection-dark');
      await tester.tap(find.text('Confirmar seleção · 0'));
      await settle(tester);
      expect(
        find.textContaining('0 selecionadas · 0 já cadastradas'),
        findsOneWidget,
      );
      final save = find.widgetWithText(FilledButton, 'Importar para carreira');
      await tester.scrollUntilVisible(save, 250);
      await tester.tap(save);
      await settle(tester);
      expect(find.textContaining('concluída'), findsOneWidget);
      expect(await tester.runAsync(() => db.query('ManagerFixtures')), isEmpty);
      expect(
        (await tester.runAsync(() => db.query('FcScoreWorldFixture')))!.length,
        3,
      );
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      api.close();
    },
  );
  for (final dark in [true, false]) {
    testWidgets(
      'Player correction shows each conflict, filters occupied records and imports safely ${dark ? 'dark' : 'light'}',
      (tester) async {
        final link = apiLink()..teams['300'] = 'new:Terceiro FC';
        await tester.runAsync(
          () => repo.importWorld(person: person, link: link, data: worldData()),
        );
        await tester.runAsync(
          () => db.update('CustomCreatedPlayer', {'realPlayerId': null}),
        );
        final original30 = link.players['30']!;
        final original20 = link.players['20']!;
        final data = worldData();
        (data.teams.first['roster'] as List).add(
          apiPlayer(11, 'Marcos Antônio'),
        );
        link.players['11'] = link.players['10']!;
        link.players['30'] = original20;
        final api = worldApi(snapshot: data);
        await mount(
          tester,
          FcScoreWorldImportPage(
            api: api,
            remote: apiCareer(),
            repository: repo,
            person: person,
            link: link,
          ),
          dark: dark,
          width: 320,
          scale: 1.3,
        );
        await prepareWorld(tester);
        expect(find.text('Corrigir vínculos'), findsOneWidget);
        expect(find.text('Etapa 1 de 2'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('fc-correction-next')))
              .onPressed,
          isNull,
        );
        await preview(tester, 'player-correction-${dark ? 'dark' : 'light'}');
        final scroll = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('fc-correct-20')),
          150,
          scrollable: scroll,
        );
        await tester.pumpAndSettle();
        expect(find.text('Rival FC'), findsOneWidget);
        final card30 = find.byKey(const Key('fc-correct-30'));
        final choose30 = find.descendant(
          of: card30,
          matching: find.byType(ListTile),
        );
        await tester.scrollUntilVisible(choose30, 200, scrollable: scroll);
        await tester.pumpAndSettle();
        expect(find.text('Terceiro FC'), findsOneWidget);
        await tester.tap(choose30);
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('fc-picker-player-$original20')),
          findsNothing,
        );
        await tester.enterText(
          find.byKey(const Key('fc-picker-search')),
          'Lucas',
        );
        await tester.showKeyboard(find.byKey(const Key('fc-picker-search')));
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isTrue);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('fc-picker-player-$original30')),
          150,
          scrollable: find.descendant(
            of: find.byKey(const Key('fc-picker-list')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('fc-picker-player-$original30')));
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('fc-correction-next')));
        await tester.pumpAndSettle();
        expect(find.text('Etapa 2 de 2'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('fc-correct-10')),
          150,
          scrollable: scroll,
        );
        await tester.pumpAndSettle();
        expect(find.text('São Paulo'), findsWidgets);
        expect(find.text('Pedro Silva'), findsWidgets);
        final separate = find.byKey(const Key('fc-create-separate-11'));
        await tester.scrollUntilVisible(separate, 200, scrollable: scroll);
        await tester.pumpAndSettle();
        await tester.tap(separate);
        await tester.pumpAndSettle();
        expect(
          (await tester.runAsync(() => db.query('CustomCreatedPlayer')))!
              .length,
          3,
        );
        await tester.tap(find.text('Voltar'));
        await tester.pumpAndSettle();
        expect(find.text('Etapa 1 de 2'), findsOneWidget);
        await tester.tap(find.byKey(const Key('fc-correction-next')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Concluir revisão'));
        await settle(tester);
        expect(find.byType(Dialog), findsNothing);
        expect(find.text('Vínculos precisam de correção'), findsNothing);
        final save = find.widgetWithText(FilledButton, 'Atualizar carreira');
        await tester.scrollUntilVisible(save, 250);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await settle(tester);
        expect(find.textContaining('concluída'), findsOneWidget);
        expect(link.players['30'], original30);
        expect(link.players['20'], original20);
        expect(link.players['11'], isNot(link.players['10']));
        expect(
          (await tester.runAsync(() => db.query('CustomCreatedPlayer')))!
              .length,
          4,
        );
        expect(
          (await tester.runAsync(() => db.query('ManagerFixtures')))!.length,
          1,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
        api.close();
      },
    );
  }
  testWidgets(
    'Cancelling correction discards changes; the next save reopens review and imports only after completion',
    (tester) async {
      final link = apiLink()..teams['300'] = 'new:Terceiro FC';
      await tester.runAsync(
        () => repo.importWorld(person: person, link: link, data: worldData()),
      );
      await tester.runAsync(
        () => db.update('CustomCreatedPlayer', {'realPlayerId': null}),
      );
      final original20 = link.players['20']!;
      link.players['30'] = original20;
      final api = worldApi();
      await mount(
        tester,
        FcScoreWorldImportPage(
          api: api,
          remote: apiCareer(),
          repository: repo,
          person: person,
          link: link,
        ),
      );
      await prepareWorld(tester);
      final scroll = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(Scrollable),
      );
      final separate = find.byKey(const Key('fc-create-separate-30'));
      await tester.scrollUntilVisible(separate, 200, scrollable: scroll);
      await tester.pumpAndSettle();
      await tester.tap(separate);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('fc-correction-next')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      await tester.pageBack();
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('Vínculos precisam de correção'),
        -250,
      );
      await tester.pumpAndSettle();
      expect(find.text('Vínculos precisam de correção'), findsOneWidget);
      expect(link.players['30'], original20);
      await reviewWorld(tester);
      expect(find.text('Corrigir vínculos'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('fc-correction-next')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      expect(
        (await tester.runAsync(() => db.query('CustomCreatedPlayer')))!.length,
        3,
      );
      expect(
        (await tester.runAsync(() => db.query('ManagerFixtures')))!.length,
        1,
      );
      await tester.tap(find.byKey(const Key('fc-world-confirm-mapping')));
      await settle(tester);
      await tester.scrollUntilVisible(separate, 200, scrollable: scroll);
      await tester.pumpAndSettle();
      await tester.tap(separate);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Concluir revisão'));
      await settle(tester);
      final save = find.widgetWithText(FilledButton, 'Atualizar carreira');
      await tester.scrollUntilVisible(save, 250);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await settle(tester);
      expect(find.textContaining('concluída'), findsOneWidget);
      expect(link.players['30'], isNot(original20));
      expect(
        (await tester.runAsync(() => db.query('CustomCreatedPlayer')))!.length,
        4,
      );
      expect(
        (await tester.runAsync(() => db.query('ManagerFixtures')))!.length,
        1,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      api.close();
    },
  );
  for (final dark in [true, false]) {
    testWidgets(
      'Incomplete player can be ${dark ? 'generated' : 'created manually'} here with a stable keyboard',
      (tester) async {
        final data = worldData();
        final remotePlayer = (data.teams[1]['roster'] as List).first as Map;
        remotePlayer['name'] = '';
        remotePlayer['overall'] = null;
        final api = worldApi(snapshot: data), link = apiLink();
        await mount(
          tester,
          FcScoreWorldImportPage(
            api: api,
            remote: apiCareer(),
            repository: repo,
            person: person,
            link: link,
          ),
          dark: dark,
          width: 320,
          scale: 1.3,
        );
        await tester.scrollUntilVisible(find.text('Preparar importação'), 200);
        await tester.pumpAndSettle();
        await prepareWorld(tester);
        final dialogScroll = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(Scrollable),
        );
        final choice = find.descendant(
          of: find.byKey(const Key('fc-correct-20')),
          matching: find.byType(ListTile),
        );
        await tester.scrollUntilVisible(choice, 150, scrollable: dialogScroll);
        await tester.pumpAndSettle();
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('fc-player-create-here')), findsOneWidget);
        expect(find.byKey(const Key('fc-player-generate')), findsOneWidget);
        expect(find.text('Criar com os dados da API'), findsNothing);
        await preview(
          tester,
          'missing-player-options-${dark ? 'dark' : 'light'}',
        );
        final action = find.byKey(
          Key(dark ? 'fc-player-generate' : 'fc-player-create-here'),
        );
        await tester.scrollUntilVisible(
          action,
          100,
          scrollable: find.descendant(
            of: find.byKey(const Key('fc-picker-list')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
        final nameField = find.byKey(const Key('fc-create-name'));
        if (dark) {
          expect(
            tester.widget<TextFormField>(nameField).controller!.text,
            isNotEmpty,
          );
        }
        await tester.enterText(nameField, 'João Criado Aqui');
        await tester.showKeyboard(nameField);
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isTrue);
        expect(
          tester.widget<TextFormField>(nameField).controller!.text,
          'João Criado Aqui',
        );
        final fieldsScroll = find
            .descendant(
              of: find.byKey(const Key('fc-create-fields')),
              matching: find.byType(Scrollable),
            )
            .first;
        final overall = find.byKey(const Key('fc-create-overall'));
        await tester.scrollUntilVisible(overall, 150, scrollable: fieldsScroll);
        await tester.pumpAndSettle();
        await tester.enterText(overall, '74');
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const Key('fc-create-potential')),
              )
              .controller!
              .text,
          '90',
        );
        expect(tester.takeException(), isNull);
        await preview(
          tester,
          'inline-player-creator-${dark ? 'dark' : 'light'}',
        );
        await tester.tap(find.text('Usar jogador'));
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(find.text('Criar: João Criado Aqui · OVR 74'), findsOneWidget);
        expect(
          await tester.runAsync(() => db.query('CustomCreatedPlayer')),
          isEmpty,
        );
        await tester.tap(find.text('Concluir revisão'));
        await settle(tester);
        final save = find.widgetWithText(
          FilledButton,
          'Importar para carreira',
        );
        await tester.scrollUntilVisible(save, 200);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await settle(tester);
        expect(find.textContaining('concluída'), findsOneWidget);
        final created = (await tester.runAsync(
          () => db.query(
            'CustomCreatedPlayer',
            where: 'realPlayerId = ?',
            whereArgs: ['20'],
          ),
        ))!.single;
        expect(created['name'], 'João Criado Aqui');
        expect(created['overall'], 74);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
        api.close();
      },
    );
  }
  testWidgets(
    '18 missing players can be generated together, cancelled, reviewed and imported once',
    (tester) async {
      final data = worldData();
      final roster = data.teams.first['roster'] as List;
      for (var id = 1000; id < 1018; id++) {
        roster.add({
          ...apiPlayer(id, ''),
          'leagueGoals': 2,
          'leagueAppearances': 5,
        });
      }
      final api = worldApi(snapshot: data), link = apiLink();
      await mount(
        tester,
        FcScoreWorldImportPage(
          api: api,
          remote: apiCareer(),
          repository: repo,
          person: person,
          link: link,
        ),
      );
      await prepareWorld(tester);
      expect(find.text('Etapa 1 de 18'), findsOneWidget);
      await tester.tap(find.byKey(const Key('fc-generate-all-missing')));
      await tester.pumpAndSettle();
      expect(find.text('Dados faltantes preenchidos'), findsOneWidget);
      expect(
        await tester.runAsync(() => db.query('CustomCreatedPlayer')),
        isEmpty,
      );
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      await tester.pageBack();
      await settle(tester);
      final resume = find.widgetWithText(
        ListTile,
        'Vínculos precisam de correção',
      );
      await tester.scrollUntilVisible(resume, -200);
      await tester.pumpAndSettle();
      await tester.tap(resume);
      await tester.pumpAndSettle();
      expect(find.text('Etapa 1 de 18'), findsOneWidget);
      await tester.tap(find.byKey(const Key('fc-generate-all-missing')));
      await tester.pumpAndSettle();
      await preview(tester, 'bulk-generated-players-review');
      await tester.tap(find.text('Concluir revisão'));
      await settle(tester);
      await reviewWorld(tester);
      final save = find.widgetWithText(FilledButton, 'Importar para carreira');
      await tester.scrollUntilVisible(save, 200);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await settle(tester);
      expect(find.textContaining('concluída'), findsOneWidget);
      final players = await tester.runAsync(
        () => db.query('CustomCreatedPlayer'),
      );
      expect(players!.length, 21);
      expect(
        players.every(
          (p) => p['overall'] == 82 && (p['name'] as String).isNotEmpty,
        ),
        isTrue,
      );
      final ids = Map<String, String>.of(link.players);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      await mount(
        tester,
        FcScoreWorldImportPage(
          api: api,
          remote: apiCareer(),
          repository: repo,
          person: person,
          link: link,
        ),
      );
      await prepareWorld(tester);
      expect(find.text('Corrigir vínculos'), findsNothing);
      final update = find.byKey(const Key('fc-world-primary'));
      await tester.scrollUntilVisible(update, 200);
      await tester.pumpAndSettle();
      await tester.tap(update);
      await settle(tester);
      expect(find.textContaining('concluída'), findsOneWidget);
      expect(link.players, ids);
      expect(
        (await tester.runAsync(() => db.query('CustomCreatedPlayer')))!.length,
        21,
      );
      expect(
        (await tester.runAsync(() => db.query('ManagerFixtures')))!.length,
        1,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      api.close();
    },
  );
  for (final dark in [true, false]) {
    testWidgets(
      'Match selection protects configured games, filters and stays readable ${dark ? 'dark' : 'light'}',
      (tester) async {
        final existingMatch = FcScoreMatch.fromFixture(apiFixture(), 'save-A');
        final newMatch = FcScoreMatch.fromFixture({
          ...apiFixture(),
          'id': 46,
          'date': '2028-06-26',
        }, 'save-A');
        final rows = [
          FcWorldMatchPreview(
            match: existingMatch,
            existingFixtureId: 'manual',
            manual: true,
            localHomeGoals: 1,
            localAwayGoals: 4,
          ),
          FcWorldMatchPreview(match: newMatch),
        ];
        await mount(
          tester,
          FcScoreWorldMatchesPage(
            matches: rows,
            selectedKeys: {existingMatch.remoteKey, newMatch.remoteKey},
          ),
          dark: dark,
          width: 320,
          scale: 1.3,
        );
        expect(
          find.textContaining('1 selecionadas · 1 já cadastradas'),
          findsOneWidget,
        );
        final tile = tester.widget<CheckboxListTile>(
          find.widgetWithText(CheckboxListTile, 'Já configurada · preservar'),
        );
        expect(tile.onChanged, isNull);
        expect(tile.value, isFalse);
        await tester.tap(find.text('Novos'));
        await tester.pumpAndSettle();
        expect(find.text('Já configurada · preservar'), findsNothing);
        await tester.enterText(find.byType(TextField), '26/06');
        await tester.pumpAndSettle();
        expect(find.text('Importar partida'), findsOneWidget);
        await tester.tap(find.text('Desmarcar todos'));
        await tester.pumpAndSettle();
        expect(find.text('Confirmar seleção · 0'), findsOneWidget);
        await tester.tap(find.text('Selecionar novos'));
        await tester.pumpAndSettle();
        expect(find.text('Confirmar seleção · 1'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'ausente');
        await tester.pumpAndSettle();
        expect(find.text('Nenhuma partida neste filtro.'), findsOneWidget);
        expect(find.text('Confirmar seleção · 1'), findsOneWidget);
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final editable = tester.widget<EditableText>(find.byType(EditableText));
        expect(editable.focusNode.hasFocus, isTrue);
        expect(editable.controller.text, 'ausente');
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
      },
    );
  }
  testWidgets(
    'Recent addresses do not connect automatically; keyboard and typed IP stay stable',
    (tester) async {
      await tester.runAsync(
        () => repo.rememberAddress(fcScoreAddress('192.168.0.20')),
      );
      final requests = <http.Request>[];
      await mount(
        tester,
        FcScoreConnectionPage(
          repository: repo,
          apiFactory: (uri) => fakeApi(uri, requests: requests),
        ),
      );
      final input = find.byKey(const Key('fc-ip'));
      expect(tester.widget<TextField>(input).controller!.text, '');
      expect(requests, isEmpty);
      await tester.tap(input);
      await tester.enterText(input, '192.168.0.33');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, true);
      expect(tester.widget<TextField>(input).controller!.text, '192.168.0.33');
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('192.168.0.20:38291'));
      await tester.tap(find.text('192.168.0.20:38291'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input).controller!.text,
        contains('192.168.0.20'),
      );
      expect(requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets('USB shows ADB command and connects via localhost', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await mount(
      tester,
      FcScoreConnectionPage(
        repository: repo,
        apiFactory: (uri) => fakeApi(uri, requests: requests),
      ),
    );
    await tester.tap(find.text('Cabo USB'));
    await tester.pumpAndSettle();
    expect(find.text('adb reverse tcp:38291 tcp:38291'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('fc-connect')));
    await tester.tap(find.byKey(const Key('fc-connect')));
    await settle(tester);
    expect(requests.first.url.host, '127.0.0.1');
    expect(find.text('Escolha o save'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
  testWidgets(
    'First connection reviews mappings, saves them and opens career hub',
    (tester) async {
      await mount(
        tester,
        FcScoreConnectionPage(
          initialPerson: person,
          repository: repo,
          apiFactory: fakeApi,
        ),
      );
      await tester.enterText(find.byKey(const Key('fc-ip')), '192.168.0.20');
      await tester.tap(find.byKey(const Key('fc-connect')));
      await settle(tester);
      await tester.tap(find.text('Minha carreira'));
      await settle(tester);
      expect(find.text('Vincular carreira'), findsOneWidget);
      await preview(tester, 'mapping-dark');
      await tester.scrollUntilVisible(find.byKey(const Key('fc-bind')), 300);
      await tester.tap(find.byKey(const Key('fc-bind')));
      await settle(tester);
      expect(find.text('Carreira conectada'.toUpperCase()), findsOneWidget);
      expect(await tester.runAsync(() => repo.linkFor(person.id)), isNotNull);
      expect(tester.takeException(), isNull);
      await preview(tester, 'hub-dark');
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  for (final kind in FcScoreView.values) {
    testWidgets('${kind.title} loads on small screen without overflow', (
      tester,
    ) async {
      final api = fakeApi(fcScoreAddress('pc'));
      await mount(
        tester,
        FcScoreDataPage(
          api: api,
          remote: apiCareer(),
          kind: kind,
          onMatch: (_) async {},
        ),
        width: 320,
        scale: 1.15,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      if (kind == FcScoreView.standings) {
        expect(find.text('PTS'), findsOneWidget);
        expect(find.text('45'), findsOneWidget);
        await preview(tester, 'standings-dark');
      }
      await tester.pumpWidget(const SizedBox());
      if (kind == FcScoreView.squad || kind == FcScoreView.youth) {
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(seconds: 11));
        }
      }
      api.close();
    });
  }
  testWidgets('Match filters and pagination produce correct requests', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final api = fakeApi(
      fcScoreAddress('pc'),
      requests: requests,
      fixturesTotal: 60,
    );
    await mount(
      tester,
      FcScoreDataPage(
        api: api,
        remote: apiCareer(),
        kind: FcScoreView.fixtures,
        onMatch: (_) async {},
      ),
    );
    await tester.tap(find.text('Resultados'));
    await settle(tester);
    expect(requests.last.url.queryParameters['status'], 'played');
    await tester.ensureVisible(find.text('Carregar mais'));
    await tester.tap(find.text('Carregar mais'));
    await settle(tester);
    expect(requests.last.url.queryParameters['offset'], '1');
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  Future<String> seedMappingClubs() async {
    final logo = File('build/v0.9.11-custom-club-logo.png').absolute;
    if (!await logo.exists()) {
      await File('assets/images/clubLogos/sao-paulo.png').copy(logo.path);
    }
    await db.insert('CustomLeague', {
      'id': 'custom-league',
      'label': 'Liga personalizada',
      'fifaVersion': 'FC26, FC25',
    });
    for (final (id, label, league, version) in [
      ('aurora', 'Aurora FC', '1014', 'FC26, FC25'),
      ('lobos', 'Lobos FC', 'custom-league', 'FC26, FC25'),
      ('orphan', 'Clube sem liga', 'deleted-league', 'FC26'),
      ('other-edition', 'Outro FIFA FC', '1014', 'FC27'),
    ]) {
      await db.insert('CustomClub', {
        'id': id,
        'label': label,
        'leagueId': league,
        'fifaVersion': version,
        'personId': '',
        'imagePath': logo.path,
        'imageUrl': 'https://example.com/$id.png',
      });
    }
    await db.insert('ClubCustomizationModel', {
      'id': 'edited-sp',
      'clubName': 'São Paulo Personalizado',
      'originalTeamId': '40-13',
      'originalLeagueId': '1014',
      'fifaVersion': 'FC26',
      'imagePath': logo.path,
    });
    return logo.path;
  }

  test(
    'Club mapping catalog includes multi-edition customs and current badges',
    () async {
      final logo = await seedMappingClubs();
      final clubs = await FcScoreClubCatalog.load(repo.sql, 'FC26');
      expect(clubs.teams.map((t) => t.id).toSet().length, clubs.teams.length);
      final custom = clubs.teams.singleWhere((t) => t.id == 'lobos');
      expect(custom.imagePath, logo);
      expect(custom.imageUrl, 'https://example.com/lobos.png');
      expect(custom.isCustom, isTrue);
      final edited = clubs.teams.singleWhere((t) => t.id == '40-13');
      expect(edited.label, 'São Paulo Personalizado');
      expect(edited.imagePath, logo);
      expect(edited.clubIdentity, isNotNull);
      expect(clubs.teams.any((t) => t.id == 'other-edition'), isFalse);
      final groups = fcGroupClubs(clubs.teams, clubs.leagues);
      expect(
        groups.singleWhere((g) => g.id == 'custom-league').label,
        'Liga personalizada',
      );
      expect(
        groups
            .singleWhere((g) => g.id == 'other')
            .rows
            .any((t) => t.id == 'orphan'),
        isTrue,
      );
      final previousEdition = await FcScoreClubCatalog.load(repo.sql, 'FC25');
      expect(previousEdition.teams.any((t) => t.id == 'lobos'), isTrue);
      expect(
        previousEdition.leagues.any((l) => l.id == 'custom-league'),
        isTrue,
      );
      expect(previousEdition.teams.any((t) => t.id == 'orphan'), isFalse);
      expect((await db.query('CustomClub')), hasLength(4));
    },
  );

  for (final dark in [true, false]) {
    testWidgets(
      'Club picker expands leagues, finds customs and keeps keyboard ${dark ? 'dark' : 'light'}',
      (tester) async {
        late FcScoreClubCatalog clubs;
        late String logo;
        String? selected;
        await tester.runAsync(() async {
          logo = await seedMappingClubs();
          clubs = await FcScoreClubCatalog.load(repo.sql, 'FC26');
        });
        await mount(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => selected = await fcPick(
                  context,
                  title: 'Relacionar clube',
                  items: clubs.teams
                      .where(
                        (t) => [
                          '40-13',
                          'aurora',
                          'lobos',
                          'orphan',
                        ].contains(t.id),
                      )
                      .toList(),
                  clubLeagues: clubs.leagues,
                  selectedId: '40-13',
                  createName: 'Clube da API',
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
          dark: dark,
          width: 320,
          scale: 1.2,
        );
        await tester.runAsync(
          () => precacheImage(
            FileImage(File(logo)),
            tester.element(find.byType(Scaffold).first),
          ),
        );
        await tester.tap(find.text('Abrir'));
        await tester.pumpAndSettle();
        final brazil = find.byKey(const Key('fc-picker-league-1014'));
        expect(find.text('São Paulo Personalizado'), findsOneWidget);
        final logoWidget = tester.widget<TeamLogo>(
          find.descendant(
            of: find.byKey(const Key('fc-picker-club-aurora')),
            matching: find.byType(TeamLogo),
          ),
        );
        expect(logoWidget.imagePath, logo);
        await tester.tap(brazil);
        await tester.pumpAndSettle();
        expect(find.text('Aurora FC'), findsNothing);
        final customLeague = find.byKey(
          const Key('fc-picker-league-custom-league'),
        );
        await tester.tap(customLeague);
        await tester.pumpAndSettle();
        expect(find.text('Lobos FC'), findsOneWidget);
        await preview(tester, 'club-picker-${dark ? 'dark' : 'light'}');
        final search = find.byKey(const Key('fc-picker-search'));
        await tester.enterText(search, 'aurora');
        await tester.showKeyboard(search);
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        await tester.pumpAndSettle();
        final scroll = find.descendant(
          of: find.byKey(const Key('fc-picker-list')),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.text('Aurora FC'),
          100,
          scrollable: scroll,
        );
        expect(tester.testTextInput.isVisible, isTrue);
        expect(find.text('Lobos FC'), findsNothing);
        await tester.enterText(search, 'Liga personalizada');
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Lobos FC'),
          100,
          scrollable: scroll,
        );
        expect(find.text('Lobos FC'), findsOneWidget);
        expect(tester.testTextInput.isVisible, isTrue);
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lobos FC'));
        await tester.pumpAndSettle();
        expect(selected, 'lobos');
        expect(
          (await tester.runAsync(() => db.query('CustomClub'))),
          hasLength(4),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'World team review groups mapped leagues and links a multi-edition custom ${dark ? 'dark' : 'light'}',
      (tester) async {
        late String logo;
        await tester.runAsync(() async => logo = await seedMappingClubs());
        final data = worldData();
        data.teams.last['league'] = {'id': 90, 'name': 'Nome da liga na API'};
        final api = worldApi(snapshot: data);
        final link = apiLink()..leagues['90'] = 'custom-league';
        await mount(
          tester,
          FcScoreWorldImportPage(
            api: api,
            remote: apiCareer(),
            repository: repo,
            person: person,
            link: link,
          ),
          dark: dark,
          width: 320,
          scale: 1.2,
        );
        await tester.runAsync(
          () => precacheImage(
            FileImage(File(logo)),
            tester.element(find.byType(Scaffold).first),
          ),
        );
        await tester.scrollUntilVisible(find.text('Preparar importação'), 250);
        await tester.tap(find.text('Preparar importação'));
        await settle(tester);
        final primary = find.byKey(const Key('fc-world-primary'));
        await tester.scrollUntilVisible(primary, 250);
        await tester.tap(primary);
        await settle(tester);
        await tester.tap(find.byKey(const Key('fc-world-confirm-mapping')));
        await settle(tester);
        expect(find.text('De-para · Equipes'), findsOneWidget);
        expect(find.text('Liga personalizada'), findsOneWidget);
        expect(find.text('Nome da liga na API'), findsNothing);
        final third = find.byKey(const Key('fc-world-mapping-300'));
        expect(third, findsNothing);
        final group = find.byKey(const Key('fc-world-league-90'));
        final scroll = find.descendant(
          of: find.byKey(const Key('fc-world-list')),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(group, 150, scrollable: scroll);
        await tester.tap(group);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(third, 150, scrollable: scroll);
        await tester.tap(third);
        await tester.pumpAndSettle();
        final search = find.byKey(const Key('fc-picker-search'));
        await tester.enterText(search, 'Lobos');
        await tester.pumpAndSettle();
        final club = find.byKey(const Key('fc-picker-club-lobos'));
        await tester.ensureVisible(club);
        expect(
          find.descendant(of: club, matching: find.text('Personalizado')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TeamLogo>(
                find.descendant(of: club, matching: find.byType(TeamLogo)),
              )
              .imagePath,
          logo,
        );
        await tester.tap(club);
        await tester.pumpAndSettle();
        expect(tester.widget<FcChoice>(third).value, 'Lobos FC');
        expect(
          tester
              .widget<FcClubLogo>(
                find.descendant(of: third, matching: find.byType(FcClubLogo)),
              )
              .item!
              .imagePath,
          logo,
        );
        await preview(tester, 'club-review-${dark ? 'dark' : 'light'}');
        await tester.tap(group);
        await tester.pumpAndSettle();
        expect(third, findsNothing);
        final reviewSearch = find.byKey(const Key('fc-world-mapping-search'));
        await tester.enterText(reviewSearch, 'Lobos');
        await tester.pumpAndSettle();
        expect(third, findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(
          (await tester.runAsync(() => db.query('CustomClub'))),
          hasLength(4),
        );
        expect(await tester.runAsync(() => repo.linkFor(person.id)), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 11));
        api.close();
      },
    );
  }

  for (final career in [true, false]) {
    testWidgets(
      'Team mapping entry point includes multi-edition custom ${career ? 'career' : 'match'}',
      (tester) async {
        final logo = await tester.runAsync(seedMappingClubs);
        await mount(
          tester,
          career
              ? FcScoreMappingPage(
                  remote: apiCareer(),
                  repository: repo,
                  initialPerson: person,
                )
              : FcScoreImportPage(
                  repository: repo,
                  person: person,
                  link: apiLink(),
                  match: FcScoreMatch.fromReport(apiReport()),
                ),
        );
        await tester.runAsync(
          () => precacheImage(
            FileImage(File(logo!)),
            tester.element(find.byType(Scaffold).first),
          ),
        );
        final choice = find.byWidgetPredicate(
          (w) => w is FcChoice && w.title == (career ? 'Clube' : 'Adversário'),
        );
        await tester.scrollUntilVisible(choice, 200);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('fc-picker-search')),
          'Lobos',
        );
        await tester.pumpAndSettle();
        final club = find.byKey(const Key('fc-picker-club-lobos'));
        await tester.ensureVisible(club);
        expect(
          find.descendant(of: club, matching: find.byType(TeamLogo)),
          findsOneWidget,
        );
        await tester.tap(club);
        await tester.pumpAndSettle();
        await settle(tester);
        expect(tester.widget<FcChoice>(choice).value, 'Lobos FC');
        expect(tester.takeException(), isNull);
        expect(await tester.runAsync(() => repo.linkFor(person.id)), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 11));
      },
    );
  }

  testWidgets(
    'Picker search keeps focus and text when keyboard resizes the sheet',
    (tester) async {
      await mount(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => fcPick(
                context,
                title: 'Selecionar jogador',
                items: const [
                  CatalogItem('1', 'Pedro Silva'),
                  CatalogItem('2', 'Marcos Antônio'),
                ],
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('fc-picker-search'));
      await tester.tap(search);
      await tester.enterText(search, 'Pedro');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, true);
      expect(find.text('Pedro Silva'), findsOneWidget);
      expect(find.text('Marcos Antônio'), findsNothing);
      await tester.enterText(search, 'marcosantonio');
      await tester.pumpAndSettle();
      expect(find.text('Marcos Antônio'), findsOneWidget);
      expect(find.text('Pedro Silva'), findsNothing);
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Classification opens the linked career match offline and keeps other matches read-only',
    (tester) async {
      late FcJson competition;
      late String nativeId;
      await tester.runAsync(() async {
        await repo.importWorld(
          person: person,
          link: apiLink()..teams['300'] = 'new:Terceiro FC',
          data: worldData(),
          importOwnMatches: true,
        );
        competition = (await repo.careerCompetitions(
          person.id,
          seasonId: 's2028',
        )).single;
        nativeId = (await db.query('ManagerFixtures')).single['id'] as String;
        await SqlService.ensureTransferReleaseSchema(db);
      });
      await mount(
        tester,
        CareerCompetitionPage(
          person: person,
          repository: repo,
          competition: competition,
        ),
      );
      await tester.tap(find.text('Partidas'));
      await tester.pumpAndSettle();
      final own = find.byWidgetPredicate(
        (w) => w is CareerCompetitionMatchCard && fcId(w.fixture['id']) == '42',
      );
      final other = find.byWidgetPredicate(
        (w) => w is CareerCompetitionMatchCard && fcId(w.fixture['id']) == '44',
      );
      final upcoming = find.byWidgetPredicate(
        (w) => w is CareerCompetitionMatchCard && fcId(w.fixture['id']) == '45',
      );
      expect(tester.widget<CareerCompetitionMatchCard>(own).onTap, isNotNull);
      expect(tester.widget<CareerCompetitionMatchCard>(other).onTap, isNull);
      expect(tester.widget<CareerCompetitionMatchCard>(upcoming).onTap, isNull);
      await tester.tap(own);
      await settle(tester);
      final page = tester.widget<FixtureDetailsPage>(
        find.byType(FixtureDetailsPage),
      );
      expect(page.fixture['id'], nativeId);
      expect(page.fixture['personId'], person.id);
      expect(page.sql, repo.sql);
      final complete = find.byKey(const Key('fixture-complete-api'));
      expect(complete, findsOneWidget);
      expect(
        tester.widget<IconButton>(complete).tooltip,
        'Vinculada à API · completar de novo',
      );
      expect(find.textContaining('Exception'), findsNothing);
      expect(tester.takeException(), isNull);
      await preview(tester, 'linked-career-match');
      await tester.pageBack();
      await settle(tester);
      expect(find.byType(CareerCompetitionPage), findsOneWidget);
      expect(
        (await tester.runAsync(() => db.query('ManagerFixtures'))),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets('Import preview saves once and disables duplicate import', (
    tester,
  ) async {
    final link = apiLink();
    await mount(
      tester,
      FcScoreImportPage(
        repository: repo,
        person: person,
        link: link,
        match: FcScoreMatch.fromReport(apiReport()),
      ),
    );
    await preview(tester, 'import-dark');
    final button = find.byKey(const Key('fc-import'));
    await tester.scrollUntilVisible(button, 300);
    await tester.tap(button);
    await settle(tester);
    expect(find.text('Ver partida'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      (await tester.runAsync(() => db.query('ManagerFixtures')))!.length,
      1,
    );
    await tester.pumpWidget(const SizedBox());
    await mount(
      tester,
      FcScoreImportPage(
        repository: repo,
        person: person,
        link: link,
        match: FcScoreMatch.fromReport(apiReport(id: 'batch-B')),
      ),
    );
    await tester.scrollUntilVisible(find.byKey(const Key('fc-import')), 300);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('fc-import'))).onPressed,
      isNull,
    );
    expect(find.text('Já cadastrada'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
  testWidgets(
    'Player selected in import preview stays selected for the next import',
    (tester) async {
      final player = reviewPerson(category: PersonCategory.player);
      await tester.runAsync(
        () => db.update(
          'Persons',
          player.toMap(),
          where: 'id = ?',
          whereArgs: [player.id],
        ),
      );
      final link = apiLink(category: 'player');
      await mount(
        tester,
        FcScoreImportPage(
          repository: repo,
          person: player,
          link: link,
          match: FcScoreMatch.fromReport(apiReport()),
        ),
      );
      await tester.scrollUntilVisible(find.text('Meu jogador'), 250);
      await tester.tap(find.text('Meu jogador'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Marcos Antônio'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('fc-import')), 300);
      await tester.tap(find.byKey(const Key('fc-import')));
      await settle(tester);
      expect(find.text('Ver partida'), findsOneWidget);
      expect(link.playerId, '11');
      expect(
        (await tester.runAsync(() => db.query('PlayerFixtures')))!
            .single['minsPlayed'],
        27,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  FcScoreApi updateApi(
    Uri uri,
    FcScoreWorldData data, {
    bool offline = false,
    Future<void>? waitForCalendar,
  }) {
    final world = worldApi(snapshot: data);
    addTearDown(world.close);
    return FcScoreApi(
      uri,
      client: MockClient((r) async {
        if (offline) return http.Response('{}', 503);
        final path = r.url.path.substring('/api/'.length);
        if (path.endsWith('/fixtures') && waitForCalendar != null) {
          await waitForCalendar;
        }
        final Object? value;
        if (path == 'health') {
          value = {'status': 'ok'};
        } else if (path == 'meta') {
          value = {'gameVersion': 'FC 26'};
        } else if (path == 'careers') {
          value = [apiCareer().overview['save']];
        } else if (path.endsWith('/squad')) {
          value = {'players': apiCareer().squad};
        } else if (path.endsWith('/competitions')) {
          value = [
            {'competition': apiCareer().competitions.single},
          ];
        } else {
          try {
            value = await world.request(path, query: r.url.queryParameters);
          } on FcScoreException catch (e) {
            return http.Response('{}', e.status ?? 500);
          }
        }
        return http.Response(
          jsonEncode(value),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  }

  for (final dark in [true, false]) {
    testWidgets(
      'Quick update options are readable, cancelable and reject an empty selection $dark',
      (tester) async {
        FcScoreUpdateOptions? result;
        await mount(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    result = await showDialog<FcScoreUpdateOptions>(
                      context: context,
                      builder: (_) => const FcScoreUpdateOptionsDialog(
                        initial: FcScoreUpdateOptions(
                          calendar: false,
                          squads: false,
                          overalls: false,
                        ),
                      ),
                    );
                  },
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
          dark: dark,
          width: 320,
          scale: 1.3,
        );
        await tester.tap(find.text('Abrir'));
        await settle(tester);
        await preview(
          tester,
          'v0105-update-options-${dark ? 'dark' : 'light'}',
        );
        final competitions = find.byKey(
          const ValueKey('fc-update-option-competitions'),
        );
        await tester.tap(competitions);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('fc-update-options-confirm')),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
        await settle(tester);
        expect(result, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'One-tap update confirms new teams and never imports new career matches',
    (tester) async {
      final link = apiLink()
        ..teams['200'] = '40-1'
        ..teams['300'] = 'new:Terceiro FC';
      await tester.runAsync(() async {
        await repo.importWorld(
          person: person,
          link: link,
          data: worldData(),
          preserveOwnPlayers: true,
        );
        await repo.rememberCareerAddress(link, fcScoreAddress('192.168.0.8'));
        await repo.rememberAddress(fcScoreAddress('192.168.0.99'));
      });
      final next = worldData();
      next.teams.add({
        'id': 999,
        'name': 'Novo time',
        'league': {'id': 80, 'name': 'Brasileirão'},
        'roster': [],
      });
      next.fixtures.add({
        ...next.fixtures[1],
        'id': 100,
        'home': {
          'team': {'id': 999, 'name': 'Novo time'},
          'goals': 1,
        },
      });
      var refreshed = 0;
      await mount(
        tester,
        Scaffold(
          appBar: AppBar(
            title: const Text('Partidas'),
            actions: [
              FcScoreCareerUpdateButton(
                person: person,
                repository: repo,
                onUpdated: () async {
                  refreshed++;
                },
                apiFactory: (uri) {
                  expect(uri.host, '192.168.0.8');
                  return updateApi(uri, next);
                },
              ),
            ],
          ),
        ),
        width: 320,
        scale: 1.2,
      );
      await tester.tap(find.byKey(const Key('fc-career-update')));
      await settle(tester);
      expect(find.byType(FcScoreUpdateOptionsDialog), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNWidgets(5));
      final overallChoice = find.byKey(
        const ValueKey('fc-update-option-overalls'),
      );
      await tester.ensureVisible(overallChoice);
      await tester.tap(overallChoice);
      await tester.pumpAndSettle();
      await preview(tester, 'v0105-update-options-small');
      await tester.tap(find.byKey(const Key('fc-update-options-confirm')));
      await settle(tester);
      expect(find.text('Novidades na carreira'), findsOneWidget);
      expect(find.textContaining('0 partidas e 1 equipe'), findsOneWidget);
      expect(
        (await tester.runAsync(() => db.query('FcScoreWorldTeam')))!,
        hasLength(3),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final before = tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value!;
      await preview(tester, 'update-confirmation-small');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Cancelar'),
        ),
      );
      await settle(tester);
      expect(
        (await tester.runAsync(() => db.query('FcScoreWorldTeam')))!,
        hasLength(3),
      );
      expect(
        find.text('Atualização cancelada. Nenhum dado foi importado.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Fechar'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('fc-career-update')));
      await settle(tester);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('fc-update-option-overalls')),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('fc-update-options-confirm')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('fc-sync-confirm')));
      await settle(tester);
      expect(find.text('Carreira atualizada'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        1,
      );
      expect(before, greaterThan(0));
      expect(
        (await tester.runAsync(() => db.query('ManagerFixtures')))!,
        hasLength(1),
      );
      expect(
        (await tester.runAsync(() => db.query('FcScoreWorldTeam')))!,
        hasLength(4),
      );
      expect(tester.takeException(), isNull);
      await preview(tester, 'update-complete-small');
      await tester.tap(find.text('Fechar'));
      await settle(tester);
      expect(refreshed, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Personalizing stops the automatic update before any commit', (
    tester,
  ) async {
    final link = apiLink()
      ..teams['200'] = '40-1'
      ..teams['300'] = 'new:Terceiro FC';
    await tester.runAsync(() async {
      await repo.importWorld(
        person: person,
        link: link,
        data: worldData(),
        importOwnMatches: false,
        preserveOwnPlayers: true,
      );
      await repo.rememberCareerAddress(link, fcScoreAddress('pc'));
    });
    final next = worldData(date: '2028-07-01');
    (next.teams[1]['roster'] as List).first['leagueGoals'] = 20;
    final gate = Completer<void>();
    await mount(
      tester,
      FcScoreCareerUpdateDialog(
        person: person,
        repository: repo,
        apiFactory: (uri) => updateApi(uri, next, waitForCalendar: gate.future),
      ),
    );
    await tester.tap(find.text('Personalizar atualização'));
    await tester.pump(const Duration(milliseconds: 350));
    gate.complete();
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'Atualizar carreira'), findsOneWidget);
    expect(find.text('Carreira atualizada'), findsNothing);
    expect(find.text('Novidades na carreira'), findsNothing);
    expect(
      (await tester.runAsync(
        () => repo.careerRoster(person.id, link.seasonId, '200'),
      ))!.single['leagueGoals'],
      18,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('Repeated update finishes without confirming old data', (
    tester,
  ) async {
    final link = apiLink()
      ..teams['200'] = '40-1'
      ..teams['300'] = 'new:Terceiro FC';
    await tester.runAsync(() async {
      await repo.importWorld(
        person: person,
        link: link,
        data: worldData(),
        importOwnMatches: false,
        preserveOwnPlayers: true,
      );
      await repo.rememberCareerAddress(link, fcScoreAddress('pc'));
    });
    await mount(
      tester,
      FcScoreCareerUpdateDialog(
        person: person,
        repository: repo,
        apiFactory: (uri) => updateApi(uri, worldData()),
      ),
    );
    expect(find.text('Carreira atualizada'), findsOneWidget);
    expect(find.text('Novidades na carreira'), findsNothing);
    expect(
      (await tester.runAsync(() => db.query('ManagerFixtures')))!,
      isEmpty,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Unavailable PC offers reconnect without importing data', (
    tester,
  ) async {
    final link = apiLink();
    await tester.runAsync(() async {
      await repo.moveLink(link, link.saveId);
      await repo.rememberCareerAddress(link, fcScoreAddress('pc'));
    });
    await mount(
      tester,
      FcScoreCareerUpdateDialog(
        person: person,
        repository: repo,
        apiFactory: (uri) => updateApi(uri, worldData(), offline: true),
      ),
    );
    expect(find.text('Alterar conexão'), findsOneWidget);
    expect(
      (await tester.runAsync(() => db.query('FcScoreWorldTeam')))!,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Hub keeps all shortcuts in theme on narrow screen', (
    tester,
  ) async {
    final api = fakeApi(fcScoreAddress('pc'));
    await mount(
      tester,
      FcScoreHubPage(
        api: api,
        repository: repo,
        remote: apiCareer(),
        person: person,
        link: apiLink(),
      ),
      width: 320,
      dark: false,
      scale: 1.2,
    );
    await tester.scrollUntilVisible(find.text('Tática'), 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await preview(tester, 'hub-light-small');
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}
