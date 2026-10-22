import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileData.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileCharts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test('Opening a v40 career repairs copied values, keeps 2029 edits and aligns profile and chart', () async {
    final directory = await Directory('build/test-databases')
        .create(recursive: true);
    final file = File(
      '${directory.absolute.path}/season-values-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    Database? opened;
    try {
      var db = opened = await SqlService.openCareerDatabase(file.path);
      await db.insert('Persons', reviewPerson().toMap());
      for (final year in [2028, 2029]) {
        await db.insert(
          'Seasons',
          reviewSeason(id: 's$year', year: year).toMap(),
        );
      }
      for (final id in ['copied', 'edited']) {
        await db.insert('CustomCreatedPlayer', {
          'id': id,
          'personId': 'career',
          'name': id,
          'positionId': '25',
          'overall': 73,
          'potential': 85,
          'realFace': 0,
          'fromRealPlayer': 0,
          'foot': 'Right',
        });
        for (final year in [2028, 2029]) {
          await db.insert('TeamPlayer', {
            'id': '$id-$year',
            'personId': 'career',
            'seasonId': 's$year',
            'playerId': id,
            'isBench': 0,
            'overall': year == 2029 && id == 'edited' ? 76 : 73,
            'marketValue': year == 2029 && id == 'edited' ? 8000000 : 5000000,
          });
        }
        await db.insert('Overall', {
          'id': id,
          'personId': 'career',
          'customPlayerId': id,
          'date': '2028-08-20',
          'createdAt': '2028-08-20',
          'overall': 75,
        });
        await db.insert('MarketValue', {
          'id': id,
          'personId': 'career',
          'customPlayerId': id,
          'date': '2028-09-03',
          'createdAt': '2028-09-03',
          'value': 6500000,
        });
      }
      await db.insert('SeasonRosterInitialization', {
        'personId': 'career',
        'seasonId': 's2029',
        'sourceSeasonId': 's2028',
        'teamId': '40-13',
        'createdAt': '2029-01-01',
      });
      await db.execute(
        'ALTER TABLE SeasonRosterInitialization DROP COLUMN valueRevision',
      );
      await db.setVersion(40);
      await db.close();
      db = opened = await SqlService.openCareerDatabase(file.path);
      expect(await db.getVersion(), 46);
      final sql = SqlService.withDatabase(db);
      final roster = await sql.getTeamPlayers('career', 's2029');
      final copied = roster.singleWhere((r) => r['playerId'] == 'copied');
      expect(copied['overall'], 75);
      expect(copied['marketValue'], 6500000);
      final edited = roster.singleWhere((r) => r['playerId'] == 'edited');
      expect(edited['overall'], 76);
      expect(edited['marketValue'], 8000000);
      final history = await sql.getPlayerHistory('career', 'edited', 'Overall');
      final market = await sql.getPlayerHistory(
        'career',
        'edited',
        'MarketValue',
      );
      final profile = PlayerProfileData(
        seasons: const [],
        matches: const [],
        overalls: history,
        marketValues: market,
        contracts: const [],
        tournamentNames: const {},
      );
      expect(profile.latestOverall, 76);
      expect(profile.latestMarketValue, 8000000);
      final marker = profileHistoryPoints(history, 'overall').last;
      expect(marker.value, 76);
      expect(marker.date, DateTime(2029));
      expect(marker.caption, 'Início da temporada');
      expect(
        (await sql.getPlayerSeasonRows('career', 'edited')).last['overall'],
        73,
      );
      await db.update(
        'TeamPlayer',
        {'overall': 73},
        where: 'id = ?',
        whereArgs: ['edited-2029'],
      );
      expect(
        (await sql.getTeamPlayers(
          'career',
          's2029',
        )).singleWhere((r) => r['playerId'] == 'edited')['overall'],
        73,
      );
      expect(await db.query('Overall'), hasLength(2));
      expect(await db.query('MarketValue'), hasLength(2));
    } finally {
      await opened?.close();
      if (await file.exists()) await file.delete();
    }
  });
}
