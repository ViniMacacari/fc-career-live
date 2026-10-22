part of 'FcScoreRepository.dart';

class FcWorldImportResult {
  const FcWorldImportResult(
    this.competitions,
    this.teams,
    this.players,
    this.fixtures,
    this.ownMatches,
    this.preservedMatches, [
    this.skippedMatches = 0,
    this.newPlayers = 0,
    this.reusedPlayers = 0,
  ]);
  final int competitions,
      teams,
      players,
      fixtures,
      ownMatches,
      preservedMatches,
      skippedMatches;
  final int newPlayers, reusedPlayers;
}

class FcWorldMatchPreview {
  const FcWorldMatchPreview({
    required this.match,
    this.existingFixtureId,
    this.manual = false,
    this.localHomeGoals,
    this.localAwayGoals,
    this.ignored = false,
  });
  final FcScoreMatch match;
  final String? existingFixtureId;
  final bool manual;
  final bool ignored;
  final int? localHomeGoals, localAwayGoals;
  bool get exists => existingFixtureId != null;
  bool get scoreDiffers =>
      exists &&
      (localHomeGoals != match.homeGoals || localAwayGoals != match.awayGoals);
}

class FcCompetitionScorers {
  const FcCompetitionScorers(
    this.players,
    this.notice, {
    this.statistics = const [],
    this.complete = false,
  });
  final List<FcJson> players;
  final List<FcJson> statistics;
  final String notice;
  final bool complete;
}

extension FcScoreWorldRepository on FcScoreRepository {
  Future<List<FcWorldMappingIssue>> worldMappingIssues({
    required Person person,
    required FcScoreLink link,
    required FcScoreWorldData data,
  }) async {
    final db = await sql.database;
    final clubs = await FcScoreClubCatalog.load(sql, person.fifaVersion);
    final catalog = await GameCatalog.load();
    final labels = <String, String>{for (final t in clubs.teams) t.id: t.label};
    final competitions = <String, String>{
      for (final t in await catalog.tournaments(person.fifaVersion))
        t.id: t.label,
      for (final l in clubs.leagues) 'league:${l.id}': l.label,
      for (final t in await db.query('Tournament'))
        fcId(t['id']): fcName(t['name']),
    };
    final issues = <FcWorldMappingIssue>[];
    final leagues = Map<String, String>.from(link.leagues);
    final ownTeam = data.teams
        .where((t) => fcId(t['id']) == link.remoteClubId)
        .firstOrNull;
    final ownLeague = fcId(fcObject(ownTeam?['league'])['id']);
    if (ownLeague.isNotEmpty) {
      leagues.putIfAbsent(ownLeague, () => link.localLeagueId);
    }
    for (final kind in ['Competições', 'Equipes']) {
      final rows = kind == 'Equipes'
          ? data.teams
          : data.competitions.map((c) => fcObject(c['competition'])).toList();
      final mapping = kind == 'Equipes' ? link.teams : link.competitions;
      final seen = <String, List<FcJson>>{}, sources = <String>{};
      for (final row in rows) {
        final id = fcId(row['id']), name = fcName(row['name'], 'Sem nome');
        if (id.isEmpty || !sources.add(id)) {
          issues.add(
            FcWorldMappingIssue(
              kind: kind,
              remoteIds: {id},
              sourceProblem: true,
              message:
                  '$name (ID API: ${id.isEmpty ? 'ausente' : id}) veio sem identificação única. A API enviou o cadastro vazio ou repetido. Exporte o save novamente e recarregue os dados.',
            ),
          );
          continue;
        }
        final choice = mapping[id];
        if (choice == null ||
            choice.trim().isEmpty ||
            choice.startsWith('new:') && choice.substring(4).trim().isEmpty) {
          issues.add(
            FcWorldMappingIssue(
              kind: kind,
              remoteIds: {id},
              message:
                  '$name (ID API: $id) está sem vínculo válido. Escolha um cadastro do aplicativo ou crie um novo neste de-para.',
            ),
          );
          continue;
        }
        String? leagueId;
        if (kind == 'Equipes') {
          final league = fcObject(row['league']),
              remoteLeague = fcId(league['id']);
          if (remoteLeague.isNotEmpty) {
            final leagueChoice =
                leagues[remoteLeague] ??
                (id == link.remoteClubId
                    ? link.localLeagueId
                    : 'new:${fcName(league['name'])}');
            leagueId =
                await _existingEntityChoice(
                  db,
                  'CustomLeague',
                  leagueChoice,
                  link.gameVersion,
                ) ??
                leagueChoice;
          }
        }
        final local =
            await _existingEntityChoice(
              db,
              kind == 'Equipes' ? 'CustomClub' : 'Tournament',
              choice,
              link.gameVersion,
              leagueId: leagueId,
            ) ??
            'new:${fcNormalize(choice.substring(4))}:${leagueId ?? ''}';
        final localName =
            (kind == 'Equipes' ? labels : competitions)[local] ??
            (choice.startsWith('new:') ? choice.substring(4) : local);
        if (kind == 'Equipes' &&
            id == link.remoteClubId &&
            local != link.localClubId) {
          issues.add(
            FcWorldMappingIssue(
              kind: kind,
              remoteIds: {id},
              restoreOwnClub: true,
              message:
                  'Seu clube $name (ID API: $id) está ligado a $localName (ID app: $local), mas esta carreira usa ${labels[link.localClubId] ?? link.localClubId} (ID app: ${link.localClubId}). Restaure o vínculo do seu clube para continuar.',
            ),
          );
        }
        (seen[local] ??= []).add({...row, 'resolvedName': localName});
      }
      for (final entry in seen.entries.where((e) => e.value.length > 1)) {
        final names = entry.value
            .map((r) => '${fcName(r['name'])} (ID API: ${fcId(r['id'])})')
            .join(' e ');
        issues.add(
          FcWorldMappingIssue(
            kind: kind,
            remoteIds: entry.value.map((r) => fcId(r['id'])).toSet(),
            message:
                '$names estão ligados ao mesmo cadastro: ${entry.value.first['resolvedName']} (ID app: ${entry.key}). Escolha um cadastro diferente para cada um; o vínculo do seu clube será mantido.',
          ),
        );
      }
    }
    return issues;
  }

