import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/AppColors.dart';

class PitchMenuItem {
  const PitchMenuItem(this.value, this.label, this.icon);
  final String value, label;
  final Widget icon;
}

Future<String?> showPitchPlayerMenu(
  BuildContext context, {
  required Rect anchor,
  required List<PitchMenuItem> items,
  Widget? avatar,
}) {
  final size = MediaQuery.sizeOf(context);
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar opções do jogador',
    barrierColor: Colors.black.withValues(alpha: .5),
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) =>
        _PitchPlayerMenu(anchor: anchor, items: items, avatar: avatar),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        alignment: Alignment(
          anchor.center.dx / size.width * 2 - 1,
          anchor.center.dy / size.height * 2 - 1,
        ),
        scale: Tween(begin: .8, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        ),
        child: child,
      ),
    ),
  );
}

class _PitchPlayerMenu extends StatelessWidget {
  const _PitchPlayerMenu({
    required this.anchor,
    required this.items,
    this.avatar,
  });
  final Rect anchor;
  final List<PitchMenuItem> items;
  final Widget? avatar;

  static const _button = 46.0, _margin = 6.0;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final center = anchor.center;
    final count = items.length;
    final ring = anchor.shortestSide / 2 + 5;
    final radius = math.max(
      math.max(ring + _button / 2 + 10, 72.0),
      count * (_button + 6) / (2 * math.pi),
    );
    final angles = [
      for (var i = 0; i < count; i++) -math.pi / 2 + 2 * math.pi * i / count,
    ];
    final half = _button / 2;
    final points = [
      for (final angle in angles)
        Offset(
          center.dx + radius * math.cos(angle),
          center.dy + radius * math.sin(angle),
        ),
    ];
    double shift(Iterable<double> values, double low, double high) {
      final min = values.reduce(math.min), max = values.reduce(math.max);
      if (min < low) return low - min;
      if (max > high) return high - max;
      return 0;
    }

    final move = Offset(
      shift(
        points.map((p) => p.dx),
        half + _margin,
        size.width - half - _margin,
      ),
      shift(
        points.map((p) => p.dy),
        padding.top + half + _margin,
        size.height - padding.bottom - half - _margin,
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
          ),
        ),
        Positioned(
          left: center.dx - ring,
          top: center.dy - ring,
          child: IgnorePointer(
            child: Container(
              width: ring * 2,
              height: ring * 2,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.accent, width: 2.5),
              ),
              child: avatar == null ? null : ClipOval(child: avatar),
            ),
          ),
        ),
        for (final (i, item) in items.indexed)
          Positioned(
            left: points[i].dx + move.dx - half,
            top: points[i].dy + move.dy - half,
            child: Tooltip(
              message: item.label,
              child: Material(
                color: c.panel,
                elevation: 6,
                shape: CircleBorder(side: BorderSide(color: c.line)),
                child: InkWell(
                  key: ValueKey('pitch-action-${item.value}'),
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(context, item.value),
                  child: Semantics(
                    button: true,
                    label: item.label,
                    child: SizedBox.square(
                      dimension: _button,
                      child: Center(child: item.icon),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
