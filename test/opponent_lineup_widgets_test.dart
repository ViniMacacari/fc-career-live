import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Common/FixtureDetailsPage.dart';
import 'package:mcmanager/Common/FixtureCaptainPanel.dart';
import 'package:mcmanager/Common/FixtureFormationView.dart';
import 'package:mcmanager/models/FixtureFormation.dart';
import 'package:mcmanager/models/FixtureCaptaincy.dart';
import 'package:mcmanager/ManagerCareer/Fixtures/ManagerFixtureForm.dart';
import 'package:mcmanager/ManagerCareer/Fixtures/OpponentLineupEditor.dart';
import 'package:mcmanager/ManagerCareer/Fixtures/OpponentGoals/OpponentGoalsPanel.dart';
import 'package:mcmanager/ManagerCareer/Fixtures/Performances/PerformanceDetails.dart';
import 'package:mcmanager/ManagerCareer/Fixtures/Performances/TeamPlayersPerformanceGrid.dart';
import 'package:mcmanager/utils/databaseUtils.dart';
import 'package:mcmanager/utils/Components/PlayerAvatar.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/models/ManagerFixture.dart';
import 'package:mcmanager/models/OpponentLineup.dart';
import 'package:mcmanager/utils/FixtureTablePosition.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';

class _Translations extends AssetLoader {
  const _Translations(this.values);
  final Map<String, dynamic> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['PROFILE_PREVIEW_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  late Map<String, dynamic> translations;
  Widget app({required Widget home}) => EasyLocalization(
    supportedLocales: const [Locale('pt', 'BR')],
    startLocale: const Locale('pt', 'BR'),
    fallbackLocale: const Locale('pt', 'BR'),
    path: 'assets/translations',
    assetLoader: _Translations(translations),
    saveLocale: false,
    child: Builder(
      builder: (context) => MaterialApp(
        theme: managerDarkTheme,
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: context.localizationDelegates,
        home: home,
      ),
    ),
  );
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory('build/opponent-photo-test-docs').absolute.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (_) async =>
          File('assets/branding/fc-career-live-icon.png').absolute.path,
    );
    await EasyLocalization.ensureInitialized();
    translations = jsonDecode(
      await rootBundle.loadString('assets/translations/pt_BR.json'),
    ) as Map<String, dynamic>;
    await loadPreviewFonts();
    await GameCatalog.load();
  });

  testWidgets(
    'Captain selection prompts for the armband on substitution and persists when reopened',
    (tester) async {
      viewport(tester, const Size(360, 800));
      final key = GlobalKey();
      final performances = [
        ManagerFixturePlayerPerformance(
          personId: 'career',
          fixtureId: 'f1',
          playerInstanceId: 'a',
          substitutionDetails: [
            PerformanceSubstitutionDetails(
              id: 'out-a',
              minute: 65,
              type: SubstitutionType.outGame,
            ),
          ],
        ),
        ManagerFixturePlayerPerformance(
          personId: 'career',
          fixtureId: 'f1',
          playerInstanceId: 'b',
          substitutionDetails: [
            PerformanceSubstitutionDetails(
              id: 'in-b',
              minute: 65,
              type: SubstitutionType.inGame,
            ),
          ],
        ),
        ManagerFixturePlayerPerformance(
          personId: 'career',
          fixtureId: 'f1',
          playerInstanceId: 'c',
        ),
      ];
      final players = [
        for (final (id, name) in [
          ('a', 'Arboleda'),
          ('b', 'Calleri'),
          ('c', 'Lucas'),
        ])
          {'id': id, 'name': name, 'positionId': '25'},
      ];
      Map<String, Object?>? saved;
      Widget form(Map<String, Object?> existing) => ManagerFixtureForm(
        key: ValueKey(existing['captaincy']),
        person: reviewPerson(),
        existing: existing,
        preloaded: (seasons: [reviewSeason()], players: players, roster: []),
        preloadedPerformances: performances,
        onFixtureSaved: (value, perfs) async {
          saved = value;
        },
      );
      Future<void> open(Map<String, Object?> existing) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          app(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RepaintBoundary(key: key, child: form(existing)),
                    ),
                  ),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Abrir'));
        await tester.pumpAndSettle();
      }

      await open(reviewFixture(1));
      final panel = find.byKey(const ValueKey('fixture-captaincy'));
      await tester.dragUntilVisible(
        panel,
        find.byKey(const PageStorageKey('edit-fixture-main')),
        const Offset(0, -220),
      );
      await tester.ensureVisible(find.text('Escolher capitão'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escolher capitão'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('captain-pick-b')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('captain-pick-a')));
      await tester.pumpAndSettle();
      expect(find.text('Quem recebeu a braçadeira?'), findsOneWidget);
      expect(find.byKey(const ValueKey('captain-pick-a')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('captain-search')),
        'Call',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('captain-pick-c')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('captain-pick-b')));
      await tester.pumpAndSettle();
      await capture(tester, key, 'captain-lineup');
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      final captaincy = FixtureCaptaincy.decode(saved?['captaincy']);
      expect(captaincy.initialPlayerId, 'a');
      expect(captaincy.handovers.single.playerId, 'b');
      expect(captaincy.handovers.single.substitutionId, 'out-a');

      await open(saved!);
      await tester.dragUntilVisible(
        panel,
        find.byKey(const PageStorageKey('edit-fixture-main')),
        const Offset(0, -220),
      );
      expect(find.text('Arboleda · desde o início'), findsOneWidget);
      expect(find.textContaining('Calleri'), findsWidgets);
      final handover = find
          .descendant(of: panel, matching: find.byType(InkWell))
          .last;
      await tester.ensureVisible(handover);
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        handover.hitTestable(),
        find.byKey(const PageStorageKey('edit-fixture-main')),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      await tester.tap(handover);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('captain-none')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(
        FixtureCaptaincy.decode(saved?['captaincy']).handovers.single.playerId,
        isNull,
      );

      await tester.pumpWidget(
        app(
          home: Scaffold(
            body: FixtureCaptainPanel(
              captaincy: captaincy,
              performances: performances,
              names: const {'a': 'Arboleda', 'b': 'Calleri', 'c': 'Lucas'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(
        tester
            .widgetList<InkWell>(find.byType(InkWell))
            .every((w) => w.onTap == null),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Formation is editable only within the lineup section and saved with the match',
    (tester) async {
      viewport(tester, const Size(390, 840));
      Map<String, Object?>? saved;
      final players = [
        for (var i = 0; i < 11; i++)
          {
            'id': 'p$i',
            'name': 'Jogador $i',
            'positionId': i == 10 ? '0' : '25',
          },
      ];
      await tester.pumpWidget(
        app(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Abrir'),
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ManagerFixtureForm(
                      person: reviewPerson(),
                      existing: reviewFixture(1),
                      preloaded: (
                        seasons: [reviewSeason()],
                        players: players,
                        roster: [
                          for (final p in players)
                            {
                              'id': 't${p['id']}',
                              'playerId': p['id'],
                              'customPositionId': p['positionId'],
                            },
                        ],
                      ),
                      preloadedPerformances: [
                        for (final p in players)
                          ManagerFixturePlayerPerformance(
                            personId: 'career',
                            fixtureId: 'f1',
                            playerInstanceId: p['id']!,
                          ),
                      ],
                      onFixtureSaved: (fixture, _) async {
                        saved = fixture;
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      final scroll = find.byKey(const PageStorageKey('edit-fixture-main'));
      final toggle = find.byKey(const ValueKey('lineup-view-formation'));
      await tester.dragUntilVisible(
        toggle.hitTestable(),
        scroll,
        const Offset(0, -200),
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final choose = find.byKey(const ValueKey('choose-fixture-formation'));
      await tester.ensureVisible(choose);
      await tester.pumpAndSettle();
      await tester.tap(choose);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '4-4-2'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.byType(LongPressDraggable<String>), findsWidgets);
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lineup-view-list')));
      await tester.pumpAndSettle();
      expect(find.byType(FixtureFormationView), findsNothing);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      final snapshot = FixtureFormation.decode(saved?['matchLineup'])!;
      expect(snapshot.formation, '4-4-2');
      var writes = 0;
      await tester.pumpWidget(
        app(
          home: Scaffold(
            body: FixtureFormationView(
              person: reviewPerson(),
              saved: snapshot,
              available: snapshot,
              performances: const [],
              header: const SizedBox.shrink(),
              onSave: (_) async {
                writes++;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LongPressDraggable<String>), findsNothing);
      expect(find.byKey(const ValueKey('relate-fixture-bench')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('choose-fixture-formation')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Goal picker includes the opponent custom roster and creates a player inline',
    (tester) async {
      viewport(tester, const Size(360, 800));
      final key = GlobalKey();
      var lineup = OpponentLineup.empty().addReserve('Nicolas personalizado');
      var goals = <OpponentGoalDetails>[];
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: app(
            home: StatefulBuilder(
              builder: (context, update) => Scaffold(
                body: OpponentGoalsPanel(
                  person: reviewPerson(),
                  lineup: lineup,
                  goals: goals,
                  loadPlayers: () async => [
                    {'id': 'world-custom', 'name': 'João do adversário'},
                    {'id': 'blank', 'name': ''},
                    {'id': 'spaces', 'name': '  '},
                    {'id': 'missing'},
                    {
                      'id': 'fc-opponent:42',
                      'apiPlayerId': '42',
                      'name': 'Jogador 42',
                    },
                  ],
                  onLineupChanged: (next) => update(() => lineup = next),
                  onChanged: (next) => update(() => goals = next),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-opponent-goal')));
      await tester.pumpAndSettle();
      expect(find.text('Nicolas personalizado'), findsOneWidget);
      expect(find.text('João do adversário'), findsOneWidget);
      expect(
        find.widgetWithText(ListTile, 'Elenco adversário'),
        findsNWidgets(2),
      );
      expect(find.text('Jogador 42'), findsNothing);
      await capture(tester, key, 'opponent-goal-picker');
      await tester.tap(find.text('João do adversário'));
      await tester.pumpAndSettle();
      expect(goals.single.scorerName, 'João do adversário');
      expect(lineup.names.values, contains('João do adversário'));
      await tester.tap(find.byKey(const ValueKey('add-opponent-goal')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Criar jogador neste adversário'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('opponent-player-name')),
        'Novo atacante',
      );
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(goals.map((g) => g.scorerName), [
        'João do adversário',
        'Novo atacante',
      ]);
      expect(lineup.names.values, contains('Novo atacante'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Opponent editor prepares slots, edits names, records substitutions and ratings',
    (tester) async {
      viewport(tester, const Size(360, 800));
      var lineup = OpponentLineup.empty();
      final goalkeeper = lineup.startingIds.first;
      for (var i = 1; i < 11; i++) {
        lineup = lineup.rename(lineup.startingIds[i], 'Adversário $i');
      }
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => SingleChildScrollView(
                  key: const ValueKey('editor-scroll'),
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 80),
                  child: OpponentLineupEditor(
                    person: reviewPerson(),
                    fixtureId: 'match',
                    lineup: lineup,
                    onChanged: (value) => update(() => lineup = value),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TeamPlayersPerformanceGrid), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.byKey(ValueKey('add-opponent-player-$goalkeeper')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('opponent-player-name')),
        'Alisson',
      );
      await tester.tap(find.byKey(const ValueKey('opponent-player-photo')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('save-opponent-player')));
        for (var i = 0; i < 100 && lineup.names[goalkeeper] != 'Alisson'; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(lineup.names[goalkeeper], 'Alisson');
      final photo =
          lineup.squad.players[goalkeeper]?['customAvatarFilePath'] as String;
      expect(photo, startsWith('/faces/'));
      expect(File(CustomImageFiles.absolute(photo)!).existsSync(), isTrue);
      expect(
        lineup.forNewMatch().squad.players[goalkeeper]?['customAvatarFilePath'],
        photo,
      );
      await tester.tap(find.byKey(const ValueKey('add-opponent-player')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('opponent-player-name')),
        'Reserva Novo',
      );
      await tester.tap(find.byKey(const ValueKey('save-opponent-player')));
      await tester.pumpAndSettle();
      expect(lineup.squad.bench, hasLength(1));
      final reserve = lineup.squad.bench.single;
      expect(lineup.names[reserve], 'Reserva Novo');
      final row = find.byKey(ValueKey('performance-row-$goalkeeper'));
      expect(tester.getSize(row).height, 44);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(PerformanceDetails), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('rating-input')), '8,4');
      final addSub = find.byKey(const ValueKey('add-fixtures.substitutions'));
      await tester.dragUntilVisible(
        addSub,
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.tap(addSub);
      await tester.pumpAndSettle();
      expect(find.byType(ToggleButtons), findsOneWidget);
      await tester.tap(find.byIcon(Icons.person_add_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reserva Novo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(lineup.performances, hasLength(2));
      final outgoing = lineup.performances
          .where((p) => p.playerInstanceId == goalkeeper)
          .single;
      final incoming = lineup.performances
          .where((p) => p.playerInstanceId == reserve)
          .single;
      expect(outgoing.avgRating, 8.4);
      expect(
        outgoing.substitutionDetails.single.type,
        SubstitutionType.outGame,
      );
      expect(incoming.substitutionDetails.single.type, SubstitutionType.inGame);
      expect(outgoing.substitutionDetails.single.anotherPlayerId, reserve);
      expect(find.byIcon(Icons.sync_alt_rounded), findsNothing);
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('performance-player-identity')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('opponent-player-name')),
        'Alisson atualizado',
      );
      await tester.tap(find.byKey(const ValueKey('save-opponent-player')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(lineup.names[goalkeeper], 'Alisson atualizado');
      expect(lineup.squad.players[goalkeeper]?['customAvatarFilePath'], photo);
      await tester.ensureVisible(
        find.byKey(const ValueKey('choose-opponent-formation')),
      );
      await tester.tap(find.byKey(const ValueKey('choose-opponent-formation')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '4-2-3-1');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '4-2-3-1'));
      await tester.pumpAndSettle();
      expect(lineup.squad.formation, '4-2-3-1');
      expect(lineup.names[goalkeeper], 'Alisson atualizado');
      expect(lineup.startingIds.first, goalkeeper);
      await capture(tester, key, 'opponent_editor');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Match form reuses a team without old events and saves the edited snapshot',
    (tester) async {
      SharedPreferences.setMockInitialValues({'auto_fill_team_score': false});
      viewport(tester, const Size(390, 844));
      var memory = OpponentLineup.empty();
      for (var i = 0; i < 11; i++) {
        memory = memory.rename(memory.startingIds[i], 'Jogador $i');
      }
      final id = memory.startingIds.first;
      memory = memory.editPerformance(
        ManagerFixturePlayerPerformance(
          personId: 'career',
          fixtureId: 'old-match',
          playerInstanceId: id,
          avgRating: 9,
          yellowCardDetails: [PerformanceTimeDetails(minute: 50)],
        ),
      );
      Map<String, Object?>? saved;
      List<ManagerFixturePlayerPerformance>? ownPerfs;
      DateTime? rememberedDate;
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Abrir'),
                onPressed: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RepaintBoundary(
                        key: key,
                        child: ManagerFixtureForm(
                          person: reviewPerson(),
                          existing: {
                            ...reviewFixture(1),
                            'oppositeTeamId': 'fixture-opponent',
                            'tournamentId': 'league:1014',
                            'date': '2026-10-09T00:00:00.000',
                          },
                          preloaded: (
                            seasons: [reviewSeason()],
                            players: [],
                            roster: [],
                          ),
                          opponentLineupLoader: (team, date) async {
                            expect(team.id, 'fixture-opponent');
                            rememberedDate = date;
                            return memory;
                          },
                          onFixtureSaved: (value, performances) async {
                            saved = value;
                            ownPerfs = performances;
                          },
                        ),
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
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.byType(TabBar), findsNothing);
      expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
      expect(rememberedDate, DateTime(2026, 10, 9));
      final scroll = find.byKey(const PageStorageKey('edit-fixture-main'));
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('fixture-opponent-goals')),
        scroll,
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      for (final (ownGoal, name) in [
        (false, 'Gol direto'),
        (true, 'Gol contra direto'),
      ]) {
        final add = find.byKey(
          ValueKey('add-opponent-${ownGoal ? 'own-goal' : 'goal'}'),
        );
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'Inserir manualmente'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), name);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
        await tester.pumpAndSettle();
      }
      await capture(tester, key, 'main_opponent_goal_shortcuts');
      final switchTeam = find.byKey(const ValueKey('lineup-team-opponent'));
      await tester.ensureVisible(switchTeam);
      await tester.pumpAndSettle();
      await tester.tap(switchTeam);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('fixture-lineups-section')),
          matching: switchTeam,
        ),
        findsOneWidget,
      );
      expect(find.text('Jogador 0'), findsOneWidget);
      expect(find.text('9.0'), findsNothing);
      final playerRow = find.byKey(ValueKey('performance-row-$id'));
      await tester.ensureVisible(playerRow);
      await tester.longPress(playerRow);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('opponent-player-name')),
        'Nome atualizado',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-opponent-player')));
      await tester.pumpAndSettle();
      await capture(tester, key, 'match_opponent_tab');
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      final snapshot = OpponentLineup.decode(saved?['opponentLineup']);
      expect(snapshot?.names[id], 'Nome atualizado');
      expect(snapshot?.performances, isEmpty);
      expect(memory.names[id], 'Jogador 0');
      expect(ownPerfs, isEmpty);
      final goals = decodeOpponentGoals(saved?['opponentGoalDetails']);
      expect(goals.map((g) => g.scorerName), [
        'Gol direto',
        'Gol contra direto',
      ]);
      expect(goals.where((g) => g.isOwnGoal), hasLength(1));
      expect(saved?['playerTeamScore'], 1);
      expect(saved?['oppositeTeamScore'], 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Both formations use squad spacing and show ratings on the portraits',
    (tester) async {
      viewport(tester, const Size(390, 1000));
      var opponent = OpponentLineup.empty(formation: '4-2-3-1');
      for (var i = 0; i < 11; i++) {
        opponent = opponent.rename(
          opponent.startingIds[i],
          'Jogador adversário $i',
        );
      }
      opponent = opponent.addReserve('Reserva do adversário');
      final opponentStarter = opponent.startingIds.last;
      opponent = opponent
          .withIdentity(
            opponentStarter,
            name: opponent.names[opponentStarter]!,
            photo: File('assets/branding/fc-career-live-icon.png')
                .absolute
                .path,
          )
          .editPerformance(
            ManagerFixturePlayerPerformance(
              personId: 'career',
              fixtureId: 'match',
              playerInstanceId: opponentStarter,
              substitutionDetails: [
                PerformanceSubstitutionDetails(
                  type: SubstitutionType.outGame,
                  anotherPlayerId: opponent.squad.bench.single,
                ),
              ],
            ),
          );
      final roster = [
        for (var i = 0; i < 11; i++)
          {
            'playerId': 'p$i',
            'id': 't$i',
            'customName': i == 1
                ? 'Samuel Guimarães'
                : i == 2
                ? 'Marcos Antônio'
                : i == 6
                ? 'Domingos Duarte'
                : 'Jogador $i',
            'shirtNumber': i + 1,
            'customPositionId': i == 10
                ? '0'
                : i < 3
                ? '25'
                : i < 6
                ? '14'
                : '5',
          },
      ];
      final names = {
        for (final p in roster) '${p['playerId']}': '${p['customName']}',
      };
      final positions = {
        for (final p in roster) '${p['playerId']}': '${p['customPositionId']}',
      };
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          home: RepaintBoundary(
            key: key,
            child: FixtureDetailsPage(
              person: reviewPerson(),
              fixture: {
                ...reviewFixture(1),
                'oppositeTeamId': 'fixture-opponent',
                'opponentLineup': opponent.encode(),
              },
              opponent: 'Adversário',
              tournament: 'Brasileirão',
              tablePosition: Future.value(
                const FixtureTablePosition(position: 3, previous: 4),
              ),
              lineupData: Future.value(
                FixtureLineupData(
                  roster,
                  [
                    for (var i = 0; i < 11; i++)
                      ManagerFixturePlayerPerformance(
                        personId: 'career',
                        fixtureId: 'match',
                        playerInstanceId: 'p$i',
                        avgRating: 7.3,
                        substitutionDetails: i == 0
                            ? [
                                PerformanceSubstitutionDetails(
                                  type: SubstitutionType.outGame,
                                ),
                              ]
                            : null,
                      ),
                  ],
                  names,
                  positions,
                  positionIds: positions,
                ),
              ),
              onFormationSaved: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Formação'));
      await tester.pumpAndSettle();
      final tabs = tester.getRect(
        find.byKey(const ValueKey('fixture-details-tabs')),
      );
      expect(tabs.left, greaterThanOrEqualTo(16));
      expect(tabs.right, lessThanOrEqualTo(390 - 16));
      final ownSub = find.descendant(
        of: find.byKey(const ValueKey('fixture-pitch-player-p0')),
        matching: find.byType(LineupSubstitutionIcon),
      );
      expect(tester.widget<LineupSubstitutionIcon>(ownSub).incoming, isFalse);
      for (var i = 0; i < 11; i++) {
        final avatar = tester.getRect(find.byKey(ValueKey('pitch-avatar-p$i')));
        final rating = tester.getRect(find.byKey(ValueKey('pitch-rating-p$i')));
        final name = tester.getRect(find.byKey(ValueKey('pitch-name-p$i')));
        expect(rating.overlaps(avatar), isTrue);
        expect(name.top, greaterThan(avatar.bottom));
      }
      await capture(tester, key, 'formation_spacing');
      await tester.tap(find.byKey(const ValueKey('formation-team-opponent')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-opponent-lineup')), findsNothing);
      expect(find.text('Editar escalação do adversário'), findsNothing);
      expect(find.byTooltip('Editar'), findsOneWidget);
      expect(find.byIcon(Icons.sync_alt_rounded), findsNothing);
      final avatar = find.descendant(
        of: find.byKey(ValueKey('pitch-avatar-$opponentStarter')),
        matching: find.byType(PlayerAvatar),
      );
      expect(
        tester.widget<PlayerAvatar>(avatar).customAvatarFilePath,
        File('assets/branding/fc-career-live-icon.png').absolute.path,
      );
      expect(
        find.byKey(const ValueKey('fixture-opponent-pitch')),
        findsOneWidget,
      );
      expect(find.text('4-2-3-1'), findsOneWidget);
      expect(find.text('11/11'), findsOneWidget);
      await capture(tester, key, 'opponent_formation');
      await tester.tap(find.byKey(const ValueKey('formation-team-own')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('fixture-pitch-4-3-3')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'Compact lineup and team selector stay in the form at $width px',
      (tester) async {
        viewport(tester, Size(width, 844));
        const names = [
          'Samuel Guimaraes',
          'Calleri',
          'Ian Moreira',
          'Caio Coutinho',
          'B. Aaronson',
          'Juliano',
          'Gil Batista',
          'Marcos Antonio',
          'Alan',
          'Wagner Jesus',
          'Arboleda',
          'Domingos Duarte',
          'Matias Vina',
          'Luiz Gustavo',
          'Aloisio Ceni',
        ];
        const positions = [
          '25',
          '25',
          '27',
          '27',
          '23',
          '23',
          '18',
          '10',
          '10',
          '10',
          '5',
          '5',
          '7',
          '3',
          '0',
        ];
        final players = [
          for (var i = 0; i < names.length; i++)
            {'id': 'own-$i', 'name': names[i], 'positionId': positions[i]},
        ];
        final performances = [
          for (var i = 0; i < names.length; i++)
            ManagerFixturePlayerPerformance(
              personId: 'career',
              fixtureId: 'match',
              playerInstanceId: 'own-$i',
              avgRating: i == 0 ? 8.4 : 7.2,
              goalDetails: i == 0 ? [PerformanceGoalDetails(minute: 68)] : null,
              assistDetails: i == 0
                  ? [PerformanceAssistDetails(minute: 58)]
                  : null,
              substitutionDetails: i == 0
                  ? [
                      PerformanceSubstitutionDetails(
                        minute: 69,
                        type: SubstitutionType.outGame,
                      ),
                    ]
                  : null,
            ),
        ];
        final key = GlobalKey();
        await tester.pumpWidget(
          app(
            home: RepaintBoundary(
              key: key,
              child: ManagerFixtureForm(
                person: reviewPerson(),
                existing: reviewFixture(1),
                preloaded: (
                  seasons: [reviewSeason()],
                  players: players,
                  roster: [
                    for (final p in players)
                      {
                        'id': 'team-${p['id']}',
                        'playerId': p['id'],
                        'customName': p['name'],
                        'customPositionId': p['positionId'],
                      },
                  ],
                ),
                preloadedPerformances: performances,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TabBar), findsNothing);
        final switchTeam = find.byKey(
          const ValueKey('fixture-lineups-team-selector'),
        );
        final scroll = find.byKey(const PageStorageKey('edit-fixture-main'));
        await tester.dragUntilVisible(
          switchTeam,
          scroll,
          const Offset(0, -180),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('fixture-lineups-section')),
        );
        await tester.pumpAndSettle();
        final row = tester.getRect(
          find.byKey(const ValueKey('performance-row-own-0')),
        );
        expect(row.height, 44);
        expect(
          tester
              .getRect(find.byKey(const ValueKey('performance-row-own-1')))
              .height,
          44,
        );
        expect(
          tester.getCenter(find.text(names.first)).dy,
          closeTo(row.center.dy, 1),
        );
        expect(
          tester.getCenter(find.text('8.4')).dy,
          closeTo(row.center.dy, 1),
        );
        expect(
          tester.getRect(find.text('8.4')).right,
          closeTo(tester.getRect(find.text('7.2').first).right, 1),
        );
        expect(tester.getBottomLeft(switchTeam).dy, lessThanOrEqualTo(row.top));
        expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
        await capture(tester, key, 'compact_editor_${width.toInt()}');
        await tester.tap(find.byKey(const ValueKey('lineup-team-opponent')));
        await tester.pumpAndSettle();
        expect(find.byType(OpponentLineupEditor), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('lineup-team-own')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('performance-row-own-0')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
