import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Common/FixtureFormationView.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ManagerRosterView.dart';
import 'package:mcmanager/models/FixtureFormation.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/models/OpponentLineup.dart';
import 'package:mcmanager/utils/Components/FootballPitch.dart';
import 'package:mcmanager/utils/Components/PlayerAvatar.dart';
import 'package:mcmanager/utils/FootballFormations.dart';
import 'package:mcmanager/utils/themes.dart';

import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory('build/v0106-cache').absolute.path,
        );
    await loadPreviewFonts();
  });
  final shape = footballFormations['4-2-1-3']!;
  final roles = [
    '27',
    '25',
    '23',
    '18',
    '14',
    '10',
    '7',
    '5',
    '5',
    '3',
    '0',
    '25',
  ];
  final roster = <Map<String, Object?>>[];
  var i = 0;
  for (var y = 0; y < shape.length; y++) {
    for (var x = 0; x < shape[y]; x++) {
      roster.add({
        'id': 'team-$i',
        'playerId': 'p$i',
        'customName': 'Titular $i',
        'customPositionId': roles[i],
        'x': x,
        'y': y,
        'isBench': 0,
        'shirtNumber': i + 1,
        'overall': 80,
      });
      i++;
    }
  }
  roster.add({
    'id': 'team-11',
    'playerId': 'p11',
    'customName': 'Reserva',
    'customPositionId': '25',
    'isBench': 1,
  });
  final names = {
    for (final p in roster) '${p['playerId']}': '${p['customName']}',
  };
  final positions = {
    for (final p in roster)
      '${p['playerId']}': p['customPositionId'] as String?,
  };
  final perfs = [
    for (var j = 0; j < 11; j++)
      ManagerFixturePlayerPerformance(
        personId: 'career',
        fixtureId: 'match',
        playerInstanceId: 'p$j',
        recordedStarted: true,
        avgRating: 7.5,
      ),
  ];
  final formation = FixtureFormation.initial(
    roster: roster,
    names: names,
    positions: positions,
    performances: perfs,
  );

  for (final size in [const Size(360, 640), const Size(390, 844)]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets(
        'Match and squad have identical pitch size and all 11 portrait coordinates $size scale $scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
          tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPadding);
          addTearDown(tester.view.resetViewPadding);
          final boundary = GlobalKey();
          Widget app(Widget body) => MaterialApp(
            theme: managerDarkTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              appBar: AppBar(title: const Text('2028 - 2028')),
              body: RepaintBoundary(key: boundary, child: body),
            ),
          );
          Future<void> capture(String suffix) async {
            final directory = Platform.environment['PROFILE_PREVIEW_DIR'];
            if (directory == null) return;
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(directory).create(recursive: true);
              await File(
                '$directory/v0106-$suffix-${size.width.toInt()}-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }

          await tester.pumpWidget(
            app(
              ManagerRosterView(
                person: reviewPerson(),
                roster: roster,
                gamePlayers: const {},
                onPlayerTap: (_, _) {},
                onAdd: () {},
                onMove: (_, _, _, {targetPosition}) async {},
                onLineupChanged: (_) async {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          final squadRect = tester.getRect(find.byType(FootballPitch));
          final centers = <String, Offset>{};
          final diameters = <String, Size>{};
          for (var j = 0; j < 11; j++) {
            final avatar = find.descendant(
              of: find.byKey(ValueKey('player-team-$j')),
              matching: find.byType(PlayerAvatar),
            );
            centers['p$j'] = tester.getCenter(avatar) - squadRect.topLeft;
            diameters['p$j'] = tester.getSize(avatar);
          }
          await capture('central');
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            app(
              FixtureFormationView(
                person: reviewPerson(),
                available: formation,
                saved: formation,
                performances: perfs,
                header: const SizedBox.shrink(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final matchRect = tester.getRect(find.byType(FootballPitch));
          expect(matchRect.size.width, closeTo(squadRect.width, .01));
          expect(matchRect.size.height, closeTo(squadRect.height, .01));
          for (var j = 0; j < 11; j++) {
            final avatar = find.byKey(ValueKey('pitch-avatar-p$j'));
            final center = tester.getCenter(avatar) - matchRect.topLeft;
            expect(
              center.dx,
              closeTo(centers['p$j']!.dx, .01),
              reason: 'p$j horizontal',
            );
            expect(
              center.dy,
              closeTo(centers['p$j']!.dy, .01),
              reason: 'p$j vertical',
            );
            expect(tester.getSize(avatar), diameters['p$j']);
          }
          expect(find.byType(LongPressDraggable<String>), findsNothing);
          expect(tester.takeException(), isNull);
          await capture('partida');
        },
      );
    }
  }

  test('Replacing one starter keeps the squad formation and every other coordinate', () {
    final extended = [
      ...roster,
      {
        'id': 'team-new',
        'playerId': 'new-cam',
        'customName': 'Meia do jogo',
        'customPositionId': '18',
        'isBench': 1,
      },
    ];
    final changed = FixtureFormation.initial(
      roster: extended,
      names: {...names, 'new-cam': 'Meia do jogo'},
      positions: {...positions, 'new-cam': '18'},
      performances: [
        for (final p in perfs)
          if (p.playerInstanceId != 'p3') p,
        ManagerFixturePlayerPerformance(
          personId: 'career',
          fixtureId: 'match',
          playerInstanceId: 'new-cam',
          recordedStarted: true,
        ),
      ],
    );
    expect(changed.formation, '4-2-1-3');
    expect(changed.starters['new-cam'], (x: 0, y: 1));
    for (final e in formation.starters.entries.where((e) => e.key != 'p3')) {
      expect(changed.starters[e.key], e.value, reason: e.key);
    }
  });

  test('Automatic lineup respects wings/fullbacks and midfield shapes without defaulting every team to 433', () {
    final set =
        FixtureFormation(
          formation: '4-2-1-3',
          players: formation.players,
          starters: {},
          bench: [],
        ).withFormation(
          '4-2-1-3',
          starting: formation.starters.keys.toList(),
          source: 'api',
        );
    expect(set.starters['p0'], (x: 0, y: 0));
    expect(set.starters['p1'], (x: 1, y: 0));
    expect(set.starters['p2'], (x: 2, y: 0));
    expect(set.starters['p6'], (x: 0, y: 3));
    expect(set.starters['p9'], (x: 3, y: 3));
    expect(
      inferFootballFormation([
        '0',
        '7',
        '5',
        '5',
        '3',
        '16',
        '14',
        '14',
        '12',
        '25',
        '25',
      ]),
      '4-4-2',
    );
    expect(
      inferFootballFormation([
        '0',
        '5',
        '5',
        '5',
        '16',
        '14',
        '10',
        '14',
        '12',
        '25',
        '25',
      ]),
      '3-1-4-2',
    );
    expect(
      inferFootballFormation([
        '0',
        '7',
        '5',
        '5',
        '3',
        '10',
        '10',
        '16',
        '18',
        '12',
        '25',
      ]),
      '4-2-3-1',
    );
  });

  test('Legacy empty opponent slots never hide named recorded starters that were put on the bench', () {
    final template = OpponentLineup.empty().squad;
    final broken = OpponentLineup(
      squad: template.copy(
        players: {...template.players, ...formation.players},
        bench: formation.players.keys.toList(),
        layoutSource: 'api',
      ),
      performances: perfs,
    );
    final fixed = broken.resolved();
    expect(fixed.squad.starters, hasLength(11));
    expect(fixed.squad.starters.keys.toSet(), formation.starters.keys.toSet());
    expect(
      fixed.squad.starters.keys.every(
        (id) => hasFootballPlayerName(fixed.names[id]),
      ),
      isTrue,
    );
    expect(fixed.squad.players.length, broken.squad.players.length);
    expect(fixed.performances, perfs);
  });
}
