part of 'FcScoreRepository.dart';

extension FcScoreMatchStandings on FcScoreRepository {
  Future<int> refreshMatchStandings({
    required FcScoreApi api,
    required Person person,
    required FcScoreLink link,
  }) async {
    if (person.id != link.personId ||
        fcVersion(person.fifaVersion) != link.gameVersion) {
      throw const FcScoreException('O vínculo não pertence a esta carreira.');
    }
    final db = await sql.database;
    final previous = await db.query(
      'FcScoreCompetition',
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [person.id, link.seasonId],
    );
    final configured = link.worldSync[link.seasonId]?.competitionIds;
    final rows = previous
        .where(
          (row) =>
              configured == null || configured.contains(fcId(row['remoteId'])),
        )
        .toList();
    if (rows.isEmpty) return 0;
    final seasonRow = (await db.query(
      'Seasons',
      where: 'personId = ? AND id = ?',
      whereArgs: [person.id, link.seasonId],
    )).firstOrNull;
    if (seasonRow == null || Season.fromMap(seasonRow).isClosed) return 0;
    final season = Season.fromMap(seasonRow);
    final overview = await api.object(api.careerPath(link.saveId));
    final remote = FcScoreRemoteCareer(
      gameVersion: link.gameVersion,
      overview: overview,
      squad: [],
      competitions: [],
    );
    if (remote.saveId != link.saveId || !link.belongsTo(remote, person)) {
      throw const FcScoreException(
        'Confira o clube e o save antes de atualizar a classificação.',
      );
    }
    final currentDate = fcId(overview['currentDate']);
    final date = DateTime.tryParse(currentDate);
    if (date == null ||
        date.isBefore(season.startDate) ||
        date.isAfter(season.endDate)) {
      throw const FcScoreException(
        'O save está fora da temporada da classificação.',
      );
    }
    final downloaded = <String, FcJson>{};
    for (final row in rows) {
      final id = fcId(row['remoteId']);
      final data = await api.object(
        api.careerPath(link.saveId, 'competitions/$id'),
      );
      if (fcId(fcObject(data['competition'])['id']) != id ||
          data['stages'] is! List) {
        throw const FcScoreException(
          'Uma classificação veio incompleta. Tente atualizar novamente.',
        );
      }
      downloaded[id] = data;
    }
    final mapped = link.copy();
    for (final team in await db.query(
      'FcScoreWorldTeam',
      columns: ['remoteId', 'teamId'],
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [person.id, link.seasonId],
    )) {
      mapped.teams[fcId(team['remoteId'])] = fcId(team['teamId']);
    }
    final now = DateTime.now().toIso8601String();
    await db.transaction((tx) async {
      for (final row in rows) {
        final id = fcId(row['remoteId']);
        final latest = (await tx.query(
          'FcScoreCompetition',
          where: 'personId = ? AND seasonId = ? AND remoteId = ?',
          whereArgs: [person.id, link.seasonId, id],
        )).single;
        if (fcId(latest['currentDate']).compareTo(currentDate) > 0) {
          throw const FcScoreException(
            'Este save é anterior à classificação já importada.',
          );
        }
        mapped.competitions[id] = fcId(latest['tournamentId']);
        final old = fcObject(jsonDecode(fcId(latest['rawJson'])));
        final data = {
          ...downloaded[id]!,
          for (final key in ['playerStats', 'playerStatsComplete'])
            if (old.containsKey(key)) key: old[key],
        };
        for (final stage in fcList(data['stages'])) {
          for (final group in fcList(stage['groups'])) {
            for (final item in fcList(group['rows'])) {
              final teamId = fcId(fcObject(item['team'])['id']);
              if (teamId.isNotEmpty && !mapped.teams.containsKey(teamId)) {
                throw const FcScoreException(
                  'Uma equipe da classificação ainda não está vinculada. Atualize a configuração da importação.',
                );
              }
            }
          }
        }
        await tx.update(
          'FcScoreCompetition',
          {
            'saveId': link.saveId,
            'currentDate': currentDate,
            'importedAt': now,
            'rawJson': jsonEncode(data),
          },
          where: 'personId = ? AND seasonId = ? AND remoteId = ?',
          whereArgs: [person.id, link.seasonId, id],
        );
        await _mirrorWorldTables(
          tx,
          person,
          mapped,
          data,
          [],
          now,
          standingsOnly: true,
        );
      }
    });
    return rows.length;
  }
}
