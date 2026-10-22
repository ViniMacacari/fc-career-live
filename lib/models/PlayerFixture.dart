enum GameLocation { home, away, neutral }

class PlayerFixture {
  const PlayerFixture({
    required this.id,
    required this.personId,
    required this.date,
    required this.fifaVersion,
    required this.playerTeamScore,
    required this.oppositeTeamScore,
    required this.goalsCount,
    required this.assistsCount,
    required this.savesCount,
    required this.yellowCards,
    required this.redCards,
    required this.oppositeTeamId,
    required this.playerTeamId,
    required this.tournamentId,
    required this.seasonId,
    required this.location,
    required this.createdAt,
    required this.updatedAt,
    this.oppositeTeamLeagueId,
    this.playerTeamLeagueId,
    this.rating,
    this.minsPlayed,
    this.stage,
    this.goalsFromPenalty,
    this.shotsOnTarget,
    this.isInjured = false,
    this.isDisqualified = false,
    this.notes,
    this.playerTeamPenaltiesScore,
    this.oppositeTeamPenaltiesScore,
    this.position,
  });

  final String id,
      personId,
      fifaVersion,
      oppositeTeamId,
      playerTeamId,
      tournamentId,
      seasonId;
  final DateTime date, createdAt, updatedAt;
  final int playerTeamScore,
      oppositeTeamScore,
      goalsCount,
      assistsCount,
      savesCount,
      yellowCards,
      redCards;
  final GameLocation location;
  final String? oppositeTeamLeagueId, playerTeamLeagueId, stage, notes;
  final double? rating;
  final int? minsPlayed, goalsFromPenalty, shotsOnTarget;
  final int? playerTeamPenaltiesScore, oppositeTeamPenaltiesScore, position;
  final bool isInjured, isDisqualified;

  Map<String, Object?> toMap() => {
    'id': id,
    'personId': personId,
    'date': date.toIso8601String(),
    'fifaVersion': fifaVersion,
    'playerTeamScore': playerTeamScore,
    'oppositeTeamScore': oppositeTeamScore,
    'rating': rating,
    'goalsCount': goalsCount,
    'assistsCount': assistsCount,
    'savesCount': savesCount,
    'minsPlayed': minsPlayed,
    'yellowCards': yellowCards,
    'redCards': redCards,
    'oppositeTeamLeagueId': oppositeTeamLeagueId,
    'oppositeTeamId': oppositeTeamId,
    'playerTeamLeagueId': playerTeamLeagueId,
    'playerTeamId': playerTeamId,
    'tournamentId': tournamentId,
    'seasonId': seasonId,
    'stage': stage,
    'goalsFromPenalty': goalsFromPenalty,
    'shotsOnTarget': shotsOnTarget,
    'location': location.name,
    'isInjured': isInjured ? 1 : 0,
    'isDisqualified': isDisqualified ? 1 : 0,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'notes': notes,
    'playerTeamPenaltiesScore': playerTeamPenaltiesScore,
    'oppositeTeamPenaltiesScore': oppositeTeamPenaltiesScore,
    'position': position,
  };
}
