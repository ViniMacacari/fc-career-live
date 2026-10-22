import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/ManagerSeasonsStatistics/ManagerSeasonsStatisticsGrid.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ManagerRosterView.dart';
import 'package:mcmanager/models/Person.dart';
import 'package:mcmanager/models/Season.dart';
import 'package:mcmanager/utils/Components/PlayerAvatar.dart';
import 'package:mcmanager/utils/Components/FootballPitch.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:mcmanager/utils/FootballFormations.dart';

void main() {
  final person = Person(
    id: 'person',
    name: 'Treinador',
    category: PersonCategory.manager,
    fifaVersion: 'FC27',
    leagueId: '100',
    teamId: '1',
    nationalityId: '54',
    createdAt: DateTime(2028),
    updatedAt: DateTime(2028),
  );

  void viewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
  }

  Future<void> drag(WidgetTester tester, Finder source, Finder target) async {
    final gesture = await tester.startGesture(tester.getCenter(source));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(360, 640), const Size(390, 844)]) {
    testWidgets(
      'campo inteiro e reservas juntos em $size nas quatro formações',
      (tester) async {
        viewport(tester, size);
        Map<String, ({int x, int y})>? saved;
        await tester.pumpWidget(
          MaterialApp(
            theme: managerDarkTheme,
            home: Scaffold(
              appBar: AppBar(title: const Text('2028 - 2028')),
              body: ManagerRosterView(
                person: person,
                gamePlayers: const {},
                roster: [
                  for (var i = 0; i < 11; i++)
                    {
                      'id': 'starter$i',
                      'customName': 'Titular $i',
                      'customPositionId': '14',
                      'overall': 80,
                      'isBench': 0,
                    },
                  {'id': 'reserve', 'customName': 'Reserva', 'isBench': 1},
                ],
                onAdd: () {},
                onMove: (_, _, _, {targetPosition}) async {},
                onPlayerTap: (_, _) {},
                onLineupChanged: (lineup) async => saved = lineup,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(FootballPitch), findsOneWidget);
        for (final formation in ['4-3-3', '4-4-2', '3-5-2', '4-2-3-1']) {
          await tester.tap(find.byType(DropdownButton<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.text(formation).last);
          await tester.pumpAndSettle();
          expect(saved, hasLength(11));
          for (var i = 0; i < 11; i++) {
            final player = find.byKey(ValueKey('player-starter$i'));
            expect(player.hitTestable(), findsOneWidget);
            final avatar = find.descendant(
              of: player,
              matching: find.byType(PlayerAvatar),
            );
            expect(
              tester.getSize(avatar).width,
              greaterThanOrEqualTo(size.height > 800 ? 44 : 32),
            );
          }
          final pitch = tester.getRect(
            find.byKey(const ValueKey('lineup-pitch')),
          );
          final bench = tester.getRect(
            find.byKey(const ValueKey('reserve-area')),
          );
          expect(pitch.top, lessThan(130));
          expect(pitch.bottom, lessThan(bench.top));
          expect(bench.bottom, lessThanOrEqualTo(size.height));
          expect(find.text('Reserva').hitTestable(), findsOneWidget);
          expect(find.byType(TabBar), findsNothing);
          expect(tester.takeException(), isNull);
        }
        final from = saved!['starter0'], to = saved!['starter1'];
        await drag(tester, find.text('Titular 0'), find.text('Titular 1'));
        expect(saved!['starter0'], to);
        expect(saved!['starter1'], from);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Catálogo ampliado mantém todos os titulares visíveis no elenco',
    (tester) async {
      viewport(tester, const Size(360, 640));
      Map<String, ({int x, int y})>? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: managerDarkTheme,
          home: Scaffold(
            appBar: AppBar(title: const Text('Elenco')),
            body: ManagerRosterView(
              person: person,
              gamePlayers: const {},
              roster: [
                for (var i = 0; i < 11; i++)
                  {
                    'id': 'starter$i',
                    'customName': 'Titular $i',
                    'customPositionId': '14',
                    'overall': 80,
                    'isBench': 0,
                  },
                {'id': 'reserve', 'customName': 'Reserva', 'isBench': 1},
              ],
              onAdd: () {},
              onMove: (_, _, _, {targetPosition}) async {},
              onPlayerTap: (_, _) {},
              onLineupChanged: (value) async => saved = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in footballFormations.keys) {
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .onChanged!(label);
        await tester.pumpAndSettle();
        expect(saved, hasLength(11), reason: label);
        for (var i = 0; i < 11; i++) {
          expect(
            find.byKey(ValueKey('player-starter$i')).hitTestable(),
            findsOneWidget,
            reason: label,
          );
        }
        expect(tester.takeException(), isNull, reason: label);
      }
    },
  );

  testWidgets(
    'arraste troca reserva e titular nos dois sentidos e preenche vaga',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final rows = <Map<String, Object?>>[
        for (var y = 0; y < 5; y++)
          for (var x = 0; x < [1, 3, 2, 4, 1][y]; x++)
            {
              'id': 's$x$y',
              'customName': 'Titular $x$y',
              'x': x,
              'y': y,
              'isBench': 0,
            },
        {'id': 'r0', 'customName': 'Reserva 0', 'isBench': 1},
        {'id': 'r1', 'customName': 'Reserva 1', 'isBench': 1},
      ];
      String? moved, replaced, opened;
      bool? reserve;
      ({int x, int y})? savedPosition;
      await tester.pumpWidget(
        MaterialApp(
          theme: managerDarkTheme,
          home: Scaffold(
            appBar: AppBar(title: const Text('2028 - 2028')),
            body: StatefulBuilder(
              builder: (context, setState) => ManagerRosterView(
                person: person,
                roster: rows,
                gamePlayers: const {},
                onAdd: () {},
                onLineupChanged: (_) async {},
                onPlayerTap: (row, _) => opened = row['id'] as String,
                onMove: (row, toReserve, replacement, {targetPosition}) async {
                  moved = row['id'] as String;
                  replaced = replacement?['id'] as String?;
                  reserve = toReserve;
                  savedPosition = targetPosition;
                  setState(() {
                    if (replacement != null) {
                      replacement['isBench'] = 1;
                      replacement['x'] = null;
                      replacement['y'] = null;
                    }
                    row['isBench'] = toReserve ? 1 : 0;
                    row['x'] = toReserve ? null : targetPosition?.x;
                    row['y'] = toReserve ? null : targetPosition?.y;
                  });
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await drag(tester, find.text('Reserva 0'), find.text('Titular 00'));
      expect(moved, 'r0');
      expect(replaced, 's00');
      expect(reserve, false);
      expect(savedPosition, (x: 0, y: 0));
      expect(rows.where((r) => r['isBench'] == 0), hasLength(11));
      expect(
        tester.getRect(find.text('Reserva 0')).bottom,
        lessThan(
          tester.getRect(find.byKey(const ValueKey('reserve-area'))).top,
        ),
      );

      await drag(tester, find.text('Reserva 0'), find.text('Reserva 1'));
      expect(moved, 'r1');
      expect(replaced, 'r0');
      expect(savedPosition, (x: 0, y: 0));
      expect(rows.where((r) => r['isBench'] == 0), hasLength(11));

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Reserva 1')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final bench = tester.getRect(find.byKey(const ValueKey('reserve-area')));
      await gesture.moveTo(Offset(bench.right - 12, bench.top + 30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(moved, 'r1');
      expect(reserve, true);
      expect(replaced, isNull);
      expect(rows.where((r) => r['isBench'] == 0), hasLength(10));
      expect(find.text('4-2-3-1'), findsOneWidget);

      await drag(
        tester,
        find.text('Reserva 1'),
        find.byKey(const ValueKey('lineup-slot-0-0')),
      );
      expect(moved, 'r1');
      expect(replaced, isNull);
      expect(reserve, false);
      expect(savedPosition, (x: 0, y: 0));
      expect(rows.where((r) => r['isBench'] == 0), hasLength(11));
      await tester.tap(find.text('Reserva 1'));
      await tester.pump();
      expect(opened, 'r1');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reservas crescem em linhas verticais com o campo sempre visível',
    (tester) async {
      viewport(tester, const Size(390, 844));
      String? opened;
      String? movedReserve, replacedStarter;
      ({int x, int y})? savedPosition;
      final previewKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: managerDarkTheme,
          home: RepaintBoundary(
            key: previewKey,
            child: Scaffold(
              appBar: AppBar(
                leading: const BackButton(),
                title: const Text('2028 - 2028'),
                actions: const [
                  IconButton(
                    onPressed: null,
                    icon: Icon(Icons.calendar_month_outlined),
                  ),
                ],
              ),
              body: ManagerRosterView(
                person: person,
                gamePlayers: const {},
                roster: [
                  for (var i = 0; i < 11; i++)
                    {
                      'id': 'starter$i',
                      'customName': 'Titular $i',
                      'overall': 80,
                      'isBench': 0,
                    },
                  for (var i = 0; i < 22; i++)
                    {
                      'id': 'reserve$i',
                      'customName': 'Reserva $i',
                      'overall': 75,
                      'isBench': 1,
                    },
                ],
                onAdd: () {},
                onMove: (row, _, replacement, {targetPosition}) async {
                  movedReserve = row['id'] as String;
                  replacedStarter = replacement?['id'] as String?;
                  savedPosition = targetPosition;
                },
                onLineupChanged: (_) async {},
                onPlayerTap: (row, _) => opened = row['id'] as String,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = tester.getRect(find.text('Reserva 0'));
      final second = tester.getRect(find.text('Reserva 1'));
      final nextRow = tester.getRect(find.text('Reserva 5'));
      expect(second.center.dx, greaterThan(first.center.dx));
      expect(second.top, closeTo(first.top, 1));
      expect(nextRow.top, greaterThan(first.bottom));
      final pitch = tester.getRect(find.byKey(const ValueKey('lineup-pitch')));
      final directory = Platform.environment['ROSTER_PREVIEW_DIR'];
      if (directory != null) {
        await tester.runAsync(() async {
          final boundary =
              previewKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final picture = await boundary.toImage(pixelRatio: 2);
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await Directory(directory).create(recursive: true);
          await File('$directory/roster.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
      final scroll = find.descendant(
        of: find.byKey(const ValueKey('reserve-grid')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Reserva 21'),
        90,
        scrollable: scroll,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reserva 21'));
      await tester.pump();
      expect(opened, 'reserve21');
      await drag(tester, find.text('Reserva 21'), find.text('Titular 0'));
      expect(movedReserve, 'reserve21');
      expect(replacedStarter, 'starter0');
      expect(savedPosition, (x: 0, y: 0));
      expect(tester.getRect(find.byKey(const ValueKey('lineup-pitch'))), pitch);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('grade calcula vitórias e percentual por temporada', (
    tester,
  ) async {
    final season = Season(
      id: 'season',
      personId: person.id,
      startDate: DateTime(2025),
      endDate: DateTime(2026),
      createdAt: DateTime(2025),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManagerSeasonsStatisticsGrid(
            seasons: [season],
            fixtures: const [
              {
                'seasonId': 'season',
                'playerTeamScore': 2,
                'oppositeTeamScore': 0,
              },
              {
                'seasonId': 'season',
                'playerTeamScore': 1,
                'oppositeTeamScore': 1,
              },
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('2025/2026'), findsOneWidget);
    expect(find.text('50.0%'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
