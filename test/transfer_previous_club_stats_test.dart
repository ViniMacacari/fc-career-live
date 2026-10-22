import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/TeamTransfers/CreateTeamTransferPage.dart';
import 'package:mcmanager/ManagerCareer/TeamTransfers/SelectTransferPlayerPage.dart';
import 'package:mcmanager/ManagerCareer/TeamTransfers/TransferPreviousClubStatsDialog.dart';
import 'package:mcmanager/models/TransferPreviousClubStats.dart';
import 'package:mcmanager/utils/BackupService.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';
import 'backup_storage_fixture.dart';

class _Translations extends AssetLoader {
  const _Translations(this.values);
  final Map<String, dynamic> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final person = reviewPerson();
  final player = <String, Object?>{
    'id': 'incoming',
    'personId': person.id,
    'name': 'Pedro Silva',
    'positionId': '23',
    'overall': 80,
    'potential': 82,
    'foot': 'right',
    'realFace': 0,
    'fromRealPlayer': 0,
  };
  final stats = TransferPreviousClubStats(
    asOfDate: DateTime(2026, 7, 1),
    matches: 15,
    goals: 14,
    assists: 5,
    averageRating: 7.8,
    notes: 'Titular, vinha em boa fase.',
  );
  late GameCatalog catalog;
  late Map<String, dynamic> translations;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    mockBackupStorage();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory('build/previous-club-test-docs').absolute.path,
        );
    await EasyLocalization.ensureInitialized();
    translations = jsonDecode(
      await rootBundle.loadString('assets/translations/pt_BR.json'),
    ) as Map<String, dynamic>;
    await loadPreviewFonts();
    catalog = await GameCatalog.load();
  });

  Future<Database> database() async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('CREATE TABLE Settings(activePersonId TEXT)');
    await SqlService.ensureCompatibleSchema(db);
    await SqlService.ensureSeasonClosureSchema(db);
    for (final column in [
      'releaseDate TEXT',
      'movementApplied INTEGER',
      'keepInSquad INTEGER',
    ]) {
      await db.execute('ALTER TABLE TeamTransferItem ADD COLUMN $column');
    }
    await db.insert('Persons', person.toMap());
    await db.insert('Seasons', reviewSeason().toMap());
    await db.insert('CustomCreatedPlayer', player);
    return db;
  }

  Map<String, Object?> purchase() => {
    'id': 'purchase',
    'personId': person.id,
    'seasonId': 's2026',
    'playerInstanceId': 'incoming',
    'type': 'buy',
    'fromTeamId': 'destination',
    'toTeamId': person.teamId,
    'toLeagueId': person.leagueId,
    'date': stats.asOfDate.toIso8601String(),
    'previousClubStats': stats.encode(),
  };

  test('Optional fields stay unknown; explicit zero and dated snapshots round-trip', () {
    final decoded = TransferPreviousClubStats.decode(stats.encode())!;
    expect(decoded.toMap(), stats.toMap());
    expect(decoded.availableAt(DateTime(2026, 6, 30)), false);
    expect(decoded.availableAt(DateTime(2026, 7, 1, 12)), true);
    expect(
      decoded.summary('Clube anterior'),
      contains('15 jogos, 14 gols, 5 assistências'),
    );
    final partial = TransferPreviousClubStats(
      asOfDate: stats.asOfDate,
      goals: 0,
    );
    expect(TransferPreviousClubStats.decode(partial.encode())!.goals, 0);
    expect(partial.toMap().containsKey('matches'), false);
    expect(
      TransferPreviousClubStats.decode(
        TransferPreviousClubStats(asOfDate: stats.asOfDate).encode(),
      ),
      isNull,
    );
    for (final bad in [
      null,
      '',
      '{}',
      '[]',
      '{"asOfDate":"2026-07-01","matches":-1}',
      '{"asOfDate":"2026-07-01","matches":1.5}',
      '{"asOfDate":"2026-07-01","averageRating":11}',
    ]) {
      expect(TransferPreviousClubStats.decode(bad), isNull);
    }
  });

  test('Migration preserves legacy transfers and is idempotent', () async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    await db.execute(
      'CREATE TABLE TeamTransferItem(id TEXT PRIMARY KEY, date TEXT)',
    );
    await db.insert('TeamTransferItem', {'id': 'legacy', 'date': '2026-01-01'});
    await SqlService.ensureTransferPreviousClubStatsSchema(db);
    await SqlService.ensureTransferPreviousClubStatsSchema(db);
    expect((await db.query('TeamTransferItem')).single, {
      'id': 'legacy',
      'date': '2026-01-01',
      'previousClubStats': null,
    });
  });

  test('Save, edit and backup preserve prior-club data without fictitious performances', () async {
    final db = await database();
    addTearDown(db.close);
    final sql = SqlService.withDatabase(db);
    await sql.saveTeamTransfer(purchase());
    final edit = purchase()..remove('previousClubStats');
    edit['transferValue'] = 20000000;
    await sql.saveTeamTransfer(edit, update: true);
    final saved = (await db.query('TeamTransferItem')).single;
    expect(saved['previousClubStats'], stats.encode());
    expect(await db.query('ManagerFixturePlayerPerformances'), isEmpty);
    final backup = await BackupService(database: () async => db)
        .generateBackup(includeImages: false);
    final restored = await database();
    addTearDown(restored.close);
    final report = await BackupService(database: () async => restored)
        .restoreBackup(backup);
    expect(report.skippedRows, 0);
    expect(report.skippedTables, isEmpty);
    expect((await restored.query('TeamTransferItem')).single, saved);
    expect(await restored.query('ManagerFixturePlayerPerformances'), isEmpty);
  });

  Widget app(Widget home, {double scale = 1, GlobalKey? capture}) =>
      EasyLocalization(
        supportedLocales: const [Locale('pt', 'BR')],
        startLocale: const Locale('pt', 'BR'),
        path: 'assets/translations',
        assetLoader: _Translations(translations),
        saveLocale: false,
        child: Builder(
          builder: (context) => RepaintBoundary(
            key: capture,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: managerDarkTheme,
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: home,
            ),
          ),
        ),
      );
  void viewport(WidgetTester tester, double width, double height) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> preview(WidgetTester tester, GlobalKey key, String name) async {
    final path = Platform.environment['PREVIOUS_CLUB_PREVIEW_DIR'];
    if (path == null) return;
    await tester.pump();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(path).create(recursive: true);
      await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final size in [const Size(430, 932), const Size(320, 640)]) {
    testWidgets(
      'Dialog fits ${size.width.toInt()}px, validates and keeps keyboard focus',
      (tester) async {
        viewport(tester, size.width, size.height);
        final capture = GlobalKey();
        TransferPreviousClubStatsResult? result;
        await tester.pumpWidget(
          app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  child: const Text('Comprar'),
                  onPressed: () async {
                    result = await showTransferPreviousClubStats(
                      context,
                      playerName: 'Pedro Silva',
                      clubName: 'Flamengo',
                      season: reviewSeason(),
                      date: stats.asOfDate,
                      initial: stats,
                    );
                  },
                ),
              ),
            ),
            scale: size.width == 320 ? 1.3 : 1,
            capture: capture,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Comprar'));
        await tester.pumpAndSettle();
        await preview(tester, capture, 'previous-club-${size.width.toInt()}');
        final matches = find.byKey(const ValueKey('previous-club-matches'));
        await tester.ensureVisible(matches);
        await tester.tap(matches);
        tester.view.viewInsets = FakeViewPadding(bottom: 240);
        await tester.pumpAndSettle();
        final field = tester.widget<EditableText>(
          find.descendant(of: matches, matching: find.byType(EditableText)),
        );
        expect(field.focusNode.hasFocus, true);
        await tester.enterText(matches, '0');
        await tester.tap(
          find.byKey(const ValueKey('confirm-previous-club-stats')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Confira o número de jogos.'), findsWidgets);
        expect(result, isNull);
        await tester.ensureVisible(matches);
        await tester.enterText(matches, '15');
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('confirm-previous-club-stats')),
        );
        await tester.pumpAndSettle();
        expect(result!.stats!.toMap(), stats.toMap());
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final action in ['provide', 'skip', 'cancel']) {
    testWidgets(
      'Purchase popup $action happens before commit and notification',
      (tester) async {
        viewport(tester, 430, 932);
        final db = (await tester.runAsync(database))!;
        addTearDown(db.close);
        final sql = SqlService.withDatabase(db);
        var notified = 0;
        TransferPreviousClubStats? notifiedStats;
        Map<String, Object?>? existing;
        await tester.pumpWidget(
          app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  child: const Text('Transferência'),
                  onPressed: () => Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreateTeamTransferPage(
                        person: person,
                        season: reviewSeason(),
                        roster: const [],
                        names: const {},
                        sql: sql,
                        existing: existing,
                        initialPlayer: TransferPlayerChoice(
                          id: 'incoming',
                          name: 'Pedro Silva',
                          custom: player,
                        ),
                        transferNotifier: (_, id) async {
                          notified++;
                          final row = (await db.query(
                            'TeamTransferItem',
                            where: 'id = ?',
                            whereArgs: [id],
                          )).single;
                          notifiedStats = TransferPreviousClubStats.decode(
                            row['previousClubStats'],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Transferência'));
        await settle(tester);
        await tester.tap(find.text('Transferido De'));
        await tester.pumpAndSettle();
        final from = catalog
            .teams(person.fifaVersion)
            .firstWhere(
              (t) => t.leagueId == person.leagueId && t.id != person.teamId,
            );
        await tester.enterText(find.byType(TextField), from.label);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, from.label));
        await tester.pumpAndSettle();
        final save = find.byKey(const ValueKey('save-team-transfer'));
        await tester.dragUntilVisible(
          save,
          find.byType(ListView),
          const Offset(0, -200),
        );
        await tester.tap(save);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(TransferPreviousClubStatsDialog), findsOneWidget);
        expect(
          await tester.runAsync(() => db.query('TeamTransferItem')),
          isEmpty,
        );
        expect(notified, 0);
        if (action == 'cancel') {
          await tester.tap(find.byTooltip('Cancelar'));
          await tester.pumpAndSettle();
          expect(find.byType(CreateTeamTransferPage), findsOneWidget);
          expect(
            await tester.runAsync(() => db.query('TeamTransferItem')),
            isEmpty,
          );
          expect(notified, 0);
        } else {
          if (action == 'provide') {
            for (final entry in {
              'matches': '15',
              'goals': '14',
              'assists': '5',
              'rating': '7,8',
              'notes': 'Titular, vinha em boa fase.',
            }.entries) {
              final field = find.byKey(ValueKey('previous-club-${entry.key}'));
              await tester.ensureVisible(field);
              await tester.enterText(field, entry.value);
            }
            await tester.tap(
              find.byKey(const ValueKey('confirm-previous-club-stats')),
            );
          } else {
            await tester.tap(
              find.byKey(const ValueKey('skip-previous-club-stats')),
            );
          }
          await settle(tester);
          expect(find.byType(CreateTeamTransferPage), findsNothing);
          expect(notified, 1);
          final row = (await tester.runAsync(
            () => db.query('TeamTransferItem'),
          ))!.single;
          expect(
            await tester.runAsync(
              () => db.query('ManagerFixturePlayerPerformances'),
            ),
            isEmpty,
          );
          if (action == 'provide') {
            expect(notifiedStats!.matches, 15);
            expect(notifiedStats!.goals, 14);
            expect(notifiedStats!.averageRating, 7.8);
            existing = row;
            await tester.tap(find.text('Transferência'));
            await settle(tester);
            await tester.tap(
              find.byKey(const ValueKey('edit-previous-club-stats')),
            );
            await tester.pumpAndSettle();
            final field = find.byKey(const ValueKey('previous-club-goals'));
            expect(tester.widget<TextFormField>(field).controller!.text, '14');
            await tester.enterText(field, '16');
            await tester.tap(
              find.byKey(const ValueKey('confirm-previous-club-stats')),
            );
            await tester.pumpAndSettle();
            await tester.dragUntilVisible(
              save,
              find.byType(ListView),
              const Offset(0, -200),
            );
            await tester.tap(save);
            await settle(tester);
            expect(find.byType(TransferPreviousClubStatsDialog), findsNothing);
            expect(find.byType(CreateTeamTransferPage), findsNothing);
            expect(notified, 2);
            expect(notifiedStats!.goals, 16);
          } else {
            expect(row['previousClubStats'], isNull);
            expect(notifiedStats, isNull);
          }
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 11));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      },
    );
  }
}
