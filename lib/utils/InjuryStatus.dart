bool isActiveInjury(Map<String, Object?> row, DateTime careerDate) {
  final start = DateTime.tryParse('${row['startDate']}');
  final end = DateTime.tryParse('${row['endDate']}');
  DateTime day(DateTime date) => DateTime(date.year, date.month, date.day);
  final current = day(careerDate);
  return start != null &&
      !day(start).isAfter(current) &&
      (end == null || day(end).isAfter(current));
}
