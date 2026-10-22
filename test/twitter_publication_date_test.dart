import 'package:mcmanager/utils/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Twitter/TwitterPublicationDate.dart';

void main() {
  test('selected publication day overrides the default match day', () {
    expect(
      resolveTwitterPublicationDate(
        selected: DateTime(2028, 2, 3),
        latestFixture: DateTime(2028, 1, 15, 20, 30),
      ),
      DateTime(2028, 2, 3, 20, 30),
    );
    expect(
      resolveTwitterPublicationDate(latestFixture: DateTime(2028, 1, 15)),
      DateTime(2028, 1, 15),
    );
  });
  test('reply keeps the parent time and cannot precede the original', () {
    final parent = DateTime(2028, 1, 15, 22);
    expect(
      resolveTwitterPublicationDate(
        parent: parent,
        selected: DateTime(2028, 1, 15),
      ),
      parent,
    );
    expect(
      resolveTwitterPublicationDate(
        parent: parent,
        selected: DateTime(2028, 1, 16),
      ),
      DateTime(2028, 1, 16, 22),
    );
    expect(
      () => resolveTwitterPublicationDate(
        parent: parent,
        selected: DateTime(2028, 1, 14),
      ),
      throwsFormatException,
    );
  });
  testWidgets('publication day opens a calendar and applies the choice', (
    tester,
  ) async {
    DateTime? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: managerDarkTheme.copyWith(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: TwitterPublicationDateField(
            date: DateTime(2028, 1, 15),
            onChanged: (date) => selected = date,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('publication-date')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(
      tester
          .widget<DatePickerDialog>(find.byType(DatePickerDialog))
          .initialDate,
      DateTime(2028, 1, 15),
    );
    await tester.tap(find.text('20').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(selected, DateTime(2028, 1, 20));
    expect(tester.takeException(), isNull);
  });
}
