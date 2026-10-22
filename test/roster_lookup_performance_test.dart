import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/FcScore/FcScoreRepository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

class _MeasuredDatabase implements Database {
  _MeasuredDatabase(this.inner);
  final Database inner;
  int overallRows = 0, seasonRows = 0, departureRows = 0;
  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => inner.transaction(action, exclusive: exclusive);

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final rows = await inner.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    if (table == 'Overall') overallRows += rows.length;
    return rows;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    final rows = await inner.rawQuery(sql, arguments);
    if (sql.contains('FROM Overall h')) overallRows += rows.length;
    if (sql.contains('FROM TeamPlayer tp JOIN Seasons')) {
      seasonRows += rows.length;
    }
    if (sql.contains('FROM TeamPlayerDeparture d')) {
      departureRows += rows.length;
    }
    return rows;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  late Database db;
  setUp(() async {
    db = await SqlService.openCareerDatabase(inMemoryDatabasePath);
    await db.insert('Persons', reviewPerson().toMap());
    for (final year in [2025, 2026]) {
      await db.insert(
        'Seasons',
        reviewSeason(id: 's$year', year: year).toMap(),
      );
    }
    await db.insert('SeasonRosterInitialization', {
      'personId': 'career',
      'seasonId': 's2026',
      'teamId': '40-13',
      'createdAt': '2026-01-01',
      'valueRevision': 1,
    });
  });
  tearDown(() => db.close());

