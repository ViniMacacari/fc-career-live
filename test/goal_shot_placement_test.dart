import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Common/GoalShotPlacementPage.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui_preview_fonts.dart';

class _Loader extends AssetLoader {
  const _Loader(this.translations);
  final Map<String, dynamic> translations;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      translations;
}

void main() {
  late Map<String, dynamic> translations;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await loadPreviewFonts();
    translations = jsonDecode(
      await rootBundle.loadString('assets/translations/pt_BR.json'),
    ) as Map<String, dynamic>;
  });

  Widget app(Widget child, GlobalKey key, {ThemeData? theme}) =>
      RepaintBoundary(
        key: key,
        child: EasyLocalization(
          supportedLocales: const [Locale('pt', 'BR')],
          startLocale: const Locale('pt', 'BR'),
          fallbackLocale: const Locale('pt', 'BR'),
          path: 'assets/translations',
          assetLoader: _Loader(translations),
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: (theme ?? managerDarkTheme).copyWith(
                splashFactory: NoSplash.splashFactory,
              ),
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: child,
            ),
          ),
        ),
      );

  void viewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  final goal = find.byKey(const ValueKey('shot-goal-surface'));
  final field = find.byKey(const ValueKey('shot-field-surface'));

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    final directory = Platform.environment['PROFILE_PREVIEW_DIR'];
    if (directory == null) return;
    final label = Platform.environment['SHOT_PREVIEW_LABEL'] ?? 'atual';
    Map<String, double> geometry(Finder finder) {
      final rect = tester.getRect(finder);
      return {
        'x': rect.left,
        'y': rect.top,
        'width': rect.width,
        'height': rect.height,
      };
    }

    final positions = {
      'goal': geometry(goal),
      'field': geometry(field),
      'apply': geometry(find.byType(FloatingActionButton)),
    };
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final picture = await boundary.toImage(pixelRatio: 2);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/${name}_$label.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      await File('$directory/${name}_$label.json')
          .writeAsString(jsonEncode(positions));
      picture.dispose();
    });
  }

  for (final size in [const Size(360, 800), const Size(390, 844)]) {
    testWidgets('proporções, posições e coordenadas preservadas em $size', (
      tester,
    ) async {
      viewport(tester, size);
      GoalShotPlacementResult? result;
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await Navigator.push<GoalShotPlacementResult>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const GoalShotPlacementPage(
                          goalLocation: GoalShotLocation(.95, .38),
                          fieldLocation: GoalShotLocation(.45, .87),
                        ),
                      ),
                    ),
                child: const Text('Abrir'),
              ),
            ),
          ),
          key,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      final goalRect = tester.getRect(goal), fieldRect = tester.getRect(field);
      expect(goalRect.left, 32);
      expect(fieldRect.left, goalRect.left);
      expect(goalRect.width, size.width - 64);
      expect(fieldRect.width, goalRect.width);
      expect(goalRect.width / goalRect.height, closeTo(3, .000001));
      expect(fieldRect.width / fieldRect.height, closeTo(1.5, .000001));
      expect(fieldRect.top, greaterThan(goalRect.bottom));
      await capture(tester, key, 'posicionamento_${size.width.toInt()}');
      await tester.tapAt(
        goalRect.topLeft + Offset(goalRect.width * .28, goalRect.height / 3),
      );
      await tester.tapAt(
        fieldRect.topLeft +
            Offset(fieldRect.width * .45, fieldRect.height * .13),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(goal), goalRect);
      expect(tester.getRect(field), fieldRect);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(result!.goalLocation!.x, closeTo(.28, .000001));
      expect(result!.goalLocation!.y, closeTo(1 / 3, .000001));
      expect(result!.fieldLocation!.x, closeTo(.45, .000001));
      expect(result!.fieldLocation!.y, closeTo(.87, .000001));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'pênalti começa na marca correta e Limpar remove ambas as posições',
    (tester) async {
      viewport(tester, const Size(390, 844));
      GoalShotPlacementResult? result;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await Navigator.push<GoalShotPlacementResult>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const GoalShotPlacementPage(isPenalty: true),
                      ),
                    ),
                child: const Text('Abrir'),
              ),
            ),
          ),
          GlobalKey(),
          theme: managerLightTheme,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          '${penaltySpotLocation.x.toStringAsFixed(2)}, ${penaltySpotLocation.y.toStringAsFixed(2)}',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('goalShotMap.clear'.tr()));
      await tester.pumpAndSettle();
      expect(find.text('goalShotMap.noShotSelected'.tr()), findsNWidgets(2));
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(result!.goalLocation, isNull);
      expect(result!.fieldLocation, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  test('coordenadas antigas do campo mantêm a orientação e os limites', () {
    const size = Size(300, 200);
    for (final point in [
      const GoalShotLocation(0, 0),
      const GoalShotLocation(1, 1),
      const GoalShotLocation(.45, .87),
      penaltySpotLocation,
    ]) {
      final stored = goalFieldLocationAt(goalFieldOffset(point, size), size);
      expect(stored.x, closeTo(point.x, .000001));
      expect(stored.y, closeTo(point.y, .000001));
    }
    final outside = goalFieldLocationAt(const Offset(-5, 300), size);
    expect(outside.x, 0);
    expect(outside.y, 0);
    final spot = goalFieldOffset(penaltySpotLocation, size);
    expect(spot.dx, 150);
    expect(spot.dy, closeTo(200 * 11 / (68 * 2 / 3), .000001));
  });
}
