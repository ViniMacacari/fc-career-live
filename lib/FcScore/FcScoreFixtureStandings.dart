part of 'FcScoreRepository.dart';

class FcStandingPositions {
  const FcStandingPositions({this.own, this.opponent});
  final int? own, opponent;
  bool get isEmpty => own == null && opponent == null;
}

DateTime? _standingDay(Object? value) {
  final date = value is DateTime ? value : DateTime.tryParse(fcId(value));
  return date == null ? null : DateTime(date.year, date.month, date.day);
}

String _sideId(FcJson fixture, String side) =>
    fcId(fcObject(fcObject(fixture[side])['team'])['id']);

FcStandingPositions fcStandingPositionsAt({
  required FcJson competition,
  required List<FcJson> fixtures,
  required String ownId,
  String? opponentId,
  DateTime? date,
  DateTime? snapshotDate,
  bool laterOwnMatch = false,
  int knownOwnMatches = 0,
  bool requireMatchDay = false,
}) {
  final tables = <({Set<String> stage, List<FcJson> rows})>[];
  for (final stage in fcList(competition['stages'])) {
    final name = fcName(stage['name'], fcId(stage['code']));
    for (final group in fcList(stage['groups'])) {
      final rows = fcList(group['rows']);
      if (rows.length > 2 &&
          rows.any((row) => fcId(fcObject(row['team'])['id']) == ownId)) {
        tables.add((
          stage: {
            fcNormalize(name),
            fcNormalize(fcStageLabel(name)),
            fcNormalize(fcId(stage['code'])),
          },
          rows: rows,
        ));
      }
    }
  }
  if (tables.isEmpty || ownId.isEmpty) return const FcStandingPositions();
  final day = _standingDay(date);
  bool played(FcJson fixture) =>
      (fixture['played'] == true || fixture['played'] == 1) &&
      fcInt(fcObject(fixture['home'])['goals']) != null &&
      fcInt(fcObject(fixture['away'])['goals']) != null;
  bool own(FcJson fixture) =>
      _sideId(fixture, 'home') == ownId || _sideId(fixture, 'away') == ownId;
  bool inStage(FcJson fixture, Set<String> stage) {
    final name = fcId(fixture['stage']);
    return stage.contains(fcNormalize(name)) ||
        stage.contains(fcNormalize(fcStageLabel(name)));
  }

  final matchDay = day == null
      ? null
      : fixtures
            .where(
              (fixture) =>
                  played(fixture) &&
                  own(fixture) &&
                  _standingDay(fixture['date']) == day,
            )
            .firstOrNull;
  final table =
      (matchDay == null
          ? null
          : tables.where((t) => inStage(matchDay, t.stage)).firstOrNull) ??
      tables
          .where((t) => t.rows.any((row) => (fcInt(row['played']) ?? 0) > 0))
          .lastOrNull ??
      tables.first;
  final teams = {
    for (final row in table.rows) fcId(fcObject(row['team'])['id']): row,
  };
  int? snapshot(String? id) {
    final position = fcInt(teams[id]?['position']);
    return position != null && position > 0 ? position : null;
  }

  final current = FcStandingPositions(
    own: snapshot(ownId),
    opponent: snapshot(opponentId),
  );
  if (day == null) return current;
  final games = fixtures
      .where(
        (fixture) =>
            played(fixture) &&
            teams.containsKey(_sideId(fixture, 'home')) &&
            teams.containsKey(_sideId(fixture, 'away')) &&
            (tables.length == 1 ||
                fcId(fixture['stage']).isEmpty ||
                inStage(fixture, table.stage)),
      )
      .toList();
  bool until(FcJson fixture) =>
      _standingDay(fixture['date'])?.isAfter(day) == false;
  final ownGames = games.where(own).toList();
  final ownUntil = ownGames.where(until).length;
  final later = laterOwnMatch || ownGames.any((fixture) => !until(fixture));
  final recorded = fcInt(teams[ownId]?['played']);
  final known = tables.length == 1 && knownOwnMatches > ownUntil
      ? knownOwnMatches
      : ownUntil;
  if (!later &&
      snapshotDate?.isBefore(day) != true &&
      (recorded == null || recorded >= known)) {
    return current;
  }
  if (ownUntil == 0 || (requireMatchDay && matchDay == null)) {
    return const FcStandingPositions();
  }
  final points = <String, int>{}, difference = <String, int>{};
  final scored = <String, int>{};
  for (final fixture in games.where(until)) {
    final home = _sideId(fixture, 'home'), away = _sideId(fixture, 'away');
    final homeGoals = fcInt(fcObject(fixture['home'])['goals'])!;
    final awayGoals = fcInt(fcObject(fixture['away'])['goals'])!;
    void add(String id, int goalsFor, int goalsAgainst) {
      points[id] =
          (points[id] ?? 0) +
          (goalsFor > goalsAgainst
              ? 3
              : goalsFor == goalsAgainst
              ? 1
              : 0);
      difference[id] = (difference[id] ?? 0) + goalsFor - goalsAgainst;
      scored[id] = (scored[id] ?? 0) + goalsFor;
    }

    add(home, homeGoals, awayGoals);
    add(away, awayGoals, homeGoals);
  }
  final order = teams.keys.toList()
    ..sort((a, b) {
      for (final stat in [points, difference, scored]) {
        final byStat = (stat[b] ?? 0).compareTo(stat[a] ?? 0);
        if (byStat != 0) return byStat;
      }
      return (snapshot(a) ?? 999).compareTo(snapshot(b) ?? 999);
    });
  int? computed(String? id) {
    final index = id == null ? -1 : order.indexOf(id);
    return index < 0 ? null : index + 1;
  }

  return FcStandingPositions(
    own: computed(ownId),
    opponent: computed(opponentId),
  );
}