  Future<({int teams, int matches})> previewWorldAdditions({
    required Person person,
    required FcScoreLink link,
    required FcScoreWorldData data,
    required Set<String> selectedMatchKeys,
    bool includeCalendarMatches = true,
  }) async {
    final db = await sql.database;
    final teams = (await db.query(
      'FcScoreWorldTeam',
      columns: ['remoteId'],
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [person.id, link.seasonId],
    )).map((r) => fcId(r['remoteId'])).toSet();
    final games = (await db.query(
      'FcScoreWorldFixture',
      columns: ['remoteKey'],
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [person.id, link.seasonId],
    )).map((r) => fcId(r['remoteKey'])).toSet();
    final previews = await previewWorldMatches(
      person: person,
      link: link,
      data: data,
    );
    final excluded = {
      for (final p in previews)
        if (p.exists || p.ignored) p.match.remoteKey,
    };
    final newGames = {
      for (final f in data.fixtures)
        if (includeCalendarMatches &&
            !games.contains(
              FcScoreMatch.fromFixture(f, data.saveId).remoteKey,
            ) &&
            !excluded.contains(
              FcScoreMatch.fromFixture(f, data.saveId).remoteKey,
            ))
          FcScoreMatch.fromFixture(f, data.saveId).remoteKey,
      ...selectedMatchKeys.difference(excluded),
    };
    return (
      teams: data.teams.where((t) => !teams.contains(fcId(t['id']))).length,
      matches: newGames.length,
    );
  }

  Future<FcWorldSyncState?> previousWorldSync(
    Person person,
    FcScoreLink link,
  ) async {
    final saved = link.worldSync[link.seasonId];
    if (saved != null) return saved;
    final db = await sql.database;
    final competitions = await db.query(
      'FcScoreCompetition',
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [person.id, link.seasonId],
    );
    if (competitions.isEmpty) return null;
    final ignored = <String>{};
    for (final row in await db.query(
      'FcScoreWorldFixture',
      where: 'personId = ? AND seasonId = ? AND played = 1 AND (homeTeamId = ? OR awayTeamId = ?)',
      whereArgs: [person.id, link.seasonId, link.localClubId, link.localClubId],
    )) {
      final match = FcScoreMatch.fromFixture(
        fcObject(jsonDecode(row['rawJson'] as String)),
        link.saveId,
      );
      if (await _existing(db, person, link, match) == null) {
        ignored.add(match.remoteKey);
      }
    }
    return FcWorldSyncState(
      competitionIds: competitions.map((c) => fcId(c['remoteId'])).toSet(),
      ignoredMatchKeys: ignored,
      importedAt: fcId(competitions.first['importedAt']),
    );
  }

  Future<FcWorldPlayerReview> reviewWorldPlayers({
    required Person person,
    required FcScoreLink link,
    required FcScoreWorldData data,
    bool preserveOwnPlayers = false,
  }) async {
    if (person.id != link.personId || data.saveId != link.saveId) {
      throw const FcScoreException('Confira a carreira e o save vinculados.');
    }
    return FcWorldPlayerReview(
      data,
      await sql.getCustomPlayers(person.id),
      protectedPlayerIds: preserveOwnPlayers
          ? _ownWorldPlayerIds(data, link)
          : {},
    );
  }

  Future<List<FcWorldMatchPreview>> previewWorldMatches({
    required Person person,
    required FcScoreLink link,
    required FcScoreWorldData data,
  }) async {
    if (person.id != link.personId || data.saveId != link.saveId) {
      throw const FcScoreException('Confira a carreira e o save vinculados.');
    }
    final db = await sql.database;
    final previews = <FcWorldMatchPreview>[];
    for (final fixture in data.fixtures) {
      final match = FcScoreMatch.fromFixture(fixture, data.saveId);
      if (fixture['played'] != true ||
          (match.homeId != link.remoteClubId &&
              match.awayId != link.remoteClubId)) {
        continue;
      }
      final old = await _existing(db, person, link, match);
      final local = old?['localFixture'] as Map<String, Object?>?;
      final home = match.homeId == link.remoteClubId;
      previews.add(
        FcWorldMatchPreview(
          match: match,
          existingFixtureId: old?['fixtureId'] as String?,
          manual: old?['manual'] == true,
          localHomeGoals: fcInt(
            local?[home ? 'playerTeamScore' : 'oppositeTeamScore'],
          ),
          localAwayGoals: fcInt(
            local?[home ? 'oppositeTeamScore' : 'playerTeamScore'],
          ),
          ignored:
              link.worldSync[link.seasonId]?.ignoredMatchKeys.contains(
                match.remoteKey,
              ) ==
              true,
        ),
      );
    }
    previews.sort(
      (a, b) =>
          (b.match.date ?? DateTime(0)).compareTo(a.match.date ?? DateTime(0)),
    );
    return previews;
  }

