import '../../../utils/AppColors.dart';

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../Common/GoalShotPlacementPage.dart'
    show goalFieldAspectRatio, goalFieldOffset, paintGoalFieldLines;
import '../../../models/ManagerFixturePlayerPerformance.dart';
import '../../../utils/databaseUtils.dart';
import '../../../utils/Components/CompetitionLogo.dart';

export 'PlayerProfileCharts.dart' show OverallChart;

class PlayerProfileScroll extends StatelessWidget {
  const PlayerProfileScroll({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
  });
  final List<Widget> children;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      if (context.findAncestorWidgetOfExactType<NestedScrollView>() != null)
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
      SliverPadding(
        padding: padding,
        sliver: SliverList(delegate: SliverChildListDelegate(children)),
      ),
    ],
  );
}

class ProfilePanel extends StatelessWidget {
  const ProfilePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.of(context).panel,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: AppColors.of(context).line.withValues(alpha: .45),
      ),
    ),
    child: child,
  );
}

class ProfileLine extends StatelessWidget {
  const ProfileLine(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: AppColors.of(context).muted, fontSize: 13),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(color: AppColors.of(context).text, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

class ProfileRating extends StatelessWidget {
  const ProfileRating(
    this.rating, {
    super.key,
    this.large = false,
    this.small = false,
  });
  final double? rating;
  final bool large;

  final bool small;
  @override
  Widget build(BuildContext context) {
    final color = rating == null
        ? AppColors.of(context).muted
        : rating! >= 8
        ? AppColors.ratingExcellent
        : rating! >= 7
        ? AppColors.profileGoodRating
        : rating! >= 6
        ? AppColors.profileAverageRating
        : AppColors.lowRating;
    final size = large
        ? 53.0
        : small
        ? 29.0
        : 40.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(small ? 9 : 12),
      ),
      child: Text(
        rating?.toStringAsFixed(1) ?? '–',
        style: TextStyle(
          fontSize: large
              ? 17
              : small
              ? 12
              : 14,
          color: AppColors.onColor(color),
        ),
      ),
    );
  }
}

class ProfilePortrait extends StatelessWidget {
  const ProfilePortrait({
    super.key,
    required this.version,
    this.realPlayerId,
    this.customAvatarFilePath,
    this.width = 56,
    this.height = 72,
  });
  final String version;
  final String? realPlayerId, customAvatarFilePath;
  final double width, height;
  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: width,
      height: height,
      color: AppColors.of(context).raised,
      child: Icon(Icons.person, color: AppColors.of(context).muted),
    );
    final local = CustomImageFiles.absolute(customAvatarFilePath);
    if (local != null && File(local).existsSync()) {
      return Image.file(
        File(local),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    final url = getPlayerImageUrl(realPlayerId, version);
    if (url == null) return fallback;
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}

class TournamentBadge extends StatelessWidget {
  const TournamentBadge({
    super.key,
    required this.version,
    required this.tournamentId,
    this.size = 26,
  });
  final String version, tournamentId;
  final double size;
  @override
  Widget build(BuildContext context) => CompetitionLogo(
    version: version,
    competitionId: tournamentId,
    size: size,
  );
}

class PitchMap extends StatelessWidget {
  const PitchMap({super.key, required this.locations});
  final List<GoalShotLocation> locations;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: goalFieldAspectRatio,
    child: CustomPaint(
      painter: _PitchMapPainter(locations, AppColors.of(context)),
    ),
  );
}

class _PitchMapPainter extends CustomPainter {
  const _PitchMapPainter(this.locations, this.colors);
  final AppColors colors;
  final List<GoalShotLocation> locations;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(7)),
      Paint()..color = colors.pitchStart,
    );
    for (var i = 0; i < 8; i++) {
      canvas.drawRect(
        Rect.fromLTWH(i * size.width / 8, 0, size.width / 16, size.height),
        Paint()..color = colors.text.withValues(alpha: .035),
      );
    }
    final line = Paint()
      ..color = colors.text.withValues(alpha: .48)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    paintGoalFieldLines(canvas, size, line);
    final outline = Paint()
      ..color = line.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final location in locations) {
      final center = goalFieldOffset(location, size);
      canvas
        ..drawCircle(center, 9, Paint()..color = AppColors.goalMarker)
        ..drawCircle(center, 9, outline);
    }
  }

  @override
  bool shouldRepaint(covariant _PitchMapPainter old) =>
      old.colors != colors || old.locations != locations;
}

class GoalMouth extends StatelessWidget {
  const GoalMouth({super.key, required this.locations});
  final List<GoalShotLocation> locations;
  @override
  Widget build(BuildContext context) {
    final cells = List<int>.filled(9, 0);
    for (final location in locations) {
      final x = location.x < .28
          ? 0
          : location.x < .72
          ? 1
          : 2;
      final y = (location.y.clamp(0, .999) * 3).floor();
      cells[y * 3 + x]++;
    }
    final largest = cells.fold<int>(1, (a, b) => a > b ? a : b);
    return AspectRatio(
      aspectRatio: 2.8,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.of(context).line, width: 3),
          color: AppColors.of(context).pitchStart,
        ),
        child: Column(
          children: [
            for (var y = 0; y < 3; y++)
              Expanded(
                child: Row(
                  children: [
                    for (var x = 0; x < 3; x++)
                      Expanded(
                        child: Semantics(
                          label:
                              '${const ['Alta', 'Média', 'Baixa'][y]}, ${const ['esquerda', 'centro', 'direita'][x]}: ${cells[y * 3 + x]} gols',
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.of(context).line,
                                width: .5,
                              ),
                              color: cells[y * 3 + x] == 0
                                  ? null
                                  : AppColors.of(context).accent.withValues(
                                      alpha:
                                          .12 + .4 * cells[y * 3 + x] / largest,
                                    ),
                            ),
                            child: Text(
                              '${cells[y * 3 + x]}',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: cells[y * 3 + x] == 0
                                    ? AppColors.of(context).text
                                    : AppColors.onColor(
                                        Color.alphaBlend(
                                          AppColors.of(
                                            context,
                                          ).accent.withValues(
                                            alpha:
                                                .12 +
                                                .4 * cells[y * 3 + x] / largest,
                                          ),
                                          AppColors.of(context).pitchStart,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
