import '../models/Season.dart';
import 'FcScoreApi.dart';
import 'FcScoreModels.dart';
import 'FcScoreSeasonStats.dart';
import 'FcScoreUpdateOptions.dart';

class FcScoreWorldData {
  FcScoreWorldData({
    required this.saveId,
    required this.currentDate,
    required this.competitions,
    required this.fixtures,
    required this.teams,
    this.excludedFixtures = 0,
    this.statisticsTeams,
  });
  final String saveId, currentDate;
  final List<FcJson> competitions, fixtures, teams;
  final List<FcJson>? statisticsTeams;
  final int excludedFixtures;
  int get playerCount =>
      teams.fold(0, (n, t) => n + fcList(t['roster']).length);

  FcScoreWorldData forUpdate(FcScoreUpdateOptions options, String ownClubId) =>
      FcScoreWorldData(
        saveId: saveId,
        currentDate: currentDate,
        competitions: competitions,
        fixtures: fixtures,
        excludedFixtures: excludedFixtures,
        statisticsTeams: statisticsTeams ?? teams,
        teams: [
          for (final team in teams)
            {
              ...team,
              if (!(fcId(team['id']) == ownClubId
                  ? options.ownSquad
                  : options.squads))
                'roster': <FcJson>[],
            },
        ],
      );

  static Future<List<FcJson>> statisticsFor(
    FcScoreApi api,
    String saveId,
    String competitionId, {
    void Function(String)? onProgress,
  }) async {
    final records = <FcJson>[];
    final seen = <String>{};
    var offset = 0;
    while (true) {
      onProgress?.call('Buscando estatísticas · ${records.length} jogadores');
      final page = await api.object(
        api.careerPath(saveId, 'stats'),
        query: {
          'competitionId': competitionId,
          'sort': 'goals',
          'limit': '500',
          'offset': '$offset',
        },
      );
      final total = fcInt(page['total']);
      if (page['items'] is! List || total == null || total < 0) {
        throw const FcScoreException(
          'As estatísticas vieram incompletas. Tente novamente.',
        );
      }
      final items = fcList(page['items']);
      for (final row in items) {
        final pid = fcId(fcObject(row['player'])['id']);
        final tid = fcId(fcObject(row['team'])['id']);
        if (pid.isEmpty ||
            tid.isEmpty ||
            fcId(fcObject(row['competition'])['id']) != competitionId ||
            !seen.add('$tid:$pid')) {
          throw const FcScoreException(
            'As estatísticas mudaram durante a leitura. Atualize e tente novamente.',
          );
        }
        fcValidateStats(row);
        records.add({...row}..remove('recentMatches'));
      }
      offset += items.length;
      if (offset >= total) break;
      if (items.isEmpty) {
        throw const FcScoreException(
          'A API não enviou todas as estatísticas. Tente novamente.',
        );
      }
    }
    return records;
  }

  static Future<List<FcJson>> fixturesFor(
    FcScoreApi api,
    String saveId, {
    void Function(String)? onProgress,
  }) async {
    final rows = <FcJson>[];
    final seen = <String>{};
    var offset = 0;
    while (true) {
      onProgress?.call(
        'Buscando calendário de todas as equipes · ${rows.length} jogos',
      );
      final page = await api.object(
        api.careerPath(saveId, 'fixtures'),
        query: {'allTeams': 'true', 'limit': '500', 'offset': '$offset'},
      );
      if (page['items'] is! List || fcInt(page['total']) == null) {
        throw const FcScoreException(
          'O calendário veio incompleto. Tente novamente.',
        );
      }
      final items = fcList(page['items']);
      for (final f in items) {
        final key = FcScoreMatch.fromFixture(f, saveId).remoteKey;
        if (!seen.add(key)) {
          throw const FcScoreException(
            'O calendário mudou durante a leitura. Atualize e tente novamente.',
          );
        }
      }
      rows.addAll(items);
      offset += items.length;
      if (offset >= fcInt(page['total'])!) break;
      if (items.isEmpty) {
        throw const FcScoreException(
          'A API não enviou todo o calendário. Tente novamente.',
        );
      }
    }
    return rows;
  }

