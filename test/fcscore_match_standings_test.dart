import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/FcScore/FcScoreModels.dart';
import 'package:mcmanager/FcScore/FcScoreRepository.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fcscore_fixture.dart';
import 'season_review_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late FcScoreRepository repo;
  late FcScoreLink link;
  final person = reviewPerson();
  final season = reviewSeason(id: 's2028', year: 2028);
  final requests = <String>[];
  late FcJson table;
  late String currentDate;
  late FcScoreApi api;
  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    await SqlService.ensureCompatibleSchema(db);
    await SqlService.ensureSeasonClosureSchema(db);
    await db.insert('Persons', person.toMap());
    await db.insert('Seasons', season.toMap());
    repo = FcScoreRepository(sql: SqlService.withDatabase(db));
    link = apiLink();
    requests.clear();
    table = apiTable();
    currentDate = '2028-06-30';
    api = FcScoreApi(
      fcScoreAddress('192.168.0.20'),
      client: MockClient((request) async {
        requests.add(request.url.path);
        final value = request.url.path.endsWith('/competitions/1528')
            ? table
            : {...apiCareer().overview, 'currentDate': currentDate};
        return http.Response(
          jsonEncode(value),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  });
  tearDown(() async {
    api.close();
    await db.close();
  });

  Future<void> configure() async {
    link.worldSync[season.id] = FcWorldSyncState(
      competitionIds: {'1528'},
      ignoredMatchKeys: {'keep-ignored'},
    );
    await db.insert('FcScoreCompetition', {
      'personId': person.id,
      'seasonId': season.id,
      'remoteId': '1528',
      'tournamentId': 'league:1014',
      'saveId': link.saveId,
      'name': 'Brasileirão',
      'currentDate': '2028-06-20',
      'importedAt': 'before',
      'rawJson': jsonEncode({
        ...apiTable(),
        'playerStats': [
          {'kept': true},
        ],
        'playerStatsComplete': true,
      }),
    });
    await db.insert('TournamentPlayersResult', {
      'id': 'fcscore-scorer:keep',
      'personId': person.id,
      'seasonId': season.id,
      'fifaVersion': 'FC26',
      'tournamentResultId': 'fcscore-result:career:s2028:1528',
      'customPlayerId': 'scorer',
      'teamId': person.teamId,
      'type': 'goals',
      'matchesCount': 10,
      'value': 12,
    });
  }

  test(
    'Updates configured tables while retaining scorer data and sync choices',
    () async {
      await configure();
      final scorers = await db.query('TournamentPlayersResult');
      final mapping = jsonEncode(link.toMap());
      final count = await repo.refreshMatchStandings(
        api: api,
        person: person,
        link: link,
      );
      expect(count, 1);
      expect(requests, [
        '/api/careers/save-A',
        '/api/careers/save-A/competitions/1528',
      ]);
      final saved = (await db.query('FcScoreCompetition')).single;
      expect(saved['currentDate'], '2028-06-30');
      expect(jsonDecode(saved['rawJson'] as String)['playerStats'], [
        {'kept': true},
      ]);
      expect(await db.query('TournamentPlayersResult'), scorers);
      expect(jsonEncode(link.toMap()), mapping);
      final rows = await db.query(
        'TournamentResultTableItem',
        orderBy: 'position',
      );
      expect(rows.map((r) => r['teamId']), [person.teamId, 'rival']);
      expect(rows.first['points'], 45);
      for (final name in [
        'TeamPlayer',
        'FcScoreWorldPlayer',
        'FcScoreWorldTeam',
        'FcScoreWorldFixture',
        'ManagerFixtures',
        'FcScoreCareerLink',
      ]) {
        expect(await db.query(name), isEmpty, reason: name);
      }
    },
  );

  test('No configuration or closed season makes no API requests', () async {
    expect(
      await repo.refreshMatchStandings(api: api, person: person, link: link),
      0,
    );
    await configure();
    await db.update('Seasons', {'closedAt': '2029-01-01'});
    expect(
      await repo.refreshMatchStandings(api: api, person: person, link: link),
      0,
    );
    expect(requests, isEmpty);
  });

  test('Invalid tables roll back both the snapshot and native table', () async {
    await configure();
    final before = await db.query('FcScoreCompetition');
    table['stages'][0]['groups'][0]['rows'][1]['points'] = -1;
    await expectLater(
      repo.refreshMatchStandings(api: api, person: person, link: link),
      throwsA(isA<FcScoreException>()),
    );
    expect(await db.query('FcScoreCompetition'), before);
    expect(await db.query('TournamentResultTableItem'), isEmpty);
    expect(await db.query('TournamentPlayersResult'), hasLength(1));
  });

  test(
    'An older save or a different season preserves existing standings',
    () async {
      await configure();
      final before = await db.query('FcScoreCompetition');
      for (final date in ['2028-06-01', '2027-06-30']) {
        currentDate = date;
        await expectLater(
          repo.refreshMatchStandings(api: api, person: person, link: link),
          throwsA(isA<FcScoreException>()),
        );
        expect(await db.query('FcScoreCompetition'), before);
      }
    },
  );
}
