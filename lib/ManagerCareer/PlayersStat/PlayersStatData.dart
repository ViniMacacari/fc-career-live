import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../models/TeamTransferItem.dart';
import '../../models/Tournament.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/GamePlayers.dart';
import '../../utils/SqlService.dart';
import '../../utils/BackgroundData.dart';
import '../TeamPage/ViewPlayer/PlayerProfileData.dart' show PlayerMatchData;

enum PlayersStatGroup { summary, shooting, teamwork, defense }

enum PlayersStatMetric {
  matches('MP', 'Total de Jogos'),
  starts('S11', 'Jogos no time titular'),
  captainMatches('CAP', 'Jogos como capitão'),
  captainStarts('C11', 'Capitão desde o início'),
  goals('GLS', 'Total de Gols'),
  penalties('GLSP', 'Gols de pênaltis'),
  shots('TOS', 'Chutes'),
  shotAccuracy('SA%', 'Precisão de chutes %', percentage: true),
  assists('AST', 'Assistências'),
  goalsAssists('G+A', 'Total de Gols + Assistências'),
  keyPasses('KEYP', 'Passes-chave'),
  passes('PAS', 'Passes'),
  passAccuracy('PA%', 'Precisão de Passe', percentage: true),
  dribbles('DR', 'Dribles'),
  dribbleAccuracy('SDR%', 'Dribles bem-sucedidos %', percentage: true),
  rating('AR', 'Avaliação', decimal: true),
  motm('MOTM', 'Jogador do Jogo'),
  minutes('MIN', 'Minutos Jogados'),
  tackles('TACK', 'Desarmes'),
  tackleAccuracy('TA%', 'Taxa de desarmes certos %', percentage: true),
  yellowCards('CA', 'Cartões amarelos'),
  redCards('CV', 'Cartões vermelhos'),
  ownGoals('OWG', 'Gols contra'),
  hatTricks('3HT', 'Hat-tricks'),
  saves('SAV', 'Defesas'),
  penaltySaves('PSAV', 'Pênaltis defendidos'),
  cleanSheets('CLN', 'Jogo Sem Sofrer Gols');

  const PlayersStatMetric(
    this.shortLabel,
    this.label, {
    this.percentage = false,
    this.decimal = false,
  });
  final String shortLabel, label;
  final bool percentage, decimal;

  String format(num? value) => value == null
      ? '–'
      : percentage
      ? '${value.toStringAsFixed(1)}%'
      : decimal
      ? value.toStringAsFixed(1)
      : value.toInt().toString();
}

extension PlayersStatGroupDetails on PlayersStatGroup {
  String get label => switch (this) {
    PlayersStatGroup.summary => 'Resumo',
    PlayersStatGroup.shooting => 'Remate',
    PlayersStatGroup.teamwork => 'Jogo em equipe',
    PlayersStatGroup.defense => 'Defesa',
  };
  List<PlayersStatMetric> get metrics => switch (this) {
    PlayersStatGroup.summary => [
      PlayersStatMetric.matches,
      PlayersStatMetric.goals,
      PlayersStatMetric.assists,
      PlayersStatMetric.rating,
      PlayersStatMetric.motm,
      PlayersStatMetric.minutes,
      PlayersStatMetric.captainMatches,
    ],
    PlayersStatGroup.shooting => [
      PlayersStatMetric.matches,
      PlayersStatMetric.goals,
      PlayersStatMetric.penalties,
      PlayersStatMetric.shots,
      PlayersStatMetric.shotAccuracy,
      PlayersStatMetric.hatTricks,
    ],
    PlayersStatGroup.teamwork => [
      PlayersStatMetric.matches,
      PlayersStatMetric.starts,
      PlayersStatMetric.captainMatches,
      PlayersStatMetric.captainStarts,
      PlayersStatMetric.assists,
      PlayersStatMetric.goalsAssists,
      PlayersStatMetric.keyPasses,
      PlayersStatMetric.passes,
      PlayersStatMetric.passAccuracy,
      PlayersStatMetric.dribbles,
      PlayersStatMetric.dribbleAccuracy,
    ],
    PlayersStatGroup.defense => [
      PlayersStatMetric.matches,
      PlayersStatMetric.tackles,
      PlayersStatMetric.tackleAccuracy,
      PlayersStatMetric.yellowCards,
      PlayersStatMetric.redCards,
      PlayersStatMetric.ownGoals,
      PlayersStatMetric.saves,
      PlayersStatMetric.penaltySaves,
      PlayersStatMetric.cleanSheets,
    ],
  };
}

