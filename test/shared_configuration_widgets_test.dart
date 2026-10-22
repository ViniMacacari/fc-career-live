import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/CreateCustomPlayerPage.dart';
import 'package:mcmanager/Settings/CustomConfiguration/CustomConfiguration.dart';
import 'package:mcmanager/Settings/CustomConfiguration/CustomConfigurationComponents.dart';
import 'package:mcmanager/Settings/CustomConfiguration/CustomConfiguration_AddCustom/Teams/CreateCustomTeamPage.dart';
import 'package:mcmanager/Settings/CustomConfiguration/CustomConfiguration_AddCustom/Leagues/CreateCustomLeaguePage.dart';
import 'package:mcmanager/Settings/CustomConfiguration/CustomConfiguration_AddCustom/Tournaments/CreateCustomTournamentPage.dart';
import 'package:mcmanager/Settings/CustomConfiguration/ClubCustomization/ClubCustomizationFormPage.dart';
import 'package:mcmanager/Settings/CustomConfiguration/CustomPlayersPage.dart';
import 'package:mcmanager/models/CustomClub.dart';
import 'package:mcmanager/models/CustomLeague.dart';
import 'package:mcmanager/models/ClubCustomizationModel.dart';
import 'package:mcmanager/models/Tournament.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show sqfliteFfiInit, databaseFactoryFfiNoIsolate;

import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';

