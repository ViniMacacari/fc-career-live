import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../Common/FixturePlayerPerformancePage.dart';
import '../../Common/FixtureResultTile.dart';
import '../../models/MatchPerformanceStats.dart';
import '../../models/Person.dart';
import '../../utils/AppColors.dart';
import '../../utils/Components/CareerInsightWidgets.dart';
import '../../utils/Components/CompactDashboardWidgets.dart';
import '../../utils/Components/PlayerAvatar.dart';
import '../../utils/Components/TeamLogo.dart';
import '../../utils/SqlService.dart';
import '../../utils/databaseUtils.dart';
import '../TeamPage/ViewPlayer/PlayerProfileData.dart';
import '../TeamPage/ViewPlayer/PlayerProfileVisuals.dart'
    show GoalMouth, PitchMap;
import '../TeamPage/ViewPlayer/PlayerScoringInsights.dart'
    show PlayerScoringData;
import '../TeamPage/ViewPlayer/ViewPlayerPage.dart';
import 'PlayerActivityAnalysis.dart';
import 'PlayerStatWidgets.dart';
import 'PlayersStatData.dart';
import 'PlayersStatPageFilterModal.dart';
import 'RecordedPlayerStats.dart';

class PlayerActivityPage extends StatelessWidget {
  const PlayerActivityPage({
    super.key,
    required this.person,
    required this.data,
    required this.entry,
    required this.filters,
    this.sql,
  });
  final Person person;
  final PlayersStatData data;
  final PlayersStatEntry entry;
  final PlayersStatFilters filters;
  final SqlService? sql;

  bool get _keeper => entry.player['positionId'] == '0';
  Widget _avatar(double radius) => PlayerAvatar(
    fifaVersion: person.fifaVersion,
    realPlayerId: entry.player['realPlayerId']?.toString(),
    customAvatarFilePath: entry.player['customAvatarFilePath']?.toString(),
    radius: radius,
  );
  String _opponent(PlayerMatchData m) => data.catalog.teamLabel(
    person.fifaVersion,
    '${m.row['oppositeTeamId']}',
    leagueId: m.row['oppositeTeamLeagueId']?.toString(),
  );
  String _score(PlayerMatchData m) =>
      '${m.row['playerTeamScore'] ?? '—'}–${m.row['oppositeTeamScore'] ?? '—'}';

