part of 'FcScoreRepository.dart';

class FcOpponentCompletion {
  FcOpponentCompletion(
    this.current,
    this.known,
    this.ids,
    this.missing, [
    this.rememberedFormation,
  ]);
  final OpponentLineup? current;
  final Map<String, Map<String, Object?>> known;
  final Map<String, String> ids;
  final List<FcJson> missing;
  final String? rememberedFormation;
}

Future<Map<String, Map<String, Object?>>> _careerPitchPlayers(
  DatabaseExecutor db,
  String personId,
  String version, {
  Set<String> playerIds = const {},
  Set<String> realIds = const {},
}) async {
  if (playerIds.isEmpty && realIds.isEmpty) return {};
  final conditions = [
    if (playerIds.isNotEmpty)
      'id IN (${List.filled(playerIds.length, '?').join(',')})',
    if (realIds.isNotEmpty)
      'realPlayerId IN (${List.filled(realIds.length, '?').join(',')})',
  ];
  final players = await db.query(
    'CustomCreatedPlayer',
    where: 'personId = ? AND (${conditions.join(' OR ')})',
    whereArgs: [personId, ...playerIds, ...realIds],
  );
  final real = await GamePlayers.lookup(version, [
    for (final p in players)
      if (!hasFootballIdentity(p) || p['positionId'] == null)
        fcId(p['realPlayerId']),
  ]);
  return {
    for (final p in players)
      fcId(p['id']): {
        ...p,
        'positionId':
            p['positionId'] ?? real[fcId(p['realPlayerId'])]?.mainPositionId,
        'name': hasFootballIdentity(p)
            ? p['name']
            : real[fcId(p['realPlayerId'])]?.name,
      },
  };
}

Future<FixtureFormation> _ownPitchFormation(
  DatabaseExecutor db,
  Map<String, Object?> fixture,
  List<FcJson> remote,
  Map<String, String> ids,
  String? explicit,
) async {
  final roster = await db.query(
    'TeamPlayer',
    where: 'personId = ? AND seasonId = ?',
    whereArgs: [fixture['personId'], fixture['seasonId']],
  );
  final known = await _careerPitchPlayers(
    db,
    fcId(fixture['personId']),
    fcId(fixture['fifaVersion']),
    playerIds: {for (final p in roster) fcId(p['playerId']), ...ids.values},
  );
  final reference = FixtureFormation.initial(
    roster: roster,
    names: {for (final p in known.entries) p.key: fcName(p.value['name'])},
    positions: {
      for (final p in known.entries) p.key: p.value['positionId'] as String?,
    },
    performances: [],
  );
  final hasSetup =
      roster
          .where((p) => p['isBench'] != 1 && p['x'] is int && p['y'] is int)
          .length ==
      11;
  final label = explicit ?? (hasSetup ? reference.formation : null);
  var result = _formation(
    remote,
    ids,
    label,
    known: known,
  ).copy(layoutSource: explicit == null ? 'api' : 'manual');
  if (hasSetup && result.formation == reference.formation) {
    result = result.withPreservedSlots(reference.starters);
  }
  return result;
}

bool _usesLegacyAutomaticPitch(FixtureFormation lineup) {
  final ids = lineup.starters.keys.toList()
    ..sort((a, b) {
      int priority(String id) {
        final value = getPositionPriority(
          lineup.players[id]?['positionId'] as String?,
        );
        return value < 0 ? 8 : value;
      }

      return priority(a).compareTo(priority(b));
    });
  final arranged = <String, FixturePitchSlot>{};
  final keeper = ids
      .where((id) => lineup.players[id]?['positionId'] == '0')
      .firstOrNull;
  if (keeper != null) {
    arranged[keeper] = (x: 0, y: lineup.shape.length - 1);
    ids.remove(keeper);
  }
  var index = 0;
  for (var y = 0; y < lineup.shape.length; y++) {
    for (var x = 0; x < lineup.shape[y]; x++) {
      if (keeper != null && y == lineup.shape.length - 1) continue;
      if (index < ids.length) {
        arranged[ids[index++]] = (x: x, y: y);
      }
    }
  }
  return arranged.length == lineup.starters.length &&
      arranged.entries.every((e) => lineup.starters[e.key] == e.value);
}

