class Tournament {
  const Tournament({
    required this.id,
    required this.name,
    this.abbreviation,
    this.type,
    this.category,
    this.fifaVersions,
    this.sex,
    this.imageName,
    this.leagueId,
    this.format,
  });
  final String id, name;
  final String? abbreviation,
      type,
      category,
      fifaVersions,
      sex,
      imageName,
      leagueId;

  final String? format;

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'abbreviation': abbreviation,
    'type': type,
    'category': category,
    'fifaVersions': fifaVersions,
    'sex': sex,
    'imageName': imageName,
    'leagueId': leagueId,
    'format': format,
  };

  factory Tournament.fromMap(Map<String, Object?> row) => Tournament(
    id: row['id'] as String,
    name: row['name'] as String,
    abbreviation: row['abbreviation'] as String?,
    type: row['type'] as String?,
    category: row['category'] as String?,
    fifaVersions: row['fifaVersions'] as String?,
    sex: row['sex'] as String?,
    imageName: row['imageName'] as String?,
    leagueId: row['leagueId'] as String?,
    format: row['format'] as String?,
  );
}
