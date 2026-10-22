import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/FcScore/FcScoreQuickImportPage.dart';
import 'package:mcmanager/FcScore/FcScoreRepository.dart';
import 'package:mcmanager/ManagerCareer/Fixtures/ManagerFixtureForm.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fcscore_fixture.dart';
import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late FcScoreRepository repo;
  final person = reviewPerson();
  final season = reviewSeason(id: 's2028', year: 2028);
  final boundary = GlobalKey();
  setUpAll(() async {
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory('build/fcscore-quick-docs').absolute.path,
        );
    await GameCatalog.load();
    await loadPreviewFonts();
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
    await db.insert('Seasons', season.toMap());
    repo = FcScoreRepository(sql: SqlService.withDatabase(db));
  });
  tearDown(() async => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> mount(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: managerDarkTheme,
        builder: (context, child) =>
            RepaintBoundary(key: boundary, child: child!),
        home: page,
      ),
    );
    await settle(tester);
  }

  Future<void> linkCareer(WidgetTester tester, {String saveId = 'save-A'}) =>
      tester.runAsync(() async {
        await repo.rememberAddress(fcScoreAddress('192.168.0.20'));
        await repo.moveLink(apiLink(), saveId);
      });

  Future<void> configureStandings(WidgetTester tester) =>
      tester.runAsync(() async {
        await db.insert('FcScoreCompetition', {
          'personId': person.id,
          'seasonId': season.id,
          'remoteId': '1528',
          'tournamentId': 'league:1014',
          'saveId': 'save-A',
          'name': 'Brasileirão',
          'currentDate': '2028-06-20',
          'importedAt': 'before',
          'rawJson': jsonEncode(apiTable()),
        });
      });

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

  Future<void> connect(WidgetTester tester) async {
    await tester.tap(find.text('192.168.0.20:38291'));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  for (final failStandings in [false, true]) {
    testWidgets(
      'Connects explicitly and imports the match with a standings refresh (failure: $failStandings)',
      (tester) async {
        await linkCareer(tester);
        await configureStandings(tester);
        final requests = <http.Request>[];
        await mount(
          tester,
          FcScoreQuickImportPage(
            person: person,
            repository: repo,
            apiFactory: (uri) =>
                fakeApi(uri, requests: requests, failStandings: failStandings),
          ),
        );
        expect(requests, isEmpty);
        expect(find.text('Partidas realizadas'), findsNothing);
        await connect(tester);
        expect(find.text('Partidas realizadas'), findsOneWidget);
        expect(find.text('Com desempenho dos jogadores'), findsOneWidget);
        await tester.tap(find.text('Revisar importação →'));
        await settle(tester);
        expect(find.text('Revisar importação'), findsOneWidget);
        expect(find.text('Desempenho da partida'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('fc-import')),
          400,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.byKey(const Key('fc-import')));
        await settle(tester);
        final tables = await tester.runAsync(
          () => db.query('FcScoreCompetition'),
        );
        expect(
          tables!.single['currentDate'],
          failStandings ? '2028-06-20' : '2028-06-30',
        );
        expect(
          await tester.runAsync(() => db.query('ManagerFixtures')),
          hasLength(1),
        );
        if (failStandings) {
          expect(
            find.textContaining('Partida salva. Não foi possível atualizar'),
            findsOneWidget,
          );
        }
        expect(
          requests.where((r) => r.url.path.endsWith('/competitions/1528')),
          hasLength(1),
        );
        expect(
          requests.where(
            (r) =>
                r.url.path.endsWith('/squad') || r.url.path.endsWith('/stats'),
          ),
          isEmpty,
        );
        await unmount(tester);
      },
    );
  }

  testWidgets(
    'Follows a save renamed by the game without asking for the mapping again',
    (tester) async {
      await linkCareer(tester, saveId: 'save-OLD');
      await mount(
        tester,
        FcScoreQuickImportPage(
          person: person,
          repository: repo,
          apiFactory: (uri) => fakeApi(uri),
        ),
      );
      await connect(tester);
      expect(find.text('Partidas realizadas'), findsOneWidget);
      final link = await tester.runAsync(() => repo.linkFor(person.id));
      expect(link!.saveId, 'save-A');
      await unmount(tester);
    },
  );

  testWidgets(
    'Completes a registered fixture from the recommended match without replacing its data',
    (tester) async {
      await linkCareer(tester);
      await configureStandings(tester);
      late Map<String, Object?> fixture;
      await tester.runAsync(() async {
        await db.insert('ManagerFixtures', {
          ...reviewFixture(0, season: season.id),
          'id': 'mine',
          'date': '2028-06-25T00:00:00.000',
          'oppositeTeamId': 'rival',
          'location': 'away',
          'playerTeamScore': 2,
          'oppositeTeamScore': 1,
          'notes': 'Minha anotação',
        });
        fixture = (await db.query('ManagerFixtures')).single;
      });
      bool? completed;
      await mount(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              completed = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => FcScoreQuickImportPage(
                    person: person,
                    repository: repo,
                    apiFactory: (uri) => fakeApi(uri),
                    target: fixture,
                  ),
                ),
              );
            },
            child: const Text('Abrir'),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await settle(tester);
      expect(find.text('Completar com a API'), findsOneWidget);
      await connect(tester);
      expect(find.text('Recomendada'), findsOneWidget);
      await preview(tester, 'complete-recommended');
      await tester.tap(find.byKey(const Key('fc-recommended-match')));
      await settle(tester);
      expect(find.text('Completar partida'), findsWidgets);
      expect(find.textContaining('No save o placar foi'), findsNothing);
      await preview(tester, 'complete-review');
      await tester.scrollUntilVisible(
        find.byKey(const Key('fc-complete')),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('fc-complete')));
      await settle(tester);
      expect(find.text('Criar jogadores do adversário?'), findsOneWidget);
      expect(completed, isNull);
      await preview(tester, 'complete-opponent-consent');
      await tester.tap(find.text('Criar e completar'));
      await settle(tester);
      expect(completed, isTrue);
      final saved = await tester.runAsync(
        () async => (await db.query('ManagerFixtures')).single,
      );
      expect(saved!['notes'], 'Minha anotação');
      expect(saved['playerTeamScore'], 2);
      expect(saved['playerTeamShoutsCount'], 15);
      final ledger = await tester.runAsync(() => db.query('FcScoreImport'));
      expect(ledger!.single['fixtureId'], 'mine');
      expect(ledger.single['completedByUser'], 1);
      final tables = await tester.runAsync(
        () => db.query('FcScoreCompetition'),
      );
      expect(tables!.single['currentDate'], '2028-06-30');
      await unmount(tester);
    },
  );

  testWidgets(
    'Lists a detailed report exported after the last save and opens it',
    (tester) async {
      await linkCareer(tester);
      await mount(
        tester,
        FcScoreQuickImportPage(
          person: person,
          repository: repo,
          apiFactory: (uri) => fakeApi(uri, unsaved: true),
        ),
      );
      await connect(tester);
      const note = 'Ainda não salva no jogo · com desempenho dos jogadores';
      expect(find.text(note), findsOneWidget);
      expect(find.textContaining('depois do último save'), findsOneWidget);
      expect(find.text('Com desempenho dos jogadores'), findsOneWidget);
      await tester.tap(find.text(note));
      await settle(tester);
      expect(find.text('Revisar importação'), findsOneWidget);
      expect(find.text('Desempenho da partida'), findsOneWidget);
      expect(find.textContaining('batch-B'), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets('Asks to connect when the career has no link', (tester) async {
    await mount(
      tester,
      FcScoreQuickImportPage(
        person: person,
        repository: repo,
        apiFactory: (uri) => fakeApi(uri),
      ),
    );
    expect(find.text('Conectar ao PC'), findsOneWidget);
    expect(find.text('Partidas realizadas'), findsNothing);
    await unmount(tester);
  });

  testWidgets('A recent address that does not answer keeps the choices', (
    tester,
  ) async {
    await linkCareer(tester);
    await mount(
      tester,
      FcScoreQuickImportPage(
        person: person,
        repository: repo,
        apiFactory: (uri) => fakeApi(uri, failHealth: true),
      ),
    );
    await connect(tester);
    expect(find.text('Partidas realizadas'), findsNothing);
    expect(find.text('192.168.0.20:38291'), findsOneWidget);
    expect(find.text('Outro endereço'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
    'New fixture offers the API import at the top; editing does not',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      Future<void> form(Map<String, Object?>? existing) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ManagerFixtureForm(
              person: person,
              existing: existing,
              seasonId: season.id,
              preloaded: (
                seasons: [season],
                players: const [],
                roster: const [],
              ),
            ),
          ),
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
      }

      await form(null);
      expect(find.text('Importar partida da API'), findsOneWidget);
      await form({...reviewFixture(0, season: season.id), 'id': 'existing'});
      expect(find.text('Importar partida da API'), findsNothing);
    },
  );
}
