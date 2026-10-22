enum ManagerHistoryItemType {
  startCareer,
  changeTeam,
  contractChange,
  startNationalTeam,
  endNationalTeam,
  retired,
}

class ManagerCareerHistoryItem {
  const ManagerCareerHistoryItem({
    required this.id,
    required this.date,
    required this.personId,
    required this.fifaVersion,
    required this.type,
    this.fromTeamId,
    this.fromLeagueId,
    this.toTeamId,
    this.toLeagueId,
    this.weeklyWage,
    this.yearlyWage,
    this.nationalTeamId,
    this.taxRate,
    this.rules,
  });
  final String id, personId, fifaVersion;
  final DateTime date;
  final ManagerHistoryItemType type;
  final String? fromTeamId,
      fromLeagueId,
      toTeamId,
      toLeagueId,
      nationalTeamId,
      rules;
  final int? weeklyWage, yearlyWage;
  final double? taxRate;

  Map<String, Object?> toMap() => {
    'id': id,
    'date': date.toIso8601String(),
    'personId': personId,
    'fifaVersion': fifaVersion,
    'fromTeamId': fromTeamId,
    'fromLeagueId': fromLeagueId,
    'toTeamId': toTeamId,
    'toLeagueId': toLeagueId,
    'weeklyWage': weeklyWage,
    'yearlyWage': yearlyWage,
    'nationalTeamId': nationalTeamId,
    'taxRate': taxRate,
    'rules': rules,
    'type': type.name,
  };
}
