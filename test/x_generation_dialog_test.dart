import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Twitter/TwitterModels.dart';
import 'package:mcmanager/Twitter/TwitterSchema.dart';
import 'package:mcmanager/Twitter/TwitterStore.dart';
import 'package:mcmanager/Twitter/TwitterStyle.dart';
import 'package:mcmanager/Twitter/XGenerationDialog.dart';
import 'package:mcmanager/utils/AppColors.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final person = reviewPerson();
  late Database db;
  late TwitterStore store;
  late GameCatalog catalog;
  setUpAll(() async {
    catalog = await GameCatalog.load();
    await loadPreviewFonts();
  });
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await createTwitterSchema(db);
    store = TwitterStore.withDatabase(db);
  });
  tearDown(() async {
    store.dispose();
    await db.close();
  });

  for (final width in [360.0, 430.0]) {
    testWidgets(
      'Custom X generation fits $width and prevents duplicate official posts',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() async {
          await store.saveAccount(
            TwitterAccount(
              id: 'other',
              personId: person.id,
              name: 'Adversário',
              handle: 'adversario',
              kind: TwitterAccountKind.club,
            ),
          );
          await db.insert('TwitterPosts', {
            'id': '${person.id}:opponentOfficial:f0',
            'personId': person.id,
            'accountId': 'other',
            'fixtureId': 'f0',
            'text': 'Resultado do jogo',
            'postedAt': '2026-01-10',
            'createdAt': '2026-01-10',
          });
        });
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: managerDarkTheme,
            home: RepaintBoundary(
              key: boundary,
              child: XTheme(
                builder: (_) => Scaffold(
                  body: XGenerationDialog(
                    person: person,
                    store: store,
                    settings: const TwitterPreferences(),
                    fixtures: [reviewFixture(0)],
                    catalog: catalog,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.byType(XGenerationDialog)))
              .colorScheme
              .primary,
          AppColors.xDark.accent,
        );
        await tester.tap(find.byKey(const ValueKey('x-generation-match')));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('(3 × 1)').last);
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        final opponent = tester.widget<CheckboxListTile>(
          find.byKey(const ValueKey('x-generation-opponent')),
        );
        expect(opponent.onChanged, isNull);
        expect(find.text('Já publicado nesta partida'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final output = Platform.environment['FC_SCORE_PREVIEW_DIR'];
        if (output != null) {
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(output).create(recursive: true);
            await File('$output/x-custom-${width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
