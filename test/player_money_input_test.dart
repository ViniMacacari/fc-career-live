import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/PlayerWidget.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/TeamPage.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ManagerRosterView.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/EditTeamPlayerPage.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileData.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileVisuals.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/ViewPlayerPage.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/GamePlayers.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/ThousandsSeparatorInputFormatter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';

void main() {
  final formatter = ThousandsSeparatorInputFormatter();
  TextEditingValue editing(String text, {int? cursor}) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: cursor ?? text.length),
  );

  test(
    'whole monetary amounts group digits and parse without changing units',
    () {
      for (final (typed, expected, amount) in [
        ('1250000', '1.250.000', 1250000),
        ('50000', '50.000', 50000),
        ('999', '999', 999),
        ('0', '0', 0),
        ('R\$ 1.250.000', '1.250.000', 1250000),
        ('', '', null),
      ]) {
        final result = formatter.formatEditUpdate(editing(''), editing(typed));
        expect(result.text, expected);
        expect(result.selection.baseOffset, expected.length);
        expect(ThousandsSeparatorInputFormatter.parse(result.text), amount);
      }
    },
  );

  test('editing in the middle keeps the cursor next to the same digits', () {
    final result = formatter.formatEditUpdate(
      editing('1.250.000', cursor: 3),
      editing('1.2950.000', cursor: 4),
    );
    expect(result.text, '12.950.000');
    expect(result.selection.baseOffset, 4);
    final selection = formatter.formatEditUpdate(
      editing(''),
      const TextEditingValue(
        text: '1250000',
        selection: TextSelection(baseOffset: 4, extentOffset: 1),
      ),
    );
    expect(
      selection.selection,
      const TextSelection(baseOffset: 5, extentOffset: 1),
    );
  });

  test('backspace and delete across a separator still remove a digit', () {
    final backspace = formatter.formatEditUpdate(
      editing('1.234', cursor: 2),
      editing('1234', cursor: 1),
    );
    expect(backspace.text, '234');
    expect(backspace.selection.baseOffset, 0);
    final delete = formatter.formatEditUpdate(
      editing('1.234', cursor: 1),
      editing('1234', cursor: 1),
    );
    expect(delete.text, '134');
    expect(delete.selection.baseOffset, 1);
    final composing = const TextEditingValue(
      text: '1234',
      composing: TextRange(start: 0, end: 4),
    );
    expect(formatter.formatEditUpdate(editing(''), composing), composing);
  });

  final person = reviewPerson();
  final season = reviewSeason();
  final row = <String, Object?>{
    'id': 'roster',
    'personId': person.id,
    'seasonId': season.id,
    'playerId': 'player',
    'overall': 70,
    'shirtNumber': 7,
    'marketValue': 1250000,
    'isBench': 1,
  };
  final market = <String, Object?>{
    'id': 'market',
    'personId': person.id,
    'customPlayerId': 'player',
    'date': '2026-10-10T00:00:00.000',
    'createdAt': '2026-10-10T10:00:00.000',
    'value': 1250000,
  };
  final contract = <String, Object?>{
    'id': 'contract',
    'personId': person.id,
    'customPlayerId': 'player',
    'date': '2026-10-10T00:00:00.000',
    'createdAt': '2026-10-10T10:00:00.000',
    'wage': 50000,
    'squadRole': 'Importante',
  };
  late Database db;
  late SqlService sql;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory('build/player-input-test-docs').absolute.path,
        );
    await initializeDateFormatting('pt_BR');
    await GameCatalog.load();
    await GamePlayers.load(person.fifaVersion);
    await loadPreviewFonts();
  });
  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    sql = SqlService.withDatabase(db);
    await SqlService.ensureCompatibleSchema(db);
    await SqlService.ensureSeasonClosureSchema(db);
    for (final (column, type) in [
      ('releaseDate', 'TEXT'),
      ('movementApplied', 'INTEGER'),
      ('keepInSquad', 'INTEGER'),
    ]) {
      await db.execute('ALTER TABLE TeamTransferItem ADD COLUMN $column $type');
    }
    await db.insert('Persons', person.toMap());
    await db.insert('Seasons', season.toMap());
    await db.insert('CustomCreatedPlayer', {
      'id': 'player',
      'personId': person.id,
      'name': 'Lucas',
      'positionId': '23',
      'overall': 70,
      'potential': 90,
      'foot': 'Right',
      'realFace': 0,
      'fromRealPlayer': 0,
    });
    await db.insert('TeamPlayer', row);
    await db.insert('MarketValue', market);
    await db.insert('ContractItem', contract);
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
  }

  Finder verticalScroll() => find
      .byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      )
      .last;
  Future<void> showProfile(WidgetTester tester, GlobalKey preview) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: preview,
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Manrope'),
          ),
          home: ViewPlayerPage(
            person: person,
            row: {...row, 'customName': 'Lucas', 'customPositionId': '23'},
            sql: sql,
            profileData: Future.value(
              PlayerProfileData(
                seasons: [season],
                matches: const [],
                overalls: const [],
                marketValues: [market],
                contracts: [contract],
                tournamentNames: const {},
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['PLAYER_INPUT_PREVIEW_DIR'];
    if (directory == null) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'roster updates the visible badge after editing overall in the profile',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await sql.addPlayerHistory('Overall', {
        'id': 'overall',
        'personId': person.id,
        'customPlayerId': 'player',
        'overall': 85,
        'date': '2026-10-01T00:00:00.000',
        'createdAt': '2026-10-01T00:00:00.000',
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: TeamPage(person: person, sql: sql),
        ),
      );
      await settle(tester);
      expect(
        tester
            .widget<ManagerRosterView>(find.byType(ManagerRosterView))
            .gamePlayers,
        isEmpty,
      );
      expect(
        tester.widget<PlayerWidget>(find.byType(PlayerWidget)).overall,
        85,
      );
      await tester.tap(find.byType(PlayerWidget));
      await settle(tester);
      await tester.tap(find.text('Estatísticas'));
      await settle(tester);
      expect(find.text('85'), findsAtLeastNWidgets(1));
      final title = find.text('Classificação geral');
      await tester.scrollUntilVisible(title, 250, scrollable: verticalScroll());
      final panel = find.ancestor(
        of: title,
        matching: find.byType(ProfilePanel),
      );
      final add = find.descendant(of: panel, matching: find.byIcon(Icons.add));
      await Scrollable.ensureVisible(tester.element(add), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, '88');
      await tester.tap(find.text('Salvar'));
      await settle(tester);
      await tester.pageBack();
      await settle(tester);
      expect(
        tester.widget<PlayerWidget>(find.byType(PlayerWidget)).overall,
        88,
      );
      expect((await db.query('TeamPlayer')).single['overall'], 70);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('market history opens formatted and saves the edited integer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showProfile(tester, GlobalKey());
    final title = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.data == 'Valor de mercado' &&
          widget.style?.fontSize == 16,
    );
    await tester.scrollUntilVisible(title, 400, scrollable: verticalScroll());
    final panel = find.ancestor(of: title, matching: find.byType(ProfilePanel));
    await tester.tap(
      find.descendant(of: panel, matching: find.byIcon(Icons.list)),
    );
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('1.250.000 €'),
      ),
    );
    await settle(tester);
    final input = find.byType(TextField).first;
    expect(tester.widget<TextField>(input).controller!.text, '1.250.000');
    await tester.enterText(input, '2500000');
    expect(tester.widget<TextField>(input).controller!.text, '2.500.000');
    await capture(tester, 'market-input');
    await tester.tap(find.text('Salvar'));
    await settle(tester);
    expect((await db.query('MarketValue')).single['value'], 2500000);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'salary editing preformats, accepts typing and keeps the contract',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await showProfile(tester, GlobalKey());
      final panel = find.ancestor(
        of: find.text('Contrato atual'),
        matching: find.byType(ProfilePanel),
      );
      await tester.scrollUntilVisible(panel, 300, scrollable: verticalScroll());
      await tester.tap(
        find.descendant(of: panel, matching: find.byIcon(Icons.edit_outlined)),
      );
      await settle(tester);
      final input = find.byType(TextField).first;
      expect(tester.widget<TextField>(input).controller!.text, '50.000');
      await tester.enterText(input, '75000');
      expect(tester.widget<TextField>(input).controller!.text, '75.000');
      await capture(tester, 'salary-input');
      await tester.tap(find.text('Salvar'));
      await settle(tester);
      final saved = (await db.query('ContractItem')).single;
      expect(saved['wage'], 75000);
      expect(saved['squadRole'], 'Importante');
      expect(saved['id'], 'contract');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('season configuration formats the initial market value', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: EditTeamPlayerPage(person: person, row: row, sql: sql),
      ),
    );
    await settle(tester);
    final textField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Valor de mercado (opcional)',
    );
    await tester.scrollUntilVisible(
      textField,
      400,
      scrollable: verticalScroll(),
    );
    expect(tester.widget<TextField>(textField).controller!.text, '1.250.000');
    await tester.enterText(textField, '3700000');
    expect(tester.widget<TextField>(textField).controller!.text, '3.700.000');
    await tester.scrollUntilVisible(
      find.text('Salvar'),
      250,
      scrollable: verticalScroll(),
    );
    await tester.tap(find.text('Salvar'));
    await settle(tester);
    final saved = (await db.query('TeamPlayer')).single;
    expect(saved['marketValue'], 3700000);
    expect(saved['overall'], 70);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
