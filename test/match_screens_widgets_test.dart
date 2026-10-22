import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Common/FixtureDetailsPage.dart';
import 'package:mcmanager/ManagerCareer/Fixtures/ManagerFixtureForm.dart';
import 'package:mcmanager/ManagerCareer/Fixtures/Performances/PerformanceDetails.dart';
import 'package:mcmanager/models/ManagerFixture.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
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

const _names = [
  'Calleri',
  'Luciano',
  'Ferreira',
  'Lucas Moura',
  'Alisson',
  'Pablo Maia',
  'Wendell',
  'Arboleda',
  'Alan Franco',
  'Cédric',
  'Rafael',
  'André Silva',
  'Luan',
  'Jandrei',
];

String _position(int i) => i == 10 || i == 13
    ? '0'
    : i < 3
    ? '25'
    : i < 6
    ? '14'
    : '5';

final _roster = [
  for (var i = 0; i < _names.length; i++)
    {
      'id': 'team-$i',
      'playerId': 'p$i',
      'customName': _names[i],
      'customPositionId': _position(i),
      'shirtNumber': i + 1,
      'overall': 78,
      'isBench': i >= 11 ? 1 : 0,
    },
];
final _players = [
  for (var i = 0; i < _names.length; i++)
    {'id': 'p$i', 'name': _names[i], 'positionId': _position(i)},
];

List<ManagerFixturePlayerPerformance> _performances() => [
  for (var i = 0; i < 11; i++)
    ManagerFixturePlayerPerformance(
      personId: 'career',
      fixtureId: 'match',
      playerInstanceId: 'p$i',
      avgRating: i == 0
          ? 8.9
          : i == 10
          ? 7.1
          : 6.4 + (i % 4) * .4,
      goalDetails: i == 0
          ? [
              PerformanceGoalDetails(
                id: 'first-goal',
                minute: 23,
                assistantId: 'p3',
                assistantName: 'Lucas Moura',
              ),
              PerformanceGoalDetails(
                id: 'second-goal',
                minute: 57,
                type: [GoalType.penalty],
              ),
              PerformanceGoalDetails(id: 'fourth-goal', minute: 89),
            ]
          : i == 1
          ? [PerformanceGoalDetails(id: 'third-goal', minute: 81)]
          : i == 5
          ? [PerformanceGoalDetails(id: 'fifth-goal', minute: 6)]
          : null,
      assistDetails: i == 3
          ? [PerformanceAssistDetails(minute: 23, goalscorerId: 'p0')]
          : i == 0
          ? [PerformanceAssistDetails(minute: 79)]
          : i == 5
          ? [
              PerformanceAssistDetails(minute: 30),
              PerformanceAssistDetails(minute: 60),
            ]
          : null,
      yellowCardDetails: i == 4 || i == 7
          ? [PerformanceTimeDetails(minute: 30 + i * 6)]
          : null,
      substitutionDetails: i == 1
          ? [
              PerformanceSubstitutionDetails(
                id: 'sub',
                minute: 85,
                type: SubstitutionType.outGame,
                anotherPlayerId: 'p11',
              ),
            ]
          : i == 5
          ? [
              PerformanceSubstitutionDetails(
                id: 'sub-5',
                minute: 71,
                type: SubstitutionType.outGame,
              ),
            ]
          : null,
    ),
  ManagerFixturePlayerPerformance(
    personId: 'career',
    fixtureId: 'match',
    playerInstanceId: 'p11',
    avgRating: 6.6,
    substitutionDetails: [
      PerformanceSubstitutionDetails(
        id: 'sub-in',
        minute: 85,
        type: SubstitutionType.inGame,
        anotherPlayerId: 'p1',
      ),
    ],
  ),
];

OpponentLineup _opponentLineup() {
  var lineup = OpponentLineup.empty(formation: '4-2-3-1');
  for (var i = 0; i < 11; i++) {
    lineup = lineup.rename(lineup.startingIds[i], 'Rival ${i + 1}');
  }
  return lineup.addReserve('Reserva rival');
}