Future<FcOpponentCompletion> _opponentCompletion(
  DatabaseExecutor db,
  Map<String, Object?> fixture,
  List<FcJson> remote,
) async {
  final current = OpponentLineup.decode(fixture['opponentLineup']);
  String? rememberedFormation;
  final known = <String, Map<String, Object?>>{
    for (final e
        in current?.squad.players.entries ??
            <MapEntry<String, Map<String, Object?>>>[])
      e.key: Map<String, Object?>.of(e.value),
  };
  for (final row in await db.query(
    'ManagerFixtures',
    columns: ['opponentLineup'],
    where:
        'personId = ? AND fifaVersion = ? AND oppositeTeamId = ? '
        "AND COALESCE(oppositeTeamLeagueId, '') = ? AND id != ? AND julianday(date) <= julianday(?)",
    whereArgs: [
      fixture['personId'],
      fixture['fifaVersion'],
      fixture['oppositeTeamId'],
      fixture['oppositeTeamLeagueId'] ?? '',
      fixture['id'],
      fixture['date'],
    ],
    orderBy: 'julianday(date) DESC, rowid DESC',
  )) {
    final remembered = OpponentLineup.decode(row['opponentLineup']);
    if (remembered?.hasNames == true &&
        remembered!.squad.formation.isNotEmpty) {
      rememberedFormation ??= remembered.squad.formation;
    }
    for (final e
        in remembered?.squad.players.entries ??
            <MapEntry<String, Map<String, Object?>>>[]) {
      if (hasFootballIdentity(e.value)) {
        known.putIfAbsent(e.key, () => e.value);
      }
    }
  }
  final tables = (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  )).map((r) => r['name']).toSet();
  final registeredByRemote = <String, Map<String, Object?>>{};
  if (tables.contains('FcScoreWorldTeam') &&
      tables.contains('FcScoreWorldPlayer')) {
    for (final r in await db.rawQuery(
      '''SELECT w.*, p.name, p.positionId, p.realPlayerId, p.customAvatarFilePath
      FROM FcScoreWorldPlayer w JOIN FcScoreWorldTeam t ON t.personId = w.personId
        AND t.seasonId = w.seasonId AND t.remoteId = w.remoteTeamId
      LEFT JOIN CustomCreatedPlayer p ON p.id = w.playerId AND p.personId = w.personId
      WHERE t.personId = ? AND t.seasonId = ? AND t.teamId = ?''',
      [fixture['personId'], fixture['seasonId'], fixture['oppositeTeamId']],
    )) {
      final id = fcId(r['playerId']);
      if (id.isEmpty) continue;
      final raw = fcObject(jsonDecode(r['rawJson'] as String));
      final stored = known[id] ?? {};
      known[id] = {
        ...stored,
        'id': id,
        'name': hasFootballIdentity(stored)
            ? stored['name']
            : hasFootballIdentity({
                'name': r['name'],
                'apiPlayerId': r['remotePlayerId'],
              })
            ? r['name']
            : fcPlayerName(
                fcObject(raw['profile']).isEmpty
                    ? raw
                    : fcObject(raw['profile']),
              ),
        'apiPlayerId': r['remotePlayerId'],
        'positionId': canonicalPositionId(
          (current?.squad.layoutSource == 'manual'
                  ? stored['positionId'] as String?
                  : null) ??
              r['positionId'] as String? ??
              fcKnownPositionId(raw['positions']) ??
              fcKnownPositionId(raw['lineupPosition']) ??
              stored['positionId'] as String?,
        ),
        'shirtNumber': stored['shirtNumber'] ?? raw['jerseyNumber'],
        'realPlayerId': r['realPlayerId'],
        'customAvatarFilePath': r['customAvatarFilePath'],
      };
      registeredByRemote[fcId(r['remotePlayerId'])] = known[id]!;
    }
  }
  final career = await _careerPitchPlayers(
    db,
    fcId(fixture['personId']),
    fcId(fixture['fifaVersion']),
    playerIds: known.keys.toSet(),
    realIds: {for (final p in remote) fcId(p['id'])},
  );
  for (final e in career.entries) {
    if (e.value['realPlayerId'] == null ||
        !remote.any((p) => fcId(p['id']) == fcId(e.value['realPlayerId']))) {
      continue;
    }
    known.putIfAbsent(
      e.key,
      () => {...e.value, 'apiPlayerId': e.value['realPlayerId']},
    );
  }
  final real = await GamePlayers.lookup(fcId(fixture['fifaVersion']), [
    for (final p in known.values)
      if (!hasFootballIdentity(p) || p['positionId'] == null)
        fcId(p['apiPlayerId'] ?? p['realPlayerId']),
  ]);
  for (final e in known.entries) {
    final registered =
        registeredByRemote[fcId(
          e.value['apiPlayerId'] ?? e.value['realPlayerId'],
        )];
    if (registered != null) {
      if (!hasFootballIdentity(e.value)) {
        e.value['name'] = registered['name'];
      }
      if (current?.squad.layoutSource != 'manual') {
        e.value['positionId'] =
            registered['positionId'] ?? e.value['positionId'];
      }
      e.value['customAvatarFilePath'] ??= registered['customAvatarFilePath'];
      e.value['shirtNumber'] ??= registered['shirtNumber'];
    }
    final fallback =
        real[fcId(e.value['apiPlayerId'] ?? e.value['realPlayerId'])];
    if (fallback == null) continue;
    if (!hasFootballIdentity(e.value)) {
      e.value['name'] = fallback.name;
    }
    e.value['positionId'] ??= fallback.mainPositionId;
  }
  final ids = <String, String>{}, used = <String>{};
  final missing = <FcJson>[];
  for (final p in remote) {
    final remoteId = fcId(p['id']);
    if ((fcInt(p['id']) ?? -1) < 0 || ids.containsKey(remoteId)) continue;
    final byId = known.entries
        .where(
          (e) =>
              !used.contains(e.key) &&
              (fcId(e.value['apiPlayerId'] ?? e.value['realPlayerId']) ==
                      remoteId ||
                  e.key == 'fc-opponent:$remoteId'),
        )
        .toList();
    final name = fcNormalize(fcPlayerName(fcObject(p['profile'])));
    final byName = known.entries
        .where(
          (e) =>
              !used.contains(e.key) &&
              name.isNotEmpty &&
              fcNormalize(fcName(e.value['name'])) == name,
        )
        .toList();
    final inCurrentById = byId
        .where((e) => current?.squad.players.containsKey(e.key) == true)
        .toList();
    final inCurrentByName = byName
        .where((e) => current?.squad.players.containsKey(e.key) == true)
        .toList();
    final found = inCurrentById.length == 1
        ? inCurrentById.single
        : byId.isNotEmpty
        ? byId.first
        : byId.isEmpty && inCurrentByName.length == 1
        ? inCurrentByName.single
        : byId.isEmpty && byName.length == 1
        ? byName.single
        : null;
    if (found == null) {
      missing.add(p);
      final fallback = real[remoteId];
      if (fallback != null) {
        known.putIfAbsent(
          'fc-opponent:$remoteId',
          () => {
            'id': 'fc-opponent:$remoteId',
            'name': fallback.name,
            'positionId': fallback.mainPositionId,
            'realPlayerId': remoteId,
          },
        );
      }
    } else {
      ids[remoteId] = found.key;
      used.add(found.key);
    }
  }
  return FcOpponentCompletion(
    current,
    known,
    ids,
    missing,
    rememberedFormation,
  );
}

