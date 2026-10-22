import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/FcScore/FcScoreMatchSource.dart';
import 'package:mcmanager/FcScore/FcScoreModels.dart';
import 'package:mcmanager/FcScore/FcScoreRepository.dart';
import 'package:mcmanager/models/Person.dart';
import 'package:mcmanager/models/Season.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'backup_storage_fixture.dart';
import 'fcscore_fixture.dart';
import 'season_review_fixture.dart';

FcScoreApi _api(Object? Function(String path) answer) => FcScoreApi(
  fcScoreAddress('pc'),
  client: MockClient((request) async {
    final value = answer(request.url.path);
    if (value is http.Response) return value;
    return http.Response(
      jsonEncode(value),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('Detailed match for a save result', () {
    test(
      'A save result is upgraded to the exported report of the same fixture',
      () async {
        final api = fakeApi(fcScoreAddress('pc'));
        final match = await fcDetailedMatch(
          api,
          FcScoreMatch.fromFixture(apiFixture(), 'save-A'),
        );
        expect(match.detailed, isTrue);
        expect(match.reportId, 'batch-A');
        expect(fcList(match.own(apiLink())['players']), hasLength(3));
        api.close();
      },
    );

    test(
      'Without a report for the fixture the score-only match is kept',
      () async {
        final api = fakeApi(fcScoreAddress('pc'));
        final original = FcScoreMatch.fromFixture({
          ...apiFixture(),
          'id': 99,
        }, 'save-A');
        final match = await fcDetailedMatch(api, original);
        expect(match, same(original));
        expect(match.detailed, isFalse);
        api.close();
      },
    );

    test('An unavailable report folder keeps the score-only match', () async {
      final api = _api(
        (path) => path.endsWith('/matches')
            ? http.Response(
                '{"error":{"code":"PERFORMANCE_DIRECTORY_UNAVAILABLE"}}',
                503,
              )
            : apiReport(),
      );
      final match = await fcDetailedMatch(
        api,
        FcScoreMatch.fromFixture(apiFixture(), 'save-A'),
      );
      expect(match.detailed, isFalse);
      expect(match.warnings, isEmpty);
      api.close();
    });

    test('A report of other teams is ignored', () async {
      final api = _api(
        (path) => path.endsWith('/matches')
            ? [
                {'id': 'batch-A', 'fixtureId': 42},
              ]
            : path.endsWith('/set-file')
            ? {'id': 'save-A'}
            : apiReport(away: false),
      );
      final match = await fcDetailedMatch(
        api,
        FcScoreMatch.fromFixture(apiFixture(), 'save-A'),
      );
      expect(match.detailed, isFalse);
      api.close();
    });

    test(
      'A report that fails to load keeps the score and explains why',
      () async {
        final api = _api(
          (path) => path.endsWith('/matches')
              ? [
                  {'id': 'batch-A', 'fixtureId': 42},
                ]
              : http.Response('{"error":{"code":"NOT_FOUND"}}', 404),
        );
        final match = await fcDetailedMatch(
          api,
          FcScoreMatch.fromFixture(apiFixture(), 'save-A'),
        );
        expect(match.detailed, isFalse);
        expect(match.warnings.single, contains('desempenho dos jogadores'));
        api.close();
      },
    );

    test('Reports are indexed by fixture, keeping the newest export', () async {
      final api = _api(
        (_) => [
          {'id': 'new', 'fixtureId': 42},
          {'id': 'old', 'fixtureId': 42},
          {'id': 'other', 'fixtureId': 7},
          {'id': 'unlinked', 'fixtureId': null},
        ],
      );
      final reports = await fcReportsByFixture(api);
      expect(reports.keys, unorderedEquals(['42', '7']));
      expect(reports['42']!['id'], 'new');
      api.close();
    });
  });

  group('Career link and imports', () {
    late Database db;
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
      repo = FcScoreRepository(sql: SqlService.withDatabase(db));
      person = reviewPerson();
      season = reviewSeason(id: 's2028', year: 2028);
      link = apiLink();
      await db.insert('Persons', person.toMap());
      await db.insert('Seasons', season.toMap());
    });
    tearDown(() async => db.close());

    FcJson save(
      String id, {
      String name = 'Minha carreira',
      String type = 'manager',
      int? backupSlot,
    }) => {
      'id': id,
      'inGameName': name,
      'careerType': type,
      'backupSlot': backupSlot,
    };

    test('A renamed save is found by in-game name, ignoring backups and other careers', () {
      expect(
        repo.currentSave([save('save-A'), save('save-B')], link, person)!['id'],
        'save-A',
      );
      expect(
        repo.currentSave(
          [
            save('save-B'),
            save('_1_save-B', backupSlot: 1),
            save('other', name: 'Outra'),
          ],
          link,
          person,
        )!['id'],
        'save-B',
      );
      expect(
        repo.currentSave([save('save-B'), save('save-C')], link, person),
        isNull,
      );
      expect(
        repo.currentSave([save('save-B', type: 'player')], link, person),
        isNull,
      );
    });

    test('Moving a link to the renamed save keeps every mapping', () async {
      link.players['10'] = 'local-10';
      final moved = await repo.moveLink(link, 'save-B');
      final stored = (await repo.linkFor(person.id))!;
      expect(moved.saveId, 'save-B');
      expect(stored.saveId, 'save-B');
      expect(stored.players, {'10': 'local-10'});
      expect(stored.teams, link.teams);
      expect(stored.competitions, link.competitions);
    });

    test(
      'Importing the save result brings player actions when a report exists',
      () async {
        final api = fakeApi(fcScoreAddress('pc'));
        final scoreOnly = await repo.importMatch(
          person: person,
          link: link,
          match: FcScoreMatch.fromFixture(apiFixture(), 'save-A'),
        );
        expect(await db.query('ManagerFixturePlayerPerformances'), isEmpty);
        final detailed = await fcDetailedMatch(
          api,
          FcScoreMatch.fromFixture(apiFixture(), 'save-A'),
        );
        expect(
          await repo.importState(person, link, detailed),
          FcImportState.canComplete,
        );
        final completed = await repo.importMatch(
          person: person,
          link: link,
          match: detailed,
        );
        expect(completed.fixtureId, scoreOnly.fixtureId);
        final performances = await db.query('ManagerFixturePlayerPerformances');
        expect(performances, hasLength(2));
        expect(performances.map((p) => p['goalsCount']), everyElement(1));
        expect(performances.map((p) => p['assistsCount']), everyElement(1));
        expect((await db.query('ManagerFixtures')), hasLength(1));
        api.close();
      },
    );
  });
}
