import 'package:flutter/material.dart';

import '../utils/Components/CareerUiStyle.dart';
import '../utils/FixtureTablePosition.dart';

class FixturePositionIndicator extends StatelessWidget {
  const FixturePositionIndicator({super.key, required this.value});
  final FixtureTablePosition value;

  @override
  Widget build(BuildContext context) {
    final colors = CareerUiColors(context), change = value.change;
    final color = change == 0
        ? colors.muted
        : (change ?? 0) > 0
        ? colors.green
        : colors.red;
    final tooltip =
        '${value.movement}${value.previous == null ? '' : ' · ${value.previous}º → ${value.position}º'}';
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: '${value.position}º lugar. $tooltip',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${value.position ?? '—'}',
              style: TextStyle(color: colors.text, fontSize: 14),
            ),
            if (change != null) ...[
              const SizedBox(width: 5),
              Icon(
                change == 0
                    ? Icons.horizontal_rule_rounded
                    : change > 0
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                key: const ValueKey('fixture-position-direction'),
                color: color,
                size: 17,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
