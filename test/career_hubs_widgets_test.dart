import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mcmanager/Common/FixturePlayerPerformancePage.dart';
import 'package:mcmanager/ManagerCareer/PlayersStat/PlayerActivityPage.dart';
import 'package:mcmanager/ManagerCareer/PlayersStat/PlayersStatPage.dart';
import 'package:mcmanager/ManagerCareer/PlayersStat/PlayersStatPageSortModal.dart';
import 'package:mcmanager/ManagerCareer/PlayersStat/PlayersStatData.dart';
import 'package:mcmanager/ManagerCareer/PlayersStat/PlayerStatWidgets.dart';
import 'package:mcmanager/ManagerCareer/TeamCenter/TeamCenterPage.dart';
import 'package:mcmanager/Trophies/Trophies.dart';
import 'package:mcmanager/Trophies/ViewTrophyPage.dart';
import 'package:mcmanager/utils/Components/CompactDashboardWidgets.dart';
import 'package:mcmanager/utils/Components/CareerInsightWidgets.dart';
import 'package:mcmanager/utils/AppColors.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'career_hub_fixture.dart';
import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';

class _HubTranslations extends AssetLoader {
  const _HubTranslations(this.values);
  final Map<String, dynamic> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late SqlService sql;
  late Map<String, dynamic> translations;
  final capture = GlobalKey(), person = reviewPerson();
  setUpAll(() async {
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory('build/career-hub-widget-docs').absolute.path,
        );
    await EasyLocalization.ensureInitialized();
    translations = jsonDecode(
      await rootBundle.loadString('assets/translations/pt_BR.json'),
    ) as Map<String, dynamic>;
    await GameCatalog.load();
    await loadPreviewFonts();
  });
  setUp(() async {
    db = await createHubFixture();
    sql = SqlService.withDatabase(db);
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester,
    Widget home, {
    bool dark = true,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('pt', 'BR')],
        startLocale: const Locale('pt', 'BR'),
        path: 'assets/translations',
        assetLoader: _HubTranslations(translations),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? managerDarkTheme : managerLightTheme,
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
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
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(seconds: 11));
    }
  }

  Future<void> preview(WidgetTester tester, String name) async {
    final directory = Platform.environment['CAREER_HUB_PREVIEW_DIR'];
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

  List<String> tooltips(WidgetTester tester) {
    final chart = tester.widget<LineChart>(find.byType(LineChart)).data;
    return [
      for (final indicator in chart.showingTooltipIndicators)
        for (final item in chart.lineTouchData.touchTooltipData.getTooltipItems(
          indicator.showingSpots,
        ))
          TextSpan(text: item!.text, children: item.children).toPlainText(),
    ];
  }

  testWidgets('Shared trend chart keeps a tooltip on the touched point', (
    tester,
  ) async {
    await mount(
      tester,
      const Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: CareerTrendChart(
              label: 'Nota',
              maxY: 10,
              points: [CareerTrendPoint('01/06', 7, detail: 'Adversário')],
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(LineChart));
    await tester.tapAt(
      Offset(
        rect.left + 30 + (rect.width - 30) / 2,
        rect.top + (rect.height - 34) * .3,
      ),
    );
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tooltips(tester), ['Adversário · 01/06\n7  Nota']);
    await tester.tapAt(Offset(rect.left + 34, rect.top + 10));
    await settle(tester);
    expect(tooltips(tester), isEmpty);
    await unmount(tester);
  });

  for (final dark in [true, false]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets(
      'Trophies expand by competition/year and open a campaign summary ($theme)',
      (tester) async {
        await mount(
          tester,
          TrophiesPage(person: person, sql: sql),
          dark: dark,
        );
        final cup = find.byKey(const PageStorageKey('trophy-group-cup'));
        await tester.ensureVisible(cup);
        await tester.tap(cup);
        await settle(tester);
        expect(find.text('2028'), findsOneWidget);
        expect(find.text('2027'), findsOneWidget);
        await preview(tester, 'trophies-$theme');
        final edition = find.byKey(
          const ValueKey('trophy-edition-auto:s2028:cup'),
        );
        await tester.ensureVisible(edition);
        await tester.tap(edition);
        await settle(tester);
        expect(find.byType(ViewTrophyPage), findsOneWidget);
        expect(find.text('Quem mais marcou'), findsOneWidget);
        await preview(tester, 'trophy-summary-$theme');
        await tester.tap(find.widgetWithText(Tab, 'Partidas'));
        await settle(tester);
        expect(find.byType(RecordedFixtureTile), findsNWidgets(2));
        expect(find.text('Conquista'), findsNothing);
        expect(tester.takeException(), isNull);
        await preview(tester, 'trophy-journey-$theme');
        await unmount(tester);
      },
    );
    testWidgets(
      'Statistics use player cards and open filtered activity plus the full match report ($theme)',
      (tester) async {
        await mount(
          tester,
          PlayersStatPage(person: person, sql: sql),
          dark: dark,
        );
        double top(String id) =>
            tester.getTopLeft(find.byKey(ValueKey('player-stat-$id'))).dy;
        await tester.tap(find.byKey(const ValueKey('stat-group-defense')));
        await settle(tester);
        expect(find.byKey(const ValueKey('stat-column-saves')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('stat-column-saves')));
        await settle(tester);
        expect(top('p2'), lessThan(top('p1')));
        await tester.tap(find.byKey(const ValueKey('stat-group-summary')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('stat-column-goals')));
        await settle(tester);
        expect(top('p1'), lessThan(top('p2')));
        await tester.enterText(find.byType(TextField), 'Arthur');
        await settle(tester);
        final card = find.byKey(const ValueKey('player-stat-p1'));
        expect(card, findsOneWidget);
        expect(find.byType(DataTable), findsNothing);
        await preview(tester, 'player-statistics-$theme');
        await tester.tap(card);
        await settle(tester);
        expect(find.byType(PlayerActivityPage), findsOneWidget);
        expect(find.text('Qualidade dos registros'), findsNothing);
        await preview(tester, 'player-activity-$theme');
        final chart = find.byType(LineChart);
        await tester.ensureVisible(chart);
        await settle(tester);
        final plot = tester.getRect(chart);
        await tester.tapAt(
          Offset(plot.right - 2, plot.top + (plot.height - 34) * .3),
        );
        await settle(tester);
        expect(find.byType(BottomSheet), findsNothing);
        expect(tooltips(tester).single, contains('7,0  Nota'));
        await preview(tester, 'player-chart-tooltip-$theme');
        await tester.tap(find.widgetWithText(Tab, 'Estatísticas'));
        await settle(tester);
        expect(find.text('Minutos'), findsOneWidget);
        await preview(tester, 'player-details-$theme');
        final yellow = find.byKey(const ValueKey('stat-help-yellowCards'));
        await tester.scrollUntilVisible(
          yellow,
          250,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('player-activity-statistics')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(
          find.descendant(of: yellow, matching: find.byType(PlayerMetricIcon)),
          findsOneWidget,
        );
        expect(find.text('Cartões amarelos'), findsOneWidget);
        await tester.tap(yellow);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          find.text('Cartões amarelos\nTotal nas atuações do recorte.'),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 200));
        await preview(tester, 'player-stat-tooltip-$theme');
        await settle(tester);
        await tester.tap(find.widgetWithText(Tab, 'Partidas'));
        await settle(tester);
        final match = find.byWidgetPredicate(
          (w) => '${w.key}'.contains("player-match-"),
        );
        expect(match, findsWidgets);
        await preview(tester, 'player-matches-$theme');
        await tester.tap(match.first);
        await settle(tester);
        expect(find.byType(FixturePlayerPerformancePage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await unmount(tester);
      },
    );
    testWidgets(
      'Sort selection is readable, searchable and keeps actions above the keyboard ($theme)',
      (tester) async {
        PlayersStatSort? selected;
        await mount(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async => selected = await showPlayersStatSort(
                  context,
                  const PlayersStatSort(),
                ),
                child: const Text('Ordenar'),
              ),
            ),
          ),
          dark: dark,
          width: 320,
          scale: 1.35,
        );
        await tester.tap(find.text('Ordenar'));
        await settle(tester);
        final direction = tester.widget<FilledButton>(
          find.byKey(const ValueKey('sort-direction-true')),
        );
        final foreground = direction.style!.foregroundColor!.resolve({})!;
        final background = direction.style!.backgroundColor!.resolve({})!;
        final light = foreground.computeLuminance(),
            shade = background.computeLuminance();
        final contrast = (light > shade
            ? (light + .05) / (shade + .05)
            : (shade + .05) / (light + .05));
        expect(contrast, greaterThan(4.5));
        final position = find.byKey(const ValueKey('sort-metric-position'));
        final text = tester.widget<Text>(
          find.descendant(of: position, matching: find.text('Posição')),
        );
        expect(
          text.style!.color,
          dark ? AppColors.dark.accent : AppColors.light.accent,
        );
        await preview(tester, 'player-sort-$theme');
        await tester.tap(find.byKey(const ValueKey('sort-direction-false')));
        await tester.enterText(find.byType(TextField), 'gols');
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('sort-metric-goals')));
        expect(
          tester.getRect(find.text('Aplicar')).bottom,
          lessThan(844 - 260),
        );
        expect(tester.takeException(), isNull);
        await preview(tester, 'player-sort-keyboard-$theme');
        await tester.tap(find.text('Aplicar'));
        await settle(tester);
        expect(selected!.metric, PlayersStatMetric.goals);
        expect(selected!.descending, isFalse);
        await unmount(tester);
      },
    );
    testWidgets(
      'Squad hub shows one currently injured roster player and useful actions ($theme)',
      (tester) async {
        await mount(
          tester,
          TeamCenterPage(person: person, sql: sql),
          dark: dark,
        );
        expect(find.text('Disponíveis'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        await preview(tester, 'squad-hub-$theme');
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('active-injury-p1')),
          250,
        );
        expect(find.byKey(const ValueKey('active-injury-p2')), findsNothing);
        expect(find.byKey(const ValueKey('active-injury-p3')), findsNothing);
        await preview(tester, 'squad-injuries-$theme');
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('season-leader-goals')),
          250,
        );
        expect(find.text('Destaques da temporada'), findsOneWidget);
        expect(find.text('ARTILHARIA'), findsOneWidget);
        await preview(tester, 'squad-highlights-$theme');
        expect(tester.takeException(), isNull);
        await unmount(tester);
      },
    );
  }
  testWidgets('All three dashboards remain usable at 320px with large text', (
    tester,
  ) async {
    for (final page in [
      TrophiesPage(person: person, sql: sql),
      PlayersStatPage(person: person, sql: sql),
      TeamCenterPage(person: person, sql: sql),
    ]) {
      await mount(tester, page, width: 320, scale: 1.35);
      expect(find.textContaining('Não foi possível carregar'), findsNothing);
      expect(tester.takeException(), isNull);
      await preview(tester, 'narrow-${page.runtimeType}');
      if (page is PlayersStatPage) {
        await tester.tap(find.byKey(const ValueKey('player-stat-p1')));
        await settle(tester);
        await preview(tester, 'narrow-player-activity');
        expect(tester.takeException(), isNull);
        await tester.tap(find.widgetWithText(Tab, 'Estatísticas'));
        await settle(tester);
        await preview(tester, 'narrow-player-details');
        expect(tester.takeException(), isNull);
      }
      await unmount(tester);
    }
  });
}
