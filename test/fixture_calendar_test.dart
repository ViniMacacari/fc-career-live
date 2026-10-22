import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mcmanager/Common/FixtureCalendar.dart';
import 'package:mcmanager/utils/themes.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));
  final games = <Map<String, Object?>>[
    {
      'id': 'a',
      'date': '2024-02-29T21:00:00',
      'playerTeamScore': 3,
      'oppositeTeamScore': 0,
    },
    {
      'id': 'b',
      'date': '2024-02-29T15:00:00',
      'playerTeamScore': 0,
      'oppositeTeamScore': 1,
    },
    {
      'id': 'c',
      'date': '2023-12-31T18:00:00',
      'playerTeamScore': 1,
      'oppositeTeamScore': 1,
    },
  ];
  Widget app(
    List<Map<String, Object?>> rows, {
    VoidCallback? onOpen,
    bool dark = true,
    double scale = 1,
  }) => MaterialApp(
    theme: dark ? managerDarkTheme : managerLightTheme,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: SingleChildScrollView(
          child: FixtureCalendar(
            rows: rows,
            locale: 'pt_BR',
            matchBuilder: (row) => TextButton(
              key: ValueKey('match-${row['id']}'),
              onPressed: onOpen ?? () {},
              child: Text('Jogo ${row['id']}'),
            ),
          ),
        ),
      ),
    ),
  );
  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Calendar has actual leap-month days, multiple games in time order and empty days',
    (tester) async {
      var opened = false;
      await tester.pumpWidget(app(games, onOpen: () => opened = true));
      await tester.pumpAndSettle();
      expect(find.text('fevereiro 2024'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('calendar-day-2024-02-29')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-day-2024-02-30')),
        findsNothing,
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('match-b'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('match-a'))).dy),
      );
      await tap(tester, 'match-a');
      expect(opened, isTrue);
      await tap(tester, 'calendar-day-2024-02-28');
      expect(
        find.text('Nenhuma partida registrada neste dia.'),
        findsOneWidget,
      );
      expect(find.text('Jogo a'), findsNothing);
      await tap(tester, 'calendar-latest-match');
      expect(find.text('Jogo a'), findsOneWidget);
      expect(find.text('Jogo b'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Month navigation crosses years and selected day survives unrelated rebuilds',
    (tester) async {
      await tester.pumpWidget(app(games));
      await tester.pumpAndSettle();
      await tap(tester, 'calendar-previous-month');
      expect(find.text('janeiro 2024'), findsOneWidget);
      await tap(tester, 'calendar-previous-month');
      expect(find.text('dezembro 2023'), findsOneWidget);
      await tap(tester, 'calendar-day-2023-12-31');
      expect(find.text('Jogo c'), findsOneWidget);
      await tester.pumpWidget(
        app([
          for (final r in games) {...r},
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('dezembro 2023'), findsOneWidget);
      expect(find.text('Jogo c'), findsOneWidget);
      await tap(tester, 'calendar-next-month');
      expect(find.text('janeiro 2024'), findsOneWidget);
      await tester.pumpWidget(app([games[1]]));
      await tester.pumpAndSettle();
      expect(find.text('fevereiro 2024'), findsOneWidget);
      expect(find.text('Jogo a'), findsNothing);
      expect(find.text('Jogo b'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final dark in [true, false]) {
    testWidgets(
      'Calendar fits a narrow phone with large text (${dark ? 'dark' : 'light'})',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(app(games, dark: dark, scale: 1.5));
        await tester.pumpAndSettle();
        await tap(tester, 'calendar-day-2024-02-29');
        await tap(tester, 'match-b');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
