import '../../../models/FixtureCaptaincy.dart';
import '../../../models/ManagerFixturePlayerPerformance.dart';
import '../../../models/Person.dart';
import '../../../models/Season.dart';
import '../../../utils/GameCatalog.dart';
import '../../../utils/SqlService.dart';
import '../../../utils/managerPlayerMinutesUtils.dart';

int? _number(Object? value) => value is num ? value.toInt() : null;

class PlayerMatchData {
  PlayerMatchData(this.row)
    : performance = ManagerFixturePlayerPerformance.fromMap(row);

  final Map<String, Object?> row;
  final ManagerFixturePlayerPerformance performance;
  String get seasonId => row['seasonId']?.toString() ?? '';
  String get tournamentId => row['tournamentId']?.toString() ?? '';
  String get fixtureId => row['fixtureId']?.toString() ?? '';
  DateTime? get date => DateTime.tryParse(row['date']?.toString() ?? '');
  int get minutes => getManagerPlayerPlayedMinutes(
    performance,
    getManagerFixtureDurationMinutes(
      extraTime: row['extraTime'] == 1,
      performance: performance,
    ),
  );
  bool get started =>
      performance.recordedStarted ??
      !performance.substitutionDetails.any(
        (item) => item.type == SubstitutionType.inGame,
      );
  bool get manOfTheMatch =>
      row['playerOfTheMatchId'] == performance.playerInstanceId &&
      row['isPotmFromMyTeam'] == 1;
  int get goals => performance.goalsCount ?? 0;
  int get assists => performance.assistsCount ?? 0;
  FixtureCaptaincy get captaincy => FixtureCaptaincy.decode(row['captaincy']);
  bool get startedCaptain =>
      captaincy.initialPlayerId == performance.playerInstanceId;
  bool get wasCaptain =>
      startedCaptain ||
      captaincy.handovers.any(
        (h) => h.playerId == performance.playerInstanceId,
      );
}

class PlayerTotals {
  PlayerTotals(Iterable<PlayerMatchData> source) {
    for (final match in source) {
      matches++;
      if (match.started) starts++;
      if (match.manOfTheMatch) motm++;
      if (match.captaincy.isRecorded) hasCaptaincy = true;
      if (match.wasCaptain) captainGames++;
      if (match.startedCaptain) captainStarts++;
      if (match.wasCaptain && !match.startedCaptain) captainInherited++;

      minutes += match.minutes;
      goals += match.goals;
      assists += match.assists;
      yellowCards += match.performance.yellowCards ?? 0;
      redCards += match.performance.redCards ?? 0;
      penalties += match.performance.goalDetails
          .where((goal) => goal.isPenalty)
          .length;
      if (match.row['goalDetails'] != null) {
        hasGoalDetails = true;
      }
      shots += match.performance.shotsCount ?? 0;
      passes += match.performance.passes ?? 0;
      keyPasses += match.performance.keyPasses ?? 0;
      tackles += match.performance.tackles ?? 0;
      dribbles += match.performance.dribbles ?? 0;
      saves += match.performance.saves ?? 0;
      if (match.performance.shotsCount != null) hasShots = true;
      if (match.performance.passes != null) hasPasses = true;
      if (match.performance.tackles != null) hasTackles = true;
      final rating = match.performance.avgRating;
      if (rating != null) {
        ratingSum += rating;
        ratedMatches++;
      }
    }
    if (goals == 0) hasGoalDetails = true;
  }
  int matches = 0, starts = 0, motm = 0, minutes = 0;
  int goals = 0, assists = 0, yellowCards = 0, redCards = 0;
  int penalties = 0, shots = 0, passes = 0, keyPasses = 0;
  int tackles = 0, dribbles = 0, saves = 0;
  int ratedMatches = 0;
  int captainGames = 0, captainStarts = 0, captainInherited = 0;
  bool hasCaptaincy = false;
  double ratingSum = 0;
  bool hasShots = false, hasPasses = false, hasTackles = false;
  bool hasGoalDetails = false;
  double? get rating => ratedMatches == 0 ? null : ratingSum / ratedMatches;
  String get ratingLabel => rating?.toStringAsFixed(1) ?? '–';
  String perGame(int value) =>
      matches == 0 ? '–' : (value / matches).toStringAsFixed(2);
  String minutesPer(int value) =>
      value == 0 ? '–' : (minutes / value).toStringAsFixed(2);
}

class PlayerProfileData {
  const PlayerProfileData({
    required this.seasons,
    required this.matches,
    required this.overalls,
    required this.marketValues,
    required this.contracts,
    required this.tournamentNames,
  });
  final List<Season> seasons;
  final List<PlayerMatchData> matches;
  final List<Map<String, Object?>> overalls, marketValues, contracts;
  final Map<String, String> tournamentNames;

  static Future<PlayerProfileData> load(
    Person person,
    String playerId, {
    SqlService? sql,
  }) async {
    final db = sql ?? SqlService.instance;
    final seasonsTask = db.getSeasons(person.id);
    final matchesTask = db.getPlayerMatchRows(person.id, playerId);
    final overallsTask = db.getPlayerHistory(person.id, playerId, 'Overall');
    final marketTask = db.getPlayerHistory(person.id, playerId, 'MarketValue');
    final contractsTask = db.getPlayerHistory(
      person.id,
      playerId,
      'ContractItem',
    );
    final catalogTask = GameCatalog.load();
    final customTask = db.getCustomTournaments(person.fifaVersion);
    final catalog = await catalogTask;
    final tournaments = await catalog.tournaments(person.fifaVersion);
    final custom = await customTask;
    return PlayerProfileData(
      seasons: await seasonsTask,
      matches: (await matchesTask).map(PlayerMatchData.new).toList(),
      overalls: await overallsTask,
      marketValues: await marketTask,
      contracts: await contractsTask,
      tournamentNames: {
        for (final tournament in tournaments) tournament.id: tournament.label,
        for (final tournament in custom) tournament.id: tournament.name,
      },
    );
  }

  List<PlayerMatchData> filtered({String? seasonId, String? tournamentId}) =>
      matches
          .where(
            (match) =>
                (seasonId == null || match.seasonId == seasonId) &&
                (tournamentId == null || match.tournamentId == tournamentId),
          )
          .toList();

  PlayerTotals totals({String? seasonId, String? tournamentId}) =>
      PlayerTotals(filtered(seasonId: seasonId, tournamentId: tournamentId));

  Map<int, double> monthlyRatings(String seasonId) {
    final groups = <int, List<double>>{};
    for (final match in filtered(seasonId: seasonId)) {
      final month = match.date?.month;
      final rating = match.performance.avgRating;
      if (month != null && rating != null) {
        (groups[month] ??= []).add(rating);
      }
    }
    return {
      for (final entry in groups.entries)
        entry.key: entry.value.reduce((a, b) => a + b) / entry.value.length,
    };
  }

  int? get latestOverall {
    return _number(overalls.firstOrNull?['overall']);
  }

  int? get latestMarketValue =>
      marketValues.isEmpty ? null : _number(marketValues.first['value']);
}
