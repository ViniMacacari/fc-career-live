import '../../../utils/AppColors.dart';

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../Fixtures/Performances/TeamPlayersPerformanceGrid.dart'
    show performanceRatingColor;

class ProfileChartPoint {
  const ProfileChartPoint(this.value, {this.date, this.caption});
  final double value;
  final DateTime? date;
  final String? caption;
}

List<ProfileChartPoint> profileHistoryPoints(
  List<Map<String, Object?>> records,
  String field,
) => [
  for (final record in records.reversed)
    if (record[field] is num)
      ProfileChartPoint(
        (record[field] as num).toDouble(),
        date: DateTime.tryParse(record['date']?.toString() ?? ''),
        caption: record['isSeasonInitial'] == true
            ? 'Início da temporada'
            : null,
      ),
];

TextStyle _axisText(BuildContext context) =>
    TextStyle(color: AppColors.of(context).muted, fontSize: 10);
TextStyle _tooltipText(BuildContext context) => TextStyle(
  color: AppColors.of(context).text,
  fontSize: 13,
  fontWeight: FontWeight.w600,
);

Widget _sideTitle(
  BuildContext context,
  double value,
  TitleMeta meta,
  String text,
) => SideTitleWidget(
  meta: meta,
  space: 8,
  fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
  child: Text(text, style: _axisText(context)),
);

FlGridData _grid(BuildContext context, double interval) => FlGridData(
  drawVerticalLine: false,
  horizontalInterval: interval,
  getDrawingHorizontalLine: (_) => FlLine(
    color: AppColors.of(context).text.withValues(alpha: .10),
    strokeWidth: 1,
    dashArray: [4, 5],
  ),
);

FlBorderData _border(BuildContext context) => FlBorderData(
  border: Border(
    bottom: BorderSide(
      color: AppColors.of(context).text.withValues(alpha: .20),
    ),
  ),
);

class OverallChart extends StatefulWidget {
  const OverallChart({
    super.key,
    required this.points,
    this.valueFormatter,
    this.compactAxis = false,
    this.height = 190,
  });
  final List<ProfileChartPoint> points;
  final String Function(num)? valueFormatter;
  final bool compactAxis;
  final double height;

  @override
  State<OverallChart> createState() => _OverallChartState();
}

class _OverallChartState extends State<OverallChart> {
  int? selected;

