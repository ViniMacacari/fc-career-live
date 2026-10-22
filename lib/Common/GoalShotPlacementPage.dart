import '../utils/AppColors.dart';

import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/ManagerFixturePlayerPerformance.dart';

const _fieldWidth = 68.0;
const _fieldHeight = _fieldWidth * 2 / 3;

const penaltySpotLocation = GoalShotLocation(
  0.5,
  (_fieldHeight - _fieldWidth * 11 / 68) / _fieldHeight,
);

class GoalShotPlacementResult {
  const GoalShotPlacementResult(this.goalLocation, this.fieldLocation);
  final GoalShotLocation? goalLocation, fieldLocation;
}

GoalShotLocation _fromTap(Offset position, Size size) {
  if (size.width <= 0 || size.height <= 0) {
    return const GoalShotLocation(0.5, 0.5);
  }
  return GoalShotLocation(
    (position.dx / size.width).clamp(0, 1),
    (position.dy / size.height).clamp(0, 1),
  );
}

Offset goalFieldOffset(GoalShotLocation location, Size size) => Offset(
  location.x.clamp(0, 1) * size.width,
  (1 - location.y.clamp(0, 1)) * size.height,
);

GoalShotLocation goalFieldLocationAt(Offset position, Size size) {
  final tap = _fromTap(position, size);
  return GoalShotLocation(tap.x, 1 - tap.y);
}

class GoalShotPlacementPage extends StatefulWidget {
  const GoalShotPlacementPage({
    super.key,
    this.goalLocation,
    this.fieldLocation,
    this.isPenalty = false,
  });
  final GoalShotLocation? goalLocation, fieldLocation;
  final bool isPenalty;

  @override
  State<GoalShotPlacementPage> createState() => _GoalShotPlacementPageState();
}

class _GoalShotPlacementPageState extends State<GoalShotPlacementPage> {
  late GoalShotLocation? _goal = widget.goalLocation;
  late GoalShotLocation? _field =
      widget.fieldLocation ?? (widget.isPenalty ? penaltySpotLocation : null);

  Widget _area({
    required String title,
    required String description,
    required double aspectRatio,
    required Key paintKey,
    required CustomPainter Function(GoalShotLocation?) painter,
    required GoalShotLocation? value,
    required ValueChanged<GoalShotLocation> onChanged,
    GoalShotLocation Function(Offset, Size) fromTap = _fromTap,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(description, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: aspectRatio,
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                onTapDown: (details) => onChanged(
                  fromTap(details.localPosition, constraints.biggest),
                ),
                child: CustomPaint(
                  key: paintKey,
                  size: constraints.biggest,
                  painter: painter(value),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value == null
                ? 'goalShotMap.noShotSelected'.tr()
                : '${'goalShotMap.normalizedCoordinates'.tr()}: '
                      '${value.x.toStringAsFixed(2)}, ${value.y.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('goalShotMap.title'.tr()),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            _goal = null;
            _field = null;
          }),
          child: Text('goalShotMap.clear'.tr()),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () =>
          Navigator.pop(context, GoalShotPlacementResult(_goal, _field)),
      icon: const Icon(Icons.check),
      label: Text('common.apply'.tr()),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        _area(
          title: 'goalShotMap.tapInside'.tr(),
          description: 'goalShotMap.tapDescription'.tr(),
          aspectRatio: 3,
          paintKey: const ValueKey('shot-goal-surface'),
          painter: (value) => _GoalPainter(value, AppColors.of(context)),
          value: _goal,
          onChanged: (value) => setState(() => _goal = value),
        ),
        _area(
          title: 'goalShotMap.tapInsideField'.tr(),
          description: 'goalShotMap.tapFieldDescription'.tr(),
          aspectRatio: _fieldWidth / _fieldHeight,
          paintKey: const ValueKey('shot-field-surface'),
          painter: (value) => _FieldPainter(value, AppColors.of(context)),
          value: _field,
          onChanged: (value) => setState(() => _field = value),
          fromTap: goalFieldLocationAt,
        ),
      ],
    ),
  );
}

void _paintMarker(Canvas canvas, Offset center) {
  final bounds = Rect.fromCircle(center: center, radius: 9);
  canvas
    ..drawCircle(
      center,
      9,
      Paint()
        ..color = AppColors.markerShadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    )
    ..drawCircle(
      center,
      9,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.markerHighlight,
            AppColors.markerMiddle,
            AppColors.markerEdge,
          ],
        ).createShader(bounds),
    )
    ..drawCircle(
      center,
      9,
      Paint()
        ..color = AppColors.markerInk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    )
    ..drawCircle(center, 2, Paint()..color = AppColors.markerInk);
}

void _paintDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
  final delta = end - start;
  final length = delta.distance;
  if (length == 0) return;
  final direction = delta / length;
  for (var distance = 0.0; distance < length; distance += 9) {
    canvas.drawLine(
      start + direction * distance,
      start + direction * math.min(distance + 4, length),
      paint,
    );
  }
}

