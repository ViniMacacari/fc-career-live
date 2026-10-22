enum PersonCategory { player, manager }

class Person {
  const Person({
    required this.id,
    required this.name,
    required this.category,
    required this.fifaVersion,
    required this.leagueId,
    required this.teamId,
    required this.nationalityId,
    required this.createdAt,
    required this.updatedAt,
    this.positionId,
    this.nationalCoachingTeamId,
    this.realPlayerId,
    this.currency,
    this.avatarPathName,
    this.birthdate,
    this.foot,
    this.height,
    this.weight,
    this.promotedYoungPlayersCount,
    this.achievementsInitialized,
  });

  final String id, name, fifaVersion, leagueId, teamId, nationalityId;
  final PersonCategory category;
  final DateTime createdAt, updatedAt;
  final String? positionId,
      nationalCoachingTeamId,
      realPlayerId,
      currency,
      avatarPathName,
      foot;
  final int? birthdate,
      height,
      weight,
      promotedYoungPlayersCount,
      achievementsInitialized;

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'category': category.name,
    'fifaVersion': fifaVersion,
    'positionId': positionId,
    'leagueId': leagueId,
    'teamId': teamId,
    'nationalityId': nationalityId,
    'nationalCoachingTeamId': nationalCoachingTeamId,
    'realPlayerId': realPlayerId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'currency': currency,
    'avatarPathName': avatarPathName,
    'birthdate': birthdate,
    'foot': foot,
    'height': height,
    'weight': weight,
    'promotedYoungPlayersCount': promotedYoungPlayersCount,
    'achievementsInitialized': achievementsInitialized,
  };

  factory Person.fromMap(Map<String, Object?> row) => Person(
    id: row['id'] as String,
    name: row['name'] as String,
    category: PersonCategory.values.byName(row['category'] as String),
    fifaVersion: row['fifaVersion'] as String,
    positionId: row['positionId'] as String?,
    leagueId: row['leagueId'] as String,
    teamId: row['teamId'] as String,
    nationalityId: row['nationalityId'] as String,
    nationalCoachingTeamId: row['nationalCoachingTeamId'] as String?,
    realPlayerId: row['realPlayerId'] as String?,
    createdAt:
        DateTime.tryParse(row['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(row['updatedAt'] as String? ?? '') ?? DateTime.now(),
    currency: row['currency'] as String?,
    avatarPathName: row['avatarPathName'] as String?,
    birthdate: row['birthdate'] as int?,
    foot: row['foot'] as String?,
    height: row['height'] as int?,
    weight: row['weight'] as int?,
    promotedYoungPlayersCount: row['promotedYoungPlayersCount'] as int?,
    achievementsInitialized: row['achievementsInitialized'] as int?,
  );
}
