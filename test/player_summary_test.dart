import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileData.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerScoringInsights.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerSummary/PlayerSummaryData.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerSummary/PlayerSummaryTab.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/models/Person.dart';
import 'package:mcmanager/models/Season.dart';

import 'ui_preview_fonts.dart';

const _player = 'p9';

Map<String, Object?> _fixture(
  String id,
  String season,
  String date,
  int us,
  int them, {
  List<int?> opponentGoals = const [],
  String team = 'club',
}) => {
  'id': id,
  'date': date,
  'seasonId': season,
  'tournamentId': 'league',
  'location': 'home',
  'extraTime': 0,
  'playerTeamId': team,
  'oppositeTeamId': 'rival-$id',
  'playerTeamScore': us,
  'oppositeTeamScore': them,
  'opponentGoalDetails': jsonEncode([
    for (final minute in opponentGoals) {'minute': minute},
  ]),
};

PerformanceGoalDetails _goal(int? minute, {String? assistant}) =>
    PerformanceGoalDetails(
      minute: minute,
      assistantId: assistant,
      type: [GoalType.openplay],
    );

PlayerMatchData _match(
  Map<String, Object?> fixture, {
  double rating = 7,
  List<PerformanceGoalDetails> goals = const [],
  List<PerformanceAssistDetails> assists = const [],
  List<PerformanceSubstitutionDetails> subs = const [],
  List<PerformanceTimeDetails> reds = const [],
}) {
  final performance = ManagerFixturePlayerPerformance(
    personId: 'career',
    fixtureId: fixture['id'] as String,
    playerInstanceId: _player,
    goalsCount: goals.length,
    assistsCount: assists.length,
    redCards: reds.length,
    avgRating: rating,
    goalDetails: goals,
    assistDetails: assists,
    substitutionDetails: subs,
    redCardDetails: reds,
  ).toMap();
  return PlayerMatchData({
    ...performance,
    'fixtureId': fixture['id'],
    'date': fixture['date'],
    'seasonId': fixture['seasonId'],
    'tournamentId': fixture['tournamentId'],
    'playerTeamId': fixture['playerTeamId'],
    'oppositeTeamId': fixture['oppositeTeamId'],
    'playerTeamScore': fixture['playerTeamScore'],
    'oppositeTeamScore': fixture['oppositeTeamScore'],
    'extraTime': 0,
  });
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    await loadPreviewFonts();
  });
  final f1 = _fixture('f1', 's1', '2027-02-01', 1, 0);
  final f2 = _fixture('f2', 's1', '2027-03-01', 2, 2, opponentGoals: [30, 60]);
  final f3 = _fixture('f3', 's1', '2027-04-01', 3, 0);
  final f4 = _fixture('f4', 's1', '2027-05-01', 0, 1, opponentGoals: [55]);
  final f5 = _fixture('f5', 's2', '2028-02-01', 1, 2, opponentGoals: [40, 85]);
  final f6 = _fixture('f6', 's2', '2028-03-01', 2, 0);
  final f7 = _fixture('f7', 's1', '2027-06-01', 0, 3, team: 'national');

  final matches = [
    _match(f1, goals: [_goal(88, assistant: 'p7')]),
    _match(
      f2,
      assists: [PerformanceAssistDetails(minute: 80, goalscorerId: 'p7')],
      subs: [
        PerformanceSubstitutionDetails(
          minute: 46,
          type: SubstitutionType.inGame,
        ),
      ],
    ),
    _match(
      f3,
      rating: 8.4,
      goals: [_goal(20, assistant: 'p5')],
      subs: [
        PerformanceSubstitutionDetails(
          minute: 60,
          type: SubstitutionType.outGame,
        ),
      ],
    ),
    _match(f5, rating: 5.5, reds: [PerformanceTimeDetails(minute: 70)]),
  ];
  final source = PlayerSummarySource(
    fixtures: [f1, f2, f3, f4, f5, f6, f7],
    teamGoals: {
      'f1': [_goal(88)],
      'f2': [_goal(10), _goal(80)],
      'f3': [_goal(20), _goal(50), _goal(70)],
      'f5': [_goal(30)],
      'f6': [_goal(null), _goal(null)],
    },
    names: {'p7': 'Calleri', 'p5': 'Lucas'},
  );

  test('resumo de todas as temporadas', () {
    final s = PlayerSummary(allMatches: matches, source: source);
    expect(s.totals.matches, 4);
    expect(s.contributions, 3);

    expect(s.decidedMatches, 2);
    expect(s.pointsSecured, 3);
    expect(s.winsSecured, 1);
    expect(s.drawsSaved, 1);

    expect(
      [s.withHim.games, s.withHim.wins, s.withHim.draws, s.withHim.losses],
      [4, 2, 1, 1],
    );
    expect([s.withHim.goalsFor, s.withHim.goalsAgainst], [7, 4]);
    expect(
      [s.withoutHim.games, s.withoutHim.wins, s.withoutHim.losses],
      [2, 1, 1],
    );

    expect([s.minutesOn, s.minutesOff], [264, 276]);
    expect([s.forOn, s.forOff, s.againstOn, s.againstOff], [5, 4, 2, 3]);
    expect(s.unassignedGoals, 0);

    expect(s.goalsByBand[5], 1);
    expect(s.goalsByBand[1], 1);
    expect(s.assistsByBand[5], 1);

    expect(s.assistedBy.map((p) => p.$1), containsAll(['Calleri', 'Lucas']));
    expect(s.assistedTo, [('Calleri', 1)]);
    expect(s.ratingBands, [1, 0, 2, 1, 0]);
  });

  test('resumo de uma temporada', () {
    final s = PlayerSummary(
      allMatches: matches,
      source: source,
      seasonId: 's2',
    );
    expect(s.totals.matches, 1);
    expect([s.withHim.games, s.withHim.losses], [1, 1]);
    expect([s.withoutHim.games, s.withoutHim.wins], [1, 1]);
    expect(s.decidedMatches, 0);
  });

  for (final size in [const Size(400, 820), const Size(320, 640)]) {
    testWidgets('Resumo mostra as seções rolando em ${size.width}', (
      tester,
    ) async {
      final previewKey = GlobalKey();
      Future<void> capture(String section) async {
        final directory = Platform.environment['PLAYER_STATS_PREVIEW_DIR'];
        if (directory == null) return;
        await tester.runAsync(() async {
          final boundary =
              previewKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final picture = await boundary.toImage(pixelRatio: 2);
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await Directory(directory).create(recursive: true);
          await File('$directory/resumo-${size.width.toInt()}-$section.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }

      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: RepaintBoundary(
            key: previewKey,
            child: Scaffold(
              body: PlayerSummaryTab(
                person: Person(
                  id: 'career',
                  name: 'Treinador',
                  category: PersonCategory.manager,
                  fifaVersion: 'FC26',
                  leagueId: 'league',
                  teamId: 'club',
                  nationalityId: '54',
                  nationalCoachingTeamId: 'national',
                  createdAt: DateTime(2027),
                  updatedAt: DateTime(2027),
                ),
                data: PlayerProfileData(
                  seasons: [
                    Season(
                      id: 's1',
                      personId: 'career',
                      startDate: DateTime(2027),
                      endDate: DateTime(2027, 12, 31),
                      createdAt: DateTime(2027),
                    ),
                    Season(
                      id: 's2',
                      personId: 'career',
                      startDate: DateTime(2028),
                      endDate: DateTime(2028, 12, 31),
                      createdAt: DateTime(2028),
                    ),
                  ],
                  matches: matches,
                  overalls: const [],
                  marketValues: const [],
                  contracts: const [],
                  tournamentNames: const {'league': 'Brasileiro Serie A'},
                ),
                source: source,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Visão geral'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await capture('inicio');
      final scrollable = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first;
      final contributions = find.byKey(
        const ValueKey('player-trend-contributions'),
      );
      await tester.scrollUntilVisible(
        contributions,
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      await tester.tap(contributions);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(contributions).selected, isTrue);
      expect(
        find.byKey(const ValueKey('player-line-contributions')),
        findsOneWidget,
      );
      for (final title in [
        'Atuações',
        'Gols e assistências por minuto',
        'Com ele e sem ele',
        'Em campo e fora de campo',
        'Decisivo',
        'Parcerias',
        'Tipos de gol',
        'Posicionamento do chute',
        'Mapa de gols',
        'Pênaltis',
        'Capitania',
        'Por temporada',
      ]) {
        await tester.scrollUntilVisible(
          find.text(title),
          240,
          scrollable: scrollable,
          maxScrolls: 40,
        );
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget, reason: title);
        expect(tester.takeException(), isNull);
      }
      await capture('temporadas');
      await tester.scrollUntilVisible(
        find.byType(DropdownButton<String>),
        -300,
        scrollable: scrollable,
        maxScrolls: 40,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Temporada 2028').last);
      await tester.pumpAndSettle();
      expect(find.text('Desempenho em 2028.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(PlayerScoringInsights),
        240,
        scrollable: scrollable,
        maxScrolls: 40,
      );
      expect(
        tester
            .widget<PlayerScoringInsights>(find.byType(PlayerScoringInsights))
            .matches
            .every((m) => m.seasonId == 's2'),
        isTrue,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('player-summary-section/decisive')),
        -240,
        scrollable: scrollable,
        maxScrolls: 40,
      );
      expect(
        find.byKey(const ValueKey('player-summary-section/decisive')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
