import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/FcScore/FcScoreModels.dart';
import 'package:mcmanager/FcScore/FcScoreMappingIssues.dart';
import 'package:mcmanager/FcScore/FcScoreRepository.dart';
import 'package:mcmanager/FcScore/FcScoreSchema.dart';
import 'package:mcmanager/FcScore/FcScoreWorldData.dart';
import 'package:mcmanager/FcScore/FcScoreWorldPlayerReview.dart';
import 'package:mcmanager/FcScore/FcScorePlayerCreation.dart';
import 'package:mcmanager/FcScore/FcScoreSeasonStats.dart';
import 'package:mcmanager/FcScore/FcScoreUpdateOptions.dart';
import 'package:mcmanager/utils/BackupService.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/SeasonClosureService.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fcscore_fixture.dart';
import 'fcscore_world_fixture.dart';
import 'season_review_fixture.dart';
import 'backup_storage_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late FcScoreRepository repo;
  late FcScoreLink link;
  final person = reviewPerson(), season = reviewSeason(id: 's2028', year: 2028);
  setUpAll(() {
    mockBackupStorage();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory('build/fcscore-world-docs').absolute.path,
        );
  });
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqlService.ensureCompatibleSchema(db);
    await SqlService.ensureSeasonClosureSchema(db);
    await SqlService.ensureFixtureFormationSchema(db);
    await SqlService.ensureOpponentLineupSchema(db);
    await db.execute(
      'ALTER TABLE ManagerFixtures ADD COLUMN opponentStats TEXT',
    );
    await db.insert('Persons', person.toMap());
    await db.insert('Seasons', season.toMap());
    repo = FcScoreRepository(sql: SqlService.withDatabase(db));
    link = apiLink()..teams['300'] = 'new:Terceiro FC';
  });
  tearDown(() async => db.close());
  Future<FcWorldImportResult> import({
    FcScoreWorldData? data,
    bool own = true,
  }) => repo.importWorld(
    person: person,
    link: link,
    data: data ?? worldData(),
    importOwnMatches: own,
  );

  test('Mapping conflicts identify both API teams and the app target before any write', () async {
    link.teams['300'] = 'rival';
    final issues = await repo.worldMappingIssues(
      person: person,
      link: link,
      data: worldData(),
    );
    final issue = issues.single;
    expect(issue.remoteIds, {'200', '300'});
    expect(issue.message, contains('Rival FC'));
    expect(issue.message, contains('Terceiro FC'));
    expect(issue.message, contains('200'));
    expect(issue.message, contains('300'));
    expect(issue.message, contains('rival'));
    await expectLater(import(), throwsA(isA<FcWorldMappingException>()));
    expect(await db.query('TeamPlayer'), isEmpty);
    expect(await db.query('ManagerFixtures'), isEmpty);
    link.teams['300'] = 'new:Terceiro FC';
    expect(
      await repo.worldMappingIssues(
        person: person,
        link: link,
        data: worldData(),
      ),
      isEmpty,
    );
    expect((await import()).teams, 3);
  });

  test('A new club draft resolving to an existing custom club is checked as that same club', () async {
    await db.insert('CustomClub', {
      'id': 'custom-rival',
      'personId': 'career',
      'label': 'Rival criado',
      'leagueId': '1014',
      'fifaVersion': 'FC26',
    });
    link.teams['200'] = 'custom-rival';
    link.teams['300'] = 'new:Rival criado';
    final issues = await repo.worldMappingIssues(
      person: person,
      link: link,
      data: worldData(),
    );
    expect(issues.single.remoteIds, {'200', '300'});
    expect(issues.single.message, contains('Rival criado'));
    await expectLater(import(), throwsA(isA<FcWorldMappingException>()));
    expect(await db.query('CustomClub'), hasLength(1));
  });

  test('The own-club mismatch has a distinct actionable diagnostic', () async {
    link.teams['598'] = 'wrong-club';
    final issues = await repo.worldMappingIssues(
      person: person,
      link: link,
      data: worldData(),
    );
    expect(issues.single.restoreOwnClub, isTrue);
    expect(issues.single.message, contains('598'));
    expect(issues.single.message, contains('wrong-club'));
    expect(issues.single.message, contains('40-13'));
  });

  test('Invalid player counters identify player, team, API field and rejected value', () async {
    final data = worldData();
    (data.teams[1]['roster'] as List).first['leagueGoals'] = -4;
    await expectLater(
      import(data: data),
      throwsA(
        predicate(
          (e) =>
              e.toString().contains('João Souza') &&
              e.toString().contains('Rival FC') &&
              e.toString().contains('leagueGoals') &&
              e.toString().contains('-4'),
        ),
      ),
    );
    expect(await db.query('ManagerFixtures'), isEmpty);
  });

  test('Quick refresh only writes selected sections and preserves unchecked snapshots', () async {
    await import();
    final oldCompetitions = await db.query('FcScoreCompetition');
    final oldCalendar = await db.query('FcScoreWorldFixture');
    final oldPlayers = await db.query('FcScoreWorldPlayer');
    final oldTeams = await db.query('FcScoreWorldTeam');
    final oldOveralls = await db.query('Overall');
    final next = worldData(date: '2028-07-01');
    next.fixtures.first['date'] = '2028-06-29';
    for (final team in next.teams) {
      final player = (team['roster'] as List).single as Map;
      player['overall'] = 99;
      player['leagueGoals'] = 44;
    }
    await repo.importWorld(
      person: person,
      link: link,
      data: next,
      importOwnMatches: false,
      rememberSkippedOwnMatches: false,
      updateOptions: const FcScoreUpdateOptions(
        competitions: false,
        squads: false,
        overalls: false,
      ),
    );
    expect(await db.query('FcScoreCompetition'), oldCompetitions);
    expect(await db.query('FcScoreWorldPlayer'), oldPlayers);
    expect(await db.query('FcScoreWorldTeam'), oldTeams);
    expect(await db.query('Overall'), oldOveralls);
    expect(await db.query('FcScoreWorldFixture'), isNot(oldCalendar));
    final calendarAfter = await db.query('FcScoreWorldFixture');
    await repo.importWorld(
      person: person,
      link: link,
      data: next,
      importOwnMatches: false,
      rememberSkippedOwnMatches: false,
      updateOptions: const FcScoreUpdateOptions(calendar: false, squads: false),
    );
    expect(await db.query('FcScoreWorldFixture'), calendarAfter);
    expect(await db.query('FcScoreWorldPlayer'), oldPlayers);
    expect(await db.query('Overall'), oldOveralls);
    expect(
      (await db.query('FcScoreCompetition')).single['currentDate'],
      '2028-07-01',
    );
    expect(await db.query('ManagerFixtures'), hasLength(1));
  });

  test('Quick refresh squad and overall options are independent and own squad is protected', () async {
    await import();
    final oldCompetitions = await db.query('FcScoreCompetition');
    final oldCalendar = await db.query('FcScoreWorldFixture');
    final oldOwn = (await db.query(
      'FcScoreWorldPlayer',
      where: 'remoteTeamId = ?',
      whereArgs: ['598'],
    )).single;
    final oldOveralls = await db.query('Overall');
    final next = worldData(date: '2028-07-01');
    for (final team in next.teams) {
      ((team['roster'] as List).single as Map)['overall'] = 99;
    }
    await repo.importWorld(
      person: person,
      link: link,
      data: next,
      importOwnMatches: false,
      updateOptions: const FcScoreUpdateOptions(
        competitions: false,
        calendar: false,
        overalls: false,
      ),
    );
    expect(await db.query('FcScoreCompetition'), oldCompetitions);
    expect(await db.query('FcScoreWorldFixture'), oldCalendar);
    expect(await db.query('Overall'), oldOveralls);
    expect(
      (await db.query(
        'FcScoreWorldPlayer',
        where: 'remoteTeamId = ?',
        whereArgs: ['598'],
      )).single,
      oldOwn,
    );
    expect(
      fcObject(
        jsonDecode(
          (await db.query(
                'FcScoreWorldPlayer',
                where: 'remoteTeamId = ?',
                whereArgs: ['200'],
              )).single['rawJson']
              as String,
        ),
      )['overall'],
      99,
    );
    await repo.importWorld(
      person: person,
      link: link,
      data: next,
      importOwnMatches: false,
      updateOptions: const FcScoreUpdateOptions(
        competitions: false,
        calendar: false,
      ),
    );
    expect((await db.query('Overall')).length, greaterThan(oldOveralls.length));
    expect(
      (await db.query(
        'FcScoreWorldPlayer',
        where: 'remoteTeamId = ?',
        whereArgs: ['598'],
      )).single,
      oldOwn,
    );
  });

  test(
    'Update choices survive save changes and remain scoped to each career',
    () async {
      await import();
      const options = FcScoreUpdateOptions(
        competitions: false,
        squads: false,
        ownSquad: true,
        overalls: false,
      );
      await repo.rememberUpdateOptions(person.id, options);
      final stored = (await repo.linkFor(person.id))!;
      final moved = await repo.moveLink(stored, 'new-save-file');
      expect(moved.updateOptions!.toMap(), options.toMap());
      expect(
        link.withSavedMappings(stored).updateOptions!.toMap(),
        options.toMap(),
      );
      final other = FcScoreLink.fromMap({
        ...stored.toMap(),
        'personId': 'other-career',
        'updateOptions': null,
      });
      await repo.moveLink(other, 'other-save');
      expect((await repo.linkFor('other-career'))!.updateOptions, isNull);
      expect(
        (await repo.linkFor(person.id))!.updateOptions!.toMap(),
        options.toMap(),
      );
    },
  );

  test('Classification match links preserve explicit imports and only resolve unique manual matches', () async {
    await import();
    final fixture = (await db.query('ManagerFixtures')).single;
    final nativeId = fixture['id'];
    final imported = (await db.query('FcScoreImport')).single;
    final remoteKey = imported['remoteKey'] as String;
    Future<Map<String, String>> links() =>
        repo.competitionFixtureLinks(person, 's2028', '1528');
    expect(await links(), {remoteKey: nativeId});
    expect(
      await repo.competitionFixtureLinks(person, 's2027', '1528'),
      isEmpty,
    );
    await db.delete('FcScoreImport');
    expect(await links(), {remoteKey: nativeId});
    await db.insert('ManagerFixtures', {...fixture, 'id': 'manual-duplicate'});
    expect(await links(), isEmpty);
    await db.insert('FcScoreImport', imported);
    expect(await links(), {remoteKey: nativeId});
    await db.delete(
      'ManagerFixtures',
      where: 'id = ?',
      whereArgs: ['manual-duplicate'],
    );
    await db.insert('ManagerFixtures', {
      ...fixture,
      'id': 'foreign',
      'personId': 'other-person',
    });
    await db.insert('ManagerFixtures', {
      ...fixture,
      'id': 'other-season',
      'seasonId': 's2027',
    });
    await db.delete('FcScoreImport');
    expect(await links(), {remoteKey: nativeId});
    await db.update(
      'ManagerFixtures',
      {'playerTeamScore': 9},
      where: 'id = ?',
      whereArgs: [nativeId],
    );
    expect(await links(), {remoteKey: nativeId});
    await db.delete('ManagerFixtures', where: 'id = ?', whereArgs: [nativeId]);
    expect(await links(), isEmpty);
    expect(await db.query('FcScoreImport'), isEmpty);
  });

  test(
    'Unchanged players and overalls are reused while statistics refresh',
    () async {
      final first = await import();
      expect(first.newPlayers, 3);
      expect(first.reusedPlayers, 0);
      final before = await db.rawQuery(
        'SELECT rowid, * FROM FcScoreWorldPlayer',
      );
      final profiles = await db.query('CustomCreatedPlayer');
      final overalls = await db.query('Overall');
      final progress = <double>[];
      final repeated = await repo.importWorld(
        person: person,
        link: link,
        data: worldData(date: '2028-07-01'),
        onProgress: progress.add,
      );
      expect(repeated.newPlayers, 0);
      expect(repeated.reusedPlayers, 3);
      expect(
        await db.rawQuery('SELECT rowid, * FROM FcScoreWorldPlayer'),
        before,
      );
      expect(await db.query('CustomCreatedPlayer'), profiles);
      expect(await db.query('Overall'), overalls);
      expect(progress.last, 1);
      expect(progress, orderedEquals([...progress]..sort()));
      final changed = worldData(date: '2028-07-02');
      final player = (changed.teams[1]['roster'] as List).first as Map;
      player['overall'] = 85;
      player['leagueGoals'] = 21;
      await import(data: changed);
      expect(await db.query('CustomCreatedPlayer'), profiles);
      expect(await db.query('Overall'), hasLength(overalls.length + 1));
      final roster = await repo.careerRoster(person.id, link.seasonId, '200');
      expect(roster.single['overall'], 85);
      expect(roster.single['leagueGoals'], 21);
    },
  );

  test('Update additions exclude configured and ignored matches', () async {
    await import(own: false);
    final existing = await repo.previewWorldAdditions(
      person: person,
      link: link,
      data: worldData(),
      selectedMatchKeys: {},
    );
    expect(existing, (teams: 0, matches: 0));
    final changed = worldData(date: '2028-07-01');
    changed.fixtures.add({
      ...changed.fixtures[1],
      'id': 100,
      'date': '2028-07-01',
    });
    changed.teams.add({
      ...changed.teams[1],
      'id': 999,
      'name': 'Novo time',
      'roster': [],
    });
    final next = await repo.previewWorldAdditions(
      person: person,
      link: link,
      data: changed,
      selectedMatchKeys: {},
    );
    expect(next, (teams: 1, matches: 1));
    expect(await db.query('FcScoreWorldTeam'), hasLength(3));
    expect(await db.query('ManagerFixtures'), isEmpty);
  });

  test(
    'Career connection is preserved when the save filename changes',
    () async {
      await import();
      final connected = await repo.rememberCareerAddress(
        link,
        Uri.parse('http://192.168.0.8:38291/api'),
      );
      final moved = await repo.moveLink(connected, 'save-B');
      expect(moved.connectionAddress, 'http://192.168.0.8:38291/api');
      expect(
        (await repo.linkFor(person.id))!.connectionAddress,
        moved.connectionAddress,
      );
      expect(moved.players, link.players);
    },
  );

  test(
    'Sync choices round-trip without sharing ignored games across copies',
    () {
      link.worldSync[season.id] = FcWorldSyncState(
        competitionIds: {'1528'},
        ignoredMatchKeys: {'ignored'},
        preserveOwnPlayers: false,
        bringOwnSquad: true,
        updateOveralls: false,
      );
      final restored = FcScoreLink.fromMap(
        fcObject(jsonDecode(jsonEncode(link.toMap()))),
      );
      expect(restored.worldSync[season.id]!.ignoredMatchKeys, {'ignored'});
      expect(restored.worldSync[season.id]!.preserveOwnPlayers, isFalse);
      expect(restored.worldSync[season.id]!.bringOwnSquad, isTrue);
      expect(restored.worldSync[season.id]!.updateOveralls, isFalse);
      final copy = restored.copy();
      copy.worldSync[season.id]!.ignoredMatchKeys.add('another');
      expect(restored.worldSync[season.id]!.ignoredMatchKeys, {'ignored'});
    },
  );
  test('Quick refresh adds no career matches and leaves unseen games available for explicit import', () async {
    final data = worldData();
    final result = await repo.importWorld(
      person: person,
      link: link,
      data: data,
      importOwnMatches: false,
      rememberSkippedOwnMatches: false,
      selectedOwnMatchKeys: {},
      preserveOwnPlayers: true,
    );
    expect(result.ownMatches, 0);
    expect(await db.query('ManagerFixtures'), isEmpty);
    expect(link.worldSync[season.id]!.ignoredMatchKeys, isEmpty);
    final preview = await repo.previewWorldMatches(
      person: person,
      link: link,
      data: data,
    );
    expect(preview.where((p) => !p.exists && !p.ignored), isNotEmpty);
  });

  test('Ignored old games survive reimport, new results import and explicit selection restores ignored games', () async {
    final first = worldData();
    final oldKey = FcScoreMatch.fromFixture(
      first.fixtures.first,
      first.saveId,
    ).remoteKey;
    final result = await repo.importWorld(
      person: person,
      link: link,
      data: first,
      importOwnMatches: false,
      preserveOwnPlayers: true,
      updateOveralls: false,
    );
    expect(result.ownMatches, 0);
    expect(link.worldSync[season.id]!.ignoredMatchKeys, {oldKey});
    final saved = (await repo.linkFor(person.id))!;
    expect(saved.worldSync[season.id]!.updateOveralls, isFalse);
    final next = worldData(date: '2028-07-15');
    next.fixtures.last['played'] = true;
    next.fixtures.last['home'] = {
      ...fcObject(next.fixtures.last['home']),
      'goals': 0,
    };
    next.fixtures.last['away'] = {
      ...fcObject(next.fixtures.last['away']),
      'goals': 1,
    };
    final previews = await repo.previewWorldMatches(
      person: person,
      link: saved,
      data: next,
    );
    expect(previews.where((p) => p.ignored).single.match.remoteKey, oldKey);
    final updated = await repo.importWorld(
      person: person,
      link: saved,
      data: next,
    );
    expect(updated.ownMatches, 1);
    expect(updated.skippedMatches, 1);
    expect((await db.query('ManagerFixtures')).length, 1);
    final repeated = await repo.importWorld(
      person: person,
      link: saved,
      data: next,
    );
    expect(repeated.ownMatches, 0);
    expect(repeated.preservedMatches, 1);
    final restored = await repo.importWorld(
      person: person,
      link: saved,
      data: next,
      selectedOwnMatchKeys: {oldKey},
    );
    expect(restored.ownMatches, 1);
    expect(saved.worldSync[season.id]!.ignoredMatchKeys, isEmpty);
    expect((await db.query('ManagerFixtures')).length, 2);
  });
  test('Old builds recover ignored games from the saved calendar without writes during review', () async {
    await import(own: false);
    link.worldSync.clear();
    final before = await db.query('FcScoreCareerLink');
    final state = await repo.previousWorldSync(person, link);
    expect(state!.competitionIds, {'1528'});
    expect(state.ignoredMatchKeys, {
      FcScoreMatch.fromFixture(
        worldData().fixtures.first,
        link.saveId,
      ).remoteKey,
    });
    expect(await db.query('FcScoreCareerLink'), before);
    final renamed = FcScoreLink.fromMap({
      ...link.toMap(),
      'saveId': 'renamed-save',
    });
    expect(
      (await repo.previousWorldSync(person, renamed))!.ignoredMatchKeys,
      state.ignoredMatchKeys,
    );
    final otherSeason = link.copy()..seasonId = 'not-imported';
    expect(await repo.previousWorldSync(person, otherSeason), isNull);
  });
  for (final cup in [false, true]) {
    test(
      'Real season statistics replace obsolete league totals and cover ${cup ? 'cups' : 'leagues'}',
      () async {
        final data = worldStatistics(cup: cup);
        await import(data: data);
        final competition = (await repo.careerCompetitions(person.id)).single;
        final stats = await repo.competitionScorers(person, competition);
        expect(stats.complete, isTrue);
        expect(stats.players.map((p) => p['goals']), [14, 11, 2]);
        expect(fcRankStats(stats.statistics, 'assists').first['id'], 30);
        expect(fcRankStats(stats.statistics, 'cleanSheets').single['id'], 30);
        expect(
          fcRankStats(stats.statistics, 'averageRating').first['averageRating'],
          9.0,
        );
        expect(
          (await db.query('TournamentPlayersResult'))
              .map((p) => p['value'])
              .toSet(),
          {2, 11},
        );
        await import(data: data);
        expect((await db.query('TournamentPlayersResult')).length, 2);
        data.competitions.single['playerStats'] = [];
        await import(data: data);
        expect(
          (await repo.competitionScorers(
            person,
            (await repo.careerCompetitions(person.id)).single,
          )).players,
          isEmpty,
        );
        expect(await db.query('TournamentPlayersResult'), isEmpty);
      },
    );
  }
  test(
    'seasonStats roster fallback uses the exact competition, including cups',
    () async {
      final data = worldStatistics(cup: true, endpoint: false);
      for (final t in data.teams) {
        final p = (t['roster'] as List).first as Map;
        (p['seasonStats']['competitions'] as List).add(<String, dynamic>{
          ...p['seasonStats']['competitions'][0],
          'competition': {'id': 999},
          'goals': 200,
        });
      }
      await import(data: data);
      final stats = await repo.competitionScorers(
        person,
        (await repo.careerCompetitions(person.id)).single,
      );
      expect(stats.players.map((p) => p['goals']), [11, 2]);
      expect(stats.statistics.length, 3);
      expect((await db.query('TournamentPlayersResult')).length, 2);
    },
  );
  test('Stats endpoint paginates and download retains every player and roster stats', () async {
    final requests = <http.Request>[];
    final api = worldApi(
      snapshot: worldStatistics(),
      requests: requests,
      pageSize: 1,
    );
    addTearDown(api.close);
    final data = await FcScoreWorldData.load(
      api: api,
      remote: apiCareer(),
      season: season,
      calendar: worldData().fixtures,
      competitionIds: {'1528'},
    );
    expect(fcList(data.competitions.single['playerStats']).length, 4);
    expect(requests.where((r) => r.url.path.endsWith('/stats')).length, 4);
    expect(
      fcList(data.competitions.single['playerStats']).first
          .containsKey('recentMatches'),
      isFalse,
    );
    expect(
      fcObject(fcList(data.teams.first['roster']).first['seasonStats']),
      isNotEmpty,
    );
    expect(await db.query('FcScoreCompetition'), isEmpty);
  });
  test(
    'Malformed season stats roll back both data and ignored-match preferences',
    () async {
      await import(own: false);
      final before = await db.query('FcScoreCareerLink');
      final bad = worldStatistics();
      fcList(bad.competitions.single['playerStats']).first['assists'] = -1;
      (bad.competitions.single['playerStats'] as List).first['assists'] = -1;
      await expectLater(import(data: bad), throwsA(isA<FcScoreException>()));
      expect(await db.query('FcScoreCareerLink'), before);
      expect(await db.query('ManagerFixtures'), isEmpty);
    },
  );

  test(
    'Current real API snapshot imports every selected competition with correct scorers and offline season stats',
    () async {
      final raw = fcObject(
        jsonDecode(
          File(Platform.environment['FC_SCORE_STATS_SNAPSHOT']!)
              .readAsStringSync(),
        ),
      );
      final snapshot = FcScoreWorldData(
        saveId: link.saveId,
        currentDate: fcId(raw['currentDate']),
        competitions: fcList(raw['competitions']),
        fixtures: fcList(raw['fixtures']),
        teams: fcList(raw['teams']),
      );
      final remote = FcScoreRemoteCareer(
        overview: {
          ...apiCareer().overview,
          'currentDate': snapshot.currentDate,
        },
        squad: apiCareer().squad,
        competitions: snapshot.competitions
            .map((c) => fcObject(c['competition']))
            .toList(),
        gameVersion: 'FC26',
      );
      final api = worldApi(snapshot: snapshot);
      addTearDown(api.close);
      final data = await FcScoreWorldData.load(
        api: api,
        remote: remote,
        season: season,
        calendar: snapshot.fixtures,
        competitionIds: snapshot.competitions
            .map((c) => fcId(fcObject(c['competition'])['id']))
            .toSet(),
      );
      for (final c in data.competitions) {
        final ref = fcObject(c['competition']);
        link.competitions[fcId(ref['id'])] = 'new:${fcName(ref['name'])}';
      }
      for (final t in data.teams) {
        final tid = fcId(t['id']);
        link.teams[tid] = tid == link.remoteClubId
            ? link.localClubId
            : 'new:${fcName(t['name'])}';
        if (tid == link.remoteClubId) continue;
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
      final first = await repo.importWorld(
        person: person,
        link: link,
        data: data,
        importOwnMatches: false,
        preserveOwnPlayers: true,
      );
      expect(first.competitions, 7);
      expect(first.players, greaterThan(4000));
      expect(first.ownMatches, 0);
      for (final c in await repo.careerCompetitions(person.id)) {
        final stats = await repo.competitionScorers(person, c);
        final oracle = fcList(
          data.competitions.firstWhere(
            (r) =>
                fcId(fcObject(r['competition'])['id']) == fcId(c['remoteId']),
          )['playerStats'],
        );
        expect(stats.complete, isTrue);
        expect(stats.statistics.length, oracle.length);
        expect(
          stats.players
              .map((p) => '${p['remoteTeamId']}:${p['id']}:${p['goals']}')
              .toSet(),
          oracle
              .where((p) => (fcInt(p['goals']) ?? 0) > 0)
              .map(
                (p) =>
                    '${fcObject(p['team'])['id']}:${fcObject(p['player'])['id']}:${p['goals']}',
              )
              .toSet(),
        );
        if (fcId(c['remoteId']) == '1528') {
          expect(stats.statistics.length, 541);
          expect(stats.players.first['goals'], 15);
        }
      }
      expect(
        fcObject(
          (await repo.careerRoster(
            person.id,
            season.id,
            '598',
          )).first['seasonStats'],
        ),
        isNotEmpty,
      );
      final repeat = await repo.importWorld(
        person: person,
        link: link,
        data: data,
        preserveOwnPlayers: true,
      );
      expect(repeat.ownMatches, 0);
      expect(await db.query('ManagerFixtures'), isEmpty);
      expect(
        (await repo.linkFor(person.id))!
            .worldSync[season.id]!
            .ignoredMatchKeys
            .length,
        first.skippedMatches,
      );
    },
    skip: Platform.environment['FC_SCORE_STATS_SNAPSHOT'] == null
        ? 'Set FC_SCORE_STATS_SNAPSHOT for the current real API dataset.'
        : false,
  );

  test('Nicolas in the current squad is reserved for his own club, not another namesake', () {
    final data = worldData();
    (data.teams.first['roster'] as List).first['name'] = 'Nicolas';
    (data.teams[1]['roster'] as List).first['name'] = 'Nicolas';
    final local = <Map<String, Object?>>[
      {'id': 'my-nicolas', 'name': 'Nicolas'},
      {'id': 'old-nicolas', 'name': 'Nicolas'},
    ];
    final mapping = fcSuggestWorldPlayers(
      data,
      local,
      mapping: {'10': 'new', '20': 'new'},
      ownClubId: '598',
      ownPlayerIds: {'my-nicolas'},
    );
    expect(mapping['10'], 'my-nicolas');
    expect(mapping['20'], 'new');
    final repaired = fcSuggestWorldPlayers(
      data,
      local,
      mapping: {'10': 'my-nicolas', '20': 'my-nicolas'},
      ownClubId: '598',
      ownPlayerIds: {'my-nicolas'},
    );
    expect(repaired['10'], 'my-nicolas');
    expect(repaired['20'], 'new');
    final exact = fcSuggestWorldPlayers(
      data,
      [
        {'id': 'my-nicolas', 'name': 'Nicolas', 'realPlayerId': '10'},
        {'id': 'their-nicolas', 'name': 'Nicolas', 'realPlayerId': '20'},
      ],
      mapping: {'10': 'new', '20': 'new'},
      ownClubId: '598',
    );
    expect(exact['10'], 'my-nicolas');
    expect(exact['20'], 'their-nicolas');
    final occupiedIdentity = fcSuggestWorldPlayers(
      data,
      [
        {'id': 'my-nicolas', 'name': 'Nicolas', 'realPlayerId': '10'},
      ],
      mapping: {'10': 'new', '20': 'my-nicolas'},
      ownClubId: '598',
    );
    expect(occupiedIdentity['10'], 'my-nicolas');
    expect(
      FcWorldPlayerReview(data, [
        {'id': 'my-nicolas', 'name': 'Nicolas', 'realPlayerId': '10'},
      ]).issues(occupiedIdentity).single.kind,
      FcWorldPlayerIssueKind.duplicate,
    );
  });

  test('Preserving own players imports other clubs without new own players or overall changes', () async {
    await import();
    final ownId = link.players['10']!;
    final beforePlayer = await db.query(
      'CustomCreatedPlayer',
      where: 'id = ?',
      whereArgs: [ownId],
    );
    final beforeSquad = await db.query('TeamPlayer');
    final beforeOverall = await db.query(
      'Overall',
      where: 'customPlayerId = ?',
      whereArgs: [ownId],
    );
    final data = worldData();
    (data.teams.first['roster'] as List).first['overall'] = 99;
    (data.teams.first['roster'] as List).add({
      ...apiPlayer(98163, ''),
      'overall': null,
    });
    (data.teams[1]['roster'] as List).first['overall'] = 90;
    final review = await repo.reviewWorldPlayers(
      person: person,
      link: link,
      data: data,
      preserveOwnPlayers: true,
    );
    expect(review.issues(link.players), isEmpty);
    expect(review.isProtected('98163'), isTrue);
    await repo.importWorld(
      person: person,
      link: link,
      data: data,
      preserveOwnPlayers: true,
      bringOwnSquad: true,
      updateOveralls: true,
    );
    expect(
      await db.query(
        'CustomCreatedPlayer',
        where: 'id = ?',
        whereArgs: [ownId],
      ),
      beforePlayer,
    );
    expect(await db.query('TeamPlayer'), beforeSquad);
    expect(
      await db.query(
        'Overall',
        where: 'customPlayerId = ?',
        whereArgs: [ownId],
      ),
      beforeOverall,
    );
    expect((await db.query('CustomCreatedPlayer')).length, 3);
    final ownSnapshot = await repo.careerRoster(person.id, season.id, '598');
    expect(ownSnapshot.length, 2);
    expect(ownSnapshot.last['localPlayerId'], '');
    expect(
      (await repo.careerRoster(person.id, season.id, '200')).single['overall'],
      90,
    );
    (data.teams.last['roster'] as List).add(apiPlayer(10, 'Pedro Silva'));
    await repo.importWorld(
      person: person,
      link: link,
      data: data,
      preserveOwnPlayers: true,
    );
    expect(
      await db.query(
        'Overall',
        where: 'customPlayerId = ?',
        whereArgs: [ownId],
      ),
      beforeOverall,
    );
    await expectLater(
      repo.importWorld(
        person: person,
        link: link,
        data: data,
        preserveOwnPlayers: false,
      ),
      throwsA(isA<FcWorldPlayerMappingException>()),
    );
  });

  test(
    'Downloads all fixture pages and only participant rosters before any write',
    () async {
      final requests = <http.Request>[];
      final api = worldApi(requests: requests, pageSize: 1);
      final calendar = await FcScoreWorldData.fixturesFor(api, 'save-A');
      expect(calendar.length, 3);
      final data = await FcScoreWorldData.load(
        api: api,
        remote: apiCareer(),
        season: season,
        calendar: calendar,
        competitionIds: {'1528'},
      );
      expect(data.teams.length, 3);
      expect(data.playerCount, 3);
      final calls = requests
          .where((r) => r.url.path.endsWith('/fixtures'))
          .toList();
      expect(calls.map((r) => r.url.queryParameters['offset']), [
        '0',
        '1',
        '2',
      ]);
      expect(
        calls.every((r) => r.url.queryParameters['allTeams'] == 'true'),
        isTrue,
      );
      expect(await repo.careerCompetitions(person.id), isEmpty);
      api.close();
    },
  );
  test('Stops incomplete or repeated pages, excludes unresolved/out of season fixtures visibly', () async {
    final api = FcScoreApi(
      Uri.parse('http://localhost/api'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'total': 5,
            'items': [apiFixture()],
          }),
          200,
        ),
      ),
    );
    await expectLater(
      FcScoreWorldData.fixturesFor(api, 'save-A'),
      throwsA(isA<FcScoreException>()),
    );
    api.close();
    final working = worldApi();
    final data = await FcScoreWorldData.load(
      api: working,
      remote: apiCareer(),
      season: season,
      calendar: [
        apiFixture(),
        {...apiFixture(), 'id': 90, 'date': '2027-01-01'},
        {...apiFixture(), 'id': 91, 'date': null},
      ],
      competitionIds: {'1528'},
    );
    expect(data.fixtures.length, 1);
    expect(data.excludedFixtures, 2);
    working.close();
  });
  test('Rejects save advancing during download and wrong season', () async {
    final api = worldApi(changeSave: true);
    await expectLater(
      FcScoreWorldData.load(
        api: api,
        remote: apiCareer(),
        season: season,
        calendar: worldData().fixtures,
        competitionIds: {'1528'},
      ),
      throwsA(isA<FcScoreException>()),
    );
    await expectLater(
      FcScoreWorldData.load(
        api: api,
        remote: apiCareer(),
        season: reviewSeason(),
        calendar: [],
        competitionIds: {'1528'},
      ),
      throwsA(isA<FcScoreException>()),
    );
    api.close();
  });
  test('Imports all teams, schedules, native tables and league scorers into career', () async {
    final result = await import();
    expect(result.fixtures, 3);
    expect(result.ownMatches, 1);
    expect(result.players, 3);
    expect((await db.query('ManagerFixtures')).length, 1);
    expect(
      (await db.query('FcScoreWorldFixture'))
          .where((r) => r['played'] == 0)
          .length,
      1,
    );
    expect((await db.query('TournamentResultTableItem')).length, 2);
    expect((await db.query('TournamentPlayersResult')).length, 3);
    expect((await db.query('TeamPlayer')).length, 1);
    expect((await db.query('Overall')).length, 3);
    expect(link.leagues['80'], link.localLeagueId);
    expect((await db.query('TournamentResult')).single['isWinner'], isNull);
    expect(await db.query('Trophies'), isEmpty);
    final saved = (await repo.careerCompetitions(person.id)).single;
    final scorers = await repo.competitionScorers(person, saved);
    expect(scorers.players.first['name'], 'João Souza');
    expect(scorers.players.first['goals'], 18);
    expect(
      (await repo.careerRoster(
        person.id,
        season.id,
        '200',
      )).single['leagueGoals'],
      18,
    );
    expect((await repo.linkFor(person.id))!.players.length, 3);
    final review = await SeasonClosureService(
      database: () async => db,
      labels: const SeasonReviewLabels(),
    ).load(person, season);
    expect(review.tables.single.rows.length, 2);
    expect(review.tables.single.closedAt, isNull);
  });
  test('Re-import refreshes standings and rosters without duplicates and preserves own reports', () async {
    await import();
    final detailed = await repo.importMatch(
      person: person,
      link: link,
      match: FcScoreMatch.fromReport(apiReport()),
    );
    expect(detailed.state, FcImportState.canComplete);
    final data = worldData();
    (data.teams[1]['roster'] as List).first['leagueGoals'] = 21;
    final result = await import(data: data);
    expect(result.ownMatches, 0);
    expect(result.preservedMatches, 1);
    expect((await db.query('ManagerFixtures')).length, 1);
    expect((await db.query('FcScoreWorldFixture')).length, 3);
    expect((await db.query('ManagerFixturePlayerPerformances')).length, 2);
    expect(
      (await repo.competitionScorers(
        person,
        (await repo.careerCompetitions(person.id)).single,
      )).players.first['goals'],
      21,
    );
    expect((await db.query('FcScoreImport')).single['reportId'], 'batch-A');
  });
  test('Optional own match/squad import keeps world results and no fabricated performances', () async {
    await repo.importWorld(
      person: person,
      link: link,
      data: worldData(),
      importOwnMatches: false,
      bringOwnSquad: false,
      updateOveralls: false,
    );
    expect(await db.query('ManagerFixtures'), isEmpty);
    expect(await db.query('TeamPlayer'), isEmpty);
    expect(await db.query('ManagerFixturePlayerPerformances'), isEmpty);
    expect(await db.query('Overall'), isEmpty);
    expect((await db.query('FcScoreWorldFixture')).length, 3);
  });
  test(
    'Per-match selection skips unchecked games and allows importing them later',
    () async {
      final data = worldData();
      data.fixtures.add({...apiFixture(), 'id': 46, 'date': '2028-06-26'});
      final preview = await repo.previewWorldMatches(
        person: person,
        link: link,
        data: data,
      );
      expect(preview.length, 2);
      expect(preview.every((item) => !item.exists), isTrue);
      expect(await db.query('ManagerFixtures'), isEmpty);
      final chosen = preview.first.match.remoteKey;
      final result = await repo.importWorld(
        person: person,
        link: link,
        data: data,
        selectedOwnMatchKeys: {chosen},
      );
      expect(result.ownMatches, 1);
      expect(result.skippedMatches, 1);
      expect((await db.query('FcScoreImport')).single['remoteKey'], chosen);
      expect(
        (await db.query('ManagerFixtures')).single['date'],
        startsWith('2028-06-26'),
      );
      expect((await db.query('FcScoreWorldFixture')).length, 4);
      final updated = await repo.previewWorldMatches(
        person: person,
        link: link,
        data: data,
      );
      expect(updated.where((item) => item.exists).length, 1);
      final remaining = await repo.importWorld(
        person: person,
        link: link,
        data: data,
        selectedOwnMatchKeys: updated
            .where((item) => !item.exists)
            .map((item) => item.match.remoteKey)
            .toSet(),
      );
      expect(remaining.ownMatches, 1);
      expect(remaining.preservedMatches, 1);
      expect((await db.query('ManagerFixtures')).length, 2);
    },
  );
  test('Empty match selection imports competition data without creating a match ledger', () async {
    final result = await repo.importWorld(
      person: person,
      link: link,
      data: worldData(),
      selectedOwnMatchKeys: {},
    );
    expect(result.ownMatches, 0);
    expect(result.skippedMatches, 1);
    expect(await db.query('ManagerFixtures'), isEmpty);
    expect(await db.query('FcScoreImport'), isEmpty);
    expect((await db.query('FcScoreWorldFixture')).length, 3);
    expect((await db.query('TournamentResultTableItem')).length, 2);
  });
  test('Invalid selection cannot import an upcoming or another club game, with no writes', () async {
    for (final key in [
      'unknown',
      FcScoreMatch.fromFixture(worldData().fixtures[1], 'save-A').remoteKey,
      FcScoreMatch.fromFixture(worldData().fixtures[2], 'save-A').remoteKey,
    ]) {
      await expectLater(
        repo.importWorld(
          person: person,
          link: link,
          data: worldData(),
          selectedOwnMatchKeys: {key},
        ),
        throwsA(isA<FcScoreException>()),
      );
    }
    expect(await db.query('FcScoreCompetition'), isEmpty);
    expect(await db.query('ManagerFixtures'), isEmpty);
    expect(await db.query('FcScoreCareerLink'), isEmpty);
  });
  test('Review identifies manual games, score differences and changes to team mapping', () async {
    link.teams['200'] = 'new:Rival FC';
    await import();
    await db.delete('FcScoreImport');
    await db.update('ManagerFixtures', {
      'notes': 'Configurado por mim',
      'playerTeamScore': 4,
    });
    final preview = (await repo.previewWorldMatches(
      person: person,
      link: link,
      data: worldData(),
    )).single;
    expect(preview.exists, isTrue);
    expect(preview.manual, isTrue);
    expect(preview.scoreDiffers, isTrue);
    expect(preview.localHomeGoals, 1);
    expect(preview.localAwayGoals, 4);
    final changed = link.copy()..teams['200'] = 'another-club';
    expect(
      (await repo.previewWorldMatches(
        person: person,
        link: changed,
        data: worldData(),
      )).single.exists,
      isFalse,
    );
    final names = link.copy()..teams['200'] = 'new:Rival FC';
    expect(
      (await repo.previewWorldMatches(
        person: person,
        link: names,
        data: worldData(),
      )).single.exists,
      isTrue,
    );
    final result = await repo.importWorld(
      person: person,
      link: link,
      data: worldData(),
      selectedOwnMatchKeys: {preview.match.remoteKey},
    );
    expect(result.preservedMatches, 1);
    expect(result.ownMatches, 0);
    expect(
      (await db.query('ManagerFixtures')).single['notes'],
      'Configurado por mim',
    );
    expect((await db.query('ManagerFixtures')).single['playerTeamScore'], 4);
  });
  test('Save rechecks matches registered after the preview and never overwrites them', () async {
    final preview = (await repo.previewWorldMatches(
      person: person,
      link: link,
      data: worldData(),
    )).single;
    expect(preview.exists, isFalse);
    await repo.importMatch(
      person: person,
      link: link,
      match: FcScoreMatch.fromReport(apiReport()),
    );
    await db.update('ManagerFixtures', {'notes': 'Já terminei a configuração'});
    final result = await repo.importWorld(
      person: person,
      link: link,
      data: worldData(),
      selectedOwnMatchKeys: {preview.match.remoteKey},
    );
    expect(result.ownMatches, 0);
    expect(result.preservedMatches, 1);
    expect(
      (await db.query('ManagerFixtures')).single['notes'],
      'Já terminei a configuração',
    );
    expect((await db.query('ManagerFixturePlayerPerformances')).length, 2);
    expect((await db.query('FcScoreImport')).single['reportId'], 'batch-A');
  });
  test('Duplicate team/player mapping rolls back snapshots, catalog, fixtures and links', () async {
    link.teams['300'] = link.teams['200']!;
    await expectLater(import(), throwsA(isA<FcScoreException>()));
    for (final table in [
      'FcScoreCompetition',
      'CustomCreatedPlayer',
      'FcScoreWorldTeam',
      'FcScoreWorldFixture',
      'ManagerFixtures',
      'FcScoreCareerLink',
    ]) {
      expect(await db.query(table), isEmpty, reason: table);
    }
    link.teams['300'] = 'new:Terceiro FC';
    await import();
    link.players['30'] = link.players['20']!;
    await expectLater(import(), throwsA(isA<FcScoreException>()));
    expect((await db.query('FcScoreWorldPlayer')).length, 3);
  });
  test('Player review identifies names and teams, resolves all duplicate groups and preserves history', () async {
    await import();
    final original20 = link.players['20']!;
    final original30 = link.players['30']!;
    final original10 = link.players['10']!;
    final before = await db.query(
      'CustomCreatedPlayer',
      where: 'id = ?',
      whereArgs: [original20],
    );
    await db.insert('Overall', {
      'id': 'historic-20',
      'personId': person.id,
      'customPlayerId': original20,
      'date': '2027-01-01',
      'createdAt': '2027-01-01',
      'overall': 72,
    });
    final data = worldData();
    (data.teams.first['roster'] as List).add(apiPlayer(11, 'Marcos Antônio'));
    link.players['30'] = original20;
    link.players['11'] = original10;
    final review = await repo.reviewWorldPlayers(
      person: person,
      link: link,
      data: data,
    );
    final issues = review.issues(link.players);
    expect(issues.length, 2);
    expect(
      issues.every((i) => i.kind == FcWorldPlayerIssueKind.duplicate),
      isTrue,
    );
    expect(issues.last.players.map((p) => p.name), [
      'João Souza',
      'Lucas Paiva',
    ]);
    expect(issues.last.players.last.teams, {'Terceiro FC'});
    expect(review.occupiedByOthers('30', link.players), contains(original20));
    await expectLater(
      repo.importWorld(person: person, link: link, data: data),
      throwsA(isA<FcWorldPlayerMappingException>()),
    );
    expect((await db.query('FcScoreWorldPlayer')).length, 3);
    link.players['30'] = original30;
    link.players['11'] = 'new';
    expect(review.issues(link.players), isEmpty);
    await import(data: data);
    expect((await repo.linkFor(person.id))!.players['30'], original30);
    expect(link.players['11'], isNot(original10));
    expect(
      await db.query(
        'CustomCreatedPlayer',
        where: 'id = ?',
        whereArgs: [original20],
      ),
      before,
    );
    expect(
      (await db.query(
        'Overall',
        where: 'id = ?',
        whereArgs: ['historic-20'],
      )).single['overall'],
      72,
    );
  });
  test('Same source player in two squads is one identity; inactive saved mappings are ignored', () async {
    final data = worldData();
    (data.teams.last['roster'] as List).add(apiPlayer(10, 'Pedro Silva'));
    await import(data: data);
    link.players['no-longer-in-save'] = link.players['10']!;
    final review = await repo.reviewWorldPlayers(
      person: person,
      link: link,
      data: data,
    );
    expect(review.players['10']!.teams, {'São Paulo', 'Terceiro FC'});
    expect(review.issues(link.players), isEmpty);
    final result = await import(data: data);
    expect(result.players, 3);
    expect((await db.query('CustomCreatedPlayer')).length, 3);
    expect((await db.query('FcScoreWorldPlayer')).length, 4);
  });
  test('Missing career links and incomplete API profiles are actionable before any writes', () async {
    final data = worldData();
    (data.teams.first['roster'] as List).first['overall'] = null;
    (data.teams.last['roster'] as List).first['name'] = '';
    link.players['20'] = 'deleted-or-other-career';
    final review = await repo.reviewWorldPlayers(
      person: person,
      link: link,
      data: data,
    );
    final issues = review.issues(link.players);
    expect(issues.length, 3);
    expect(
      issues.map((i) => i.kind),
      contains(FcWorldPlayerIssueKind.missingLink),
    );
    expect(review.players['10']!.canCreate, isFalse);
    expect(review.players['30']!.canCreate, isFalse);
    await expectLater(
      import(data: data),
      throwsA(isA<FcWorldPlayerMappingException>()),
    );
    for (final table in [
      'CustomCreatedPlayer',
      'FcScoreWorldPlayer',
      'FcScoreWorldTeam',
      'FcScoreCareerLink',
      'ManagerFixtures',
    ]) {
      expect(await db.query(table), isEmpty, reason: table);
    }
  });
  test('Created and generated incomplete players import atomically with stable identity and original league stats', () async {
    final data = worldData();
    for (final team in data.teams) {
      final player = (team['roster'] as List).first as FcJson;
      player['name'] = '';
      player['overall'] = null;
      final profile = fcGeneratePlayerProfile(player);
      if (fcId(player['id']) == '20') {
        profile['name'] = 'João Criado Aqui';
        profile['overall'] = 74;
      }
      link.players[fcId(player['id'])] = fcCreatePlayerChoice(
        player,
        profile,
        generated: true,
      );
    }
    final review = await repo.reviewWorldPlayers(
      person: person,
      link: link,
      data: data,
    );
    expect(review.issues(link.players), isEmpty);
    expect(await db.query('CustomCreatedPlayer'), isEmpty);
    await import(data: data);
    final originalIds = Map<String, String>.of(link.players);
    final created20 = (await db.query(
      'CustomCreatedPlayer',
      where: 'id = ?',
      whereArgs: [link.players['20']],
    )).single;
    expect(created20['name'], 'João Criado Aqui');
    expect(created20['overall'], 74);
    expect(created20['realPlayerId'], '20');
    expect(
      (await repo.careerRoster(person.id, season.id, '200')).single['overall'],
      74,
    );
    final raw = fcObject(
      jsonDecode(
        (await db.query(
              'FcScoreWorldPlayer',
              where: 'remotePlayerId = ?',
              whereArgs: ['20'],
            )).single['rawJson']
            as String,
      ),
    );
    expect(raw['leagueGoals'], 18);
    expect(raw['overall'], isNull);
    await import(data: data);
    expect(link.players, originalIds);
    expect((await db.query('CustomCreatedPlayer')).length, 3);
    expect((await db.query('ManagerFixtures')).length, 1);
    final broken = worldData();
    link.players['30'] = fcCreatePlayerChoice(
      (broken.teams.last['roster'] as List).first,
      fcGeneratePlayerProfile((broken.teams.last['roster'] as List).first),
    );
    (broken.teams.last['roster'] as List).first['leagueGoals'] = -1;
    await expectLater(import(data: broken), throwsA(isA<FcScoreException>()));
    expect((await db.query('CustomCreatedPlayer')).length, 3);
    expect((await repo.linkFor(person.id))!.players, originalIds);
  });
  test('Final transaction detects a mapped player deleted after review and rolls back', () async {
    await import();
    final review = await repo.reviewWorldPlayers(
      person: person,
      link: link,
      data: worldData(),
    );
    expect(review.issues(link.players), isEmpty);
    await db.delete(
      'CustomCreatedPlayer',
      where: 'id = ?',
      whereArgs: [link.players['30']],
    );
    await expectLater(
      import(),
      throwsA(
        isA<FcWorldPlayerMappingException>().having(
          (e) => e.review.issues(link.players).single.players.single.name,
          'affected player',
          'Lucas Paiva',
        ),
      ),
    );
    expect((await db.query('FcScoreWorldPlayer')).length, 3);
    expect((await repo.linkFor(person.id))!.players, link.players);
  });
  test('Rejects older save, closed season, negative stats and date/score conflicts without partial updates', () async {
    await import();
    await expectLater(
      import(data: worldData(date: '2028-06-29')),
      throwsA(isA<FcScoreException>()),
    );
    final bad = worldData();
    (bad.teams.first['roster'] as List).first['leagueGoals'] = -1;
    await expectLater(import(data: bad), throwsA(isA<FcScoreException>()));
    final broken = worldData();
    broken.fixtures.first['date'] = '2027-01-01';
    await expectLater(import(data: broken), throwsA(isA<FcScoreException>()));
    await db.update(
      'Seasons',
      {'closedAt': '2029-01-01'},
      where: 'id = ?',
      whereArgs: [season.id],
    );
    await expectLater(import(), throwsA(isA<FcScoreException>()));
    expect(
      (await db.query('FcScoreCompetition')).single['currentDate'],
      '2028-06-30',
    );
  });
  test(
    'Manual names/photos, starting XI, fixtures and final tables remain intact',
    () async {
      await import();
      await db.update(
        'CustomCreatedPlayer',
        {'name': 'Meu nome', 'customAvatarFilePath': 'custom-photo'},
        where: 'id = ?',
        whereArgs: [link.players['10']],
      );
      await db.update('TeamPlayer', {'isBench': 0});
      await db.update('ManagerFixtures', {'notes': 'Minha nota'});
      final table = (await db.query('TournamentResultTable')).single;
      await db.update(
        'TournamentResultTable',
        {'closedAt': '2028-06-30', 'name': 'Tabela conferida'},
        where: 'id = ?',
        whereArgs: [table['id']],
      );
      await import();
      expect(
        (await repo.careerRoster(
          person.id,
          season.id,
          '598',
        )).single['localName'],
        'Meu nome',
      );
      expect(
        (await repo.careerRoster(
          person.id,
          season.id,
          '598',
        )).single['customAvatarFilePath'],
        'custom-photo',
      );
      expect((await db.query('TeamPlayer')).single['isBench'], 0);
      await db.insert('Overall', {
        'id': 'future-overall',
        'personId': person.id,
        'customPlayerId': link.players['10'],
        'date': '2029-01-01',
        'overall': 88,
      });
      expect(
        (await repo.careerRoster(
          person.id,
          season.id,
          '598',
        )).single['overall'],
        88,
      );
      expect((await db.query('ManagerFixtures')).single['notes'], 'Minha nota');
      expect(
        (await db.query('TournamentResultTable')).single['name'],
        'Tabela conferida',
      );
    },
  );
  test('Cups never borrow league goals; detailed reports provide explicitly partial scoring', () async {
    await import(data: worldData(cup: true));
    final comp = (await repo.careerCompetitions(person.id)).single;
    final empty = await repo.competitionScorers(person, comp);
    expect(empty.players, isEmpty);
    expect(empty.notice, contains('não fornece'));
    expect(await db.query('TournamentPlayersResult'), isEmpty);
    await repo.importMatch(
      person: person,
      link: link,
      match: FcScoreMatch.fromReport(apiReport()),
    );
    final partial = await repo.competitionScorers(person, comp);
    expect(partial.notice, contains('parcial'));
    expect(partial.players.length, 3);
    expect(partial.players.every((p) => p['goals'] == 1), isTrue);
  });
  test(
    'Data is career/season scoped and backup restore preserves offline world',
    () async {
      await import();
      expect(await repo.careerCompetitions('other-career'), isEmpty);
      expect(
        await repo.competitionFixtures(person.id, 'other-season', '1528'),
        isEmpty,
      );
      final backup = BackupService(database: () async => db, imageFolders: []);
      final file = await backup.generateBackup(includeImages: false);
      await db.delete('FcScoreCompetition');
      await db.delete('FcScoreWorldPlayer');
      await backup.restoreBackup(file);
      expect((await repo.careerCompetitions(person.id)).length, 1);
      expect(
        (await repo.careerRoster(
          person.id,
          season.id,
          '200',
        )).single['leagueGoals'],
        18,
      );
      expect((await db.query('FcScoreWorldFixture')).length, 3);
    },
  );
  test(
    'World schema migration is idempotent and old link JSON remains readable',
    () async {
      await ensureFcScoreSchema(db);
      await ensureFcScoreSchema(db);
      expect(
        (await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name = 'FcScoreWorldFixture'",
        )).length,
        1,
      );
      final map = apiLink().toMap()..remove('leagues');
      expect(FcScoreLink.fromMap(map).leagues, isEmpty);
    },
  );
}