extension FcScoreOpponentReview on FcScoreRepository {
  Future<({FixtureFormation? own, OpponentLineup? opponent})>
  fixturePitchLineups(Person person, Map<String, Object?> fixture) async {
    var own = FixtureFormation.decode(fixture['matchLineup']);
    var opponent = OpponentLineup.decode(fixture['opponentLineup']);
    final db = await sql.database;
    final reports = await db.query(
      'FcScoreImport',
      columns: ['rawJson'],
      where: 'personId = ? AND fixtureId = ? AND reportId IS NOT NULL',
      whereArgs: [person.id, fixture['id']],
      limit: 1,
    );
    if (own != null &&
        own.layoutSource == null &&
        _usesLegacyAutomaticPitch(own)) {
      own = own.copy(layoutSource: 'squad');
    }
    if (reports.isEmpty) return (own: own, opponent: opponent?.resolved());
    final raw = fcObject(
      await BackgroundData.jsonString(reports.single['rawJson'] as String),
    );
    final home = fixture['location'] == 'home';
    final ownPlayers = fcList(fcObject(raw[home ? 'home' : 'away'])['players']);
    final otherPlayers = fcList(
      fcObject(raw[home ? 'away' : 'home'])['players'],
    );
    if (own != null &&
        own.layoutSource == null &&
        !_usesLegacyAutomaticPitch(own)) {
      own = own.copy(layoutSource: 'manual');
    }
    if (ownPlayers.isNotEmpty && own?.layoutSource != 'manual') {
      final link = await linkFor(person.id);
      final known = await _careerPitchPlayers(
        db,
        person.id,
        person.fifaVersion,
        playerIds: {
          ...?own?.players.keys,
          for (final p in ownPlayers)
            if (link?.players[fcId(p['id'])] case final String id) id,
        },
        realIds: {for (final p in ownPlayers) fcId(p['id'])},
      );
      final ids = <String, String>{};
      for (final p in ownPlayers) {
        final remoteId = fcId(p['id']);
        final savedId = own?.players.entries
            .where(
              (e) =>
                  fcId(e.value['apiPlayerId'] ?? e.value['realPlayerId']) ==
                  remoteId,
            )
            .firstOrNull
            ?.key;
        final local =
            savedId ??
            link?.players[remoteId] ??
            known.entries
                .where((e) => fcId(e.value['realPlayerId']) == remoteId)
                .firstOrNull
                ?.key;
        if (local != null && known.containsKey(local)) ids[remoteId] = local;
      }
      if (ids.isNotEmpty) {
        own = await _ownPitchFormation(db, fixture, ownPlayers, ids, null);
      }
    }
    if (otherPlayers.isNotEmpty) {
      final plan = await _opponentCompletion(db, fixture, otherPlayers);
      opponent = _mergeOpponentCompletion(
        plan,
        otherPlayers,
        fixture,
        null,
        createPlayers: false,
      );
    }
    return (own: own, opponent: opponent?.resolved());
  }

