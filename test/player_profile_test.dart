import 'package:mcmanager/utils/themes.dart';
import 'package:mcmanager/utils/AppColors.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mcmanager/Common/FixtureResultTile.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileData.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerPerformanceInsights.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileVisuals.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerSummary/PlayerSummaryData.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/ViewPlayerPage.dart';
import 'package:mcmanager/ManagerCareer/Graphics/TeamAnalyticsCharts.dart';
import 'package:mcmanager/models/Person.dart';
import 'package:mcmanager/models/Season.dart';
import 'package:mcmanager/utils/ManagerStatService.dart';

import 'ui_preview_fonts.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    await loadPreviewFonts();
  });

  final person = Person(
    id: 'career',
    name: 'Treinador',
    category: PersonCategory.manager,
    fifaVersion: 'FC27',
    leagueId: '1014',
    teamId: '598',
    nationalityId: '54',
    createdAt: DateTime(2028),
    updatedAt: DateTime(2028),
  );
  final season = Season(
    id: 'season',
    personId: person.id,
    startDate: DateTime(2028),
    endDate: DateTime(2028, 12),
    createdAt: DateTime(2028),
  );
  final match = PlayerMatchData({
    'id': 'performance',
    'personId': person.id,
    'fixtureId': 'fixture',
    'playerInstanceId': 'player',
    'seasonId': season.id,
    'tournamentId': '86',
    'date': '2028-02-09T12:00:00.000',
    'playerTeamId': person.teamId,
    'oppositeTeamId': '123',
    'location': 'home',
    'playerTeamScore': 2,
    'oppositeTeamScore': 1,
    'goalsCount': 2,
    'assistsCount': 1,
    'avgRating': 8.2,
    'playerOfTheMatchId': 'player',
    'isPotmFromMyTeam': 1,
  });
  final data = PlayerProfileData(
    seasons: [season],
    matches: [match],
    overalls: const [],
    marketValues: const [],
    contracts: const [],
    tournamentNames: const {'86': 'Brasileiro Serie A'},
  );

  test('id da nacionalidade é o código da bandeira (54 = Brazil)', () {
    final catalog = jsonDecode(
      File('assets/game_catalog.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final nationalities = (catalog['nationalities'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(
      nationalities.firstWhere((item) => item['id'] == '54')['label'],
      'Brazil',
    );
    for (final item in nationalities) {
      expect(item['imageUrl'], contains('/f_${item['id']}.'));
    }
  });

  test('partidas seguidas do mesmo torneio ficam no mesmo cartão', () {
    final groups = groupByConsecutiveTournament([
      'paulista',
      'paulista',
      'serieA',
      'serieA',
      'supercopa',
      'serieA',
    ], (id) => id);
    expect(groups.map((group) => group.length), [2, 2, 1, 1]);
    expect(groups.map((group) => group.first), [
      'paulista',
      'serieA',
      'supercopa',
      'serieA',
    ]);
  });

  test('V/E/D pelo placar e, no empate, pelos pênaltis', () {
    expect(
      fixtureResult({'playerTeamScore': 5, 'oppositeTeamScore': 0}),
      FixtureResult.win,
    );
    expect(
      fixtureResult({'playerTeamScore': 2, 'oppositeTeamScore': 2}),
      FixtureResult.draw,
    );
    expect(
      fixtureResult({'playerTeamScore': 3, 'oppositeTeamScore': 4}),
      FixtureResult.lose,
    );
    expect(
      fixtureResult({
        'playerTeamScore': 1,
        'oppositeTeamScore': 1,
        'playerTeamPenaltiesScore': 4,
        'oppositeTeamPenaltiesScore': 3,
      }),
      FixtureResult.win,
    );
  });

  test('idade segue calcPlayerAge', () {
    expect(
      calcPlayerAge(
        fifaVersion: 'FC26',
        seasonStart: DateTime(2028),
        seasonEnd: DateTime(2028, 12, 31),
        birthdate: DateTime(2026, 9, 8),
        firstSeasonAge: 25,
      ),
      28,
    );
    expect(
      calcPlayerAge(
        fifaVersion: 'FC24',
        seasonStart: DateTime(2024),
        seasonEnd: DateTime(2024, 12, 31),
        birthdate: DateTime(2000, 1, 16),
        firstSeasonAge: 99,
      ),
      24,
    );
  });

  test('totais do jogador usam as atuações registradas', () {
    final totals = data.totals(seasonId: season.id);
    expect(totals.matches, 1);
    expect(totals.starts, 1);
    expect(totals.motm, 1);
    expect(totals.minutes, 90);
    expect(totals.goals, 2);
    expect(totals.assists, 1);
    expect(totals.ratingLabel, '8.2');
    expect(data.totals(tournamentId: 'other').matches, 0);
  });

  test('evolução ordena atuações e preserva notas ausentes', () {
    final source = [
      match,
      PlayerMatchData({
        ...match.row,
        'fixtureId': 'earlier',
        'date': '2028-02-01',
        'avgRating': null,
        'goalsCount': 0,
        'assistsCount': 3,
        'substitutionDetails': '[{"type":"inGame","minute":60}]',
      }),
    ];
    final ratings = playerTrendPoints(source, PlayerTrendMetric.rating);
    expect(ratings.map((point) => point.detail), ['01/02/2028', '09/02/2028']);
    expect(ratings.map((point) => point.value), [null, 8.2]);
    final production = playerTrendPoints(
      source,
      PlayerTrendMetric.contributions,
    );
    expect(production.map((point) => point.value), [0.0, 2.0]);
    expect(production.map((point) => point.other), [3.0, 1.0]);
    expect(
      playerTrendPoints(
        source,
        PlayerTrendMetric.minutes,
      ).map((point) => point.value),
      [30.0, 90.0],
    );
  });

  for (final dark in [true, false]) {
    testWidgets('perfil abre cinco abas no tema ${dark ? 'escuro' : 'claro'}', (
      tester,
    ) async {
      final previewKey = GlobalKey();
      Future<void> capture(String tab) async {
        final directory = Platform.environment['PROFILE_PREVIEW_DIR'];
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
          await File('$directory/$tab-${dark ? 'dark' : 'light'}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        });
      }

      await tester.binding.setSurfaceSize(const Size(390, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? managerDarkTheme : managerLightTheme,
          home: RepaintBoundary(
            key: previewKey,
            child: ViewPlayerPage(
              person: person,
              row: const {
                'id': 'teamPlayer',
                'personId': 'career',
                'playerId': 'player',
                'seasonId': 'season',
                'customName': 'Brenner',
                'customPositionId': '25',
                'overall': 76,
                'isBench': 0,
              },
              profileData: Future.value(data),
              summarySource: const PlayerSummarySource(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Brenner'), findsOneWidget);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        dark ? AppColors.dark.background : AppColors.light.background,
      );
      await tester.scrollUntilVisible(
        find.text('Classificação geral'),
        240,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Classificação geral'), findsOneWidget);
      expect(find.byType(OverallChart), findsNothing);
      expect(
        find.byKey(
          const ValueKey('player-history-value/Classifica\u00e7\u00e3o geral'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await capture('detalhes');

      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Nota mês a mês'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture('temporada');
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      for (final title in [
        'Resumo da temporada',
        'Ataque',
        'Criação',
        'Defesa e disciplina',
        'Posicionamento do chute',
        'Mapa de gols',
      ]) {
        await tester.scrollUntilVisible(
          find.text(title).first,
          240,
          scrollable: find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .last,
          maxScrolls: 40,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: title);
      }
      await capture('temporada-mapa');

      await tester.tap(find.byType(Tab).at(2));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AnalyticsPanel),
          matching: find.text('Visão geral'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await capture('resumo');

      await tester.tap(find.byType(Tab).at(3));
      await tester.pumpAndSettle();
      expect(find.text('Brasileiro Serie A'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture('partidas');

      await tester.tap(find.byType(Tab).at(4));
      await tester.pumpAndSettle();
      expect(find.text('Todos os Torneios'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TabBarView),
          matching: find.text('Resumo'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await capture('carreira');
    });
  }

  for (final size in [const Size(390, 820), const Size(320, 640)]) {
    testWidgets(
      'Partidas filtra temporadas independentemente em ${size.width}',
      (tester) async {
        final older = Season(
          id: 'older',
          personId: person.id,
          startDate: DateTime(2027),
          endDate: DateTime(2027, 12),
          createdAt: DateTime(2027),
        );
        final empty = Season(
          id: 'empty',
          personId: person.id,
          startDate: DateTime(2026),
          endDate: DateTime(2026, 12),
          createdAt: DateTime(2026),
        );
        final history = PlayerProfileData(
          seasons: [season, older, empty],
          matches: [
            PlayerMatchData({
              ...match.row,
              'fixtureId': 'cup',
              'tournamentId': 'cup',
              'date': '2028-03-01',
            }),
            match,
            PlayerMatchData({
              ...match.row,
              'fixtureId': 'old',
              'seasonId': older.id,
              'date': '2027-03-01',
            }),
          ],
          overalls: const [],
          marketValues: const [],
          contracts: const [],
          tournamentNames: const {
            '86': 'Brasileiro Serie A',
            'cup': 'Copa do Brasil',
          },
        );
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: ViewPlayerPage(
              person: person,
              row: const {
                'id': 'teamPlayer',
                'personId': 'career',
                'playerId': 'player',
                'seasonId': 'season',
                'customName': 'Brenner',
                'customPositionId': '25',
                'overall': 76,
                'isBench': 0,
              },
              profileData: Future.value(history),
              summarySource: const PlayerSummarySource(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Tab).at(3));
        await tester.pumpAndSettle();
        final period = find.byKey(const ValueKey('player-matches-period'));
        Finder verticalScroll() => find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .last;
        Future<void> choosePeriod(String label) async {
          await tester.scrollUntilVisible(
            period,
            -200,
            scrollable: verticalScroll(),
          );
          await tester.tap(period);
          await tester.pumpAndSettle();
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
        }

        Iterable<Object?> shownFixtures() => tester
            .widgetList<FixtureTournamentCard>(
              find.byType(FixtureTournamentCard),
            )
            .expand((card) => card.children.whereType<FixtureResultTile>())
            .map((tile) => tile.fixture['fixtureId']);
        await tester.drag(verticalScroll(), const Offset(0, -250));
        await tester.pumpAndSettle();
        expect(find.text('Atual · 2028'), findsOneWidget);
        expect(shownFixtures(), unorderedEquals(['cup', 'fixture']));
        await choosePeriod('2027');
        expect(shownFixtures(), ['old']);
        await choosePeriod('Todas as temporadas');
        expect(shownFixtures(), unorderedEquals(['cup', 'fixture', 'old']));
        await choosePeriod('2026');
        expect(shownFixtures(), isEmpty);
        expect(find.text('Nenhuma atuação registrada.'), findsOneWidget);
        await choosePeriod('Todas as temporadas');
        await tester.tap(find.text('Todos os Torneios'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'Brasileiro Serie A'));
        await tester.pumpAndSettle();
        expect(shownFixtures(), unorderedEquals(['fixture', 'old']));
        await tester.ensureVisible(find.byType(Tab).at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Tab).at(1));
        await tester.pumpAndSettle();
        final seasonPicker = find.byType(DropdownButton<String>);
        await tester.scrollUntilVisible(
          seasonPicker,
          -200,
          scrollable: verticalScroll(),
        );
        await tester.tap(seasonPicker);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Temporada 2027').last);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<PlayerPerformanceOverview>(
                find.byType(PlayerPerformanceOverview),
              )
              .matches
              .single
              .fixtureId,
          'old',
        );
        await tester.tap(find.byType(Tab).at(3));
        await tester.pumpAndSettle();
        expect(find.text('Todas as temporadas'), findsOneWidget);
        expect(shownFixtures(), unorderedEquals(['fixture', 'old']));
        await choosePeriod('Atual · 2028');
        expect(shownFixtures(), ['fixture']);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
