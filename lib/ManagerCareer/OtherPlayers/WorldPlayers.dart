import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../models/TeamTransferItem.dart';

abstract final class WorldPlayers {
  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS WorldPlayer(
      personId TEXT NOT NULL, playerId TEXT NOT NULL, teamId TEXT,
      leagueId TEXT, shirtNumber INTEGER, since TEXT, source TEXT NOT NULL,
      hidden INTEGER NOT NULL DEFAULT 0, updatedAt TEXT NOT NULL,
      PRIMARY KEY(personId, playerId))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS WorldTransfer(
      id TEXT PRIMARY KEY, personId TEXT NOT NULL, playerId TEXT NOT NULL,
      date TEXT NOT NULL, fromTeamId TEXT, fromLeagueId TEXT, toTeamId TEXT,
      toLeagueId TEXT, type TEXT NOT NULL, value INTEGER, source TEXT NOT NULL,
      createdAt TEXT NOT NULL)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS WorldTransferByPlayer ON WorldTransfer(personId, playerId)',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS WorldPlayerStats(
      id TEXT PRIMARY KEY, personId TEXT NOT NULL, playerId TEXT NOT NULL,
      seasonId TEXT NOT NULL, competition TEXT NOT NULL, tournamentId TEXT,
      name TEXT, teamId TEXT, leagueId TEXT, appearances INTEGER,
      goals INTEGER, assists INTEGER, minutes INTEGER, averageRating REAL,
      yellowCards INTEGER, redCards INTEGER, cleanSheets INTEGER,
      updatedAt TEXT NOT NULL)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS WorldPlayerStatsByPlayer ON WorldPlayerStats(personId, playerId)',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS WorldPlayerSeason(
      personId TEXT NOT NULL, playerId TEXT NOT NULL, seasonId TEXT NOT NULL,
      statsJson TEXT NOT NULL, statsDate TEXT NOT NULL, updatedAt TEXT NOT NULL,
      PRIMARY KEY(personId, playerId, seasonId))''');
  }

  static Future<void> backfill(
    DatabaseExecutor db,
    String personId,
    String ownTeamId,
  ) async {
    await ensureSchema(db);
    final done = await db.query(
      'WorldPlayer',
      columns: ['playerId'],
      where: "personId = ? AND source = 'api'",
      whereArgs: [personId],
      limit: 1,
    );
    if (done.isNotEmpty) return;
    final latest = <String, Map<String, Object?>>{};
    for (var offset = 0; ; offset += 256) {
      final rows = await db.rawQuery(
        '''
        SELECT p.playerId, p.rawJson, t.teamId, t.leagueId, s.startDate,
          (SELECT MAX(c.currentDate) FROM FcScoreCompetition c
            WHERE c.personId = p.personId AND c.seasonId = p.seasonId) AS since
        FROM FcScoreWorldPlayer p
        JOIN FcScoreWorldTeam t ON t.personId = p.personId
          AND t.seasonId = p.seasonId AND t.remoteId = p.remoteTeamId
        JOIN Seasons s ON s.id = p.seasonId AND s.personId = p.personId
        WHERE p.personId = ? AND p.playerId != ''
        ORDER BY s.startDate, p.rowid LIMIT 256 OFFSET ?''',
        [personId, offset],
      );
      for (final row in rows) {
        final raw = jsonDecode('${row['rawJson']}');
        latest['${row['playerId']}'] = {
          'teamId': row['teamId'],
          'leagueId': row['leagueId'],
          'since': row['since'] ?? row['startDate'],
          'shirtNumber': raw is Map ? raw['jerseyNumber'] : null,
        };
      }
      if (rows.length < 256) break;
    }
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final MapEntry(key: playerId, value: row) in latest.entries) {
      if (row['teamId'] == ownTeamId) continue;
      batch.insert('WorldPlayer', {
        'personId': personId,
        'playerId': playerId,
        'teamId': row['teamId'],
        'leagueId': row['leagueId'],
        'shirtNumber': row['shirtNumber'] is num
            ? (row['shirtNumber'] as num).toInt()
            : null,
        'since': row['since'],
        'source': 'api',
        'hidden': 0,
        'updatedAt': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }
}

class WorldRosterRecorder {
  WorldRosterRecorder._(
    this._tx,
    this._personId,
    this._ownTeamId,
    this._known,
    this._formerOwn,
    this._registered,
  );
  final DatabaseExecutor _tx;
  final String _personId, _ownTeamId;
  final Map<String, Map<String, Object?>> _known;
  final Set<String> _formerOwn;

  final Map<String, Map<String, Object?>> _registered;

  static Future<WorldRosterRecorder> start(
    DatabaseExecutor tx, {
    required String personId,
    required String ownTeamId,
  }) async {
    await WorldPlayers.backfill(tx, personId, ownTeamId);
    final moves = <String, Map<String, Object?>>{};
    final transfers = await tx.query(
      'TeamTransferItem',
      where: 'personId = ?',
      whereArgs: [personId],
    );
    transfers.sort(
      (a, b) => (teamTransferEffectiveDate(a) ?? DateTime(0)).compareTo(
        teamTransferEffectiveDate(b) ?? DateTime(0),
      ),
    );
    for (final row in transfers) {
      moves['${row['playerInstanceId']}'] = row;
    }
    return WorldRosterRecorder._(
      tx,
      personId,
      ownTeamId,
      {
        for (final row in await tx.query(
          'WorldPlayer',
          where: 'personId = ?',
          whereArgs: [personId],
        ))
          '${row['playerId']}': row,
      },
      {
        for (final row in await tx.rawQuery(
          'SELECT DISTINCT playerId FROM TeamPlayer WHERE personId = ? AND playerId IS NOT NULL',
          [personId],
        ))
          '${row['playerId']}',
      },
      moves,
    );
  }

  Future<void> _transfer(
    String playerId,
    String? from,
    String? fromLeague,
    String to,
    String? toLeague,
    DateTime date,
  ) => _tx.insert('WorldTransfer', {
    'id': const Uuid().v4(),
    'personId': _personId,
    'playerId': playerId,
    'date': date.toIso8601String(),
    'fromTeamId': from,
    'fromLeagueId': fromLeague,
    'toTeamId': to,
    'toLeagueId': toLeague,
    'type': from == null ? 'free' : 'transfer',
    'value': null,
    'source': 'api',
    'createdAt': DateTime.now().toIso8601String(),
  });

  Future<void> record({
    required String playerId,
    required String teamId,
    String? leagueId,
    required DateTime date,
    int? shirtNumber,
  }) async {
    if (playerId.isEmpty || teamId.isEmpty) return;
    final old = _known[playerId];
    final since = DateTime.tryParse('${old?['since'] ?? ''}');
    if (old != null && old['source'] == 'manual' && since != null) {
      if (since.isAfter(date)) return;
    }
    final now = DateTime.now().toIso8601String();
    final registered = _registered[playerId];
    if (teamId == _ownTeamId) {
      final from = old?['teamId'] as String?;
      if (from != null &&
          from != teamId &&
          registered?['toTeamId'] != _ownTeamId) {
        await _transfer(
          playerId,
          from,
          old?['leagueId'] as String?,
          teamId,
          leagueId,
          date,
        );
      }
      if (old != null) {
        await _tx.delete(
          'WorldPlayer',
          where: 'personId = ? AND playerId = ?',
          whereArgs: [_personId, playerId],
        );
        _known.remove(playerId);
      }
      return;
    }
    if (old == null) {
      final from =
          registered?['toTeamId'] as String? ??
          (_formerOwn.contains(playerId) ? _ownTeamId : null);
      if (from != null && from != teamId) {
        await _transfer(
          playerId,
          from,
          registered?['toLeagueId'] as String?,
          teamId,
          leagueId,
          date,
        );
      }
      final row = {
        'personId': _personId,
        'playerId': playerId,
        'teamId': teamId,
        'leagueId': leagueId,
        'shirtNumber': shirtNumber,
        'since': date.toIso8601String(),
        'source': 'api',
        'hidden': 0,
        'updatedAt': now,
      };
      await _tx.insert(
        'WorldPlayer',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _known[playerId] = row;
      return;
    }
    final changed = old['teamId'] != teamId;
    if (changed && old['hidden'] != 1) {
      await _transfer(
        playerId,
        old['teamId'] as String?,
        old['leagueId'] as String?,
        teamId,
        leagueId,
        date,
      );
    }
    final row = {
      ...old,
      'teamId': teamId,
      'leagueId': leagueId,
      'shirtNumber': shirtNumber ?? old['shirtNumber'],
      if (changed) 'since': date.toIso8601String(),
      if (changed) 'source': 'api',
      'updatedAt': now,
    };
    await _tx.update(
      'WorldPlayer',
      row,
      where: 'personId = ? AND playerId = ?',
      whereArgs: [_personId, playerId],
    );
    _known[playerId] = row;
  }
}
