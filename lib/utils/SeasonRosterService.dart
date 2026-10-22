import 'dart:math' show min;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/Season.dart';
import '../models/TeamTransferItem.dart';
import 'PlayerValueHistory.dart';
import 'SquadLineup.dart';

class SeasonRosterService {
  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS SeasonRosterInitialization(
      personId TEXT NOT NULL, seasonId TEXT NOT NULL, sourceSeasonId TEXT,
      teamId TEXT NOT NULL, createdAt TEXT NOT NULL,
      valueRevision INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(personId, seasonId))''');
    final columns = await db.rawQuery(
      'PRAGMA table_info(SeasonRosterInitialization)',
    );
    if (!columns.any((c) => c['name'] == 'valueRevision')) {
      await db.execute(
        'ALTER TABLE SeasonRosterInitialization ADD COLUMN valueRevision INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  static Future<Map<String, Map<String, Object?>>> _startingValues(
    DatabaseExecutor db,
    Season season,
    Map<String, Object?> previous,
    List<Map<String, Object?>> source,
  ) async {
    final values = <String, Map<String, Object?>>{};
    final ids = {
      for (final row in source)
        if (row['playerId'] is String) row['playerId'] as String,
    }.toList();
    if (ids.isEmpty) return values;
    for (final table in ['Overall', 'MarketValue']) {
      final field = table == 'Overall' ? 'overall' : 'value';
      final target = table == 'Overall' ? 'overall' : 'marketValue';
      final records = <Map<String, Object?>>[];
      for (var i = 0; i < ids.length; i += 400) {
        final batch = ids.sublist(i, min(i + 400, ids.length));
        records.addAll(
          await db.query(
            table,
            where:
                'personId = ? AND customPlayerId IN (${List.filled(batch.length, '?').join(',')}) AND julianday(date) <= julianday(?)',
            whereArgs: [
              season.personId,
              ...batch,
              season.startDate.toIso8601String(),
            ],
            orderBy:
                'julianday(date) DESC, julianday(createdAt) DESC, rowid DESC',
          ),
        );
      }
      final timeline = PlayerValueHistory.latest(records, [
        for (final row in source)
          {
            ...row,
            'seasonStartDate': previous['startDate'],
            'seasonCreatedAt': previous['createdAt'],
          },
      ], table);
      for (final row in timeline.values) {
        final id = row['customPlayerId'];
        if (id is String && row[field] is num) {
          (values[id] ??= {}).putIfAbsent(target, () => row[field]);
        }
      }
    }
    return values;
  }

  static Future<void> _repairValues(
    DatabaseExecutor db,
    Season season,
    Map<String, Object?> marker,
  ) async {
    if (marker['valueRevision'] == 1 || marker['sourceSeasonId'] == null) {
      return;
    }
    if (!season.isClosed) {
      final newer = await db.query(
        'Seasons',
        where: 'personId = ? AND julianday(startDate) > julianday(?)',
        whereArgs: [season.personId, season.startDate.toIso8601String()],
        limit: 1,
      );
      final previous = (await db.query(
        'Seasons',
        where: 'id = ? AND personId = ?',
        whereArgs: [marker['sourceSeasonId'], season.personId],
      )).firstOrNull;
      if (newer.isEmpty && previous != null) {
        final source = await db.query(
          'TeamPlayer',
          where: 'personId = ? AND seasonId = ?',
          whereArgs: [season.personId, previous['id']],
        );
        final values = await _startingValues(db, season, previous, source);
        final byId = {for (final row in source) row['playerId']: row};
        for (final row in await db.query(
          'TeamPlayer',
          where: 'personId = ? AND seasonId = ?',
          whereArgs: [season.personId, season.id],
        )) {
          final old = byId[row['playerId']], latest = values[row['playerId']];
          if (old == null || latest == null) continue;
          final changes = <String, Object?>{
            for (final field in ['overall', 'marketValue'])
              if (row[field] == old[field] &&
                  latest[field] != null &&
                  latest[field] != row[field])
                field: latest[field],
          };
          if (changes.isNotEmpty) {
            await db.update(
              'TeamPlayer',
              changes,
              where: 'id = ? AND personId = ?',
              whereArgs: [row['id'], season.personId],
            );
          }
        }
      }
    }
    await db.update(
      'SeasonRosterInitialization',
      {'valueRevision': 1},
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [season.personId, season.id],
    );
  }

  static Future<void> repairPendingValues(
    DatabaseExecutor db, {
    String? personId,
  }) async {
    await ensureSchema(db);
    final pending = await db.rawQuery(
      '''SELECT s.*, r.sourceSeasonId, r.valueRevision
      FROM Seasons s JOIN SeasonRosterInitialization r ON r.personId = s.personId AND r.seasonId = s.id
      WHERE r.valueRevision = 0 AND r.sourceSeasonId IS NOT NULL
      ${personId == null ? '' : 'AND r.personId = ?'}''',
      personId == null ? [] : [personId],
    );
    for (final row in pending) {
      await _repairValues(db, Season.fromMap(row), row);
    }
  }

  static Future<int> initialize(DatabaseExecutor db, Season season) async {
    await ensureSchema(db);
    final marker = (await db.query(
      'SeasonRosterInitialization',
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [season.personId, season.id],
    )).firstOrNull;
    if (marker != null) {
      await _repairValues(db, season, marker);
      return 0;
    }
    final person = (await db.query(
      'Persons',
      where: 'id = ?',
      whereArgs: [season.personId],
    )).firstOrNull;
    if (person == null || person['category'] != 'manager') return 0;
    final teamId = '${person['teamId']}';
    final current = await db.query(
      'TeamPlayer',
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [season.personId, season.id],
    );
    final departures = await db.query(
      'TeamPlayerDeparture',
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [season.personId, season.id],
      limit: 1,
    );
    final newer = await db.query(
      'Seasons',
      where: 'personId = ? AND julianday(startDate) > julianday(?)',
      whereArgs: [season.personId, season.startDate.toIso8601String()],
      limit: 1,
    );
    final canCarry =
        current.isEmpty &&
        departures.isEmpty &&
        newer.isEmpty &&
        !season.isClosed;
    final previous = canCarry
        ? (await db.query(
            'Seasons',
            where: 'personId = ? AND julianday(startDate) < julianday(?)',
            whereArgs: [season.personId, season.startDate.toIso8601String()],
            orderBy: 'julianday(startDate) DESC',
            limit: 1,
          )).firstOrNull
        : null;
    var added = 0;
    if (previous != null) {
      final oldClub = (await db.query(
        'ManagerFixtures',
        columns: ['playerTeamId'],
        where: 'personId = ? AND seasonId = ?',
        whereArgs: [season.personId, previous['id']],
        orderBy: 'julianday(date) DESC',
        limit: 1,
      )).firstOrNull?['playerTeamId'];
      final move = (await db.query(
        'ManagerCareerHistoryItem',
        where: 'personId = ? AND julianday(date) <= julianday(?)',
        whereArgs: [season.personId, season.startDate.toIso8601String()],
        orderBy: 'julianday(date) DESC',
        limit: 1,
      )).firstOrNull;
      final changedClub =
          move != null &&
          move['fromTeamId'] != null &&
          move['fromTeamId'] != move['toTeamId'] &&
          DateTime.tryParse('${move['date']}')
                  ?.isBefore(DateTime.parse('${previous['endDate']}')) ==
              false;
      if ((oldClub == null || oldClub == teamId) && !changedClub) {
        final formation = await SquadLineup.ensure(
          db,
          season.personId,
          previous['id'] as String,
          materialize: false,
        );
        final source = await db.query(
          'TeamPlayer',
          where: 'personId = ? AND seasonId = ?',
          whereArgs: [season.personId, previous['id']],
          orderBy: 'isBench, rowid',
        );
        final startingValues = await _startingValues(
          db,
          season,
          previous,
          source,
        );
        final movements = await db.query(
          'TeamTransferItem',
          where: 'personId = ? AND date(COALESCE(actualReleaseDate, releaseDate, date)) <= date(?)',
          whereArgs: [season.personId, season.startDate.toIso8601String()],
          orderBy: 'julianday(COALESCE(actualReleaseDate, releaseDate, date)), rowid',
        );
        final lastMovement = <Object?, Map<String, Object?>>{};
        for (final movement in movements) {
          if (movement['fromTeamId'] == teamId ||
              movement['toTeamId'] == teamId) {
            lastMovement[movement['playerInstanceId']] = movement;
          }
        }
        final seen = <Object?>{};
        for (final row in source) {
          final id = row['playerId'];
          if (id == null || !seen.add(id)) continue;
          final movement = lastMovement[id];
          if (movement != null &&
              !isIncomingTeamTransfer(movement, teamId) &&
              transferTypeFromRow(movement) != TeamTransferType.outLoan &&
              movement['keepInSquad'] != 1 &&
              (movement['movementApplied'] == 0 ||
                  teamTransferEffectiveDate(
                        movement,
                      )?.isBefore(DateTime.parse('${previous['endDate']}')) ==
                      false)) {
            continue;
          }
          await db.insert('TeamPlayer', {
            ...row,
            ...?startingValues[id],
            'id': const Uuid().v4(),
            'seasonId': season.id,
          });
          added++;
        }
        if (added > 0) {
          await SquadLineup.save(db, season.personId, season.id, formation);
        }
      }
    }
    await db.insert('SeasonRosterInitialization', {
      'personId': season.personId,
      'seasonId': season.id,
      'sourceSeasonId': previous?['id'],
      'teamId': teamId,
      'createdAt': DateTime.now().toIso8601String(),
      'valueRevision': 1,
    });
    return added;
  }
}
