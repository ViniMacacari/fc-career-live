import 'package:flutter/material.dart';

import '../AppColors.dart';

class CareerUiColors {
  CareerUiColors(BuildContext context) {
    final c = AppColors.of(context);
    accent = c.accent;
    panel = c.panel;
    text = c.text;
    muted = c.muted;
    line = c.line.withValues(alpha: .55);
    green = c.success;
    amber = c.warning;
    red = c.danger;
  }
  late final Color accent, panel, text, muted, line, green, amber, red;
  BoxDecoration surface({double radius = 22}) => BoxDecoration(
    color: panel,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: line),
  );
}
