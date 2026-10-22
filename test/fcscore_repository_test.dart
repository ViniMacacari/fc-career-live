import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/FcScore/FcScoreModels.dart';
import 'package:mcmanager/FcScore/FcScoreRepository.dart';
import 'package:mcmanager/FcScore/FcScorePlayerCreation.dart';
import 'package:mcmanager/FcScore/FcScoreSchema.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileData.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerSummary/PlayerSummaryData.dart';
import 'package:mcmanager/models/FixtureFormation.dart';
import 'package:mcmanager/models/ManagerFixture.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/models/OpponentLineup.dart';
import 'package:mcmanager/models/Person.dart';
import 'package:mcmanager/models/Season.dart';
import 'package:mcmanager/utils/BackupService.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/managerPlayerMinutesUtils.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fcscore_fixture.dart';
import 'season_review_fixture.dart';
import 'backup_storage_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late SqlService sql;
  late FcScoreRepository repo;
  late Person person;
  late Season season;
  late FcScoreLink link;
  setUpAll(() {
    mockBackupStorage();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory('build/fcscore-test-docs').absolute.path,
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
    await db.setVersion(33);
    sql = SqlService.withDatabase(db);
    repo = FcScoreRepository(sql: sql);
    person = reviewPerson();
    season = reviewSeason(id: 's2028', year: 2028);
    link = apiLink();
    await db.insert('Persons', person.toMap());
    await db.insert('Seasons', season.toMap());
  });
  tearDown(() async => db.close());
  test('Opponent name falls back to its imported profile when the custom record is blank', () async {
    await db.insert('CustomCreatedPlayer', {
      'id': 'blank-custom',
      'personId': person.id,
      'name': ' ',
      'positionId': '25',
      'overall': 70,
      'potential': 80,
      'foot': 'Right',
      'realFace': 0,
      'fromRealPlayer': 0,
    });
    await db.insert('FcScoreWorldTeam', {
      'personId': person.id,
      'seasonId': season.id,
      'remoteId': '200',
      'teamId': 'mirassol',
      'leagueId': '1014',
      'rawJson': '{}',
    });
    await db.insert('FcScoreWorldPlayer', {
      'personId': person.id,
      'seasonId': season.id,
      'remoteTeamId': '200',
      'remotePlayerId': '20',
      'playerId': 'blank-custom',
      'rawJson': jsonEncode({
        'id': 20,
        'profile': {'name': 'João do Mirassol'},
      }),
    });
    final candidates = await repo.opponentPlayers(
      person: person,
      teamId: 'mirassol',
      leagueId: '1014',
      seasonId: season.id,
    );
    expect(candidates.single['name'], 'João do Mirassol');
    expect(candidates.single['id'], 'blank-custom');
  });
  test('Opponent candidates skip the blank legacy formation template without inventing identities', () async {
    final lineup = OpponentLineup.empty(formation: '4-4-2')
        .addReserve('Jogador personalizado');
    await db.insert('ManagerFixtures', {
      ...reviewFixture(10, season: season.id),
      'date': '2028-01-01',
      'oppositeTeamId': 'mirassol',
      'opponentLineup': lineup.encode(),
    });
    final candidates = await repo.opponentPlayers(
      person: person,
      teamId: 'mirassol',
      leagueId: '1014',
      seasonId: season.id,
      beforeDate: DateTime(2028, 2),
    );
    expect(candidates, hasLength(1));
    expect(candidates.single['name'], 'Jogador personalizado');
    expect(
      OpponentLineup.decode(
        (await db.query('ManagerFixtures')).single['opponentLineup'],
      )!.squad.players,
      hasLength(12),
    );
  });
  test('Incomplete API profiles use the registered opponent XI, infer 442 and repair old snapshots without writing', () async {
    await ensureFcScoreSchema(db);
    final raw = apiReport();
    const roles = [
      'GK',
      'LB',
      'CB',
      'CB',
      'RB',
      'LM',
      'CM',
      'CM',
      'RM',
      'ST',
      'ST',
    ];
    const positionIds = [
      '0',
      '7',
      '5',
      '5',
      '3',
      '16',
      '14',
      '14',
      '12',
      '25',
      '25',
    ];
    await db.insert('FcScoreWorldTeam', {
      'personId': person.id,
      'seasonId': season.id,
      'remoteId': '200',
      'teamId': link.teams['200'],
      'leagueId': 'different-league',
      'rawJson': '{}',
    });
    final remote = <FcJson>[];
    for (var j = 0; j < 11; j++) {
      final rid = 800000 + j, id = 'known-opponent-$j';
      await db.insert('CustomCreatedPlayer', {
        'id': id,
        'personId': person.id,
        'name': 'Rival $j',
        'overall': 75,
        'potential': 85,
        'realFace': 0,
        'fromRealPlayer': 0,
        'foot': 'Right',
        'positionId': positionIds[j],
        'realPlayerId': '$rid',
        'customAvatarFilePath': 'faces/$j.png',
      });
      await db.insert('FcScoreWorldPlayer', {
        'personId': person.id,
        'seasonId': season.id,
        'remoteTeamId': '200',
        'remotePlayerId': '$rid',
        'playerId': id,
        'rawJson': jsonEncode({
          'id': rid,
          'name': {'displayName': 'Rival $j'},
          'lineupPosition': roles[j],
        }),
      });
      remote.add({
        ...apiPerformance(rid, '', goals: 0),
        'profile': null,
        'lineupSlot': j,
      });
    }
    (raw['home'] as Map)['players'] = remote;
    final first = await repo.importMatch(
      person: person,
      link: link,
      match: FcScoreMatch.fromReport(raw),
    );
    final row = (await db.query('ManagerFixtures')).single;
    final lineup = OpponentLineup.decode(row['opponentLineup'])!;
    expect(lineup.squad.formation, '4-4-2');
    expect(lineup.squad.starters, hasLength(11));
    expect(lineup.squad.starters.keys.toSet(), {
      for (var j = 0; j < 11; j++) 'known-opponent-$j',
    });
    expect(
      lineup.squad.players['known-opponent-2']!['customAvatarFilePath'],
      'faces/2.png',
    );
    expect(lineup.names.values, everyElement(isNot(startsWith('Jogador '))));
    final template = OpponentLineup.empty().squad;
    final broken = OpponentLineup(
      squad: template.copy(
        players: {...template.players, ...lineup.squad.players},
        bench: lineup.squad.players.keys.toList(),
        layoutSource: 'api',
      ),
      performances: lineup.performances,
    );
    await db.update(
      'ManagerFixtures',
      {'opponentLineup': broken.encode()},
      where: 'id = ?',
      whereArgs: [first.fixtureId],
    );
    final stored = (await db.query('ManagerFixtures')).single;
    final repaired = (await repo.fixturePitchLineups(person, stored)).opponent!;
    expect(repaired.squad.formation, '4-4-2');
    expect(
      repaired.squad.starters.keys.toSet(),
      lineup.squad.starters.keys.toSet(),
    );
    expect(
      repaired.squad.starters.keys.every(
        (id) => repaired.names[id]!.startsWith('Rival '),
      ),
      isTrue,
    );
    expect(await db.query('ManagerFixtures'), [stored]);
    final aliases = <String, Map<String, Object?>>{};
    final slots = <String, ({int x, int y})>{};
    final shape = [3, 3, 4, 1];
    final order = [
      for (var y = 3; y >= 0; y--)
        for (var x = 0; x < shape[y]; x++) (x: x, y: y),
    ];
    for (var j = 0; j < 11; j++) {
      final rid = 800000 + j, id = 'fc-opponent:$rid';
      aliases[id] = {
        'id': id,
        'name': 'Jogador $rid',
        'realPlayerId': '$rid',
        'positionId': j == 0 ? '0' : '25',
      };
      slots[id] = order[j];
    }
    final legacy = OpponentLineup(
      squad: FixtureFormation(
        formation: '4-3-3',
        players: aliases,
        starters: slots,
        bench: [],
      ),
      performances: [
        for (var j = 0; j < 11; j++)
          ManagerFixturePlayerPerformance(
            personId: person.id,
            fixtureId: first.fixtureId,
            playerInstanceId: 'fc-opponent:${800000 + j}',
            recordedStarted: true,
          ),
      ],
    );
    await db.update(
      'ManagerFixtures',
      {'opponentLineup': legacy.encode()},
      where: 'id = ?',
      whereArgs: [first.fixtureId],
    );
    final aliased = (await repo.fixturePitchLineups(
      person,
      (await db.query('ManagerFixtures')).single,
    )).opponent!;
    expect(aliased.squad.formation, '4-4-2');
    expect(aliased.squad.starters, hasLength(11));
    expect(aliased.squad.starters.keys.toSet(), aliases.keys.toSet());
    expect(
      aliased.squad.starters.keys.map((id) => aliased.names[id]),
      everyElement(startsWith('Rival ')),
    );
  });

  test('Detailed report stores all player stats and opponent substitutions without template players', () async {
    final raw = apiReport();
    final ours = raw['away'] as Map;
    (ours['players'] as List).first['stats'] = <String, dynamic>{
      ...((ours['players'] as List).first['stats'] as Map),
      'npkExpectedGoals': 1.2345,
      'expectedAssists': .21,
      'interceptions': 3,
      'futureCounter': 17,
    };
    final opposite = raw['home'] as Map;
    opposite['players'] = [
      apiPerformance(20, 'Goleiro', minutes: 93, goals: 0)..['lineupSlot'] = 0,
      apiPerformance(21, 'Saiu', minutes: 76, goals: 0),
      apiPerformance(22, 'Entrou', minutes: 17, started: false, goals: 0),
    ];
    final result = await repo.importMatch(
      person: person,
      link: link,
      match: FcScoreMatch.fromReport(raw),
    );
    final row = (await db.query('ManagerFixtures')).single;
    final opponent = OpponentLineup.decode(row['opponentLineup'])!;
    expect(opponent.squad.players, hasLength(3));
    expect(opponent.squad.starters, hasLength(2));
    expect(
      opponent.performances
          .firstWhere((p) => p.playerInstanceId == 'fc-opponent:21')
          .substitutionDetails
          .single
          .minute,
      76,
    );
    expect(
      opponent.performances
          .firstWhere((p) => p.playerInstanceId == 'fc-opponent:22')
          .substitutionDetails
          .single
          .type,
      SubstitutionType.inGame,
    );
    final all = (await sql.getPerformanceModels(person.id, result.fixtureId));
    final source = all.firstWhere((p) => p.apiStats['futureCounter'] == 17);
    expect(source.apiStats['npkExpectedGoals'], 1.2345);
    final joined = await sql.getPlayerMatchRows(
      person.id,
      source.playerInstanceId,
    );
    expect(
      PlayerMatchData(joined.single).performance.apiStats['interceptions'],
      3,
    );
  });
  test(
    'Saved career/team binding is reused after both file and save-name changes',
    () async {
      final saved = await repo.bind(
        link: link,
        remote: apiCareer(),
        season: season,
        bringSquad: false,
      );
      final remote = apiCareer(saveId: 'save-NEW');
      (remote.overview['save'] as Map)['inGameName'] =
          'Novo nome do mesmo save';
      final before = await db.query('FcScoreCareerLink');
      final found = await repo.linkedCareerFor(remote, person: person);
      expect(found!.personId, person.id);
      expect(found.competitions, saved.competitions);
      expect(await db.query('FcScoreCareerLink'), before);
      final moved = await repo.moveLink(
        found,
        remote.saveId,
        saveName: remote.saveName,
      );
      expect(moved.saveId, 'save-NEW');
      expect(moved.saveName, remote.saveName);
      expect((await repo.linkFor(person.id))!.teams, saved.teams);
    },
  );
  test('Global connection reuses only an unambiguous matching career and never another club or game', () async {
    await repo.moveLink(link, 'save-OLD');
    final remote = apiCareer();
    expect((await repo.linkedCareerFor(remote))!.personId, person.id);
    final other = reviewPerson(id: 'other');
    await db.insert('Persons', other.toMap());
    await repo.moveLink(apiLink(personId: other.id), 'save-OTHER');
    expect(await repo.linkedCareerFor(remote), isNull);
    expect(
      (await repo.linkedCareerFor(remote, person: person))!.personId,
      person.id,
    );
    remote.overview['club'] = {'id': 200, 'name': 'Outro clube'};
    expect(await repo.linkedCareerFor(remote, person: person), isNull);
    final changedGame = FcScoreRemoteCareer(
      overview: apiCareer().overview,
      squad: [],
      competitions: [],
      gameVersion: 'FC25',
    );
    expect(await repo.linkedCareerFor(changedGame, person: person), isNull);
    expect(
      await repo.linkedCareerFor(apiCareer(category: 'player'), person: person),
      isNull,
    );
  });
  test('Older previews restore confirmed mappings but keep explicit changes and player drafts', () {
    final saved = link.copy()
      ..teams['300'] = 'confirmed-third'
      ..players['10'] = 'confirmed-player';
    final stale = link.copy()
      ..teams['300'] = 'new:Third'
      ..players['10'] = 'new';
    final resumed = stale.withSavedMappings(saved);
    expect(resumed.teams['300'], 'confirmed-third');
    expect(resumed.players['10'], 'confirmed-player');
    stale.players['10'] = 'explicit-other-player';
    expect(
      stale.withSavedMappings(saved).players['10'],
      'explicit-other-player',
    );
    final p = apiPlayer(10, 'Pedro');
    final draft = fcCreatePlayerChoice(p, fcGeneratePlayerProfile(p));
    stale.players['10'] = draft;
    expect(stale.withSavedMappings(saved).players['10'], draft);
    expect(stale.teams['300'], 'new:Third');
  });
  test(
    'First career binding can create incomplete players from an inline draft',
    () async {
      final remote = apiCareer();
      final player = remote.squad.first;
      player['name'] = '';
      player['overall'] = null;
      final profile = fcGeneratePlayerProfile(player)
        ..['name'] = 'Criado no de-para';
      link.players['10'] = fcCreatePlayerChoice(player, profile);
      expect(await db.query('CustomCreatedPlayer'), isEmpty);
      final saved = await repo.bind(link: link, remote: remote, season: season);
      final created = (await db.query(
        'CustomCreatedPlayer',
        where: 'id = ?',
        whereArgs: [saved.players['10']],
      )).single;
      expect(created['name'], 'Criado no de-para');
      expect(created['overall'], profile['overall']);
      expect(
        (await db.query(
          'Overall',
          where: 'customPlayerId = ?',
          whereArgs: [created['id']],
        )).single['overall'],
        profile['overall'],
      );
      await repo.bind(link: saved, remote: remote, season: season);
      expect((await db.query('CustomCreatedPlayer')).length, 2);
    },
  );
  test('Detailed match import consumes an inline player draft without altering goals', () async {
    final raw = apiReport();
    final player = ((raw['away'] as Map)['players'] as List).first as FcJson;
    final source = fcObject(player['profile'])
      ..['name'] = ''
      ..['overall'] = null;
    player['profile'] = source;
    link.players['10'] = fcCreatePlayerChoice(
      source,
      fcGeneratePlayerProfile(source)..['name'] = 'Criado na partida',
    );
    await repo.importMatch(
      person: person,
      link: link,
      match: FcScoreMatch.fromReport(raw),
    );
    expect(
      (await db.query(
        'CustomCreatedPlayer',
        where: 'id = ?',
        whereArgs: [link.players['10']],
      )).single['name'],
      'Criado na partida',
    );
    expect(
      (await db.query(
        'ManagerFixturePlayerPerformances',
        where: 'playerInstanceId = ?',
        whereArgs: [link.players['10']],
      )).single['goalsCount'],
      1,
    );
  });
  Future<FcImportResult> import(
    FcJson raw, {
    FcScoreLink? selected,
    Person? career,
  }) => repo.importMatch(
    person: career ?? person,
    link: selected ?? link,
    match: FcScoreMatch.fromReport(raw),
  );
  test(
    'Migration adds optional metadata without losing existing rows',
    () async {
      final legacy = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await legacy.execute(
        'CREATE TABLE ManagerFixturePlayerPerformances(id TEXT, goalsCount INTEGER)',
      );
      await legacy.insert('ManagerFixturePlayerPerformances', {
        'id': 'old',
        'goalsCount': 14,
      });
      await ensureFcScoreSchema(legacy);
      await ensureFcScoreSchema(legacy);
      expect(
        (await legacy.query('ManagerFixturePlayerPerformances'))
            .single['goalsCount'],
        14,
      );
      expect(
        (await legacy.rawQuery(
          'PRAGMA table_info(ManagerFixturePlayerPerformances)',
        )).where((r) => r['name'] == 'recordedMinutes').length,
        1,
      );
      await legacy.close();
    },
  );
  test('Recent connections persist, require explicit selection and keep only eight', () async {
    for (var i = 1; i <= 10; i++) {
      await repo.rememberAddress(fcScoreAddress('192.168.0.$i'));
    }
    final restored = FcScoreRepository(sql: sql);
    expect((await restored.recentAddresses()).length, 8);
    expect((await restored.recentAddresses()).first, contains('192.168.0.10'));
    await repo.rememberAddress(fcScoreAddress('192.168.0.5'));
    expect((await restored.recentAddresses()).first, contains('192.168.0.5'));
  });
  test('Bind existing career preserves history and starting XI, records latest overall', () async {
    await db.insert('CustomCreatedPlayer', {
      'id': 'existing',
      'personId': person.id,
      'realPlayerId': '10',
      'name': 'Pedro Silva',
      'positionId': '25',
      'overall': 65,
      'potential': 90,
      'realFace': 0,
      'fromRealPlayer': 0,
      'foot': 'Right',
    });
    await db.insert('TeamPlayer', {
      'id': 'starter',
      'personId': person.id,
      'playerId': 'existing',
      'seasonId': season.id,
      'isBench': 0,
      'overall': 65,
    });
    await db.insert('Overall', {
      'id': 'old',
      'personId': person.id,
      'customPlayerId': 'existing',
      'date': '2027-01-01',
      'overall': 70,
    });
    link.players['10'] = 'existing';
    link.players['11'] = 'new';
    final saved = await repo.bind(
      link: link,
      remote: apiCareer(),
      season: season,
    );
    expect(
      (await db.query(
        'TeamPlayer',
        where: 'id = ?',
        whereArgs: ['starter'],
      )).single['isBench'],
      0,
    );
    expect(
      (await sql.getCustomPlayerById(person.id, 'existing'))!['overall'],
      82,
    );
    expect((await db.query('Overall')).length, 3);
    expect((await db.query('CustomCreatedPlayer')).length, 2);
    expect((await repo.linkFor(person.id))!.players, saved.players);
    await repo.bind(link: saved, remote: apiCareer(), season: season);
    expect((await db.query('CustomCreatedPlayer')).length, 2);
    expect((await db.query('TeamPlayer')).length, 2);
    expect((await db.query('Overall')).length, 3);
  });
  test('Create career, club, league and competitions atomically without activating it', () async {
    final now = DateTime(2028);
    final incoming = Person(
      id: 'new-career',
      name: 'Nova carreira',
      category: PersonCategory.manager,
      fifaVersion: 'FC26',
      leagueId: 'new:Minha Liga',
      teamId: 'new:Meu Clube',
      nationalityId: '54',
      createdAt: now,
      updatedAt: now,
    );
    final selected = apiLink(personId: 'new-career')
      ..localLeagueId = 'new:Minha Liga'
      ..localClubId = 'new:Meu Clube';
    selected.competitions['1528'] = 'new:Minha competição';
    final newSeason = Season(
      id: 'new-season',
      personId: incoming.id,
      startDate: now,
      endDate: DateTime(2028, 12, 31),
      createdAt: now,
    );
    await db.insert('Settings', {'activePersonId': person.id});
    final saved = await repo.bind(
      link: selected,
      remote: apiCareer(),
      season: newSeason,
      newPerson: incoming,
    );
    expect(saved.localClubId, isNot(startsWith('new:')));
    expect((await db.query('CustomClub')).single['label'], 'Meu Clube');
    expect((await db.query('Tournament')).single['type'], 'custom');
    expect((await db.query('Settings')).single['activePersonId'], person.id);
  });
  test('Ambiguous player mapping rolls back roster and link changes', () async {
    await db.insert('CustomCreatedPlayer', {
      'id': 'existing',
      'personId': person.id,
      'name': 'Pedro Silva',
      'positionId': '25',
      'overall': 80,
      'potential': 90,
      'realFace': 0,
      'fromRealPlayer': 0,
      'foot': 'Right',
    });
    link.players.addAll({'10': 'existing', '11': 'existing'});
    await expectLater(
      repo.bind(link: link, remote: apiCareer(), season: season),
      throwsA(isA<FcScoreException>()),
    );
    expect(await db.query('TeamPlayer'), isEmpty);
    expect(await repo.linkFor(person.id), isNull);
  });
  for (final away in [true, false]) {
    test(
      'Import ${away ? 'away' : 'home'} stats, real minutes, reserve and opponent snapshots',
      () async {
        final result = await import(apiReport(away: away));
        final fixture = (await db.query('ManagerFixtures')).single;
        expect(fixture['location'], away ? 'away' : 'home');
        expect(fixture['playerTeamScore'], 2);
        expect(fixture['oppositeTeamScore'], 1);
        expect(fixture['date'], '2028-06-25T00:00:00.000');
        expect(fixture['extraTime'], 0);
        expect(fixture['teamPossession'], isNull);
        expect(fixture['passAccuracy'], 85);
        expect(fixture['playerTeamShoutsCount'], 15);
        expect(fixture['playerOfTheMatchId'], link.players['10']);
        final rows = await db.query('ManagerFixturePlayerPerformances');
        expect(rows.length, 2);
        final starter = ManagerFixturePlayerPerformance.fromMap(rows.first);
        expect(getManagerPlayerPlayedMinutes(starter, 90), 93);
        expect(
          getManagerFixtureDurationMinutes(
            extraTime: false,
            performance: starter,
          ),
          90,
        );
        expect(starter.goalDetails.single.minute, isNull);
        expect(starter.substitutionDetails, isEmpty);
        final sub = rows.firstWhere((r) => r['recordedStarted'] == 0);
        expect(PlayerMatchData(sub).started, false);
        expect(PlayerMatchData(sub).minutes, 27);
        final formation = FixtureFormation.decode(fixture['matchLineup']);
        expect(formation!.bench, contains(link.players['12']));
        expect(
          OpponentLineup.decode(fixture['opponentLineup'])!
              .performances
              .single
              .playerInstanceId,
          'fc-opponent:20',
        );
        expect(
          jsonDecode(
            (await db.query('FcScoreImport')).single['rawJson'] as String,
          )['id'],
          'batch-A',
        );
        expect(result.state, FcImportState.available);
      },
    );
  }
  test(
    'Double tap and another export of same fixture never duplicate',
    () async {
      final results = await Future.wait([
        import(apiReport()),
        import(apiReport()),
      ]);
      expect(results.map((r) => r.fixtureId).toSet().length, 1);
      final repeat = await import(apiReport(id: 'batch-B'));
      expect(repeat.state, FcImportState.alreadyImported);
      expect((await db.query('ManagerFixtures')).length, 1);
      expect((await db.query('ManagerFixturePlayerPerformances')).length, 2);
    },
  );
  test(
    'New save file of the same career still recognizes the fixture',
    () async {
      await import(apiReport());
      final other = FcScoreLink.fromMap({...link.toMap(), 'saveId': 'save-B'});
      expect(
        (await import(
          apiReport(id: 'batch-B', saveId: 'save-B'),
          selected: other,
        )).state,
        FcImportState.alreadyImported,
      );
    },
  );
  test('Manual fixture is detected and preserved', () async {
    await db.insert('ManagerFixtures', {
      ...reviewFixture(0, season: season.id),
      'date': '2028-06-25T12:00:00.000',
      'oppositeTeamId': 'rival',
      'location': 'away',
      'notes': 'Anotação manual',
      'playerTeamScore': 3,
    });
    expect((await import(apiReport())).state, FcImportState.alreadyImported);
    expect(
      (await db.query('ManagerFixtures')).single['notes'],
      'Anotação manual',
    );
    expect(await db.query('FcScoreImport'), isEmpty);
  });
  test('Score-only import is completed on the same fixture, without changing notes', () async {
    final initial = await repo.importMatch(
      person: person,
      link: link,
      match: FcScoreMatch.fromFixture(apiFixture(), 'save-A'),
    );
    expect(await db.query('ManagerFixturePlayerPerformances'), isEmpty);
    await db.update(
      'ManagerFixtures',
      {'notes': 'Minha anotação'},
      where: 'id = ?',
      whereArgs: [initial.fixtureId],
    );
    expect(
      await repo.importState(
        person,
        link,
        FcScoreMatch.fromReport(apiReport()),
      ),
      FcImportState.canComplete,
    );
    final complete = await import(apiReport());
    expect(complete.fixtureId, initial.fixtureId);
    expect(complete.state, FcImportState.canComplete);
    expect((await db.query('ManagerFixtures')).length, 1);
    expect(
      (await db.query('ManagerFixtures')).single['notes'],
      'Minha anotação',
    );
  });
  test('Do not overwrite individual performances manually added after score import', () async {
    final initial = await repo.importMatch(
      person: person,
      link: link,
      match: FcScoreMatch.fromFixture(apiFixture(), 'save-A'),
    );
    await db.insert(
      'ManagerFixturePlayerPerformances',
      ManagerFixturePlayerPerformance(
        personId: person.id,
        fixtureId: initial.fixtureId,
        playerInstanceId: 'manual',
      ).toMap(),
    );
    expect((await import(apiReport())).state, FcImportState.alreadyImported);
    expect(
      (await db.query('ManagerFixturePlayerPerformances'))
          .single['playerInstanceId'],
      'manual',
    );
  });
  test(
    'Explicitly deleted fixture can be imported again despite stale ledger',
    () async {
      final initial = await import(apiReport());
      await db.delete(
        'ManagerFixturePlayerPerformances',
        where: 'fixtureId = ?',
        whereArgs: [initial.fixtureId],
      );
      await db.delete(
        'ManagerFixtures',
        where: 'id = ?',
        whereArgs: [initial.fixtureId],
      );
      expect((await import(apiReport())).state, FcImportState.available);
      expect((await db.query('ManagerFixtures')).length, 1);
    },
  );
  test(
    'Imported partial minutes do not attribute untimed goals to a substitute',
    () async {
      await import(apiReport());
      final fixture = (await db.query('ManagerFixtures')).single;
      final perf = (await db.query(
        'ManagerFixturePlayerPerformances',
        where: 'recordedStarted = 0',
      )).single;
      final summary = PlayerSummary(
        allMatches: [
          PlayerMatchData({
            ...perf,
            ...fixture,
            'fixtureId': fixture['id'],
            'id': perf['id'],
          }),
        ],
        source: PlayerSummarySource(fixtures: [fixture]),
      );
      expect(summary.totals.minutes, 27);
      expect(summary.totals.starts, 0);
      expect(summary.minutesOn, 27);
      expect(summary.minutesOff, 63);
      expect(summary.unassignedGoals, 3);
      expect(summary.forOn, 0);
    },
  );
  test(
    'Missing team and player statistics remain unknown; opponent MOTM is kept',
    () async {
      final raw = apiReport();
      (raw['away'] as Map)['stats'] = <String, Object?>{};
      final stats =
          ((((raw['away'] as Map)['players'] as List).first as Map)['stats']
              as Map);
      for (final key in [
        'goalsDerived',
        'assists',
        'yellowCardEvents',
        'passes',
        'shots',
      ]) {
        stats.remove(key);
      }
      raw['manOfTheMatch'] = {
        'player': {'id': 20, 'name': 'João Souza'},
        'team': {'id': 200, 'name': 'Rival FC'},
      };
      await import(raw);
      final fixture = (await db.query('ManagerFixtures')).single;
      expect(fixture['passAccuracy'], isNull);
      expect(fixture['playerTeamShoutsCount'], isNull);
      expect(fixture['playerOfTheMatchId'], 'João Souza');
      expect(fixture['isPotmFromMyTeam'], 0);
      final perf = (await db.query(
        'ManagerFixturePlayerPerformances',
        where: 'playerInstanceId = ?',
        whereArgs: [link.players['10']],
      )).single;
      expect(perf['goalsCount'], isNull);
      expect(perf['assistsCount'], isNull);
      expect(perf['passes'], isNull);
    },
  );
  test('Linked players retain their customized name and portrait on the imported pitch', () async {
    await db.insert('CustomCreatedPlayer', {
      'id': 'custom-10',
      'personId': person.id,
      'realPlayerId': '10',
      'name': 'Meu camisa 10',
      'positionId': '25',
      'overall': 80,
      'potential': 90,
      'realFace': 1,
      'fromRealPlayer': 1,
      'foot': 'Right',
      'customAvatarFilePath': 'faces/personal.png',
    });
    link.players['10'] = 'custom-10';
    await import(apiReport());
    final formation = FixtureFormation.decode(
      (await db.query('ManagerFixtures')).single['matchLineup'],
    )!;
    expect(formation.players['custom-10']!['name'], 'Meu camisa 10');
    expect(
      formation.players['custom-10']!['customAvatarFilePath'],
      'faces/personal.png',
    );
  });
  for (final failure in [
    'wrong-save',
    'score-conflict',
    'unknown-date',
    'unknown-player',
    'invalid-minutes',
    'negative-stat',
    'same-club',
    'wrong-season',
    'wrong-person',
  ]) {
    test('Reject $failure with full rollback', () async {
      final raw = apiReport();
      switch (failure) {
        case 'wrong-save':
          raw['activeSave'] = {'id': 'save-B'};
        case 'score-conflict':
          fcObject(raw['match'])['savedResult'] = {
            'played': true,
            'home': 7,
            'away': 8,
          };
          raw['match'] = {
            ...fcObject(raw['match']),
            'savedResult': {'played': true, 'home': 7, 'away': 8},
          };
        case 'unknown-date':
          raw['match'] = {...fcObject(raw['match']), 'date': null};
        case 'unknown-player':
          fcList(fcObject(raw['away'])['players']).first['id'] = -1;
          final players = (raw['away'] as Map)['players'] as List;
          (players.first as Map)['id'] = -1;
        case 'invalid-minutes':
          ((((raw['away'] as Map)['players'] as List).first as Map)['stats']
                  as Map)['minutesPlayed'] =
              200;
        case 'negative-stat':
          ((((raw['away'] as Map)['players'] as List).first as Map)['stats']
                  as Map)['assists'] =
              -1;
        case 'same-club':
          link.teams['200'] = link.localClubId;
        case 'wrong-season':
          link.seasonId = 'missing';
        case 'wrong-person':
          link = apiLink(personId: 'other');
      }
      await expectLater(import(raw), throwsA(isA<FcScoreException>()));
      expect(await db.query('ManagerFixtures'), isEmpty);
      expect(await db.query('ManagerFixturePlayerPerformances'), isEmpty);
      expect(await db.query('CustomCreatedPlayer'), isEmpty);
      expect(await db.query('FcScoreImport'), isEmpty);
    });
  }
  test(
    'Import a player career performance and require selected player',
    () async {
      final player = reviewPerson(category: PersonCategory.player);
      await db.update(
        'Persons',
        player.toMap(),
        where: 'id = ?',
        whereArgs: [player.id],
      );
      final selected = apiLink(category: 'player');
      await import(apiReport(), career: player, selected: selected);
      final fixture = (await db.query('PlayerFixtures')).single;
      expect(fixture['minsPlayed'], 93);
      expect(fixture['goalsCount'], 1);
      expect(fcInt(fixture['playerOfTheMatch']), 1);
      expect(await db.query('ManagerFixturePlayerPerformances'), isEmpty);
    },
  );
  test('Backup and restore preserve mappings, imported identities and original report', () async {
    await import(apiReport());
    await repo.rememberAddress(fcScoreAddress('192.168.1.20'));
    final backup = BackupService(database: () async => db, imageFolders: []);
    final path = await backup.generateBackup(includeImages: false);
    final report = await backup.restoreBackup(path);
    expect(report.skippedRows, 0);
    expect((await repo.linkFor(person.id))!.players, link.players);
    expect(
      await repo.importState(
        person,
        link,
        FcScoreMatch.fromReport(apiReport()),
      ),
      FcImportState.alreadyImported,
    );
    expect((await db.query('FcScoreImport')).single['reportId'], 'batch-A');
    expect((await repo.recentAddresses()).single, contains('192.168.1.20'));
  });
  group('Completing a registered fixture', () {
    Future<String> registered({
      int score = 2,
      List<Map<String, Object?>> opponentGoals = const [],
      ManagerFixturePlayerPerformance? Function(String)? typed,
    }) async {
      await db.insert('CustomCreatedPlayer', {
        'id': 'pedro',
        'personId': person.id,
        'realPlayerId': '10',
        'name': 'Pedro Silva',
        'positionId': '25',
        'overall': 82,
        'potential': 90,
        'realFace': 1,
        'fromRealPlayer': 1,
        'foot': 'Right',
      });
      await db.insert('ManagerFixtures', {
        ...reviewFixture(0, season: season.id),
        'id': 'mine',
        'date': '2028-06-25T00:00:00.000',
        'oppositeTeamId': 'rival',
        'location': 'away',
        'playerTeamScore': score,
        'oppositeTeamScore': 1,
        'notes': 'Minha anotação',
        'opponentGoalDetails': jsonEncode(opponentGoals),
      });
      final performance = typed?.call('mine');
      if (performance != null) {
        await db.insert(
          'ManagerFixturePlayerPerformances',
          performance.toMap(),
        );
      }
      link.players['10'] = 'pedro';
      return 'mine';
    }

    Future<void> complete({FcJson? raw, String fixtureId = 'mine'}) =>
        repo.completeFixture(
          person: person,
          link: link,
          match: FcScoreMatch.fromReport(raw ?? apiReport()),
          fixtureId: fixtureId,
        );

    test(
      'Missing opponents require consent and are reused from club memory',
      () async {
        await registered();
        final match = FcScoreMatch.fromReport(apiReport());
        final preview = await repo.opponentCompletionPreview(
          person: person,
          link: link,
          match: match,
          fixtureId: 'mine',
        );
        expect(preview!.missing, hasLength(1));
        await complete();
        expect(
          OpponentLineup.decode(
            (await db.query('ManagerFixtures')).single['opponentLineup'],
          ),
          isNull,
        );
        await repo.completeFixture(
          person: person,
          link: link,
          match: match,
          fixtureId: 'mine',
          createOpponentPlayers: true,
        );
        final lineup = OpponentLineup.decode(
          (await db.query('ManagerFixtures')).single['opponentLineup'],
        )!;
        expect(lineup.names.values, contains('João Souza'));
        expect(lineup.performances.single.avgRating, 8.4);
        expect(
          (await db.query('CustomCreatedPlayer'))
              .where((p) => p['realPlayerId'] == '20'),
          isEmpty,
        );
        final next = {
          ...reviewFixture(1, season: season.id),
          'id': 'next',
          'date': '2028-07-01',
          'oppositeTeamId': 'rival',
          'oppositeTeamScore': 1,
        };
        await db.insert('ManagerFixtures', next);
        final nextReport = apiReport(id: 'batch-next');
        (nextReport['match'] as Map)['fixtureId'] = 43;
        (nextReport['match'] as Map)['date'] = '2028-07-01';
        final again = await repo.opponentCompletionPreview(
          person: person,
          link: link,
          match: FcScoreMatch.fromReport(nextReport),
          fixtureId: 'next',
        );
        expect(again!.missing, isEmpty);
        await repo.completeFixture(
          person: person,
          link: link,
          match: FcScoreMatch.fromReport(nextReport),
          fixtureId: 'next',
        );
        final remembered = await sql.getRememberedOpponentLineup(
          personId: person.id,
          fifaVersion: person.fifaVersion,
          teamId: 'rival',
          leagueId: '1014',
        );
        expect(remembered!.names.values, contains('João Souza'));
        final filled = OpponentLineup.decode(
          (await db.query(
            'ManagerFixtures',
            where: 'id = ?',
            whereArgs: ['next'],
          )).single['opponentLineup'],
        )!;
        expect(
          filled.performances.single.playerInstanceId,
          lineup.performances.single.playerInstanceId,
        );
        final otherTeam = await repo.opponentPlayers(
          person: person,
          teamId: 'unrelated',
          leagueId: '1014',
          seasonId: season.id,
        );
        expect(otherTeam, isEmpty);
      },
    );

    test('Completing opponent stats preserves identity, photo, rating, goals and substitutions', () async {
      final goal = OpponentGoalDetails(scorerName: 'João Souza', minute: 67);
      await registered(opponentGoals: [goal.toMap()]);
      final empty = OpponentLineup.empty(formation: '4-4-2');
      final id = empty.startingIds.first;
      final lineup = empty
          .withIdentity(id, name: 'João Souza', photo: 'faces/my-photo.png')
          .copy(
            performances: [
              ManagerFixturePlayerPerformance(
                personId: person.id,
                fixtureId: 'mine',
                playerInstanceId: id,
                avgRating: 6.7,
                goalDetails: [PerformanceGoalDetails(id: goal.id, minute: 67)],
                substitutionDetails: [
                  PerformanceSubstitutionDetails(
                    minute: 80,
                    type: SubstitutionType.outGame,
                  ),
                ],
              ),
            ],
          );
      await db.update(
        'ManagerFixtures',
        {'opponentLineup': lineup.encode()},
        where: 'id = ?',
        whereArgs: ['mine'],
      );
      expect(
        (await repo.opponentCompletionPreview(
          person: person,
          link: link,
          match: FcScoreMatch.fromReport(apiReport()),
          fixtureId: 'mine',
        ))!.missing,
        isEmpty,
      );
      await complete();
      final row = (await db.query('ManagerFixtures')).single;
      final filled = OpponentLineup.decode(row['opponentLineup'])!;
      expect(filled.squad.formation, '4-4-2');
      expect(
        filled.squad.players[id]!['customAvatarFilePath'],
        'faces/my-photo.png',
      );
      expect(filled.names[id], 'João Souza');
      final perf = filled.performances.single;
      expect(perf.playerInstanceId, id);
      expect(perf.avgRating, 6.7);
      expect(perf.passes, 20);
      expect(perf.goalDetails.single.minute, 67);
      expect(perf.substitutionDetails.single.minute, 80);
      expect(perf.recordedMinutes, isNull);
      expect(decodeOpponentGoals(row['opponentGoalDetails']).single.minute, 67);
      final before = filled.encode();
      await complete();
      expect(
        (await db.query('ManagerFixtures')).single['opponentLineup'],
        before,
      );
    });

    Future<ManagerFixturePlayerPerformance> performanceOf(
      String player,
    ) async => ManagerFixturePlayerPerformance.fromMap(
      (await db.query(
        'ManagerFixturePlayerPerformances',
        where: 'playerInstanceId = ?',
        whereArgs: [player],
      )).single,
    );

    test(
      'World roster custom players appear only for their mapped opponent',
      () async {
        await registered();
        await ensureFcScoreSchema(db);
        await db.insert('CustomCreatedPlayer', {
          'id': 'custom-opponent',
          'personId': person.id,
          'name': 'João Souza',
          'positionId': '25',
          'overall': 77,
          'potential': 80,
          'realFace': 0,
          'fromRealPlayer': 0,
          'foot': 'Right',
          'customAvatarFilePath': 'faces/opponent.png',
        });
        await db.insert('FcScoreWorldTeam', {
          'personId': person.id,
          'seasonId': season.id,
          'remoteId': '200',
          'teamId': 'rival',
          'leagueId': '1014',
          'rawJson': '{}',
        });
        await db.insert('FcScoreWorldPlayer', {
          'personId': person.id,
          'seasonId': season.id,
          'remoteTeamId': '200',
          'remotePlayerId': '20',
          'playerId': 'custom-opponent',
          'rawJson': jsonEncode(apiPlayer(20, 'João Souza')),
        });
        final candidates = await repo.opponentPlayers(
          person: person,
          teamId: 'rival',
          leagueId: '1014',
          seasonId: season.id,
        );
        expect(candidates.single['name'], 'João Souza');
        expect(candidates.single['customAvatarFilePath'], 'faces/opponent.png');
        final review = await repo.opponentCompletionPreview(
          person: person,
          link: link,
          match: FcScoreMatch.fromReport(apiReport()),
          fixtureId: 'mine',
        );
        expect(review!.missing, isEmpty);
        await complete();
        final lineup = OpponentLineup.decode(
          (await db.query('ManagerFixtures')).single['opponentLineup'],
        )!;
        expect(lineup.performances.single.playerInstanceId, 'custom-opponent');
      },
    );

    test('Opponent completion does not add goals already credited manually to someone else', () async {
      await registered(
        opponentGoals: [
          OpponentGoalDetails(scorerName: 'Autor manual', minute: 40).toMap(),
          OpponentGoalDetails(
            scorerName: 'Contra manual',
            minute: 50,
            isOwnGoal: true,
          ).toMap(),
        ],
      );
      final raw = apiReport();
      final other = (raw['home'] as Map)['players'] as List;
      ((other.single as Map)['stats'] as Map)['ownGoals'] = 1;
      await repo.completeFixture(
        person: person,
        link: link,
        match: FcScoreMatch.fromReport(raw),
        fixtureId: 'mine',
        createOpponentPlayers: true,
      );
      final row = (await db.query('ManagerFixtures')).single;
      final goals = decodeOpponentGoals(row['opponentGoalDetails']);
      expect(goals, hasLength(2));
      expect(goals.map((g) => g.minute), containsAll([40, 50]));
      final ownPerfs = (await db.query('ManagerFixturePlayerPerformances'))
          .map(ManagerFixturePlayerPerformance.fromMap);
      expect(ownPerfs.fold<int>(0, (n, p) => n + p.goalDetails.length), 1);
    });

    test(
      'Typed events, minutes and substitutions stay; the rest is filled',
      () async {
        await registered(
          opponentGoals: [
            OpponentGoalDetails(
              scorerName: 'Atacante rival',
              minute: 60,
            ).toMap(),
          ],
          typed: (fixture) => ManagerFixturePlayerPerformance(
            personId: person.id,
            fixtureId: fixture,
            playerInstanceId: 'pedro',
            goalsCount: 1,
            goalDetails: [PerformanceGoalDetails(minute: 30)],
            substitutionDetails: [
              PerformanceSubstitutionDetails(
                minute: 70,
                type: SubstitutionType.outGame,
              ),
            ],
          ),
        );
        await complete();
        final fixture = (await db.query('ManagerFixtures')).single;
        expect(fixture['playerTeamScore'], 2);
        expect(fixture['oppositeTeamId'], 'rival');
        expect(fixture['notes'], 'Minha anotação');
        expect(fixture['passAccuracy'], 82.0);
        expect(fixture['playerTeamShoutsCount'], 15);
        expect(fixture['playerOfTheMatchId'], 'pedro');
        expect(FixtureFormation.decode(fixture['matchLineup']), isNotNull);
        final opponentGoals = decodeOpponentGoals(
          fixture['opponentGoalDetails'],
        );
        expect(opponentGoals.single.minute, 60);
        expect(opponentGoals.single.scorerName, 'Atacante rival');
        final pedro = await performanceOf('pedro');
        expect(pedro.goalDetails.single.minute, 30);
        expect(pedro.substitutionDetails.single.minute, 70);
        expect(pedro.recordedMinutes, isNull);
        expect(pedro.recordedStarted, isNull);
        expect(pedro.avgRating, 8.4);
        expect(pedro.passes, 20);
        expect(pedro.assistsCount, 1);
        expect(pedro.yellowCards, 1);
        final added = (await db.query('ManagerFixturePlayerPerformances'))
            .where((row) => row['playerInstanceId'] != 'pedro')
            .single;
        final marcos = ManagerFixturePlayerPerformance.fromMap(added);
        expect(marcos.recordedMinutes, 27);
        expect(marcos.recordedStarted, isFalse);
        expect(marcos.goalDetails, hasLength(1));
        final ledger = (await db.query('FcScoreImport')).single;
        expect(ledger['fixtureId'], 'mine');
        expect(ledger['completedByUser'], 1);
        expect(
          await repo.importState(
            person,
            link,
            FcScoreMatch.fromReport(apiReport()),
          ),
          FcImportState.alreadyImported,
        );
        expect(
          (await import(apiReport())).state,
          FcImportState.alreadyImported,
        );
        expect(
          (await db.query('ManagerFixtures')).single['notes'],
          'Minha anotação',
        );
        expect(
          await db.query('ManagerFixturePlayerPerformances'),
          hasLength(2),
        );
      },
    );

    test(
      'Goals the user credited to another player are not added twice',
      () async {
        await registered(
          typed: (fixture) => ManagerFixturePlayerPerformance(
            personId: person.id,
            fixtureId: fixture,
            playerInstanceId: 'pedro',
            goalsCount: 2,
            goalDetails: [
              PerformanceGoalDetails(minute: 10),
              PerformanceGoalDetails(minute: 20),
            ],
          ),
        );
        await complete();
        final rows = await db.query('ManagerFixturePlayerPerformances');
        final goals = rows
            .map(ManagerFixturePlayerPerformance.fromMap)
            .fold<int>(0, (n, p) => n + p.goalDetails.length);
        expect(goals, 2);
        expect(
          (await performanceOf('pedro')).goalDetails.map((g) => g.minute),
          [10, 20],
        );
      },
    );

    test('A match already linked to another fixture is refused', () async {
      await import(apiReport());
      await registered();
      await expectLater(
        complete(),
        throwsA(
          isA<FcScoreException>().having(
            (e) => '$e',
            'message',
            contains('já está vinculada a outro jogo'),
          ),
        ),
      );
      expect(
        (await db.query(
          'ManagerFixtures',
          where: 'id = ?',
          whereArgs: ['mine'],
        )).single['playerTeamShoutsCount'],
        isNull,
      );
    });

    test(
      'Player career keeps typed counters and fills the missing ones',
      () async {
        final player = reviewPerson(category: PersonCategory.player);
        await db.update(
          'Persons',
          player.toMap(),
          where: 'id = ?',
          whereArgs: [player.id],
        );
        await db.insert(
          'PlayerFixtures',
          {
            ...reviewFixture(0, season: season.id),
            'id': 'mine',
            'date': '2028-06-25T00:00:00.000',
            'oppositeTeamId': 'rival',
            'location': 'away',
            'playerTeamScore': 2,
            'oppositeTeamScore': 1,
            'goalsCount': 0,
            'assistsCount': 2,
            'savesCount': 0,
            'yellowCards': 0,
            'redCards': 0,
            'isInjured': 0,
          }..removeWhere(
            (key, _) => ['teamPossession', 'passAccuracy'].contains(key),
          ),
        );
        await repo.completeFixture(
          person: player,
          link: apiLink(category: 'player'),
          match: FcScoreMatch.fromReport(apiReport()),
          fixtureId: 'mine',
        );
        final fixture = (await db.query('PlayerFixtures')).single;
        expect(fixture['rating'], 8.4);
        expect(fixture['goalsCount'], 1);
        expect(fixture['assistsCount'], 2);
        expect(fixture['minsPlayed'], 93);
        expect(fixture['playerTeamScore'], 2);
      },
    );
  });

  test('Recommends the single match of the same day and venue', () {
    final fixture = {
      'date': '2028-06-25T00:00:00.000',
      'oppositeTeamId': 'rival',
      'tournamentId': 'league:1014',
      'location': 'away',
      'playerTeamScore': 2,
      'oppositeTeamScore': 1,
    };
    final same = FcScoreMatch.fromFixture(apiFixture(), 'save-A');
    final other = FcScoreMatch.fromFixture({
      ...apiFixture(),
      'id': 50,
      'date': '2028-06-28',
    }, 'save-A');
    final far = FcScoreMatch.fromFixture({
      ...apiFixture(),
      'id': 51,
      'date': '2028-07-25',
    }, 'save-A');
    expect(fcRecommendedMatch(fixture, [other, same, far], link), same);
    expect(fcFixtureAffinity(fixture, far, link), isNull);
    expect(fcRecommendedMatch(fixture, [far], link), isNull);
    final twin = FcScoreMatch.fromFixture({
      ...apiFixture(),
      'id': 52,
    }, 'save-A');
    expect(fcRecommendedMatch(fixture, [same, twin], link), isNull);
  });
}