Map<String, Object?> _fixture() => {
  ...reviewFixture(1),
  'id': 'match',
  'location': 'home',
  'playerTeamScore': 3,
  'oppositeTeamScore': 1,
  'stage': 'Rodada 16',
  'teamPossession': 56.4,
  'passAccuracy': 84.0,
  'playerTeamShoutsCount': 15,
  'opponentTeamShotsCount': 9,
  'position': 3,
  'playerOfTheMatchId': 'p0',
  'captaincy': jsonEncode({'initialPlayerId': 'p7'}),
  'notes':
      'Jogo controlado do início ao fim, com pressão alta e '
      'boa saída de bola pelos lados.',
  'opponentStats': jsonEncode({
    'passAccuracy': 78.5,
    'yellowCards': 2,
    'injuries': 1,
    'position': 6,
  }),
  'opponentGoalDetails': encodeOpponentGoals([
    OpponentGoalDetails(scorerName: 'Rival 9', minute: 71),
  ]),
  'opponentLineup': _opponentLineup().encode(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> translations;
  final capture = GlobalKey();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory('build/match-screens-docs').absolute.path,
        );
    await EasyLocalization.ensureInitialized();
    translations = jsonDecode(
      await rootBundle.loadString('assets/translations/pt_BR.json'),
    ) as Map<String, dynamic>;
    await loadPreviewFonts();
    await GameCatalog.load();
  });

  Future<void> mount(
    WidgetTester tester,
    Widget home, {
    bool dark = true,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('pt', 'BR')],
        startLocale: const Locale('pt', 'BR'),
        fallbackLocale: const Locale('pt', 'BR'),
        path: 'assets/translations',
        assetLoader: _Translations(translations),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? managerDarkTheme : managerLightTheme,
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
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
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> preview(WidgetTester tester, String name) async {
    final directory = Platform.environment['MATCH_PREVIEW_DIR'];
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

  Widget details() => FixtureDetailsPage(
    person: reviewPerson(),
    fixture: _fixture(),
    opponent: 'Flamengo',
    tournament: 'Brasileirão Série A',
    tablePosition: Future.value(
      const FixtureTablePosition(position: 3, previous: 5),
    ),
    lineupData: Future.value(
      FixtureLineupData(
        _roster,
        _performances(),
        {for (var i = 0; i < _names.length; i++) 'p$i': _names[i]},
        {
          for (var i = 0; i < _names.length; i++)
            'p$i': const {
              '25': 'ATA',
              '14': 'MC',
              '5': 'ZAG',
              '0': 'GOL',
            }[_position(i)]!,
        },
        positionIds: {
          for (var i = 0; i < _names.length; i++) 'p$i': _position(i),
        },
      ),
    ),
    onFormationSaved: (_) async {},
  );

  Widget form() => ManagerFixtureForm(
    person: reviewPerson(),
    existing: _fixture(),
    preloaded: (seasons: [reviewSeason()], players: _players, roster: _roster),
    preloadedPerformances: _performances(),
    onFixtureSaved: (_, _) async {},
  );

  for (final dark in [true, false]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('Match tabs read cleanly ($theme)', (tester) async {
      await mount(tester, details(), dark: dark, size: const Size(390, 2400));
      await preview(tester, 'details-principal-$theme');
      await tester.tap(find.widgetWithText(Tab, 'Linha do Tempo'));
      await tester.pumpAndSettle();
      await preview(tester, 'details-timeline-$theme');
      await mount(tester, details(), dark: dark, size: const Size(390, 1500));
      await tester.tap(find.widgetWithText(Tab, 'Formação'));
      await tester.pumpAndSettle();
      await preview(tester, 'details-formation-$theme');
      await tester.tap(find.byKey(const ValueKey('formation-team-opponent')));
      await tester.pumpAndSettle();
      await preview(tester, 'details-opponent-$theme');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Match form keeps every field reachable ($theme)', (
      tester,
    ) async {
      await mount(tester, form(), dark: dark, size: const Size(390, 3200));
      await preview(tester, 'form-$theme');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('The main tab shows the lineup on the pitch', (tester) async {
    await mount(tester, details());
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('fixture-pitch-player-p0')).hitTestable(),
      find.byKey(const PageStorageKey('fixture-principal')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await preview(tester, 'principal-pitch');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('principal-formation')),
        matching: find.byKey(const ValueKey('fixture-captaincy')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Player performance editor', (tester) async {
    await mount(
      tester,
      PerformanceDetails(
        person: reviewPerson(),
        performance: _performances().first,
        isNew: false,
        roster: _roster,
        names: {for (var i = 0; i < _names.length; i++) 'p$i': _names[i]},
        positions: {
          for (var i = 0; i < _names.length; i++) 'p$i': _position(i),
        },
      ),
      size: const Size(390, 1800),
    );
    await preview(tester, 'performance-editor');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Match screens fit 320px with larger text', (tester) async {
    await mount(tester, details(), size: const Size(320, 2400), scale: 1.3);
    await preview(tester, 'narrow-details');
    expect(find.byKey(const ValueKey('principal-formation')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await mount(tester, form(), size: const Size(320, 3400), scale: 1.3);
    await preview(tester, 'narrow-form');
    final busy = tester.getRect(
      find.byKey(const ValueKey('performance-row-p0')),
    );
    final calm = tester.getRect(
      find.byKey(const ValueKey('performance-row-p2')),
    );
    expect(busy.height, closeTo(calm.height, .01));
    expect(
      tester.getRect(find.text('8.9')).right,
      closeTo(tester.getRect(find.text('7.2').first).right, 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('The editor reopens the lineup on the last chosen view', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    await mount(tester, form(), size: const Size(390, 3200));
    expect(find.byKey(const ValueKey('edit-own-formation')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('lineup-view-formation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-own-formation')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await mount(tester, form(), size: const Size(390, 3200));
    expect(find.byKey(const ValueKey('edit-own-formation')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lineup-view-list')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await mount(tester, form(), size: const Size(390, 3200));
    expect(find.byKey(const ValueKey('edit-own-formation')), findsNothing);
    expect(find.byKey(const ValueKey('performance-row-p0')), findsOneWidget);
  });

  testWidgets('An opponent man of the match keeps rating and photo', (
    tester,
  ) async {
    var lineup = _opponentLineup();
    final id = lineup.startingIds[9];
    lineup = lineup.rename(id, 'Almoez Ali');
    lineup = OpponentLineup(
      squad: lineup.squad,
      performances: [
        ManagerFixturePlayerPerformance(
          personId: 'career',
          fixtureId: 'match',
          playerInstanceId: id,
          avgRating: 8.5,
        ),
      ],
    );
    await mount(
      tester,
      FixtureDetailsPage(
        person: reviewPerson(),
        fixture: {
          ..._fixture(),
          'playerOfTheMatchId': 'Almoez Ali',
          'isPotmFromMyTeam': 0,
          'opponentLineup': lineup.encode(),
        },
        opponent: 'Santos',
        tournament: 'Campeonato Paulista',
        tablePosition: Future.value(
          const FixtureTablePosition(position: 3, previous: 5),
        ),
        lineupData: Future.value(
          FixtureLineupData(
            _roster,
            _performances(),
            {for (var i = 0; i < _names.length; i++) 'p$i': _names[i]},
            const {},
            opponentLineup: lineup,
          ),
        ),
        onFormationSaved: (_) async {},
      ),
      size: const Size(390, 2400),
    );
    final row = find.byKey(ValueKey('fixture-highlight-$id'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('8.5')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Almoez Ali')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Editing on the pitch offers icon actions and quick goals', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    List<ManagerFixturePlayerPerformance>? saved;
    await mount(
      tester,
      ManagerFixtureForm(
        person: reviewPerson(),
        existing: _fixture(),
        preloaded: (
          seasons: [reviewSeason()],
          players: _players,
          roster: _roster,
        ),
        preloadedPerformances: _performances(),
        onFixtureSaved: (_, performances) async => saved = performances,
      ),
      size: const Size(390, 3200),
    );
    await tester.tap(find.byKey(const ValueKey('lineup-view-formation')));
    await tester.pumpAndSettle();
    final player = find.byKey(const ValueKey('pitch-name-p1'));
    await tester.ensureVisible(player);
    await tester.tap(player);
    await tester.pumpAndSettle();
    for (final action in [
      'goal',
      'assist',
      'substitutionOut',
      'yellowCard',
      'redCard',
      'view',
      'replace',
      'bench',
    ]) {
      expect(
        find.byKey(ValueKey('pitch-action-$action')),
        findsOneWidget,
        reason: action,
      );
    }
    expect(find.text('Trocar jogador'), findsNothing);
    await preview(tester, 'pitch-actions');
    await tester.tap(find.byKey(const ValueKey('pitch-action-goal')));
    await tester.pumpAndSettle();
    expect(find.byType(PerformanceDetails), findsOneWidget);
    await tester.tap(find.text('common.ok'.tr()));
    await tester.pumpAndSettle();
    expect(find.byType(PerformanceDetails), findsNothing);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final before = _performances()
        .firstWhere((p) => p.playerInstanceId == 'p1')
        .goalDetails
        .length;
    expect(
      saved!.firstWhere((p) => p.playerInstanceId == 'p1').goalDetails.length,
      before + 1,
    );
    expect(tester.takeException(), isNull);
  });
}