class PlayersStatFilters {
  const PlayersStatFilters({this.seasonId, this.tournamentId, this.teamId});
  final String? seasonId, tournamentId, teamId;
  bool get active => seasonId != null || tournamentId != null || teamId != null;
}

class PlayersStatSort {
  const PlayersStatSort({this.metric, this.descending = true});
  final PlayersStatMetric? metric;
  final bool descending;
}

class PlayersStatTotals {
  PlayersStatTotals(Iterable<PlayerMatchData> source) {
    for (final metric in [
      PlayersStatMetric.matches,
      PlayersStatMetric.starts,
      PlayersStatMetric.goals,
      PlayersStatMetric.assists,
      PlayersStatMetric.goalsAssists,
      PlayersStatMetric.motm,
      PlayersStatMetric.minutes,
      PlayersStatMetric.hatTricks,
      PlayersStatMetric.yellowCards,
      PlayersStatMetric.redCards,
      PlayersStatMetric.cleanSheets,
    ]) {
      values[metric] = 0;
    }
    var penalties = 0;
    var penaltyDetailsKnown = true;
    final averages = <PlayersStatMetric, List<num>>{};
    for (final match in source) {
      final p = match.performance;
      if (match.captaincy.isRecorded) {
        add(PlayersStatMetric.captainMatches, match.wasCaptain ? 1 : 0);
        add(PlayersStatMetric.captainStarts, match.startedCaptain ? 1 : 0);
      }
      add(PlayersStatMetric.matches, 1);
      add(PlayersStatMetric.starts, match.started ? 1 : 0);
      add(PlayersStatMetric.goals, match.goals);
      add(PlayersStatMetric.assists, match.assists);
      add(PlayersStatMetric.goalsAssists, match.goals + match.assists);
      add(PlayersStatMetric.minutes, match.minutes);
      add(PlayersStatMetric.motm, match.manOfTheMatch ? 1 : 0);
      add(PlayersStatMetric.hatTricks, match.goals >= 3 ? 1 : 0);
      add(
        PlayersStatMetric.yellowCards,
        p.yellowCards ?? p.yellowCardDetails.length,
      );
      add(PlayersStatMetric.redCards, p.redCards ?? p.redCardDetails.length);
      add(PlayersStatMetric.shots, p.shotsCount);
      add(PlayersStatMetric.passes, p.passes);
      add(PlayersStatMetric.keyPasses, p.keyPasses);
      add(PlayersStatMetric.dribbles, p.dribbles);
      add(PlayersStatMetric.tackles, p.tackles);
      add(PlayersStatMetric.saves, p.saves);
      add(PlayersStatMetric.penaltySaves, p.penaltySaves);
      if (match.row['ownGoalDetails'] != null) {
        add(PlayersStatMetric.ownGoals, p.ownGoalDetails.length);
      }
      if (match.row['oppositeTeamScore'] != null &&
          match.row['oppositeTeamScore'] == 0) {
        add(PlayersStatMetric.cleanSheets, 1);
      }
      if (match.row['goalDetails'] == null && match.goals > 0) {
        penaltyDetailsKnown = false;
      }
      penalties += p.goalDetails.where((goal) => goal.isPenalty).length;
      for (final (metric, value) in <(PlayersStatMetric, num?)>[
        (PlayersStatMetric.rating, p.avgRating),
        (PlayersStatMetric.shotAccuracy, p.shotAccuracy),
        (PlayersStatMetric.passAccuracy, p.passAccuracy),
        (PlayersStatMetric.dribbleAccuracy, p.dribblesAccuracy),
        (PlayersStatMetric.tackleAccuracy, p.tacklesAccuracy),
      ]) {
        if (value != null) (averages[metric] ??= []).add(value);
      }
    }
    values[PlayersStatMetric.penalties] = penaltyDetailsKnown
        ? penalties
        : null;
    for (final entry in averages.entries) {
      values[entry.key] =
          entry.value.reduce((a, b) => a + b) / entry.value.length;
    }
  }
  final values = <PlayersStatMetric, num?>{};
  void add(PlayersStatMetric metric, num? value) {
    if (value != null) values[metric] = (values[metric] ?? 0) + value;
  }