class _Translations extends AssetLoader {
  const _Translations(this.values);
  final Map<String, dynamic> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Map<String, dynamic> translations;
  late Database db;
  late SqlService sql;
  final now = DateTime(2026, 10, 11);
  final capture = GlobalKey();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory('build/shared-config-widget-docs').absolute.path,
    );
    databaseFactory = databaseFactorySqflitePlugin;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.tekartik.sqflite'),
      (call) async {
        final args = call.arguments is Map ? call.arguments as Map : const {};
        switch (call.method) {
          case 'getDatabasesPath':
            return Directory('build/shared-config-widget-db').absolute.path;
          case 'openDatabase':
            return {'id': 1};
          case 'query':
            return args['sql'].toString().contains('user_version')
                ? [
                    {'user_version': 32},
                  ]
                : <Map<String, Object?>>[];
          case 'insert':
          case 'update':
            return 1;
          default:
            return null;
        }
      },
    );
    await EasyLocalization.ensureInitialized();
    await loadPreviewFonts();
    translations = jsonDecode(
      await rootBundle.loadString('assets/translations/pt_BR.json'),
    ) as Map<String, dynamic>;
    await GameCatalog.load();
  });
  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    sql = SqlService.withDatabase(db);
    await SqlService.ensureCompatibleSchema(db);
    await SqlService.ensureSeasonClosureSchema(db);
    await db.execute(
      'ALTER TABLE TeamTransferItem ADD COLUMN releaseDate TEXT',
    );
    await db.execute(
      'ALTER TABLE TeamTransferItem ADD COLUMN movementApplied INTEGER NOT NULL DEFAULT 1',
    );
    await db.insert('Persons', reviewPerson().toMap());
    await db.insert('Seasons', reviewSeason().toMap());
    await sql.saveSharedPlayer({
      'id': 'samuel',
      'name': 'Samuel Guimarães',
      'positionId': '25',
      'overall': 83,
      'potential': 90,
      'foot': 'Right',
      'nationalityId': '54',
    });
  });
  tearDown(() => db.close());
  Widget app(Widget home, {double scale = 1}) => RepaintBoundary(
    key: capture,
    child: EasyLocalization(
      supportedLocales: const [Locale('pt', 'BR')],
      startLocale: const Locale('pt', 'BR'),
      path: 'assets/translations',
      assetLoader: _Translations(translations),
      saveLocale: false,
      child: Builder(
        builder: (context) => MaterialApp(
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
  void viewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
  }

  Future<void> preview(WidgetTester tester, String name) async {
    final directory = Platform.environment['SHARED_CONFIG_PREVIEW_DIR'];
    if (directory == null) return;
    await tester.runAsync(() async {
      final boundary =
          capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(seconds: 11));
    }
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(390, 844), const Size(320, 640)]) {
    testWidgets(
      'Application settings hub has the shared player entry at ${size.width}',
      (tester) async {
        viewport(tester, size);
        await tester.pumpWidget(
          app(const ConfigurationHub(), scale: size.width == 320 ? 1.2 : 1),
        );
        await settle(tester);
        expect(find.text('Configurações do aplicativo'), findsOneWidget);
        expect(find.text('Jogadores personalizados'), findsOneWidget);
        await preview(tester, 'hub-${size.width.toInt()}');
        expect(tester.takeException(), isNull);
        await cleanup(tester);
      },
    );
    testWidgets(
      'Shared player search preserves keyboard focus at ${size.width}',
      (tester) async {
        viewport(tester, size);
        await tester.pumpWidget(
          app(
            CustomPlayersPage(service: sql),
            scale: size.width == 320 ? 1.2 : 1,
          ),
        );
        await settle(tester);
        expect(find.text('Samuel Guimarães'), findsOneWidget);
        await preview(tester, 'players-${size.width.toInt()}');
        final search = find.descendant(
          of: find.byKey(const ValueKey('shared-player-search')),
          matching: find.byType(TextField),
        );
        await tester.tap(search);
        await tester.enterText(search, 'guimaraes');
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        await settle(tester);
        final input = tester.widget<EditableText>(find.byType(EditableText));
        expect(input.focusNode.hasFocus, true);
        expect(input.controller.text, 'guimaraes');
        expect(find.text('Samuel Guimarães'), findsOneWidget);
        await preview(tester, 'players-keyboard-${size.width.toInt()}');
        expect(tester.takeException(), isNull);
        await cleanup(tester);
      },
    );
  }

  testWidgets(
    'Shared player editing persists without changing an existing career copy',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final careerPlayer = (await tester.runAsync(
        () => sql.useSharedPlayer(personId: 'career', templateId: 'samuel'),
      ))!;
      await tester.pumpWidget(app(CustomPlayersPage(service: sql)));
      await settle(tester);
      await tester.tap(find.text('Samuel Guimarães'));
      await settle(tester);
      expect(find.text('Editar jogador personalizado'), findsOneWidget);
      await preview(tester, 'player-editor-390');
      await tester.enterText(
        find.byKey(const ValueKey('custom-player-name')),
        'Samuel editado',
      );
      await tester.tap(find.text('Atributos'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('custom-player-overall')),
        '86',
      );
      await tester.tap(find.text('Salvar alterações'));
      await settle(tester);
      expect(find.byType(CreateCustomPlayerPage), findsNothing);
      expect(find.text('Samuel editado'), findsOneWidget);
      final original = await tester.runAsync(
        () => sql.getCustomPlayerById('career', careerPlayer['id'] as String),
      );
      expect(original!['name'], 'Samuel Guimarães');
      expect(original['overall'], 83);
      expect(tester.takeException(), isNull);
      await cleanup(tester);
    },
  );

  testWidgets('Shared player picker adds the chosen template to the roster', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    await tester.runAsync(
      () => sql.getTeamPlayers('career', reviewSeason().id),
    );
    Map<String, Object?>? result;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.push<Map<String, Object?>>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CustomPlayersPage(
                      service: sql,
                      person: reviewPerson(),
                      season: reviewSeason(),
                      addToRoster: true,
                    ),
                  ),
                );
              },
              child: const Text('Escolher'),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Escolher'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('shared-player-samuel')));
    await settle(tester);
    expect(result!['libraryPlayerId'], 'samuel');
    final roster = await tester.runAsync(() => db.query('TeamPlayer'));
    expect(roster!.single['playerId'], result!['id']);
    expect(tester.takeException(), isNull);
    await cleanup(tester);
  });

  testWidgets(
    'All settings editors use spaced steps and team availability supports multiple FIFAs',
    (tester) async {
      viewport(tester, const Size(320, 640));
      final forms = <String, Widget>{
        'team': CustomTeamForm(
          club: CustomClub(
            id: 'team',
            label: 'Meu clube',
            leagueId: '1014',
            fifaVersion: 'FC26,FIFA23',
            createdAt: now,
            updatedAt: now,
          ),
        ),
        'league': CustomLeagueForm(
          league: CustomLeague(
            id: 'league',
            label: 'Minha liga',
            fifaVersion: 'FC26,FIFA23',
            createdAt: now,
            updatedAt: now,
          ),
        ),
        'tournament': CustomTournamentForm(
          tournament: const Tournament(
            id: 'cup',
            name: 'Minha copa',
            abbreviation: 'MC',
            type: 'custom',
            category: 'club',
            fifaVersions: 'FC26',
          ),
        ),
        'customization': ClubCustomizationFormPage(
          customization: ClubCustomizationModel(
            id: 'customization',
            clubName: 'São Paulo FC',
            originalTeamId: '40-13',
            originalLeagueId: '1014',
            fifaVersion: 'FC26',
            createdAt: now,
            updatedAt: now,
          ),
        ),
      };
      for (final entry in forms.entries) {
        await tester.pumpWidget(app(entry.value, scale: 1.2));
        await settle(tester);
        expect(find.byType(CustomFormStepper), findsOneWidget);
        expect(find.byType(Stepper), findsNothing);
        await preview(tester, '${entry.key}-editor-320');
        expect(tester.takeException(), isNull);
        await cleanup(tester);
      }
      await tester.pumpWidget(app(const CustomTeamForm(), scale: 1.2));
      await settle(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'Clube compartilhado',
      );
      await settle(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, 'customConfiguration.next'.tr()),
      );
      await settle(tester);
      for (final version in ['FC26', 'FIFA23']) {
        await tester.tap(find.byKey(ValueKey('available-version-$version')));
        await settle(tester);
        expect(
          tester
              .widget<FilterChip>(
                find.byKey(ValueKey('available-version-$version')),
              )
              .selected,
          true,
        );
      }
      await preview(tester, 'team-availability-320');
      expect(find.text('Versão de origem da competição'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cleanup(tester);
    },
  );
}
