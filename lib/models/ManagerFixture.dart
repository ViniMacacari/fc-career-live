import 'dart:convert';

import 'ManagerFixturePlayerPerformance.dart';
import 'PlayerFixture.dart';

class ManagerFixture {
  const ManagerFixture({
    required this.id,
    required this.personId,
    required this.date,
    required this.fifaVersion,
    required this.playerTeamScore,
    required this.oppositeTeamScore,
    required this.oppositeTeamId,
    required this.playerTeamId,
    required this.tournamentId,
    required this.seasonId,
    required this.location,
    required this.createdAt,
    required this.updatedAt,
    this.oppositeTeamLeagueId,
    this.playerTeamLeagueId,
    this.stage,
    this.teamPossession,
    this.passAccuracy,
    this.playerTeamShotsCount,
    this.opponentTeamShotsCount,
    this.notes,
    this.playerTeamPenaltiesScore,
    this.oppositeTeamPenaltiesScore,
    this.position,
    this.extraTime = false,
  });

  final String id,
      personId,
      fifaVersion,
      oppositeTeamId,
      playerTeamId,
      tournamentId,
      seasonId;
  final DateTime date, createdAt, updatedAt;
  final int playerTeamScore, oppositeTeamScore;
  final GameLocation location;
  final String? oppositeTeamLeagueId, playerTeamLeagueId, stage, notes;
  final double? teamPossession, passAccuracy;
  final int? playerTeamShotsCount, opponentTeamShotsCount;
  final int? playerTeamPenaltiesScore, oppositeTeamPenaltiesScore, position;
  final bool extraTime;

  Map<String, Object?> toMap() => {
    'id': id,
    'personId': personId,
    'date': date.toIso8601String(),
    'fifaVersion': fifaVersion,
    'playerTeamScore': playerTeamScore,
    'oppositeTeamScore': oppositeTeamScore,
    'oppositeTeamLeagueId': oppositeTeamLeagueId,
    'oppositeTeamId': oppositeTeamId,
    'playerTeamLeagueId': playerTeamLeagueId,
    'playerTeamId': playerTeamId,
    'tournamentId': tournamentId,
    'seasonId': seasonId,
    'stage': stage,
    'teamPossession': teamPossession,
    'passAccuracy': passAccuracy,
    'playerTeamShoutsCount': playerTeamShotsCount,
    'opponentTeamShotsCount': opponentTeamShotsCount,
    'location': location.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'notes': notes,
    'extraTime': extraTime ? 1 : 0,
    'playerTeamPenaltiesScore': playerTeamPenaltiesScore,
    'oppositeTeamPenaltiesScore': oppositeTeamPenaltiesScore,
    'position': position,
  };
}

class OpponentGoalDetails extends PerformanceTimeDetails {
  OpponentGoalDetails({
    super.id,
    super.minute,
    super.addedMinute,
    this.scorerName = '',
    List<GoalType>? type,
    this.isOwnGoal = false,
  }) : type = type ?? [];

  factory OpponentGoalDetails.fromMap(Map<String, dynamic> map) =>
      OpponentGoalDetails(
        id: map['id'] as String?,
        scorerName: map['scorerName'] as String? ?? '',
        minute: (map['minute'] as num?)?.toInt(),
        addedMinute: (map['addedMinute'] as num?)?.toInt(),
        type: decodeGoalTypes(map['type']),
        isOwnGoal: map['isOwnGoal'] == true,
      );

  String scorerName;
  List<GoalType> type;
  bool isOwnGoal;

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'scorerName': scorerName,
    'minute': minute,
    'addedMinute': addedMinute,
    'type': encodeGoalTypes(type),
    'isOwnGoal': isOwnGoal,
  };
}

List<OpponentGoalDetails> decodeOpponentGoals(Object? value) {
  if (value == null) return [];
  final decoded = value is String ? jsonDecode(value) : value;
  if (decoded is! List) return [];
  return decoded
      .whereType<Map>()
      .map(
        (item) => OpponentGoalDetails.fromMap(Map<String, dynamic>.from(item)),
      )
      .toList();
}

String encodeOpponentGoals(List<OpponentGoalDetails> goals) =>
    jsonEncode(goals.map((goal) => goal.toMap()).toList());

class OpponentStats {
  const OpponentStats({
    this.passAccuracy,
    this.yellowCards,
    this.redCards,
    this.ownGoals,
    this.missedPenalties,
    this.injuries,
    this.position,
  });

  factory OpponentStats.decode(Object? value) {
    try {
      final decoded = value is String ? jsonDecode(value) : value;
      if (decoded is! Map) return const OpponentStats();
      int? count(String key) => (decoded[key] as num?)?.toInt();
      return OpponentStats(
        passAccuracy: (decoded['passAccuracy'] as num?)?.toDouble(),
        yellowCards: count('yellowCards'),
        redCards: count('redCards'),
        ownGoals: count('ownGoals'),
        missedPenalties: count('missedPenalties'),
        injuries: count('injuries'),
        position: count('position'),
      );
    } catch (_) {
      return const OpponentStats();
    }
  }

  final double? passAccuracy;
  final int? yellowCards, redCards, ownGoals, missedPenalties, injuries;
  final int? position;

  Map<String, num> toMap() => {
    'passAccuracy': ?passAccuracy,
    'yellowCards': ?yellowCards,
    'redCards': ?redCards,
    'ownGoals': ?ownGoals,
    'missedPenalties': ?missedPenalties,
    'injuries': ?injuries,
    'position': ?position,
  };

  bool get isEmpty => toMap().isEmpty;

  String? encode() => isEmpty ? null : jsonEncode(toMap());
}
