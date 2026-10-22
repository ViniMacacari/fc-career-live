import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Common/StagePicker.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/competitions/CompetitionFormats.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  for (final (last, next) in [
    ('Rodada 1', 'Rodada 2'),
    ('Fase de grupos · Rodada 6', 'Fase de grupos · Rodada 7'),
    ('Quartas de final · Ida', 'Quartas de final · Volta'),
    ('Quartas de final · Volta', 'Semifinal'),
  ]) {
    test('Unknown format suggests $next after $last', () async {
      final db = await SqlService.openCareerDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.insert('Persons', reviewPerson().toMap());
      await db.insert('Seasons', reviewSeason().toMap());
      for (final (i, stage, tournament, season, date) in [
        (0, last, 'custom', 's2026', '2026-03-01'),
        (1, 'Rodada 90', 'other', 's2026', '2026-03-02'),
        (2, 'Rodada 91', 'custom', 's2025', '2026-03-03'),
        (3, 'Rodada 92', 'custom', 's2026', '2026-04-01'),
        (4, 'Rodada 93', 'custom', 's2026', '2026-03-04'),
      ]) {
        await db.insert('ManagerFixtures', {
          ...reviewFixture(i),
          'stage': stage,
          'tournamentId': tournament,
          'seasonId': season,
          'date': date,
        });
      }
      expect(
        await suggestStage(
          reviewPerson(),
          tournamentId: 'custom',
          seasonId: 's2026',
          format: const CompetitionFormat.open(),
          date: DateTime(2026, 3, 10),
          excludeFixtureId: 'f4',
          sql: SqlService.withDatabase(db),
        ),
        next,
      );
    });
  }

  test('Empty custom competition starts at round one and known rules keep their limits', () async {
    expect(
      await suggestStage(
        reviewPerson(),
        tournamentId: 'custom',
        seasonId: null,
        format: const CompetitionFormat.open(),
      ),
      'Rodada 1',
    );
    expect(
      CompetitionFormat.of('86', 'FC26').next(const MatchStage.round(38)),
      isNull,
    );
    expect(const CompetitionFormat.open().parse('Rodada 38'), isNull);
    expect(const CompetitionFormat.open().structured, isFalse);
  });

  for (final (kind, expected) in [
    (CompetitionKind.league, 'Rodada 2'),
    (CompetitionKind.groups, 'Fase de grupos · Rodada 2'),
    (CompetitionKind.knockout, 'Quartas de final'),
  ]) {
    testWidgets('Manual stage picker offers $kind and saves its label', (
      tester,
    ) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showStagePicker(
                    context,
                    format: const CompetitionFormat.open(),
                    current: '',
                    competition: 'Minha copa',
                    suggested: 'Rodada 2',
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      tester
          .widget<DropdownButtonFormField<CompetitionKind>>(
            find.byType(DropdownButtonFormField<CompetitionKind>),
          )
          .onChanged!(kind);
      await tester.pumpAndSettle();
      final target = kind == CompetitionKind.knockout
          ? 'Quartas de final'
          : '2';
      await tester.ensureVisible(find.text(target).last);
      await tester.tap(find.text(target).last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        expected,
      );
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(result, expected);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Known competition keeps its official rounds; free text remains editable',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showStagePicker(
                  context,
                  format: CompetitionFormat.of('86', 'FC26'),
                  current: 'Rodada 37',
                  competition: 'Brasileirão',
                  suggested: 'Rodada 38',
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(
        find.byType(DropdownButtonFormField<CompetitionKind>),
        findsNothing,
      );
      expect(find.text('38'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Rodada especial');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Rodada especial',
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