  static Future<FcScoreWorldData> load({
    required FcScoreApi api,
    required FcScoreRemoteCareer remote,
    required Season season,
    required List<FcJson> calendar,
    required Set<String> competitionIds,
    FcScoreUpdateOptions? updateOptions,
    void Function(String)? onProgress,
    void Function(double)? onFraction,
  }) async {
    if (competitionIds.isEmpty) {
      throw const FcScoreException('Selecione pelo menos uma competição.');
    }
    final current = DateTime.tryParse(fcId(remote.overview['currentDate']));
    if (current == null ||
        current.isBefore(season.startDate) ||
        current.isAfter(season.endDate)) {
      throw const FcScoreException(
        'Escolha a temporada correspondente à data do save.',
      );
    }
    final competitions = <FcJson>[];
    final teamIds = <String>{};
    var supportsStats = updateOptions?.competitions ?? true;
    for (final id in competitionIds) {
      onFraction?.call(.35 * competitions.length / competitionIds.length);
      onProgress?.call(
        'Buscando tabelas · ${competitions.length + 1}/${competitionIds.length}',
      );
      final c = await api.object(
        api.careerPath(remote.saveId, 'competitions/$id'),
      );
      if (fcId(fcObject(c['competition'])['id']) != id ||
          c['stages'] is! List) {
        throw const FcScoreException(
          'Uma competição veio incompleta. Tente novamente.',
        );
      }
      competitions.add(c);
      if (supportsStats) {
        try {
          final stats = await statisticsFor(
            api,
            remote.saveId,
            id,
            onProgress: onProgress,
          );
          c['playerStats'] = stats;
          c['playerStatsComplete'] = true;
          for (final row in stats) {
            teamIds.add(fcId(fcObject(row['team'])['id']));
          }
        } on FcScoreException catch (e) {
          if (e.status != 404) rethrow;
          supportsStats = false;
        }
      }
      for (final stage in fcList(c['stages'])) {
        for (final group in fcList(stage['groups'])) {
          for (final row in fcList(group['rows'])) {
            final teamId = fcId(fcObject(row['team'])['id']);
            if (teamId.isNotEmpty) teamIds.add(teamId);
          }
        }
      }
    }
    final fixtures = <FcJson>[];
    var excluded = 0;
    for (final f in calendar) {
      final match = FcScoreMatch.fromFixture(f, remote.saveId);
      if (!competitionIds.contains(match.competitionId)) continue;
      if (match.date == null ||
          match.homeId.isEmpty ||
          match.awayId.isEmpty ||
          match.date!.isBefore(season.startDate) ||
          match.date!.isAfter(season.endDate)) {
        excluded++;
        continue;
      }
      fixtures.add(f);
      teamIds.addAll([match.homeId, match.awayId]);
    }
    final teams = <FcJson>[];
    final ids = teamIds.toList()..sort();
    for (var i = 0; i < ids.length; i += 4) {
      onFraction?.call(.35 + .6 * teams.length / ids.length);
      onProgress?.call(
        'Baixando elencos · ${teams.length}/${ids.length} equipes',
      );
      final batch = await Future.wait(
        ids.skip(i).take(4).map((id) async {
          final team = await api.object(
            'saves/${Uri.encodeComponent(remote.saveId)}/teams/$id',
          );
          if (fcId(team['id']) != id || team['roster'] is! List) {
            throw const FcScoreException(
              'Um elenco veio incompleto. Tente novamente.',
            );
          }
          return team;
        }),
      );
      teams.addAll(batch);
    }
    onFraction?.call(.95);
    final fresh = await api.object(api.careerPath(remote.saveId));
    final beforeFile = fcObject(remote.overview['save']),
        afterFile = fcObject(fresh['save']);
    if (fcId(fresh['currentDate']) != fcId(remote.overview['currentDate']) ||
        (beforeFile['modifiedAt'] != null &&
            beforeFile['modifiedAt'] != afterFile['modifiedAt']) ||
        fcId(fcObject(fresh['club'])['id']) != fcId(remote.club['id'])) {
      throw const FcScoreException(
        'O save avançou durante a leitura. Atualize antes de importar.',
      );
    }
    onFraction?.call(1);
    final data = FcScoreWorldData(
      saveId: remote.saveId,
      currentDate: current.toIso8601String().substring(0, 10),
      competitions: competitions,
      fixtures: fixtures,
      teams: teams,
      excludedFixtures: excluded,
    );
    return updateOptions == null
        ? data
        : data.forUpdate(updateOptions, fcId(remote.club['id']));
  }
}