class _GoalPainter extends CustomPainter {
  const _GoalPainter(this.location, this.colors);
  final AppColors colors;
  final GoalShotLocation? location;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final back = Rect.fromLTRB(
      size.width * .045,
      size.height * .11,
      size.width * .955,
      size.height * .9,
    );
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.pitchStart, colors.pitchEnd, colors.pitchEnd],
        ).createShader(rect),
    );
    void side(List<Offset> points, Color color) {
      canvas.drawPath(Path()..addPolygon(points, true), Paint()..color = color);
    }

    side([
      rect.topLeft,
      rect.topRight,
      back.topRight,
      back.topLeft,
    ], colors.pitchLine);
    side([
      rect.topLeft,
      back.topLeft,
      back.bottomLeft,
      rect.bottomLeft,
    ], colors.pitchStart);
    side([
      rect.topRight,
      rect.bottomRight,
      back.bottomRight,
      back.topRight,
    ], colors.pitchEnd);
    side([
      rect.bottomLeft,
      back.bottomLeft,
      back.bottomRight,
      rect.bottomRight,
    ], colors.pitchEnd);

    final net = Paint()
      ..color = colors.muted.withValues(alpha: .28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7;
    final sides = Paint()
      ..color = colors.muted.withValues(alpha: .2)
      ..strokeWidth = .65;
    for (var column = 0; column <= 24; column++) {
      final fraction = column / 24;
      final x = back.left + back.width * fraction;
      canvas.drawPath(
        Path()
          ..moveTo(x, back.top)
          ..quadraticBezierTo(
            x + size.width * .003,
            back.center.dy,
            x,
            back.bottom,
          ),
        net,
      );
      canvas
        ..drawLine(Offset(size.width * fraction, 0), Offset(x, back.top), sides)
        ..drawLine(
          Offset(x, back.bottom),
          Offset(size.width * fraction, size.height),
          sides,
        );
    }
    for (var row = 0; row <= 8; row++) {
      final fraction = row / 8;
      final y = back.top + back.height * fraction;
      canvas.drawPath(
        Path()
          ..moveTo(back.left, y)
          ..quadraticBezierTo(
            back.center.dx,
            y + size.height * .008,
            back.right,
            y,
          ),
        net,
      );
      canvas
        ..drawLine(
          Offset(0, size.height * fraction),
          Offset(back.left, y),
          sides,
        )
        ..drawLine(
          Offset(back.right, y),
          Offset(size.width, size.height * fraction),
          sides,
        );
    }
    final grid = Paint()
      ..color = colors.text.withValues(alpha: .22)
      ..strokeWidth = .8;
    for (final x in [0.28, 0.72]) {
      _paintDashedLine(
        canvas,
        Offset(size.width * x, 0),
        Offset(size.width * x, size.height),
        grid,
      );
    }
    for (final y in [1 / 3, 2 / 3]) {
      _paintDashedLine(
        canvas,
        Offset(0, size.height * y),
        Offset(size.width, size.height * y),
        grid,
      );
    }
    canvas.restore();
    canvas.drawRect(
      rect,
      Paint()
        ..color = colors.background.withValues(alpha: .45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.text, colors.muted, colors.text],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawRect(
      rect.deflate(.8),
      Paint()
        ..color = Colors.white.withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7,
    );
    if (location case final location?) {
      _paintMarker(
        canvas,
        Offset(location.x * size.width, location.y * size.height),
      );
    }
  }

  @override
  bool shouldRepaint(_GoalPainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate.location != location;
}

final _arcAngle = math.asin(5.5 / 9.15);

const goalFieldAspectRatio = _fieldWidth / _fieldHeight;

void paintGoalFieldLines(Canvas canvas, Size size, Paint line) {
  final scale = size.width / _fieldWidth;
  Offset point(double x, double y) => Offset(x * scale, y * scale);
  canvas
    ..drawRect(Offset.zero & size, line)
    ..drawRect(
      Rect.fromPoints(
        point((_fieldWidth - 40.32) / 2, 0),
        point((_fieldWidth + 40.32) / 2, 16.5),
      ),
      line,
    )
    ..drawRect(
      Rect.fromPoints(
        point((_fieldWidth - 18.32) / 2, 0),
        point((_fieldWidth + 18.32) / 2, 5.5),
      ),
      line,
    )
    ..drawCircle(point(_fieldWidth / 2, 11), 3, Paint()..color = line.color)
    ..drawArc(
      Rect.fromCircle(center: point(_fieldWidth / 2, 11), radius: 9.15 * scale),
      _arcAngle,
      math.pi - 2 * _arcAngle,
      false,
      line,
    );
}

class _FieldPainter extends CustomPainter {
  const _FieldPainter(this.location, this.colors);
  final AppColors colors;
  final GoalShotLocation? location;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.pitchStart, colors.pitchStart, colors.pitchEnd],
        ).createShader(rect),
    );
    for (var band = 0; band < 8; band += 2) {
      canvas.drawRect(
        Rect.fromLTWH(0, band * size.height / 8, size.width, size.height / 8),
        Paint()..color = Colors.white.withValues(alpha: .045),
      );
    }
    final grass = Paint()
      ..color = Colors.white.withValues(alpha: .025)
      ..strokeWidth = .4;
    for (var x = 2.0; x < size.width; x += 3) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grass);
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.1, -.7),
          radius: 1.3,
          colors: [Colors.white.withValues(alpha: .06), Colors.transparent],
        ).createShader(rect),
    );
    canvas.restore();
    paintGoalFieldLines(
      canvas,
      size,
      Paint()
        ..color = Colors.black.withValues(alpha: .16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round,
    );
    paintGoalFieldLines(
      canvas,
      size,
      Paint()
        ..color = colors.muted.withValues(alpha: .85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    if (location case final location?) {
      _paintMarker(canvas, goalFieldOffset(location, size));
    }
  }

  @override
  bool shouldRepaint(_FieldPainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate.location != location;
}
