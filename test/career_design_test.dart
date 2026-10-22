import 'package:mcmanager/utils/AppColors.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Common/StreaksPage.dart';
import 'package:mcmanager/Settings/SettingsPage.dart';
import 'package:mcmanager/Settings/CustomConfiguration/CustomConfiguration.dart';
import 'package:mcmanager/StartInitialCareerPage.dart';
import 'package:mcmanager/Trophies/ViewTrophyPage.dart';
import 'package:mcmanager/Twitter/TwitterStyle.dart';
import 'package:mcmanager/models/Person.dart';
import 'package:mcmanager/utils/Components/CareerPageWidgets.dart';
import 'package:mcmanager/utils/Providers/StateProvider.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
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
    await GameCatalog.load();
    translations = jsonDecode(
      await rootBundle.loadString('assets/translations/pt_BR.json'),
    ) as Map<String, dynamic>;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Person person(PersonCategory category) => Person(
    id: 'career',
    name: 'Minha carreira',
    category: category,
    fifaVersion: 'FC26',
    teamId: 'club',
    leagueId: 'league',
    nationalityId: '54',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  Widget app(Widget home, {ThemeData? theme, GlobalKey? captureKey}) =>
      RepaintBoundary(
        key: captureKey,
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
              home: home,
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

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    final directory = Platform.environment['PROFILE_PREVIEW_DIR'];
    if (directory == null) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final picture = await boundary.toImage(pixelRatio: 2);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
  }

  testWidgets('início: os dois modos continuam acessíveis em celular pequeno', (
    tester,
  ) async {
    viewport(tester, const Size(360, 640));
    var managers = 0, players = 0;
    final key = GlobalKey();
    await tester.pumpWidget(
      app(
        StartInitialCareerPage(
          onCreateManager: () => managers++,
          onCreatePlayer: () => players++,
        ),
        captureKey: key,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('initialPage.startNewManagerCareer'.tr()));
    await tester.tap(find.text('initialPage.startNewPlayerCareer'.tr()));
    expect((managers, players), (1, 1));
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'inicio_renovado');
    await tester.scrollUntilVisible(
      find.text('Como funciona'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Como funciona'));
    await tester.pumpAndSettle();
    expect(find.text('initialPage.description'.tr()), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [true, false]) {
    testWidgets(
      'configurações: navegação e preferência persistida, ${dark ? 'escuro' : 'claro'}',
      (tester) async {
        viewport(tester, const Size(390, 844));
        final state = AppStateNotifier();
        addTearDown(state.dispose);
        final key = GlobalKey();
        await tester.pumpWidget(
          app(
            SettingsPage(
              appState: state,
              configurationHubBuilder: (_) => const ConfigurationHub(),
            ),
            theme: dark ? managerDarkTheme : managerLightTheme,
            captureKey: key,
          ),
        );
        await tester.pumpAndSettle();
        await capture(
          tester,
          key,
          'configuracoes_${dark ? 'escuro' : 'claro'}',
        );
        await tester.tap(find.text('settings.appearance'.tr()));
        await tester.pumpAndSettle();
        expect(find.text('Seu estilo de jogo'), findsOneWidget);
        await tester.tap(find.text('settings.dark'.tr()));
        await tester.pumpAndSettle();
        expect(state.themeMode, ThemeMode.dark);
        expect(
          (await SharedPreferences.getInstance()).getString(themeModePrefsKey),
          'dark',
        );
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text('customConfiguration.configurationHub'.tr()),
        );
        await tester.pumpAndSettle();
        expect(find.text('Seu futebol, do seu jeito'), findsOneWidget);
        expect(
          find.text('customConfiguration.customContent'.tr()),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        if (dark) await capture(tester, key, 'conteudo_personalizado');
      },
    );
  }

  final rows = [
    for (final (index, game) in [
      (2, 0, 'home', 1, 0),
      (1, 0, 'away', 1, 1),
      (1, 1, 'home', 0, 1),
      (0, 2, 'home', 0, 0),
      (3, 0, 'home', 1, 0),
    ].indexed)
      <String, Object?>{
        'id': 'f$index',
        'playerTeamScore': game.$1,
        'oppositeTeamScore': game.$2,
        'location': game.$3,
        'goalsCount': game.$4,
        'assistsCount': game.$5,
      },
  ].reversed.toList();

  void metric(WidgetTester tester, String labelKey, int value) {
    final tile = find.widgetWithText(CareerMetricTile, labelKey.tr());
    expect(tile, findsOneWidget);
    expect(
      find.descendant(of: tile, matching: find.text('$value')),
      findsOneWidget,
    );
  }

  testWidgets(
    'sequências: abas preservam os recordes gerais, de casa e de gols',
    (tester) async {
      viewport(tester, const Size(360, 640));
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          StreaksPage(
            person: person(PersonCategory.manager),
            fixtures: Future.value(rows),
          ),
          captureKey: key,
        ),
      );
      await tester.pumpAndSettle();
      metric(tester, 'stats.longestWinStreak', 2);
      metric(tester, 'stats.longestUnbeatenStreak', 3);
      expect(find.text('stats.longestWinStreakAtHome'.tr()), findsNothing);
      await capture(tester, key, 'sequencias_geral');
      await tester.tap(find.text('Em casa'));
      await tester.pumpAndSettle();
      metric(tester, 'stats.longestWinStreakAtHome', 1);
      metric(tester, 'stats.longestUnbeatenStreakAtHome', 2);
      await tester.tap(find.text('Produção'));
      await tester.pumpAndSettle();
      metric(tester, 'stats.longestScoringStreak', 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sequências do jogador: gols e assistências em sua própria aba', (
    tester,
  ) async {
    viewport(tester, const Size(360, 640));
    await tester.pumpWidget(
      app(
        StreaksPage(
          person: person(PersonCategory.player),
          fixtures: Future.value(rows),
        ),
        theme: playerDarkTheme,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Produção'));
    await tester.pumpAndSettle();
    metric(tester, 'stats.longestScoringStreak', 2);
    metric(tester, 'stats.longestAssistingStreak', 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('troféu: informações e ações continuam disponíveis', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    final key = GlobalKey();
    await tester.pumpWidget(
      app(
        ViewTrophyPage(
          person: person(PersonCategory.manager),
          awardName: 'Campeão brasileiro',
          teamName: 'São Paulo',
          trophy: const {
            'id': 'trophy',
            'count': 2,
            'date': '2026-09-30',
            'description': 'Uma campanha histórica.',
          },
        ),
        captureKey: key,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Registro'));
    await tester.pumpAndSettle();
    expect(find.text('30/9/2026'), findsOneWidget);
    expect(find.text('Uma campanha histórica.'), findsOneWidget);
    expect(find.byTooltip('common.edit'.tr()), findsOneWidget);
    await capture(tester, key, 'detalhes_trofeu');
    await tester.tap(find.byTooltip('common.remove'.tr()));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('common.cancel'.tr()));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ViewTrophyPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [true, false]) {
    testWidgets(
      'X acompanha o modo com sua paleta ${dark ? 'escuro' : 'claro'}',
      (tester) async {
        late ThemeData inside;
        final selected = dark ? managerDarkTheme : managerLightTheme;
        await tester.pumpWidget(
          MaterialApp(
            theme: selected,
            home: Builder(
              builder: (context) => Theme(
                data: twitterTheme(context),
                child: Builder(
                  builder: (context) {
                    inside = Theme.of(context);
                    return const Scaffold(body: Text('Twitter'));
                  },
                ),
              ),
            ),
          ),
        );
        expect(inside.brightness, selected.brightness);
        expect(
          inside.scaffoldBackgroundColor,
          dark ? AppColors.xDark.background : AppColors.xLight.background,
        );
        expect(inside.textTheme.bodyMedium?.fontFamily, 'Manrope');
        expect(
          inside.filledButtonTheme.style!.backgroundColor!.resolve({}),
          dark ? AppColors.xDark.accent : AppColors.xLight.accent,
        );
      },
    );
  }
}
