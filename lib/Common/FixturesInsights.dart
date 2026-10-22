import 'package:flutter/material.dart';

import '../ManagerCareer/Graphics/TeamAnalyticsCharts.dart';
import '../ManagerCareer/Graphics/TeamAnalyticsData.dart';
import '../utils/Components/CareerInsightWidgets.dart';
import '../utils/Components/CareerUiStyle.dart';
import '../utils/Components/ManagerFormStyle.dart';

class FixturesInsights extends StatefulWidget {
  const FixturesInsights({
    super.key,
    required this.rows,
    required this.onOpen,
    required this.charts,
  });
  final List<Map<String, Object?>> rows;
  final ValueChanged<Map<String, Object?>> onOpen;
  final bool charts;
  @override
  State<FixturesInsights> createState() => _FixturesInsightsState();
}

class _FixturesInsightsState extends State<FixturesInsights> {
  AnalyticsMetric metric = AnalyticsMetric.goals;
  String chart = 'evolution';
  @override
  Widget build(BuildContext context) {
    final data = TeamAnalytics.fromRows(widget.rows),
        c = CareerUiColors(context);
    if (data.played == 0) return const SizedBox.shrink();
    final byLocation = <String, TeamAnalytics>{
      for (final location in ['home', 'away', 'neutral'])
        if (data.matches.any((m) => m.location == location))
          location: TeamAnalytics(
            data.matches.where((m) => m.location == location),
          ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.charts)
          AnalyticsPanel(
            title: 'Raio-X dos jogos',
            subtitle: '${data.played} partidas no recorte selecionado.',
            child: Column(
              children: [
                InsightStatGrid(
                  items: [
                    (
                      '${data.goalsFor}',
                      'Gols marcados',
                      Icons.sports_soccer_rounded,
                      c.green,
                    ),
                    (
                      '${data.goalsAgainst}',
                      'Gols sofridos',
                      Icons.shield_outlined,
                      c.red,
                    ),
                    (
                      '${data.balance > 0 ? '+' : ''}${data.balance}',
                      'Saldo de gols',
                      Icons.swap_vert_rounded,
                      c.accent,
                    ),
                    (
                      '${data.cleanSheets}',
                      'Jogos sem sofrer gol',
                      Icons.lock_outline_rounded,
                      c.amber,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '${data.scoredPerGame.toStringAsFixed(2).replaceAll('.', ',')} gol(s) marcado(s) por jogo'
                  ' · ${data.longestUnbeaten} jogo(s) na maior sequência invicta.',
                  style: TextStyle(color: c.muted, fontSize: 11, height: 1.6),
                ),
                const SizedBox(height: 12),
                Text(
                  '${data.efficiency.toStringAsFixed(1).replaceAll('.', ',')}% de aproveitamento'
                  ' · ${data.points} pontos no período. Placar antes dos pênaltis.',
                  style: TextStyle(color: c.muted, fontSize: 11, height: 1.6),
                ),
              ],
            ),
          ),
        if (widget.charts) ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('fixtures-chart'),
            initialValue: chart,
            isExpanded: true,
            decoration: managerFieldDecoration(
              context,
              'Gráfico',
              icon: Icons.insights_rounded,
            ),
            items: const [
              DropdownMenuItem(
                value: 'evolution',
                child: Text('Evolução do time'),
              ),
              DropdownMenuItem(
                value: 'results',
                child: Text('Distribuição de resultados'),
              ),
              DropdownMenuItem(
                value: 'location',
                child: Text('Dentro e fora de casa'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => chart = value);
            },
          ),
          const SizedBox(height: 16),
        ],
        if (widget.charts && chart == 'evolution')
          AnalyticsPanel(
            title: 'Como o time evoluiu',
            subtitle: 'Toque no gráfico para abrir a partida. Médias em janelas de até cinco jogos.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    for (final option in [
                      AnalyticsMetric.goals,
                      AnalyticsMetric.form,
                      AnalyticsMetric.balance,
                    ])
                      ChoiceChip(
                        label: Text(
                          option.label,
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected: metric == option,
                        onSelected: (_) => setState(() => metric = option),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                AnalyticsEvolutionChart(
                  data: data,
                  metric: metric,
                  onSelected: (m) => widget.onOpen(m.row),
                ),
              ],
            ),
          ),
        if (widget.charts && chart == 'results')
          AnalyticsPanel(
            title: 'Resultados do período',
            subtitle: 'Resultados e aproveitamento consideram o placar antes dos pênaltis.',
            child: AnalyticsResultsChart(data: data),
          ),
        if (widget.charts && chart == 'location' && byLocation.isNotEmpty) ...[
          AnalyticsPanel(
            title: 'Dentro e fora de casa',
            subtitle: 'Gols marcados e sofridos por partida em cada mando.',
            child: AnalyticsBars(
              groups: byLocation,
              goals: true,
              label: (location) => switch (location) {
                'home' => 'Em casa',
                'away' => 'Fora',
                _ => 'Neutro',
              },
            ),
          ),
        ],
      ],
    );
  }
}
