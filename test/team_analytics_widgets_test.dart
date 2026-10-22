import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/Graphics/ManagerGraphics.dart';
import 'package:mcmanager/ManagerCareer/Graphics/TeamAnalyticsCharts.dart';
import 'package:mcmanager/models/Person.dart';
import 'package:mcmanager/models/Season.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/themes.dart';

import 'ui_preview_fonts.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadPreviewFonts();
  });
  final person = Person(
    id: 'career',
    name: 'Carreira São Paulo',
    category: PersonCategory.manager,
    fifaVersion: 'FC26',
    leagueId: '1',
    teamId: 'club',
    nationalityId: '54',
    createdAt: DateTime(2025),
    updatedAt: DateTime(2026),
  );
  final source = TeamAnalyticsSnapshot(
    teams: const {
      'club': CatalogItem('club', 'São Paulo'),
      'other': CatalogItem('other', 'Santos'),
      'opponent': CatalogItem('opponent', 'Flamengo'),
    },
    competitions: const {'league': 'Brasileirão', 'cup': 'Copa do Brasil'},
    seasons: [
      for (var i = 0; i < 2; i++)
        Season(
          id: 's$i',
          personId: person.id,
          startDate: DateTime(2025 + i, 7),
          endDate: DateTime(2026 + i, 6),
          createdAt: DateTime(2025),
        ),
    ],
    fixtures: [
      for (var i = 0; i < 24; i++)
        {
          'id': 'f$i',
          'date': DateTime(
            2025 + i ~/ 12,
            7 + (i % 12) ~/ 4,
            1 + (i % 4) * 7,
          ).toIso8601String(),
          'seasonId': i < 12 ? 's0' : 's1',
          'playerTeamId': i < 20 ? 'club' : 'other',
          'oppositeTeamId': 'opponent',
          'tournamentId': i % 4 == 0 ? 'cup' : 'league',
          'location': i.isEven ? 'home' : 'away',
          'playerTeamScore': i % 4,
          'oppositeTeamScore': i % 3,
          'teamPossession': i % 5 == 0 ? null : 48.0 + i % 15,
          'passAccuracy': 80.0 + i % 10,
          'playerTeamShoutsCount': 10 + i % 7,
        },
    ],
  );

  void viewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    final directory = Platform.environment['PROFILE_PREVIEW_DIR'];
    if (directory == null) return;
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

  for (final size in [const Size(360, 640), const Size(390, 844)]) {
    testWidgets('analytics charts, filters and timeline fit $size', (
      tester,
    ) async {
      viewport(tester, size);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: managerDarkTheme.copyWith(
              splashFactory: NoSplash.splashFactory,
            ),
            home: ManagerGraphics(person: person, load: (_) async => source),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('24 jogos'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'analytics-top-${size.width.toInt()}');
      await tester.scrollUntilVisible(
        find.text('O ritmo do time'),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(AnalyticsEvolutionChart), findsOneWidget);
      await capture(tester, key, 'analytics-evolution-${size.width.toInt()}');
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Gols'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Gols'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Saldo'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Saldo'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Posse'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Posse'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Como os jogos terminaram'),
        230,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await capture(tester, key, 'analytics-results-${size.width.toInt()}');
      await tester.ensureVisible(
        find.widgetWithText(ChoiceChip, 'Por temporada'),
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Por temporada'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('A identidade em campo'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Linha do tempo'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await capture(tester, key, 'analytics-timeline-${size.width.toInt()}');
      await tester.tap(find.byTooltip('Filtros'));
      await tester.pumpAndSettle();
      await capture(tester, key, 'analytics-filters-${size.width.toInt()}');
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026/2027').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver análise'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
      await tester.pumpAndSettle();
      expect(find.text('12 jogos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('empty career offers a clear starting state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ManagerGraphics(
          person: person,
          load: (_) async => const TeamAnalyticsSnapshot(fixtures: []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A história começa no próximo jogo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
