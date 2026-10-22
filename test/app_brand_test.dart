import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/StartInitialCareerPage.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileVisuals.dart';
import 'package:mcmanager/utils/AppBrand.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/Components/TeamLogo.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui_preview_fonts.dart';

class _Translations extends AssetLoader {
  const _Translations(this.values);
  final Map<String, dynamic> values;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> translations;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await loadPreviewFonts();
    await GameCatalog.load();
    translations = jsonDecode(
      await rootBundle.loadString('assets/translations/pt_BR.json'),
    ) as Map<String, dynamic>;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget localized(Widget Function(BuildContext) builder) => EasyLocalization(
    supportedLocales: const [Locale('pt', 'BR')],
    startLocale: const Locale('pt', 'BR'),
    fallbackLocale: const Locale('pt', 'BR'),
    path: 'assets/translations',
    assetLoader: _Translations(translations),
    saveLocale: false,
    child: Builder(builder: builder),
  );

  Future<void> settleImages(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        await precacheImage((element.widget as Image).image, element);
      }
    });
    await tester.pumpAndSettle();
  }

  Future<void> capture(
    WidgetTester tester,
    GlobalKey boundary,
    String name,
  ) async {
    final path = Platform.environment['BRAND_PREVIEW_DIR'];
    if (path == null) return;
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('$path/$name.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final dark in [true, false]) {
    testWidgets(
      'Branding keeps career creation usable on a small screen ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        var manager = 0, player = 0;
        await tester.pumpWidget(
          localized(
            (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              theme: dark ? managerDarkTheme : managerLightTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(1.3)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: boundary,
                child: StartInitialCareerPage(
                  onCreateManager: () => manager++,
                  onCreatePlayer: () => player++,
                ),
              ),
            ),
          ),
        );
        await settleImages(tester);
        expect(find.text(AppBrand.name), findsOneWidget);
        final images = tester.widgetList<Image>(find.byType(Image));
        expect(
          images.any(
            (image) =>
                image.image is AssetImage &&
                (image.image as AssetImage).assetName == AppBrand.iconAsset,
          ),
          isTrue,
        );
        await capture(tester, boundary, 'start-${dark ? 'dark' : 'light'}');
        for (final (label, expected) in [
          ('initialPage.startNewManagerCareer', (1, 0)),
          ('initialPage.startNewPlayerCareer', (1, 1)),
        ]) {
          await tester.scrollUntilVisible(
            find.text(label.tr()),
            150,
            scrollable: find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.tap(find.text(label.tr()));
          expect((manager, player), expected);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'Unknown teams and tournaments use generic icons ${dark ? 'dark' : 'light'}',
      (tester) async {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? managerDarkTheme : managerLightTheme,
            home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                body: SizedBox.expand(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Clube sem escudo'),
                        TeamLogo.fromItem(null, size: 90),
                        const SizedBox(height: 20),
                        const Text('Competição sem logo'),
                        const TournamentBadge(
                          version: 'FC26',
                          tournamentId: 'unknown-brand-competition',
                          size: 90,
                        ),
                        const SizedBox(height: 20),
                        const Text('Escudo cadastrado'),
                        const TeamLogo(
                          localAsset: 'assets/images/clubLogos/sao-paulo.png',
                          width: 60,
                          height: 60,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await settleImages(tester);
        final assets = tester
            .widgetList<Image>(find.byType(Image))
            .where((image) => image.image is AssetImage)
            .map((image) => (image.image as AssetImage).assetName)
            .toList();
        expect(assets.where((asset) => asset == AppBrand.iconAsset), isEmpty);
        expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
        expect(find.byIcon(Icons.emoji_events_outlined), findsOneWidget);
        expect(assets, contains('assets/images/clubLogos/sao-paulo.png'));
        await capture(tester, boundary, 'fallback-${dark ? 'dark' : 'light'}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
