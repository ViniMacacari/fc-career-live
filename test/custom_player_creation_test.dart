import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/CreateCustomPlayerPage.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/CustomPlayerPreview.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/SelectRealPlayerPage.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/TeamPage.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/ViewPlayerPage.dart';
import 'package:mcmanager/ManagerCareer/TeamTransfers/CreateTeamTransferPage.dart';
import 'package:mcmanager/ManagerCareer/TeamTransfers/SelectTransferPlayerPage.dart';
import 'package:mcmanager/ManagerCareer/TeamTransfers/TeamTransfersPage.dart';
import 'package:mcmanager/ManagerCareer/TeamTransfers/PlayerFarewellDialog.dart';
import 'package:mcmanager/models/Person.dart';
import 'package:mcmanager/models/Season.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/GamePlayers.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/themes.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'ui_preview_fonts.dart';

class _Translations extends AssetLoader {
  const _Translations(this.values);
  final Map<String, dynamic> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

void main() {
  final person = Person(
    id: 'career',
    name: 'Minha carreira',
    category: PersonCategory.manager,
    fifaVersion: 'FC26',
    leagueId: '1014',
    teamId: '40-13',
    nationalityId: '54',
    createdAt: DateTime(2028),
    updatedAt: DateTime(2028),
  );
  final season = Season(
    id: 'season',
    personId: person.id,
    startDate: DateTime(2028),
    endDate: DateTime(2028, 12, 31),
    createdAt: DateTime(2028),
  );
  late Map<String, dynamic> translations;
  var starters = 0;
  var failSave = false;
  var failRosterRemoval = false;
  List<Map<String, Object?>>? rosterRows;
  final removedRosterIds = <String>[];
  final rosterIdentities = <String, Map<String, Object?>>{};
  Object? result;
  final inserted = <String, Map<String, Object?>>{};
  final rosterInitializations = <Map<String, Object?>>[];
  final squadLineups = <Map<String, Object?>>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await loadPreviewFonts();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory('build/custom-player-test-docs').absolute.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (_) async =>
          File('assets/branding/fc-career-live-icon.png').absolute.path,
    );
    translations = jsonDecode(
      await rootBundle.loadString('assets/translations/pt_BR.json'),
    ) as Map<String, dynamic>;
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
              if (sql.contains('FROM SquadLineup')) {
                final bindings = args['arguments'] as List;
                return squadLineups
                    .where(
                      (row) =>
                          row['personId'] == bindings[0] &&
                          row['seasonId'] == bindings[1],
                    )
                    .toList();
              }
              if (sql.contains('FROM SeasonRosterInitialization')) {
                final bindings = args['arguments'] as List;
                return rosterInitializations
                    .where(
                      (row) =>
                          row['personId'] == bindings[0] &&
                          row['seasonId'] == bindings[1],
                    )
                    .toList();
              }
              if (sql.contains('user_version')) {
                return [
                  {'user_version': 27},
                ];
              }
              if (sql.contains('FROM TeamPlayer tp LEFT JOIN')) {
                if (rosterRows != null) {
                  final bindings = args['arguments'] as List;
                  return rosterRows!
                      .where(
                        (row) =>
                            row['personId'] == bindings[0] &&
                            row['seasonId'] == bindings[1],
                      )
                      .toList();
                }
                return [
                  for (var i = 0; i < starters; i++)
                    {'id': 'starter$i', 'isBench': 0},
                ];
              }
              if (sql.contains('FROM Seasons')) return [season.toMap()];
              if (sql.contains('FROM Persons')) return [person.toMap()];
              if (sql.startsWith('SELECT * FROM TeamPlayer WHERE')) {
                final bindings = args['arguments'] as List;
                return rosterRows
                        ?.where(
                          (row) =>
                              row['id'] == bindings[0] &&
                              row['personId'] == bindings[1],
                        )
                        .toList() ??
                    [];
              }
              if (sql.contains('FROM CustomCreatedPlayer') &&
                  inserted.containsKey('CustomCreatedPlayer')) {
                return [inserted['CustomCreatedPlayer']!];
              }
              if (sql.contains('FROM CustomCreatedPlayer') &&
                  rosterIdentities.isNotEmpty) {
                final bindings = args['arguments'] as List;
                final player = rosterIdentities[bindings.first];
                return player == null ? [] : [player];
              }
              return <Map<String, Object?>>[];
            case 'insert':
              final initialization = sql.contains(
                'INTO SeasonRosterInitialization',
              );
              final lineup = sql.contains('INTO SquadLineup');
              if (failSave && !initialization && !lineup) {
                throw PlatformException(code: 'test', message: 'Save failed');
              }
              final match = RegExp(
                r'INSERT(?: OR \w+)? INTO (\w+) \((.*?)\) VALUES \((.*?)\)',
              ).firstMatch(sql)!;
              final columns = match[2]!
                  .split(',')
                  .map((s) => s.trim())
                  .toList();
              final values = match[3]!.split(',').map((s) => s.trim()).toList();
              final bindings = args['arguments'] as List;
              var binding = 0;
              final row = <String, Object?>{
                for (var i = 0; i < columns.length; i++)
                  columns[i]: values[i] == '?' ? bindings[binding++] : null,
              };
              if (lineup) {
                squadLineups.removeWhere(
                  (saved) =>
                      saved['personId'] == row['personId'] &&
                      saved['seasonId'] == row['seasonId'],
                );
                squadLineups.add(row);
              } else if (initialization) {
                rosterInitializations.add(row);
              } else {
                inserted[match[1]!] = row;
              }
              return 1;
            case 'update':
              if (sql.startsWith('DELETE FROM TeamPlayer')) {
                if (failRosterRemoval) {
                  throw PlatformException(
                    code: 'test',
                    message: 'Remove failed',
                  );
                }
                final bindings = args['arguments'] as List;
                expect(sql, contains('id = ? AND personId = ?'));
                expect(bindings[1], person.id);
                removedRosterIds.add(bindings[0] as String);
                rosterRows!.removeWhere(
                  (row) =>
                      row['id'] == bindings[0] &&
                      row['personId'] == bindings[1],
                );
              }
              return 1;
            case 'execute':
              return null;
            default:
              return null;
          }
        });
    await SqlService.instance.database;
    await GameCatalog.load();
    await GamePlayers.load(person.fifaVersion);
  });
  setUp(() {
    starters = 0;
    failSave = false;
    failRosterRemoval = false;
    rosterRows = null;
    removedRosterIds.clear();
    rosterIdentities.clear();
    result = null;
    inserted.clear();
    rosterInitializations.clear();
    squadLineups.clear();
    SharedPreferences.setMockInitialValues({});
  });

  Future<GlobalKey> open(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    bool dark = true,
    double textScale = 1,
    bool reducedMotion = false,
    Widget? entry,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: EasyLocalization(
          supportedLocales: const [Locale('pt', 'BR')],
          startLocale: const Locale('pt', 'BR'),
          path: 'assets/translations',
          assetLoader: _Translations(translations),
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: (dark ? managerDarkTheme : managerLightTheme).copyWith(
                splashFactory: NoSplash.splashFactory,
              ),
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                  disableAnimations: reducedMotion,
                ),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () async {
                        result = await Navigator.push<Object?>(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                entry ??
                                CreateCustomPlayerPage(
                                  person: person,
                                  season: season,
                                ),
                          ),
                        );
                      },
                      child: const Text('Abrir'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir'));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pumpAndSettle();
    return key;
  }

  Finder field(String name) => find.byKey(ValueKey('custom-player-$name'));
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String name, String value) async {
    await tester.ensureVisible(field(name));
    await tester.enterText(field(name), value);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  Future<void> identity(WidgetTester tester) async {
    await enter(tester, 'name', '  Lucas Andrade  ');
    await tap(tester, field('position'));
    await tester.enterText(find.byType(TextField).last, 'Atacante');
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(ListTile, 'Atacante'));
  }

  Future<void> attributes(WidgetTester tester) async {
    await tap(tester, find.text('Atributos'));
    await enter(tester, 'overall', '76');
    await enter(tester, 'potential', '89');
  }

  Future<void> capture(
    WidgetTester tester,
    GlobalKey key,
    String name, {
    bool overlay = false,
  }) async {
    final dir = Platform.environment['PROFILE_PREVIEW_DIR'];
    if (dir == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!overlay) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    }
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

  Future<void> closePortraits(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(seconds: 11));
    }
  }

  void prepareRoster() {
    rosterRows = [
      {
        'id': 'starter',
        'personId': person.id,
        'seasonId': season.id,
        'playerId': 'custom-starter',
        'customName': 'Lucas Andrade',
        'customPositionId': '25',
        'overall': 76,
        'isBench': 0,
      },
      {
        'id': 'reserve',
        'personId': person.id,
        'seasonId': season.id,
        'playerId': 'custom-reserve',
        'customName': 'Pedro Silva',
        'customPositionId': '14',
        'isBench': 1,
      },
      {
        'id': 'starter-another-season',
        'personId': person.id,
        'seasonId': 'another-season',
        'playerId': 'custom-starter',
        'customName': 'Lucas Andrade',
        'isBench': 0,
      },
      {
        'id': 'starter',
        'personId': 'another-career',
        'seasonId': season.id,
        'playerId': 'custom-starter',
        'customName': 'Lucas Andrade',
        'isBench': 0,
      },
    ];
    for (final row in rosterRows!) {
      rosterIdentities[row['playerId'] as String] = {
        'id': row['playerId'],
        'personId': row['personId'],
        'name': row['customName'],
        'positionId': row['customPositionId'],
      };
    }
  }

  Future<void> settleRoster(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  for (final id in ['starter', 'reserve']) {
    testWidgets(
      'roster $id tap offers removal and the existing statistics page',
      (tester) async {
        prepareRoster();
        final key = await open(tester, entry: TeamPage(person: person));
        await tap(tester, find.byKey(ValueKey('player-$id')));
        expect(find.byType(ViewPlayerPage), findsNothing);
        expect(
          find.widgetWithText(ListTile, 'Remover jogador'),
          findsOneWidget,
        );
        expect(find.widgetWithText(ListTile, 'Estatísticas'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Estatísticas')).dy,
          lessThan(tester.getTopLeft(find.text('Remover jogador')).dy),
        );
        expect(removedRosterIds, isEmpty);
        if (id == 'starter') {
          await capture(tester, key, 'roster-player-menu-dark', overlay: true);
        }
        await tap(tester, find.text('Estatísticas'));
        await settleRoster(tester);
        final profile = tester.widget<ViewPlayerPage>(
          find.byType(ViewPlayerPage),
        );
        expect(profile.row['id'], id);
        expect(profile.row['playerId'], 'custom-$id');
        expect(profile.person.id, person.id);
        expect(find.text('Remover jogador'), findsNothing);
        expect(removedRosterIds, isEmpty);
        await closePortraits(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('roster removal is cancelled or dismissed without changes', (
    tester,
  ) async {
    prepareRoster();
    await open(tester, entry: TeamPage(person: person));
    await tap(tester, find.byKey(const ValueKey('player-starter')));
    await tester.tapAt(const Offset(16, 100));
    await tester.pumpAndSettle();
    expect(removedRosterIds, isEmpty);
    for (final cancel in [true, false]) {
      await tap(tester, find.byKey(const ValueKey('player-starter')));
      await tap(tester, find.text('Remover jogador'));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('Lucas Andrade do elenco desta temporada'),
        findsOneWidget,
      );
      expect(removedRosterIds, isEmpty);
      if (cancel) {
        await tap(tester, find.text('Cancelar'));
      } else {
        await tester.tapAt(const Offset(16, 100));
        await tester.pumpAndSettle();
      }
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('player-starter')), findsOneWidget);
      expect(removedRosterIds, isEmpty);
      expect(rosterRows, hasLength(4));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmed removal refreshes only the selected season roster', (
    tester,
  ) async {
    prepareRoster();
    final key = await open(tester, entry: TeamPage(person: person));
    await tap(tester, find.byKey(const ValueKey('player-starter')));
    await tap(tester, find.text('Remover jogador'));
    expect(find.textContaining('estatísticas e o histórico'), findsOneWidget);
    expect(removedRosterIds, isEmpty);
    await capture(tester, key, 'roster-player-confirm-dark', overlay: true);
    await tap(tester, find.widgetWithText(FilledButton, 'Remover'));
    await settleRoster(tester);
    expect(removedRosterIds, ['starter']);
    expect(find.byKey(const ValueKey('player-starter')), findsNothing);
    expect(find.byKey(const ValueKey('player-reserve')), findsOneWidget);
    expect(
      rosterRows!.map((row) => row['id']),
      contains('starter-another-season'),
    );
    expect(
      rosterRows!.where((row) => row['personId'] == 'another-career'),
      hasLength(1),
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(PlayerFarewellDialog), findsOneWidget);
    await tap(tester, find.text('Continuar'));
    await closePortraits(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed roster removal keeps the player and can be retried', (
    tester,
  ) async {
    prepareRoster();
    failRosterRemoval = true;
    await open(tester, entry: TeamPage(person: person));
    await tap(tester, find.byKey(const ValueKey('player-reserve')));
    await tap(tester, find.text('Remover jogador'));
    await tap(tester, find.widgetWithText(FilledButton, 'Remover'));
    await settleRoster(tester);
    expect(find.byKey(const ValueKey('player-reserve')), findsOneWidget);
    expect(
      find.textContaining('Não foi possível remover o jogador'),
      findsOneWidget,
    );
    expect(removedRosterIds, isEmpty);
    failRosterRemoval = false;
    await tester.pump(const Duration(seconds: 5));
    await tap(tester, find.byKey(const ValueKey('player-reserve')));
    await tap(tester, find.text('Remover jogador'));
    await tap(tester, find.widgetWithText(FilledButton, 'Remover'));
    await settleRoster(tester);
    expect(removedRosterIds, ['reserve']);
    expect(find.byKey(const ValueKey('player-reserve')), findsNothing);
    expect(find.byKey(const ValueKey('player-starter')), findsOneWidget);
    expect(find.byType(PlayerFarewellDialog), findsOneWidget);
    await tap(tester, find.text('Continuar'));
    await closePortraits(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'roster player actions fit a small light screen with large text',
    (tester) async {
      prepareRoster();
      rosterRows!.removeWhere((row) => row['isBench'] == 0);
      final key = await open(
        tester,
        entry: TeamPage(person: person),
        size: const Size(320, 640),
        dark: false,
        textScale: 1.4,
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'Existing roster before menu',
      );
      await tap(tester, find.byKey(const ValueKey('player-reserve')));
      expect(find.text('Remover jogador').hitTestable(), findsOneWidget);
      expect(find.text('Estatísticas').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(
        tester,
        key,
        'roster-player-menu-light-large',
        overlay: true,
      );
      await tap(tester, find.text('Remover jogador'));
      expect(find.text('Cancelar').hitTestable(), findsOneWidget);
      expect(find.text('Remover').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(
        tester,
        key,
        'roster-player-confirm-light-large',
        overlay: true,
      );
    },
  );

  for (final dark in [true, false]) {
    testWidgets(
      'tabs preserve draft and fit ${dark ? 'dark 360' : 'light 390'}',
      (tester) async {
        final key = await open(
          tester,
          size: dark ? const Size(360, 640) : const Size(390, 844),
          dark: dark,
        );
        await identity(tester);
        await capture(
          tester,
          key,
          'custom-player-identity-${dark ? 'dark' : 'light'}',
        );
        await tap(tester, find.text('Atributos'));
        await enter(tester, 'overall', '76');
        await enter(tester, 'potential', '89');
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CustomPlayerPreview>(find.byType(CustomPlayerPreview))
              .overall,
          76,
        );
        await capture(
          tester,
          key,
          'custom-player-attributes-${dark ? 'dark' : 'light'}',
        );
        await tap(tester, find.text('Elenco'));
        await enter(tester, 'shirt', '10');
        await capture(
          tester,
          key,
          'custom-player-roster-${dark ? 'dark' : 'light'}',
        );
        await tap(tester, find.text('Identidade'));
        expect(
          tester.widget<TextFormField>(field('name')).controller!.text,
          '  Lucas Andrade  ',
        );
        expect(
          tester.widget<TextFormField>(field('position')).controller!.text,
          'Atacante',
        );
        await tap(tester, find.text('Atributos'));
        expect(
          tester.widget<TextFormField>(field('overall')).controller!.text,
          '76',
        );
        expect(
          tester.widget<TextFormField>(field('potential')).controller!.text,
          '89',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('save finds missing and invalid fields across hidden tabs', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, find.text('Elenco'));
    await tap(tester, find.text('Criar jogador'));
    expect(find.text('Informe o nome do jogador.'), findsOneWidget);
    expect(find.text('Escolha uma posição.'), findsOneWidget);
    expect(inserted, isEmpty);
    await identity(tester);
    await tap(tester, find.text('Elenco'));
    await tap(tester, find.text('Criar jogador'));
    expect(find.text('Atributos e evolução'), findsOneWidget);
    expect(find.text('Preencha este campo.'), findsNWidgets(2));
    await enter(tester, 'overall', '100');
    await enter(tester, 'potential', '89');
    await tap(tester, find.text('Elenco'));
    await tap(tester, find.text('Criar jogador'));
    expect(find.text('Use um valor de 0 a 99.'), findsOneWidget);
    expect(inserted, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creation saves optional data and rechecks the starting eleven', (
    tester,
  ) async {
    starters = 10;
    await open(tester);
    await identity(tester);
    await tap(tester, field('nationality'));
    await tester.enterText(find.byType(TextField).last, 'Brasil');
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(ListTile, 'Brasil'));
    await tap(tester, field('birthday'));
    expect(
      tester.widget<DatePickerDialog>(find.byType(DatePickerDialog)).lastDate,
      season.startDate,
    );
    await tap(tester, find.text('OK'));
    await attributes(tester);
    await enter(tester, 'height', '182');
    await enter(tester, 'weight', '75');
    await tap(tester, find.text('Esquerdo'));
    await tap(tester, find.text('Elenco'));
    await enter(tester, 'shirt', '10');
    starters = 11;
    await tap(tester, find.text('Criar jogador'));
    expect(result, isTrue);
    final player = inserted['CustomCreatedPlayer']!;
    final roster = inserted['TeamPlayer']!;
    expect(player['name'], 'Lucas Andrade');
    expect(player['positionId'], '25');
    expect(player['nationalityId'], '54');
    expect(player['overall'], 76);
    expect(player['potential'], 89);
    expect(player['height'], 182);
    expect(player['weight'], 75);
    expect(player['foot'], 'Left');
    expect(player['birthdate'], DateTime(2008).millisecondsSinceEpoch);
    expect(roster['playerId'], player['id']);
    expect(roster['seasonId'], season.id);
    expect(roster['shirtNumber'], 10);
    expect(roster['isBench'], 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full roster is explained and a failed save can be retried', (
    tester,
  ) async {
    starters = 11;
    await open(tester);
    await identity(tester);
    await attributes(tester);
    await tap(tester, find.text('Elenco'));
    expect(
      find.textContaining('Os 11 titulares já estão preenchidos.'),
      findsOneWidget,
    );
    failSave = true;
    await tap(tester, find.text('Criar jogador'));
    expect(result, isNull);
    expect(
      find.text('Não foi possível criar o jogador. Tente novamente.'),
      findsOneWidget,
    );
    expect(inserted, isEmpty);
    failSave = false;
    await tap(tester, find.text('Criar jogador'));
    expect(result, isTrue);
    expect(inserted['TeamPlayer']!['isBench'], 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'large text and keyboard keep actions accessible with reduced motion',
    (tester) async {
      await open(
        tester,
        size: const Size(320, 568),
        textScale: 1.6,
        reducedMotion: true,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.text('Continuar').hitTestable(), findsOneWidget);
      await tap(tester, find.text('Continuar'));
      await tester.scrollUntilVisible(
        find.text('Atributos e evolução'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Atributos e evolução'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('optional photo can be removed and is copied before saving', (
    tester,
  ) async {
    await open(tester);
    final addPhoto = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'Adicionar foto do jogador',
    );
    await tap(tester, addPhoto);
    expect(find.text('Remover foto'), findsOneWidget);
    await tap(tester, find.text('Remover foto'));
    expect(
      tester
          .widget<CustomPlayerPreview>(find.byType(CustomPlayerPreview))
          .avatar,
      isNull,
    );
    await tap(tester, addPhoto);
    await identity(tester);
    await attributes(tester);
    await tap(tester, find.text('Elenco'));
    await tester.tap(find.text('Criar jogador'));
    final copying = Stopwatch()..start();
    while (result == null && copying.elapsed < const Duration(seconds: 10)) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
    expect(result, isTrue);
    final path =
        inserted['CustomCreatedPlayer']!['customAvatarFilePath'] as String;
    expect(path, startsWith('/faces/${person.id}/'));
    final copy = File(
      '${Directory('build/custom-player-test-docs').absolute.path}$path',
    );
    expect(copy.existsSync(), isTrue);
    expect(
      copy.readAsBytesSync(),
      File('assets/branding/fc-career-live-icon.png').readAsBytesSync(),
    );
    await tester.runAsync(() => copy.delete());
    expect(tester.takeException(), isNull);
  });

  testWidgets('roster add menu opens the shared creator', (tester) async {
    await open(tester, entry: TeamPage(person: person));
    await tap(tester, find.byTooltip('players.addPlayers'.tr()));
    expect(find.text('Adicionar ao elenco'), findsOneWidget);
    await tap(tester, find.text('Criar jogador personalizado'));
    expect(find.byType(CreateCustomPlayerPage), findsOneWidget);
    expect(
      tester
          .widget<CreateCustomPlayerPage>(find.byType(CreateCustomPlayerPage))
          .season!
          .id,
      season.id,
    );
    expect(inserted, isEmpty);
  });

  testWidgets('catalog add shortcut creates in the selected roster', (
    tester,
  ) async {
    await open(
      tester,
      entry: SelectRealPlayerPage(
        person: person,
        season: season,
        existingIds: const {},
      ),
    );
    await tap(tester, find.text('Criar jogador personalizado'));
    await identity(tester);
    await attributes(tester);
    await tap(tester, find.text('Elenco'));
    await tap(tester, find.text('Criar jogador'));
    expect(result, isTrue);
    expect(inserted['TeamPlayer']!['seasonId'], season.id);
  });

  testWidgets(
    'transfer selection creates and returns a player without early arrival',
    (tester) async {
      await open(
        tester,
        entry: SelectTransferPlayerPage(
          person: person,
          season: season,
          rosterIds: const {},
        ),
      );
      await tap(tester, find.text('Criar jogador personalizado'));
      expect(find.text('Elenco'), findsNothing);
      await identity(tester);
      await attributes(tester);
      await tap(tester, find.text('Criar jogador'));
      final choice = result as TransferPlayerChoice;
      expect(choice.name, 'Lucas Andrade');
      expect(choice.id, inserted['CustomCreatedPlayer']!['id']);
      expect(choice.overall, 76);
      expect(inserted.containsKey('TeamPlayer'), isFalse);
      await closePortraits(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('outgoing transfer creation adds the player to its roster', (
    tester,
  ) async {
    await open(
      tester,
      entry: SelectTransferPlayerPage(
        person: person,
        season: season,
        rosterIds: const {},
        onlyRoster: true,
      ),
    );
    await tap(tester, find.text('Criar jogador personalizado'));
    await identity(tester);
    await attributes(tester);
    await tap(tester, find.text('Elenco'));
    await tap(tester, find.text('Criar jogador'));
    final choice = result as TransferPlayerChoice;
    expect(inserted['TeamPlayer']!['playerId'], choice.id);
    expect(inserted['TeamPlayer']!['seasonId'], season.id);
  });

  testWidgets(
    'transfer purchase search keeps focus and filtering when the keyboard opens',
    (tester) async {
      addTearDown(tester.view.resetViewInsets);
      await open(
        tester,
        entry: SelectTransferPlayerPage(
          person: person,
          season: season,
          rosterIds: const {},
        ),
      );
      final search = find.byType(TextField);
      final originalField = tester.element(search);
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      final player = (await tester.runAsync(
        () => GamePlayers.load(person.fifaVersion),
      ))!.first;
      expect(find.text('Criar jogador personalizado'), findsOneWidget);
      await tester.tap(search);
      await tester.enterText(search, player.id);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, player.name), findsOneWidget);

      for (final bottom in [80.0, 180.0, 300.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: bottom);
        await tester.pumpAndSettle();
        expect(tester.element(search), same(originalField));
        expect(editable.focusNode.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
        expect(editable.controller.text, player.id);
        expect(find.text('Criar jogador personalizado'), findsNothing);
        expect(find.widgetWithText(ListTile, player.name), findsOneWidget);
      }

      await tester.enterText(search, 'no-player-matches-this-query');
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);
      await tester.enterText(search, player.id);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, player.name), findsOneWidget);

      editable.focusNode.unfocus();
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(tester.element(search), same(originalField));
      expect(editable.controller.text, player.id);
      expect(find.text('Criar jogador personalizado'), findsOneWidget);
      await tester.tap(search);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(editable.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(find.widgetWithText(ListTile, player.name), findsOneWidget);
      await closePortraits(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'transfer add menu opens negotiation with the created player selected',
    (tester) async {
      await open(tester, entry: TeamTransfersPage(person: person));
      await tap(tester, find.byTooltip('Adicionar Item de Transferência'));
      expect(find.text('Registrar transferência'), findsOneWidget);
      await tap(tester, find.text('Criar jogador personalizado'));
      await identity(tester);
      await attributes(tester);
      await tap(tester, find.text('Criar jogador'));
      final form = tester.widget<CreateTeamTransferPage>(
        find.byType(CreateTeamTransferPage),
      );
      expect(form.initialPlayer!.name, 'Lucas Andrade');
      expect(find.text('Lucas Andrade'), findsOneWidget);
      expect(inserted.containsKey('TeamPlayer'), isFalse);
      expect(inserted.containsKey('TeamTransferItem'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelling creation returns to transfer selection without saving',
    (tester) async {
      await open(
        tester,
        entry: SelectTransferPlayerPage(
          person: person,
          season: season,
          rosterIds: const {},
        ),
      );
      await tap(tester, find.text('Criar jogador personalizado'));
      await enter(tester, 'name', 'Rascunho');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(SelectTransferPlayerPage), findsOneWidget);
      expect(inserted, isEmpty);
      expect(result, isNull);
      await closePortraits(tester);
    },
  );
}
