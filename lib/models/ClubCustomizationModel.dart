class ClubCustomizationModel {
  const ClubCustomizationModel({
    required this.id,
    required this.clubName,
    required this.originalTeamId,
    this.originalLeagueId,
    this.imageUrl,
    this.imagePath,
    required this.fifaVersion,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id, clubName, originalTeamId, fifaVersion;
  final String? originalLeagueId, imageUrl, imagePath;
  final DateTime createdAt, updatedAt;

  static String buildId(
    String fifaVersion,
    String? originalLeagueId,
    String originalTeamId,
  ) => '${fifaVersion}_${originalLeagueId ?? 'nat'}_$originalTeamId';

  factory ClubCustomizationModel.fromMap(Map<String, Object?> row) =>
      ClubCustomizationModel(
        id: row['id'] as String,
        clubName: row['clubName'] as String,
        originalTeamId: row['originalTeamId'] as String,
        fifaVersion: row['fifaVersion'] as String,
        originalLeagueId: row['originalLeagueId'] as String?,
        imageUrl: row['imageUrl'] as String?,
        imagePath: row['imagePath'] as String?,
        createdAt: _date(row['createdAt']),
        updatedAt: _date(row['updatedAt']),
      );

  Map<String, Object?> toMap() => {
    'id': id,
    'clubName': clubName,
    'originalTeamId': originalTeamId,
    'imageUrl': imageUrl,
    'imagePath': imagePath,
    'originalLeagueId': originalLeagueId,
    'fifaVersion': fifaVersion,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

DateTime _date(Object? value) => value is String
    ? DateTime.tryParse(value) ?? DateTime(1970)
    : DateTime(1970);
