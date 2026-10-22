import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/Fixtures/Performances/PerformanceDetails.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerDetailedStats.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileData.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/utils/themes.dart';

import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';

void main() {
  setUpAll(loadPreviewFonts);
  final p = ManagerFixturePlayerPerformance(
    personId: 'career',
    fixtureId: 'f',
    playerInstanceId: 'a',
    passes: 20,
    apiStats: {
      'npkExpectedGoals': 1.2345,
      'expectedAssists': .42,
      'interceptions': 3,
      'passesUnderPressure': 10,
      'passesCompletedUnderPressure': 8,
      'futureField': 'keep',
    },
  );
  for (final dark in [true, false]) {
    testWidgets(
      'Detailed player stats fit narrow ${dark ? 'dark' : 'light'} screens and show weighted values',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
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
                appBar: AppBar(title: const Text('Estatísticas')),
                body: SingleChildScrollView(
                  child: PlayerDetailedStats(
                    matches: [PlayerMatchData(p.toMap())],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('1,23'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('detailed-stat/goalsConceded')),
          findsNothing,
        );
        expect(find.text('80,0%'), findsOneWidget);
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
              '$directory/detailed-stats-${dark ? 'dark' : 'light'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Detailed inputs keep decimals and hidden legacy values on save',
    (tester) async {
      PerformanceDetailsResult? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: managerDarkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Abrir'),
                onPressed: () async {
                  result = await Navigator.push<PerformanceDetailsResult>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PerformanceDetails(
                        person: reviewPerson(),
                        performance: p,
                        isNew: false,
                        names: const {'a': 'Atacante'},
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      final expansion = find.byKey(
        const ValueKey('detailed-performance-editor'),
      );
      await tester.scrollUntilVisible(
        expansion,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(expansion);
      await tester.pumpAndSettle();
      final xg = find.byKey(
        const ValueKey('performance-stat/npkExpectedGoals'),
      );
      await tester.ensureVisible(xg);
      await tester.pumpAndSettle();
      await tester.enterText(xg, '2,75');
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(result!.performance!.apiStats['npkExpectedGoals'], 2.75);
      expect(result!.performance!.apiStats['futureField'], 'keep');
      expect(result!.performance!.passes, 20);
      expect(p.apiStats['npkExpectedGoals'], 1.2345);
      expect(tester.takeException(), isNull);
    },
  );
}
