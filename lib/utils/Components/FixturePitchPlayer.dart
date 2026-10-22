import '../../Common/FixtureCaptainPanel.dart';
import '../AppColors.dart';
import 'PitchPlayerCard.dart';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/ManagerFixturePlayerPerformance.dart';
import '../eventTimeUtils.dart';

import '../../../ManagerCareer/Fixtures/Performances/TeamPlayersPerformanceGrid.dart'
    show performanceRatingColor, LineupSubstitutionIcon;

class FixturePitchPlayer extends StatelessWidget {
  const FixturePitchPlayer({
    super.key,
    required this.id,
    required this.name,
    required this.avatar,
    this.shirtNumber,
    this.position = '',
    this.rating,
    this.yellow = false,
    this.red = false,
    this.substitutionIn = false,
    this.substitutionOut = false,
    this.onTap,
    this.captain = false,
    this.performance,
  });
  final String id, name, position;
  final Widget Function(double radius) avatar;
  final Object? shirtNumber;
  final double? rating;
  final bool yellow, red, substitutionIn, substitutionOut, captain;
  final VoidCallback? onTap;
  final ManagerFixturePlayerPerformance? performance;

  @override
  Widget build(BuildContext context) {
    final label = '${shirtNumber == null ? '' : '$shirtNumber. '}$name';
    return Tooltip(
      message: label,
      child: PitchPlayerCard(
        name: label,
        position: position,
        avatar: avatar,
        onTap: onTap,
        avatarKey: ValueKey('pitch-avatar-$id'),
        nameKey: ValueKey('pitch-name-$id'),
        marker: Container(
          key: ValueKey('pitch-rating-$id'),
          width: 28,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: rating == null
                ? AppColors.of(context).raised
                : performanceRatingColor(rating),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            rating?.toStringAsFixed(1) ?? '—',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              color: rating == null
                  ? AppColors.of(context).text
                  : AppColors.onColor(performanceRatingColor(rating)),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        overlays: [
          if (captain)
            const Positioned(
              left: -3,
              bottom: -3,
              child: CaptainBadge(size: 16),
            ),
          if (red || yellow || substitutionIn || substitutionOut)
            Positioned(
              left: -10,
              top: -4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (red || yellow)
                    _PitchEventBadge(
                      id: '$id-card',
                      label: red ? 'Cartão vermelho' : 'Cartão amarelo',
                      icon: Icon(
                        Icons.style_rounded,
                        size: 12,
                        color: red ? AppColors.injury : AppColors.pitchCard,
                      ),
                    ),
                  for (final incoming in [true, false])
                    if (incoming ? substitutionIn : substitutionOut)
                      _substitutionBadge(incoming),
                ],
              ),
            ),
          if (performance?.goalDetails.isNotEmpty == true ||
              performance?.assistDetails.isNotEmpty == true)
            Positioned(
              right: -10,
              top: -4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (performance!.goalDetails.isNotEmpty)
                    _PitchEventBadge(
                      id: '$id-goals',
                      label: 'Gols: ${_eventTimes(performance!.goalDetails)}',
                      count: performance!.goalDetails.length,
                      icon: const Icon(
                        Icons.sports_soccer,
                        size: 13,
                        color: Colors.black87,
                      ),
                    ),
                  if (performance!.assistDetails.isNotEmpty)
                    _PitchEventBadge(
                      id: '$id-assists',
                      label:
                          'Assistências: ${_eventTimes(performance!.assistDetails)}',
                      count: performance!.assistDetails.length,
                      icon: SvgPicture.asset(
                        'assets/images/assistBoot.svg',
                        width: 12,
                        height: 12,
                        colorFilter: const ColorFilter.mode(
                          Colors.black87,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _substitutionBadge(bool incoming) {
    final events =
        performance?.substitutionDetails
            .where((s) => (s.type == SubstitutionType.inGame) == incoming)
            .toList() ??
        <PerformanceSubstitutionDetails>[];
    final time = events.isEmpty || events.every((s) => s.minute == null)
        ? null
        : _eventTimes(events);
    return _PitchEventBadge(
      id: '$id-sub-${incoming ? 'in' : 'out'}',
      label:
          '${incoming ? 'Entrou' : 'Saiu'}${time == null ? '' : ' aos $time'}',
      footer: time,
      icon: LineupSubstitutionIcon(incoming: incoming, size: 12),
    );
  }
}

String _eventTimes(List<PerformanceTimeDetails> events) => events
    .map(
      (s) => s.minute == null
          ? 'sem minuto'
          : '${s is PerformanceSubstitutionDetails && s.inferred ? '~' : ''}${formatEventMinute(s.minute, s.addedMinute)}',
    )
    .join(', ');

class _PitchEventBadge extends StatelessWidget {
  const _PitchEventBadge({
    required this.id,
    required this.label,
    required this.icon,
    this.count = 1,
    this.footer,
  });
  final String id, label;
  final Widget icon;
  final int count;
  final String? footer;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      label: label,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: ValueKey('pitch-event-$id'),
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: Color(0xfff5f5f5),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: count > 1
                  ? Stack(
                      clipBehavior: Clip.none,
                      children: [
                        icon,
                        Positioned(
                          right: -5,
                          bottom: -4,
                          child: Container(
                            width: 10,
                            height: 10,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: Color(0xfff5f5f5),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$count',
                              textScaler: TextScaler.noScaling,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : icon,
            ),
            if (footer != null)
              Container(
                constraints: const BoxConstraints(maxWidth: 30),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.of(context).panel,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  footer!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    color: AppColors.of(context).text,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class FixturePitchEvents extends StatelessWidget {
  const FixturePitchEvents({super.key, this.performance});
  final ManagerFixturePlayerPerformance? performance;
  @override
  Widget build(BuildContext context) {
    final p = performance;
    if (p == null) return const SizedBox.shrink();
    final events = <(Widget, List<PerformanceTimeDetails>)>[
      (const Icon(Icons.sports_soccer, size: 11), p.goalDetails),
      (
        SvgPicture.asset(
          'assets/images/assistBoot.svg',
          width: 11,
          height: 11,
          colorFilter: ColorFilter.mode(
            AppColors.of(context).text,
            BlendMode.srcIn,
          ),
        ),
        p.assistDetails,
      ),
      for (final s in p.substitutionDetails)
        (
          LineupSubstitutionIcon(
            incoming: s.type == SubstitutionType.inGame,
            size: 11,
          ),
          [s],
        ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final visible = events.where((e) => e.$2.isNotEmpty).toList();
        final maxWidth = box.maxWidth.isFinite ? box.maxWidth : 100.0;
        final itemWidth = visible.length > 2 && maxWidth < 110
            ? (maxWidth - 4) / 2
            : maxWidth;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 3,
          children: [
            for (final (icon, details) in visible)
              if (details.isNotEmpty)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: itemWidth.clamp(1, double.infinity),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        icon,
                        const SizedBox(width: 2),
                        Text(
                          details.length > 1
                              ? '${details.length}'
                              : (details.single.minute == null
                                    ? ''
                                    : '${details.single is PerformanceSubstitutionDetails && (details.single as PerformanceSubstitutionDetails).inferred ? '~' : ''}${formatEventMinute(details.single.minute, details.single.addedMinute)}'),
                          style: const TextStyle(fontSize: 9, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}
