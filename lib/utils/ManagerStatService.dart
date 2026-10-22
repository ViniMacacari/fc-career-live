import 'databaseUtils.dart';

int? calcPlayerAge({
  required String fifaVersion,
  required DateTime seasonStart,
  required DateTime seasonEnd,
  DateTime? birthdate,
  int? firstSeasonAge,
}) {
  if (fifaVersion == 'FC24' && birthdate != null) {
    final middle = seasonStart.add(
      Duration(days: (seasonEnd.difference(seasonStart).inDays / 2).round()),
    );
    return middle.difference(birthdate).inDays ~/ 365;
  }
  final initial = getInitialSeasonDefaultDate(fifaVersion);
  if (initial != null && firstSeasonAge != null) {
    return firstSeasonAge + seasonStart.year - initial.year;
  }
  if (birthdate == null) return null;
  final beforeBirthday =
      seasonStart.month < birthdate.month ||
      (seasonStart.month == birthdate.month && seasonStart.day < birthdate.day);
  return seasonStart.year - birthdate.year - (beforeBirthday ? 1 : 0);
}