  test('Large saved team payloads keep the event loop alive and list reads preserve the roster', () async {
    final raw = jsonEncode({
      'name': 'Clube',
      'roster': [
        for (var i = 0; i < 4000; i++)
          {'id': i, 'name': 'Jogador $i', 'overall': 70},
        'invalid profile',
      ],
    });
    await db.insert('FcScoreWorldTeam', {
      'personId': 'career',
      'seasonId': 's2026',
      'remoteId': 'club',
      'teamId': '40-13',
      'rawJson': raw,
    });
    final repo = FcScoreRepository(sql: SqlService.withDatabase(db));
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => ticks++,
    );
    final teams = await repo.careerTeams(
      'career',
      's2026',
      includeRosters: false,
    );
    timer.cancel();
    expect(ticks, greaterThan(0));
    expect(teams.single['rosterCount'], 4000);
    expect(teams.single.containsKey('rawJson'), isFalse);
    expect((teams.single['data'] as Map).containsKey('roster'), isFalse);
    final complete = await repo.careerTeams('career', 's2026');
    expect(((complete.single['data'] as Map)['roster'] as List).length, 4001);
    expect((await db.query('FcScoreWorldTeam')).single['rawJson'], raw);
    expect(await repo.careerTeams('other-career', 's2026'), isEmpty);
  });

  test('Global player loading materializes only latest dates, including submillisecond ties', () async {
    final batch = db.batch();
    for (var i = 0; i < 200; i++) {
      batch.insert('CustomCreatedPlayer', {
        'id': 'p$i',
        'personId': 'career',
        'name': 'Player $i',
        'positionId': '25',
        'overall': 60,
        'potential': 90,
        'realFace': 0,
        'foot': 'Right',
        'fromRealPlayer': 0,
      });
      for (var month = 1; month <= 24; month++) {
        batch.insert('Overall', {
          'id': '$i-$month',
          'personId': 'career',
          'customPlayerId': 'p$i',
          'date': DateTime(2025, month, 1).toIso8601String(),
          'createdAt': '2027-01-01',
          'overall': 60 + month,
        });
      }
    }
    await batch.commit(noResult: true);
    final measured = _MeasuredDatabase(db);
    final sql = SqlService.withDatabase(measured);
    final all = await sql.getCustomPlayers('career');
    expect(all.length, 200);
    expect(all.every((r) => r['overall'] == 84), isTrue);
    expect(measured.overallRows, 200);
    measured.overallRows = 0;
    final names = await sql.getCustomPlayers(
      'career',
      playerIds: {'p1', 'p2'},
      includeCurrentOverall: false,
    );
    expect(names.map((r) => r['id']).toSet(), {'p1', 'p2'});
    expect(measured.overallRows, 0);
    for (final (id, date, created, value) in [
      (
        'exact-new',
        '2028-01-01T12:00:00.000002Z',
        '2028-01-01T12:00:00.000002Z',
        88,
      ),
      (
        'exact-old',
        '2028-01-01T12:00:00.000001Z',
        '2028-01-01T12:00:00.000001Z',
        87,
      ),
    ]) {
      await db.insert('Overall', {
        'id': id,
        'personId': 'career',
        'customPlayerId': 'p1',
        'date': date,
        'createdAt': created,
        'overall': value,
      });
    }
    expect((await sql.getCustomPlayerById('career', 'p1'))!['overall'], 88);
    final local = DateTime(2029, 1, 1, 12);
    await db.insert('Overall', {
      'id': 'local-new',
      'personId': 'career',
      'customPlayerId': 'p1',
      'date': local.toIso8601String(),
      'overall': 90,
    });
    await db.insert('Overall', {
      'id': 'utc-old',
      'personId': 'career',
      'customPlayerId': 'p1',
      'date': local
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String(),
      'overall': 89,
    });
    expect((await sql.getCustomPlayerById('career', 'p1'))!['overall'], 90);
  });

  test(
    'Small squad reads only its own histories among thousands of imports',
    () async {
      final batch = db.batch();
      for (var i = 0; i < 4000; i++) {
        final id = i < 2 ? 'own$i' : 'other$i';
        batch.insert('Overall', {
          'id': id,
          'personId': 'career',
          'customPlayerId': id,
          'date': '2026-02-01',
          'createdAt': '2026-02-01',
          'overall': 80 + i % 5,
        });
        if (i >= 1000) continue;
        final roster = <String, Object?>{
          'id': 'past$id',
          'personId': 'career',
          'seasonId': 's2025',
          'playerId': id,
          'overall': 60,
          'isBench': 1,
        };
        batch.insert('TeamPlayer', roster);
        batch.insert('TeamPlayerDeparture', {
          'id': id,
          'rosterId': 'archived$id',
          'personId': 'career',
          'seasonId': 's2025',
          'playerId': id,
          'teamId': '40-13',
          'departureDate': '2025-11-01',
          'rosterJson': jsonEncode({...roster, 'id': 'archived$id'}),
        });
        if (i < 2) {
          batch.insert('CustomCreatedPlayer', {
            'id': id,
            'personId': 'career',
            'name': id,
            'positionId': '25',
            'overall': 70,
            'potential': 90,
            'realFace': 0,
            'foot': 'Right',
            'fromRealPlayer': 0,
          });
          batch.insert('TeamPlayer', {
            ...roster,
            'id': id,
            'seasonId': 's2026',
            'overall': 70,
          });
        }
      }
      await batch.commit(noResult: true);
      final measured = _MeasuredDatabase(db);
      final rows = await SqlService.withDatabase(measured)
          .getTeamPlayers('career', 's2026');
      expect(rows.map((r) => r['overall']), [80, 81]);
      expect(measured.overallRows, 2);
      expect(measured.seasonRows, 4);
      expect(measured.departureRows, 2);
    },
  );

  test(
    'Bulk statistics cross SQLite bind limits without losing player values',
    () async {
      final batch = db.batch();
      for (var i = 0; i < 1100; i++) {
        batch.insert('TeamPlayer', {
          'id': 'r$i',
          'playerId': 'p$i',
          'personId': 'career',
          'seasonId': 's2026',
          'isBench': 1,
          'overall': 70,
        });
        batch.insert('Overall', {
          'id': 'h$i',
          'customPlayerId': 'p$i',
          'personId': 'career',
          'date': '2026-02-01',
          'createdAt': '2026-02-01',
          'overall': 80 + i % 5,
        });
      }
      await batch.commit(noResult: true);
      final rows = await SqlService.withDatabase(db)
          .getManagerStatisticsRoster('career');
      expect(rows.length, 1100);
      for (final row in rows) {
        final i = int.parse((row['playerId'] as String).substring(1));
        expect(row['overall'], 80 + i % 5);
      }
    },
  );

  test('Upgrading an existing v41 career adds usable lookup indexes and retains data', () async {
    final directory = await Directory('build/test-databases')
        .create(recursive: true);
    final file = File(
      '${directory.absolute.path}/roster-index-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    Database? disk;
    try {
      disk = await SqlService.openCareerDatabase(file.path);
      await disk.insert('Persons', reviewPerson().toMap());
      for (final name in [
        'roster_overall_player',
        'roster_season_players',
        'roster_player_seasons',
        'roster_departed_player',
      ]) {
        await disk.execute('DROP INDEX $name');
      }
      await disk.setVersion(41);
      await disk.close();
      disk = await SqlService.openCareerDatabase(file.path);
      expect(await disk.getVersion(), 46);
      expect((await disk.query('Persons')).single['id'], 'career');
      for (final (table, column) in [
        ('Overall', 'customPlayerId'),
        ('TeamPlayer', 'playerId'),
        ('TeamPlayerDeparture', 'playerId'),
      ]) {
        final plan = await disk.rawQuery(
          'EXPLAIN QUERY PLAN SELECT * FROM $table WHERE personId = ? AND $column IN (?, ?)',
          ['career', 'a', 'b'],
        );
        expect(
          plan.map((r) => r['detail']).join(' '),
          contains('USING INDEX roster_'),
        );
      }
    } finally {
      await disk?.close();
      if (await file.exists()) await file.delete();
    }
  });
}
