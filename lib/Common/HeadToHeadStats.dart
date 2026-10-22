import 'FixtureResultTile.dart' show FixtureResult, fixtureResult;

class HeadToHeadStats {
  HeadToHeadStats(Iterable<Map<String, Object?>> fixtures)
    : fixtures = [...fixtures]..sort((a, b) => _date(b).compareTo(_date(a)));

  final List<Map<String, Object?>> fixtures;

  static DateTime _date(Map<String, Object?> f) =>
      DateTime.tryParse('${f['date']}') ?? DateTime(0);

  static int _number(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static DateTime date(Map<String, Object?> f) => _date(f);

  int get games => fixtures.length;

  int _count(FixtureResult result) =>
      fixtures.where((f) => fixtureResult(f) == result).length;

  int get wins => _count(FixtureResult.win);
  int get draws => _count(FixtureResult.draw);
  int get losses => _count(FixtureResult.lose);

  int get goalsFor =>
      fixtures.fold(0, (sum, f) => sum + _number(f['playerTeamScore']));
  int get goalsAgainst =>
      fixtures.fold(0, (sum, f) => sum + _number(f['oppositeTeamScore']));
  int get cleanSheets =>
      fixtures.where((f) => _number(f['oppositeTeamScore']) == 0).length;

  double get pointsShare => games == 0 ? 0 : (wins * 3 + draws) / (games * 3);

  static int goalDifference(Map<String, Object?> f) =>
      _number(f['playerTeamScore']) - _number(f['oppositeTeamScore']);

  Map<String, Object?>? get biggestWin => _widest(1);

  Map<String, Object?>? get biggestLoss => _widest(-1);

  Map<String, Object?>? _widest(int sign) {
    Map<String, Object?>? best;
    for (final f in fixtures) {
      final margin = goalDifference(f) * sign;
      if (margin <= 0) continue;
      final goals = _number(
        f[sign > 0 ? 'playerTeamScore' : 'oppositeTeamScore'],
      );
      if (best == null) {
        best = f;
        continue;
      }
      final bestMargin = goalDifference(best) * sign;
      final bestGoals = _number(
        best[sign > 0 ? 'playerTeamScore' : 'oppositeTeamScore'],
      );
      if (margin > bestMargin || (margin == bestMargin && goals > bestGoals)) {
        best = f;
      }
    }
    return best;
  }

  ({FixtureResult result, int length})? get streak {
    if (fixtures.isEmpty) return null;
    final result = fixtureResult(fixtures.first);
    final length = fixtures.takeWhile((f) => fixtureResult(f) == result).length;
    return (result: result, length: length);
  }

  int get unbeaten =>
      fixtures.takeWhile((f) => fixtureResult(f) != FixtureResult.lose).length;

  int get winless =>
      fixtures.takeWhile((f) => fixtureResult(f) != FixtureResult.win).length;

  Map<String, HeadToHeadStats> by(String Function(Map<String, Object?>) key) {
    final groups = <String, List<Map<String, Object?>>>{};
    for (final f in fixtures) {
      groups.putIfAbsent(key(f), () => []).add(f);
    }
    return {
      for (final MapEntry(key: k, value: v) in groups.entries)
        k: HeadToHeadStats(v),
    };
  }
}
