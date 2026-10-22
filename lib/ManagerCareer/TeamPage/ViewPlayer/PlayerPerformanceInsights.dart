import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../Graphics/TeamAnalyticsCharts.dart';
import '../../../utils/Components/CareerInsightWidgets.dart';
import '../../../utils/Components/CareerUiStyle.dart';
import 'PlayerAnalysis.dart';
import 'PlayerProfileData.dart';

String _decimal(num? value, [int digits = 1]) =>
    value == null ? '—' : value.toStringAsFixed(digits).replaceAll('.', ',');

class PlayerPerformanceOverview extends StatelessWidget {
  const PlayerPerformanceOverview({
    super.key,
    required this.matches,
    this.title = 'Destaques do jogador',
    this.subtitle = 'Produção nas atuações registradas.',
  });
  final List<PlayerMatchData> matches;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) {
    final numbers = PlayerNumbers(matches), c = CareerUiColors(context);
    final total = numbers.totals;
    final every = numbers.minutesPer(numbers.contributions);
    Widget fact(String label, String value) => Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: c.muted, fontSize: 12)),
        ),
        Text(
          value,
          style: TextStyle(
            color: c.text,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
    return AnalyticsPanel(
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnalysisStrip(
            items: [
              ('${total.matches}', 'Jogos'),
              ('${total.goals}', 'Gols'),
              ('${total.assists}', 'Assist.'),
              (_decimal(total.rating, 2), 'Nota média'),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, box) {
              final width = (box.maxWidth - 20) / 2;
              return Wrap(
                spacing: 20,
                runSpacing: 10,
                children: [
                  for (final (label, value) in [
                    ('Minutos', analysisNumber(total.minutes)),
                    ('Como titular', '${total.starts} de ${total.matches}'),
                    ('Melhor em campo', '${total.motm}'),
                    (
                      "G + A por 90'",
                      analysisNumber(
                        numbers.per90(numbers.contributions),
                        decimals: 2,
                      ),
                    ),
                  ])
                    SizedBox(width: width, child: fact(label, value)),
                ],
              );
            },
          ),
          if (every != null) ...[
            const SizedBox(height: 12),
            Text(
              'Participa de um gol a cada ${every.round()} minutos em campo'
              '${total.ratedMatches < total.matches ? ' · nota em ${total.ratedMatches} de ${total.matches} jogos' : ''}.',
              style: TextStyle(color: c.muted, fontSize: 11.5, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

enum PlayerTrendMetric { rating, contributions, minutes }

List<CareerTrendPoint> playerTrendPoints(
  Iterable<PlayerMatchData> source,
  PlayerTrendMetric metric,
) {
  final matches = source.toList()
    ..sort((a, b) {
      final date = (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0));
      return date != 0 ? date : a.fixtureId.compareTo(b.fixtureId);
    });
  return [
    for (final (i, m) in matches.indexed)
      CareerTrendPoint(
        m.date == null ? '#${i + 1}' : DateFormat('dd/MM').format(m.date!),
        switch (metric) {
          PlayerTrendMetric.rating => m.performance.avgRating,
          PlayerTrendMetric.contributions => m.goals.toDouble(),
          PlayerTrendMetric.minutes => m.minutes.toDouble(),
        },
        other: metric == PlayerTrendMetric.contributions
            ? m.assists.toDouble()
            : null,
        detail: m.date == null
            ? 'Atuação sem data'
            : DateFormat('dd/MM/yyyy').format(m.date!),
      ),
  ];
}

class PlayerPerformanceTrend extends StatefulWidget {
  const PlayerPerformanceTrend({super.key, required this.matches});
  final List<PlayerMatchData> matches;
  @override
  State<PlayerPerformanceTrend> createState() => _PlayerPerformanceTrendState();
}

class _PlayerPerformanceTrendState extends State<PlayerPerformanceTrend> {
  PlayerTrendMetric metric = PlayerTrendMetric.rating;
  bool recent = true;
  @override
  Widget build(BuildContext context) {
    final ordered = widget.matches.toList()
      ..sort(
        (a, b) => (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0)),
      );
    final matches = recent
        ? ordered.skip(math.max(0, ordered.length - 12)).toList()
        : ordered;
    return AnalyticsPanel(
      title: 'Evolução em campo',
      subtitle:
          'Cada ponto representa uma atuação. Toque para ver seus números.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: [
              for (final (option, label) in [
                (PlayerTrendMetric.rating, 'Notas'),
                (PlayerTrendMetric.contributions, 'Gols + assistências'),
                (PlayerTrendMetric.minutes, 'Minutos'),
              ])
                ChoiceChip(
                  key: ValueKey('player-trend-${option.name}'),
                  label: Text(label, style: const TextStyle(fontSize: 11)),
                  selected: metric == option,
                  onSelected: (_) => setState(() => metric = option),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile.adaptive(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Últimas 12 atuações',
                style: TextStyle(fontSize: 11),
              ),
              value: recent,
              onChanged: (value) => setState(() => recent = value),
            ),
          ),
          const SizedBox(height: 10),
          CareerTrendChart(
            key: ValueKey('player-line-${metric.name}'),
            points: playerTrendPoints(matches, metric),
            label: switch (metric) {
              PlayerTrendMetric.rating => 'Nota',
              PlayerTrendMetric.contributions => 'Gols',
              PlayerTrendMetric.minutes => 'Minutos',
            },
            otherLabel: metric == PlayerTrendMetric.contributions
                ? 'Assistências'
                : null,
            maxY: metric == PlayerTrendMetric.rating ? 10 : null,
            emptyMessage: metric == PlayerTrendMetric.rating
                ? 'Adicione notas às atuações para acompanhar a evolução.'
                : 'Nenhuma atuação neste período.',
          ),
        ],
      ),
    );
  }
}
