import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ManagerCareer/Fixtures/Performances/TeamPlayersPerformanceGrid.dart'
    show LineupSubstitutionIcon;
import '../ManagerCareer/TeamPage/ViewPlayer/PlayerProfileVisuals.dart';
import '../models/FixtureCaptaincy.dart';
import '../models/ManagerFixturePlayerPerformance.dart';
import '../models/MatchPerformanceStats.dart';
import '../utils/AppColors.dart';
import '../utils/eventTimeUtils.dart';
import '../utils/managerPlayerMinutesUtils.dart';

class FixturePlayerPerformancePage extends StatelessWidget {
  const FixturePlayerPerformancePage({
    super.key,
    required this.name,
    required this.team,
    required this.match,
    required this.avatar,
    this.performance,
    this.position = '',
    this.date,
    this.extraTime = false,
    this.captain = false,
    this.playerOfMatch = false,
    this.onViewPlayer,
  });

  final String name, team, match, position;
  final DateTime? date;
  final ManagerFixturePlayerPerformance? performance;
  final Widget Function(double radius) avatar;
  final bool extraTime, captain, playerOfMatch;
  final VoidCallback? onViewPlayer;

  static String _number(num value, {int decimals = 0}) =>
      NumberFormat.decimalPatternDigits(
        locale: 'pt_BR',
        decimalDigits: decimals,
      ).format(value);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context), p = performance;
    final raw = p?.apiStats ?? const <String, Object?>{};
    num? value(String key) {
      final n = raw[key];
      return n is num && n.isFinite && n >= 0 ? n : null;
    }

    final goals =
        p?.goalsCount ??
        (p?.goalDetails.isNotEmpty == true ? p!.goalDetails.length : null);
    final assists =
        p?.assistsCount ??
        (p?.assistDetails.isNotEmpty == true ? p!.assistDetails.length : null);
    final metrics = <(String, num?, IconData)>[
      ('Gols', goals, Icons.sports_soccer_rounded),
      ('Assistências', assists, Icons.assistant_outlined),
      (
        'Finalizações',
        p?.shotsCount ?? value('shots'),
        Icons.my_location_rounded,
      ),
      ('Passes', p?.passes ?? value('passes'), Icons.alt_route_rounded),
      (
        'Passes decisivos',
        p?.keyPasses ?? value('keyPasses'),
        Icons.key_rounded,
      ),
      ('Desarmes', p?.tackles ?? value('tackles'), Icons.shield_outlined),
      (
        'Dribles',
        p?.dribbles ?? value('dribbles'),
        Icons.directions_run_rounded,
      ),
      ('Defesas', p?.saves ?? value('saves'), Icons.pan_tool_outlined),
    ].where((m) => m.$2 != null).toList();
    final charts = <Widget>[];
    void accuracy(
      String label,
      String numerator,
      String denominator,
      int? legacyPercentage,
      String legend,
    ) {
      final n = value(numerator), d = value(denominator);
      final attempts =
          d ??
          switch (denominator) {
            'passes' => p?.passes,
            'shots' => p?.shotsCount,
            'dribbles' => p?.dribbles,
            _ => null,
          };
      if (attempts == 0 || (n != null && d != null && n > d)) return;
      final validRatio = n != null && d != null && d > 0 && n <= d;
      final percentage = validRatio ? n * 100 / d : legacyPercentage;
      if (percentage == null || percentage < 0 || percentage > 100) return;
      charts.add(
        _AccuracyChart(
          label: label,
          fraction: percentage / 100,
          caption: validRatio
              ? '${_number(n)} de ${_number(d)} $legend'
              : legend,
        ),
      );
    }

    accuracy(
      'Precisão de passes',
      'passesCompleted',
      'passes',
      p?.passAccuracy,
      'passes certos',
    );
    accuracy(
      'Finalizações no alvo',
      'shotsOnTarget',
      'shots',
      p?.shotAccuracy,
      'finalizações no alvo',
    );
    accuracy(
      'Dribles certos',
      'dribblesCompleted',
      'dribbles',
      p?.dribblesAccuracy,
      'dribles certos',
    );
    accuracy(
      'Duelos aéreos',
      'aerialDuelsWon',
      'aerialDuelsAttempted',
      null,
      'duelos ganhos',
    );
    accuracy(
      'Duelos defensivos',
      'defenseDuelsWon',
      'defenseDuelsAttempted',
      null,
      'duelos ganhos',
    );
    final events =
        <({PerformanceTimeDetails time, String title, Widget icon})>[];
    void addEvents(
      Iterable<PerformanceTimeDetails> times,
      String title,
      IconData icon,
      Color color,
    ) {
      events.addAll(
        times.map(
          (t) =>
              (time: t, title: title, icon: Icon(icon, size: 20, color: color)),
        ),
      );
    }

    if (p != null) {
      for (final goal in p.goalDetails) {
        addEvents(
          [goal],
          goal.isPenalty ? 'Gol de pênalti' : 'Gol',
          Icons.sports_soccer_rounded,
          c.accent,
        );
      }
      addEvents(
        p.assistDetails,
        'Assistência',
        Icons.assistant_outlined,
        c.accent,
      );
      addEvents(
        p.yellowCardDetails,
        'Cartão amarelo',
        Icons.style_rounded,
        c.warning,
      );
      addEvents(
        p.redCardDetails,
        'Cartão vermelho',
        Icons.style_rounded,
        c.danger,
      );
      addEvents(
        p.ownGoalDetails,
        'Gol contra',
        Icons.sports_soccer_rounded,
        c.danger,
      );
      addEvents(
        p.missedPenaltyDetails,
        'Pênalti perdido',
        Icons.close_rounded,
        c.danger,
      );
      addEvents(
        p.injuryDetails,
        'Lesão',
        Icons.medical_services_outlined,
        c.warning,
      );
      for (final sub in p.substitutionDetails) {
        final incoming = sub.type == SubstitutionType.inGame;
        final other = sub.anotherPlayerName;
        events.add((
          time: sub,
          title:
              '${incoming ? 'Entrou' : 'Saiu'}${other == null || other.isEmpty ? '' : ' · $other'}',
          icon: LineupSubstitutionIcon(incoming: incoming),
        ));
      }
    }
    events.sort(
      (a, b) => (FixtureCaptaincy.eventOrder(a.time) ?? 999999).compareTo(
        FixtureCaptaincy.eventOrder(b.time) ?? 999999,
      ),
    );
    final locations =
        p?.goalDetails
            .where((g) => g.fieldLocation != null)
            .map((g) => g.fieldLocation!)
            .toList() ??
        <GoalShotLocation>[];
    final goalLocations =
        p?.goalDetails
            .where((g) => g.goalLocation != null)
            .map((g) => g.goalLocation!)
            .toList() ??
        <GoalShotLocation>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Atuação na partida')),
      body: ListView(
        key: const ValueKey('match-player-report'),
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          ProfilePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match,
                  style: TextStyle(color: c.muted, fontSize: 13, height: 1.6),
                ),
                if (date != null)
                  Text(
                    DateFormat('dd/MM/yyyy · HH:mm').format(date!),
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                const SizedBox(height: 22),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    avatar(33),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '$team${position.isEmpty ? '' : ' · $position'}',
                            style: TextStyle(color: c.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (p?.avgRating != null) ...[
                      const SizedBox(width: 10),
                      ProfileRating(p!.avgRating),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (p != null &&
                        (p.recordedStarted != false ||
                            p.recordedMinutes != null ||
                            p.substitutionDetails.any(
                              (s) =>
                                  s.type == SubstitutionType.inGame &&
                                  s.minute != null,
                            )))
                      _Tag(
                        '${getManagerPlayerPlayedMinutes(p, getManagerFixtureDurationMinutes(extraTime: extraTime, performance: p))} min em campo',
                      ),
                    if (p?.recordedStarted != null)
                      _Tag(p!.recordedStarted! ? 'Titular' : 'Reserva'),
                    if (captain) const _Tag('Capitão'),
                    if (playerOfMatch) const _Tag('Melhor em campo'),
                  ],
                ),
                if (onViewPlayer != null) ...[
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    key: const ValueKey('match-player-profile'),
                    onPressed: onViewPlayer,
                    icon: const Icon(Icons.person_outline_rounded),
                    label: const Text('Informações do jogador'),
                  ),
                ],
              ],
            ),
          ),
          if (metrics.isNotEmpty)
            ProfilePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Heading('Resumo do jogo'),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, box) => Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final (label, number, icon) in metrics)
                          SizedBox(
                            width: (box.maxWidth - 12) / 2,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: c.raised,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(icon, color: c.accent, size: 19),
                                  const SizedBox(height: 10),
                                  Text(
                                    _number(number!),
                                    key: ValueKey('match-metric-$label'),
                                    style: const TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      color: c.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (charts.isNotEmpty)
            ProfilePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Heading('Aproveitamento'),
                  const SizedBox(height: 8),
                  Text(
                    'Acertos em relação às tentativas nesta partida.',
                    style: TextStyle(color: c.muted, fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, box) => Wrap(
                      spacing: 16,
                      runSpacing: 24,
                      children: [
                        for (final chart in charts)
                          SizedBox(
                            width:
                                box.maxWidth < 260 ||
                                    MediaQuery.textScalerOf(context).scale(1) >
                                        1.4
                                ? box.maxWidth
                                : (box.maxWidth - 16) / 2,
                            child: chart,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (events.isNotEmpty)
            ProfilePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Heading('Momentos na partida'),
                  const SizedBox(height: 16),
                  for (final event in events)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 52,
                            child: Text(
                              '${event.time is PerformanceSubstitutionDetails && (event.time as PerformanceSubstitutionDetails).inferred ? '~' : ''}${event.time.minute == null ? '—' : formatEventMinute(event.time.minute, event.time.addedMinute)}',
                              style: TextStyle(
                                color: c.accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          SizedBox(width: 28, child: event.icon),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              event.title,
                              style: const TextStyle(fontSize: 13, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (p!.substitutionDetails.any((s) => s.inferred))
                    Text(
                      '~ Minuto estimado a partir dos minutos jogados.',
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                ],
              ),
            ),
          if (locations.isNotEmpty || goalLocations.isNotEmpty)
            ProfilePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Heading('Mapa dos gols'),
                  const SizedBox(height: 8),
                  Text(
                    'Somente gols com localização registrada nesta partida.',
                    style: TextStyle(color: c.muted, fontSize: 12, height: 1.5),
                  ),
                  if (locations.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    PitchMap(locations: locations),
                  ],
                  if (goalLocations.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    GoalMouth(locations: goalLocations),
                  ],
                ],
              ),
            ),
          for (final group in performanceStats.map((s) => s.group).toSet())
            if (performanceStats.any(
              (s) => s.group == group && s.total([raw]) != null,
            ))
              ProfilePanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Heading(group),
                    const SizedBox(height: 12),
                    for (final stat in performanceStats.where(
                      (s) => s.group == group,
                    ))
                      if (stat.total([raw]) case final n?)
                        ProfileLine(
                          stat.label,
                          '${_number(n, decimals: stat.decimals)}${stat.percentage ? '%' : ''}',
                        ),
                  ],
                ),
              ),
          if (p != null)
            ProfilePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Heading('Outros registros'),
                  const SizedBox(height: 12),
                  if (p.yellowCards != null)
                    ProfileLine('Cartões amarelos', '${p.yellowCards}'),
                  if (p.redCards != null)
                    ProfileLine('Cartões vermelhos', '${p.redCards}'),
                  if (p.penaltySaves != null)
                    ProfileLine('Pênaltis defendidos', '${p.penaltySaves}'),
                  if (p.tacklesAccuracy != null)
                    ProfileLine(
                      'Precisão nos desarmes',
                      '${p.tacklesAccuracy}%',
                    ),
                  Text(
                    'Dados exclusivos desta partida. Campos não registrados ficam ocultos.',
                    style: TextStyle(color: c.muted, fontSize: 12, height: 1.6),
                  ),
                ],
              ),
            ),
          if (p == null ||
              metrics.isEmpty &&
                  charts.isEmpty &&
                  events.isEmpty &&
                  raw.isEmpty)
            const ProfilePanel(
              child: Column(
                children: [
                  Icon(Icons.query_stats_rounded, size: 36),
                  SizedBox(height: 12),
                  Text(
                    'Sem estatísticas registradas para este jogador nesta partida.',
                    textAlign: TextAlign.center,
                    style: TextStyle(height: 1.6),
                  ),
                ],
              ),
            ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom + 20),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: c.accent,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AccuracyChart extends StatelessWidget {
  const _AccuracyChart({
    required this.label,
    required this.caption,
    required this.fraction,
  });
  final String label, caption;
  final double fraction;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      label: '$label: ${(fraction * 100).round()}%. $caption',
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (context, progress, _) => SizedBox(
              width: 104,
              height: 104,
              child: CustomPaint(
                painter: _RingPainter(progress, c.accent, c.line),
                child: Center(
                  child: Text(
                    '${(fraction * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.fraction, this.color, this.track);
  final double fraction;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(6);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      paint..color = track.withValues(alpha: .5),
    );
    if (fraction > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * fraction,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}
