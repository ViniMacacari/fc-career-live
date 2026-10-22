import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Common/SelectTeam/SelectTeamPage.dart';
import 'package:mcmanager/ManagerCareer/Fixtures/ManagerFixtureForm.dart';
import 'package:mcmanager/ManagerCareer/Fixtures/SelectPlayerOfMatchSheet.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> translations;
  late GameCatalog catalog;
  final names = <String, String>{
    'samuel': 'Samuel Guimarães',
    'marcos': 'Marcos Antônio',
    'domingos': 'Domingos Duarte',
    'lucas': 'Lucas Moura',
  };
  final positions = <String, String>{
    'samuel': 'ATA',
    'marcos': 'VOL',
    'domingos': 'ZAG',
    'lucas': 'PD',
  };
  final players = {
    for (final (i, name) in names.entries.indexed)
      name.key: <String, Object?>{
        'id': name.key,
        'name': name.value,
        'positionId': i == 0
            ? '25'
            : i == 1
            ? '10'
            : i == 2
            ? '5'
            : '23',
        'overall': 83 - i,
        'shirtNumber': [20, 8, 4, 7][i],
      },
  };
  final performances = [
    for (final (i, entry) in names.entries.indexed)
      ManagerFixturePlayerPerformance(
        personId: 'career',
        fixtureId: 'f0',
        playerInstanceId: entry.key,
        avgRating: i == 3 ? null : [8.4, 7.2, 7.3][i],
        goalsCount: i == 0 ? 2 : 0,
        assistsCount: i == 1 ? 1 : 0,
      ),
  ];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async =>
              Directory('build/match-selection-test-docs').absolute.path,
        );
    await EasyLocalization.ensureInitialized();
    await loadPreviewFonts();
    translations = jsonDecode(
      await rootBundle.loadString('assets/translations/pt_BR.json'),
    ) as Map<String, dynamic>;
    catalog = await GameCatalog.load();
  });
  Widget app(Widget home, {GlobalKey? capture, double scale = 1}) =>
      RepaintBoundary(
        key: capture,
        child: EasyLocalization(
          supportedLocales: const [Locale('pt', 'BR')],
          startLocale: const Locale('pt', 'BR'),
          path: 'assets/translations',
          assetLoader: _Translations(translations),
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: managerDarkTheme,
              locale: context.locale,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
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
    addTearDown(tester.view.resetViewInsets);
  }

  Future<void> preview(WidgetTester tester, GlobalKey key, String name) async {
    final directory = Platform.environment['MATCH_SELECTION_PREVIEW_DIR'];
    if (directory == null) return;
    await tester.pump();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(seconds: 11));
    }
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(390, 844), const Size(320, 640)]) {
    testWidgets(
      'MOTM search stays focused and preserves current choice at ${size.width}',
      (tester) async {
        viewport(tester, size);
        final capture = GlobalKey();
        String? result;
        await tester.pumpWidget(
          app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  child: const Text('MOTM'),
                  onPressed: () async {
                    result = await showPlayerOfMatchPicker(
                      context,
                      fifaVersion: 'FC26',
                      performances: performances,
                      players: players,
                      names: names,
                      positions: positions,
                      selectedId: 'samuel',
                    );
                  },
                ),
              ),
            ),
            capture: capture,
            scale: size.width == 320 ? 1.3 : 1,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('MOTM'));
        await tester.pumpAndSettle();
        expect(find.text('Samuel Guimarães'), findsOneWidget);
        expect(find.text('8.4'), findsOneWidget);
        expect(find.text('2 gols'), findsOneWidget);
        expect(find.text('#20 · ATA · GER 83'), findsOneWidget);
        expect(find.byIcon(Icons.star_rounded), findsNWidgets(2));
        await preview(tester, capture, 'motm-${size.width.toInt()}');
        final search = find.descendant(
          of: find.byKey(const ValueKey('motm-player-search')),
          matching: find.byType(TextField),
        );
        await tester.tap(search);
        await tester.enterText(search, 'antonio');
        await tester.pumpAndSettle();
        final input = tester.widget<EditableText>(
          find.descendant(of: search, matching: find.byType(EditableText)),
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        await tester.pumpAndSettle();
        expect(input.focusNode.hasFocus, true);
        expect(input.controller.text, 'antonio');
        expect(find.text('Marcos Antônio'), findsOneWidget);
        expect(find.text('Samuel Guimarães'), findsNothing);
        await preview(tester, capture, 'motm-keyboard-${size.width.toInt()}');
        final choice = find.byKey(const ValueKey('motm-player-marcos'));
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(result, 'marcos');
        expect(find.byType(SelectPlayerOfMatchSheet), findsNothing);
        expect(tester.takeException(), isNull);
        await cleanUp(tester);
      },
    );

    testWidgets(
      'Team search shows league, selected club and stable keyboard at ${size.width}',
      (tester) async {
        viewport(tester, size);
        final capture = GlobalKey();
        CatalogItem? result;
        final own = catalog.team('FC26', '40-13', leagueId: '1014')!;
        await tester.pumpWidget(
          app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  child: const Text('Times'),
                  onPressed: () async {
                    result = await Navigator.push<CatalogItem>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SelectTeamPage(
                          fifaVersion: 'FC26',
                          selectedTeamId: '40-13',
                          selectedLeagueId: '1014',
                          initialLeagueId: '1014',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            capture: capture,
            scale: size.width == 320 ? 1.3 : 1,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Times'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ExpansionTile>(find.byType(ExpansionTile).first)
              .initiallyExpanded,
          true,
        );
        await preview(tester, capture, 'team-leagues-${size.width.toInt()}');
        final search = find.descendant(
          of: find.byKey(const ValueKey('team-selection-search')),
          matching: find.byType(TextField),
        );
        await tester.tap(search);
        await tester.enterText(search, 'sao paulo');
        await tester.pumpAndSettle();
        final currentTeam = find.byKey(
          ValueKey('team-choice-${own.leagueId}-${own.id}'),
        );
        expect(currentTeam, findsOneWidget);
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
        final input = tester.widget<EditableText>(
          find.descendant(of: search, matching: find.byType(EditableText)),
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        await tester.pumpAndSettle();
        expect(input.focusNode.hasFocus, true);
        expect(input.controller.text, 'sao paulo');
        await preview(
          tester,
          capture,
          'team-search-keyboard-${size.width.toInt()}',
        );
        await tester.enterText(search, 'does-not-exist');
        await tester.pumpAndSettle();
        expect(find.text('Nenhum time encontrado'), findsOneWidget);
        await tester.tap(find.byTooltip('Limpar busca'));
        await tester.pumpAndSettle();
        expect(find.byType(ExpansionTile), findsWidgets);
        await tester.enterText(search, 'sao paulo');
        await tester.pumpAndSettle();
        await tester.tap(currentTeam);
        await tester.pumpAndSettle();
        expect(result!.id, own.id);
        expect(result!.leagueId, own.leagueId);
        expect(find.byType(SelectTeamPage), findsNothing);
        expect(tester.takeException(), isNull);
        await cleanUp(tester);
      },
    );
  }

  testWidgets('MOTM clear and dismissal have different results', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    String? result = 'unchanged';
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('MOTM'),
              onPressed: () async {
                result = await showPlayerOfMatchPicker(
                  context,
                  fifaVersion: 'FC26',
                  performances: performances,
                  players: players,
                  names: names,
                  positions: positions,
                  selectedId: 'samuel',
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('MOTM'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    await tester.tap(find.text('MOTM'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clear-motm-selection')));
    await tester.pumpAndSettle();
    expect(result, '');
    expect(tester.takeException(), isNull);
    await cleanUp(tester);
  });

  testWidgets(
    'Match form saves selected MOTM and reopens opponent with its current league',
    (tester) async {
      viewport(tester, const Size(390, 844));
      Map<String, Object?>? saved;
      final opponent = catalog
          .teams('FC26')
          .firstWhere((t) => t.leagueId == '1014' && t.id != '40-13');
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Partida'),
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ManagerFixtureForm(
                      person: reviewPerson(),
                      existing: {
                        ...reviewFixture(0),
                        'tournamentId': 'league:1014',
                        'oppositeTeamId': opponent.id,
                        'oppositeTeamLeagueId': opponent.leagueId,
                        'playerOfTheMatchId': 'samuel',
                      },
                      preloaded: (
                        seasons: [reviewSeason()],
                        players: players.values.toList(),
                        roster: [
                          for (final p in players.values)
                            {
                              ...p,
                              'playerId': p['id'],
                              'customName': p['name'],
                              'overall': 60,
                            },
                        ],
                      ),
                      preloadedPerformances: performances,
                      opponentLineupLoader: (_, _) async => null,
                      onFixtureSaved: (value, _) async => saved = value,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Partida'));
      await tester.pumpAndSettle();
      final motm = find.text('Samuel Guimarães').first;
      await tester.ensureVisible(motm);
      await tester.tap(motm);
      await tester.pumpAndSettle();
      expect(find.byType(SelectPlayerOfMatchSheet), findsOneWidget);
      expect(find.text('#20 · ATA · GER 83'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('motm-player-marcos')));
      await tester.pumpAndSettle();
      final opponentField = find.byKey(
        const ValueKey('fixture-opponent-picker'),
      );
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(opponentField);
      await tester.pumpAndSettle();
      final picker = tester.widget<SelectTeamPage>(find.byType(SelectTeamPage));
      expect(picker.selectedTeamId, opponent.id);
      expect(picker.initialLeagueId, opponent.leagueId);
      await tester.tap(
        find.byTooltip(
          MaterialLocalizations.of(tester.element(find.byType(SelectTeamPage)))
              .backButtonTooltip,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Salvar'));
      await tester.pumpAndSettle();
      expect(saved!['playerOfTheMatchId'], 'marcos');
      expect(saved!['isPotmFromMyTeam'], 1);
      expect(saved!['oppositeTeamId'], opponent.id);
      expect(tester.takeException(), isNull);
      await cleanUp(tester);
    },
  );
}
