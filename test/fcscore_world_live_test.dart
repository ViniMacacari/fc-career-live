import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/FcScore/FcScoreModels.dart';
import 'package:mcmanager/FcScore/FcScoreRepository.dart';
import 'package:mcmanager/FcScore/FcScoreWorldData.dart';
import 'package:mcmanager/FcScore/FcScorePlayerCreation.dart';
import 'package:mcmanager/models/Season.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final address = Platform.environment['FC_SCORE_LIVE_URL'];
  test(
    'Real API: entire competition imports locally with all teams and no duplicates',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final api = FcScoreApi(fcScoreAddress(address!));
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(() async {
        api.close();
        await db.close();
      });
      await SqlService.ensureCompatibleSchema(db);
      await SqlService.ensureSeasonClosureSchema(db);
      await SqlService.ensureFixtureFormationSchema(db);
      await SqlService.ensureOpponentLineupSchema(db);
      final meta = await api.connect();
      final saves = await api.list('careers');
      final saveId = fcId(
        saves.firstWhere((s) => s['careerType'] == 'manager')['id'],
      );
      final remote = await FcScoreRemoteCareer.load(
        api,
        saveId,
        fcId(meta['gameVersion']),
      );
      final date = DateTime.parse(fcId(remote.overview['currentDate']));
      final person = reviewPerson();
      final season = Season(
        id: 'live-world-season',
        personId: person.id,
        startDate: DateTime(date.year),
        endDate: DateTime(date.year, 12, 31),
        createdAt: DateTime.now(),
      );
      await db.insert('Persons', person.toMap());
      await db.insert('Seasons', season.toMap());
      final calendar = await FcScoreWorldData.fixturesFor(api, saveId);
      final competition = remote.competitions.firstWhere(
        (c) => fcId(c['code']) == 'C${remote.league['id']}',
      );
      final data = await FcScoreWorldData.load(
        api: api,
        remote: remote,
        season: season,
        calendar: calendar,
        competitionIds: {fcId(competition['id'])},
      );
      final repo = FcScoreRepository(sql: SqlService.withDatabase(db));
      final link = FcScoreLink(
        personId: person.id,
        saveId: saveId,
        saveName: remote.saveName,
        gameVersion: remote.gameVersion,
        remoteClubId: fcId(remote.club['id']),
        localClubId: person.teamId,
        localLeagueId: person.leagueId,
        seasonId: season.id,
        teams: {
          for (final t in data.teams)
            fcId(t['id']): fcId(t['id']) == fcId(remote.club['id'])
                ? person.teamId
                : 'new:${fcName(t['name'])}',
        },
        competitions: {
          fcId(competition['id']): 'new:${fcName(competition['name'])}',
        },
      );
      for (final t in data.teams) {
        if (fcId(t['id']) == link.remoteClubId) continue;
        for (final p in fcList(t['roster'])) {
          if (!fcCanCreatePlayer(p)) {
            link.players[fcId(p['id'])] = fcCreatePlayerChoice(
              p,
              fcGeneratePlayerProfile(p),
              generated: true,
            );
          }
        }
      }
      final result = await repo.importWorld(
        person: person,
        link: link,
        data: data,
        preserveOwnPlayers: true,
      );
      expect(result.teams, greaterThan(1));
      expect(result.players, greaterThan(22));
      expect(result.fixtures, greaterThan(result.ownMatches));
      expect((await repo.careerCompetitions(person.id)).length, 1);
      expect(
        (await repo.careerTeams(person.id, season.id)).length,
        result.teams,
      );
      expect(
        (await repo.careerRoster(
          person.id,
          season.id,
          fcId(data.teams.first['id']),
        )).length,
        fcList(data.teams.first['roster']).length,
      );
      final repeated = await repo.importWorld(
        person: person,
        link: link,
        data: data,
        preserveOwnPlayers: true,
      );
      expect(repeated.ownMatches, 0);
      expect(repeated.preservedMatches, result.ownMatches);
      expect((await db.query('FcScoreWorldPlayer')).length, data.playerCount);
      expect((await db.query('FcScoreWorldFixture')).length, result.fixtures);
      final localStats = await repo.competitionScorers(
        person,
        (await repo.careerCompetitions(person.id)).single,
      );
      final oracle = await FcScoreWorldData.statisticsFor(
        api,
        saveId,
        fcId(competition['id']),
      );
      expect(localStats.complete, isTrue);
      expect(localStats.statistics.length, oracle.length);
      expect(localStats.players.first['goals'], oracle.first['goals']);
      expect(
        localStats.players
            .map((p) => '${p['remoteTeamId']}:${p['id']}')
            .toSet(),
        oracle
            .where((p) => (fcInt(p['goals']) ?? 0) > 0)
            .map(
              (p) =>
                  '${fcObject(p['team'])['id']}:${fcObject(p['player'])['id']}',
            )
            .toSet(),
      );
    },
    skip: address == null
        ? 'Set FC_SCORE_LIVE_URL for read-only local API integration.'
        : false,
  );
}
