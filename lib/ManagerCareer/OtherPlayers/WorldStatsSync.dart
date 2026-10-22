import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../FcScore/FcScoreApi.dart';
import '../../FcScore/FcScoreModels.dart';
import '../../FcScore/FcScoreRepository.dart';
import '../../models/Person.dart';
import '../../utils/SqlService.dart';
import 'OtherPlayersData.dart';

class WorldStatsNotLinked extends FcScoreException {
  const WorldStatsNotLinked(super.message);
}

class WorldStatsResult {
  const WorldStatsResult({
    required this.date,
    required this.seasonId,
    required this.lines,
  });
  final DateTime date;
  final String? seasonId;
  final List<CompetitionLine> lines;
}

class _WorldSession {
  _WorldSession(this.api, this.saveId, this.date, this.seasonId);
  final FcScoreApi api;
  final String saveId;
  final DateTime date;
  final String? seasonId;
  final DateTime openedAt = DateTime.now();
}

class WorldStatsSync {
  WorldStatsSync({SqlService? sql, this.apiFactory})
    : sql = sql ?? SqlService.instance;
  final SqlService sql;
  final FcScoreApi Function(Uri address)? apiFactory;

  static final _sessions = <String, Future<_WorldSession>>{};

  static void forget(String personId) => _sessions.remove(personId);

  Future<_WorldSession> _session(Person person) async {
    final cached = _sessions[person.id];
    if (cached != null) {
      try {
        final session = await cached;
        if (DateTime.now().difference(session.openedAt) <
            const Duration(minutes: 5)) {
          return session;
        }
      } catch (_) {}
    }
    final opening = _open(person);
    _sessions[person.id] = opening;
    try {
      return await opening;
    } catch (_) {
      _sessions.remove(person.id);
      rethrow;
    }
  }

  Future<_WorldSession> _open(Person person) async {
    final repo = FcScoreRepository(sql: sql);
    final link = await repo.linkFor(person.id);
    if (link == null) {
      throw const WorldStatsNotLinked(
        'Ligue esta carreira ao FC Score para buscar os números da temporada.',
      );
    }
    final address =
        link.connectionAddress ?? (await repo.recentAddresses()).firstOrNull;
    if (address == null) {
      throw const WorldStatsNotLinked(
        'Conecte o FC Score ao PC para buscar os números da temporada.',
      );
    }
    final uri = fcScoreAddress(address);
    final api =
        apiFactory?.call(uri) ??
        FcScoreApi(uri, timeout: const Duration(seconds: 12));
    final meta = await api.connect();
    if (fcVersion(fcId(meta['gameVersion'])) != link.gameVersion) {
      throw const FcScoreException(
        'O PC está com outra versão do jogo aberta.',
      );
    }
    final save = repo.currentSave(await api.list('careers'), link, person);
    if (save == null) {
      throw const FcScoreException(
        'O save desta carreira não foi encontrado no PC.',
      );
    }
    final saveId = fcId(save['id']);
    final overview = await api.object(api.careerPath(saveId));
    final date = DateTime.tryParse(fcId(overview['currentDate']));
    if (date == null) {
      throw const FcScoreException('A API não informou a data do save.');
    }
    final seasons = await sql.getSeasons(person.id);
    final season = seasons
        .where((s) => !date.isBefore(s.startDate) && !date.isAfter(s.endDate))
        .firstOrNull;
    return _WorldSession(api, saveId, date, season?.id);
  }

  Future<String?> _remotePlayerId(
    Database db,
    Person person,
    String playerId,
  ) async {
    final world = await db.rawQuery(
      '''SELECT w.remotePlayerId FROM FcScoreWorldPlayer w
      JOIN Seasons s ON s.id = w.seasonId AND s.personId = w.personId
      WHERE w.personId = ? AND w.playerId = ?
      ORDER BY s.startDate DESC LIMIT 1''',
      [person.id, playerId],
    );
    if (world.isNotEmpty) return fcId(world.first['remotePlayerId']);
    final player = await db.query(
      'CustomCreatedPlayer',
      columns: ['realPlayerId'],
      where: 'personId = ? AND id = ?',
      whereArgs: [person.id, playerId],
      limit: 1,
    );
    final real = fcId(player.firstOrNull?['realPlayerId']);
    return real.isEmpty ? null : real;
  }

  Future<WorldStatsResult?> refreshPlayer(
    Person person, {
    String? playerId,
    String? remotePlayerId,
  }) async {
    final db = await sql.database;
    await WorldPlayers.ensureSchema(db);
    final remote =
        remotePlayerId ??
        (playerId == null || playerId.isEmpty
            ? null
            : await _remotePlayerId(db, person, playerId));
    if (remote == null || remote.isEmpty) return null;
    final session = await _session(person);
    final FcJson profile;
    try {
      profile = await session.api.object(
        session.api.careerPath(session.saveId, 'players/$remote'),
      );
    } on FcScoreException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
    final stats = fcObject(profile['seasonStats']);
    if (stats['competitions'] is! List) return null;
    final day = session.date.toIso8601String().substring(0, 10);
    if (playerId != null && playerId.isNotEmpty && session.seasonId != null) {
      await db.insert('WorldPlayerSeason', {
        'personId': person.id,
        'playerId': playerId,
        'seasonId': session.seasonId,
        'statsJson': jsonEncode(stats),
        'statsDate': day,
        'updatedAt': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return WorldStatsResult(
      date: session.date,
      seasonId: session.seasonId,
      lines: await OtherPlayersRepository(sql: sql)
          .apiLines(person, session.seasonId, stats, session.date),
    );
  }

  Future<int> refreshTeam(Person person, String teamId) async {
    final db = await sql.database;
    final session = await _session(person);
    if (session.seasonId == null) return 0;
    final team = await db.query(
      'FcScoreWorldTeam',
      columns: ['remoteId'],
      where: 'personId = ? AND seasonId = ? AND teamId = ?',
      whereArgs: [person.id, session.seasonId, teamId],
      limit: 1,
    );
    if (team.isEmpty) return 0;
    final remoteTeam = fcId(team.first['remoteId']);
    final data = await session.api.object(
      'saves/${Uri.encodeComponent(session.saveId)}/teams/$remoteTeam',
    );
    final day = session.date.toIso8601String().substring(0, 10);
    var updated = 0;
    await db.transaction((txn) async {
      for (final entry in fcList(data['roster'])) {
        if (entry['seasonStats'] is! Map) continue;
        updated += await txn.update(
          'FcScoreWorldPlayer',
          {
            'rawJson': jsonEncode({...entry, 'statsDate': day}),
          },
          where: 'personId = ? AND seasonId = ? AND remoteTeamId = ? AND remotePlayerId = ?',
          whereArgs: [
            person.id,
            session.seasonId,
            remoteTeam,
            fcId(entry['id']),
          ],
        );
      }
    });
    return updated;
  }
}