  Future<List<Map<String, Object?>>> opponentPlayers({
    required Person person,
    required String teamId,
    String? leagueId,
    String? seasonId,
    DateTime? beforeDate,
  }) async {
    final plan = await _opponentCompletion(await sql.database, {
      'personId': person.id,
      'fifaVersion': person.fifaVersion,
      'oppositeTeamId': teamId,
      'oppositeTeamLeagueId': leagueId,
      'seasonId': seasonId,
      'date': (beforeDate ?? DateTime(9999)).toIso8601String(),
      'id': '',
    }, []);
    return plan.known.values.where(hasFootballIdentity).toList()
      ..sort((a, b) => fcName(a['name']).compareTo(fcName(b['name'])));
  }

  Future<FcOpponentCompletion?> opponentCompletionPreview({
    required Person person,
    required FcScoreLink link,
    required FcScoreMatch match,
    required String fixtureId,
  }) async {
    if (person.category != PersonCategory.manager || !match.detailed) {
      return null;
    }
    final db = await sql.database;
    final rows = await db.query(
      'ManagerFixtures',
      where: 'id = ? AND personId = ?',
      whereArgs: [fixtureId, person.id],
    );
    if (rows.isEmpty) {
      throw const FcScoreException('Esta partida foi removida.');
    }
    return _opponentCompletion(
      db,
      rows.single,
      fcList(match.opponent(link)['players']),
    );
  }
}

