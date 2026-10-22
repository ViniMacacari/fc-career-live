class FixtureTablePosition {
  const FixtureTablePosition({
    this.position,
    this.previous,
    this.inherited = false,
  });

  final int? position, previous;
  final bool inherited;

  int? get change =>
      position == null || previous == null ? null : previous! - position!;

  String get movement => switch (change) {
    null => 'Primeira posição registrada',
    0 => 'Manteve a posição',
    final n when n > 0 => 'Ganhou $n ${n == 1 ? 'posição' : 'posições'}',
    final n => 'Perdeu ${-n} ${n == -1 ? 'posição' : 'posições'}',
  };

  Map<String, Object?> get context => {
    'position': ?position,
    'previousPosition': ?previous,
    'positionChange': ?change,
    if (position != null) 'positionMovement': movement,
    if (inherited) 'positionCarriedForward': true,
  };

  static int? _positive(Object? value) {
    final n = value is num ? value.toInt() : int.tryParse('$value');
    return n != null && n > 0 ? n : null;
  }

  static String? _scope(Map<String, Object?> row) {
    final parts = [
      row['personId'],
      row['seasonId'],
      row['tournamentId'],
      row['playerTeamId'],
    ];
    if (parts.any((p) => p == null || '$p'.isEmpty)) return null;
    return parts.map((p) => '$p').join('\u0000');
  }

  static Map<Object?, FixtureTablePosition> timeline(
    List<Map<String, Object?>> fixtures,
  ) {
    final ordered = fixtures.indexed.toList()
      ..sort((a, b) {
        DateTime date(Map<String, Object?> row, String key) =>
            DateTime.tryParse('${row[key]}') ?? DateTime(0);
        final byDate = date(a.$2, 'date').compareTo(date(b.$2, 'date'));
        if (byDate != 0) return byDate;
        final byCreation = date(
          a.$2,
          'createdAt',
        ).compareTo(date(b.$2, 'createdAt'));
        return byCreation != 0 ? byCreation : b.$1.compareTo(a.$1);
      });
    final last = <String, int>{};
    final result = <Object?, FixtureTablePosition>{};
    for (final (_, row) in ordered) {
      final scope = DateTime.tryParse('${row['date']}') == null
          ? null
          : _scope(row);
      final previous = scope == null ? null : last[scope];
      final recorded = _positive(row['position']);
      final position = recorded ?? previous;
      result[row['id']] = FixtureTablePosition(
        position: position,
        previous: previous,
        inherited: recorded == null && previous != null,
      );
      if (scope != null && position != null) last[scope] = position;
    }
    return result;
  }

  static FixtureTablePosition resolve(
    Map<String, Object?> fixture,
    List<Map<String, Object?>> history,
  ) => timeline([
    if (!history.any((f) => f['id'] == fixture['id'])) fixture,
    for (final row in history) row['id'] == fixture['id'] ? fixture : row,
  ])[fixture['id']]!;

  static List<Map<String, Object?>> carryForward(
    List<Map<String, Object?>> fixtures,
  ) {
    final positions = timeline(fixtures);
    return [
      for (final row in fixtures)
        {...row, 'position': positions[row['id']]?.position},
    ];
  }
}