  num? operator [](PlayersStatMetric metric) => values[metric];
}

class PlayersStatEntry {
  const PlayersStatEntry({
    required this.id,
    required this.player,
    required this.totals,
    required this.departed,
    this.exit,
    this.rosterRow,
    this.realPlayer,
  });
  final String id;
  final Map<String, Object?> player;
  final PlayersStatTotals totals;
  final bool departed;
  final Map<String, Object?>? exit, rosterRow;
  final GamePlayer? realPlayer;
  String get name =>
      player['name']?.toString() ?? realPlayer?.name ?? 'Jogador';
  String? get destinationId => exit?['toTeamId']?.toString();
  String? get destinationLeagueId => exit?['toLeagueId']?.toString();
  int? get exitValue => (exit?['transferValue'] as num?)?.toInt();
}

class PlayersStatData {
  const PlayersStatData({
    required this.seasons,
    required this.players,
    required this.matches,
    required this.roster,
    required this.transfers,
    required this.catalog,
    required this.tournamentNames,
    required this.realPlayers,
    this.careerDate,
  });
  final List<Season> seasons;
  final DateTime? careerDate;
  final List<PlayerMatchData> matches;
  final List<Map<String, Object?>> roster, transfers;
  final Map<String, Map<String, Object?>> players;
  final GameCatalog catalog;
  final Map<String, String> tournamentNames;
  final Map<String, GamePlayer> realPlayers;

  static Future<PlayersStatData> load(Person person, {SqlService? sql}) async {
    final db = sql ?? SqlService.instance;
    await db.applyDueTeamTransfers(person.id);
    final careerDate = await db.getLatestFixtureDate(person.id);
    final results = await Future.wait<Object>([
      db.getSeasons(person.id),
      db.getManagerStatisticsMatchRows(person.id),
      db.getManagerStatisticsRoster(person.id),
      db.getTeamTransfers(person.id),
      GameCatalog.load(),
      db.getCustomTournaments(person.fifaVersion),
    ]);
    final matchRows = results[1] as List<Map<String, Object?>>;
    final roster = results[2] as List<Map<String, Object?>>;
    final transfers = results[3] as List<Map<String, Object?>>;
    final catalog = results[4] as GameCatalog;
    final players = await db.getCustomPlayers(
      person.id,
      playerIds: {
        for (final row in matchRows) row['playerInstanceId'] as String,
        for (final row in roster) row['playerId'] as String,
        for (final row in transfers) row['playerInstanceId'] as String,
      },
    );
    final realPlayers = await GamePlayers.lookup(person.fifaVersion, [
      for (final row in players)
        if (row['realPlayerId'] is String) row['realPlayerId'] as String,
    ]);
    final tournaments = await catalog.tournaments(person.fifaVersion);
    return PlayersStatData(
      careerDate: careerDate,
      seasons: results[0] as List<Season>,
      players: {for (final row in players) row['id'] as String: row},
      matches: await BackgroundData.run(
        _decodeMatches,
        matchRows,
        label: 'player statistics',
        background: matchRows.length >= 128,
      ),
      roster: roster,
      transfers: transfers,
      catalog: catalog,
      tournamentNames: {
        for (final item in tournaments) item.id: item.label,
        for (final item in results[5] as List<Tournament>) item.id: item.name,
      },
      realPlayers: realPlayers,
    );
  }