  Future<FcCompetitionScorers> competitionScorers(
    Person person,
    FcJson competition,
  ) async {
    final db = await sql.database;
    final raw = fcObject(competition['data']);
    List<FcJson>? statistics = raw['playerStatsComplete'] == true
        ? fcList(raw['playerStats'])
        : null;
    if (statistics == null) {
      final records = <FcJson>[];
      var available = false;
      for (var offset = 0; ; offset += 256) {
        final rows = await db.query(
          'FcScoreWorldPlayer',
          columns: ['remoteTeamId', 'rawJson'],
          where: 'personId = ? AND seasonId = ?',
          whereArgs: [person.id, competition['seasonId']],
          orderBy: 'remoteTeamId, remotePlayerId',
          limit: 256,
          offset: offset,
        );
        for (final row in rows) {
          final p = fcObject(jsonDecode(row['rawJson'] as String));
          final season = fcObject(p['seasonStats']);
          if (season['competitions'] is! List) continue;
          available = true;
          for (final s in fcList(season['competitions'])) {
            if (fcId(fcObject(s['competition'])['id']) ==
                    fcId(competition['remoteId']) &&
                fcId(fcObject(s['team'])['id']) == fcId(row['remoteTeamId'])) {
              records.add({
                ...s,
                'player': {'id': p['id'], 'name': fcPlayerName(p)},
              });
            }
          }
        }
        if (rows.length < 256) break;
      }
      if (available) statistics = records;
    }
    if (statistics != null) {
      final locals = <String, Object?>{};
      for (var offset = 0; ; offset += 256) {
        final rows = await db.rawQuery(
          '''SELECT w.remotePlayerId, p.name
          FROM FcScoreWorldPlayer w JOIN CustomCreatedPlayer p
          ON p.personId = w.personId AND p.id = w.playerId
          WHERE w.personId = ? AND w.seasonId = ?
          ORDER BY w.remotePlayerId, w.remoteTeamId LIMIT 256 OFFSET ?''',
          [person.id, competition['seasonId'], offset],
        );
        for (final row in rows) {
          locals[fcId(row['remotePlayerId'])] = row['name'];
        }
        if (rows.length < 256) break;
      }
      final records = <FcJson>[
        for (final s in statistics)
          {
            ...s,
            'id': fcObject(s['player'])['id'],
            'name':
                locals[fcId(fcObject(s['player'])['id'])] ??
                fcName(fcObject(s['player'])['name']),
            'remoteTeamId': fcObject(s['team'])['id'],
            'teamName': fcName(fcObject(s['team'])['name']),
          },
      ];
      return FcCompetitionScorers(
        fcRankStats(records, 'goals'),
        'Estatísticas desta competição no save em ${competition['currentDate']}.',
        statistics: records,
        complete: true,
      );
    }
    final league = RegExp(r'^C(\d+)$')
        .firstMatch(fcId(competition['code']))
        ?.group(1);
    final seasonTeams = await careerTeams(
      person.id,
      fcId(competition['seasonId']),
      includeRosters: false,
    );
    final participants = <String>{};
    for (final stage in fcList(fcObject(competition['data'])['stages'])) {
      for (final group in fcList(stage['groups'])) {
        for (final row in fcList(group['rows'])) {
          participants.add(fcId(fcObject(row['team'])['id']));
        }
      }
    }
    for (final f in await competitionFixtures(
      person.id,
      fcId(competition['seasonId']),
      fcId(competition['remoteId']),
    )) {
      for (final side in ['home', 'away']) {
        participants.add(
          fcId(fcObject(fcObject(fcObject(f['data'])[side])['team'])['id']),
        );
      }
    }
    final isLeague =
        league != null &&
        seasonTeams.any(
          (t) =>
              participants.contains(t['remoteId']) &&
              fcId(fcObject(fcObject(t['data'])['league'])['id']) == league,
        );
    if (isLeague) {
      final teams = {
        for (final t in seasonTeams)
          if (participants.contains(t['remoteId']) &&
              fcId(fcObject(fcObject(t['data'])['league'])['id']) == league)
            fcId(t['remoteId']): fcObject(t['data']),
      };
      final players = <String, FcJson>{};
      final teamIds = teams.keys.toList();
      for (var start = 0; start < teamIds.length; start += 200) {
        final chunk = teamIds.skip(start).take(200).toList();
        for (var offset = 0; ; offset += 256) {
          final rows = await db.rawQuery(
            '''SELECT w.remotePlayerId, w.remoteTeamId, w.rawJson,
              p.name AS localName FROM FcScoreWorldPlayer w
            LEFT JOIN CustomCreatedPlayer p ON p.personId = w.personId AND p.id = w.playerId
            WHERE w.personId = ? AND w.seasonId = ?
              AND w.remoteTeamId IN (${List.filled(chunk.length, '?').join(',')})
            ORDER BY w.remoteTeamId, w.remotePlayerId LIMIT 256 OFFSET ?''',
            [person.id, competition['seasonId'], ...chunk, offset],
          );
          for (final row in rows) {
            final team = teams[fcId(row['remoteTeamId'])]!;
            final p = fcObject(jsonDecode(row['rawJson'] as String));
            if (fcInt(p['leagueGoals']) == null ||
                fcInt(p['leagueGoals'])! <= 0) {
              continue;
            }
            final id = fcId(row['remotePlayerId']);
            if ((fcInt(players[id]?['goals']) ?? -1) >
                fcInt(p['leagueGoals'])!) {
              continue;
            }
            players[id] = {
              ...p,
              'name': row['localName'] ?? fcPlayerName(p),
              'goals': p['leagueGoals'],
              'appearances': p['leagueAppearances'],
              'remoteTeamId': row['remoteTeamId'],
              'teamName': fcName(team['name']),
            };
          }
          if (rows.length < 256) break;
        }
      }
      final sorted = players.values.toList()
        ..sort(
          (a, b) => fcInt(b['goals']) == fcInt(a['goals'])
              ? fcName(a['name']).compareTo(fcName(b['name']))
              : fcInt(b['goals'])! - fcInt(a['goals'])!,
        );
      return FcCompetitionScorers(
        sorted,
        'Artilharia de liga registrada no save em ${competition['currentDate']}.',
      );
    }
    final fixtureTable = person.category == PersonCategory.manager
        ? 'ManagerFixtures'
        : 'PlayerFixtures';
    final reports = await db.rawQuery(
      '''SELECT i.rawJson FROM FcScoreImport i
      JOIN $fixtureTable f ON f.id = i.fixtureId AND f.personId = i.personId
      WHERE i.personId = ? AND f.seasonId = ? AND f.tournamentId = ? AND i.reportId IS NOT NULL''',
      [person.id, competition['seasonId'], competition['tournamentId']],
    );
    final players = <String, FcJson>{};
    for (final report in reports) {
      final raw = fcObject(jsonDecode(report['rawJson'] as String));
      for (final side in [fcObject(raw['home']), fcObject(raw['away'])]) {
        for (final p in fcList(side['players'])) {
          if (p['played'] != true ||
              fcInt(fcObject(p['stats'])['goalsDerived']) == null) {
            continue;
          }
          final id = fcId(p['id']), team = fcObject(side['team']);
          final entry = players.putIfAbsent(
            id,
            () => {
              'id': id,
              'name': fcPlayerName(fcObject(p['profile'])),
              'goals': 0,
              'appearances': 0,
            },
          );
          entry['goals'] =
              fcInt(entry['goals'])! +
              fcInt(fcObject(p['stats'])['goalsDerived'])!;
          entry['appearances'] = fcInt(entry['appearances'])! + 1;
          entry['remoteTeamId'] = fcId(team['id']);
          entry['teamName'] = fcName(team['name']);
        }
      }
    }
    final sorted = players.values.where((p) => fcInt(p['goals'])! > 0).toList()
      ..sort((a, b) => fcInt(b['goals'])! - fcInt(a['goals'])!);
    return FcCompetitionScorers(
      sorted,
      reports.isEmpty
          ? 'A API não fornece o acumulado de gols desta copa. Importe relatórios detalhados para registrar a artilharia dos jogos disponíveis.'
          : 'Artilharia parcial · ${reports.length} relatórios importados. A API não fornece o acumulado completo desta copa.',
    );
  }

  Future<List<FcJson>> careerCompetitions(
    String personId, {
    String? seasonId,
  }) async {
    final db = await sql.database;
    final person = (await db.query(
      'Persons',
      columns: ['fifaVersion'],
      where: 'id = ?',
      whereArgs: [personId],
    )).firstOrNull;
    final local = person == null
        ? <String, CatalogItem>{}
        : await FcScoreCareerIdentity.competitionCatalog(
            sql,
            fcId(person['fifaVersion']),
          );
    final rows = await db.query(
      'FcScoreCompetition',
      where: 'personId = ?${seasonId == null ? '' : ' AND seasonId = ?'}',
      whereArgs: [personId, ?seasonId],
      orderBy: 'currentDate DESC, name COLLATE NOCASE',
    );
    final decoded = await _readWorldRows(rows);
    return [
      for (final r in decoded)
        {...r, 'name': local[fcId(r['tournamentId'])]?.label ?? r['name']},
    ];
  }

  Future<List<FcJson>> careerTeams(
    String personId,
    String seasonId, {
    bool includeRosters = true,
  }) async {
    final rows = await (await sql.database).query(
      'FcScoreWorldTeam',
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [personId, seasonId],
    );
    return _readWorldRows(rows, hideRosters: !includeRosters);
  }

