import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mcmanager/Common/Seasons/CreateSeason.dart';
import 'package:mcmanager/Common/Seasons/SeasonArchivePage.dart';
import 'package:mcmanager/Common/Seasons/SeasonClosingPage.dart';
import 'package:mcmanager/Common/Seasons/SeasonRecapPage.dart';
import 'package:mcmanager/Common/Seasons/SeasonTablePage.dart';
import 'package:mcmanager/ManagerCareer/Graphics/TeamAnalyticsCharts.dart';
import 'package:mcmanager/models/Person.dart';
import 'package:mcmanager/models/Season.dart';
import 'package:mcmanager/models/SeasonReview.dart';
import 'package:mcmanager/utils/SeasonClosureService.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';

class _Loader extends AssetLoader {
  const _Loader(this.translations);
  final Map<String, dynamic> translations;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      translations;
}

class _FakeService extends SeasonClosureService {
  int closures = 0;
  @override
  Future<SeasonReview> load(
    Person person,
    Season season, {
    bool live = false,
  }) async => exampleReview(closed: season.isClosed);
  @override
  Future<SeasonReview> close(
    Person person,
    Season season, {
    List<SeasonFinalTable> tables = const [],
  }) async {
    closures++;
    return exampleReview();
  }
}

void main() {
  late Map<String, dynamic> translations;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await initializeDateFormatting('pt_BR');
    await loadPreviewFonts();
    await GameCatalog.load();
    translations = jsonDecode(
      await rootBundle.loadString('assets/translations/pt_BR.json'),
    ) as Map<String, dynamic>;
  });
  void viewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(
    Widget home, {
    GlobalKey? captureKey,
    ThemeData? theme,
    bool reduced = false,
    double scale = 1,
  }) => RepaintBoundary(
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduced,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: home,
        ),
      ),
    ),
  );
  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    final dir = Platform.environment['PROFILE_PREVIEW_DIR'];
    if (dir == null) return;
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/images/clubLogos/sao-paulo.png'),
        key.currentContext!,
      );
      await precacheImage(
        const AssetImage('assets/branding/fc-career-live-icon.png'),
        key.currentContext!,
      );
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(dir).create(recursive: true);
      await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  for (final dark in [true, false]) {
    testWidgets(
      'Recap uses separate tabs and working rankings in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        viewport(tester, const Size(390, 844));
        final key = GlobalKey();
        await tester.pumpWidget(
          app(
            SeasonRecapPage(person: reviewPerson(), review: exampleReview()),
            captureKey: key,
            theme: dark ? managerDarkTheme : managerLightTheme,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SeasonRecapHero), findsOneWidget);
        expect(find.byType(AnalyticsResultsChart), findsOneWidget);
        await capture(
          tester,
          key,
          'retrospectiva_${dark ? 'escuro' : 'claro'}',
        );
        await tap(tester, find.text('Competições'));
        expect(find.byType(SeasonStandingsCard), findsOneWidget);
        expect(find.byType(AnalyticsResultsChart), findsNothing);
        await capture(
          tester,
          key,
          'retrospectiva_competicoes_${dark ? 'escuro' : 'claro'}',
        );
        await tap(tester, find.text('Destaques'));
        expect(find.byType(SeasonStandingsCard), findsNothing);
        await tap(tester, find.byType(DropdownButtonFormField<String>).first);
        await tester.tap(find.text('Assistências').last);
        await tester.pumpAndSettle();
        expect(find.text('7'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Animated story advances and remains scrollable on a small phone',
    (tester) async {
      viewport(tester, const Size(360, 640));
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          SeasonStoryPage(review: exampleReview(), person: reviewPerson()),
          captureKey: key,
          scale: 1.2,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 / 6'), findsOneWidget);
      await capture(tester, key, 'retrospectiva_apresentacao');
      await tester.tap(find.text('Próximo'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 6'), findsOneWidget);
      expect(find.text('gols marcados'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Reduced motion shows final numbers immediately', (tester) async {
    viewport(tester, const Size(360, 640));
    await tester.pumpWidget(
      app(
        SeasonStoryPage(review: exampleReview(), person: reviewPerson()),
        reduced: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Closing season saves once and opens story then recap', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    final service = _FakeService();
    final key = GlobalKey();
    await tester.pumpWidget(
      app(
        SeasonClosingPage(
          person: reviewPerson(),
          season: reviewSeason(),
          initialReview: exampleReview(closed: false),
          service: service,
        ),
        captureKey: key,
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, key, 'encerrar_temporada');
    final closeButton = find.byWidgetPredicate((w) => w is FilledButton);
    await tester.scrollUntilVisible(
      closeButton,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tap(tester, closeButton);
    expect(service.closures, 1);
    expect(find.byType(SeasonStoryPage), findsOneWidget);
    await tester.tap(find.text('Ver detalhes'));
    await tester.pumpAndSettle();
    expect(find.byType(SeasonRecapPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Quick table edit stores entered position and leaves missing stats null',
    (tester) async {
      viewport(tester, const Size(390, 844));
      SeasonFinalTable? saved;
      final table = exampleReview().draftTable('league:1014');
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          SeasonTablePage(
            person: reviewPerson(),
            table: table,
            ownTeamId: '40-13',
            onSave: (t) async => saved = t,
          ),
          captureKey: key,
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, key, 'fechar_tabela');
      await tap(tester, find.text('São Paulo'));
      await tester.enterText(find.byType(TextFormField).first, '4');
      await tester.enterText(find.byType(TextFormField).at(1), '62');
      await tap(tester, find.text('Aplicar'));
      await tap(tester, find.text('Salvar tabela final'));
      expect(saved!.rows.single.position, 4);
      expect(saved!.rows.single.stats['points'], 62);
      expect(saved!.rows.single.stats['wins'], null);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Final table validates duplicate ranks before saving', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    var saves = 0;
    final table = SeasonFinalTable(
      id: '',
      tournamentId: 'league:1014',
      name: 'Brasileirão',
      rows: const [
        SeasonStanding(teamId: '40-13', name: 'São Paulo', position: 1),
        SeasonStanding(teamId: 'fla', name: 'Flamengo', position: 1),
      ],
    );
    await tester.pumpWidget(
      app(
        SeasonTablePage(
          person: reviewPerson(),
          table: table,
          ownTeamId: '40-13',
          onSave: (_) async {
            saves++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, find.text('Salvar tabela final'));
    expect(saves, 0);
    expect(
      find.text('Cada clube precisa ter uma posição positiva e diferente.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Archive includes old open seasons and filters completed seasons',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          SeasonArchivePage(
            person: reviewPerson(),
            service: _FakeService(),
            loader: () async => [
              reviewSeason(),
              reviewSeason(id: 's2025', year: 2025, closed: true),
              reviewSeason(id: 's2024', year: 2024),
            ],
          ),
          captureKey: key,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2024'), findsOneWidget);
      expect(find.text('Encerrar e registrar tabela →'), findsNWidgets(2));
      await capture(tester, key, 'temporadas_retrospectivas');
      await tester.tap(find.text('Encerradas'));
      await tester.pumpAndSettle();
      expect(find.text('2025'), findsOneWidget);
      expect(find.text('2024'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'New season proposes closing current season and permits explicit skip',
    (tester) async {
      viewport(tester, const Size(390, 844));
      Season? created;
      await tester.pumpWidget(
        app(
          CreateSeasonPage(
            personId: 'career',
            person: reviewPerson(),
            seasonLoader: () async => [reviewSeason()],
            onCreate: (s) async => created = s,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Encerrar temporada atual'), findsOneWidget);
      expect(find.text('Encerrar antes de continuar'), findsOneWidget);
      await tap(tester, find.text('Criar sem encerrar agora'));
      await tap(tester, find.text('Criar temporada'));
      expect(created!.startDate, DateTime(2027));
      expect(created!.endDate, DateTime(2027, 12, 31));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Close current season, review it, then create the next season', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    final service = _FakeService();
    Season? created;
    await tester.pumpWidget(
      app(
        CreateSeasonPage(
          personId: 'career',
          person: reviewPerson(),
          service: service,
          seasonLoader: () async => [
            reviewSeason(closed: service.closures > 0),
          ],
          onCreate: (s) async => created = s,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, find.text('Encerrar temporada atual'));
    final button = find.byWidgetPredicate((w) => w is FilledButton);
    await tester.scrollUntilVisible(
      button,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tap(tester, button);
    expect(service.closures, 1);
    expect(find.byType(SeasonStoryPage), findsOneWidget);
    await tester.tap(find.text('Ver detalhes'));
    await tester.pumpAndSettle();
    expect(find.byType(SeasonRecapPage), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Temporada anterior encerrada'), findsOneWidget);
    await tap(tester, find.text('Criar temporada'));
    expect(created!.startDate, DateTime(2027));
    expect(service.closures, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Journey filters matches and events by competition', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      app(SeasonRecapPage(person: reviewPerson(), review: exampleReview())),
    );
    await tester.pumpAndSettle();
    await tap(tester, find.text('Jornada'));
    expect(find.text('Mês a mês'), findsOneWidget);
    await tap(tester, find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.text('Copa do Brasil').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Nenhum evento registrado nesta temporada.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Editing only my team preserves the rest of a saved final table',
    (tester) async {
      viewport(tester, const Size(390, 844));
      SeasonFinalTable? saved;
      await tester.pumpWidget(
        app(
          SeasonTablePage(
            person: reviewPerson(),
            table: exampleReview().tables.single,
            ownTeamId: '40-13',
            onSave: (t) async => saved = t,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Meu time'));
      await tester.pumpAndSettle();
      expect(find.text('Palmeiras'), findsNothing);
      await tap(tester, find.text('Salvar tabela final'));
      expect(saved!.rows, hasLength(3));
      expect(saved!.rows[1].name, 'Palmeiras');
      expect(tester.takeException(), isNull);
    },
  );
}
