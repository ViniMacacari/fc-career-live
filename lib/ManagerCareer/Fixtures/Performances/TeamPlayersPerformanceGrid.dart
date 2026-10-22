import '../../../Common/FixtureCaptainPanel.dart';
import '../../../utils/AppColors.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../models/ManagerFixturePlayerPerformance.dart';
import '../../../utils/eventTimeUtils.dart';

const _red = AppColors.eventRed;

Color performanceRatingColor(num? rating) {
  if (rating == null) return AppColors.ratingUnknown;
  if (rating >= 8) return AppColors.ratingExcellent;
  if (rating >= 7) return AppColors.ratingGood;
  if (rating >= 6.5) return AppColors.ratingAverage;
  if (rating >= 6) return AppColors.ratingBelowAverage;
  return AppColors.ratingPoor;
}

class TeamPlayersPerformanceGrid extends StatefulWidget {
  const TeamPlayersPerformanceGrid({
    super.key,
    required this.rows,
    required this.names,
    required this.positions,
    required this.playerOfMatchId,
    this.onTap,
    this.onLongPress,
    this.showHeader = true,
    this.onAddPlayer,
    this.captainIds = const {},
    this.leading,
  });
  final List<ManagerFixturePlayerPerformance> rows;
  final Set<String> captainIds;
  final Map<String, String> names, positions;
  final String? playerOfMatchId;
  final ValueChanged<ManagerFixturePlayerPerformance>? onTap;
  final ValueChanged<ManagerFixturePlayerPerformance>? onLongPress;
  final ValueChanged<ManagerFixturePlayerPerformance>? onAddPlayer;

  final bool showHeader;

  final Widget? leading;

  @override
  State<TeamPlayersPerformanceGrid> createState() =>
      _TeamPlayersPerformanceGridState();
}

