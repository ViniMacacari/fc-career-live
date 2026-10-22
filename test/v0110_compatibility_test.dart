import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Settings/AdvancedSettingsPage.dart';
import 'package:mcmanager/utils/BackupService.dart';
import 'package:mcmanager/utils/CompetitionTrophies.dart';
import 'package:mcmanager/utils/Components/CatalogLogoAssets.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/databaseUtils.dart';
import 'package:mcmanager/utils/competitions/TournamentAutomation.dart';
import 'package:mcmanager/models/Tournament.dart';
import 'package:mcmanager/models/Trophy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Existing disabled preference cannot turn off recorded goals', () async {
    SharedPreferences.setMockInitialValues({'auto_fill_team_score': false});
    expect(await AdvancedSettings.autoFillTeamScore(), isTrue);
  });

  test('Backup filename contains local date, time and a safe club name', () {
    expect(
      BackupService.backupFileName(
        DateTime(2026, 10, 20, 7, 8, 9),
        'São Paulo',
      ),
      'carreira_2026-10-20_07-08-09_São_Paulo.zip',
    );
    expect(
      BackupService.backupFileName(DateTime(2026), '  A/B:C*?  '),
      'carreira_2026-01-01_00-00-00_ABC.zip',
    );
  });

  test('v43 career migrates without changing any existing table or record', () async {
    final dir = await Directory('build/test-databases').create(recursive: true);
    final file = File(
      '${dir.absolute.path}/v0110-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    Database? opened;
    try {
      var db = opened = await SqlService.openCareerDatabase(file.path);
      await db.insert('Persons', reviewPerson().toMap());
      await db.insert('Seasons', reviewSeason().toMap());
      await db.execute('DROP TABLE CompetitionTrophy');
      await db.setVersion(43);
      Future<Map<String, Object>> snapshot(Database db) async => {
        for (final row in await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
        ))
          row['name'] as String: await db.query(row['name'] as String),
      };
      final previous = await snapshot(db);
      await db.close();
      db = opened = await SqlService.openCareerDatabase(file.path);
      expect(await db.getVersion(), 46);
      final current = await snapshot(db);
      expect(current.remove('CompetitionTrophy'), isEmpty);
      expect(current, previous);
      const trophy = CompetitionTrophy(
        competitionId: 'league:custom',
        version: 'FC26',
        name: 'Taça da liga',
        imagePath: '/trophies/custom/cup.png',
      );
      await CompetitionTrophies.save(db, trophy);
      await db.close();
      db = opened = await SqlService.openCareerDatabase(file.path);
      final restored = (await CompetitionTrophies.all(database: db)).single;
      expect(restored.toMap(), trophy.toMap());
      expect(restored.awardId, 'competition:FC26:league:custom');
    } finally {
      if (opened?.isOpen == true) await opened!.close();
      if (file.existsSync()) await file.delete();
    }
  });

  test(
    'Bundled competition logos resolve numeric IDs, variants and league names',
    () async {
      final champions = await CatalogLogoAssets.tournament('1', 'FC26');
      expect(champions, isNotNull);
      expect(champions, isNot(contains('1-w-')));
      final women = await CatalogLogoAssets.tournament('1-w', 'FC26');
      expect(women, contains('1-w-'));
      expect(
        await CatalogLogoAssets.league('Brasileiro Série A'),
        contains('86-Brasileiro_Serie_A'),
      );
      expect(
        await CatalogLogoAssets.tournament('not-a-real-competition', 'FC26'),
        isNull,
      );
    },
  );

  test('Competition trophy updates an existing title, respects manual trophies and survives edits', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory(
      'build/test-databases/trophy-${DateTime.now().microsecondsSinceEpoch}',
    ).absolute.create(recursive: true);
    await databaseFactory.setDatabasesPath(dir.path);
    final sql = SqlService.instance;
    final db = await sql.database;
    final person = reviewPerson(), season = reviewSeason();
    const tournament = Tournament(
      id: 'custom-cup',
      name: 'Copa personalizada',
      type: 'custom',
      fifaVersions: 'FC26',
      format: 'single',
    );
    const linked = CompetitionTrophy(
      competitionId: 'custom-cup',
      version: 'FC26',
      name: 'Taça personalizada',
      imagePath: '/trophies/custom-cup/trophy.png',
    );
    try {
      await db.insert('Persons', person.toMap());
      await db.insert('Seasons', season.toMap());
      await CustomContentService.createCustomTournament(tournament, null);
      await db.insert('ManagerFixtures', {
        ...reviewFixture(1, tournament: tournament.id),
        'stage': 'Finale',
      });
      await TournamentAutomation.sync(person);
      final original = (await sql.getTrophies(person.id)).single;
      expect(original['awardId'], TournamentAutomation.otherTrophy);
      await db.update(
        'Trophies',
        {'count': 2},
        where: 'id = ?',
        whereArgs: [original['id']],
      );
      await CustomContentService.updateCustomTournament(
        tournament,
        null,
        trophy: linked,
      );
      await TournamentAutomation.sync(person);
      final updated = (await sql.getTrophies(person.id)).single;
      expect(updated['id'], original['id']);
      expect(updated['awardId'], linked.awardId);
      expect(updated['count'], 2);
      expect(updated['date'], original['date']);
      await sql.deleteTrophy(updated['id'] as String);
      await sql.saveTrophy(
        Trophy(
          id: 'my-trophy',
          teamId: person.teamId,
          isNational: false,
          awardId: TournamentAutomation.otherTrophy,
          count: 3,
          seasonId: season.id,
          personId: person.id,
          description: tournament.name,
        ),
      );
      await TournamentAutomation.sync(person);
      final manual = (await sql.getTrophies(person.id)).single;
      expect(manual['id'], 'my-trophy');
      expect(manual['count'], 3);
      const edited = CompetitionTrophy(
        competitionId: 'custom-cup',
        version: 'FC26',
        name: 'Taça editada',
      );
      await CustomContentService.updateCustomTournament(
        tournament,
        null,
        trophy: edited,
      );
      final awards = await (await GameCatalog.load()).awards();
      expect(
        awards.singleWhere((a) => a.id == linked.awardId).label,
        edited.name,
      );
    } finally {
      await db.close();
      final file = File('${dir.path}/mc_ea_rebuild.db');
      if (await file.exists()) await file.delete();
    }
  });
}
