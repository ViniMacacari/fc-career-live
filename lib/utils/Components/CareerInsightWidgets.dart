import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'CareerUiStyle.dart';

class InsightStatGrid extends StatelessWidget {
  const InsightStatGrid({super.key, required this.items});
  final List<(String, String, IconData, Color)> items;

  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    return LayoutBuilder(
      builder: (context, box) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final (value, label, icon, color) in items)
            Container(
              width: (box.maxWidth - 10) / 2,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: .15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(height: 10),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(color: c.muted, fontSize: 11, height: 1.4),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class CareerTrendPoint {
  const CareerTrendPoint(this.label, this.value, {this.other, this.detail});
  final String label;
  final String? detail;
  final double? value, other;
}

class CareerTrendChart extends StatefulWidget {
  const CareerTrendChart({
    super.key,
    required this.points,
    required this.label,
    this.otherLabel,
    this.maxY,
    this.step = false,
    this.format,
    this.emptyMessage = 'Nenhum dado registrado neste período.',
  });
  final List<CareerTrendPoint> points;
  final String label, emptyMessage;
  final String? otherLabel;
  final double? maxY;
  final bool step;
  final String Function(double value)? format;
  @override
  State<CareerTrendChart> createState() => _CareerTrendChartState();
}

class _CareerTrendChartState extends State<CareerTrendChart> {
  int? selected;
  @override
  void didUpdateWidget(CareerTrendChart old) {
    super.didUpdateWidget(old);
    if (old.points.length != widget.points.length) selected = null;
  }

  String _number(double? value) => value == null
      ? '—'
      : widget.format != null
      ? widget.format!(value)
      : value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context), points = widget.points;
    final values = [
      for (final p in points) ...[?p.value, ?p.other],
    ];
    if (values.isEmpty) {
      return SizedBox(
        height: 170,
        child: Center(
          child: Text(
            widget.emptyMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, fontSize: 12, height: 1.5),
          ),
        ),
      );
    }
    final high =
        widget.maxY ??
        math.max(1.0, (values.reduce(math.max) * 1.2).ceilToDouble());
    final interval = widget.maxY == 10
        ? 2.0
        : math.max(1.0, (high / 4).ceilToDouble());
    final labelIndices = {
      0,
      ((points.length - 1) / 2).round(),
      points.length - 1,
    };
    final background = Theme.of(context).scaffoldBackgroundColor;
    LineChartBarData line(bool other) {
      final color = other ? c.green : c.accent;
      return LineChartBarData(
        spots: [
          for (final (i, p) in points.indexed)
            (other ? p.other : p.value) == null
                ? FlSpot.nullSpot
                : FlSpot(i.toDouble(), (other ? p.other : p.value)!),
        ],
        color: color,
        barWidth: 2.5,
        isStepLineChart: widget.step,
        showingIndicators: [
          if (selected case final i?)
            if ((other ? points[i].other : points[i].value) != null) i,
        ],
        dotData: FlDotData(
          show: points.length <= 24,
          getDotPainter: (_, _, _, _) => FlDotCirclePainter(
            radius: 3,
            color: color,
            strokeWidth: 1.5,
            strokeColor: background,
          ),
        ),
        belowBarData: BarAreaData(
          show: !other,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              c.accent.withValues(alpha: .18),
              c.accent.withValues(alpha: 0),
            ],
          ),
        ),
      );
    }

    final bars = [line(false), if (widget.otherLabel != null) line(true)];
    final shown = [
      if (selected case final i?)
        for (final (b, bar) in bars.indexed)
          if (bar.spots[i].isNotNull()) LineBarSpot(bar, b, bar.spots[i]),
    ];
    final muted = TextStyle(color: c.muted, fontSize: 11, height: 1.4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.otherLabel != null) ...[
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _legend(widget.label, c.accent),
              _legend(widget.otherLabel!, c.green),
            ],
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minX: points.length == 1 ? -.5 : 0,
              maxX: points.length == 1 ? .5 : (points.length - 1).toDouble(),
              minY: 0,
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
                    reservedSize: 30,
                    interval: interval,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(
                        '${value.round()}',
                        style: TextStyle(color: c.muted, fontSize: 9),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      if (i < 0 ||
                          i >= points.length ||
                          value != i.toDouble() ||
                          !labelIndices.contains(i)) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                        space: 9,
                        child: Text(
                          points[i].label,
                          style: TextStyle(color: c.muted, fontSize: 9),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: bars,
              showingTooltipIndicators: [
                if (shown.isNotEmpty) ShowingTooltipIndicators(shown),
              ],
              lineTouchData: LineTouchData(
                touchSpotThreshold: 24,
                handleBuiltInTouches: false,
                touchCallback: (event, response) {
                  if (event is! FlTapUpEvent &&
                      event is! FlLongPressStart &&
                      event is! FlLongPressMoveUpdate &&
                      event is! FlPointerHoverEvent) {
                    return;
                  }
                  final i = response?.lineBarSpots?.firstOrNull?.x.round();
                  final next = i != null && i >= 0 && i < points.length
                      ? i
                      : null;
                  if (next == null && event is FlPointerHoverEvent) return;
                  if (next != selected) setState(() => selected = next);
                },
                getTouchedSpotIndicator: (bar, indices) => [
                  for (final _ in indices)
                    TouchedSpotIndicatorData(
                      FlLine(
                        color: c.muted.withValues(alpha: .45),
                        strokeWidth: 1,
                        dashArray: [3, 4],
                      ),
                      FlDotData(
                        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                          radius: 5.5,
                          color: bar.color ?? c.accent,
                          strokeWidth: 2.5,
                          strokeColor: background,
                        ),
                      ),
                    ),
                ],
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => c.panel,
                  tooltipBorderRadius: BorderRadius.circular(10),
                  tooltipBorder: BorderSide(color: c.line),
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  tooltipMargin: 12,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  maxContentWidth: 200,
                  getTooltipItems: (spots) => [
                    for (final (n, spot) in spots.indexed)
                      _tooltip(points[spot.x.round()], spot, n == 0, muted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  LineTooltipItem _tooltip(
    CareerTrendPoint point,
    LineBarSpot spot,
    bool first,
    TextStyle muted,
  ) {
    final paired = widget.otherLabel != null;
    return LineTooltipItem(
      first
          ? '${[?point.detail, if (point.detail?.contains(point.label) != true) point.label].join(' · ')}\n'
          : '',
      muted,
      textAlign: TextAlign.left,
      children: [
        if (paired)
          TextSpan(
            text: '${spot.barIndex == 0 ? widget.label : widget.otherLabel}  ',
            style: muted,
          ),
        TextSpan(
          text: _number(spot.y),
          style: TextStyle(
            color: spot.bar.color,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
        if (!paired) TextSpan(text: '  ${widget.label}', style: muted),
      ],
    );
  }

  Widget _legend(String text, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(fontSize: 11)),
    ],
  );
}
