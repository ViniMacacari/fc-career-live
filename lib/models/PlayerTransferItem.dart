enum TransferType {
  startCareer,
  startExistingPlayerCareer,
  transwer,
  inloan,
  outloan,
  contractChange,
  retired,
}

class PlayerTransferItem {
  const PlayerTransferItem({
    required this.id,
    required this.transferDate,
    required this.personId,
    required this.fifaVersion,
    required this.type,
    this.fromTeamId,
    this.fromLeagueId,
    this.toTeamId,
    this.toLeagueId,
    this.weeklyWage,
    this.yearlyWage,
    this.overall,
    this.transferValue,
    this.taxRate,
    this.rules,
  });
  final String id, personId, fifaVersion;
  final DateTime transferDate;
  final TransferType type;
  final String? fromTeamId, fromLeagueId, toTeamId, toLeagueId, rules;
  final int? weeklyWage, yearlyWage, overall, transferValue;
  final double? taxRate;

  Map<String, Object?> toMap() => {
    'id': id,
    'transferDate': transferDate.toIso8601String(),
    'personId': personId,
    'fifaVersion': fifaVersion,
    'fromTeamId': fromTeamId,
    'fromLeagueId': fromLeagueId,
    'toTeamId': toTeamId,
    'toLeagueId': toLeagueId,
    'weeklyWage': weeklyWage,
    'yearlyWage': yearlyWage,
    'overall': overall,
    'transferValue': transferValue,
    'taxRate': taxRate,
    'rules': rules,
    'type': type.name,
  };
}
