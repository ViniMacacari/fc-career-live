import 'dart:convert';

class TransferPreviousClubStats {
  const TransferPreviousClubStats({
    required this.asOfDate,
    this.matches,
    this.goals,
    this.assists,
    this.averageRating,
    this.notes,
  });

  final DateTime asOfDate;
  final int? matches, goals, assists;
  final double? averageRating;
  final String? notes;
  bool get hasInformation =>
      matches != null ||
      goals != null ||
      assists != null ||
      averageRating != null ||
      (notes?.trim().isNotEmpty ?? false);

  Map<String, Object?> toMap() => {
    'asOfDate': asOfDate.toIso8601String(),
    if (matches != null) 'matches': matches,
    if (goals != null) 'goals': goals,
    if (assists != null) 'assists': assists,
    if (averageRating != null) 'averageRating': averageRating,
    if (notes?.trim().isNotEmpty ?? false) 'notes': notes!.trim(),
  };
  String encode() => jsonEncode(toMap());

  static TransferPreviousClubStats? decode(Object? source) {
    if (source == null) return null;
    try {
      final decoded = source is String ? jsonDecode(source) : source;
      if (decoded is! Map) return null;
      final date = DateTime.tryParse('${decoded['asOfDate'] ?? ''}');
      if (date == null) return null;
      int? count(String field) {
        final value = decoded[field];
        if (value == null) return null;
        if (value is! num ||
            !value.isFinite ||
            value < 0 ||
            value != value.toInt()) {
          throw const FormatException('Contagem inválida.');
        }
        return value.toInt();
      }

      final rating = decoded['averageRating'];
      if (rating != null &&
          (rating is! num || !rating.isFinite || rating < 0 || rating > 10)) {
        return null;
      }
      final result = TransferPreviousClubStats(
        asOfDate: date,
        matches: count('matches'),
        goals: count('goals'),
        assists: count('assists'),
        averageRating: (rating as num?)?.toDouble(),
        notes: decoded['notes'] is String
            ? (decoded['notes'] as String).trim()
            : null,
      );
      return result.hasInformation ? result : null;
    } on FormatException {
      return null;
    }
  }

  bool availableAt(DateTime date) => !DateTime(
    asOfDate.year,
    asOfDate.month,
    asOfDate.day,
  ).isAfter(DateTime(date.year, date.month, date.day));

  String summary(String club) => [
    'no clube anterior ($club), na temporada da contratação até '
        '${asOfDate.day.toString().padLeft(2, '0')}/${asOfDate.month.toString().padLeft(2, '0')}/${asOfDate.year}',
    if (matches != null) '$matches jogos',
    if (goals != null) '$goals gols',
    if (assists != null) '$assists assistências',
    if (averageRating != null)
      'nota média ${averageRating!.toStringAsFixed(1)}',
    if (notes?.trim().isNotEmpty ?? false) notes!.trim(),
  ].join(', ');
}
