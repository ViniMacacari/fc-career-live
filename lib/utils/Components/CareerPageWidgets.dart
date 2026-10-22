import 'package:flutter/material.dart';

import 'CareerUiStyle.dart';

class CareerPageHeader extends StatelessWidget {
  const CareerPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.eyebrow,
    this.leading,
    this.footer,
  });
  final String title, subtitle;
  final String? eyebrow;
  final IconData icon;
  final Widget? leading, footer;
  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: c.accent.withValues(alpha: .25)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(c.accent.withValues(alpha: .16), c.panel),
            c.panel,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null) ...[
            Text(
              eyebrow!.toUpperCase(),
              style: TextStyle(
                color: c.accent,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading ?? CareerIconBadge(icon: icon, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (footer != null) ...[const SizedBox(height: 18), footer!],
        ],
      ),
    );
  }
}

class CareerIconBadge extends StatelessWidget {
  const CareerIconBadge({
    super.key,
    required this.icon,
    this.size = 42,
    this.color,
  });
  final IconData icon;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final accent = color ?? CareerUiColors(context).accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(size * .3),
        border: Border.all(color: accent.withValues(alpha: .2)),
      ),
      child: Icon(icon, color: accent, size: size * .5),
    );
  }
}

class CareerEmptyState extends StatelessWidget {
  const CareerEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.action,
  });
  final String title, subtitle;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: c.surface(radius: 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CareerIconBadge(icon: icon, size: 64),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted, fontSize: 12, height: 1.6),
                ),
                if (action != null) ...[const SizedBox(height: 20), action!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CareerMetricTile extends StatelessWidget {
  const CareerMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });
  final String label, value;
  final IconData icon;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CareerIconBadge(icon: icon, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: c.muted, fontSize: 13, height: 1.5),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              value,
              style: TextStyle(
                color: color ?? c.accent,
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
