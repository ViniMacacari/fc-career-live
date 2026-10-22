import 'dart:convert';

Map<String, Object?> decodePerformanceStats(Object? raw) {
  try {
    final value = raw is String ? jsonDecode(raw) : raw;
    return value is Map ? Map<String, Object?>.from(value) : {};
  } catch (_) {
    return {};
  }
}

class PerformanceStat {
  const PerformanceStat(
    this.key,
    this.label,
    this.group, {
    this.decimals = 0,
    this.numerator,
    this.denominator,
  });
  final String key, label, group;
  final int decimals;
  final String? numerator, denominator;
  bool get percentage => numerator != null;
  num? total(Iterable<Map<String, Object?>> rows) {
    num sum = 0;
    var found = false;
    num base = 0;
    for (final row in rows) {
      final value = row[percentage ? numerator : key];
      if (value is! num || !value.isFinite || value < 0) continue;
      if (percentage) {
        final d = row[denominator];
        if (d is! num || !d.isFinite || d < 0) continue;
        base += d;
      }
      sum += value;
      found = true;
    }
    return !found || (percentage && base == 0)
        ? null
        : percentage
        ? sum * 100 / base
        : sum;
  }
}

const performanceStats = <PerformanceStat>[
  PerformanceStat(
    'npkExpectedGoals',
    'Gols esperados sem pênaltis',
    'Ataque',
    decimals: 2,
  ),
  PerformanceStat(
    'expectedAssists',
    'Assistências esperadas',
    'Ataque',
    decimals: 2,
  ),
  PerformanceStat('npkGoals', 'Gols sem pênalti', 'Ataque'),
  PerformanceStat('fkGoals', 'Gols de falta', 'Ataque'),
  PerformanceStat('shotsOnTarget', 'Finalizações no alvo', 'Ataque'),
  PerformanceStat('shotsOffTargetDerived', 'Finalizações para fora', 'Ataque'),
  PerformanceStat('shotsBlocked', 'Finalizações bloqueadas', 'Ataque'),
  PerformanceStat('secondaryAssist', 'Pré-assistências', 'Ataque'),
  PerformanceStat('assistsFromShots', 'Assistências de finalização', 'Ataque'),
  PerformanceStat('assistsFromDummy', 'Assistências de corta-luz', 'Ataque'),
  PerformanceStat('offsides', 'Impedimentos', 'Ataque'),
  PerformanceStat('cornersWon', 'Escanteios conquistados', 'Ataque'),
  PerformanceStat('penaltiesWon', 'Pênaltis sofridos', 'Ataque'),
  PerformanceStat('passesCompleted', 'Passes certos', 'Passes e criação'),
  PerformanceStat(
    'passesIncompleteDerived',
    'Passes errados',
    'Passes e criação',
  ),
  PerformanceStat(
    'passesUnderPressure',
    'Passes sob pressão',
    'Passes e criação',
  ),
  PerformanceStat(
    'passesCompletedUnderPressure',
    'Passes certos sob pressão',
    'Passes e criação',
  ),
  PerformanceStat(
    'pressurePassAccuracy',
    'Precisão sob pressão',
    'Passes e criação',
    decimals: 1,
    numerator: 'passesCompletedUnderPressure',
    denominator: 'passesUnderPressure',
  ),
  PerformanceStat(
    'crossesAttempted',
    'Cruzamentos tentados',
    'Passes e criação',
  ),
  PerformanceStat('crossesDelivered', 'Cruzamentos certos', 'Passes e criação'),
  PerformanceStat(
    'crossesBlocked',
    'Cruzamentos bloqueados',
    'Passes e criação',
  ),
  PerformanceStat(
    'crossSuccessPctDerived',
    'Precisão de cruzamentos',
    'Passes e criação',
    decimals: 1,
    numerator: 'crossesDelivered',
    denominator: 'crossesAttempted',
  ),
  PerformanceStat(
    'beatWithPass',
    'Adversários superados com passe',
    'Passes e criação',
  ),
  PerformanceStat('offsidePasses', 'Passes em impedimento', 'Passes e criação'),
  PerformanceStat(
    'trackerCompletedThroughPassesIncludingLobbed',
    'Passes em profundidade certos',
    'Passes e criação',
  ),
  PerformanceStat('dribblesCompleted', 'Dribles certos', 'Dribles e posse'),
  PerformanceStat(
    'dribblesFailedDerived',
    'Dribles perdidos',
    'Dribles e posse',
  ),
  PerformanceStat(
    'skillmoveBeats',
    'Adversários superados com finta',
    'Dribles e posse',
  ),
  PerformanceStat('nutmegs', 'Canetas', 'Dribles e posse'),
  PerformanceStat('knockOns', 'Dribles de velocidade', 'Dribles e posse'),
  PerformanceStat('possessionWon', 'Posses recuperadas', 'Dribles e posse'),
  PerformanceStat('possessionLost', 'Posses perdidas', 'Dribles e posse'),
  PerformanceStat('tackledByOpponent', 'Desarmes sofridos', 'Dribles e posse'),
  PerformanceStat('foulsWon', 'Faltas sofridas', 'Dribles e posse'),
  PerformanceStat('interceptions', 'Interceptações', 'Defesa e duelos'),
  PerformanceStat(
    'passesIntercepted',
    'Passes interceptados',
    'Defesa e duelos',
  ),
  PerformanceStat('blocks', 'Bloqueios', 'Defesa e duelos'),
  PerformanceStat('clearances', 'Cortes', 'Defesa e duelos'),
  PerformanceStat('standTackles', 'Desarmes em pé', 'Defesa e duelos'),
  PerformanceStat(
    'standTacklesWon',
    'Desarmes em pé ganhos',
    'Defesa e duelos',
  ),
  PerformanceStat('slideTackles', 'Carrinhos', 'Defesa e duelos'),
  PerformanceStat('slideTacklesWon', 'Carrinhos ganhos', 'Defesa e duelos'),
  PerformanceStat(
    'offenseDuelsAttempted',
    'Duelos ofensivos',
    'Defesa e duelos',
  ),
  PerformanceStat(
    'offenseDuelsWon',
    'Duelos ofensivos ganhos',
    'Defesa e duelos',
  ),
  PerformanceStat(
    'offenseDuelSuccessPctDerived',
    'Duelos ofensivos ganhos %',
    'Defesa e duelos',
    decimals: 1,
    numerator: 'offenseDuelsWon',
    denominator: 'offenseDuelsAttempted',
  ),
  PerformanceStat(
    'defenseDuelsAttempted',
    'Duelos defensivos',
    'Defesa e duelos',
  ),
  PerformanceStat(
    'defenseDuelsWon',
    'Duelos defensivos ganhos',
    'Defesa e duelos',
  ),
  PerformanceStat(
    'defenseDuelSuccessPctDerived',
    'Duelos defensivos ganhos %',
    'Defesa e duelos',
    decimals: 1,
    numerator: 'defenseDuelsWon',
    denominator: 'defenseDuelsAttempted',
  ),
  PerformanceStat('aerialDuelsAttempted', 'Duelos aéreos', 'Defesa e duelos'),
  PerformanceStat('aerialDuelsWon', 'Duelos aéreos ganhos', 'Defesa e duelos'),
  PerformanceStat(
    'aerialDuelSuccessPctDerived',
    'Duelos aéreos ganhos %',
    'Defesa e duelos',
    decimals: 1,
    numerator: 'aerialDuelsWon',
    denominator: 'aerialDuelsAttempted',
  ),
  PerformanceStat('beatenByOpponent', 'Vezes driblado', 'Defesa e duelos'),
  PerformanceStat(
    'beatenInDefensiveThird',
    'Driblado no terço defensivo',
    'Defesa e duelos',
  ),
  PerformanceStat('beatenInBox', 'Driblado na área', 'Defesa e duelos'),
  PerformanceStat('foulsCommitted', 'Faltas cometidas', 'Defesa e duelos'),
  PerformanceStat(
    'penaltiesCommitted',
    'Pênaltis cometidos',
    'Defesa e duelos',
  ),
  PerformanceStat(
    'offsidesCaused',
    'Impedimentos provocados',
    'Defesa e duelos',
  ),
  PerformanceStat('shotsAgainst', 'Finalizações contra', 'Goleiro'),
  PerformanceStat('goalsConceded', 'Gols sofridos em campo', 'Goleiro'),
  PerformanceStat(
    'savingShotsOnTarget',
    'Defesas de chutes no alvo',
    'Goleiro',
  ),
  PerformanceStat(
    'saveSuccessPctDerived',
    'Aproveitamento nas defesas',
    'Goleiro',
    decimals: 1,
    numerator: 'savingShotsOnTarget',
    denominator: 'shotsOnTargetAgainst',
  ),
  PerformanceStat('punches', 'Socos na bola', 'Goleiro'),
  PerformanceStat('divesAtFeet', 'Saídas nos pés', 'Goleiro'),
  PerformanceStat('savingCrosses', 'Cruzamentos defendidos', 'Goleiro'),
  PerformanceStat('savePunchToClearance', 'Socos para afastar', 'Goleiro'),
  PerformanceStat(
    'penaltyGoalsConceded',
    'Gols sofridos de pênalti',
    'Goleiro',
  ),
  PerformanceStat(
    'shootoutGoals',
    'Disputa de pênaltis · convertidos',
    'Disputa de pênaltis',
  ),
  PerformanceStat(
    'shootoutSaves',
    'Disputa de pênaltis · defesas',
    'Disputa de pênaltis',
  ),
  PerformanceStat(
    'shootoutGoalsConceded',
    'Disputa de pênaltis · gols sofridos',
    'Disputa de pênaltis',
  ),
  PerformanceStat(
    'trackerNonSetPieceShots',
    'Finalizações com bola rolando',
    'Ataque',
  ),
  PerformanceStat(
    'standTackleSuccessPctDerived',
    'Desarmes em pé ganhos %',
    'Defesa e duelos',
    decimals: 1,
    numerator: 'standTacklesWon',
    denominator: 'standTackles',
  ),
  PerformanceStat(
    'slideTackleSuccessPctDerived',
    'Carrinhos ganhos %',
    'Defesa e duelos',
    decimals: 1,
    numerator: 'slideTacklesWon',
    denominator: 'slideTackles',
  ),
];
