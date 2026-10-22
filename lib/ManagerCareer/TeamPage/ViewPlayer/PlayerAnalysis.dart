import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/MatchPerformanceStats.dart';
import '../../../utils/AppColors.dart';
import '../../PlayersStat/PlayersStatData.dart' show PlayersStatMetric;
import '../../PlayersStat/RecordedPlayerStats.dart';
import 'PlayerProfileData.dart';
import 'PlayerProfileVisuals.dart';

String analysisNumber(num? value, {int decimals = 0, String suffix = ''}) =>
    value == null || !value.isFinite
    ? '–'
    : '${NumberFormat(decimals == 0 ? '#,##0' : '#,##0.${'0' * decimals}', 'pt_BR').format(value)}$suffix';

String analysisPercent(num? value) => analysisNumber(value, suffix: '%');

class PlayerNumbers {
  PlayerNumbers(Iterable<PlayerMatchData> source)
    : matches = source.toList(),
      totals = PlayerTotals(source),
      recorded = RecordedPlayerStats(source) {
    _api = [
      for (final m in matches)
        if (m.performance.apiStats.isNotEmpty) m.performance.apiStats,
    ];
  }

  final List<PlayerMatchData> matches;
  final PlayerTotals totals;
  final RecordedPlayerStats recorded;
  late final List<Map<String, Object?>> _api;

  int get games => totals.matches;
  int get minutes => totals.minutes;
  int get contributions => totals.goals + totals.assists;

  double? per90(num? value) =>
      value == null || minutes == 0 ? null : value * 90 / minutes;

  double? minutesPer(int count) => count == 0 ? null : minutes / count;

  int? sum(int? Function(PlayerMatchData) field) {
    int? total;
    for (final m in matches) {
      final value = field(m);
      if (value != null) total = (total ?? 0) + value;
    }
    return total;
  }

  int? get shots => totals.hasShots ? totals.shots : null;
  int? get passes => totals.hasPasses ? totals.passes : null;
  int? get keyPasses => sum((m) => m.performance.keyPasses);
  int? get dribbles => sum((m) => m.performance.dribbles);
  int? get tackles => totals.hasTackles ? totals.tackles : null;
  int? get saves => sum((m) => m.performance.saves);
  int? get penaltySaves => sum((m) => m.performance.penaltySaves);

  double? get shotAccuracy => _rate(PlayersStatMetric.shotAccuracy);
  double? get passAccuracy => _rate(PlayersStatMetric.passAccuracy);
  double? get dribbleAccuracy => _rate(PlayersStatMetric.dribbleAccuracy);
  double? get tackleAccuracy => _rate(PlayersStatMetric.tackleAccuracy);
  double? _rate(PlayersStatMetric metric) => recorded[metric]?.toDouble();

  bool averaged(PlayersStatMetric metric) =>
      recorded.averagedPercentages.contains(metric);

  double? get conversion {
    num goals = 0, shots = 0;
    for (final m in matches) {
      final s = m.performance.shotsCount;
      if (s == null || s <= 0) continue;
      goals += m.goals;
      shots += s;
    }
    return shots == 0 ? null : goals * 100 / shots;
  }

  int? get penaltyGoals => totals.hasGoalDetails ? totals.penalties : null;
  int get hatTricks => matches.where((m) => m.goals >= 3).length;

  int get cleanSheets =>
      matches.where((m) => m.row['oppositeTeamScore'] == 0).length;

  double? get startShare => games == 0 ? null : totals.starts * 100 / games;

  num? api(String key) {
    if (_api.isEmpty) return null;
    final stat = performanceStats.where((s) => s.key == key).firstOrNull;
    return stat?.total(_api);
  }

  double? get expectedGoals => api('npkExpectedGoals')?.toDouble();
  double? get expectedAssists => api('expectedAssists')?.toDouble();
}

class StatRow {
  const StatRow(this.label, this.total, {this.per90, this.share, this.help});
  final String label, total;
  final String? per90;

  final double? share;

  final String? help;
}

class StatTable extends StatelessWidget {
  const StatTable({
    super.key,
    required this.title,
    required this.rows,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final List<StatRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final c = AppColors.of(context);
    final rates = rows.any((r) => r.per90 != null);
    final head = TextStyle(
      color: c.muted,
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: .3,
    );
    Widget cell(String text, {bool strong = true, double width = 64}) =>
        SizedBox(
          width: width,
          child: Text(
            text,
            textAlign: TextAlign.end,
            maxLines: 1,
            style: strong
                ? TextStyle(
                    color: c.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  )
                : TextStyle(
                    color: c.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
          ),
        );
    return ProfilePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (rates) ...[
                SizedBox(
                  width: 64,
                  child: Text('TOTAL', textAlign: TextAlign.end, style: head),
                ),
                SizedBox(
                  width: 64,
                  child: Text("POR 90'", textAlign: TextAlign.end, style: head),
                ),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(color: c.muted, fontSize: 11.5, height: 1.4),
            ),
          ],
          const SizedBox(height: 8),
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) Divider(height: 1, color: c.line.withValues(alpha: .35)),
            _withHelp(
              row.help,
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.label,
                            style: TextStyle(color: c.text, fontSize: 13),
                          ),
                        ),
                        cell(row.total),
                        if (rates) cell(row.per90 ?? '', strong: false),
                      ],
                    ),
                    if (row.share != null) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: row.share!.clamp(0, 1).toDouble(),
                          minHeight: 4,
                          color: c.accent,
                          backgroundColor: c.raised,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _withHelp(String? help, Widget child) => help == null
      ? child
      : Tooltip(
          message: help,
          triggerMode: TooltipTriggerMode.tap,
          showDuration: const Duration(seconds: 4),
          child: child,
        );
}

class AnalysisStrip extends StatelessWidget {
  const AnalysisStrip({super.key, required this.items});
  final List<(String value, String label)> items;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: c.raised.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (final (i, (value, label)) in items.indexed) ...[
              if (i > 0)
                VerticalDivider(width: 9, color: c.line.withValues(alpha: .6)),
              Expanded(
                child: Column(
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 10.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
