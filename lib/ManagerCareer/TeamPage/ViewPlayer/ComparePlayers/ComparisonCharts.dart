import '../../../../utils/AppColors.dart';

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../PlayerProfileVisuals.dart';

const comparisonColors = AppColors.comparisonSeries;

const comparisonMaxPlayers = 8;

Color comparisonColor(int slot) => comparisonColors[slot];

const _dashes = <List<int>?>[
  null,
  [6, 4],
  [2, 3],
  [9, 3, 2, 3],
];
List<int>? _dash(int slot) => _dashes[slot % _dashes.length];

bool _squareMarker(int slot) => slot.isOdd != (slot >= 4);

TextStyle _axisText(BuildContext context) =>
    TextStyle(color: AppColors.of(context).muted, fontSize: 10);
TextStyle _valueText(BuildContext context) => TextStyle(
  color: AppColors.of(context).text,
  fontSize: 12,
  fontWeight: FontWeight.w600,
);
TextStyle _tooltipText(BuildContext context) => TextStyle(
  color: AppColors.of(context).text,
  fontSize: 12,
  fontWeight: FontWeight.w600,
);

class ComparisonEntry {
  const ComparisonEntry(this.slot, this.name, this.season);
  final int slot;
  final String name, season;
}

class ComparisonSection extends StatelessWidget {
  const ComparisonSection({
    super.key,
    required this.title,
    required this.child,
    required this.expanded,
    required this.onToggle,
    this.onExpand,
  });
  final String title;
  final Widget child;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) => ProfilePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: AppColors.of(context).text,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: expanded ? 'Recolher seção' : 'Expandir seção',
                        child: Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          color: AppColors.of(context).muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (onExpand != null)
              IconButton(
                tooltip: 'Ampliar gráfico',
                onPressed: onExpand,
                icon: Icon(
                  Icons.open_in_full,
                  size: 19,
                  color: AppColors.of(context).accent,
                ),
              ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(padding: const EdgeInsets.only(top: 12), child: child)
              : const SizedBox(width: double.infinity),
        ),
      ],
    ),
  );
}

Widget comparisonSwatch(BuildContext context, int slot, {bool line = false}) =>
    line
    ? Padding(
        padding: const EdgeInsets.only(top: 3, right: 7),
        child: CustomPaint(
          size: const Size(24, 10),
          painter: _LineSample(
            comparisonColor(slot),
            _dash(slot),
            AppColors.of(context),
            square: _squareMarker(slot),
          ),
        ),
      )
    : Container(
        width: 9,
        height: 9,
        margin: const EdgeInsets.only(top: 4, right: 7),
        decoration: BoxDecoration(
          color: comparisonColor(slot),
          shape: _squareMarker(slot) ? BoxShape.rectangle : BoxShape.circle,
        ),
      );

class _LineSample extends CustomPainter {
  const _LineSample(this.color, this.dash, this.colors, {required this.square});
  final AppColors colors;
  final Color color;
  final List<int>? dash;
  final bool square;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final line = Paint()
      ..color = color
      ..strokeWidth = 2;
    final pattern = dash;
    if (pattern == null) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    } else {
      var x = 0.0;
      for (var i = 0; x < size.width; i++) {
        final length = pattern[i % pattern.length].toDouble();
        if (i.isEven) {
          canvas.drawLine(
            Offset(x, y),
            Offset(math.min(x + length, size.width), y),
            line,
          );
        }
        x += length;
      }
    }
    final center = Offset(size.width / 2, y);
    final fill = Paint()..color = color;
    final ring = Paint()
      ..color = colors.panel
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    if (square) {
      final rect = Rect.fromCenter(center: center, width: 7, height: 7);
      canvas
        ..drawRect(rect, fill)
        ..drawRect(rect, ring);
    } else {
      canvas
        ..drawCircle(center, 3.5, fill)
        ..drawCircle(center, 3.5, ring);
    }
  }

  @override
  bool shouldRepaint(_LineSample old) =>
      old.colors != colors ||
      old.color != color ||
      old.dash != dash ||
      old.square != square;
}

class ComparisonLegend extends StatelessWidget {
  const ComparisonLegend({
    super.key,
    required this.entries,
    this.lines = false,
  });
  final List<ComparisonEntry> entries;

