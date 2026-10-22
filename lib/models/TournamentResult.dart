class TournamentResult {
  const TournamentResult({
    required this.id,
    required this.seasonId,
    required this.fifaVersion,
    required this.tournamentId,
    required this.result,
    required this.personId,
    this.youParticipatedIn,
    this.isWinner,
    this.playerOfTheTournamentId,
    this.playerOfTheTournamentTeamId,
    this.playerOfTheTournamentLeagueId,
  });

  final String id, seasonId, fifaVersion, tournamentId, result, personId;
  final bool? youParticipatedIn, isWinner;
  final String? playerOfTheTournamentId,
      playerOfTheTournamentTeamId,
      playerOfTheTournamentLeagueId;

  Map<String, Object?> toMap() => {
    'id': id,
    'seasonId': seasonId,
    'fifaVersion': fifaVersion,
    'tournamentId': tournamentId,
    'result': result,
    'personId': personId,
    'youParticipatedIn': youParticipatedIn == null
        ? null
        : (youParticipatedIn! ? 1 : 0),
    'isWinner': isWinner == null ? null : (isWinner! ? 1 : 0),
    'playerOfTheTournamentId': playerOfTheTournamentId,
    'playerOfTheTournamentTeamId': playerOfTheTournamentTeamId,
    'playerOfTheTournamentLeagueId': playerOfTheTournamentLeagueId,
  };

  factory TournamentResult.fromMap(Map<String, Object?> row) =>
      TournamentResult(
        id: row['id'] as String,
        seasonId: row['seasonId'] as String,
        fifaVersion: row['fifaVersion'] as String,
        tournamentId: row['tournamentId'] as String,
        result: row['result'] as String,
        personId: row['personId'] as String,
        youParticipatedIn: row['youParticipatedIn'] == null
            ? null
            : row['youParticipatedIn'] == 1,
        isWinner: row['isWinner'] == null ? null : row['isWinner'] == 1,
        playerOfTheTournamentId: row['playerOfTheTournamentId'] as String?,
        playerOfTheTournamentTeamId:
            row['playerOfTheTournamentTeamId'] as String?,
        playerOfTheTournamentLeagueId:
            row['playerOfTheTournamentLeagueId'] as String?,
      );
}
