import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileData.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerScoringInsights.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/utils/themes.dart';

import 'ui_preview_fonts.dart';

void main() {
  setUpAll(loadPreviewFonts);
  PlayerMatchData match({
    List<PerformanceGoalDetails> goals = const [],
    int count = 0,
    int missed = 0,
  }) => PlayerMatchData({
    ...ManagerFixturePlayerPerformance(
      personId: 'p',
      fixtureId: 'f',
      playerInstanceId: 'a',
      goalDetails: goals,
      missedPenaltyDetails: List.generate(
        missed,
        (_) => PerformanceTimeDetails(),
      ),
      penaltySaves: 2,
    ).toMap(),
    'goalsCount': count,
  });
  test('Scoring maps distinguish origin, goal region, penalties and missing locations', () {
    final data = PlayerScoringData([
      match(
        count: 6,
        missed: 1,
        goals: [
          PerformanceGoalDetails(
            fieldLocation: const GoalShotLocation(.5, .95),
            goalLocation: const GoalShotLocation(.1, .1),
          ),
          PerformanceGoalDetails(
            fieldLocation: const GoalShotLocation(.5, .7),
            goalLocation: const GoalShotLocation(.5, .5),
          ),
          PerformanceGoalDetails(
            fieldLocation: const GoalShotLocation(.9, .5),
            goalLocation: const GoalShotLocation(.9, .9),
          ),
          PerformanceGoalDetails(type: [GoalType.penalty]),
          PerformanceGoalDetails(),
          PerformanceGoalDetails(),
        ],
      ),
    ]);
    expect(data.origins, {
      'Pequena área': 1,
      'Grande área': 1,
      'Fora da área': 1,
      'Pênalti': 1,
    });
    expect(data.fieldLocations, hasLength(4));
    expect(data.unknownField, 2);
    expect(data.regions, [1, 0, 0, 0, 1, 0, 0, 0, 1]);
    expect(data.unknownGoal, 3);
    expect(data.penalties, 1);
    expect(data.missed, 1);
    expect(data.saved, 2);
    expect(data.conversion, '50,0%');
  });
  test(
    'Legacy counters never become invented goal positions or penalty attempts',
    () {
      final base = match(count: 3).row;
      final data = PlayerScoringData([
        PlayerMatchData({...base, 'goalDetails': null}),
      ]);
      expect(data.goals, 3);
      expect(data.unknownField, 3);
      expect(data.unknownGoal, 3);
      expect(data.fieldLocations, isEmpty);
      expect(data.conversion, '—');
    },
  );
  test('Goal region boundaries agree with the goal placement grid', () {
    final data = PlayerScoringData([
      match(
        count: 2,
        goals: [
          PerformanceGoalDetails(
            goalLocation: const GoalShotLocation(.28, 1 / 3),
          ),
          PerformanceGoalDetails(goalLocation: const GoalShotLocation(.72, 1)),
        ],
      ),
    ]);
    expect(data.regions[4], 1);
    expect(data.regions[8], 1);
  });
  for (final dark in [true, false]) {
    testWidgets(
      'Scoring insights show maps, coverage and penalties in ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? managerDarkTheme : managerLightTheme,
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                appBar: AppBar(title: const Text('Temporada · gols')),
                body: SingleChildScrollView(
                  child: PlayerScoringInsights(
                    matches: [
                      match(
                        count: 5,
                        missed: 1,
                        goals: [
                          PerformanceGoalDetails(
                            fieldLocation: const GoalShotLocation(.5, .9),
                            goalLocation: const GoalShotLocation(.1, .1),
                          ),
                          PerformanceGoalDetails(
                            fieldLocation: const GoalShotLocation(.4, .7),
                            goalLocation: const GoalShotLocation(.1, .1),
                          ),
                          PerformanceGoalDetails(
                            fieldLocation: const GoalShotLocation(.8, .4),
                            goalLocation: const GoalShotLocation(.9, .9),
                          ),
                          PerformanceGoalDetails(
                            type: [GoalType.penalty],
                            goalLocation: const GoalShotLocation(.5, .5),
                          ),
                          PerformanceGoalDetails(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Canto preferido: Alta · esquerda · 2 de 4 gols (50%)',
            findRichText: true,
          ),
          findsOneWidget,
        );
        expect(find.text('1 gol sem região do gol informada.'), findsOneWidget);
        final directory = Platform.environment['PROFILE_PREVIEW_DIR'];
        if (directory != null) {
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(directory).create(recursive: true);
            await File(
              '$directory/player-scoring-${dark ? 'dark' : 'light'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.scrollUntilVisible(
          find.text('Aproveitamento'),
          240,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('50,0%'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