  final bool lines;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 10,
        children: [
          for (final entry in entries)
            SizedBox(
              width: width,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  comparisonSwatch(context, entry.slot, line: lines),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.of(context).text,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          entry.season,
                          style: TextStyle(
                            color: AppColors.of(context).muted,
                            fontSize: 11,
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
    },
  );
}

double _step(double highest) {
  if (highest <= 0) return 1;
  final raw = highest / 4;
  final magnitude = math
      .pow(10, (math.log(raw) / math.ln10).floor())
      .toDouble();
  final scaled = raw / magnitude;
  return (scaled <= 1
          ? 1
          : scaled <= 2
          ? 2
          : scaled <= 5
          ? 5
          : 10) *
      magnitude;
}

Widget _title(
  BuildContext context,
  double value,
  TitleMeta meta,
  String text, {
  bool fit = true,
}) => SideTitleWidget(
  meta: meta,
  space: 8,
  fitInside: fit
      ? SideTitleFitInsideData.fromTitleMeta(meta)
      : SideTitleFitInsideData.disable(),
  child: Text(text, style: _axisText(context)),
);

FlGridData _grid(BuildContext context, double step) => FlGridData(
  drawVerticalLine: false,
  horizontalInterval: step,
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

String _axisNumber(double value) =>
    NumberFormat.compact(locale: 'pt_BR').format(value);

class ComparisonBarGroup {
  const ComparisonBarGroup({
    required this.label,
    required this.values,
    required this.texts,
    this.scaleMax,
  });
  final String label;
  final List<num?> values;
  final List<String> texts;

  final double? scaleMax;
}

class ComparisonGroupedBars extends StatelessWidget {
  const ComparisonGroupedBars({
    super.key,
    required this.groups,
    required this.entries,
    this.height = 150,
  });
  final List<ComparisonBarGroup> groups;
  final List<ComparisonEntry> entries;
  final double height;

  static double _labelSpace(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(12) * 1.4 + 6;

  @override
  Widget build(BuildContext context) {
    final count = entries.length;
    final perRow = math.min(
      groups.length,
      count <= 2
          ? 4
          : count <= 4
          ? 2
          : 1,
    );
    return Column(
      children: [
        for (var start = 0; start < groups.length; start += perRow)
          Padding(
            padding: EdgeInsets.only(top: start == 0 ? 0 : 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = start; i < start + perRow; i++) ...[
                  if (i > start) const SizedBox(width: 12),
                  Expanded(
                    child: i < groups.length
                        ? _group(groups[i])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _group(ComparisonBarGroup group) {
    final top =
        group.scaleMax ??
        group.values.whereType<num>().fold<double>(
          0,
          (a, b) => math.max(a, b.toDouble()),
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = entries.length;
        final width = ((constraints.maxWidth - 2 * (count - 1)) / count - 4)
            .clamp(8.0, 34.0);
        return Column(
          children: [
            SizedBox(
              height: height,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < count; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    _bar(context, group, i, top, width),
                  ],
                ],
              ),
            ),
            Container(
              height: 1,
              color: AppColors.of(context).text.withValues(alpha: .20),
            ),
            const SizedBox(height: 6),
            Text(
              group.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.of(context).muted,
                fontSize: 11,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _bar(
    BuildContext context,
    ComparisonBarGroup group,
    int index,
    double top,
    double width,
  ) {
    final value = group.values[index];
    final entry = entries[index];
    final fraction = value == null || top <= 0
        ? 0.0
        : (value / top).clamp(0.0, 1.0).toDouble();
    return Tooltip(
      message:
          '${entry.name} · ${entry.season}\n'
          '${group.label}: ${group.texts[index]}',
      triggerMode: TooltipTriggerMode.tap,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(group.texts[index], style: _valueText(context)),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: width,
              height: (height - _labelSpace(context)) * fraction,
              decoration: BoxDecoration(
                color: comparisonColor(entry.slot),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ComparisonTrendPoint {
  const ComparisonTrendPoint(this.month, this.value, this.date);

  final int month;
  final double value;
  final DateTime date;
}

class ComparisonTrendSeries {
  const ComparisonTrendSeries(this.entry, this.points);
  final ComparisonEntry entry;
  final List<ComparisonTrendPoint> points;
}

class ComparisonTrendChart extends StatefulWidget {
  const ComparisonTrendChart({
    super.key,
    required this.series,
    required this.format,
    required this.monthLabel,
    this.cap,
    this.axisSuffix = '',
    this.summaryTitle,
    this.summary,
    this.height = 220,
  });
  final List<ComparisonTrendSeries> series;

  final String Function(double) format;

  final String Function(int month) monthLabel;

  final double? cap;
  final String axisSuffix;

  final String? summaryTitle;
  final String Function(ComparisonTrendSeries series)? summary;
  final double height;

  @override
  State<ComparisonTrendChart> createState() => _ComparisonTrendChartState();
}

class _ComparisonTrendChartState extends State<ComparisonTrendChart> {
  int? selectedMonth;

  FlDotPainter _marker(int slot, {bool touched = false}) => _squareMarker(slot)
      ? FlDotSquarePainter(
          size: touched ? 12 : 8,
          color: comparisonColor(slot),
          strokeWidth: 2,
          strokeColor: touched
              ? AppColors.of(context).background
              : AppColors.of(context).panel,
        )
      : FlDotCirclePainter(
          radius: touched ? 6 : 4,
          color: comparisonColor(slot),
          strokeWidth: 2,
          strokeColor: touched
              ? AppColors.of(context).background
              : AppColors.of(context).panel,
        );

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final points = series.expand((s) => s.points).toList();
    if (points.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'Nenhum valor registrado para esta estatística na temporada.',
            textAlign: TextAlign.center,
            style: _axisText(context),
          ),
        ),
      );
    }
    final values = points.map((p) => p.value).toList();
    final lowest = values.reduce(math.min);
    final highest = values.reduce(math.max);
    var step = _step(
      highest > lowest ? highest - lowest : math.max(highest.abs(), 1),
    );
    if (step < 1 && values.every((v) => v == v.roundToDouble())) step = 1;
    final minY = math.max(0.0, (lowest / step).ceil() * step - step);
    var maxY = (highest / step).floor() * step + step;
    if (widget.cap != null) maxY = math.min(maxY, widget.cap!);
    final minMonth = points.map((p) => p.month).reduce(math.min);
    final maxX = math
        .max(minMonth + 1, points.map((p) => p.month).reduce(math.max))
        .toDouble();
    final labelStep = math.max(1, ((maxX - minMonth + 1) / 6).ceil());
    final bars = [
      for (final s in series)
        LineChartBarData(
          spots: [
            for (final p in s.points) FlSpot(p.month.toDouble(), p.value),
          ],
          color: comparisonColor(s.entry.slot),
          barWidth: 2,
          isStrokeCapRound: true,
          dashArray: _dash(s.entry.slot),
          showingIndicators: [
            for (final (index, point) in s.points.indexed)
              if (point.month == selectedMonth) index,
          ],
          dotData: FlDotData(
            getDotPainter: (_, _, _, _) => _marker(s.entry.slot),
          ),
        ),
    ];
    final selected = <LineBarSpot>[];
    if (selectedMonth != null) {
      for (var i = 0; i < series.length; i++) {
        final point = series[i].points.indexWhere(
          (p) => p.month == selectedMonth,
        );
        if (point >= 0) {
          selected.add(LineBarSpot(bars[i], i, bars[i].spots[point]));
        }
      }
    }
    final summary = widget.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: widget.height,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LineChart(
              LineChartData(
                minX: minMonth - .15,
                maxX: maxX + .15,
                minY: minY,
                maxY: maxY,
                gridData: _grid(context, step),
                borderData: _border(context),
                lineBarsData: bars,
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      interval: step,
                      getTitlesWidget: (value, meta) => _title(
                        context,
                        value,
                        meta,
                        '${_axisNumber(value)}${widget.axisSuffix}',
                        fit: false,
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final month = value.round();
                        if ((month - value).abs() > .01 ||
                            month < minMonth ||
                            month > maxX ||
                            (month - minMonth) % labelStep != 0) {
                          return const SizedBox.shrink();
                        }
                        return _title(
                          context,
                          value,
                          meta,
                          widget.monthLabel(month),
                        );
                      },
                    ),
                  ),
                ),
                showingTooltipIndicators: [
                  if (selected.isNotEmpty) ShowingTooltipIndicators(selected),
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
                    final month = response?.lineBarSpots?.firstOrNull?.x
                        .round();
                    if (month != selectedMonth) {
                      setState(() => selectedMonth = month);
                    }
                  },
                  getTouchedSpotIndicator: (bar, indices) {
                    final index = bars.indexOf(bar);
                    final slot = index < 0 ? 0 : series[index].entry.slot;
                    return [
                      for (final _ in indices)
                        TouchedSpotIndicatorData(
                          FlLine(
                            color: AppColors.of(context).text
                                .withValues(alpha: .35),
                            strokeWidth: 1,
                            dashArray: [4, 4],
                          ),
                          FlDotData(
                            getDotPainter: (_, _, _, _) =>
                                _marker(slot, touched: true),
                          ),
                        ),
                    ];
                  },
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.of(context).background,
                    tooltipBorderRadius: BorderRadius.circular(10),
                    tooltipBorder: BorderSide(
                      color: AppColors.of(context).text.withValues(alpha: .25),
                    ),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    maxContentWidth: 260,
                    getTooltipItems: (spots) => [
                      for (final spot in spots)
                        _tooltipItem(series[spot.barIndex], spot),
                    ],
                  ),
                ),
              ),
              duration: const Duration(milliseconds: 220),
            ),
          ),
        ),
        if (summary != null) ...[
          const SizedBox(height: 12),
          if (widget.summaryTitle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                widget.summaryTitle!,
                style: TextStyle(
                  color: AppColors.of(context).muted,
                  fontSize: 11,
                ),
              ),
            ),
          for (final s in series)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  comparisonSwatch(context, s.entry.slot, line: true),
                  Expanded(
                    child: Text(
                      s.entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.of(context).text,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(summary(s), style: _valueText(context)),
                ],
              ),
            ),
        ],
      ],
    );
  }

  LineTooltipItem _tooltipItem(ComparisonTrendSeries series, LineBarSpot spot) {
    final slot = series.entry.slot;
    final date = series.points[spot.spotIndex].date;
    return LineTooltipItem(
      _squareMarker(slot) ? '■ ' : '● ',
      _tooltipText(context).copyWith(color: comparisonColor(slot)),
      textAlign: TextAlign.left,
      children: [
        TextSpan(
          text: '${series.entry.name}: ${widget.format(spot.y)}',
          style: _tooltipText(context),
        ),
        TextSpan(
          text:
              ' · ${DateFormat('MMM/yy', 'pt_BR').format(date).replaceAll('.', '')}',
          style: TextStyle(
            color: AppColors.of(context).muted,
            fontSize: 11,
            fontWeight: FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
