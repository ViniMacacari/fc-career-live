import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/models/CustomClub.dart';
import 'package:mcmanager/models/CustomLeague.dart';
import 'package:mcmanager/utils/BackupService.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/SharedClubAvailability.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/databaseUtils.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late SqlService sql;
  late GameCatalog catalog;
  final now = DateTime(2026, 10, 11);
  Map<String, Object?> player(
    String id, {
    String career = 'career',
    int overall = 65,
  }) => {
    'id': id,
    'personId': career,
    'name': 'Samuel Guimarães',
    'positionId': '25',
    'overall': overall,
    'potential': 90,
    'foot': 'Right',
    'realFace': 0,
    'fromRealPlayer': 0,
    'nationalityId': '54',
    'height': 180,
    'weight': 75,
  };
  CustomClub club(String id, String league, String versions) => CustomClub(
    id: id,
    label: id,
    leagueId: league,
    fifaVersion: versions,
    createdAt: now,
    updatedAt: now,
  );
  Future<void> refreshCatalog() async => catalog.debugSetCustomData(
    leagues: (await db.query('CustomLeague'))
        .map(CustomLeague.fromMap)
        .toList(),
    clubs: (await db.query('CustomClub')).map(CustomClub.fromMap).toList(),
  );
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async =>
              Directory('build/shared-configuration-test-docs').absolute.path,
        );
    catalog = await GameCatalog.load();
  });
  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    sql = SqlService.withDatabase(db);
    await SqlService.ensureCompatibleSchema(db);
    await SqlService.ensureSeasonClosureSchema(db);
    await SqlService.ensureSharedPlayerSchema(db);
    await db.insert('Persons', reviewPerson().toMap());
    await db.insert('Seasons', reviewSeason().toMap());
    catalog.debugSetCustomData();
  });
  tearDown(() async {
    catalog.debugSetCustomData();
    await db.close();
  });

  test('migration publishes old custom players with latest overall and preserves history', () async {
    await db.execute('DROP TABLE CustomPlayerTemplate');
    await db.execute(
      'ALTER TABLE CustomCreatedPlayer DROP COLUMN libraryPlayerId',
    );
    await db.insert('CustomCreatedPlayer', player('old'));
    await db.insert('CustomCreatedPlayer', {
      ...player('real'),
      'fromRealPlayer': 1,
      'realPlayerId': '123',
    });
    await db.insert('Overall', {
      'id': 'latest',
      'personId': 'career',
      'customPlayerId': 'old',
      'overall': 84,
      'date': now.toIso8601String(),
      'createdAt': now.toIso8601String(),
    });
    await SqlService.ensureSharedPlayerSchema(db);
    await SqlService.ensureSharedPlayerSchema(db);
    await SqlService.seedSharedPlayers(db);
    await SqlService.seedSharedPlayers(db);
    final library = await sql.getSharedPlayers();
    expect(library.single['id'], 'old');
    expect(library.single['overall'], 84);
    expect(
      (await db.query(
        'CustomCreatedPlayer',
        where: 'id = ?',
        whereArgs: ['old'],
      )).single['overall'],
      65,
    );
    expect((await db.query('Overall')).single['overall'], 84);
    expect((await sql.getCustomPlayerById('career', 'old'))!['id'], 'old');
  });

  test('career creation automatically publishes its player once', () async {
    await sql.createCustomTeamPlayer(player('new'), {
      'id': 'roster',
      'personId': 'career',
      'seasonId': reviewSeason().id,
      'playerId': 'new',
      'overall': 65,
      'isBench': 0,
    });
    expect((await sql.getSharedPlayers()).single['id'], 'new');
    final chosen = await sql.useSharedPlayer(
      personId: 'career',
      templateId: 'new',
      seasonId: reviewSeason().id,
    );
    expect(chosen['id'], 'new');
    expect(await db.query('TeamPlayer'), hasLength(1));
  });

  test('same template works in different FIFA careers with independent identities and edits', () async {
    await sql.saveSharedPlayer(player('template'));
    final first = await sql.useSharedPlayer(
      personId: 'career',
      templateId: 'template',
    );
    await db.insert('Persons', {
      ...reviewPerson().toMap(),
      'id': 'other',
      'fifaVersion': 'FIFA23',
    });
    final second = await sql.useSharedPlayer(
      personId: 'other',
      templateId: 'template',
    );
    expect(first['id'], isNot(second['id']));
    await db.insert('Overall', {
      'id': 'manual',
      'personId': 'career',
      'customPlayerId': first['id'],
      'overall': 87,
      'date': now.toIso8601String(),
      'createdAt': now.toIso8601String(),
    });
    expect(
      (await sql.useSharedPlayer(
        personId: 'career',
        templateId: 'template',
      ))['overall'],
      87,
    );
    expect(
      (await sql.getCustomPlayerById(
        'other',
        second['id'] as String,
      ))!['overall'],
      65,
    );
    await sql.saveSharedPlayer({
      ...player('template', overall: 78),
      'name': 'Samuel atualizado',
    });
    expect(
      (await sql.getCustomPlayerById('career', first['id'] as String))!['name'],
      'Samuel Guimarães',
    );
    final third = await sql.useSharedPlayer(
      personId: 'future',
      templateId: 'template',
    );
    expect(third['name'], 'Samuel atualizado');
    expect(third['overall'], 78);
    expect(await db.query('Overall'), hasLength(1));
  });

  test('library and imported careers own separate photos', () async {
    final source = await CustomImageFiles.store(
      File('assets/branding/fc-career-live-icon.png').absolute.path,
      'faces',
      'career/photo-source',
    );
    await sql.createCustomPlayer({
      ...player('photo'),
      'customAvatarFilePath': source,
    });
    final template = (await sql.getSharedPlayers()).single;
    expect(template['customAvatarFilePath'], isNot(source));
    final first = await sql.useSharedPlayer(
      personId: 'other',
      templateId: 'photo',
    );
    final second = await sql.useSharedPlayer(
      personId: 'third',
      templateId: 'photo',
    );
    final paths = [
      source,
      template['customAvatarFilePath'],
      first['customAvatarFilePath'],
      second['customAvatarFilePath'],
    ];
    expect(paths.toSet(), hasLength(4));
    for (final path in paths) {
      expect(
        await File(CustomImageFiles.absolute(path as String)!).readAsBytes(),
        await File('assets/branding/fc-career-live-icon.png').readAsBytes(),
      );
    }
    await CustomImageFiles.deleteFile(source);
    expect(
      await File(
        CustomImageFiles.absolute(template['customAvatarFilePath'] as String)!,
      ).exists(),
      true,
    );
  });

  test('invalid season rolls back imported identity and a full lineup uses the bench', () async {
    await sql.saveSharedPlayer(player('template'));
    await expectLater(
      sql.useSharedPlayer(
        personId: 'career',
        templateId: 'template',
        seasonId: 'invalid',
      ),
      throwsStateError,
    );
    expect(await db.query('CustomCreatedPlayer'), isEmpty);
    for (var i = 0; i < 11; i++) {
      await db.insert('TeamPlayer', {
        'id': 'r$i',
        'personId': 'career',
        'seasonId': reviewSeason().id,
        'playerId': 'p$i',
        'isBench': 0,
      });
    }
    final chosen = await sql.useSharedPlayer(
      personId: 'career',
      templateId: 'template',
      seasonId: reviewSeason().id,
    );
    final rows = await db.query(
      'TeamPlayer',
      where: 'playerId = ?',
      whereArgs: [chosen['id']],
    );
    expect(rows.single['isBench'], 1);
    await sql.useSharedPlayer(
      personId: 'career',
      templateId: 'template',
      seasonId: reviewSeason().id,
    );
    expect(await db.query('TeamPlayer'), hasLength(12));
  });

  test(
    'backup preserves templates and old backups publish legacy players',
    () async {
      await sql.createCustomPlayer(player('legacy'));
      await sql.saveSharedPlayer(player('global', overall: 80));
      const tables = [
        'Persons',
        'Seasons',
        'CustomCreatedPlayer',
        'CustomPlayerTemplate',
      ];
      final backup = jsonEncode([
        tables,
        [for (final table in tables) await db.query(table)],
        32,
        {'app': BackupService.appMarker},
      ]);
      final service = BackupService(database: () async => db);
      await service.restoreJsonBackup(backup);
      expect(await sql.getSharedPlayers(), hasLength(2));
      expect(
        (await db.query('CustomCreatedPlayer')).single['libraryPlayerId'],
        'legacy',
      );
      final legacy = player('old-backup');
      await service.restoreJsonBackup(
        jsonEncode([
          ['CustomCreatedPlayer'],
          [
            [legacy],
          ],
          31,
          {'app': BackupService.appMarker},
        ]),
      );
      expect((await sql.getSharedPlayers()).single['id'], 'old-backup');
    },
  );

  for (final existingPhoto in [false, true]) {
    test(
      'old ZIP backup publishes independent photos after restoring files (existing: $existingPhoto)',
      () async {
        final docs = await CustomImageFiles.docsDir();
        const relative = '/faces/career/restored/player.png';
        final original = File('$docs$relative');
        await original.parent.create(recursive: true);
        final bytes = await File('assets/branding/fc-career-live-icon.png')
            .readAsBytes();
        if (existingPhoto) {
          await original.writeAsBytes([1, 2, 3]);
        } else if (await original.exists()) {
          await original.delete();
        }
        final payload = jsonEncode([
          ['Persons', 'Seasons', 'CustomCreatedPlayer'],
          [
            [reviewPerson().toMap()],
            [reviewSeason().toMap()],
            [
              {...player('restored'), 'customAvatarFilePath': relative},
            ],
          ],
          31,
          {'app': BackupService.appMarker},
        ]);
        final archive = Archive()
          ..addFile(
            ArchiveFile(
              'temp_backup/backup.json',
              utf8.encode(payload).length,
              utf8.encode(payload),
            ),
          )
          ..addFile(ArchiveFile('temp_backup$relative', bytes.length, bytes));
        final backup = File('$docs/old-player-backup.zip');
        await backup.writeAsBytes(ZipEncoder().encode(archive));
        final report = await BackupService(database: () async => db)
            .restoreBackup(backup.path);
        expect(report.restoredImageFolders, contains('faces'));
        final template = (await sql.getSharedPlayers()).single;
        final avatar = template['customAvatarFilePath'] as String;
        expect(avatar, startsWith('/faces/library/restored/'));
        expect(
          await File(CustomImageFiles.absolute(avatar)!).readAsBytes(),
          bytes,
        );
        await original.delete();
        expect(await File(CustomImageFiles.absolute(avatar)!).exists(), true);
        await backup.delete();
      },
    );
  }

  test('settings keep imported teams editable when another version has their catalog IDs', () async {
    final source = catalog
        .getAllLeagues('FIFA23')
        .firstWhere((l) => l.id == '40');
    expect(catalog.getAllLeagues('FC26').any((l) => l.id == source.id), false);
    await SharedClubAvailability.save(
      db,
      catalog,
      club('shared-old-league', source.id, 'FIFA23,FC26'),
      'FIFA23',
    );
    await refreshCatalog();
    final settings = catalog.getAllLeagues().singleWhere(
      (l) => l.id == source.id,
    );
    expect(settings.teams.where((t) => t.isCustom).map((t) => t.id).toSet(), {
      ...source.teams.map((t) => t.id),
      'shared-old-league',
    });
    expect(
      settings.teams.map((t) => t.id).toSet().length,
      settings.teams.length,
    );
  });

  test('missing catalog league is imported with its teams only in selected versions', () async {
    final source = catalog
        .getAllLeagues('FC26')
        .firstWhere((l) => l.id == '1014');
    expect(catalog.getAllLeagues('FIFA23').any((l) => l.id == '1014'), false);
    final newClub = club('shared', '1014', 'FC26,FIFA23');
    await SharedClubAvailability.save(db, catalog, newClub, 'FC26');
    await refreshCatalog();
    final imported = catalog
        .getAllLeagues('FIFA23')
        .singleWhere((l) => l.id == '1014');
    expect(imported.teams.map((t) => t.id).toSet(), {
      ...source.teams.map((t) => t.id),
      'shared',
    });
    expect(
      catalog
          .getAllLeagues('FC26')
          .singleWhere((l) => l.id == '1014')
          .teams
          .any((t) => t.id == 'shared'),
      true,
    );
    expect(
      catalog
          .getAllLeagues('FC25')
          .any((l) => l.teams.any((t) => t.id == 'shared')),
      false,
    );
    expect(imported.label, source.label);
    await SharedClubAvailability.save(db, catalog, newClub, 'FC26');
    expect(await db.query('CustomLeague'), hasLength(1));
    expect(await db.query('CustomClub'), hasLength(source.teams.length + 1));
  });

  test('custom league extension imports original clubs without duplicating their identities', () async {
    final league = CustomLeague(
      id: 'custom-league',
      label: 'Liga criada',
      fifaVersion: 'FC26',
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('CustomLeague', league.toMap());
    for (final id in ['a', 'b']) {
      await db.insert('CustomClub', club(id, league.id, 'FC26').toMap());
    }
    await refreshCatalog();
    await SharedClubAvailability.save(
      db,
      catalog,
      club('shared', league.id, 'FC26,FC25'),
      'FC26',
    );
    await refreshCatalog();
    expect(catalog.customLeague(league.id)!.fifaVersions.toSet(), {
      'FC26',
      'FC25',
    });
    for (final version in ['FC26', 'FC25']) {
      expect(
        catalog
            .getAllLeagues(version)
            .singleWhere((l) => l.id == league.id)
            .teams
            .map((t) => t.id)
            .toSet(),
        {'a', 'b', 'shared'},
      );
    }
    expect(catalog.getAllLeagues('FC24').any((l) => l.id == league.id), false);
    expect(
      catalog.getAllLeagues().singleWhere((l) => l.id == league.id).teams,
      hasLength(3),
    );
  });

  test('existing destination competition stays intact and failed imports are atomic', () async {
    final source = catalog
        .getAllLeagues('FC26')
        .firstWhere((l) => l.id == '1014');
    await SharedClubAvailability.save(
      db,
      catalog,
      club('available', source.id, 'FC26,FC25'),
      'FC26',
    );
    expect(await db.query('CustomLeague'), isEmpty);
    expect(await db.query('CustomClub'), hasLength(1));
    await db.execute(
      "CREATE TRIGGER fail_shared BEFORE INSERT ON CustomClub WHEN NEW.id = 'fail' BEGIN SELECT RAISE(ABORT, 'test failure'); END",
    );
    await expectLater(
      SharedClubAvailability.save(
        db,
        catalog,
        club('fail', source.id, 'FC26,FIFA23'),
        'FC26',
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect(await db.query('CustomLeague'), isEmpty);
    expect(await db.query('CustomClub'), hasLength(1));
  });
}