class _StandingSource {
  _StandingSource(this.competition, this.snapshotDate, this.fixtures);
  final FcJson competition;
  final DateTime? snapshotDate;
  final List<FcJson> fixtures;
}

extension FcScoreFixtureStandings on FcScoreRepository {
  Future<_StandingSource?> _standingSource(
    Database db,
    String personId,
    String seasonId,
    String tournamentId,
  ) async {
    final rows = await db.query(
      'FcScoreCompetition',
      where: 'personId = ? AND seasonId = ? AND tournamentId = ?',
      whereArgs: [personId, seasonId, tournamentId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final fixtures = await db.query(
      'FcScoreWorldFixture',
      columns: ['rawJson'],
      where: 'personId = ? AND seasonId = ? AND competitionId = ?',
      whereArgs: [personId, seasonId, rows.single['remoteId']],
    );
    return _StandingSource(
      fcObject(jsonDecode(rows.single['rawJson'] as String)),
      _standingDay(rows.single['currentDate']),
      [
        for (final row in fixtures)
          fcObject(jsonDecode(row['rawJson'] as String)),
      ],
    );
  }

  Future<Map<String, String>> _remoteTeams(
    Database db,
    String personId,
    String seasonId,
  ) async {
    final link = await linkFor(personId);
    return {
      for (final entry in (link?.teams ?? const <String, String>{}).entries)
        entry.value: entry.key,
      for (final row in await db.query(
        'FcScoreWorldTeam',
        columns: ['remoteId', 'teamId'],
        where: 'personId = ? AND seasonId = ?',
        whereArgs: [personId, seasonId],
      ))
        fcId(row['teamId']): fcId(row['remoteId']),
    };
  }

  Future<FcStandingPositions> _positionsFor(
    Database db,
    Person person,
    _StandingSource source,
    Map<String, String> remote, {
    required String seasonId,
    required String tournamentId,
    required String ownTeamId,
    String? opponentTeamId,
    DateTime? date,
    bool requireMatchDay = false,
  }) async {
    final ownId = remote[ownTeamId];
    if (ownId == null) return const FcStandingPositions();
    final day = _standingDay(date);
    var later = false, known = 0;
    if (day != null) {
      for (final row in await db.query(
        person.category == PersonCategory.manager
            ? 'ManagerFixtures'
            : 'PlayerFixtures',
        columns: ['date'],
        where: 'personId = ? AND seasonId = ? AND tournamentId = ? AND playerTeamId = ?',
        whereArgs: [person.id, seasonId, tournamentId, ownTeamId],
      )) {
        final played = _standingDay(row['date']);
        if (played == null) continue;
        if (played.isAfter(day)) {
          later = true;
        } else {
          known++;
        }
      }
    }
    return fcStandingPositionsAt(
      competition: source.competition,
      fixtures: source.fixtures,
      ownId: ownId,
      opponentId: remote[opponentTeamId],
      date: day,
      snapshotDate: source.snapshotDate,
      laterOwnMatch: later,
      knownOwnMatches: known,
      requireMatchDay: requireMatchDay,
    );
  }

  Future<FcStandingPositions> fixtureStandingPositions(
    Person person, {
    required String seasonId,
    required String tournamentId,
    required String ownTeamId,
    String? opponentTeamId,
    DateTime? date,
  }) async {
    final db = await sql.database;
    final source = await _standingSource(db, person.id, seasonId, tournamentId);
    if (source == null) return const FcStandingPositions();
    return _positionsFor(
      db,
      person,
      source,
      await _remoteTeams(db, person.id, seasonId),
      seasonId: seasonId,
      tournamentId: tournamentId,
      ownTeamId: ownTeamId,
      opponentTeamId: opponentTeamId,
      date: date,
    );
  }

  Future<int> syncFixtureStandings(
    Person person, {
    Iterable<String>? fixtureIds,
  }) async {
    final db = await sql.database;
    final manager = person.category == PersonCategory.manager;
    final table = manager ? 'ManagerFixtures' : 'PlayerFixtures';
    final ids = fixtureIds?.toSet();
    final rows = await db.rawQuery(
      '''
      SELECT f.* FROM $table f
      WHERE f.personId = ? AND EXISTS (
        SELECT 1 FROM FcScoreImport i
        WHERE i.personId = f.personId AND i.fixtureId = f.id)
      ''',
      [person.id],
    );
    final sources = <String, _StandingSource?>{};
    final remotes = <String, Map<String, String>>{};
    var updated = 0;
    for (final row in rows) {
      if (ids != null && !ids.contains(row['id'])) continue;
      final stats = manager
          ? OpponentStats.decode(row['opponentStats'])
          : const OpponentStats();
      final needsOwn = (fcInt(row['position']) ?? 0) < 1;
      final needsOpponent =
          manager && row.containsKey('opponentStats') && stats.position == null;
      if (!needsOwn && !needsOpponent) continue;
      final seasonId = fcId(row['seasonId']);
      final tournamentId = fcId(row['tournamentId']);
      final key = '$seasonId\u0000$tournamentId';
      if (!sources.containsKey(key)) {
        sources[key] = await _standingSource(
          db,
          person.id,
          seasonId,
          tournamentId,
        );
      }
      final source = sources[key];
      if (source == null) continue;
      final positions = await _positionsFor(
        db,
        person,
        source,
        remotes[seasonId] ??= await _remoteTeams(db, person.id, seasonId),
        seasonId: seasonId,
        tournamentId: tournamentId,
        ownTeamId: fcId(row['playerTeamId']),
        opponentTeamId: fcId(row['oppositeTeamId']),
        date: DateTime.tryParse(fcId(row['date'])),
        requireMatchDay: true,
      );
      final values = <String, Object?>{
        if (needsOwn && positions.own != null) 'position': positions.own,
        if (needsOpponent && positions.opponent != null)
          'opponentStats': OpponentStats(
            passAccuracy: stats.passAccuracy,
            yellowCards: stats.yellowCards,
            redCards: stats.redCards,
            ownGoals: stats.ownGoals,
            missedPenalties: stats.missedPenalties,
            injuries: stats.injuries,
            position: positions.opponent,
          ).encode(),
      };
      if (values.isEmpty) continue;
      await db.update(
        table,
        values,
        where: 'id = ? AND personId = ?',
        whereArgs: [row['id'], person.id],
      );
      updated++;
    }
    return updated;
  }
}
