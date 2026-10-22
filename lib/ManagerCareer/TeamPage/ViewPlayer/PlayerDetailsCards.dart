import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/AppColors.dart';
import 'PlayerProfileCharts.dart';
import 'PlayerProfileVisuals.dart';

class PlayerInfoGrid extends StatelessWidget {
  const PlayerInfoGrid({super.key, required this.title, required this.items});
  final String title;
  final List<({String label, String value, Widget? leading})> items;
  @override
  Widget build(BuildContext context) => ProfilePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, box) {
            final c = AppColors.of(context),
                columns = box.maxWidth >= 420 ? 3 : 2;
            final width = (box.maxWidth - (columns - 1) * 16) / columns;
            return Wrap(
              spacing: 16,
              runSpacing: 20,
              children: [
                for (final item in items)
                  SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.leading != null) ...[
                              item.leading!,
                              const SizedBox(width: 7),
                            ],
                            Expanded(
                              child: Text(
                                item.value,
                                style: TextStyle(
                                  color: c.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class PlayerHistoryCard extends StatelessWidget {
  const PlayerHistoryCard({
    super.key,
    required this.title,
    required this.value,
    required this.points,
    required this.onHistory,
    required this.onAdd,
    this.valueFormatter,
    this.compactAxis = false,
  });
  final String title, value;
  final List<ProfileChartPoint> points;
  final VoidCallback onHistory, onAdd;
  final String Function(num)? valueFormatter;
  final bool compactAxis;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final delta = points.length < 2
        ? null
        : points.last.value - points.first.value;
    final trend = delta == null
        ? null
        : '${delta > 0 ? '+' : ''}${valueFormatter?.call(delta) ?? NumberFormat.decimalPattern('pt_BR').format(delta)}';
    return ProfilePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Ver histórico de $title',
                onPressed: onHistory,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.list, size: 20),
              ),
              IconButton(
                tooltip: 'Adicionar registro de $title',
                onPressed: onAdd,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.add, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            value,
            key: ValueKey('player-history-value/$title'),
            style: TextStyle(
              color: c.accent,
              fontSize: 25,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (trend != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  Icon(
                    delta! < 0 ? Icons.trending_down : Icons.trending_up,
                    size: 16,
                    color: c.muted,
                  ),
                  Text(
                    '$trend desde o primeiro registro',
                    style: TextStyle(color: c.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          if (points.length > 1) ...[
            const SizedBox(height: 14),
            OverallChart(
              points: points,
              compactAxis: compactAxis,
              valueFormatter: valueFormatter,
              height: 168,
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                children: [
                  Icon(Icons.timeline, size: 18, color: c.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      points.isEmpty
                          ? 'Adicione registros para acompanhar a evolução.'
                          : 'Primeiro registro${points.single.date == null ? '' : ' em ${DateFormat('dd/MM/yyyy').format(points.single.date!)}'}.',
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