class _TeamPlayersPerformanceGridState
    extends State<TeamPlayersPerformanceGrid> {
  bool _ratingSort = false;

  static const _glyphSize = 15.0;
  Widget _glyph(Widget icon) => SizedBox.square(
    dimension: _glyphSize,
    child: Center(child: icon),
  );

  Widget _event(Widget icon, [String? note]) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _glyph(icon),
      if (note != null) ...[
        const SizedBox(width: 3),
        Text(
          note,
          style: TextStyle(
            color: AppColors.of(context).muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ],
    ],
  );

  Widget _card(String asset) => Image.asset(asset, width: 9, height: 12);

  List<Widget> _events(ManagerFixturePlayerPerformance row) {
    String? times(int count) => count > 1 ? '×$count' : null;
    String? minute(List<PerformanceSubstitutionDetails> subs) {
      final first = getSortedDetails(subs).first;
      return first.minute == null
          ? null
          : '${first.inferred ? '~' : ''}${formatEventMinute(first.minute, first.addedMinute)}';
    }

    final goals = row.goalDetails.where((goal) => !goal.isPenalty).length;
    final penalties = row.goalDetails.where((goal) => goal.isPenalty).length;
    final ins = row.substitutionDetails
        .where((sub) => sub.type == SubstitutionType.inGame)
        .toList();
    final outs = row.substitutionDetails
        .where((sub) => sub.type != SubstitutionType.inGame)
        .toList();
    return [
      if (widget.playerOfMatchId == row.playerInstanceId)
        _event(
          const Icon(
            TablerIcons.starFilled,
            color: AppColors.missedEvent,
            size: 14,
          ),
        ),
      if (ins.isNotEmpty)
        _event(
          const LineupSubstitutionIcon(incoming: true, size: 12),
          minute(ins),
        ),
      if (outs.isNotEmpty)
        _event(
          const LineupSubstitutionIcon(incoming: false, size: 12),
          minute(outs),
        ),
      if (goals > 0)
        _event(const Icon(TablerIcons.ballFootball, size: 14), times(goals)),
      if (penalties > 0) _event(const GoalNetIcon(size: 11), times(penalties)),
      if (row.assistDetails.isNotEmpty)
        _event(
          SvgPicture.asset(
            'assets/images/assistBoot.svg',
            width: 15,
            height: 15,
            colorFilter: ColorFilter.mode(
              AppColors.of(context).text,
              BlendMode.srcIn,
            ),
          ),
          times(row.assistDetails.length),
        ),
      if (row.yellowCardDetails.isNotEmpty)
        _event(
          _card('assets/images/yellowCard.png'),
          times(row.yellowCardDetails.length),
        ),
      if (row.redCardDetails.isNotEmpty)
        _event(_card('assets/images/redCard.png')),
      if (row.ownGoalDetails.isNotEmpty)
        _event(
          const Icon(TablerIcons.ballFootball, color: _red, size: 14),
          times(row.ownGoalDetails.length),
        ),
      if (row.missedPenaltyDetails.isNotEmpty)
        _event(
          const GoalNetIcon(color: _red, size: 11),
          times(row.missedPenaltyDetails.length),
        ),
      if (row.injuryDetails.isNotEmpty)
        _event(const Icon(TablerIcons.firstAidKit, color: _red, size: 14)),
    ];
  }

  Widget _row(ManagerFixturePlayerPerformance row, int index) {
    final c = AppColors.of(context);
    final events = _events(row);
    final missingName =
        widget.onAddPlayer != null &&
        (widget.names[row.playerInstanceId] ?? '').trim().isEmpty;
    return Material(
      key: ValueKey('performance-row-${row.playerInstanceId}'),
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onTap == null ? null : () => widget.onTap!(row),
        onLongPress: widget.onLongPress == null
            ? null
            : () => widget.onLongPress!(row),
        child: Container(
          height: 44,
          decoration: index == 0
              ? null
              : BoxDecoration(
                  border: Border(
                    top: BorderSide(color: c.line.withValues(alpha: .4)),
                  ),
                ),
          padding: EdgeInsets.symmetric(horizontal: widget.showHeader ? 14 : 4),
          child: LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                SizedBox(
                  width: 38,
                  child: Text(
                    widget.positions[row.playerInstanceId] ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .3,
                    ),
                  ),
                ),
                if (widget.captainIds.contains(row.playerInstanceId)) ...[
                  const CaptainBadge(size: 15),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    missingName
                        ? 'Sem nome'
                        : widget.names[row.playerInstanceId] ??
                              row.playerInstanceId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: missingName ? c.muted : c.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (events.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth * .5),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        key: ValueKey(
                          'performance-events-${row.playerInstanceId}',
                        ),
                        children: [
                          for (final (i, event) in events.indexed) ...[
                            if (i > 0) const SizedBox(width: 8),
                            event,
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 10),
                if (missingName)
                  SizedBox.square(
                    dimension: 28,
                    child: IconButton(
                      key: ValueKey(
                        'add-opponent-player-${row.playerInstanceId}',
                      ),
                      tooltip: 'Adicionar jogador',
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      style: IconButton.styleFrom(
                        backgroundColor: c.raised,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: Icon(TablerIcons.plus, color: c.text),
                      onPressed: () => widget.onAddPlayer!(row),
                    ),
                  )
                else
                  Container(
                    width: 36,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: row.avgRating == null
                          ? c.raised
                          : performanceRatingColor(row.avgRating),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      row.avgRating?.toStringAsFixed(1) ?? '—',
                      style: TextStyle(
                        color: row.avgRating == null
                            ? c.muted
                            : AppColors.onColor(
                                performanceRatingColor(row.avgRating),
                              ),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final sorted = [...widget.rows];
    if (_ratingSort) {
      sorted.sort((a, b) => (b.avgRating ?? -1).compareTo(a.avgRating ?? -1));
    }
    final rows = Column(
      children: [
        for (var index = 0; index < sorted.length; index++)
          _row(sorted[index], index),
      ],
    );
    if (!widget.showHeader) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [?widget.leading, rows],
      );
    }
    return Material(
      color: c.panel,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'fixtures.playerPerformance'.tr(),
                    style: TextStyle(
                      color: c.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilterChip(
                  key: const ValueKey('performance-sort-rating'),
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                  selected: _ratingSort,
                  avatar: Icon(
                    Icons.swap_vert_rounded,
                    size: 16,
                    color: _ratingSort ? c.accent : c.muted,
                  ),
                  label: Text(
                    _ratingSort ? 'Por nota' : 'Por posição',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onSelected: (value) => setState(() => _ratingSort = value),
                ),
              ],
            ),
          ),
          if (widget.leading != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: widget.leading,
            ),
          rows,
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class LineupSubstitutionIcon extends StatelessWidget {
  const LineupSubstitutionIcon({
    super.key,
    required this.incoming,
    this.size = 15,
  });
  final bool incoming;
  final double size;
  @override
  Widget build(BuildContext context) => Icon(
    incoming ? TablerIcons.triangleFilled : TablerIcons.triangleInvertedFilled,
    color: incoming ? AppColors.ratingGood : _red,
    size: size,
  );
}

class GoalNetIcon extends StatelessWidget {
  const GoalNetIcon({super.key, this.color, this.size = 17});
  final Color? color;
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size * 1.25, size),
    painter: _GoalNetPainter(color ?? AppColors.of(context).text),
  );
}

class _GoalNetPainter extends CustomPainter {
  const _GoalNetPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * .11
      ..strokeCap = StrokeCap.round;
    final top = size.height * .12;
    final path = Path()
      ..moveTo(size.width * .06, size.height * .95)
      ..lineTo(size.width * .06, top)
      ..lineTo(size.width * .94, top)
      ..lineTo(size.width * .94, size.height * .95);
    canvas
      ..drawPath(path, stroke)
      ..drawCircle(
        Offset(size.width / 2, size.height * .62),
        size.height * .26,
        stroke..strokeWidth = size.height * .09,
      );
  }

  @override
  bool shouldRepaint(covariant _GoalNetPainter oldDelegate) =>
      oldDelegate.color != color;
}
