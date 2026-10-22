import 'package:flutter/material.dart';

import '../ManagerCareer/Fixtures/Performances/TeamPlayersPerformanceGrid.dart'
    show performanceRatingColor;
import '../utils/AppColors.dart';
import 'FixtureResultTile.dart';

class MatchSegmented<T> extends StatelessWidget {
  const MatchSegmented({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.height = 40,
  });
  final T value;
  final List<MatchSegment<T>> items;
  final ValueChanged<T> onChanged;
  final double height;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      constraints: BoxConstraints(minHeight: height),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.raised.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (final item in items)
              Expanded(
                child: GestureDetector(
                  key: item.key,
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(item.value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: item.value == value ? c.panel : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      border: item.value == value
                          ? Border.all(color: c.line)
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (item.leading != null) ...[
                          item.leading!,
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: item.value == value ? c.accent : c.muted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MatchSegment<T> {
  const MatchSegment(this.value, this.label, {this.key, this.leading});
  final T value;
  final String label;
  final Key? key;
  final Widget? leading;
}

class MatchResultChip extends StatelessWidget {
  const MatchResultChip({super.key, required this.fixture});
  final Map<String, Object?> fixture;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (fixture['playerTeamScore'] == null ||
        fixture['oppositeTeamScore'] == null) {
      return const SizedBox.shrink();
    }
    final (label, color) = switch (fixtureResult(fixture)) {
      FixtureResult.win => ('Vitória', c.success),
      FixtureResult.draw => ('Empate', c.warning),
      FixtureResult.lose => ('Derrota', c.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class MatchRating extends StatelessWidget {
  const MatchRating(this.rating, {super.key, this.size = 12.5});
  final num? rating;
  final double size;
  @override
  Widget build(BuildContext context) {
    final color = performanceRatingColor(rating);
    return Container(
      constraints: BoxConstraints(minWidth: size * 2.6),
      padding: EdgeInsets.symmetric(horizontal: size * .45, vertical: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: rating == null ? AppColors.of(context).raised : color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        rating?.toStringAsFixed(1) ?? '—',
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

class MatchActionTile extends StatelessWidget {
  const MatchActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool highlighted;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: c.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.line),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: highlighted ? .22 : .1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: c.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MatchFormationBar extends StatelessWidget {
  const MatchFormationBar({
    super.key,
    required this.title,
    required this.formation,
    required this.count,
    this.onTap,
    this.trailing,
  });
  final String title, formation, count;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: c.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.line),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: Row(
            children: [
              Icon(Icons.grid_view_rounded, color: c.accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: c.muted, fontSize: 11)),
                    Text(
                      formation.isEmpty ? '—' : formation,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Text(count, style: TextStyle(color: c.muted, fontSize: 12)),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.expand_more_rounded, color: c.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class MatchPlayerRow extends StatelessWidget {
  const MatchPlayerRow({
    super.key,
    required this.avatar,
    required this.name,
    this.detail,
    this.events,
    this.rating,
    this.onTap,
  });
  final Widget avatar;
  final String name;
  final String? detail;
  final Widget? events;
  final num? rating;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (detail?.isNotEmpty == true)
                    Text(
                      detail!,
                      style: TextStyle(color: c.muted, fontSize: 11),
                    ),
                  if (events != null) ...[const SizedBox(height: 2), events!],
                ],
              ),
            ),
            if (rating != null) ...[
              const SizedBox(width: 10),
              MatchRating(rating),
            ],
          ],
        ),
      ),
    );
  }
}

class MatchBenchPanel extends StatelessWidget {
  const MatchBenchPanel({
    super.key,
    required this.count,
    required this.children,
    this.action,
    this.empty = 'Nenhum reserva relacionado.',
  });
  final int count;
  final List<Widget> children;
  final Widget? action;
  final String empty;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Reservas relacionados · $count',
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
          const SizedBox(height: 4),
          if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 4, 10),
              child: Text(
                empty,
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            )
          else
            for (final (i, child) in children.indexed) ...[
              if (i > 0)
                Divider(height: 1, color: c.line.withValues(alpha: .4)),
              child,
            ],
        ],
      ),
    );
  }
}

class MatchHint extends StatelessWidget {
  const MatchHint(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: c.muted),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: c.muted, fontSize: 11.5, height: 1.4),
          ),
        ),
      ],
    );
  }
}
