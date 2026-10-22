import 'package:flutter/material.dart';

import '../models/ManagerFixturePlayerPerformance.dart';
import '../utils/Components/CareerUiStyle.dart';
import '../utils/Components/CompactDashboardWidgets.dart';
import '../utils/FixtureTimeline.dart';
import '../utils/eventTimeUtils.dart';

class FixtureTimelineView extends StatefulWidget {
  const FixtureTimelineView({
    super.key,
    required this.fixture,
    required this.performances,
    required this.names,
    required this.header,
  });
  final Map<String, Object?> fixture;
  final List<ManagerFixturePlayerPerformance> performances;
  final Map<String, String> names;
  final Widget header;
  @override
  State<FixtureTimelineView> createState() => _FixtureTimelineViewState();
}

class _FixtureTimelineViewState extends State<FixtureTimelineView>
    with AutomaticKeepAliveClientMixin {
  bool _newest = true;
  @override
  bool get wantKeepAlive => true;
  String label(FixtureTimelineEvent e) => switch (e.kind) {
    FixtureEventKind.goal => e.penalty ? 'Gol de pênalti' : 'Gol',
    FixtureEventKind.ownGoal => 'Gol contra',
    FixtureEventKind.yellowCard => 'Cartão amarelo',
    FixtureEventKind.redCard => 'Cartão vermelho',
    FixtureEventKind.substitution => 'Substituição',
    FixtureEventKind.injury => 'Lesão',
    FixtureEventKind.missedPenalty => 'Pênalti perdido',
    FixtureEventKind.assist => 'Assistência',
  };
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = CareerUiColors(context),
        events = fixtureTimeline(
          fixture: widget.fixture,
          performances: widget.performances,
          names: widget.names,
        );
    final timed = events.where((e) => e.minute != null).toList(),
        untimed = events.where((e) => e.minute == null).toList();
    final visible = _newest ? timed.reversed.toList() : timed;
    final away = widget.fixture['location'] == 'away';
    final own = (widget.fixture['playerTeamScore'] as num?)?.toInt() ?? 0,
        other = (widget.fixture['oppositeTeamScore'] as num?)?.toInt() ?? 0;
    Widget marker(String text, IconData icon) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: colors.muted),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: colors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    return ListView(
      primary: false,
      key: const PageStorageKey('fixture-timeline'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        widget.header,
        const SizedBox(height: 12),
        if (events.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: colors.surface(radius: 20),
            child: Column(
              children: [
                Icon(Icons.timeline_rounded, color: colors.muted, size: 36),
                const SizedBox(height: 12),
                Text(
                  'Nenhum evento registrado',
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Adicione os lances nas atuações dos jogadores ou nos gols do adversário.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
              ],
            ),
          )
        else
          DashboardSection(
            title: 'Linha do tempo',
            action: DashboardLink(
              _newest ? 'Mais recentes' : 'Ordem do jogo',
              key: const ValueKey('timeline-order'),
              icon: Icons.swap_vert_rounded,
              onTap: () => setState(() => _newest = !_newest),
            ),
            child: Column(
              children: [
                if (_newest)
                  marker(
                    'Fim de jogo · ${away ? other : own}–${away ? own : other}',
                    Icons.sports_score_rounded,
                  )
                else
                  marker('Início da partida', Icons.sports_soccer_rounded),
                for (final e in visible) _event(context, e, away),
                if (_newest)
                  marker('Início da partida', Icons.sports_soccer_rounded)
                else
                  marker(
                    'Fim de jogo · ${away ? other : own}–${away ? own : other}',
                    Icons.sports_score_rounded,
                  ),
              ],
            ),
          ),
        if (untimed.isNotEmpty)
          DashboardSection(
            title: 'Sem minuto informado',
            child: Column(
              children: [for (final e in untimed) _event(context, e, away)],
            ),
          ),
      ],
    );
  }

  Widget _event(BuildContext context, FixtureTimelineEvent e, bool away) {
    final colors = CareerUiColors(context);
    final home = e.ownTeam ? !away : away;
    final accent = switch (e.kind) {
      FixtureEventKind.yellowCard => colors.amber,
      FixtureEventKind.redCard ||
      FixtureEventKind.ownGoal ||
      FixtureEventKind.missedPenalty => colors.red,
      FixtureEventKind.substitution => colors.green,
      _ => colors.accent,
    };
    final icon = switch (e.kind) {
      FixtureEventKind.goal ||
      FixtureEventKind.ownGoal => Icons.sports_soccer_rounded,
      FixtureEventKind.yellowCard ||
      FixtureEventKind.redCard => Icons.style_rounded,
      FixtureEventKind.substitution => Icons.sync_alt_rounded,
      FixtureEventKind.injury => Icons.medical_services_outlined,
      FixtureEventKind.missedPenalty => Icons.cancel_outlined,
      FixtureEventKind.assist => Icons.assistant_direction_rounded,
    };
    final textAlign = home ? TextAlign.start : TextAlign.end;
    final content = Column(
      crossAxisAlignment: home
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label(e),
                style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (e.homeScore != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${e.homeScore}–${e.awayScore}',
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          e.player,
          textAlign: textAlign,
          style: TextStyle(
            color: colors.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (e.detail?.isNotEmpty == true)
          Text(
            e.kind == FixtureEventKind.substitution
                ? 'Sai: ${e.detail}'
                : e.kind == FixtureEventKind.goal
                ? 'Assistência: ${e.detail}'
                : 'Para ${e.detail}',
            textAlign: textAlign,
            style: TextStyle(color: colors.muted, fontSize: 11),
          ),
        if (e.kind == FixtureEventKind.substitution && e.detail == null)
          Text(
            e.incoming == null
                ? 'Troca registrada'
                : e.incoming == false
                ? 'Saiu de campo'
                : 'Entrou em campo',
            style: TextStyle(color: colors.muted, fontSize: 11),
          ),
      ],
    );
    final minute = Text(
      e.minute == null
          ? '—'
          : '${e.inferred ? '~' : ''}${formatEventMinute(e.minute, e.addedMinute)}',
      style: TextStyle(
        color: colors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    );
    final badge = Container(
      width: 31,
      height: 31,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: accent),
    );
    return Semantics(
      label:
          '${e.minute == null ? 'Sem minuto' : formatEventMinute(e.minute, e.addedMinute)}, ${label(e)}, ${e.player}',
      child: Container(
        key: ValueKey('timeline-event-${e.id}'),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colors.line.withValues(alpha: .4)),
          ),
        ),
        child: Row(
          children: home
              ? [
                  SizedBox(width: 44, child: minute),
                  badge,
                  const SizedBox(width: 10),
                  Expanded(child: content),
                ]
              : [
                  Expanded(child: content),
                  const SizedBox(width: 10),
                  badge,
                  SizedBox(
                    width: 44,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: minute,
                    ),
                  ),
                ],
        ),
      ),
    );
  }
}
