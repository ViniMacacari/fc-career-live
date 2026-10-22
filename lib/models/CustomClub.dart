class CustomClub {
  const CustomClub({
    required this.id,
    required this.label,
    required this.leagueId,
    required this.fifaVersion,
    this.personId = '',
    this.imageUrl,
    this.imagePath,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id, label, leagueId, fifaVersion;
  final String? personId, imageUrl, imagePath;
  final DateTime createdAt, updatedAt;
  List<String> get fifaVersions => fifaVersion
      .split(',')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();

  factory CustomClub.fromMap(Map<String, Object?> row) => CustomClub(
    id: row['id'] as String,
    label: row['label'] as String,
    leagueId: row['leagueId'] as String,
    fifaVersion: row['fifaVersion'] as String,
    personId: row['personId'] as String?,
    imageUrl: row['imageUrl'] as String?,
    imagePath: row['imagePath'] as String?,
    createdAt: _date(row['createdAt']),
    updatedAt: _date(row['updatedAt']),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'label': label,
    'leagueId': leagueId,
    'imageUrl': imageUrl,
    'imagePath': imagePath,
    'personId': personId ?? '',
    'fifaVersion': fifaVersion,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

DateTime _date(Object? value) => value is String
    ? DateTime.tryParse(value) ?? DateTime(1970)
    : DateTime(1970);
