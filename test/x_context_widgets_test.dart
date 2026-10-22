import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Twitter/TwitterSchema.dart';
import 'package:mcmanager/Twitter/TwitterStore.dart';
import 'package:mcmanager/Twitter/TwitterStyle.dart';
import 'package:mcmanager/Twitter/XContextButton.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'ui_preview_fonts.dart';

void main() {
  late Database db;
  late TwitterStore store;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
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
  test(
    'Older Twitter settings migrate context without changing other preferences',
    () async {
      await db.execute('ALTER TABLE TwitterSettings DROP COLUMN customContext');
      await db.insert('TwitterSettings', {
        'personId': 'career',
        'postCount': 9,
        'enabled': 0,
      });
      expect(await store.customContext('career'), isEmpty);
      await store.saveCustomContext('career', 'Contexto adicional');
      expect((await store.preferences('career')).postCount, 9);
      expect((await store.preferences('career')).enabled, isFalse);
      await createTwitterSchema(db);
      expect(await store.customContext('career'), 'Contexto adicional');
    },
  );
  testWidgets(
    'Context remains editable and save is reachable with a keyboard and large text on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          theme: managerDarkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: XTheme(
            builder: (_) => Scaffold(
              appBar: AppBar(
                title: const Text('X'),
                actions: [XContextButton(personId: 'career', store: store)],
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('x-ai-context')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('x-ai-context-input')),
        'O capitão se despede.',
      );
      final save = find.byKey(const ValueKey('x-ai-context-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(() => store.customContext('career')),
        'O capitão se despede.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final dark in [true, false]) {
    testWidgets(
      'Context can be added, edited, cancelled and removed in ${dark ? 'dark' : 'light'} X UI',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? managerDarkTheme : managerLightTheme,
            builder: (context, child) =>
                RepaintBoundary(key: boundary, child: child!),
            home: XTheme(
              builder: (_) => Scaffold(
                appBar: AppBar(
                  title: const Text('X'),
                  actions: [XContextButton(personId: 'career', store: store)],
                ),
                body: ListView(
                  children: [
                    XContextButton(
                      personId: 'career',
                      store: store,
                      showPanel: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        Future<void> settle() async {
          for (var i = 0; i < 2; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 80)),
            );
            await tester.pumpAndSettle();
          }
        }

        await settle();
        expect(find.text('Adicionar contexto'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('x-ai-context-edit')));
        await settle();
        final input = find.byKey(const ValueKey('x-ai-context-input'));
        await tester.enterText(input, 'Hoje é o último jogo da temporada.');
        await tester.tap(find.byKey(const ValueKey('x-ai-context-save')));
        await settle();
        expect(
          await tester.runAsync(() => store.customContext('career')),
          'Hoje é o último jogo da temporada.',
        );
        expect(
          find.byTooltip('Contexto ativo · editar ou remover'),
          findsOneWidget,
        );
        expect(find.text('Hoje é o último jogo da temporada.'), findsOneWidget);
        expect(find.text('Editar'), findsOneWidget);
        expect(find.text('Remover'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('x-ai-context-edit')));
        await settle();
        expect(
          tester.widget<TextField>(input).controller!.text,
          'Hoje é o último jogo da temporada.',
        );
        final directory = Platform.environment['PROFILE_PREVIEW_DIR'];
        if (directory != null) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(directory).create(recursive: true);
            await File('$directory/x-context-${dark ? 'dark' : 'light'}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.enterText(input, 'Mudança que não quero salvar.');
        await tester.tap(find.text('Cancelar'));
        await settle();
        expect(
          await tester.runAsync(() => store.customContext('career')),
          'Hoje é o último jogo da temporada.',
        );
        await tester.tap(find.byKey(const ValueKey('x-ai-context')));
        await settle();
        await tester.enterText(input, 'Nosso capitão se despede.');
        await tester.tap(find.byKey(const ValueKey('x-ai-context-save')));
        await settle();
        expect(
          await tester.runAsync(() => store.customContext('career')),
          'Nosso capitão se despede.',
        );
        await tester.tap(find.byKey(const ValueKey('x-ai-context-clear')));
        await settle();
        expect(
          await tester.runAsync(() => store.customContext('career')),
          isEmpty,
        );
        expect(find.byTooltip('Adicionar contexto para a IA'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
