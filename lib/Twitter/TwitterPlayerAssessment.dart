class TwitterPlayerCriticism {
  const TwitterPlayerCriticism({
    required this.name,
    required this.scope,
    required this.reasons,
    required this.strongSeason,
  });
  final String name, scope;
  final List<String> reasons;
  final bool strongSeason;

  Map<String, Object?> get context => {
    'player': name,
    'scope': scope,
    'reasons': reasons,
    'strongSeason': strongSeason,
  };

  String angle(bool swear) =>
      '${swear ? 'xinga' : 'cobra'} a ${scope == 'recentForm' ? 'má fase recente' : 'atuação de hoje'} de $name'
      ' pelo nome${swear ? ', com palavrão' : ''}: ${reasons.join(', ')}'
      '${scope == 'today' ? '; cobrança pontual, sem transformar este jogo em histórico de fracasso' : ''}'
      '${strongSeason ? '; respeite a boa temporada dele' : ''}';
}

class TwitterPlayerAssessment {
  TwitterPlayerAssessment({required this.performance, required this.history});

  final Map<String, Object?> performance;
  final List<Map<String, Object?>> history;

  num _number(Map<String, Object?> row, String key) => row[key] as num? ?? 0;
  num? _rating(Map<String, Object?> row) => switch (row['rating']) {
    final num r when r > 0 && r <= 10 => r,
    _ => null,
  };

  num get goals => history.fold<num>(0, (sum, r) => sum + _number(r, 'goals'));
  num get assists =>
      history.fold<num>(0, (sum, r) => sum + _number(r, 'assists'));
  List<num> get _ratings => [for (final row in history) ?_rating(row)];
  num? get average => _ratings.isEmpty
      ? null
      : _ratings.reduce((a, b) => a + b) / _ratings.length;

  bool get strongSeason =>
      history.length >= 5 &&
      ((goals + assists) / history.length >= .6 || (average ?? 0) >= 7.4);

  bool get poorRecentForm {
    final recent = history.take(5).toList();
    final ratings = [for (final row in recent) ?_rating(row)];
    return ratings.length >= 3 &&
        ratings.where((r) => r <= 5.9).length >= 3 &&
        ratings.reduce((a, b) => a + b) / ratings.length < 6.3;
  }

  List<String> get reasons => [
    if (_rating(performance) case final r? when r <= 5.9)
      'atuação abaixo do esperado',
    if (_number(performance, 'missedPenalties') > 0)
      'pênalti perdido registrado',
    if (_number(performance, 'ownGoals') > 0) 'gol contra registrado',
  ];

  TwitterPlayerCriticism? criticism(String name) => reasons.isEmpty
      ? null
      : TwitterPlayerCriticism(
          name: name,
          scope: poorRecentForm && (_rating(performance) ?? 10) <= 5.9
              ? 'recentForm'
              : 'today',
          reasons: reasons,
          strongSeason: strongSeason,
        );

  Map<String, Object?> get context => {
    'season': {
      'matches': history.length,
      'goals': goals,
      'assists': assists,
      'averageRating': ?average,
    },
    'strongSeason': strongSeason,
    'poorRecentForm': poorRecentForm,
    'matchCriticismReasons': reasons,
    'criticismScope': reasons.isEmpty
        ? 'none'
        : poorRecentForm && (_rating(performance) ?? 10) <= 5.9
        ? 'recentForm'
        : 'today',
  };

  static TwitterPlayerCriticism? fromContext(String name, Map performance) {
    final assessment = performance['assessment'] as Map?;
    if (assessment == null) return null;
    final reasons = (assessment['matchCriticismReasons'] as List? ?? const [])
        .whereType<String>()
        .toList();
    if (reasons.isEmpty) return null;
    return TwitterPlayerCriticism(
      name: name,
      scope: assessment['criticismScope'] == 'recentForm'
          ? 'recentForm'
          : 'today',
      reasons: reasons,
      strongSeason: assessment['strongSeason'] == true,
    );
  }
}
