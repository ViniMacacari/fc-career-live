import 'package:flutter/material.dart';

import '../../utils/AppColors.dart';
import '../Fixtures/Performances/TeamPlayersPerformanceGrid.dart'
    show performanceRatingColor;
import 'PlayersStatData.dart';
import 'RecordedPlayerStats.dart';

PlayerStatDatum playerMetricDatum(
  RecordedPlayerStats stats,
  PlayersStatMetric metric,
) {
  final total = stats.matches.length;
  final count =
      stats.coverage[metric] ??
      (metric == PlayersStatMetric.matches ? total : 0);
  final calculation = switch (metric) {
    PlayersStatMetric.minutes =>
      'Minutos informados; com apenas substituições, o tempo é estimado.',
    PlayersStatMetric.rating => 'Média das notas das atuações.',
    PlayersStatMetric.cleanSheets => 'Partidas em que o time não sofreu gols.',
    _ =>
      stats.averagedPercentages.contains(metric)
          ? 'Média dos percentuais informados por partida.'
          : metric.percentage
          ? 'Acertos ÷ tentativas nas mesmas partidas.'
          : 'Total nas atuações do recorte.',
  };
  return PlayerStatDatum(
    id: metric.name,
    label: metric.title,
    value: stats.format(metric),
    metric: metric,
    accent: metric == PlayersStatMetric.rating,
    note: count > 0 && count < total ? '$count de $total jogos' : null,
    help: '${metric.label}\n$calculation',
  );
}

extension PlayerMetricPresentation on PlayersStatMetric {
  String get title => switch (this) {
    PlayersStatMetric.matches => 'Jogos',
    PlayersStatMetric.starts => 'Titularidades',
    PlayersStatMetric.captainMatches => 'Como capitão',
    PlayersStatMetric.captainStarts => 'Capitão inicial',
    PlayersStatMetric.goals => 'Gols',
    PlayersStatMetric.penalties => 'Gols de pênalti',
    PlayersStatMetric.shots => 'Finalizações',
    PlayersStatMetric.shotAccuracy => 'Precisão nas finalizações',
    PlayersStatMetric.assists => 'Assistências',
    PlayersStatMetric.goalsAssists => 'Gols + assistências',
    PlayersStatMetric.keyPasses => 'Passes-chave',
    PlayersStatMetric.passes => 'Passes',
    PlayersStatMetric.passAccuracy => 'Precisão de passe',
    PlayersStatMetric.dribbles => 'Dribles',
    PlayersStatMetric.dribbleAccuracy => 'Aproveitamento em dribles',
    PlayersStatMetric.rating => 'Nota média',
    PlayersStatMetric.motm => 'Melhor em campo',
    PlayersStatMetric.minutes => 'Minutos',
    PlayersStatMetric.tackles => 'Desarmes',
    PlayersStatMetric.tackleAccuracy => 'Aproveitamento em desarmes',
    PlayersStatMetric.yellowCards => 'Cartões amarelos',
    PlayersStatMetric.redCards => 'Cartões vermelhos',
    PlayersStatMetric.ownGoals => 'Gols contra',
    PlayersStatMetric.hatTricks => 'Hat-tricks',
    PlayersStatMetric.saves => 'Defesas',
    PlayersStatMetric.penaltySaves => 'Pênaltis defendidos',
    PlayersStatMetric.cleanSheets => 'Sem sofrer gols',
  };

  IconData get icon => switch (this) {
    PlayersStatMetric.matches => Icons.sports_soccer_outlined,
    PlayersStatMetric.starts => Icons.groups_outlined,
    PlayersStatMetric.captainMatches ||
    PlayersStatMetric.captainStarts => Icons.workspace_premium_outlined,
    PlayersStatMetric.goals ||
    PlayersStatMetric.penalties ||
    PlayersStatMetric.ownGoals ||
    PlayersStatMetric.hatTricks => Icons.sports_soccer,
    PlayersStatMetric.shots ||
    PlayersStatMetric.shotAccuracy => Icons.gps_fixed,
    PlayersStatMetric.assists ||
    PlayersStatMetric.goalsAssists ||
    PlayersStatMetric.keyPasses => Icons.assistant_direction_outlined,
    PlayersStatMetric.passes ||
    PlayersStatMetric.passAccuracy => Icons.swap_horiz_rounded,
    PlayersStatMetric.dribbles ||
    PlayersStatMetric.dribbleAccuracy => Icons.directions_run,
    PlayersStatMetric.rating ||
    PlayersStatMetric.motm => Icons.star_outline_rounded,
    PlayersStatMetric.minutes => Icons.timer_outlined,
    PlayersStatMetric.tackles ||
    PlayersStatMetric.tackleAccuracy => Icons.shield_outlined,
    PlayersStatMetric.yellowCards || PlayersStatMetric.redCards => Icons.style,
    PlayersStatMetric.saves ||
    PlayersStatMetric.penaltySaves ||
    PlayersStatMetric.cleanSheets => Icons.sports_handball_outlined,
  };
}

