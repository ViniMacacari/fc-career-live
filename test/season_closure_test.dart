import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/models/Person.dart';
import 'package:mcmanager/models/Season.dart';
import 'package:mcmanager/models/SeasonReview.dart';
import 'package:mcmanager/models/TournamentResult.dart';
import 'package:mcmanager/utils/BackupService.dart';
import 'package:mcmanager/utils/SeasonClosureService.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late SeasonClosureService service;
  final person = reviewPerson();
  final season = reviewSeason();
  const labels = SeasonReviewLabels(
    teams: {'40-13': 'São Paulo', 'fla': 'Flamengo'},
    competitions: {'league:1014': 'Brasileirão', 'cup': 'Copa'},
    formats: {'cup': 'single'},
  );
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('CREATE TABLE Settings(activePersonId TEXT)');
    await SqlService.ensureCompatibleSchema(db);
    await SqlService.ensureSeasonClosureSchema(db);
    await db.insert('Persons', person.toMap());
    await db.insert('Seasons', season.toMap());
    service = SeasonClosureService(
      database: () => Future.value(db),
      labels: labels,
    );
  });
  tearDown(() async => db.close());
  Future<void> matches() async {
    for (var i = 0; i < 3; i++) {
      await db.insert('ManagerFixtures', reviewFixture(i));
    }
  }

  SeasonFinalTable table({
    int position = 1,
    String id = '',
    List<SeasonStanding>? rows,
  }) => SeasonFinalTable(
    id: id,
    tournamentId: 'league:1014',
    name: 'Brasileirão',
    ownTeamId: '40-13',
    rows:
        rows ??
        [
          SeasonStanding(
            teamId: '40-13',
            name: 'São Paulo',
            position: position,
            stats: const {'points': 80},
          ),
        ],
  );
  test('Migration preserves older seasons and is repeatable', () async {
    await db.execute('ALTER TABLE Seasons DROP COLUMN closedAt');
    await db.execute('ALTER TABLE Seasons DROP COLUMN recapJson');
    await SqlService.ensureSeasonClosureSchema(db);
    await SqlService.ensureSeasonClosureSchema(db);
    final restored = Season.fromMap((await db.query('Seasons')).single);
    expect(restored.id, season.id);
    expect(restored.isClosed, false);
    expect(restored.recapJson, null);
  });
  test('Closure snapshots results and is idempotent', () async {
    await matches();
    final review = await service.close(person, season, tables: [table()]);
    expect(review.season.isClosed, true);
    expect(review.analytics.played, 3);
    expect(review.titles, 1);
    expect(review.tables.single.rows.single.stats['points'], 80);
    final frozen = (await db.query('Seasons')).single['recapJson'];
    await db.update('ManagerFixtures', {'playerTeamScore': 0});
    final again = await service.close(person, season);
    expect(again.analytics.goalsFor, 9);
    expect((await db.query('Seasons')).single['recapJson'], frozen);
    expect(await db.query('Trophies'), hasLength(1));
    expect(await db.query('TournamentResult'), hasLength(1));
  });
  test('Explicit refresh incorporates corrected matches', () async {
    await matches();
    await service.close(person, season);
    await db.update(
      'ManagerFixtures',
      {'playerTeamScore': 1},
      where: 'id = ?',
      whereArgs: ['f0'],
    );
    final archived = await service.load(person, season);
    expect(archived.analytics.goalsFor, 9);
    final updated = await service.refresh(person, season);
    expect(updated.analytics.goalsFor, 7);
    expect(updated.season.isClosed, true);
    expect((await service.load(person, season)).analytics.goalsFor, 7);
  });
  test('Final tables preserve unknown stats as missing', () async {
    final review = await service.saveTable(person, season, table());
    expect(review.season.isClosed, false);
    final own = review.tables.single.rows.single;
    expect(own.stats['points'], 80);
    expect(own.stats['wins'], null);
    expect(own.balance, null);
    final row = (await db.query('TournamentResultTableItem')).single;
    expect(row['wins'], 0);
    expect(jsonDecode(row['knownStats'] as String), ['points']);
    expect(
      SeasonReview.decode(review.encode())
          .tables
          .single
          .rows
          .single
          .stats['wins'],
      null,
    );
  });
  test('Imported legacy tables keep their known zeroes', () async {
    final saved = await service.saveTable(person, season, table());
    await db.update('TournamentResultTableItem', {'knownStats': null});
    final loaded = await service.load(person, season, live: true);
    expect(saved.tables.single.rows.single.stats['wins'], null);
    expect(loaded.tables.single.rows.single.stats['wins'], 0);
  });
  test('Invalid table prevents all closure writes', () async {
    await matches();
    final invalid = table(
      rows: const [
        SeasonStanding(teamId: '40-13', name: 'São Paulo', position: 1),
        SeasonStanding(teamId: 'fla', name: 'Flamengo', position: 1),
      ],
    );
    await expectLater(
      service.close(person, season, tables: [invalid]),
      throwsFormatException,
    );
    expect((await db.query('Seasons')).single['closedAt'], null);
    expect(await db.query('TournamentResult'), isEmpty);
    expect(await db.query('Trophies'), isEmpty);
  });
  test('Database failure rolls back standings, trophies and closure', () async {
    await db.execute(
      "CREATE TRIGGER fail_archive BEFORE UPDATE OF recapJson ON Seasons BEGIN SELECT RAISE(ABORT, 'forced failure'); END",
    );
    await expectLater(
      service.close(person, season, tables: [table()]),
      throwsA(isA<DatabaseException>()),
    );
    expect((await db.query('Seasons')).single['closedAt'], null);
    expect(await db.query('TournamentResultTable'), isEmpty);
    expect(await db.query('TournamentResult'), isEmpty);
    expect(await db.query('Trophies'), isEmpty);
  });
  test('Career isolation protects read and closure', () async {
    final other = reviewPerson(id: 'other');
    await expectLater(service.close(other, season), throwsStateError);
    await expectLater(service.load(other, season), throwsStateError);
    expect((await db.query('Seasons')).single['closedAt'], null);
  });
  test(
    'Any previous season can be closed without touching the current one',
    () async {
      final old = reviewSeason(id: 'old', year: 2024);
      await db.insert('Seasons', old.toMap());
      await service.close(person, old);
      final all = (await db.query('Seasons')).map(Season.fromMap).toList();
      expect(all.singleWhere((s) => s.id == 'old').isClosed, true);
      expect(all.singleWhere((s) => s.id == season.id).isClosed, false);
    },
  );
  test(
    'Penalty final is a title while team match record stays a draw',
    () async {
      final f = reviewFixture(0, tournament: 'cup')
        ..addAll({
          'stage': 'Final',
          'playerTeamScore': 1,
          'oppositeTeamScore': 1,
          'playerTeamPenaltiesScore': 5,
          'oppositeTeamPenaltiesScore': 4,
        });
      await db.insert('ManagerFixtures', f);
      final r = await service.close(person, season);
      expect(r.titles, 1);
      expect(r.analytics.draws, 1);
      expect(r.competitions.single['result'], 'Campeão');
      expect(await db.query('Trophies'), hasLength(1));
    },
  );
  test('Manual cup result is preserved by closure', () async {
    await db.insert(
      'ManagerFixtures',
      reviewFixture(0, tournament: 'cup')..['stage'] = 'Final',
    );
    await db.insert(
      'TournamentResult',
      const TournamentResult(
        id: 'manual',
        seasonId: 's2026',
        fifaVersion: 'FC26',
        tournamentId: 'cup',
        result: 'Vice-campeão',
        personId: 'career',
        isWinner: false,
      ).toMap(),
    );
    final r = await service.close(person, season);
    expect(r.titles, 0);
    expect(r.competitions.single['result'], 'Vice-campeão');
    expect(await db.query('Trophies'), isEmpty);
  });
  test(
    'Table corrections update the archive and remove generated title',
    () async {
      await service.close(person, season, tables: [table()]);
      final r = await service.saveTable(person, season, table(position: 2));
      expect(r.titles, 0);
      expect(r.season.isClosed, true);
      expect(await db.query('Trophies'), isEmpty);
      expect(
        (await service.load(person, season)).tables.single.rows.single.position,
        2,
      );
    },
  );
  test('Player career averages exclude missing ratings', () async {
    final player = reviewPerson(category: PersonCategory.player);
    for (var i = 0; i < 2; i++) {
      final f = reviewFixture(i)
        ..remove('teamPossession')
        ..remove('passAccuracy');
      f.addAll({
        'goalsCount': i + 1,
        'assistsCount': 1,
        'savesCount': 0,
        'yellowCards': 0,
        'redCards': 0,
        'isInjured': 0,
        'rating': i == 0 ? 8.0 : null,
        'minsPlayed': 90,
      });
      await db.insert('PlayerFixtures', f);
    }
    final r = await service.close(player, season);
    expect(r.players.single['goals'], 3);
    expect(r.players.single['rating'], 8.0);
    expect(r.players.single['ratings'], 1);
    expect(r.players.single['minutes'], 180);
  });
  test('Managers aggregate latest performance per player and game', () async {
    await matches();
    for (var i = 0; i < 2; i++) {
      await db.insert('ManagerFixturePlayerPerformances', {
        'id': 'p$i',
        'personId': 'career',
        'fixtureId': 'f0',
        'playerInstanceId': 'lucas',
        'goalsCount': i + 1,
        'assistsCount': 0,
        'avgRating': i == 1 ? 8.0 : null,
      });
    }
    final r = await service.close(person, season);
    expect(r.players.single['matches'], 1);
    expect(r.players.single['goals'], 2);
    expect(r.players.single['rating'], 8.0);
  });
  test(
    'Backup round trip retains closure, snapshot and optional table data',
    () async {
      await matches();
      await service.close(person, season, tables: [table()]);
      final names = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      )).map((r) => r['name'] as String).toList();
      final data = <List<Map<String, Object?>>>[];
      for (final name in names) {
        data.add(await db.query(name));
      }
      final payload = jsonEncode([
        names,
        data,
        25,
        {'app': BackupService.appMarker},
      ]);
      final restored = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        await restored.execute('CREATE TABLE Settings(activePersonId TEXT)');
        await SqlService.ensureCompatibleSchema(restored);
        await SqlService.ensureSeasonClosureSchema(restored);
        final report = await BackupService(
          database: () => Future.value(restored),
        ).restoreJsonBackup(payload);
        expect(report.skippedRows, 0);
        final r = await SeasonClosureService(
          database: () => Future.value(restored),
          labels: labels,
        ).load(person, season);
        expect(r.season.isClosed, true);
        expect(r.analytics.played, 3);
        expect(r.tables.single.rows.single.stats['wins'], null);
      } finally {
        await restored.close();
      }
    },
  );
  test('Empty season closes without creating fictional results', () async {
    final r = await service.close(person, season);
    expect(r.analytics.played, 0);
    expect(r.titles, 0);
    expect(r.players, isEmpty);
    expect(await db.query('TournamentResult'), isEmpty);
    expect(await db.query('Trophies'), isEmpty);
  });
  test('Final rank correction removes old automatic title', () async {
    await db.insert('Trophies', {
      'id': 'auto:s2026:league:1014',
      'personId': 'career',
      'seasonId': 's2026',
      'teamId': '40-13',
      'isNational': 0,
      'awardId': '-1',
      'count': 1,
      'description': 'Brasileirão',
    });
    await service.saveTable(person, season, table(position: 2));
    expect(await db.query('Trophies'), isEmpty);
  });
  test('Editing an imported table keeps result awards and relinks automatic tables', () async {
    await service.saveTable(person, season, table());
    final saved = (await db.query('TournamentResult')).single;
    await db.update('TournamentResult', {
      'id': 'auto:s2026:league:1014',
      'playerOfTheTournamentId': 'lucas',
    });
    await db.update('TournamentResultTable', {
      'tournamentResultId': 'auto:s2026:league:1014',
    });
    final imported = await service.load(person, season, live: true);
    final current = imported.tables.single;
    final corrected = SeasonFinalTable(
      id: current.id,
      tournamentId: current.tournamentId,
      name: current.name,
      rows: current.rows,
    );
    await service.saveTable(person, season, corrected);
    final parent = (await db.query('TournamentResultTable')).single;
    expect(parent['id'], current.id);
    expect(parent['tournamentResultId'], saved['id']);
    expect(
      (await db.query(
        'TournamentResult',
        where: 'id = ?',
        whereArgs: [saved['id']],
      )).single['playerOfTheTournamentId'],
      'lucas',
    );
    expect(await db.query('TournamentResultTableItem'), hasLength(1));
  });
}