  Future<List<FcJson>> competitionFixtures(
    String personId,
    String seasonId,
    String competitionId,
  ) async {
    final rows = await (await sql.database).query(
      'FcScoreWorldFixture',
      where: 'personId = ? AND seasonId = ? AND competitionId = ?',
      whereArgs: [personId, seasonId, competitionId],
      orderBy: 'date ASC, remoteKey ASC',
    );
    return _readWorldRows(rows);
  }

  Future<Map<String, String>> competitionFixtureLinks(
    Person person,
    String seasonId,
    String competitionId,
  ) async {
    final db = await sql.database;
    final table = person.category == PersonCategory.manager
        ? 'ManagerFixtures'
        : 'PlayerFixtures';
    final world = await db.rawQuery(
      '''
      SELECT w.remoteKey, w.homeTeamId, w.awayTeamId, w.tournamentId, w.date,
        f.id AS fixtureId
      FROM FcScoreWorldFixture w
      LEFT JOIN FcScoreImport i ON i.personId = w.personId AND i.remoteKey = w.remoteKey
      LEFT JOIN $table f ON f.personId = w.personId AND f.id = i.fixtureId AND f.seasonId = w.seasonId
      WHERE w.personId = ? AND w.seasonId = ? AND w.competitionId = ?
    ''',
      [person.id, seasonId, competitionId],
    );
    final local = await db.query(
      table,
      columns: [
        'id',
        'date',
        'playerTeamId',
        'oppositeTeamId',
        'tournamentId',
        'location',
      ],
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [person.id, seasonId],
    );
    String? key(Object? date, Object? home, Object? away, Object? tournament) {
      final day = fcId(date),
          h = fcId(home),
          a = fcId(away),
          t = fcId(tournament);
      if (day.length < 10 || h.isEmpty || a.isEmpty || t.isEmpty) return null;
      return jsonEncode([day.substring(0, 10), h, a, t]);
    }

    final matches = <String, List<String>>{};
    for (final row in local) {
      if (!['home', 'away'].contains(row['location'])) continue;
      final home = row['location'] == 'home';
      final matchKey = key(
        row['date'],
        row[home ? 'playerTeamId' : 'oppositeTeamId'],
        row[home ? 'oppositeTeamId' : 'playerTeamId'],
        row['tournamentId'],
      );
      if (matchKey != null) (matches[matchKey] ??= []).add(fcId(row['id']));
    }
    final result = <String, String>{};
    for (final row in world) {
      final id = fcId(row['fixtureId']);
      if (id.isNotEmpty) {
        result[fcId(row['remoteKey'])] = id;
        continue;
      }
      final candidates =
          matches[key(
            row['date'],
            row['homeTeamId'],
            row['awayTeamId'],
            row['tournamentId'],
          )];
      if (candidates?.length == 1) {
        result[fcId(row['remoteKey'])] = candidates!.single;
      }
    }
    return result;
  }

  Future<List<FcJson>> careerRoster(
    String personId,
    String seasonId,
    String remoteTeamId,
  ) async {
    final rows = await (await sql.database).rawQuery(
      '''
        SELECT w.*, p.name AS localName, p.customAvatarFilePath,
          COALESCE((SELECT o.overall FROM Overall o
            WHERE o.personId = w.personId AND o.customPlayerId = w.playerId
            ORDER BY julianday(o.date) DESC, o.rowid DESC LIMIT 1), p.overall) AS localOverall
        FROM FcScoreWorldPlayer w
        LEFT JOIN CustomCreatedPlayer p ON p.id = w.playerId AND p.personId = w.personId
        WHERE w.personId = ? AND w.seasonId = ? AND w.remoteTeamId = ?''',
      [personId, seasonId, remoteTeamId],
    );
    return _readWorldRows(rows, players: true);
  }

