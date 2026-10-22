import '../../utils/AppColors.dart';

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'TeamAnalyticsData.dart';

class AnalyticsColors {
  AnalyticsColors(BuildContext context) {
    final c = AppColors.of(context);
    panel = c.panel;
    text = c.text;
    muted = c.muted;
    blue = c.accent;
    green = c.success;
    red = c.danger;
    amber = c.warning;
    line = c.line.withValues(alpha: .55);
  }
  late final Color panel, text, muted, blue, green, red, amber, line;
}

class AnalyticsPanel extends StatelessWidget {
  const AnalyticsPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });
  final String title, subtitle;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final c = AnalyticsColors(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: TextStyle(color: c.muted, fontSize: 11, height: 1.5),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

Widget analyticsLegend(String text, Color color) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
    const SizedBox(width: 6),
    Flexible(
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
    ),
  ],
);

class AnalyticsEvolutionChart extends StatelessWidget {
  const AnalyticsEvolutionChart({
    super.key,
    required this.data,
    required this.metric,
    required this.onSelected,
  });
  final TeamAnalytics data;
  final AnalyticsMetric metric;
  final ValueChanged<AnalyticsMatch> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = AnalyticsColors(context);
    final points = data.evolution(metric);
    final values = [
      for (final p in points) ...[?p.value, ?p.other],
    ];
    if (values.isEmpty) {
      return const SizedBox(
        height: 190,
        child: Center(
          child: Text(
            'Registre a posse de bola nas partidas\npara acompanhar esta evolução.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final low = math.min(0.0, values.reduce(math.min));
    final high =
        metric == AnalyticsMetric.form || metric == AnalyticsMetric.possession
        ? 100.0
        : math.max(1.0, values.reduce(math.max) * 1.18);
    final interval =
        metric == AnalyticsMetric.form || metric == AnalyticsMetric.possession
        ? 25.0
        : math.max(1.0, ((high - low) / 4).ceilToDouble());
    LineChartBarData bar(Color color, bool secondary) => LineChartBarData(
      color: color,
      barWidth: 3,
      isCurved: false,
      spots: [
        for (var i = 0; i < points.length; i++)
          (secondary ? points[i].other : points[i].value) == null
              ? FlSpot.nullSpot
              : FlSpot(
                  i.toDouble(),
                  (secondary ? points[i].other : points[i].value)!,
                ),
      ],
      dotData: FlDotData(show: points.length < 12),
      belowBarData: BarAreaData(
        show: !secondary,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .22), color.withValues(alpha: 0)],
        ),
      ),
    );
    final first = bar(c.blue, false);
    final suffix =
        metric == AnalyticsMetric.form || metric == AnalyticsMetric.possession
        ? '%'
        : '';
    return Column(
      children: [
        SizedBox(
          height: 218,
          child: LineChart(
            LineChartData(
              minX: points.length == 1 ? -.5 : 0,
              maxX: points.length == 1 ? .5 : (points.length - 1).toDouble(),
              minY: low,
              maxY: high,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: c.line, dashArray: [4, 5]),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                    interval: interval,
                    getTitlesWidget: (value, meta) => Text(
                      '${value.round()}$suffix',
                      style: TextStyle(fontSize: 9, color: c.muted),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: math.max(1, points.length ~/ 2).toDouble(),
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 ||
                          index >= points.length ||
                          (index != 0 &&
                              index != points.length ~/ 2 &&
                              index != points.length - 1)) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 10,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                        child: Text(
                          DateFormat('dd/MM/yy')
                              .format(points[index].match.date),
                          style: TextStyle(fontSize: 9, color: c.muted),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                first,
                if (metric == AnalyticsMetric.goals) bar(c.red, true),
              ],
              lineTouchData: LineTouchData(
                touchCallback: (event, response) {
                  if (event is! FlTapUpEvent &&
                      event is! FlLongPressStart &&
                      event is! FlLongPressMoveUpdate) {
                    return;
                  }
                  final x = response?.lineBarSpots?.firstOrNull?.x.round();
                  if (x != null && x >= 0 && x < points.length) {
                    onSelected(points[x].match);
                  }
                },
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => c.panel,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (spots) => [
                    for (final spot in spots)
                      LineTooltipItem(
                        '${DateFormat('dd/MM').format(points[spot.x.round()].match.date)}\n${spot.y.toStringAsFixed(metric == AnalyticsMetric.goals ? 1 : 0)}$suffix',
                        TextStyle(
                          color: spot.bar.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            duration: const Duration(milliseconds: 220),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            analyticsLegend(
              metric == AnalyticsMetric.goals
                  ? 'Marcados / jogo'
                  : metric.label,
              c.blue,
            ),
            if (metric == AnalyticsMetric.goals)
              analyticsLegend('Sofridos / jogo', c.red),
          ],
        ),
      ],
    );
  }
}

class AnalyticsResultsChart extends StatelessWidget {
  const AnalyticsResultsChart({super.key, required this.data});
  final TeamAnalytics data;
  @override
  Widget build(BuildContext context) {
    final c = AnalyticsColors(context);
    final values = [data.wins, data.draws, data.losses];
    final colors = [c.green, c.amber, c.red];
    return Row(
      children: [
        SizedBox(
          width: 142,
          height: 152,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 4,
                  centerSpaceRadius: 49,
                  pieTouchData: PieTouchData(enabled: false),
                  sections: [
                    for (var i = 0; i < 3; i++)
                      if (values[i] > 0)
                        PieChartSectionData(
                          value: values[i].toDouble(),
                          color: colors[i],
                          radius: 14,
                          showTitle: false,
                        ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(data.wins / data.played * 100).round()}%',
                    style: TextStyle(
                      color: c.green,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'vitórias',
                    style: TextStyle(fontSize: 11, color: c.muted),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: analyticsLegend(
                          ['Vitórias', 'Empates', 'Derrotas'][i],
                          colors[i],
                        ),
                      ),
                      Text(
                        '${values[i]}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class AnalyticsBars extends StatelessWidget {
  const AnalyticsBars({
    super.key,
    required this.groups,
    required this.label,
    this.goals = false,
  });
  final Map<String, TeamAnalytics> groups;
  final String Function(String) label;
  final bool goals;

  @override
  Widget build(BuildContext context) {
    final c = AnalyticsColors(context);
    final entries = groups.entries.toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    final maxY = goals
        ? math.max(
            1.0,
            entries
                    .map(
                      (e) => math.max(
                        e.value.scoredPerGame,
                        e.value.concededPerGame,
                      ),
                    )
                    .reduce(math.max) *
                1.3,
          )
        : 100.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(
                constraints.maxWidth,
                entries.length * (goals ? 64.0 : 86.0),
              ),
              height: 210,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  alignment: BarChartAlignment.spaceAround,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: goals
                        ? math.max(1.0, (maxY / 3).ceilToDouble())
                        : 25,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: c.line, dashArray: [4, 5]),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        interval: goals
                            ? math.max(1.0, (maxY / 3).ceilToDouble())
                            : 25,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          meta: meta,
                          space: 7,
                          fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                          child: Text(
                            '${value.round()}${goals ? '' : '%'}',
                            style: TextStyle(fontSize: 9, color: c.muted),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (value, meta) {
                          final i = value.round();
                          return i < 0 || i >= entries.length
                              ? const SizedBox.shrink()
                              : SideTitleWidget(
                                  meta: meta,
                                  space: 10,
                                  child: Text(
                                    label(entries[i].key),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: c.muted,
                                    ),
                                  ),
                                );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < entries.length; i++)
                      BarChartGroupData(
                        x: i,
                        barsSpace: 5,
                        barRods: [
                          BarChartRodData(
                            toY: goals
                                ? entries[i].value.scoredPerGame
                                : entries[i].value.efficiency,
                            color: c.blue,
                            width: goals ? 14 : 26,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                            backDrawRodData: BackgroundBarChartRodData(
                              show: !goals,
                              toY: 100,
                              color: c.blue.withValues(alpha: .08),
                            ),
                          ),
                          if (goals)
                            BarChartRodData(
                              toY: entries[i].value.concededPerGame,
                              color: c.red,
                              width: 14,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                            ),
                        ],
                      ),
                  ],
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => c.panel,
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipItem: (group, index, rod, rodIndex) =>
                          BarTooltipItem(
                            '${label(entries[index].key)}\n${rod.toY.toStringAsFixed(1)}${goals ? ' / jogo' : '%'}\n${entries[index].value.played} jogos',
                            TextStyle(
                              color: rod.color,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                    ),
                  ),
                ),
                duration: const Duration(milliseconds: 220),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            analyticsLegend(
              goals ? 'Marcados / jogo' : 'Aproveitamento',
              c.blue,
            ),
            if (goals) analyticsLegend('Sofridos / jogo', c.red),
          ],
        ),
        if (entries.length > 4)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Deslize o gráfico para explorar todo o período →',
              style: TextStyle(fontSize: 10, color: c.muted),
            ),
          ),
      ],
    );
  }
}
