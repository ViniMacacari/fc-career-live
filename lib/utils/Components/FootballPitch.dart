import '../AppColors.dart';

import 'package:flutter/material.dart';

import '../FootballFormations.dart';

class SquadPitchMetrics {
  SquadPitchMetrics(double availableHeight, {bool hasReserves = true})
    : benchHeight = hasReserves
          ? (availableHeight * .19).clamp(112.0, 184.0)
          : 64.0,
      availableHeight = availableHeight;
  final double availableHeight, benchHeight;
  double get pitchHeight =>
      (availableHeight - benchHeight - 68).clamp(160.0, double.infinity);
  static double forMatch(BuildContext context, {bool hasReserves = true}) {
    final view = MediaQuery.of(context);
    final window = View.of(context);
    final safe = EdgeInsets.fromViewPadding(
      window.viewPadding,
      window.devicePixelRatio,
    );
    return SquadPitchMetrics(
      view.size.height - safe.vertical - kToolbarHeight - 8,
      hasReserves: hasReserves,
    ).pitchHeight;
  }
}

class FootballPitch extends StatelessWidget {
  const FootballPitch({
    super.key,
    required this.formation,
    required this.slotBuilder,
  });
  final String formation;
  final Widget Function(int x, int y) slotBuilder;

  @override
  Widget build(BuildContext context) {
    final shape = footballFormationShape(formation);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.of(context).pitchStart,
            AppColors.of(context).pitchEnd,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.of(context).pitchLine),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: FootballPitchPainter(AppColors.of(context)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              children: [
                for (var y = 0; y < shape.length; y++)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var x = 0; x < shape[y]; x++)
                          Expanded(child: slotBuilder(x, y)),
                      ],
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

class FootballPitchPainter extends CustomPainter {
  const FootballPitchPainter(this.colors);
  final AppColors colors;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = colors.text.withValues(alpha: .18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    canvas.drawRect(
      Rect.fromLTWH(12, 12, size.width - 24, size.height - 24),
      p,
    );
    canvas.drawLine(
      Offset(12, size.height / 2),
      Offset(size.width - 12, size.height / 2),
      p,
    );
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 35, p);
    canvas.drawRect(
      Rect.fromLTWH(size.width * .27, 12, size.width * .46, 52),
      p,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width * .27, size.height - 64, size.width * .46, 52),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant FootballPitchPainter oldDelegate) =>
      oldDelegate.colors != colors;
}
