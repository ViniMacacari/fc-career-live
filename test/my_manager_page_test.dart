import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/MyManager/MyManagerPage.dart';
import 'package:mcmanager/models/Person.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:sqflite/sqflite.dart';

import 'ui_preview_fonts.dart';

void main() {
  final person = Person(
    id: 'career',
    name: 'Carreira no Milan',
    category: PersonCategory.manager,
    fifaVersion: 'FC26',
    leagueId: '1',
    teamId: '1',
    nationalityId: '54',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  String? saved;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadPreviewFonts();
    databaseFactory = databaseFactorySqflitePlugin;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.tekartik.sqflite'), (
          call,
        ) async {
          final args = call.arguments is Map ? call.arguments as Map : const {};
          final sql = args['sql']?.toString() ?? '';
          switch (call.method) {
            case 'getDatabasesPath':
              return Directory('build/test-db').absolute.path;
            case 'openDatabase':
              return {'id': 1};
            case 'query':
              if (sql.contains('user_version')) {
                return [
                  {'user_version': 24},
                ];
              }
              if (sql.contains('managerProfile')) {
                return [
                  {
                    'managerProfile': jsonEncode({
                      'name': 'João Silva',
                      'nationality': 'Brasileiro',
                      'birthdate': '12/05/1980',
                      'style': 'Posse e pressão alta',
                      'biography': 'Futebol ofensivo e formação de jovens.',
                    }),
                  },
                ];
              }
              if (sql.contains('SELECT date')) {
                return [
                  {'date': '2026-10-03T20:00:00'},
                ];
              }
              return <Map<String, Object?>>[];
            case 'update':
              if (sql.contains('managerProfile')) {
                saved = (args['arguments'] as List).first as String;
              }
              return 1;
            case 'execute':
              return null;
            default:
              return null;
          }
        });
  });
  for (final size in [const Size(360, 640), const Size(390, 844)]) {
    testWidgets('coach rounded fields, birth calendar and save in $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: managerDarkTheme.copyWith(
            splashFactory: NoSplash.splashFactory,
          ),
          home: RepaintBoundary(
            key: key,
            child: MyManagerPage(person: person),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('João Silva'), findsOneWidget);
      final birth = find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == '12/05/1980',
      );
      await tester.ensureVisible(birth);
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.descendant(of: birth, matching: find.byType(TextField)),
      );
      expect(field.readOnly, isTrue);
      expect(
        (field.decoration!.enabledBorder as OutlineInputBorder).borderRadius,
        BorderRadius.circular(16),
      );
      await tester.tap(birth);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(
        tester
            .widget<DatePickerDialog>(find.byType(DatePickerDialog))
            .initialDate,
        DateTime(1980, 5, 12),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Marcos Silva');
      await tester.tap(find.text('Salvar perfil'));
      await tester.pumpAndSettle();
      expect(jsonDecode(saved!)['name'], 'Marcos Silva');
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['PROFILE_PREVIEW_DIR'];
      if (directory != null) {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(seconds: 6));
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File('$directory/my-manager-${size.width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
