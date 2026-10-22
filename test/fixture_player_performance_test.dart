import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Common/FixtureDetailsPage.dart';
import 'package:mcmanager/Common/FixtureFormationView.dart';
import 'package:mcmanager/Common/FixturePlayerPerformancePage.dart';
import 'package:mcmanager/models/FixtureFormation.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/models/OpponentLineup.dart';
import 'package:mcmanager/utils/Components/FixturePitchPlayer.dart';
import 'package:mcmanager/utils/FixtureTablePosition.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:mcmanager/ManagerCareer/Fixtures/ManagerFixtureForm.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadPreviewFonts();
    await GameCatalog.load();
  });
  final roster = <Map<String, Object?>>[
    for (var i = 0; i < 12; i++)
      {
        'playerId': 'p$i',
        'customName': i == 7
            ? 'Gariglio'
            : i == 11
            ? 'Luan Santos'
            : 'Titular $i',
        'customPositionId': i == 10
            ? '0'
            : i == 11
            ? '10'
            : i >= 6
            ? '5'
            : '25',
        'isBench': i == 11 ? 1 : 0,
        if (i < 11)
          'x': i < 3
              ? i
              : i < 6
              ? i - 3
              : i < 10
              ? i - 6
              : 0,
        if (i < 11)
          'y': i < 3
              ? 0
              : i < 6
              ? 1
              : i < 10
              ? 2
              : 3,
      },
  ];
  final names = {
    for (final r in roster) '${r['playerId']}': '${r['customName']}',
  };
  final positions = {
    for (final r in roster)
      '${r['playerId']}': r['customPositionId'] as String?,
  };
  List<ManagerFixturePlayerPerformance> selected({bool changed = false}) => [
    for (var i = 0; i < 11; i++)
      ManagerFixturePlayerPerformance(
        personId: 'career',
        fixtureId: 'match',
        playerInstanceId: changed && i == 7 ? 'p11' : 'p$i',
        recordedStarted: true,
      ),
  ];
  FixtureFormation layout(List<ManagerFixturePlayerPerformance> rows) =>
      FixtureFormation.initial(
        roster: roster,
        names: names,
        positions: positions,
        performances: rows,
      );

  test('Saved XI follows match selections out of position while preserving the other ten places', () {
    final original = layout(selected()).place('p0', (x: 2, y: 0));
    final saved = FixtureFormation.decode(original.encode())!;
    final rows = selected(changed: true);
    rows.add(
      ManagerFixturePlayerPerformance(
        personId: 'career',
        fixtureId: 'match',
        playerInstanceId: 'new-sub',
        recordedStarted: false,
        recordedMinutes: 20,
      ),
    );
    final fixed = FixtureFormation.decode(
      saved.reconciledWith(layout(rows)).encode(),
    )!;
    expect(
      fixed.starters.keys.toSet(),
      selected(changed: true).map((p) => p.playerInstanceId).toSet(),
    );
    expect(fixed.starters['p11'], saved.starters['p7']);
    for (final e in saved.starters.entries.where((e) => e.key != 'p7')) {
      expect(fixed.starters[e.key], e.value, reason: e.key);
    }
    expect(fixed.bench, contains('new-sub'));
    expect(fixed.starters, isNot(contains('new-sub')));
    expect(
      saved.starters,
      contains('p7'),
      reason: 'Repair must not mutate historical source',
    );
  });

  for (final editable in [false, true]) {
    testWidgets(
      'Rebuilding ${editable ? 'editor' : 'viewer'} replaces stale roster member with selected midfielder',
      (tester) async {
        var rows = selected();
        final saved = layout(rows);
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            theme: managerDarkTheme,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return FixtureFormationView(
                    person: reviewPerson(),
                    available: layout(rows),
                    saved: saved,
                    performances: rows,
                    editable: editable,
                    header: const SizedBox.shrink(),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<FixturePitchPlayer>(find.byType(FixturePitchPlayer))
              .map((p) => p.id),
          contains('p7'),
        );
        update(() => rows = selected(changed: true));
        await tester.pumpAndSettle();
        final ids = tester
            .widgetList<FixturePitchPlayer>(find.byType(FixturePitchPlayer))
            .map((p) => p.id)
            .toSet();
        expect(
          ids,
          selected(changed: true).map((p) => p.playerInstanceId).toSet(),
        );
        expect(ids, isNot(contains('p7')));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final empty in [false, true]) {
    testWidgets(
      'Saving ${empty ? 'an empty' : 'a changed'} match list repairs the stored XI without opening the pitch',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        Map<String, Object?>? saved;
        final rows = empty
            ? <ManagerFixturePlayerPerformance>[]
            : selected(changed: true);
        await tester.pumpWidget(
          MaterialApp(
            theme: managerDarkTheme,
            home: ManagerFixtureForm(
              person: reviewPerson(),
              existing: {
                ...reviewFixture(1),
                'id': 'match',
                'matchLineup': layout(selected()).encode(),
              },
              preloaded: (
                seasons: [reviewSeason()],
                roster: roster,
                players: [
                  for (final r in roster)
                    {
                      'id': r['playerId'],
                      'name': r['customName'],
                      'positionId': r['customPositionId'],
                    },
                ],
              ),
              preloadedPerformances: rows,
              opponentLineupLoader: (_, _) async => null,
              onFixtureSaved: (fixture, _) async => saved = fixture,
            ),
          ),
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        expect(saved, isNotNull);
        final actual = FixtureFormation.decode(saved!['matchLineup'])!;
        expect(
          actual.starters.keys.toSet(),
          rows.map((p) => p.playerInstanceId).toSet(),
        );
        expect(actual.starters, isNot(contains('p7')));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final replace in [false, true]) {
    testWidgets(
      'Opening the pitch ${replace ? 'and explicitly replacing a player updates the list' : 'preserves every selected row and statistic'}',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await tester.binding.setSurfaceSize(const Size(390, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final rows = [
          ...selected(),
          ManagerFixturePlayerPerformance(
            personId: 'career',
            fixtureId: 'match',
            playerInstanceId: 'p11',
            recordedStarted: false,
          ),
        ];
        rows.first.recordedStarted = null;
        List<ManagerFixturePlayerPerformance>? saved;
        await tester.pumpWidget(
          MaterialApp(
            theme: managerDarkTheme,
            home: ManagerFixtureForm(
              person: reviewPerson(),
              existing: {...reviewFixture(1), 'id': 'match'},
              preloaded: (
                seasons: [reviewSeason()],
                roster: roster,
                players: [
                  for (final r in roster)
                    {
                      'id': r['playerId'],
                      'name': r['customName'],
                      'positionId': r['customPositionId'],
                    },
                ],
              ),
              preloadedPerformances: rows,
              opponentLineupLoader: (_, _) async => null,
              onFixtureSaved: (_, performances) async => saved = performances,
            ),
          ),
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        final toggle = find.byKey(const ValueKey('lineup-view-formation'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        if (replace) {
          final player = find.byKey(const ValueKey('pitch-name-p7'));
          await tester.ensureVisible(player);
          await tester.tap(player);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('pitch-action-replace')));
          await tester.pumpAndSettle();
          expect(find.text('Escolher jogador'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('choose-p11')),
            120,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.tap(find.byKey(const ValueKey('choose-p11')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        expect(saved, isNotNull);
        if (replace) {
          expect(
            saved!.map((p) => p.playerInstanceId).toSet(),
            selected(changed: true).map((p) => p.playerInstanceId).toSet(),
          );
          expect(
            saved!
                .where((p) => p.playerInstanceId == 'p11')
                .single
                .recordedStarted,
            isTrue,
          );
        } else {
          expect(
            {for (final p in saved!) p.id: p.toMap()},
            {for (final p in rows) p.id: p.toMap()},
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  ManagerFixturePlayerPerformance report() => ManagerFixturePlayerPerformance(
    personId: 'career',
    fixtureId: 'match',
    playerInstanceId: 'p1',
    recordedStarted: true,
    recordedMinutes: 73,
    avgRating: 8.6,
    goalsCount: 2,
    assistsCount: 1,
    shotsCount: 5,
    passes: 40,
    keyPasses: 3,
    yellowCards: 0,
    dribbles: 4,
    apiStats: {
      'passes': 40,
      'passesCompleted': 34,
      'shots': 5,
      'shotsOnTarget': 3,
      'shotsBlocked': 1,
      'expectedAssists': .42,
      'aerialDuelsAttempted': 0,
      'aerialDuelsWon': 0,
      'dribbles': 4,
      'dribblesCompleted': 3,
    },
    goalDetails: [
      PerformanceGoalDetails(
        minute: 24,
        fieldLocation: const GoalShotLocation(.5, .8),
        goalLocation: const GoalShotLocation(.2, .7),
      ),
      PerformanceGoalDetails(minute: 63, type: [GoalType.penalty]),
    ],
    assistDetails: [PerformanceAssistDetails(minute: 41)],
    substitutionDetails: [
      PerformanceSubstitutionDetails(
        minute: 73,
        inferred: true,
        type: SubstitutionType.outGame,
        anotherPlayerName: 'Calleri',
      ),
    ],
  );

  Future<void> capture(
    WidgetTester tester,
    GlobalKey boundary,
    String suffix,
  ) async {
    final directory = Platform.environment['PROFILE_PREVIEW_DIR'];
    if (directory == null) return;
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/v0107-performance-$suffix.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final dark in [true, false]) {
    testWidgets(
      'Match report shows exact data, ratio charts, events and explicit profile action in ${dark ? 'dark' : 'light'} theme',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final boundary = GlobalKey();
        var profiles = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? managerDarkTheme : managerLightTheme,
            home: RepaintBoundary(
              key: boundary,
              child: FixturePlayerPerformancePage(
                name: 'Brenner',
                team: 'São Paulo',
                match: 'São Paulo 3 × 1 Santos',
                date: DateTime(2028, 9, 3, 21),
                position: 'ATA',
                avatar: (r) => CircleAvatar(radius: r, child: const Text('B')),
                performance: report(),
                captain: true,
                playerOfMatch: true,
                onViewPlayer: () => profiles++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('73 min em campo'), findsOneWidget);
        expect(find.text('Capitão'), findsOneWidget);
        expect(find.text('Melhor em campo'), findsOneWidget);
        expect(find.byKey(const ValueKey('match-metric-Gols')), findsOneWidget);
        expect(profiles, 0);
        await capture(tester, boundary, dark ? 'dark-header' : 'light-header');
        await tester.tap(find.byKey(const ValueKey('match-player-profile')));
        expect(profiles, 1);
        final scroll = find.byKey(const ValueKey('match-player-report'));
        await tester.drag(scroll, const Offset(0, -550));
        await tester.pumpAndSettle();
        expect(find.text('85%'), findsOneWidget);
        expect(find.text('34 de 40 passes certos'), findsOneWidget);
        expect(find.text('60%'), findsOneWidget);
        expect(find.text('75%'), findsOneWidget);
        expect(
          find.text('0%'),
          findsNothing,
          reason: 'Zero attempts is not a 0% success rate',
        );
        await capture(tester, boundary, dark ? 'dark-charts' : 'light-charts');
        await tester.drag(scroll, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(find.text('Gol de pênalti'), findsOneWidget);
        expect(find.text('~73\''), findsOneWidget);
        expect(find.text('Saiu · Calleri'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Sparse reports and large text fit small phones without invented counters or a dead profile action',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: managerDarkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: FixturePlayerPerformancePage(
            name: 'Um jogador com nome comprido',
            team: 'Time adversário',
            match: 'São Paulo 3 × 1 Adversário',
            avatar: (r) => CircleAvatar(radius: r),
            performance: ManagerFixturePlayerPerformance(
              personId: 'career',
              fixtureId: 'match',
              playerInstanceId: 'unknown',
              goalsCount: 0,
              shotsCount: 0,
              shotAccuracy: 0,
              passes: 40,
              passAccuracy: 75,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('match-player-profile')), findsNothing);
      expect(find.byKey(const ValueKey('match-metric-Gols')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('match-metric-Assistências')),
        findsNothing,
      );
      expect(find.text('Finalizações no alvo'), findsNothing);
      for (var i = 0; i < 5; i++) {
        await tester.drag(
          find.byKey(const ValueKey('match-player-report')),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'Player taps in the match list, own pitch and opponent pitch open a match report before the profile',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final own = layout(selected());
      final opponent = OpponentLineup(
        squad: FixtureFormation(
          formation: '4-3-3',
          players: {
            'other': {'name': 'Adversário', 'positionId': '25'},
          },
          starters: {'other': (x: 0, y: 0)},
          bench: [],
          layoutSource: 'manual',
        ),
        performances: [
          ManagerFixturePlayerPerformance(
            personId: 'career',
            fixtureId: 'match',
            playerInstanceId: 'other',
            goalsCount: 1,
            recordedStarted: true,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: managerDarkTheme,
          home: FixtureDetailsPage(
            person: reviewPerson(),
            fixture: {
              ...reviewFixture(1),
              'id': 'match',
              'playerTeamScore': 3,
              'oppositeTeamScore': 1,
            },
            opponent: 'Santos',
            tournament: 'Brasileirão',
            tablePosition: Future.value(
              const FixtureTablePosition(position: 1),
            ),
            lineupData: Future.value(
              FixtureLineupData(
                roster,
                [report()],
                names,
                {for (final e in positions.entries) e.key: e.value ?? ''},
                positionIds: positions,
                ownFormation: own,
                opponentLineup: opponent,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Titular 1').last);
      await tester.tap(find.text('Titular 1').last);
      await tester.pumpAndSettle();
      expect(find.byType(FixturePlayerPerformancePage), findsOneWidget);
      expect(
        find.byKey(const ValueKey('match-player-profile')),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Formação'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pitch-name-p1')));
      await tester.pumpAndSettle();
      expect(find.byType(FixturePlayerPerformancePage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('formation-team-opponent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pitch-name-other')));
      await tester.pumpAndSettle();
      expect(find.byType(FixturePlayerPerformancePage), findsOneWidget);
      expect(
        tester
            .widget<FixturePlayerPerformancePage>(
              find.byType(FixturePlayerPerformancePage),
            )
            .performance
            ?.goalsCount,
        1,
      );
      expect(find.byKey(const ValueKey('match-player-profile')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
