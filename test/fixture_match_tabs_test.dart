import 'package:mcmanager/utils/AppColors.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Common/FixtureDetailsPage.dart';
import 'package:mcmanager/Common/FixtureFormationView.dart';
import 'package:mcmanager/models/FixtureFormation.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/utils/FixtureTablePosition.dart';
import 'package:mcmanager/utils/FootballFormations.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/Components/FootballPitch.dart';
import 'package:mcmanager/utils/Components/FixturePitchPlayer.dart';
import 'package:mcmanager/utils/themes.dart';

import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';

const playerNames = [
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
final roster = [
  for (var i = 0; i < playerNames.length; i++)
    {
      'id': 'team-$i',
      'playerId': 'p$i',
      'customName': playerNames[i],
      'customPositionId': i == 10 || i == 13
          ? '0'
          : i < 3
          ? '25'
          : i < 6
          ? '14'
          : '5',
      'shirtNumber': i + 1,
      'isBench': i >= 11 ? 1 : 0,
    },
];
final names = {
  for (var i = 0; i < playerNames.length; i++) 'p$i': playerNames[i],
};
final positions = {
  for (final p in roster) '${p['playerId']}': '${p['customPositionId']}',
};
final performances = [
  for (var i = 0; i < 11; i++)
    ManagerFixturePlayerPerformance(
      personId: 'career',
      fixtureId: 'match',
      playerInstanceId: 'p$i',
      avgRating: i == 0
          ? 8.6
          : i == 10
          ? 8
          : 6.5 + (i % 3) * .4,
      goalDetails: i == 0
          ? [
              PerformanceGoalDetails(
                id: 'first-goal',
                minute: 23,
                assistantId: 'p3',
              ),
              PerformanceGoalDetails(id: 'second-goal', minute: 57),
            ]
          : null,
      yellowCardDetails: i == 4
          ? [PerformanceTimeDetails(id: 'yellow', minute: 72)]
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
FixtureFormation get initial => FixtureFormation.initial(
  roster: roster,
  names: names,
  positions: positions,
  performances: performances,
);

void viewport(WidgetTester tester, {Size size = const Size(320, 640)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['PROFILE_PREVIEW_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Widget formationApp({
  FixtureFormation? saved,
  required Future<void> Function(FixtureFormation) onSave,
}) => MaterialApp(
  theme: managerDarkTheme,
  home: Scaffold(
    body: FixtureFormationView(
      editable: true,
      person: reviewPerson(),
      available: initial,
      saved: saved,
      performances: performances,
      header: const Text('São Paulo 2–0 Cruzeiro'),
      onSave: onSave,
    ),
  ),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async {
            final directory = Directory('build/v080-widget-cache');
            await directory.create(recursive: true);
            return directory.absolute.path;
          },
        );
    await loadPreviewFonts();
    await GameCatalog.load();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'Three match tabs fit small ${brightness.name} phones and retain the lineup list',
      (tester) async {
        viewport(tester, size: const Size(390, 844));
        final key = GlobalKey();
        FixtureFormation? saved;
        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.dark
                ? managerDarkTheme
                : managerLightTheme,
            home: RepaintBoundary(
              key: key,
              child: FixtureDetailsPage(
                person: reviewPerson(),
                fixture: {
                  ...reviewFixture(1),
                  'id': 'match',
                  'playerTeamScore': 2,
                  'oppositeTeamScore': 0,
                  'oppositeTeamId': 'fixture-opponent',
                  'position': 3,
                  'stage': 'Rodada 16',
                },
                opponent: 'Cruzeiro',
                tournament: 'Brasileirão',
                tablePosition: Future.value(
                  const FixtureTablePosition(position: 3, previous: 4),
                ),
                lineupData: Future.value(
                  FixtureLineupData(
                    roster,
                    performances,
                    names,
                    positions,
                    positionIds: positions,
                  ),
                ),
                onFormationSaved: (value) async => saved = value,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.widgetWithText(Tab, 'Principal'), findsOneWidget);
        for (final label in ['45%', '55%']) {
          final element = tester.element(find.text(label));
          final ink = (element.widget as Text).style!.color!;
          Color? background;
          element.visitAncestorElements((ancestor) {
            final widget = ancestor.widget;
            if (widget is Container && widget.decoration is BoxDecoration) {
              background = (widget.decoration as BoxDecoration).color;
            } else if (widget is Material && widget.color != null) {
              background = widget.color;
            }
            return background == null;
          });
          final first = ink.computeLuminance();
          final second = background!.computeLuminance();
          final contrast = first > second
              ? (first + .05) / (second + .05)
              : (second + .05) / (first + .05);
          expect(contrast, greaterThanOrEqualTo(4.5), reason: label);
        }
        expect(
          tester
                  .widget<Scaffold>(find.byType(Scaffold).first)
                  .backgroundColor ??
              Theme.of(tester.element(find.byType(Scaffold).first))
                  .scaffoldBackgroundColor,
          brightness == Brightness.dark
              ? AppColors.dark.background
              : AppColors.light.background,
        );
        await capture(tester, key, 'v080_principal_${brightness.name}');
        await tester.tap(find.widgetWithText(Tab, 'Linha do Tempo'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('timeline-event-sub')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('timeline-event-sub-in')),
          findsNothing,
        );
        final newestY = tester
            .getTopLeft(
              find.byKey(const ValueKey('timeline-event-second-goal')),
            )
            .dy;
        final oldestY = tester
            .getTopLeft(find.byKey(const ValueKey('timeline-event-first-goal')))
            .dy;
        expect(newestY, lessThan(oldestY));
        await capture(tester, key, 'v080_timeline_${brightness.name}');
        await tester.tap(find.byKey(const ValueKey('timeline-order')));
        await tester.pumpAndSettle();
        expect(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('timeline-event-first-goal')),
              )
              .dy,
          lessThan(
            tester
                .getTopLeft(
                  find.byKey(const ValueKey('timeline-event-second-goal')),
                )
                .dy,
          ),
        );
        await tester.tap(find.widgetWithText(Tab, 'Formação'));
        await tester.pumpAndSettle();
        expect(saved, isNull);
        expect(
          tester
              .widget<FixtureFormationView>(find.byType(FixtureFormationView))
              .available
              .starters,
          hasLength(11),
        );
        expect(find.byType(LongPressDraggable<String>), findsNothing);
        expect(
          find.textContaining('Brasileirão').hitTestable(),
          findsOneWidget,
        );
        await capture(tester, key, 'v080_formation_${brightness.name}');
        await tester.dragUntilVisible(
          find.text('Reservas relacionados · 1').hitTestable(),
          find.byKey(const PageStorageKey('fixture-formation')),
          const Offset(0, -350),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Reservas relacionados · 1').hitTestable(),
          findsOneWidget,
        );
        await capture(tester, key, 'v080_bench_${brightness.name}');
        await tester.tap(find.widgetWithText(Tab, 'Principal'));
        await tester.pumpAndSettle();
        await tester.dragUntilVisible(
          find.text('Reservas relacionados · 1').hitTestable(),
          find.byKey(const PageStorageKey('fixture-principal')),
          const Offset(0, -350),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('principal-formation')),
            matching: find.byKey(const ValueKey('fixture-pitch-player-p0')),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Match events overlay portraits in circles and row slots use the whole squad pitch',
    (tester) async {
      viewport(tester, size: const Size(390, 1000));
      await tester.pumpWidget(formationApp(onSave: (_) async {}));
      await tester.pumpAndSettle();
      final pitch = find.byType(FootballPitch);
      final bounds = tester.getRect(pitch);
      final left = tester.getRect(
        find.byKey(const ValueKey('fixture-slot-0-0')),
      );
      final right = tester.getRect(
        find.byKey(const ValueKey('fixture-slot-2-0')),
      );
      expect(left.left, closeTo(bounds.left + 9, 1));
      expect(right.right, closeTo(bounds.right - 9, 1));
      final goalBadge = find.byKey(const ValueKey('pitch-event-p0-goals'));
      final avatar = tester.getRect(
        find.byKey(const ValueKey('pitch-avatar-p0')),
      );
      expect(tester.getRect(goalBadge).overlaps(avatar), isTrue);
      final decoration =
          tester.widget<Container>(goalBadge).decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(
        find.byKey(const ValueKey('pitch-event-p1-sub-out')),
        findsOneWidget,
      );
      expect(find.text("85'"), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(FixturePitchPlayer),
          matching: find.byType(FixturePitchEvents),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Every formation and dense custom shapes fit 320px with larger text',
    (tester) async {
      viewport(tester);
      for (final label in [...footballFormations.keys, '6-3-1', '9-1']) {
        final saved = initial.withFormation(label);
        await tester.pumpWidget(
          MaterialApp(
            theme: managerDarkTheme,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(
                  size: Size(320, 640),
                  textScaler: TextScaler.linear(1.3),
                ),
                child: FixtureFormationView(
                  key: ValueKey(label),
                  person: reviewPerson(),
                  available: initial,
                  saved: saved,
                  performances: performances,
                  header: const Text('São Paulo'),
                  onSave: (_) async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('fixture-pitch-$label')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: label);
      }
    },
  );

  testWidgets(
    'Formation picker, custom shape, related bench and swaps persist per match',
    (tester) async {
      viewport(tester, size: const Size(390, 1000));
      FixtureFormation? saved;
      await tester.pumpWidget(
        formationApp(onSave: (value) async => saved = value),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('choose-fixture-formation')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '3-4-1-2');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '3-4-1-2'));
      await tester.pumpAndSettle();
      expect(saved?.formation, '3-4-1-2');
      await tester.tap(find.byKey(const ValueKey('choose-fixture-formation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('custom-formation')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '4-4-3');
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(
        find.text('As linhas precisam somar 10 jogadores.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField), '6-3-1');
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(saved?.formation, '6-3-1');
      final old = saved!.starters['p0'], target = saved!.starters['p1']!;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('fixture-pitch-player-p0'))),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveTo(
        tester.getCenter(
          find.byKey(ValueKey('fixture-slot-${target.x}-${target.y}')),
        ),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(saved?.starters['p1'], old);
      expect(saved?.starters['p0'], target);
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('relate-fixture-bench')),
        find.byKey(const PageStorageKey('fixture-formation')),
        const Offset(0, -350),
      );
      await tester.tap(find.byKey(const ValueKey('relate-fixture-bench')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('relate-p0')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('relate-p12')));
      await tester.tap(find.byKey(const ValueKey('relate-p13')));
      await tester.tap(find.byKey(const ValueKey('save-related-bench')));
      await tester.pumpAndSettle();
      expect(saved?.bench.toSet(), {'p11', 'p12', 'p13'});
      final snapshot = FixtureFormation.decode(saved!.encode());
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        formationApp(saved: snapshot, onSave: (_) async {}),
      );
      await tester.pumpAndSettle();
      expect(find.text('6-3-1'), findsOneWidget);
      expect(find.text('Reservas relacionados · 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Failed saves restore the formation and allow retry', (
    tester,
  ) async {
    viewport(tester);
    var fail = true;
    FixtureFormation? saved;
    await tester.pumpWidget(
      formationApp(
        saved: initial,
        onSave: (value) async {
          if (fail) throw StateError('test save failure');
          saved = value;
        },
      ),
    );
    await tester.pumpAndSettle();
    Future<void> choose() async {
      await tester.tap(find.byKey(const ValueKey('choose-fixture-formation')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '4-4-2');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '4-4-2').first);
      await tester.pumpAndSettle();
    }

    await choose();
    expect(
      find.text('Não foi possível salvar a formação. Tente novamente.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('fixture-pitch-4-3-3')), findsOneWidget);
    fail = false;
    await choose();
    expect(saved?.formation, '4-4-2');
    expect(tester.takeException(), isNull);
  });
}