class PlayerMetricIcon extends StatelessWidget {
  const PlayerMetricIcon(this.metric, {super.key, this.size = 18, this.color});
  final PlayersStatMetric metric;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    if (metric == PlayersStatMetric.yellowCards ||
        metric == PlayersStatMetric.redCards) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Transform.rotate(
            angle: -.13,
            child: Container(
              width: size * .62,
              height: size * .85,
              decoration: BoxDecoration(
                color: metric == PlayersStatMetric.yellowCards
                    ? AppColors.yellowCard
                    : AppColors.redCard,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: AppColors.ink.withValues(alpha: .2)),
              ),
            ),
          ),
        ),
      );
    }
    return Icon(
      metric.icon,
      size: size,
      color: color ?? AppColors.of(context).muted,
    );
  }
}

class PlayerStatDatum {
  const PlayerStatDatum({
    required this.id,
    required this.label,
    required this.value,
    required this.help,
    this.metric,
    this.icon = Icons.analytics_outlined,
    this.accent = false,
    this.note,
    this.share,
  });
  final String id, label, value, help;
  final PlayersStatMetric? metric;
  final IconData icon;
  final bool accent;

  final String? note;

  final double? share;
  Widget symbol(BuildContext context, {double size = 18}) => metric == null
      ? Icon(icon, size: size, color: AppColors.of(context).muted)
      : PlayerMetricIcon(metric!, size: size);
}

class PlayerStatList extends StatelessWidget {
  const PlayerStatList({super.key, required this.items});
  final List<PlayerStatDatum> items;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      children: [
        for (final (i, item) in items.indexed) ...[
          if (i > 0) Divider(height: 1, color: c.line.withValues(alpha: .5)),
          Tooltip(
            key: ValueKey('stat-help-${item.id}'),
            message: item.help,
            triggerMode: TooltipTriggerMode.tap,
            showDuration: const Duration(seconds: 4),
            preferBelow: false,
            child: Semantics(
              label: '${item.label}: ${item.value}',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        item.symbol(context, size: 17),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.label,
                                style: TextStyle(color: c.text, fontSize: 13),
                              ),
                              if (item.note != null)
                                Text(
                                  item.note!,
                                  style: TextStyle(
                                    color: c.muted,
                                    fontSize: 10.5,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          item.value,
                          style: TextStyle(
                            color: item.accent ? c.accent : c.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    if (item.share != null) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 29),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: item.share!.clamp(0, 1),
                            minHeight: 4,
                            color: c.accent,
                            backgroundColor: c.raised,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class PlayerStatBadge extends StatelessWidget {
  const PlayerStatBadge({super.key, required this.item});
  final PlayerStatDatum item;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: item.label,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        item.symbol(context, size: 14),
        const SizedBox(width: 4),
        Text(
          item.value,
          style: TextStyle(
            color: AppColors.of(context).text,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class RatingPill extends StatelessWidget {
  const RatingPill(this.rating, {super.key, this.size = 13});
  final num? rating;
  final double size;
  @override
  Widget build(BuildContext context) {
    final color = performanceRatingColor(rating);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: size * .5, vertical: 2),
      decoration: BoxDecoration(
        color: rating == null ? AppColors.of(context).raised : color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        rating == null ? '–' : rating!.toStringAsFixed(1).replaceAll('.', ','),
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          color: rating == null
              ? AppColors.of(context).muted
              : AppColors.onColor(color),
          fontSize: size,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