  void _match(BuildContext context, PlayerMatchData m) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => FixturePlayerPerformancePage(
        name: entry.name,
        team: data.catalog.teamLabel(
          person.fifaVersion,
          '${m.row['playerTeamId'] ?? person.teamId}',
        ),
        match: '${_opponent(m)} · ${_score(m)}',
        avatar: _avatar,
        performance: m.performance,
        date: m.date,
        extraTime: m.row['extraTime'] == 1,
        captain: m.wasCaptain,
        playerOfMatch: m.manOfTheMatch,
      ),
    ),
  );

  static String _number(num value, [int decimals = 2]) =>
      value.toStringAsFixed(decimals).replaceAll('.', ',');

  Widget _hero(BuildContext context, RecordedPlayerStats stats) {
    final c = AppColors.of(context);
    final position = positionShortName(entry.player['positionId']?.toString());
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.accent.withValues(alpha: .25)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(c.accent.withValues(alpha: .14), c.panel),
            c.panel,
          ],
        ),
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _avatar(24),
              if (position.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  position,
                  style: TextStyle(
                    color: c.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StatStrip(
              items: [
                for (final metric in [
                  PlayersStatMetric.matches,
                  _keeper ? PlayersStatMetric.saves : PlayersStatMetric.goals,
                  _keeper
                      ? PlayersStatMetric.cleanSheets
                      : PlayersStatMetric.assists,
                  PlayersStatMetric.rating,
                ])
                  (
                    stats.format(metric),
                    switch (metric) {
                      PlayersStatMetric.assists => 'Assist.',
                      PlayersStatMetric.cleanSheets => 'Sem sofrer',
                      PlayersStatMetric.rating => 'Nota',
                      _ => metric.title,
                    },
                    metric == PlayersStatMetric.rating && stats[metric] != null
                        ? c.accent
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<PlayerStatDatum> _per90(PlayerActivityAnalysis analysis) => [
    for (final metric in [
      _keeper ? PlayersStatMetric.saves : PlayersStatMetric.goals,
      PlayersStatMetric.assists,
      PlayersStatMetric.shots,
      PlayersStatMetric.keyPasses,
      PlayersStatMetric.tackles,
    ])
      if (analysis.per90(metric) case final rate?)
        PlayerStatDatum(
          id: 'per90-${metric.name}',
          label: metric.title,
          value: _number(rate.value),
          metric: metric,
          help:
              '${rate.numerator} × 90 ÷ ${rate.denominator} min, em ${rate.games} jogos com os dois dados.',
        ),
  ];

  List<PlayerStatDatum> _efficiency(PlayerActivityAnalysis analysis) => [
    for (final (id, label, calculation, explanation, icon) in [
      (
        'participation',
        'Participação nos gols do time',
        analysis.goalParticipation,
        '(gols + assistências) ÷ gols do time',
        Icons.sports_soccer,
      ),
      (
        'conversion',
        'Conversão de finalizações',
        analysis.conversion,
        'gols ÷ finalizações',
        Icons.gps_fixed,
      ),
      (
        'starts',
        'Jogos como titular',
        analysis.startRate,
        'titularidades ÷ atuações',
        Icons.groups_outlined,
      ),
    ])
      if (calculation != null)
        PlayerStatDatum(
          id: id,
          label: label,
          value: '${_number(calculation.value, 0)}%',
          icon: icon,
          share: calculation.value / 100,
          help:
              '$explanation: ${calculation.numerator} ÷ ${calculation.denominator}, em ${calculation.games} jogos com os dados.',
        ),
  ];

  Widget? _form(BuildContext context, PlayerActivityAnalysis analysis) {
    final c = AppColors.of(context);
    final recent = analysis.recent;
    final current = analysis.averageRating(recent),
        delta = analysis.ratingChange;
    if (current == null || delta == null) return null;
    final trend = delta >= 0 ? c.success : c.danger;
    Widget cell(String label, Widget value, String help) => Expanded(
      child: Tooltip(
        message: help,
        triggerMode: TooltipTriggerMode.tap,
        showDuration: const Duration(seconds: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: c.muted, fontSize: 11)),
            const SizedBox(height: 3),
            value,
          ],
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.raised.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          cell(
            'Últimos ${recent.length} jogos',
            Text(
              _number(current, 1),
              style: TextStyle(
                color: c.accent,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            'Média das notas cadastradas nas últimas ${recent.length} atuações.',
          ),
          cell(
            'Variação',
            Row(
              children: [
                Icon(
                  delta >= 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 18,
                  color: trend,
                ),
                const SizedBox(width: 4),
                Text(
                  '${delta >= 0 ? '+' : ''}${_number(delta, 1)}',
                  style: TextStyle(
                    color: trend,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            'Média dos últimos ${recent.length} jogos menos a dos ${analysis.previous.length} anteriores.',
          ),
        ],
      ),
    );
  }

  List<Widget> _details(RecordedPlayerStats stats) {
    final sections = <String, List<PlayerStatDatum>>{};
    for (final (title, metrics) in playerActivityMetricGroups) {
      for (final metric in metrics) {
        if (stats[metric] == null) continue;
        if (!_keeper &&
            {
              PlayersStatMetric.saves,
              PlayersStatMetric.penaltySaves,
              PlayersStatMetric.cleanSheets,
            }.contains(metric)) {
          continue;
        }
        final group =
            {
              PlayersStatMetric.yellowCards,
              PlayersStatMetric.redCards,
              PlayersStatMetric.ownGoals,
            }.contains(metric)
            ? 'Disciplina'
            : {
                PlayersStatMetric.saves,
                PlayersStatMetric.penaltySaves,
                PlayersStatMetric.cleanSheets,
              }.contains(metric)
            ? 'Goleiro'
            : title == 'Defesa e disciplina'
            ? 'Defesa'
            : title;
        (sections[group] ??= []).add(playerMetricDatum(stats, metric));
      }
    }
    final rows = stats.matches.map((m) => m.performance.apiStats).toList();
    for (final definition in performanceStats) {
      final value = definition.total(rows);
      if (value == null ||
          (!_keeper && definition.group == 'Goleiro' && value == 0)) {
        continue;
      }
      final group = switch (definition.group) {
        'Passes e criação' || 'Dribles e posse' => 'Criação e posse',
        'Defesa e duelos' => 'Defesa',
        _ => definition.group,
      };
      final count = rows.where((r) => definition.total([r]) != null).length;
      (sections[group] ??= []).add(
        PlayerStatDatum(
          id: definition.key,
          label: _shortLabel(definition),
          value:
              '${_number(value, definition.decimals)}${definition.percentage ? '%' : ''}',
          icon: group == 'Ataque'
              ? Icons.gps_fixed
              : group == 'Defesa'
              ? Icons.shield_outlined
              : Icons.analytics_outlined,
          note: count < stats.matches.length
              ? '$count de ${stats.matches.length} jogos'
              : null,
          help:
              '${definition.label}\n${definition.percentage ? 'Acertos ÷ tentativas nas mesmas partidas.' : 'Total nas atuações do recorte.'}',
        ),
      );
    }
    return [
      for (final section in sections.entries)
        DashboardSection(
          title: section.key,
          child: PlayerStatList(items: section.value),
        ),
    ];
  }

  String _shortLabel(PerformanceStat stat) =>
      const {
        'npkExpectedGoals': 'xG sem pênalti',
        'expectedAssists': 'xA',
        'npkGoals': 'Gols sem pênalti',
        'fkGoals': 'Gols de falta',
        'shotsOnTarget': 'Chutes no alvo',
        'shotsOffTargetDerived': 'Chutes para fora',
        'shotsBlocked': 'Chutes bloqueados',
        'assistsFromShots': 'Assist. de chute',
        'assistsFromDummy': 'Assist. corta-luz',
        'cornersWon': 'Escanteios ganhos',
        'passesUnderPressure': 'Passes sob pressão',
        'passesCompletedUnderPressure': 'Certos sob pressão',
        'pressurePassAccuracy': 'Sob pressão %',
        'crossSuccessPctDerived': 'Cruzamentos %',
        'beatWithPass': 'Superados no passe',
        'trackerCompletedThroughPassesIncludingLobbed': 'Passes profundos',
        'skillmoveBeats': 'Superados em finta',
        'offenseDuelSuccessPctDerived': 'Duelos ataque %',
        'defenseDuelSuccessPctDerived': 'Duelos defesa %',
        'aerialDuelSuccessPctDerived': 'Duelos aéreos %',
        'offenseDuelsAttempted': 'Duelos no ataque',
        'offenseDuelsWon': 'Ganhos no ataque',
        'defenseDuelsAttempted': 'Duelos na defesa',
        'defenseDuelsWon': 'Ganhos na defesa',
        'beatenInDefensiveThird': 'Driblado na defesa',
        'goalsConceded': 'Gols sofridos',
        'savingShotsOnTarget': 'Defesas no alvo',
        'saveSuccessPctDerived': 'Defesas %',
        'penaltyGoalsConceded': 'Gols sofridos · pên.',
        'standTackleSuccessPctDerived': 'Desarmes em pé %',
        'slideTackleSuccessPctDerived': 'Carrinhos %',
        'trackerNonSetPieceShots': 'Chutes bola rolando',
        'shootoutGoals': 'Pênaltis convertidos',
        'shootoutSaves': 'Pênaltis defendidos',
        'shootoutGoalsConceded': 'Pênaltis sofridos',
      }[stat.key] ??
      stat.label;

  Widget _matchRow(
    BuildContext context,
    PlayerMatchData m,
    RecordedPlayerStats record, {
    EdgeInsets padding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 11,
    ),
  }) {
    final c = AppColors.of(context), row = m.row;
    final scored =
        row['playerTeamScore'] != null && row['oppositeTeamScore'] != null;
    final result = fixtureResult(row);
    final color = !scored
        ? c.muted
        : result == FixtureResult.win
        ? c.success
        : result == FixtureResult.lose
        ? c.danger
        : c.warning;
    final minutes = record[PlayersStatMetric.minutes];
    final events = [
      for (final metric in [
        _keeper ? PlayersStatMetric.saves : PlayersStatMetric.goals,
        PlayersStatMetric.assists,
        PlayersStatMetric.yellowCards,
        PlayersStatMetric.redCards,
      ])
        if ((record[metric] ?? 0) > 0)
          PlayerStatBadge(item: playerMetricDatum(record, metric)),
      if (minutes != null)
        PlayerStatBadge(
          item: PlayerStatDatum(
            id: 'minutes',
            label: 'Minutos',
            value: "${minutes.round()}'",
            metric: PlayersStatMetric.minutes,
            help: '',
          ),
        ),
    ];
    return InkWell(
      key: ValueKey('player-match-${m.fixtureId}'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => _match(context, m),
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            TeamLogo.lookup(
              fifaVersion: person.fifaVersion,
              teamId: '${row['oppositeTeamId']}',
              leagueId: row['oppositeTeamLeagueId']?.toString(),
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _opponent(m),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (m.date != null)
                        DateFormat('dd/MM/yy').format(m.date!),
                      ?data.tournamentNames[m.tournamentId],
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 11),
                  ),
                  if (events.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 12, runSpacing: 4, children: events),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  scored ? _score(m) : '—',
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                RatingPill(m.performance.avgRating, size: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: AppColors.of(context).muted),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final analysis = PlayerActivityAnalysis(data.activity(entry.id, filters)),
        matches = analysis.matches;
    final stats = RecordedPlayerStats(matches), c = AppColors.of(context);
    final scope = [
      playersStatFilterLabel(playersStatSeasonOptions(data), filters.seasonId),
      if (filters.tournamentId != null)
        data.tournamentNames[filters.tournamentId] ?? 'Competição',
      if (filters.teamId != null)
        data.catalog.teamLabel(person.fifaVersion, filters.teamId!),
      if (entry.departed) 'Fora do elenco',
    ].join(' · ');
    final rated = matches
        .where((m) => m.performance.avgRating != null)
        .toList();
    final best = rated.isEmpty
        ? null
        : rated.reduce(
            (a, b) =>
                b.performance.avgRating! > a.performance.avgRating! ? b : a,
          );
    final chronological = rated.reversed.toList();
    final scoring = PlayerScoringData(
      matches
          .where(
            (m) =>
                m.row['goalDetails'] != null &&
                m.performance.goalsCount != null &&
                m.performance.goalDetails.length == m.performance.goalsCount,
          )
          .toList(),
    );
    final per90 = _per90(analysis), efficiency = _efficiency(analysis);
    final form = _form(context, analysis);
    final details = _details(stats);
    const padding = EdgeInsets.fromLTRB(16, 16, 16, 28);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                scope,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Ver perfil',
              icon: const Icon(Icons.person_outline),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => ViewPlayerPage(
                    person: person,
                    row: data.profileRow(entry, filters.seasonId),
                    realPlayer: entry.realPlayer,
                    sql: sql,
                  ),
                ),
              ),
            ),
          ],
          bottom: TabBar(
            tabs: [
              for (final label in ['Resumo', 'Estatísticas', 'Partidas'])
                Tab(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label, maxLines: 1),
                  ),
                ),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: TabBarView(
            children: [
              ListView(
                key: const ValueKey('player-activity-summary'),
                padding: padding,
                children: [
                  _hero(context, stats),
                  if (matches.isEmpty)
                    _empty(context, 'Nenhuma atuação neste recorte.'),
                  if (rated.isNotEmpty)
                    DashboardSection(
                      title: 'Notas por partida',
                      subtitle: 'Toque em um ponto para ver a partida.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CareerTrendChart(
                            label: 'Nota',
                            maxY: 10,
                            format: (v) => _number(v, 1),
                            points: [
                              for (final m in chronological)
                                CareerTrendPoint(
                                  m.date == null
                                      ? '—'
                                      : DateFormat('dd/MM').format(m.date!),
                                  m.performance.avgRating,
                                  detail: '${_opponent(m)} ${_score(m)}',
                                ),
                            ],
                          ),
                          if (form != null) ...[
                            const SizedBox(height: 12),
                            form,
                          ],
                        ],
                      ),
                    ),
                  if (best != null)
                    DashboardSection(
                      title: 'Melhor atuação',
                      child: _matchRow(
                        context,
                        best,
                        RecordedPlayerStats([best]),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                      ),
                    ),
                  if (per90.isNotEmpty)
                    DashboardSection(
                      title: 'Por 90 minutos',
                      child: PlayerStatList(items: per90),
                    ),
                  if (efficiency.isNotEmpty)
                    DashboardSection(
                      title: 'Eficiência',
                      child: PlayerStatList(items: efficiency),
                    ),
                ],
              ),
              ListView(
                key: const ValueKey('player-activity-statistics'),
                padding: padding,
                children: [
                  if (details.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                      child: Text(
                        'Toque em um dado para ver como ele é calculado.',
                        style: TextStyle(color: c.muted, fontSize: 11),
                      ),
                    ),
                  ...details,
                  if (scoring.goalLocations.isNotEmpty)
                    DashboardSection(
                      title: 'Destino dos gols',
                      child: GoalMouth(locations: scoring.goalLocations),
                    ),
                  if (scoring.fieldLocations.isNotEmpty)
                    DashboardSection(
                      title: 'Origem dos gols',
                      child: PitchMap(locations: scoring.fieldLocations),
                    ),
                  if (matches.isEmpty)
                    _empty(context, 'Nenhuma estatística neste recorte.'),
                ],
              ),
              matches.isEmpty
                  ? _empty(context, 'Nenhuma atuação neste recorte.')
                  : ListView.separated(
                      padding: padding,
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => Material(
                        color: c.panel,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: c.line.withValues(alpha: .55),
                          ),
                        ),
                        child: _matchRow(
                          context,
                          matches[index],
                          analysis.records[index],
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
