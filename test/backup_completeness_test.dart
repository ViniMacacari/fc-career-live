import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/OtherPlayers/WorldPlayers.dart';
import 'package:mcmanager/FcScore/FcScoreModels.dart';
import 'package:mcmanager/FcScore/FcScoreRepository.dart';
import 'package:mcmanager/Twitter/TwitterSchema.dart';
import 'package:mcmanager/models/FixtureCaptaincy.dart';
import 'package:mcmanager/utils/BackupService.dart';
import 'package:mcmanager/utils/CompetitionTrophies.dart';
import 'package:mcmanager/utils/SecureStorageService.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'backup_storage_fixture.dart';
import 'fcscore_fixture.dart';
import 'fcscore_world_fixture.dart';
import 'season_review_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final docs = Directory('build/v0.9.3-backup-test-docs').absolute;
  final person = reviewPerson(), season = reviewSeason(id: 's2028', year: 2028);
  late Database db;
  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => docs.path,
        );
  });
  Future<Database> database() async {
    final result = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await SqlService.ensureCompatibleSchema(result);
    await SqlService.ensureSeasonClosureSchema(result);
    await SqlService.ensureFixtureFormationSchema(result);
    await SqlService.ensureOpponentLineupSchema(result);
    await SqlService.ensureTransferPreviousClubStatsSchema(result);
    await SqlService.ensureSharedPlayerSchema(result);
    await CompetitionTrophies.ensureSchema(result);
    await WorldPlayers.ensureSchema(result);
    await createTwitterSchema(result);
    await result.execute(
      'ALTER TABLE ManagerFixtures ADD COLUMN opponentStats TEXT',
    );
    await result.execute(
      'CREATE TABLE FutureFeature(id TEXT PRIMARY KEY, data BLOB, count INTEGER, note TEXT)',
    );
    await result.setVersion(34);
    return result;
  }

  setUp(() async {
    mockBackupStorage(
      preferences: {
        'appLang': 'pt_BR',
        'themeMode': 'dark',
        'count_pre_season_matches': false,
        'auto_fill_team_score': true,
        'auto_fill_team_shots_count': true,
        'twitter_ai_language': 'Português brasileiro',
        'twitter_ai_instructions': 'Usar a história da carreira.',
        'twitter_ai_max_tokens': 8000,
        'auto_results_dismissed_career': ['auto:s2028:cup'],
        'auto_trophies_dismissed_career': ['auto:s2028:cup'],
        'framework_cache': 'installation-only',
      },
      secure: {
        'openrouter_api_key': 'backup-test-key',
        'openrouter_model': 'test/model',
      },
    );
    db = await database();
    await db.insert('Persons', person.toMap());
    await db.insert('Seasons', season.toMap());
    await db.insert('Settings', {'activePersonId': person.id});
  });
  tearDown(() async => db.close());
  Future<Map<String, List<Map<String, Object?>>>> snapshot(
    Database database,
  ) async {
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata' ORDER BY name",
    );
    return {
      for (final table in tables)
        table['name'] as String: await database.query(table['name'] as String),
    };
  }

  List<dynamic> payload(BackupService service, String file) {
    final zip = ZipDecoder().decodeBytes(File(file).readAsBytesSync());
    final entry = zip.findFile('temp_backup/backup.json')!;
    final plain = utf8.decode(entry.readBytes()!);
    expect(BackupService.looksEncrypted(plain), isFalse);
    expect(File(file).uri.pathSegments.last, startsWith('carreira_'));
    return jsonDecode(plain) as List;
  }

  test('Fresh database restore preserves every table, imported API data, credentials and app settings', () async {
    await CompetitionTrophies.save(
      db,
      const CompetitionTrophy(
        competitionId: 'cup',
        version: 'FC26',
        name: 'Taça personalizada',
        imagePath: '/trophies/cup/trophy.png',
      ),
    );
    final repo = FcScoreRepository(sql: SqlService.withDatabase(db));
    final link = apiLink()..teams['300'] = 'new:Terceiro FC';
    await repo.importWorld(person: person, link: link, data: worldData());
    await repo.importMatch(
      person: person,
      link: link,
      match: FcScoreMatch.fromReport(apiReport()),
    );
    final captaincy = FixtureCaptaincy(
      initialPlayerId: 'captain',
      handovers: const [
        CaptainHandover(
          substitutionId: 'sub-65',
          fromPlayerId: 'captain',
          playerId: 'successor',
        ),
      ],
    ).encode();
    await db.update('ManagerFixtures', {
      'notes': 'Minha configuração manual',
      'captaincy': captaincy,
    });
    await db.insert('FutureFeature', {
      'id': 'feature',
      'data': Uint8List.fromList([0, 127, 255]),
      'count': 3,
      'note': 'Preservar campos novos',
    });
    await repo.rememberAddress(Uri.parse('http://192.168.0.20:38291/api'));
    final before = await snapshot(db);
    final service = BackupService(database: () async => db);
    final file = await service.generateBackup(includeImages: false);
    final decoded = payload(service, file);
    expect((decoded[0] as List).toSet(), before.keys.toSet());
    expect(decoded[2], 34);
    expect((decoded[3] as Map)['preferences']['framework_cache'], isNull);
    expect(
      latin1.decode(File(file).readAsBytesSync()).contains('backup-test-key'),
      isFalse,
    );
    mockBackupStorage(
      preferences: {
        'themeMode': 'light',
        'auto_results_dismissed_other': ['stale'],
        'framework_cache': 'destination-cache',
      },
      secure: {
        'openrouter_api_key': 'destination-key',
        'openrouter_model': 'old/model',
      },
    );
    final restored = await database();
    addTearDown(restored.close);
    final report = await BackupService(database: () async => restored)
        .restoreBackup(file);
    expect(report.skippedTables, isEmpty);
    expect(report.skippedColumns, isEmpty);
    expect(report.skippedRows, 0);
    expect(await snapshot(restored), before);
    expect(
      (await restored.query('ManagerFixtures')).first['captaincy'],
      captaincy,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('appLang'), 'pt_BR');
    expect(prefs.getString('themeMode'), 'dark');
    expect(prefs.getBool('count_pre_season_matches'), isFalse);
    expect(prefs.getBool('auto_fill_team_score'), isTrue);
    expect(prefs.getBool('auto_fill_team_shots_count'), isTrue);
    expect(prefs.getInt('twitter_ai_max_tokens'), 8000);
    expect(
      prefs.getString('twitter_ai_instructions'),
      'Usar a história da carreira.',
    );
    expect(prefs.getStringList('auto_results_dismissed_career'), [
      'auto:s2028:cup',
    ]);
    expect(prefs.getStringList('auto_trophies_dismissed_career'), [
      'auto:s2028:cup',
    ]);
    expect(prefs.containsKey('auto_results_dismissed_other'), isFalse);
    expect(prefs.getString('framework_cache'), 'destination-cache');
    expect(
      await SecureStorageService.readOpenRouterApiKey(),
      'backup-test-key',
    );
    expect(await SecureStorageService.readOpenRouterModel(), 'test/model');
    expect(report.preferencesRestored, 10);
    expect(report.secureSettingsRestored, 2);
    expect(report.toString(), isNot(contains('backup-test-key')));
    final restoredRepo = FcScoreRepository(
      sql: SqlService.withDatabase(restored),
    );
    expect(
      await restoredRepo.importState(
        person,
        (await restoredRepo.linkFor(person.id))!,
        FcScoreMatch.fromReport(apiReport()),
      ),
      FcImportState.alreadyImported,
    );
    final repeat = await restoredRepo.importWorld(
      person: person,
      link: (await restoredRepo.linkFor(person.id))!,
      data: worldData(),
    );
    expect(repeat.ownMatches, 0);
    expect(repeat.preservedMatches, 1);
    expect(
      (await restored.query('ManagerFixtures')).single['notes'],
      'Minha configuração manual',
    );
  });

  test('All local image folders are included and restored; opting out keeps all database records', () async {
    final files = <File>[];
    for (final folder in BackupService.defaultImageFolders) {
      final file = File('${docs.path}/$folder/backup-audit/image.bin');
      await file.parent.create(recursive: true);
      await file.writeAsBytes([1, 2, 3, folder.length]);
      files.add(file);
    }
    addTearDown(() async {
      for (final file in files) {
        if (await file.exists()) await file.delete();
      }
    });
    final service = BackupService(database: () async => db);
    final file = await service.generateBackup();
    final zip = ZipDecoder().decodeBytes(File(file).readAsBytesSync());
    for (final folder in BackupService.defaultImageFolders) {
      expect(
        zip.findFile('temp_backup/$folder/backup-audit/image.bin'),
        isNotNull,
      );
    }
    for (final image in files) {
      await image.delete();
    }
    final report = await service.restoreBackup(file);
    expect(
      report.restoredImageFolders.toSet(),
      BackupService.defaultImageFolders.toSet(),
    );
    for (final (index, image) in files.indexed) {
      expect(await image.readAsBytes(), [
        1,
        2,
        3,
        BackupService.defaultImageFolders[index].length,
      ]);
    }
    final withoutImages = await service.generateBackup(includeImages: false);
    final noImagesZip = ZipDecoder().decodeBytes(
      File(withoutImages).readAsBytesSync(),
    );
    expect(
      noImagesZip.files
          .where((entry) => entry.isFile)
          .map((entry) => entry.name),
      ['temp_backup/backup.json'],
    );
    final decoded = payload(service, withoutImages);
    expect((decoded[0] as List), contains('Persons'));
    final index = (decoded[0] as List).indexOf('Persons');
    expect((decoded[1] as List)[index].single['id'], person.id);
  });

  test(
    'Backups of other apps are imported only by Importar de outros apps',
    () async {
      final data = await snapshot(db);
      final file = File('${docs.path}/outro_app.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode([data.keys.toList(), data.values.toList(), 34]),
      );
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      await db.update('Persons', {'name': 'Carreira atual'});
      final service = BackupService(database: () async => db);
      await expectLater(
        service.restoreBackup(file.path, allowOtherApps: false),
        throwsA(isA<OtherAppBackupException>()),
      );
      expect((await db.query('Persons')).single['name'], 'Carreira atual');
      final report = await service.restoreBackup(file.path);
      expect(report.fromOtherApp, isTrue);
      expect((await db.query('Persons')).single['name'], person.name);
    },
  );

  test('Legacy backups keep device settings and modern empty settings clear old app values', () async {
    final data = await snapshot(db);
    final service = BackupService(database: () async => db);
    final report = await service.restoreJsonBackup(
      jsonEncode([
        data.keys.toList(),
        data.values.toList(),
        34,
        {'app': BackupService.appMarker},
      ]),
    );
    expect(report.preferencesRestored, 0);
    expect(
      (await SharedPreferences.getInstance()).getString('themeMode'),
      'dark',
    );
    expect(await SecureStorageService.readOpenRouterModel(), 'test/model');
    await service.restoreJsonBackup(
      jsonEncode([
        data.keys.toList(),
        data.values.toList(),
        34,
        {
          'app': BackupService.appMarker,
          'preferences': {},
          'secureSettings': {},
        },
      ]),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('themeMode'), isFalse);
    expect(prefs.containsKey('auto_results_dismissed_career'), isFalse);
    expect(prefs.getString('framework_cache'), 'installation-only');
    expect(await SecureStorageService.readOpenRouterModel(), isNull);
    expect(await SecureStorageService.readOpenRouterApiKey(), isNull);
  });

  test('Malformed settings are rejected before deleting careers or applying preferences', () async {
    final service = BackupService(database: () async => db);
    for (final metadata in [
      {
        'preferences': {'count_pre_season_matches': 'false'},
      },
      {
        'preferences': {
          'auto_trophies_dismissed_career': [1],
        },
      },
      {
        'secureSettings': {'openrouter_model': false},
      },
      {'preferences': []},
    ]) {
      await expectLater(
        service.restoreJsonBackup(
          jsonEncode([
            [],
            [],
            34,
            {'app': BackupService.appMarker, ...metadata},
          ]),
        ),
        throwsFormatException,
      );
    }
    expect((await db.query('Persons')).single['id'], person.id);
    expect(
      (await SharedPreferences.getInstance()).getString('themeMode'),
      'dark',
    );
    expect(
      await SecureStorageService.readOpenRouterApiKey(),
      'backup-test-key',
    );
  });
}