  Future<FcWorldImportResult> importWorld({
    required Person person,
    required FcScoreLink link,
    required FcScoreWorldData data,
    bool importOwnMatches = true,
    bool rememberSkippedOwnMatches = true,
    Set<String>? selectedOwnMatchKeys,
    bool bringOwnSquad = true,
    bool updateOveralls = true,
    bool preserveOwnPlayers = false,
    FcScoreUpdateOptions? updateOptions,
    void Function(double)? onProgress,
  }) async {
    if (updateOptions != null) {
      data = data.forUpdate(updateOptions, link.remoteClubId);
      bringOwnSquad = updateOptions.ownSquad;
      preserveOwnPlayers = !updateOptions.ownSquad;
      updateOveralls = updateOptions.overalls;
    }
    if (person.id != link.personId ||
        data.saveId != link.saveId ||
        fcVersion(person.fifaVersion) != link.gameVersion) {
      throw const FcScoreException('Confira a carreira e o save vinculados.');
    }
    final selected = link.copy();
    if (updateOptions != null) selected.updateOptions = updateOptions;
    final ignoredKeys = Set<String>.of(
      selected.worldSync[selected.seasonId]?.ignoredMatchKeys ?? const {},
    );
    final matchKeys = selectedOwnMatchKeys == null
        ? null
        : Set<String>.of(selectedOwnMatchKeys);
    final candidates = {
      for (final fixture in data.fixtures)
        if (fixture['played'] == true)
          if (FcScoreMatch.fromFixture(fixture, data.saveId).homeId ==
                  link.remoteClubId ||
              FcScoreMatch.fromFixture(fixture, data.saveId).awayId ==
                  link.remoteClubId)
            FcScoreMatch.fromFixture(fixture, data.saveId).remoteKey,
    };
    if (matchKeys != null && !candidates.containsAll(matchKeys)) {
      throw const FcScoreException(
        'A seleção contém partidas fora deste lote. Revise os jogos.',
      );
    }
    final db = await sql.database;
    final now = DateTime.now().toIso8601String();
    final mappingIssues = await worldMappingIssues(
      person: person,
      link: selected,
      data: data,
    );
    if (mappingIssues.isNotEmpty) throw FcWorldMappingException(mappingIssues);
    final result = await db.transaction((tx) async {
      final persons = await tx.query(
        'Persons',
        where: 'id = ?',
        whereArgs: [person.id],
      );
      final seasons = await tx.query(
        'Seasons',
        where: 'id = ? AND personId = ?',
        whereArgs: [selected.seasonId, person.id],
      );
      if (persons.isEmpty ||
          seasons.isEmpty ||
          persons.single['category'] != person.category.name ||
          fcVersion(fcId(persons.single['fifaVersion'])) != link.gameVersion) {
        throw const FcScoreException(
          'A temporada não pertence à carreira selecionada.',
        );
      }
      final season = Season.fromMap(seasons.single);
      final date = DateTime.tryParse(data.currentDate);
      if (season.isClosed ||
          date == null ||
          date.isBefore(season.startDate) ||
          date.isAfter(season.endDate)) {
        throw const FcScoreException(
          'Escolha uma temporada aberta que corresponda à data do save.',
        );
      }
      final previous = await tx.query(
        'FcScoreCompetition',
        where: 'personId = ? AND seasonId = ?',
        whereArgs: [person.id, season.id],
      );
      if (previous.any(
        (r) => fcId(r['currentDate']).compareTo(data.currentDate) > 0,
      )) {
        throw const FcScoreException(
          'Este save é anterior aos dados já importados nesta temporada. Use o save mais recente.',
        );
      }
      await SqlService.ensureTransferReleaseSchema(tx);
      await SeasonRosterService.initialize(tx, season);
      final playerReview = FcWorldPlayerReview(
        data,
        await tx.query(
          'CustomCreatedPlayer',
          where: 'personId = ?',
          whereArgs: [person.id],
        ),
        protectedPlayerIds: preserveOwnPlayers
            ? _ownWorldPlayerIds(data, link)
            : {},
      );
      if (playerReview.issues(selected.players).isNotEmpty) {
        throw FcWorldPlayerMappingException(playerReview);
      }
      final compIds = <String>{}, localComps = <String>{};
      for (final comp in data.competitions) {
        final ref = fcObject(comp['competition']), id = fcId(ref['id']);
        if (id.isEmpty ||
            !compIds.add(id) ||
            selected.competitions[id] == null) {
          throw const FcScoreException('Revise o de-para das competições.');
        }
        final local = await _entity(
          tx,
          'Tournament',
          selected.competitions[id]!,
          link.gameVersion,
        );
        if (!localComps.add(local)) {
          throw const FcScoreException(
            'Cada competição precisa de um cadastro diferente. Revise o de-para.',
          );
        }
        selected.competitions[id] = local;
      }
      final localTeams = <String, FcJson>{}, teamIds = <String>{};
      final ownTeam = data.teams
          .where((t) => fcId(t['id']) == link.remoteClubId)
          .firstOrNull;
      final ownLeagueId = fcId(fcObject(ownTeam?['league'])['id']);
      if (ownLeagueId.isNotEmpty) {
        selected.leagues.putIfAbsent(ownLeagueId, () => selected.localLeagueId);
      }
      final localPlayers = <String, String>{};
      final clubs = await WorldRosterRecorder.start(
        tx,
        personId: person.id,
        ownTeamId: link.localClubId,
      );
      var newPlayers = 0, reusedPlayers = 0;
      final remoteByLocalPlayer = <String, String>{};
      final previousPlayers = <String, Map<String, Object?>>{
        for (final row in await tx.query(
          'FcScoreWorldPlayer',
          where: 'personId = ? AND seasonId = ?',
          whereArgs: [person.id, season.id],
        ))
          '${row['remoteTeamId']}:${row['remotePlayerId']}': row,
      };
      final overalls = <String, Map<String, Object?>>{
        for (final row in await tx.query(
          'Overall',
          columns: ['customPlayerId', 'overall', 'date'],
          where: 'personId = ?',
          whereArgs: [person.id],
          orderBy: 'julianday(date) ASC, rowid ASC',
        ))
          fcId(row['customPlayerId']): row,
      };
      final protectedLocalIds = preserveOwnPlayers
          ? {
              for (final p in await tx.query(
                'TeamPlayer',
                where: 'personId = ? AND seasonId = ?',
                whereArgs: [person.id, season.id],
              ))
                fcId(p['playerId']),
              for (final id in playerReview.protectedPlayerIds)
                if (playerReview.local.containsKey(selected.players[id]))
                  selected.players[id]!,
            }
          : <String>{};
      for (final team in data.teams) {
        onProgress?.call(.55 * teamIds.length / data.teams.length);
        final id = fcId(team['id']), league = fcObject(team['league']);
        if (id.isEmpty || !teamIds.add(id) || selected.teams[id] == null) {
          throw const FcScoreException('Revise o de-para das equipes.');
        }
        String? leagueId;
        final remoteLeagueId = fcId(league['id']);
        if (remoteLeagueId.isNotEmpty) {
          if (id == link.remoteClubId) {
            selected.leagues.putIfAbsent(
              remoteLeagueId,
              () => selected.localLeagueId,
            );
          }
          selected.leagues.putIfAbsent(
            remoteLeagueId,
            () => 'new:${fcName(league['name'])}',
          );
          leagueId = await _entity(
            tx,
            'CustomLeague',
            selected.leagues[remoteLeagueId]!,
            link.gameVersion,
          );
          selected.leagues[remoteLeagueId] = leagueId;
        }
        final local = await _entity(
          tx,
          'CustomClub',
          selected.teams[id]!,
          link.gameVersion,
          leagueId: leagueId,
        );
        final conflicting = localTeams[local];
        if (conflicting != null ||
            (id == link.remoteClubId && local != link.localClubId)) {
          throw FcWorldMappingException([
            FcWorldMappingIssue(
              kind: 'Equipes',
              remoteIds: {id, if (conflicting != null) fcId(conflicting['id'])},
              restoreOwnClub: conflicting == null,
              message: conflicting == null
                  ? 'Seu clube ${fcName(team['name'])} (ID API: $id) está ligado ao cadastro $local, mas a carreira usa ${link.localClubId}. Restaure o vínculo do seu clube.'
                  : '${fcName(conflicting['name'])} (ID API: ${fcId(conflicting['id'])}) e ${fcName(team['name'])} (ID API: $id) estão ligados ao mesmo cadastro do app (ID: $local). Escolha um cadastro diferente para cada equipe.',
            ),
          ]);
        }
        localTeams[local] = team;
        selected.teams[id] = local;
        final refreshRoster =
            updateOptions == null ||
            (id == link.remoteClubId
                ? updateOptions.ownSquad
                : updateOptions.squads);
        FcJson teamSnapshot = team;
        if (!refreshRoster) {
          final previousTeam = await tx.query(
            'FcScoreWorldTeam',
            where: 'personId = ? AND seasonId = ? AND remoteId = ?',
            whereArgs: [person.id, season.id, id],
          );
          final raw = previousTeam.firstOrNull?['rawJson'];
          if (raw is String) {
            teamSnapshot = {
              ...team,
              'roster': fcObject(jsonDecode(raw))['roster'] ?? [],
            };
          }
        }
        await tx.insert('FcScoreWorldTeam', {
          'personId': person.id,
          'seasonId': season.id,
          'remoteId': id,
          'teamId': local,
          'leagueId': leagueId,
          'rawJson': jsonEncode(teamSnapshot),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        if (!refreshRoster) continue;
        final seenPlayers = <String>{};
        for (final player in fcList(team['roster'])) {
          final pid = fcId(player['id']);
          if (pid.isEmpty || !seenPlayers.add(pid)) {
            throw const FcScoreException(
              'Um elenco contém jogadores repetidos ou sem identificação.',
            );
          }
          final protected = playerReview.isProtected(pid);
          final choice = selected.players[pid];
          final localPlayer =
              localPlayers[pid] ??
              (protected
                  ? (playerReview.local.containsKey(choice) ? choice! : '')
                  : playerReview.local.containsKey(choice)
                  ? choice!
                  : await _player(tx, person.id, player, choice));
          final profile = protected
              ? player
              : fcPlayerWithChoice(player, choice);
          final previousRemoteId = remoteByLocalPlayer[localPlayer];
          if (!protected &&
              previousRemoteId != null &&
              previousRemoteId != pid) {
            throw FcWorldPlayerMappingException(playerReview);
          }
          if (localPlayer.isNotEmpty) {
            if (!localPlayers.containsKey(pid)) {
              if (playerReview.local.containsKey(localPlayer)) {
                reusedPlayers++;
              } else {
                newPlayers++;
              }
            }
            localPlayers[pid] = localPlayer;
            remoteByLocalPlayer[localPlayer] = pid;
            if (!protected) selected.players[pid] = localPlayer;
          }
          for (final key in [
            'leagueGoals',
            'leagueAppearances',
            'yellowCards',
            'redCards',
          ]) {
            if (player[key] != null &&
                (fcInt(player[key]) == null || fcInt(player[key])! < 0)) {
              throw FcScoreException(
                '${fcPlayerName(player)} (ID API: $pid), equipe ${fcName(team['name'])}: '
                'o campo $key veio com o valor ${player[key]}. Corrija esse dado no exportador e atualize; era esperado um inteiro não negativo.',
              );
            }
          }
          final seasonStats = fcObject(player['seasonStats']);
          final statSource =
              '${fcPlayerName(player)} (ID API: $pid), equipe ${fcName(team['name'])}';
          fcValidateStats(
            fcObject(seasonStats['totals']),
            source: '$statSource, totais da temporada',
          );
          for (final stats in fcList(seasonStats['competitions'])) {
            fcValidateStats(
              stats,
              source:
                  '$statSource, competição ${fcObject(stats['competition'])}',
            );
          }
          if (localPlayer.isNotEmpty) {
            await clubs.record(
              playerId: localPlayer,
              teamId: local,
              leagueId: leagueId,
              date: date,
              shirtNumber: fcInt(player['jerseyNumber']),
            );
          }
          final encoded = jsonEncode(player);
          final oldPlayer = previousPlayers['$id:$pid'];
          if (oldPlayer?['playerId'] != localPlayer ||
              oldPlayer?['rawJson'] != encoded) {
            await tx.insert('FcScoreWorldPlayer', {
              'personId': person.id,
              'seasonId': season.id,
              'remoteTeamId': id,
              'remotePlayerId': pid,
              'playerId': localPlayer,
              'rawJson': encoded,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          if (updateOveralls &&
              !protected &&
              !protectedLocalIds.contains(localPlayer)) {
            final overall = fcInt(profile['overall']);
            final latest = overalls[localPlayer];
            if (overall != null &&
                overall >= 1 &&
                overall <= 99 &&
                latest?['overall'] != overall &&
                (DateTime.tryParse(fcId(latest?['date']))?.isAfter(date) !=
                    true)) {
              final stamp = date.toIso8601String();
              final old = await tx.query(
                'Overall',
                where: 'personId = ? AND customPlayerId = ? AND date = ?',
                whereArgs: [person.id, localPlayer, stamp],
              );
              await tx.insert('Overall', {
                'id': old.firstOrNull?['id'] ?? _uuid(),
                'personId': person.id,
                'customPlayerId': localPlayer,
                'date': stamp,
                'createdAt': now,
                'overall': overall,
              }, conflictAlgorithm: ConflictAlgorithm.replace);
              overalls[localPlayer] = {'overall': overall, 'date': stamp};
            }
          }
          if (bringOwnSquad &&
              !preserveOwnPlayers &&
              id == link.remoteClubId &&
              person.category == PersonCategory.manager) {
            final roster = await tx.query(
              'TeamPlayer',
              where: 'personId = ? AND seasonId = ? AND playerId = ?',
              whereArgs: [person.id, season.id, localPlayer],
            );
            if (roster.isEmpty) {
              await tx.insert('TeamPlayer', {
                'id': _uuid(),
                'personId': person.id,
                'seasonId': season.id,
                'playerId': localPlayer,
                'overall': fcInt(profile['overall']),
                'shirtNumber': fcInt(player['jerseyNumber']),
                'isBench': 1,
              });
            }
          }
        }
        for (final old in previousPlayers.values.where(
          (r) =>
              r['remoteTeamId'] == id &&
              !seenPlayers.contains(fcId(r['remotePlayerId'])),
        )) {
          await tx.delete(
            'FcScoreWorldPlayer',
            where: 'personId = ? AND seasonId = ? AND remoteTeamId = ? AND remotePlayerId = ?',
            whereArgs: [person.id, season.id, id, old['remotePlayerId']],
          );
        }
      }
      var importedOwn = 0, preserved = 0, skipped = 0;
      for (final id
          in (updateOptions?.calendar ?? true) ? compIds : <String>{}) {
        await tx.delete(
          'FcScoreWorldFixture',
          where: 'personId = ? AND seasonId = ? AND competitionId = ?',
          whereArgs: [person.id, season.id, id],
        );
      }
      final seenFixtures = <String>{};
      for (final fixture
          in (updateOptions?.calendar ?? true) ? data.fixtures : <FcJson>[]) {
        onProgress?.call(.55 + .3 * seenFixtures.length / data.fixtures.length);
        final match = FcScoreMatch.fromFixture(fixture, data.saveId);
        if (!compIds.contains(match.competitionId) ||
            !teamIds.contains(match.homeId) ||
            !teamIds.contains(match.awayId) ||
            match.homeId == match.awayId ||
            match.fixtureId.isEmpty ||
            match.date == null ||
            match.date!.isBefore(season.startDate) ||
            match.date!.isAfter(season.endDate) ||
            !seenFixtures.add(match.remoteKey)) {
          throw const FcScoreException(
            'O calendário contém jogos sem vínculo, repetidos ou de outra temporada.',
          );
        }
        if (fixture['played'] == true &&
            (match.homeGoals == null ||
                match.awayGoals == null ||
                match.homeGoals! < 0 ||
                match.awayGoals! < 0 ||
                match.homeGoals! >= 255 ||
                match.awayGoals! >= 255)) {
          throw const FcScoreException(
            'Uma partida contém um placar inválido.',
          );
        }
        await tx.insert('FcScoreWorldFixture', {
          'personId': person.id,
          'seasonId': season.id,
          'remoteKey': match.remoteKey,
          'competitionId': match.competitionId,
          'tournamentId': selected.competitions[match.competitionId],
          'homeTeamId': selected.teams[match.homeId],
          'awayTeamId': selected.teams[match.awayId],
          'date': match.date!.toIso8601String(),
          'played': fixture['played'] == true ? 1 : 0,
          'rawJson': jsonEncode(fixture),
        });
        if (person.category == PersonCategory.manager &&
            fixture['played'] == true &&
            (match.homeId == link.remoteClubId ||
                match.awayId == link.remoteClubId)) {
          final existing = await _existing(tx, person, selected, match);
          if (existing != null) {
            preserved++;
            continue;
          }
          if (!importOwnMatches ||
              (matchKeys != null
                  ? !matchKeys.contains(match.remoteKey)
                  : ignoredKeys.contains(match.remoteKey))) {
            if (rememberSkippedOwnMatches) ignoredKeys.add(match.remoteKey);
            skipped++;
            continue;
          }
          ignoredKeys.remove(match.remoteKey);
          _validate(selected, match);
          final own = match.own(selected), other = match.opponent(selected);
          final fixtureId = _uuid();
          await tx.insert(
            'ManagerFixtures',
            ManagerFixture(
              id: fixtureId,
              personId: person.id,
              date: match.date!,
              fifaVersion: person.fifaVersion,
              playerTeamScore: fcInt(own['goals'])!,
              oppositeTeamScore: fcInt(other['goals'])!,
              playerTeamId: selected.localClubId,
              playerTeamLeagueId: selected.localLeagueId,
              oppositeTeamId:
                  selected.teams[fcId(fcObject(other['team'])['id'])]!,
              tournamentId: selected.competitions[match.competitionId]!,
              seasonId: season.id,
              location: match.homeId == link.remoteClubId
                  ? GameLocation.home
                  : GameLocation.away,
              createdAt: DateTime.parse(now),
              updatedAt: DateTime.parse(now),
              stage: match.stage,
              playerTeamPenaltiesScore: fcInt(own['penalties']),
              oppositeTeamPenaltiesScore: fcInt(other['penalties']),
            ).toMap(),
          );
          await tx.insert('FcScoreImport', {
            'personId': person.id,
            'remoteKey': match.remoteKey,
            'fixtureId': fixtureId,
            'saveId': data.saveId,
            'reportId': null,
            'rawJson': jsonEncode(fixture),
            'createdAt': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          importedOwn++;
        }
      }
      for (final competition
          in (updateOptions?.competitions ?? true)
              ? data.competitions
              : <FcJson>[]) {
        final ref = fcObject(competition['competition']),
            remoteId = fcId(ref['id']);
        final localId = selected.competitions[remoteId]!;
        final custom = await tx.query(
          'Tournament',
          where: 'id = ?',
          whereArgs: [localId],
        );
        final name = custom.firstOrNull?['name'] ?? fcName(ref['name']);
        await tx.insert('FcScoreCompetition', {
          'personId': person.id,
          'seasonId': season.id,
          'remoteId': remoteId,
          'tournamentId': localId,
          'saveId': data.saveId,
          'name': name,
          'code': fcId(ref['code']),
          'currentDate': data.currentDate,
          'importedAt': now,
          'rawJson': jsonEncode(competition),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await _mirrorWorldTables(
          tx,
          person,
          selected,
          competition,
          data.statisticsTeams ?? data.teams,
          now,
        );
      }
      selected.worldSync[season.id] = FcWorldSyncState(
        competitionIds: compIds,
        ignoredMatchKeys: ignoredKeys,
        preserveOwnPlayers: preserveOwnPlayers,
        bringOwnSquad: bringOwnSquad && !preserveOwnPlayers,
        updateOveralls: updateOveralls,
        importedAt: now,
      );
      await _saveLink(tx, selected);
      onProgress?.call(1);
      return FcWorldImportResult(
        (updateOptions?.competitions ?? true) ? compIds.length : 0,
        teamIds.length,
        localPlayers.length,
        seenFixtures.length,
        importedOwn,
        preserved,
        skipped,
        newPlayers,
        reusedPlayers,
      );
    });
    link.teams.addAll(selected.teams);
    link.players.addAll(selected.players);
    link.competitions.addAll(selected.competitions);
    link.leagues.addAll(selected.leagues);
    link.seasonId = selected.seasonId;
    link.worldSync.addAll(selected.worldSync);
    link.updateOptions = selected.updateOptions;
    await GameCatalog.reloadCustomData();
    return result;
  }

  Future<void> _mirrorWorldTables(
    DatabaseExecutor tx,
    Person person,
    FcScoreLink link,
    FcJson competition,
    List<FcJson> teams,
    String now, {
    bool standingsOnly = false,
  }) async {
    final ref = fcObject(competition['competition']),
        remoteId = fcId(ref['id']);
    final tournamentId = link.competitions[remoteId]!;
    final resultId = 'fcscore-result:${person.id}:${link.seasonId}:$remoteId';
    final old = await tx.query(
      'TournamentResult',
      where: 'id = ?',
      whereArgs: [resultId],
    );
    if (old.isEmpty) {
      await tx.insert('TournamentResult', {
        'id': resultId,
        'personId': person.id,
        'seasonId': link.seasonId,
        'fifaVersion': person.fifaVersion,
        'tournamentId': tournamentId,
        'result': 'Dados importados · Em andamento',
        'isWinner': null,
        'youParticipatedIn': null,
      });
    } else if (old.single['tournamentId'] != tournamentId) {
      await tx.update(
        'TournamentResult',
        {'tournamentId': tournamentId},
        where: 'id = ? AND personId = ?',
        whereArgs: [resultId, person.id],
      );
    }
    final activeTableIds = <String>{};
    for (final (si, stage) in fcList(competition['stages']).indexed) {
      for (final (gi, group) in fcList(stage['groups']).indexed) {
        final tableId =
            'fcscore-table:${person.id}:${link.seasonId}:$remoteId:${fcId(stage['id']).isEmpty ? si : stage['id']}:${fcId(group['id']).isEmpty ? gi : group['id']}';
        activeTableIds.add(tableId);
        final previous = await tx.query(
          'TournamentResultTable',
          where: 'id = ?',
          whereArgs: [tableId],
        );
        if (previous.firstOrNull?['closedAt'] != null) continue;
        await tx.insert('TournamentResultTable', {
          'id': tableId,
          'personId': person.id,
          'seasonId': link.seasonId,
          'fifaVersion': person.fifaVersion,
          'tournamentResultId':
              previous.firstOrNull?['tournamentResultId'] ?? resultId,
          'name':
              '${fcName(ref['name'])} · ${fcName(stage['name'])} · ${fcId(group['code'])}',
          'ownTeamId': link.localClubId,
          'position': si * 100 + gi,
          'createdAt': previous.firstOrNull?['createdAt'] ?? now,
          'updatedAt': now,
          'closedAt': null,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await tx.delete(
          'TournamentResultTableItem',
          where: 'tournamentResultTableId = ? AND personId = ?',
          whereArgs: [tableId, person.id],
        );
        final rowTeams = <String>{};
        for (final row in fcList(group['rows'])) {
          final mapped = link.teams[fcId(fcObject(row['team'])['id'])];
          if (mapped == null) {
            continue;
          }
          if (!rowTeams.add(mapped)) {
            throw const FcScoreException(
              'Uma tabela contém o mesmo time mais de uma vez.',
            );
          }
          final stats = <String, Object?>{
            'points': row['points'],
            'position': row['position'],
            'wins': row['wins'],
            'draws': row['draws'],
            'loses': row['losses'],
            'goalsFor': row['goalsFor'],
            'goalsAgainst': row['goalsAgainst'],
            'matchesPlayed': row['played'],
          };
          if (stats.values.any((v) => fcInt(v) == null || fcInt(v)! < 0)) {
            throw const FcScoreException(
              'Uma classificação contém estatísticas incompletas ou inválidas.',
            );
          }
          await tx.insert('TournamentResultTableItem', {
            'id': '$tableId:$mapped',
            'personId': person.id,
            'seasonId': link.seasonId,
            'fifaVersion': person.fifaVersion,
            'tournamentResultTableId': tableId,
            'teamId': mapped,
            ...stats,
            'knownStats': jsonEncode(
              stats.keys.where((k) => k != 'position').toList(),
            ),
            'createdAt': now,
            'updatedAt': now,
          });
        }
      }
    }
    final previousTables = await tx.query(
      'TournamentResultTable',
      where: 'personId = ? AND seasonId = ? AND tournamentResultId = ?',
      whereArgs: [person.id, link.seasonId, resultId],
    );
    for (final row in previousTables) {
      if (fcId(row['id']).startsWith('fcscore-table:') &&
          row['closedAt'] == null &&
          !activeTableIds.contains(row['id'])) {
        await tx.delete(
          'TournamentResultTableItem',
          where: 'tournamentResultTableId = ?',
          whereArgs: [row['id']],
        );
        await tx.delete(
          'TournamentResultTable',
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
    if (standingsOnly) return;
    await tx.delete(
      'TournamentPlayersResult',
      where: 'personId = ? AND tournamentResultId = ? AND id LIKE ?',
      whereArgs: [person.id, resultId, 'fcscore-scorer:%'],
    );
    final league = RegExp(r'^C(\d+)$').firstMatch(fcId(ref['code']))?.group(1);
    final statistics = fcCompetitionStats(competition, teams);
    final nativePlayers = {
      for (final p in await tx.query(
        'CustomCreatedPlayer',
        columns: ['id'],
        where: 'personId = ?',
        whereArgs: [person.id],
      ))
        fcId(p['id']),
    };
    if (statistics != null) {
      for (final p in statistics) {
        fcValidateStats(
          p,
          source:
              '${fcObject(p['player'])}, equipe ${fcObject(p['team'])}, competição ${fcName(ref['name'])} (ID API: $remoteId)',
        );
        if ((fcInt(p['goals']) ?? 0) <= 0 || fcInt(p['appearances']) == null) {
          continue;
        }
        final pid = fcId(fcObject(p['player'])['id']),
            tid = fcId(fcObject(p['team'])['id']);
        if (fcId(fcObject(p['competition'])['id']) != remoteId ||
            !link.teams.containsKey(tid)) {
          throw const FcScoreException(
            'As estatísticas não correspondem às equipes e competições selecionadas.',
          );
        }
        if (!nativePlayers.contains(link.players[pid])) continue;
        await tx.insert('TournamentPlayersResult', {
          'id':
              'fcscore-scorer:${person.id}:${link.seasonId}:$remoteId:$tid:$pid',
          'personId': person.id,
          'seasonId': link.seasonId,
          'fifaVersion': person.fifaVersion,
          'tournamentResultId': resultId,
          'customPlayerId': link.players[pid],
          'teamId': link.teams[tid],
          'leagueId': league == null ? null : link.leagues[league],
          'type': 'goals',
          'matchesCount': fcInt(p['appearances']),
          'value': fcInt(p['goals']),
          'createdAt': now,
          'updatedAt': now,
        });
      }
      return;
    }
    if (league == null) return;
    for (final team in teams.where(
      (t) => fcId(fcObject(t['league'])['id']) == league,
    )) {
      for (final p in fcList(team['roster'])) {
        if ((fcInt(p['leagueGoals']) ?? 0) <= 0 ||
            fcInt(p['leagueAppearances']) == null ||
            !nativePlayers.contains(link.players[fcId(p['id'])])) {
          continue;
        }
        await tx.insert('TournamentPlayersResult', {
          'id':
              'fcscore-scorer:${person.id}:${link.seasonId}:$remoteId:${team['id']}:${p['id']}',
          'personId': person.id,
          'seasonId': link.seasonId,
          'fifaVersion': person.fifaVersion,
          'tournamentResultId': resultId,
          'customPlayerId': link.players[fcId(p['id'])],
          'teamId': link.teams[fcId(team['id'])],
          'leagueId': link.leagues[league],
          'type': 'goals',
          'matchesCount': fcInt(p['leagueAppearances']),
          'value': fcInt(p['leagueGoals']),
          'createdAt': now,
          'updatedAt': now,
        });
      }
    }
  }
}

Set<String> _ownWorldPlayerIds(FcScoreWorldData data, FcScoreLink link) => {
  for (final team in data.teams)
    if (fcId(team['id']) == link.remoteClubId)
      for (final player in fcList(team['roster'])) fcId(player['id']),
};

Future<List<FcJson>> _readWorldRows(
  List<Map<String, Object?>> rows, {
  bool hideRosters = false,
  bool players = false,
}) => BackgroundData.run(
  _decodeWorldRows,
  (rows: rows, hideRosters: hideRosters, players: players),
  label: 'saved competition data',
  background:
      rows.length >= 128 ||
      rows.fold<int>(
            0,
            (size, row) => size + (row['rawJson'] as String).length,
          ) >=
          65536,
);

List<FcJson> _decodeWorldRows(
  ({List<Map<String, Object?>> rows, bool hideRosters, bool players}) request,
) => [
  for (final row in request.rows)
    _decodeWorldRow(row, request.hideRosters, request.players),
];

FcJson _decodeWorldRow(
  Map<String, Object?> row,
  bool hideRosters,
  bool players,
) {
  final data = fcObject(jsonDecode(row['rawJson'] as String));
  if (players) {
    return {
      ...data,
      'localPlayerId': row['playerId'],
      'localName': row['localName'],
      'customAvatarFilePath': row['customAvatarFilePath'],
      'overall': row['localOverall'] ?? data['overall'],
    };
  }
  if (!hideRosters) return {...row, 'data': data};
  final roster = data.remove('roster');
  return {
    for (final entry in row.entries)
      if (entry.key != 'rawJson') entry.key: entry.value,
    'data': data,
    'rosterCount': roster is List ? roster.whereType<Map>().length : 0,
  };
}