  static List<PlayerMatchData> _decodeMatches(List<Map<String, Object?>> rows) {
    final matches = <String, Map<String, Object?>>{};
    for (final row in rows) {
      matches.putIfAbsent(
        '${row['playerInstanceId']}/${row['fixtureId']}',
        () => row,
      );
    }
    return matches.values.map(PlayerMatchData.new).toList();
  }

  Set<String> get recordedTournamentIds => {
    for (final match in matches) match.tournamentId,
  };

  Map<String, List<PlayerMatchData>> activities(PlayersStatFilters filters) {
    final result = <String, List<PlayerMatchData>>{};
    for (final m in matches) {
      if ((filters.seasonId == null || m.seasonId == filters.seasonId) &&
          (filters.tournamentId == null ||
              m.tournamentId == filters.tournamentId) &&
          (filters.teamId == null || m.row['playerTeamId'] == filters.teamId)) {
        (result[m.performance.playerInstanceId] ??= []).add(m);
      }
    }
    return result;
  }

  List<PlayerMatchData> activity(String playerId, PlayersStatFilters filters) =>
      matches
          .where(
            (m) =>
                m.performance.playerInstanceId == playerId &&
                (filters.seasonId == null || m.seasonId == filters.seasonId) &&
                (filters.tournamentId == null ||
                    m.tournamentId == filters.tournamentId) &&
                (filters.teamId == null ||
                    m.row['playerTeamId'] == filters.teamId),
          )
          .toList();
  Set<String> recordedTeamIds(Person person) => {
    person.teamId,
    for (final match in matches)
      if (match.row['playerTeamId'] != null)
        match.row['playerTeamId'] as String,
  };