OpponentLineup _mergeOpponentCompletion(
  FcOpponentCompletion plan,
  List<FcJson> remote,
  Map<String, Object?> fixture,
  String? formation, {
  required bool createPlayers,
  List<ManagerFixturePlayerPerformance> ownPerformances = const [],
}) {
  final ids = {...plan.ids};
  if (createPlayers) {
    for (final p in plan.missing) {
      ids[fcId(p['id'])] = 'fc-opponent:${fcId(p['id'])}';
    }
  }
  final api = _formation(
    remote,
    ids,
    formation,
    known: plan.known,
    fallbackFormation: plan.current?.squad.formation.isNotEmpty == true
        ? plan.current!.squad.formation
        : plan.rememberedFormation,
  );
  final current = plan.current;
  final protectedLayout =
      current != null &&
      (current.squad.layoutSource == 'manual' ||
          (current.squad.layoutSource == null &&
              current.squad.starters.keys
                      .where(
                        (id) => hasFootballIdentity(
                          current.squad.players[id] ?? {},
                        ),
                      )
                      .length ==
                  11 &&
              !_usesLegacyAutomaticPitch(current.squad)));
  final players = <String, Map<String, Object?>>{...?current?.squad.players};
  for (final e in api.players.entries) {
    final existing = players[e.key] ?? plan.known[e.key] ?? {};
    players[e.key] = {
      ...e.value,
      ...existing,
      'apiPlayerId': e.value['apiPlayerId'] ?? e.value['realPlayerId'],
      'name': hasFootballIdentity(existing)
          ? existing['name']
          : e.value['name'],
      'positionId': protectedLayout
          ? existing['positionId'] ?? e.value['positionId']
          : e.value['positionId'] ?? existing['positionId'],
    };
    for (final v in e.value.entries) {
      if (players[e.key]![v.key] == null || players[e.key]![v.key] == '') {
        players[e.key]![v.key] = v.value;
      }
    }
  }
  FixtureFormation squad;
  final fromApi =
      current?.squad.layoutSource == 'api' ||
      current?.squad.players.values.any(
            (p) =>
                p['apiPlayerId'] != null ||
                fcId(p['id']).startsWith('fc-opponent:'),
          ) ==
          true;
  if (current == null ||
      !current.hasNames ||
      (fromApi && !protectedLayout) ||
      formation != null) {
    squad = api.copy(
      players: players,
      bench: {
        ...api.bench,
        ...?current?.squad.bench,
      }.where((id) => !api.starters.containsKey(id)).toList(),
    );
  } else {
    final starters = {...current.squad.starters},
        bench = [...current.squad.bench];
    for (final id in api.players.keys) {
      if (starters.containsKey(id) || bench.contains(id)) continue;
      final slot = starters.keys
          .where((key) => fcName(players[key]?['name']).isEmpty)
          .firstOrNull;
      if (slot != null && api.starters.containsKey(id)) {
        starters[id] = starters.remove(slot)!;
        players.remove(slot);
      } else {
        bench.add(id);
      }
    }
    squad = current.squad.copy(
      players: players,
      starters: starters,
      bench: bench,
      layoutSource: protectedLayout ? 'manual' : current.squad.layoutSource,
    );
  }
  var base = OpponentLineup(
    squad: squad,
    performances: current?.performances ?? [],
  );
  final recorded = decodeOpponentGoals(fixture['opponentGoalDetails']);
  if (recorded.isNotEmpty) base = base.withRecordedGoals(recorded);
  final perfs = {for (final p in base.performances) p.playerInstanceId: p};
  final score = fcInt(fixture['oppositeTeamScore']) ?? 1 << 20;
  var goalRoom = math.max(
    0,
    score -
        ownPerformances.fold<int>(0, (n, p) => n + p.ownGoalDetails.length) -
        recorded.where((g) => !g.isOwnGoal).length -
        perfs.values.fold<int>(
          0,
          (n, p) =>
              n +
              p.goalDetails
                  .where((g) => !recorded.any((r) => r.id == g.id))
                  .length,
        ),
  );
  var assistRoom = math.max(
    0,
    score -
        perfs.values.fold<int>(
          0,
          (n, p) => n + (p.assistsCount ?? p.assistDetails.length),
        ),
  );
  var ownGoalRoom = math.max(
    0,
    (fcInt(fixture['playerTeamScore']) ?? 1 << 20) -
        ownPerformances.fold<int>(0, (n, p) => n + p.goalDetails.length) -
        recorded.where((g) => g.isOwnGoal).length -
        perfs.values.fold<int>(
          0,
          (n, p) =>
              n +
              p.ownGoalDetails
                  .where((g) => !recorded.any((r) => r.id == g.id))
                  .length,
        ),
  );
  final incomingPerformances = [
    for (final p in remote.where((p) => p['played'] == true))
      if (ids[fcId(p['id'])] != null)
        _performance(
          p,
          fcId(fixture['personId']),
          fcId(fixture['id']),
          ids[fcId(p['id'])]!,
        ),
  ];
  fcApplySubstitutions(remote, incomingPerformances, ids);
  for (final p in remote.where((p) => p['played'] == true)) {
    final id = ids[fcId(p['id'])];
    if (id == null) continue;
    final mine =
        perfs[id] ??
        ManagerFixturePlayerPerformance(
          personId: fcId(fixture['personId']),
          fixtureId: fcId(fixture['id']),
          playerInstanceId: id,
        );
    final incoming = incomingPerformances.firstWhere(
      (p) => p.playerInstanceId == id,
    );
    incoming.ownGoalDetails = incoming.ownGoalDetails
        .take(ownGoalRoom)
        .toList();
    final merged = fcCompletePerformance(
      mine,
      incoming,
      goalRoom: goalRoom,
      assistRoom: assistRoom,
    );
    goalRoom = math.max(
      0,
      goalRoom - (merged.goalDetails.length - mine.goalDetails.length),
    );
    assistRoom = math.max(
      0,
      assistRoom - (merged.assistDetails.length - mine.assistDetails.length),
    );
    ownGoalRoom = math.max(
      0,
      ownGoalRoom - (merged.ownGoalDetails.length - mine.ownGoalDetails.length),
    );
    perfs[id] = merged;
  }
  return OpponentLineup(
    squad: squad,
    performances: perfs.values.toList(),
  ).resolved();
}
