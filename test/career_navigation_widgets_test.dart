import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mcmanager/Common/FixtureHomeMatchCard.dart';
import 'package:mcmanager/Common/FixturesPage.dart';
import 'package:mcmanager/Common/FixturesInsights.dart';
import 'package:mcmanager/ManagerCareer/Graphics/TeamAnalyticsCharts.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileData.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerSummary/PlayerSummaryData.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerSummary/PlayerSummaryTab.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerPerformanceInsights.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/ViewPlayerPage.dart';
import 'package:mcmanager/utils/Components/CareerInsightWidgets.dart';
import 'package:mcmanager/RootPage/DrawerItem.dart';
import 'package:mcmanager/RootPage/DrawerWidget.dart';
import 'package:mcmanager/RootPage/managerCareerMenuItems.dart';
import 'package:mcmanager/RootPage/playerCareerMenuItems.dart';
import 'package:mcmanager/models/CustomClub.dart';
import 'package:mcmanager/models/Person.dart';
import 'package:mcmanager/models/Season.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui_preview_fonts.dart';

class _PortugueseLoader extends AssetLoader {
  const _PortugueseLoader(this.translations);
  final Map<String, dynamic> translations;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      translations;
}

void main() {
  late FixturesData source;
  late Map<String, dynamic> translations;
  final person = Person(
    id: 'career',
    name: 'Minha carreira no São Paulo',
    category: PersonCategory.manager,
    fifaVersion: 'FC26',
    leagueId: '1014',
    teamId: '40-13',
    nationalityId: '54',
    createdAt: DateTime(2025),
    updatedAt: DateTime(2026),
  );
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await initializeDateFormatting('pt_BR');
    await loadPreviewFonts();
    translations = jsonDecode(
      await rootBundle.loadString('assets/translations/pt_BR.json'),
    ) as Map<String, dynamic>;
    final catalog = await GameCatalog.load();
    catalog.debugSetCustomData(
      clubs: [
        CustomClub(
          id: 'opponent',
          label: 'Flamengo',
          leagueId: '1014',
          fifaVersion: 'FC26',
          createdAt: DateTime(2025),
          updatedAt: DateTime(2026),
        ),
      ],
    );
    source = FixturesData(
      [
        for (final year in [2026, 2025])
          Season(
            id: 's$year',
            personId: person.id,
            startDate: DateTime(year, 1),
            endDate: DateTime(year, 12),
            createdAt: DateTime(year),
          ),
      ],
      [
        for (var i = 0; i < 12; i++)
          {
            'id': 'f$i',
            'date': DateTime(i < 4 ? 2025 : 2026, 9, i + 1).toIso8601String(),
            'seasonId': i < 4 ? 's2025' : 's2026',
            'playerTeamId': person.teamId,
            'playerTeamLeagueId': person.leagueId,
            'oppositeTeamId': 'opponent',
            'oppositeTeamLeagueId': person.leagueId,
            'tournamentId': i % 3 == 0 ? 'cup' : 'league',
            'location': ['home', 'away', 'neutral'][i % 3],
            'playerTeamScore': i % 4,
            'oppositeTeamScore': i % 3,
            'stage': i % 3 == 0 ? 'Quartas de final' : 'Rodada ${i + 1}',
            'isFavorite': i == 11 ? 1 : 0,
            if (i == 11) ...{
              'playerTeamScore': 2,
              'oppositeTeamScore': 2,
              'playerTeamPenaltiesScore': 5,
              'oppositeTeamPenaltiesScore': 4,
            },
          },
      ],
      const {'f11': 1},
      catalog,
      const {'league': 'Brasileirão', 'cup': 'Copa do Brasil'},
      const {},
    );
  });

  Widget app(Widget home, {GlobalKey? captureKey, ThemeData? theme}) =>
      RepaintBoundary(
        key: captureKey,
        child: EasyLocalization(
          supportedLocales: const [Locale('pt', 'BR')],
          startLocale: const Locale('pt', 'BR'),
          fallbackLocale: const Locale('pt', 'BR'),
          path: 'assets/translations',
          assetLoader: _PortugueseLoader(translations),
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: (theme ?? managerDarkTheme).copyWith(
                splashFactory: NoSplash.splashFactory,
              ),
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: home,
            ),
          ),
        ),
      );

  void viewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  String count(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('fixture-count'))).data!;

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    final directory = Platform.environment['PROFILE_PREVIEW_DIR'];
    if (directory == null) return;
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/clubLogos/sao-paulo.png'),
        key.currentContext!,
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, 2000),
      );
      await tester.pumpAndSettle();
    }
    await Scrollable.ensureVisible(tester.element(finder), alignment: .3);
    await tester.pumpAndSettle();
    for (var i = 0; i < 5 && finder.hitTestable().evaluate().isEmpty; i++) {
      final vertical = find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
          )
          .last;
      await tester.drag(
        vertical,
        Offset(0, tester.getCenter(finder).dy < 140 ? 180 : -180),
      );
      await tester.pumpAndSettle();
    }
    expect(finder.hitTestable(), findsOneWidget);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(360, 640), const Size(390, 844)]) {
    testWidgets(
      'fixtures tabs isolate the summary and one filtered chart $size',
      (tester) async {
        viewport(tester, size);
        final key = GlobalKey();
        await tester.pumpWidget(
          app(
            FixturesPage(person: person, load: (_) async => source),
            captureKey: key,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(FixturesInsights), findsNothing);
        await tapVisible(
          tester,
          find.byKey(const ValueKey('fixtures-section-summary')),
        );
        expect(find.byType(FixtureHomeMatchCard), findsNothing);
        expect(find.byType(AnalyticsPanel), findsOneWidget);
        expect(find.byType(AnalyticsEvolutionChart), findsNothing);
        expect(find.text('8 partidas no recorte selecionado.'), findsOneWidget);
        await tester.ensureVisible(find.byType(AnalyticsPanel));
        await tester.pumpAndSettle();
        await capture(tester, key, 'fixtures-summary-${size.width.toInt()}');
        await tapVisible(
          tester,
          find.byKey(const ValueKey('fixtures-section-charts')),
        );
        expect(
          tester
              .widget<AnalyticsEvolutionChart>(
                find.byType(AnalyticsEvolutionChart),
              )
              .data
              .played,
          8,
        );
        await tester.ensureVisible(find.byType(AnalyticsPanel));
        await tester.pumpAndSettle();
        await capture(tester, key, 'fixtures-chart-${size.width.toInt()}');
        await tapVisible(tester, find.byKey(const ValueKey('fixtures-chart')));
        await tester.tap(find.text('Distribuição de resultados').last);
        await tester.pumpAndSettle();
        expect(find.byType(AnalyticsResultsChart), findsOneWidget);
        expect(find.byType(AnalyticsEvolutionChart), findsNothing);
        expect(find.byType(AnalyticsPanel), findsOneWidget);
        await capture(tester, key, 'fixtures-results-${size.width.toInt()}');
        await tapVisible(tester, find.byKey(const ValueKey('fixtures-chart')));
        await tester.tap(find.text('Dentro e fora de casa').last);
        await tester.pumpAndSettle();
        expect(find.byType(AnalyticsBars), findsOneWidget);
        expect(find.byType(AnalyticsResultsChart), findsNothing);
        await tapVisible(tester, find.widgetWithText(TextButton, 'Filtros'));
        final filters = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(DropdownButtonFormField<String>),
        );
        await tester.tap(filters.first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copa do Brasil').last);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
        await tester.pumpAndSettle();
        final bars = tester.widget<AnalyticsBars>(find.byType(AnalyticsBars));
        expect(bars.groups.values.fold(0, (sum, data) => sum + data.played), 2);
        await tapVisible(
          tester,
          find.byKey(const ValueKey('fixtures-section-summary')),
        );
        expect(find.text('2 partidas no recorte selecionado.'), findsOneWidget);
        expect(find.byType(AnalyticsBars), findsNothing);
        await tapVisible(
          tester,
          find.byKey(const ValueKey('fixtures-section-games')),
        );
        expect(find.byType(FixturesInsights), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'player profile scrolls through season and summary statistics $size',
      (tester) async {
        viewport(tester, size);
        final profile = PlayerProfileData(
          seasons: source.seasons,
          matches: [
            for (final (i, row) in source.rows.indexed)
              PlayerMatchData({
                ...row,
                'id': 'performance-$i',
                'fixtureId': row['id'],
                'personId': person.id,
                'playerInstanceId': 'p1',
                'goalsCount': i % 3 == 0 ? 1 : 0,
                'assistsCount': i % 3 == 1 ? 1 : 0,
                'avgRating': i % 4 == 0 ? null : 6.5 + (i % 4) * .5,
                'goalDetails': jsonEncode([
                  if (i % 3 == 0) {'minute': 25 + i, 'assistPlayerId': 'p2'},
                ]),
                'assistDetails': jsonEncode([
                  if (i % 3 == 1) {'minute': 60 + i},
                ]),
              }),
          ],
          overalls: const [
            {'overall': 82, 'date': '2026-06-01'},
            {'overall': 78, 'date': '2025-01-01'},
          ],
          marketValues: const [],
          contracts: const [],
          tournamentNames: source.tournaments,
        );
        final key = GlobalKey();
        await tester.pumpWidget(
          app(
            ViewPlayerPage(
              person: person,
              row: const {
                'id': 'tp1',
                'playerId': 'p1',
                'seasonId': 's2026',
                'customName': 'Lucas Ferreira',
                'customPositionId': '25',
                'customPotential': 88,
                'overall': 82,
                'shirtNumber': 9,
                'isBench': 0,
              },
              profileData: Future.value(profile),
              summarySource: PlayerSummarySource(
                fixtures: source.rows,
                names: const {'p1': 'Lucas Ferreira', 'p2': 'Rafael Silva'},
              ),
            ),
            captureKey: key,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Lucas Ferreira'), findsOneWidget);
        Future<void> scrollTo(Finder target, {double step = 240}) async {
          final vertical = find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .last;
          for (
            var i = 0;
            i < 40 && target.hitTestable().evaluate().isEmpty;
            i++
          ) {
            await tester.drag(vertical, Offset(0, -step));
            await tester.pumpAndSettle();
          }
          expect(target.hitTestable(), findsOneWidget);
        }

        await capture(tester, key, 'player-profile-${size.width.toInt()}');
        await tester.tap(find.byType(Tab).at(1));
        await tester.pumpAndSettle();
        await scrollTo(find.text('Nota mês a mês'));
        expect(
          find.byKey(const ValueKey('player-season-section')),
          findsNothing,
        );
        await scrollTo(find.text('Ataque'));
        expect(find.text("POR 90'"), findsWidgets);
        await capture(tester, key, 'player-attack-${size.width.toInt()}');
        await scrollTo(find.text('Criação'));
        expect(find.text('Passes-chave'), findsNothing);
        await tester.tap(find.byType(Tab).at(2));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerPerformanceOverview), findsOneWidget);
        await capture(tester, key, 'player-summary-${size.width.toInt()}');
        expect(
          find.descendant(
            of: find.byType(PlayerSummaryTab),
            matching: find.byType(DropdownButtonFormField<String>),
          ),
          findsNothing,
        );
        await scrollTo(find.text('Evolução em campo'));
        expect(find.byType(PlayerPerformanceTrend), findsOneWidget);
        final contributions = find.byKey(
          const ValueKey('player-trend-contributions'),
        );
        await scrollTo(contributions);
        await tester.tap(contributions);
        await tester.pumpAndSettle();
        var chart = tester.widget<CareerTrendChart>(
          find.byType(CareerTrendChart),
        );
        expect(chart.points.length, 12);
        expect(chart.otherLabel, 'Assistências');
        await tester.ensureVisible(find.byType(CareerTrendChart));
        await tester.pumpAndSettle();
        await capture(tester, key, 'player-evolution-${size.width.toInt()}');
        final minutes = find.byKey(const ValueKey('player-trend-minutes'));
        await scrollTo(minutes, step: -120);
        await tester.tap(minutes);
        await tester.pumpAndSettle();
        expect(
          tester.widget<CareerTrendChart>(find.byType(CareerTrendChart)).label,
          'Minutos',
        );
        final summarySeason = find.descendant(
          of: find.byType(PlayerSummaryTab),
          matching: find.byType(DropdownButton<String>),
        );
        await scrollTo(summarySeason, step: -240);
        await tester.tap(summarySeason);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Temporada 2025').last);
        await tester.pumpAndSettle();
        await scrollTo(find.text('Evolução em campo'));
        chart = tester.widget<CareerTrendChart>(find.byType(CareerTrendChart));
        expect(chart.points.length, 4);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'match hub changes views, intersects filters and seasons $size',
      (tester) async {
        viewport(tester, size);
        final key = GlobalKey();
        await tester.pumpWidget(
          app(
            RootDrawerScope(
              openDrawer: () {},
              child: FixturesPage(person: person, load: (_) async => source),
            ),
            captureKey: key,
          ),
        );
        await tester.pumpAndSettle();
        expect(count(tester), '8');
        expect(find.text('Temporada 2026'), findsOneWidget);
        final summary = find.byKey(const ValueKey('fixtures-home-summary'));
        final collapsedHeight = tester.getSize(summary).height;
        expect(collapsedHeight, lessThan(155));
        expect(find.text('Últimos jogos'), findsNothing);
        expect(find.byKey(const ValueKey('view-grid')), findsNothing);
        await tapVisible(
          tester,
          find.byKey(const ValueKey('fixtures-summary-expand')),
        );
        expect(
          tester.getSize(summary).height,
          greaterThan(collapsedHeight + 120),
        );
        expect(find.text('Últimos jogos'), findsOneWidget);
        await tapVisible(
          tester,
          find.byKey(const ValueKey('fixtures-summary-collapse')),
        );
        expect(tester.getSize(summary).height, collapsedHeight);
        expect(tester.takeException(), isNull);
        await capture(tester, key, 'fixtures-top-${size.width.toInt()}');
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
        await tester.pumpAndSettle();
        expect(find.text('5–4 pên.'), findsOneWidget);
        await capture(tester, key, 'fixtures-games-${size.width.toInt()}');
        await tapVisible(tester, find.byKey(const ValueKey('view-calendar')));
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -310));
        await tester.pumpAndSettle();
        expect(find.text('setembro 2026'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('calendar-day-2026-09-12')),
          findsOneWidget,
        );
        expect(find.byType(FixtureHomeMatchCard), findsOneWidget);
        expect(
          tester
              .widget<FixtureHomeMatchCard>(find.byType(FixtureHomeMatchCard))
              .fixture['id'],
          'f11',
        );
        await tapVisible(
          tester,
          find.byKey(const ValueKey('calendar-day-2026-09-07')),
        );
        expect(
          tester
              .widget<FixtureHomeMatchCard>(find.byType(FixtureHomeMatchCard))
              .fixture['id'],
          'f6',
        );
        await tapVisible(
          tester,
          find.byKey(const ValueKey('fixtures-summary-expand')),
        );
        await tapVisible(
          tester,
          find.byKey(const ValueKey('fixtures-summary-collapse')),
        );
        expect(
          tester
              .widget<FixtureHomeMatchCard>(find.byType(FixtureHomeMatchCard))
              .fixture['id'],
          'f6',
        );
        await capture(tester, key, 'fixtures-calendar-${size.width.toInt()}');
        await tapVisible(tester, find.byKey(const ValueKey('view-list')));
        await tapVisible(tester, find.widgetWithText(TextButton, 'Filtros'));
        await capture(tester, key, 'fixtures-filters-${size.width.toInt()}');
        await tester.tap(find.byType(DropdownButtonFormField<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Brasileirão').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<String>).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Fora de casa').last);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
        await tester.pumpAndSettle();
        expect(count(tester), '3');
        await tapVisible(tester, find.byKey(const ValueKey('fixture-season')));
        await capture(tester, key, 'fixtures-seasons-${size.width.toInt()}');
        await tester.tap(find.text('Todas as Temporadas').last);
        await tester.pumpAndSettle();
        expect(count(tester), '12');
        await tapVisible(tester, find.byKey(const ValueKey('fixture-season')));
        await tester.tap(find.text('2025').last);
        await tester.pumpAndSettle();
        expect(count(tester), '4');
        expect(find.text('Temporada 2025'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('menu navigation and fixed footer remain accessible $size', (
      tester,
    ) async {
      viewport(tester, size);
      var settings = 0, mode = 0, career = 0;
      DrawerItem? selected;
      final key = GlobalKey(), scaffold = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(
        app(
          Scaffold(
            key: scaffold,
            drawer: DrawerWidget(
              person: person,
              items: managerCareerMenuItems(person),
              selected: 'fixtures',
              onSelect: (item) => selected = item,
              onChangeCareer: () => career++,
              onSwapMode: () => mode++,
              onOpenSettings: () => settings++,
              version: '0.7.0',
            ),
            body: RootDrawerScope(
              openDrawer: () => scaffold.currentState!.openDrawer(),
              child: FixturesPage(person: person, load: (_) async => source),
            ),
          ),
          captureKey: key,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Central do elenco'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('menu-fixtures')))
            .selected,
        isTrue,
      );
      await capture(tester, key, 'menu-top-${size.width.toInt()}');
      await tester.tap(find.text('Trocar Treinador'));
      await tester.tap(find.byTooltip('Configurações'));
      await tester.tap(find.text('Mudar modo'));
      expect([career, settings, mode], [1, 1, 1]);
      await tapVisible(tester, find.byKey(const ValueKey('menu-myManager')));
      expect(selected?.id, 'myManager');
      await tapVisible(
        tester,
        find.byKey(const ValueKey('menu-teamAnalytics')),
      );
      expect(selected?.id, 'teamAnalytics');
      await capture(tester, key, 'menu-career-${size.width.toInt()}');
      await tapVisible(tester, find.byKey(const ValueKey('menu-streaks')));
      expect(selected?.id, 'streaks');
      expect(find.widgetWithText(ExpansionTile, 'Mais'), findsNothing);
      expect(find.byKey(const ValueKey('menu-headToHead')), findsNothing);
      expect(find.text('FC Career Live · v0.7.0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final dark in [true, false]) {
    testWidgets(
      'player hub and menu retain season selection in ${dark ? 'dark' : 'light'} theme',
      (tester) async {
        viewport(tester, const Size(360, 640));
        final player = Person.fromMap({
          ...person.toMap(),
          'category': 'player',
        });
        final key = GlobalKey(), scaffold = GlobalKey<ScaffoldState>();
        await tester.pumpWidget(
          app(
            Scaffold(
              key: scaffold,
              drawer: DrawerWidget(
                person: player,
                items: playerCareerMenuItems(player),
                selected: 'fixtures',
                onSelect: (_) {},
                onChangeCareer: () {},
                onSwapMode: () {},
                version: '0.7.0',
              ),
              body: RootDrawerScope(
                openDrawer: () => scaffold.currentState!.openDrawer(),
                child: FixturesPage(person: player, load: (_) async => source),
              ),
            ),
            captureKey: key,
            theme: dark ? playerDarkTheme : playerLightTheme,
          ),
        );
        await tester.pumpAndSettle();
        expect(count(tester), '12');
        await capture(
          tester,
          key,
          'fixtures-player-${dark ? 'dark' : 'light'}',
        );
        await tapVisible(tester, find.byKey(const ValueKey('fixture-season')));
        await tester.tap(find.text('2025').last);
        await tester.pumpAndSettle();
        expect(count(tester), '4');
        await tester.tap(find.byTooltip('Menu'));
        await tester.pumpAndSettle();
        expect(find.text('Jogador'), findsOneWidget);
        expect(find.text('X (Rede Social)'), findsOneWidget);
        expect(find.widgetWithText(ExpansionTile, 'Mais'), findsNothing);
        expect(find.byKey(const ValueKey('menu-headToHead')), findsNothing);
        await capture(tester, key, 'menu-player-${dark ? 'dark' : 'light'}');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'light theme shows empty state and retry recovers loading failure',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        app(
          FixturesPage(
            person: person,
            load: (_) async {
              if (attempts++ == 0) throw StateError('offline');
              return FixturesData([], [], {}, source.catalog, {}, {});
            },
          ),
          theme: managerLightTheme,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Não foi possível carregar as partidas.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Sua temporada começa aqui'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Criar temporada'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
