import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Common/FixtureDetailsPage.dart';
import 'package:mcmanager/Common/FixtureFormationView.dart';
import 'package:mcmanager/models/FixtureFormation.dart';
import 'package:mcmanager/ManagerCareer/Fixtures/ManagerFixtureForm.dart';
import 'package:mcmanager/ManagerCareer/Fixtures/SelectTeamPlayerPage.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/models/Person.dart';
import 'package:mcmanager/models/Season.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/FixtureTablePosition.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import 'ui_preview_fonts.dart';

void main() {
  final person = Person(
    id: 'career',
    name: 'Treinador',
    category: PersonCategory.manager,
    fifaVersion: 'FC26',
    leagueId: 'club-league',
    teamId: 'club',
    nationalityId: '54',
    nationalCoachingTeamId: 'national',
    createdAt: DateTime(2028),
    updatedAt: DateTime(2028),
  );
  final season = Season(
    id: 'season',
    personId: person.id,
    startDate: DateTime(2028),
    endDate: DateTime(2028, 12, 31),
    createdAt: DateTime(2028),
  );
  final players = [
    for (final (id, name, position) in [
      ('p1', 'Samuel Guimaraes', '25'),
      ('p2', 'Ian Moreira', '23'),
      ('p3', 'Pablo Maia', '10'),
      ('p4', 'Arboleda', '5'),
      ('p5', 'Aloisio Ceni', '0'),
    ])
      {'id': id, 'name': name, 'positionId': position},
  ];
  final roster = [
    for (final player in players)
      {
        'id': 'tp-${player['id']}',
        'playerId': player['id'],
        'customName': player['name'],
        'customPositionId': player['positionId'],
        'overall': 70,
        'isBench': 0,
      },
  ];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadPreviewFonts();
    await GameCatalog.load();
  });

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    final directory = Platform.environment['PROFILE_PREVIEW_DIR'];
    if (directory == null) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final picture = await boundary.toImage(pixelRatio: 2);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('nova partida: placar, campos, escalação automática', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: ManagerFixtureForm(
            person: person,
            seasonId: season.id,
            preloaded: (seasons: [season], players: players, roster: roster),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('fixtures.addFixture'), findsOneWidget);
    expect(find.text('tournaments.tournament'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.text('common.auto'));
    await tester.pumpAndSettle();
    expect(find.text('Pablo Maia'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'nova_partida');
  });

  testWidgets('selecionar jogadores: filtro, já escalados e vários', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey();
    List<SelectedTeamPlayer>? result;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => RepaintBoundary(key: key, child: child),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await Navigator.push<List<SelectedTeamPlayer>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SelectTeamPlayerPage(
                        fifaVersion: person.fifaVersion,
                        roster: roster,
                        names: {
                          for (final player in players)
                            player['id']!: player['name']!,
                        },
                        positions: const {},
                        multiple: true,
                        usedIds: const {'p1'},
                        seasonStats: Future.value([
                          {
                            'playerId': 'p3',
                            'matches': 12,
                            'goals': 5,
                            'assists': 3,
                            'rating': 7.24,
                          },
                        ]),
                      ),
                    ),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('12'), findsOneWidget);
    expect(find.text('7.2'), findsOneWidget);
    await tester.tap(find.text('Samuel Guimaraes'));
    await tester.pump();
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.text('Pablo Maia'));
    await tester.tap(find.text('Aloisio Ceni'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await capture(tester, key, 'selecionar_jogador');
    final goalkeepers = find.widgetWithText(
      ChoiceChip,
      'positions.positionsList.GK',
    );
    await tester.dragUntilVisible(
      goalkeepers,
      find.byType(ListView).first,
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(goalkeepers);
    await tester.pumpAndSettle();
    expect(find.text('Pablo Maia'), findsNothing);
    expect(find.text('Aloisio Ceni'), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(result?.map((player) => player.id), ['p3', 'p5']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partida registrada: artilheiros, estatísticas e escalação', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ManagerFixturePlayerPerformance performance(
      String id, {
      double? rating,
      List<PerformanceGoalDetails>? goals,
      List<PerformanceSubstitutionDetails>? subs,
      List<PerformanceCardDetails>? yellow,
    }) => ManagerFixturePlayerPerformance(
      personId: person.id,
      fixtureId: 'fixture',
      playerInstanceId: id,
      avgRating: rating,
      goalDetails: goals,
      substitutionDetails: subs,
      yellowCardDetails: yellow,
    );
    final lineup = FixtureLineupData(
      roster,
      [
        performance(
          'p1',
          rating: 6.6,
          subs: [
            PerformanceSubstitutionDetails(
              minute: 68,
              type: SubstitutionType.outGame,
            ),
          ],
        ),
        performance(
          'p2',
          rating: 6.9,
          goals: [PerformanceGoalDetails(minute: 49)],
        ),
        performance('p3', rating: 9.2),
        performance(
          'p4',
          rating: 5.7,
          yellow: [PerformanceCardDetails(minute: 88)],
        ),
        performance(
          'p5',
          rating: 6.0,
          goals: [
            PerformanceGoalDetails(minute: 36, type: [GoalType.penalty]),
          ],
        ),
      ],
      {for (final player in players) player['id']!: player['name']!},
      {for (final player in players) player['id']!: player['positionId']!},
    );
    final key = GlobalKey();
    FixtureFormation? savedFormation;
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: FixtureDetailsPage(
            person: person,
            fixture: {
              'id': 'fixture',
              'personId': person.id,
              'date': '2028-02-23T00:00:00.000',
              'playerTeamId': person.teamId,
              'oppositeTeamId': 'opponent',
              'playerTeamScore': 2,
              'oppositeTeamScore': 2,
              'location': 'away',
              'tournamentId': 'serieA',
              'seasonId': season.id,
              'stage': 'Rodada 4',
              'teamPossession': 45.0,
              'passAccuracy': 77.0,
              'playerTeamShoutsCount': 16,
              'opponentTeamShotsCount': 7,
              'playerOfTheMatchId': 'p3',
              'position': 7,
              'opponentGoalDetails':
                  '[{"scorerName":"Viveros","minute":68,"type":"[\\"penalty\\"]"},'
                  '{"scorerName":"Wallace Franca","minute":90,"addedMinute":4}]',
            },
            opponent: 'Athletico Paranaense',
            tournament: 'Brasileiro Serie A',
            lineupData: Future.value(lineup),
            tablePosition: Future.value(
              const FixtureTablePosition(position: 7, previous: 9),
            ),
            onFormationSaved: (value) async => savedFormation = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('fixtures.playerOfTheMatch'), findsOneWidget);
    expect(find.text('Destaques'), findsOneWidget);
    expect(find.byKey(const ValueKey('fixture-highlight-p3')), findsOneWidget);
    expect(find.byKey(const ValueKey('principal-formation')), findsOneWidget);
    expect(find.text('fixtures.headToHead'), findsOneWidget);
    expect(find.byTooltip('Ganhou 2 posições · 9º → 7º'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byIcon(TablerIcons.microphone), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'partida_registrada');
    expect(find.widgetWithText(Tab, 'Principal'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Linha do Tempo'));
    await tester.pumpAndSettle();
    expect(find.text('Wallace Franca'), findsOneWidget);
    expect(find.text('Gol de pênalti'), findsNWidgets(2));
    expect(find.text('Saiu de campo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'partida_linha_do_tempo');
    await tester.tap(find.widgetWithText(Tab, 'Formação'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fixture-pitch-4-3-3')), findsOneWidget);
    expect(savedFormation, isNull);
    final pitch = tester.widget<FixtureFormationView>(
      find.byType(FixtureFormationView),
    );
    expect(pitch.available.starters.length, 5);
    expect(pitch.available.players['p3']?['name'], 'Pablo Maia');
    expect(find.text('Reservas relacionados · 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'partida_formacao');
    await tester.tap(find.widgetWithText(Tab, 'Principal'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('principal-formation')), findsOneWidget);
  });
}