  @override
  void didUpdateWidget(covariant OverallChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points.length != widget.points.length ||
        oldWidget.points.indexed.any(
          (entry) =>
              entry.$2.value != widget.points[entry.$1].value ||
              entry.$2.date != widget.points[entry.$1].date,
        )) {
      selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.isEmpty) {
      return SizedBox(
        height: 140,
        width: double.infinity,
        child: Center(
          child: Text(
            'Nenhum registro no histórico.',
            style: _axisText(context),
          ),
        ),
      );
    }
    final lowest = points.map((p) => p.value).reduce(math.min);
    final highest = points.map((p) => p.value).reduce(math.max);
    final padding = math.max(
      (highest - lowest) * .18,
      highest == lowest ? math.max(highest.abs() * .08, 1.0) : 1.0,
    );
    final rawStep = (highest - lowest + padding * 2) / 3;
    final magnitude = math.pow(10, (math.log(rawStep) / math.ln10).floor());
    final normalized = rawStep / magnitude;
    final step =
        (normalized <= 1
            ? 1
            : normalized <= 2
            ? 2
            : normalized <= 5
            ? 5
            : 10) *
        magnitude;
    final minY = math
        .max(0.0, ((lowest - padding) / step).floor() * step)
        .toDouble();
    final maxY = math
        .max(minY + step, ((highest + padding) / step).ceil() * step)
        .toDouble();
    final bar = LineChartBarData(
      spots: [
        for (var i = 0; i < points.length; i++)
          FlSpot(i.toDouble(), points[i].value),
      ],
      color: AppColors.of(context).accent,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(
        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
          radius: points.length > 24 ? 3 : 4,
          color: AppColors.of(context).panel,
          strokeWidth: 2.5,
          strokeColor: AppColors.of(context).accent,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.of(context).accent.withValues(alpha: .30),
            AppColors.of(context).accent.withValues(alpha: .02),
          ],
        ),
      ),
      showingIndicators: selected == null ? [] : [selected!],
    );
    final midIndex = (points.length - 1) ~/ 2;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, left: 4, right: 2),
        child: LineChart(
          LineChartData(
            minX: points.length == 1 ? -1 : -.15,
            maxX: points.length == 1 ? 1 : points.length - 1 + .15,
            minY: minY,
            maxY: maxY,
            gridData: _grid(context, step.toDouble()),
            borderData: _border(context),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
              rightTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: widget.compactAxis ? 51 : 35,
                  interval: step.toDouble(),
                  getTitlesWidget: (value, meta) => _sideTitle(
                    context,
                    value,
                    meta,
                    widget.compactAxis
                        ? NumberFormat.compact(locale: 'pt_BR').format(value)
                        : NumberFormat.decimalPattern('pt_BR').format(value),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 29,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final i = value.round();
                    if ((value - i).abs() > .01 ||
                        i < 0 ||
                        i >= points.length ||
                        (i != 0 && i != midIndex && i != points.length - 1)) {
                      return const SizedBox.shrink();
                    }
                    return _sideTitle(
                      context,
                      value,
                      meta,
                      points[i].date == null
                          ? '–'
                          : DateFormat('dd/MM/yy').format(points[i].date!),
                    );
                  },
                ),
              ),
            ),
            lineBarsData: [bar],
            showingTooltipIndicators: [
              if (selected != null)
                ShowingTooltipIndicators([
                  LineBarSpot(bar, 0, bar.spots[selected!]),
                ]),
            ],
            lineTouchData: LineTouchData(
              handleBuiltInTouches: false,
              touchSpotThreshold: 28,
              touchCallback: (event, response) {
                if (event is! FlTapUpEvent &&
                    event is! FlLongPressStart &&
                    event is! FlLongPressMoveUpdate &&
                    event is! FlPointerHoverEvent) {
                  return;
                }
                final index = response?.lineBarSpots?.firstOrNull?.spotIndex;
                if (index != selected) setState(() => selected = index);
              },
              getTouchedSpotIndicator: (data, indices) => [
                for (var index = 0; index < indices.length; index++)
                  TouchedSpotIndicatorData(
                    FlLine(
                      color: AppColors.of(context).accent.withValues(alpha: .6),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                    FlDotData(
                      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                        radius: 6,
                        color: AppColors.of(context).accent,
                        strokeWidth: 3,
                        strokeColor: AppColors.of(context).background,
                      ),
                    ),
                  ),
              ],
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => AppColors.of(context).background,
                tooltipBorderRadius: BorderRadius.circular(10),
                tooltipBorder: BorderSide(
                  color: AppColors.of(context).accent.withValues(alpha: .4),
                ),
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                maxContentWidth: 220,
                getTooltipItems: (spots) => [
                  for (final spot in spots)
                    LineTooltipItem(
                      '${widget.valueFormatter?.call(points[spot.spotIndex].value) ?? NumberFormat.decimalPattern('pt_BR').format(points[spot.spotIndex].value)}\n',
                      _tooltipText(context),
                      children: [
                        TextSpan(
                          text: points[spot.spotIndex].date == null
                              ? 'Data não informada'
                              : DateFormat('dd/MM/yyyy')
                                    .format(points[spot.spotIndex].date!),
                          style: TextStyle(
                            color: AppColors.of(context).muted,
                            fontWeight: FontWeight.normal,
                            fontSize: 11,
                          ),
                        ),
                        if (points[spot.spotIndex].caption != null)
                          TextSpan(
                            text: '\n${points[spot.spotIndex].caption}',
                            style: TextStyle(
                              color: AppColors.of(context).accent,
                              fontWeight: FontWeight.normal,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          duration: const Duration(milliseconds: 220),
        ),
      ),
    );
  }
}

class ProfileMonthlyRatingsChart extends StatefulWidget {
  const ProfileMonthlyRatingsChart({
    super.key,
    required this.points,
    required this.start,
    required this.end,
    this.average,
  });
  final List<ProfileChartPoint> points;
  final DateTime start, end;
  final double? average;
  @override
  State<ProfileMonthlyRatingsChart> createState() =>
      _ProfileMonthlyRatingsChartState();
}

class _ProfileMonthlyRatingsChartState
    extends State<ProfileMonthlyRatingsChart> {
  int? selected;
  @override
  void didUpdateWidget(covariant ProfileMonthlyRatingsChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.start != widget.start ||
        oldWidget.end != widget.end ||
        oldWidget.points.length != widget.points.length ||
        oldWidget.points.indexed.any(
          (entry) =>
              entry.$2.value != widget.points[entry.$1].value ||
              entry.$2.date != widget.points[entry.$1].date,
        )) {
      selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final months = <DateTime>[];
    for (
      var month = DateTime(widget.start.year, widget.start.month);
      !month.isAfter(widget.end);
      month = DateTime(month.year, month.month + 1)
    ) {
      months.add(month);
    }
    if (months.isEmpty || widget.points.isEmpty) {
      return SizedBox(
        height: 160,
        width: double.infinity,
        child: Center(
          child: Text(
            'Nenhuma avaliação registrada nesta temporada.',
            style: _axisText(context),
          ),
        ),
      );
    }
    final records = {
      for (final point in widget.points)
        if (point.date != null)
          DateTime(point.date!.year, point.date!.month): point,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = ((constraints.maxWidth - 40) / months.length * .60)
            .clamp(5.0, 28.0);
        final labelCount = math.max(
          2,
          ((constraints.maxWidth - 40) /
                  (50 * MediaQuery.textScalerOf(context).scale(10) / 10))
              .floor(),
        );
        final labelStep = math.max(1, (months.length / labelCount).ceil());
        return SizedBox(
          height: 210,
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.only(top: 8, left: 4, right: 2),
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: 10,
                alignment: BarChartAlignment.spaceAround,
                gridData: _grid(context, 2.5),
                borderData: _border(context),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 35,
                      interval: 2.5,
                      getTitlesWidget: (value, meta) => _sideTitle(
                        context,
                        value,
                        meta,
                        NumberFormat.decimalPattern('pt_BR').format(value),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= months.length || i % labelStep != 0) {
                          return const SizedBox.shrink();
                        }
                        return _sideTitle(
                          context,
                          value,
                          meta,
                          DateFormat('MMM/yy', 'pt_BR').format(months[i]),
                        );
                      },
                    ),
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    if (widget.average != null)
                      HorizontalLine(
                        y: widget.average!,
                        color: AppColors.of(context).text.withValues(alpha: .7),
                        strokeWidth: 1.5,
                        dashArray: [5, 5],
                      ),
                  ],
                ),
                barGroups: [
                  for (var i = 0; i < months.length; i++)
                    BarChartGroupData(
                      x: i,
                      showingTooltipIndicators: selected == i ? [0] : [],
                      barRods: [
                        BarChartRodData(
                          toY: records[months[i]]?.value ?? 0,
                          width: barWidth,
                          color: performanceRatingColor(
                            records[months[i]]?.value,
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(5),
                          ),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: 10,
                            color: Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                ],
                barTouchData: BarTouchData(
                  handleBuiltInTouches: false,
                  allowTouchBarBackDraw: true,
                  touchCallback: (event, response) {
                    if (event is! FlTapUpEvent &&
                        event is! FlLongPressStart &&
                        event is! FlLongPressMoveUpdate &&
                        event is! FlPointerHoverEvent) {
                      return;
                    }
                    final index = response?.spot?.touchedBarGroupIndex;
                    final valid =
                        index != null && records.containsKey(months[index])
                        ? index
                        : null;
                    if (selected != valid) setState(() => selected = valid);
                  },
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.of(context).background,
                    tooltipBorderRadius: BorderRadius.circular(10),
                    tooltipBorder: BorderSide(
                      color: AppColors.of(context).accent.withValues(alpha: .4),
                    ),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    maxContentWidth: 220,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final record = records[months[groupIndex]];
                      if (record == null) return null;
                      return BarTooltipItem(
                        '${record.value.toStringAsFixed(2).replaceAll('.', ',')}\n',
                        _tooltipText(context),
                        children: [
                          TextSpan(
                            text:
                                '${DateFormat('MMMM yyyy', 'pt_BR').format(months[groupIndex])}\n${record.caption ?? ''}',
                            style: TextStyle(
                              color: AppColors.of(context).muted,
                              fontWeight: FontWeight.normal,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              duration: const Duration(milliseconds: 220),
            ),
          ),
        );
      },
    );
  }
}
