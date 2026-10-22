class Season {
  const Season({
    required this.id,
    required this.personId,
    required this.startDate,
    required this.endDate,
    required this.createdAt,
    this.closedAt,
    this.recapJson,
  });
  final String id, personId;
  final DateTime startDate, endDate, createdAt;
  final DateTime? closedAt;
  final String? recapJson;
  bool get isClosed => closedAt != null;

  Map<String, Object?> toMap() => {
    'id': id,
    'personId': personId,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'closedAt': closedAt?.toIso8601String(),
    'recapJson': recapJson,
  };

  factory Season.fromMap(Map<String, Object?> row) => Season(
    id: row['id'] as String,
    personId: row['personId'] as String,
    startDate: DateTime.parse(row['startDate'] as String),
    endDate: DateTime.parse(row['endDate'] as String),
    createdAt:
        DateTime.tryParse('${row['createdAt']}') ??
        DateTime.parse(row['startDate'] as String),
    closedAt: DateTime.tryParse('${row['closedAt']}'),
    recapJson: row['recapJson'] as String?,
  );
}