  List<PlayersStatEntry> entries(
    Person person,
    PlayersStatFilters filters,
    PlayersStatSort sort,
  ) {
    final filtered = matches.where(
      (match) =>
          (filters.seasonId == null || match.seasonId == filters.seasonId) &&
          (filters.tournamentId == null ||
              match.tournamentId == filters.tournamentId) &&
          (filters.teamId == null ||
              match.row['playerTeamId'] == filters.teamId),
    );
    final byPlayer = <String, List<PlayerMatchData>>{};
    for (final match in filtered) {
      (byPlayer[match.performance.playerInstanceId] ??= []).add(match);
    }
    if (filters.tournamentId == null &&
        (filters.teamId == null || filters.teamId == person.teamId)) {
      for (final row in roster.where(
        (row) =>
            filters.seasonId == null || row['seasonId'] == filters.seasonId,
      )) {
        byPlayer.putIfAbsent(row['playerId'] as String, () => []);
      }
      for (final row in transfers.where(
        (row) =>
            filters.seasonId == null || row['seasonId'] == filters.seasonId,
      )) {
        byPlayer.putIfAbsent(row['playerInstanceId'] as String, () => []);
      }
    }
    final latestSeasonId = seasons.firstOrNull?.id;
    final referenceSeasonId = roster.firstOrNull?['seasonId'] ?? latestSeasonId;
    final currentRoster = {
      for (final row in roster.where(
        (row) => row['seasonId'] == referenceSeasonId,
      ))
        if (row['departureDate'] == null) row['playerId'] as String: row,
    };
    final lastMovements = <String, Map<String, Object?>>{};
    final gameDates = matches.map((m) => m.date).whereType<DateTime>().toList()
      ..sort((a, b) => b.compareTo(a));
    final gameDate =
        careerDate ?? gameDates.firstOrNull ?? seasons.firstOrNull?.startDate;
    final archivedMovements = [
      for (final row in roster)
        if (row['departureMovement'] is Map)
          Map<String, Object?>.from(row['departureMovement'] as Map),
    ];
    final archivedTransferIds = {
      for (final row in archivedMovements)
        if (row['id'] != null) row['id'],
    };
    final movements =
        <Map<String, Object?>>[
          for (final row in transfers)
            if (!archivedTransferIds.contains(row['id'])) row,
          ...archivedMovements,
        ]..sort(
          (a, b) => (teamTransferEffectiveDate(b) ?? DateTime(0)).compareTo(
            teamTransferEffectiveDate(a) ?? DateTime(0),
          ),
        );
    for (final row in movements) {
      final effective = teamTransferEffectiveDate(row);
      if (gameDate != null &&
          effective != null &&
          DateTime(
            effective.year,
            effective.month,
            effective.day,
          ).isAfter(DateTime(gameDate.year, gameDate.month, gameDate.day))) {
        continue;
      }
      lastMovements.putIfAbsent(row['playerInstanceId'] as String, () => row);
    }
    final result = <PlayersStatEntry>[];
    for (final entry in byPlayer.entries) {
      final player = players[entry.key] ?? <String, Object?>{'id': entry.key};
      final current = currentRoster[entry.key];
      final movement = lastMovements[entry.key];
      final lastWasExit =
          movement != null &&
          !(current != null && movement['rosterDepartureRecord'] == true) &&
          movement['keepInSquad'] != 1 &&
          !isIncomingTeamTransfer(movement, person.teamId);
      final departed =
          current == null || current['loanStatus'] == 'outLoan' || lastWasExit;
      final preferredRoster =
          roster
              .where(
                (row) =>
                    row['playerId'] == entry.key &&
                    (filters.seasonId == null ||
                        row['seasonId'] == filters.seasonId),
              )
              .firstOrNull ??
          roster.where((row) => row['playerId'] == entry.key).firstOrNull;
      result.add(
        PlayersStatEntry(
          id: entry.key,
          player: player,
          totals: PlayersStatTotals(entry.value),
          departed: departed,
          exit: departed && lastWasExit ? movement : null,
          rosterRow: preferredRoster,
          realPlayer: realPlayers[player['realPlayerId']?.toString()],
        ),
      );
    }
    result.sort((a, b) {
      if (a.departed != b.departed) return a.departed ? 1 : -1;
      final metric = sort.metric;
      if (metric != null) {
        final first = a.totals[metric], second = b.totals[metric];
        if (first == null && second != null) return 1;
        if (first != null && second == null) return -1;
        if (first != null && second != null) {
          final value = first.compareTo(second);
          if (value != 0) return sort.descending ? -value : value;
        }
      } else {
        final value = _positionOrder(a.player['positionId']?.toString())
            .compareTo(_positionOrder(b.player['positionId']?.toString()));
        if (value != 0) return value;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  Map<String, Object?> profileRow(PlayersStatEntry entry, String? seasonId) => {
    if (entry.rosterRow != null &&
        (seasonId == null || entry.rosterRow!['seasonId'] == seasonId))
      ...entry.rosterRow!,
    'playerId': entry.id,
    'statisticsReadOnlyRoster':
        entry.departed ||
        entry.rosterRow == null ||
        (seasonId != null && entry.rosterRow!['seasonId'] != seasonId),
    'seasonId':
        seasonId ?? entry.rosterRow?['seasonId'] ?? seasons.firstOrNull?.id,
    'overall': entry.rosterRow?['overall'] ?? entry.player['overall'],
    'customName': entry.name,
    'customPositionId': entry.player['positionId'],
    'customPotential': entry.player['potential'],
    'customFoot': entry.player['foot'],
    'realPlayerId': entry.player['realPlayerId'],
    'fromRealPlayer': entry.player['fromRealPlayer'],
    'customAvatarFilePath': entry.player['customAvatarFilePath'],
    'nationalityId': entry.player['nationalityId'],
    'birthdate': entry.player['birthdate'],
    'playerHeight': entry.player['height'],
    'playerWeight': entry.player['weight'],
    'firstSeasonAge': entry.player['firstSeasonAge'],
  };

  static int _positionOrder(String? position) =>
      const {
        '25': 0,
        '21': 1,
        '27': 2,
        '23': 3,
        '18': 4,
        '14': 5,
        '10': 6,
        '16': 7,
        '12': 8,
        '5': 9,
        '7': 10,
        '8': 11,
        '3': 12,
        '2': 13,
        '0': 14,
      }[position] ??
      15;
}
