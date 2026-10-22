class CustomLeague {
  const CustomLeague({
    required this.id,
    required this.label,
    required this.fifaVersion,
    this.isWoman = false,
    this.imageUrl,
    this.imagePath,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id, label, fifaVersion;
  final bool isWoman;
  final String? imageUrl, imagePath;
  final DateTime createdAt, updatedAt;

  factory CustomLeague.fromMap(Map<String, Object?> row) => CustomLeague(
    id: row['id'] as String,
    label: row['label'] as String,
    fifaVersion: row['fifaVersion'] as String,
    isWoman: row['isWoman'] == 1,
    imageUrl: row['imageUrl'] as String?,
    imagePath: row['imagePath'] as String?,
    createdAt: _date(row['createdAt']),
    updatedAt: _date(row['updatedAt']),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'label': label,
    'imageUrl': imageUrl,
    'imagePath': imagePath,
    'fifaVersion': fifaVersion,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isWoman': isWoman ? 1 : 0,
  };

  List<String> get fifaVersions => fifaVersion.split(',');
}

DateTime _date(Object? value) => value is String
    ? DateTime.tryParse(value) ?? DateTime(1970)
    : DateTime(1970);
