class Trophy {
  const Trophy({
    required this.id,
    required this.teamId,
    required this.isNational,
    required this.awardId,
    required this.count,
    required this.seasonId,
    required this.personId,
    this.date,
    this.leagueId,
    this.description,
    this.fixtureId,
  });
  final String id, teamId, awardId, seasonId, personId;
  final DateTime? date;
  final String? leagueId, description, fixtureId;
  final bool isNational;
  final int count;

  Map<String, Object?> toMap() => {
    'id': id,
    'date': date?.toIso8601String(),
    'teamId': teamId,
    'leagueId': leagueId,
    'isNational': isNational ? 1 : 0,
    'description': description,
    'awardId': awardId,
    'count': count,
    'seasonId': seasonId,
    'fixtureId': fixtureId,
    'personId': personId,
  };
}
