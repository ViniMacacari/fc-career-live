import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/MatchPerformanceStats.dart';
import '../../../utils/AppColors.dart';
import 'PlayerProfileData.dart';
import 'PlayerProfileVisuals.dart';

class PlayerDetailedStats extends StatelessWidget {
  const PlayerDetailedStats({super.key, required this.matches});
  final List<PlayerMatchData> matches;
  @override
  Widget build(BuildContext context) {
    final rows = matches
        .map((m) => m.performance.apiStats)
        .where((r) => r.isNotEmpty)
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    final c = AppColors.of(context);
    final groups = [
      for (final group in performanceStats.map((s) => s.group).toSet())
        if (performanceStats.any(
          (s) => s.group == group && s.total(rows) != null,
        ))
          group,
    ];
    return ProfilePanel(
      key: const ValueKey('player-detailed-stats'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Estatísticas detalhadas',
            style: TextStyle(
              color: c.text,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Do relatório das partidas (${rows.length} de ${matches.length}). '
            'Percentuais pelos totais das mesmas partidas.',
            style: TextStyle(color: c.muted, fontSize: 11.5, height: 1.4),
          ),
          for (final group in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 4),
              child: Text(
                group.toUpperCase(),
                style: TextStyle(
                  color: c.accent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                ),
              ),
            ),
            for (final s in performanceStats.where((s) => s.group == group))
              if (s.total(rows) case final value?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          s.label,
                          style: TextStyle(color: c.text, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '${NumberFormat.decimalPatternDigits(locale: 'pt_BR', decimalDigits: s.decimals).format(value)}${s.percentage ? '%' : ''}',
                        key: ValueKey('detailed-stat/${s.key}'),
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
