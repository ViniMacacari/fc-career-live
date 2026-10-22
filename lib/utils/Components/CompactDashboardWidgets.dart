import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../Common/FixtureResultTile.dart';
import '../AppColors.dart';
import '../GameCatalog.dart';
import 'CareerUiStyle.dart';
import 'TeamLogo.dart';

class DashboardSection extends StatelessWidget {
  const DashboardSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: c.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: c.line),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  ?action,
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: TextStyle(color: c.muted, fontSize: 11, height: 1.4),
                ),
              ],
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class DashboardLink extends StatelessWidget {
  const DashboardLink(this.label, {super.key, required this.onTap, this.icon});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final accent = AppColors.of(context).accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          icon == null ? 8 : 6,
          4,
          icon == null ? 2 : 6,
          4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (icon == null)
              Icon(Icons.chevron_right_rounded, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}

class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.items});
  final List<(String value, String label, Color? color)> items;
  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    return IntrinsicHeight(
      child: Row(
        children: [
          for (final (i, (value, label, color)) in items.indexed) ...[
            if (i > 0) VerticalDivider(width: 17, thickness: 1, color: c.line),
            Expanded(
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: TextStyle(
                        color: color ?? c.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(color: c.muted, fontSize: 10.5),
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

class CompactMetrics extends StatelessWidget {
  const CompactMetrics({super.key, required this.items, this.columns = 3});
  final List<(String, String)> items;
  final int columns;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
      if (items.isEmpty) return const SizedBox.shrink();
      final capacity = (box.maxWidth / (90 * scale)).floor().clamp(1, columns);
      final rows = (items.length / capacity).ceil();
      final count = (items.length / rows).ceil().clamp(1, capacity);
      return Wrap(
        spacing: 10,
        runSpacing: 14,
        children: [
          for (final (value, label) in items)
            SizedBox(
              width: (box.maxWidth - (count - 1) * 10) / count,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      color: AppColors.of(context).muted,
                      fontSize: 12,
                      height: 1.25,
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

class RecordedFixtureTile extends StatelessWidget {
  const RecordedFixtureTile({
    super.key,
    required this.fixture,
    required this.version,
    required this.catalog,
    required this.onTap,
    this.detail,
  });
  final Map<String, Object?> fixture;
  final String version;
  final GameCatalog catalog;
  final VoidCallback onTap;
  final String? detail;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final date = DateTime.tryParse('${fixture['date']}');
    final opponent = catalog.teamLabel(
      version,
      '${fixture['oppositeTeamId']}',
      leagueId: fixture['oppositeTeamLeagueId']?.toString(),
    );
    final scored =
        fixture['playerTeamScore'] != null &&
        fixture['oppositeTeamScore'] != null;
    final result = fixtureResult(fixture);
    final color = !scored
        ? c.muted
        : result == FixtureResult.win
        ? c.success
        : result == FixtureResult.lose
        ? c.danger
        : c.warning;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: TeamLogo.lookup(
        fifaVersion: version,
        teamId: '${fixture['oppositeTeamId']}',
        leagueId: fixture['oppositeTeamLeagueId']?.toString(),
        size: 28,
      ),
      title: Text(
        opponent,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        [
          if (date != null) DateFormat('dd/MM/yyyy').format(date),
          if (fixture['stage']?.toString().isNotEmpty == true)
            '${fixture['stage']}',
          if (detail?.isNotEmpty == true) detail!,
        ].join(' · '),
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            scored
                ? '${fixture['playerTeamScore']} – ${fixture['oppositeTeamScore']}'
                : '—',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: color,
            ),
          ),
          if (fixture['playerTeamPenaltiesScore'] != null)
            Text(
              'Pên. ${fixture['playerTeamPenaltiesScore']}–${fixture['oppositeTeamPenaltiesScore'] ?? '—'}',
              style: const TextStyle(fontSize: 10),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}
