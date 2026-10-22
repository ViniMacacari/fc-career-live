import '../../utils/AppColors.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../Common/FixtureResultTile.dart';
import '../../utils/Components/TeamLogo.dart';
import '../TeamPage/ViewPlayer/PlayerProfileVisuals.dart' show ProfilePortrait;
import 'PlayerFarewellData.dart';
import 'TransferStyle.dart';

Future<void> showPlayerFarewell(
  BuildContext context,
  PlayerFarewellData data,
) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Fechar despedida',
  barrierColor: AppColors.of(context).text.withValues(alpha: .78),
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 320),
  transitionBuilder: (context, animation, secondaryAnimation, child) =>
      FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .94, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
  pageBuilder: (_, _, _) => PlayerFarewellDialog(data: data),
);

class PlayerFarewellDialog extends StatefulWidget {
  const PlayerFarewellDialog({super.key, required this.data});
  final PlayerFarewellData data;
  @override
  State<PlayerFarewellDialog> createState() => _PlayerFarewellDialogState();
}

class _PlayerFarewellDialogState extends State<PlayerFarewellDialog>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  bool _started = false;
  PlayerFarewellData get data => widget.data;
  String _date(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (MediaQuery.disableAnimationsOf(context)) {
        _animation.value = 1;
      } else {
        _animation.forward();
      }
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  Widget _reveal(double start, Widget child) {
    final progress = Curves.easeOutCubic.transform(
      ((_animation.value - start) / (1 - start)).clamp(0, 1),
    );
    return Opacity(
      opacity: progress,
      child: Transform.translate(
        offset: Offset(0, 18 * (1 - progress)),
        child: child,
      ),
    );
  }

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.of(context).panel,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: AppColors.of(context).muted.withValues(alpha: .16),
      ),
    ),
    child: child,
  );

  Widget _portrait() {
    final progress = Curves.easeOutCubic.transform(
      (_animation.value / .65).clamp(0, 1),
    );
    return SizedBox(
      height: 164,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.scale(
            scale: .78 + .22 * progress,
            child: Container(
              width: 156,
              height: 156,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.of(context).warning.withValues(alpha: .18),
                    AppColors.of(context).accent.withValues(alpha: .08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          for (var i = 0; i < 7; i++)
            Transform.translate(
              offset: Offset(
                math.cos(i * math.pi * 2 / 7) * (56 + progress * 28),
                math.sin(i * math.pi * 2 / 7) * (56 + progress * 24),
              ),
              child: Opacity(
                opacity: math.sin(progress * math.pi) * .65,
                child: Icon(
                  Icons.auto_awesome,
                  size: i.isEven ? 10 : 6,
                  color: AppColors.of(context).warning,
                ),
              ),
            ),
          _reveal(
            0,
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: AppColors.of(context).warning.withValues(alpha: .65),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.of(context).warning.withValues(alpha: .08),
                    blurRadius: 26,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(27),
                child: ProfilePortrait(
                  version: data.person.fifaVersion,
                  realPlayerId: data.realPlayerId,
                  customAvatarFilePath: data.photo,
                  width: 106,
                  height: 128,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _club(String label, String? id, String? league) => Expanded(
    child: Column(
      children: [
        TeamLogo.lookup(
          fifaVersion: data.person.fifaVersion,
          teamId: id ?? '',
          leagueId: league,
          size: 30,
        ),
        const SizedBox(height: 8),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _stat(
    String label,
    num? value,
    IconData icon, {
    bool decimal = false,
  }) {
    final progress = Curves.easeOutCubic.transform(
      ((_animation.value - .18) / .65).clamp(0, 1),
    );
    final animated = value == null
        ? '—'
        : decimal
        ? (value * progress).toStringAsFixed(1).replaceAll('.', ',')
        : '${(value * progress).round()}';
    return Expanded(
      child: _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.of(context).accent, size: 19),
            const SizedBox(height: 10),
            Text(
              animated,
              style: const TextStyle(
                fontSize: 29,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: AppColors.of(context).muted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(Widget first, Widget second) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [first, const SizedBox(width: 12), second],
    ),
  );

  Widget _moment(String title, String detail, IconData icon) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppColors.of(context).warning.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.of(context).warning, size: 18),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                detail,
                style: TextStyle(
                  color: AppColors.of(context).muted,
                  fontSize: 12,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _memories() {
    final first = data.matches.first;
    final highlight = data.highlight;
    final best = data.bestSeason;
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Momentos que ficam',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          _moment(
            'Primeira atuação registrada',
            '${_date(first.date!)} · Contra ${data.opponent(first)}',
            Icons.flag_outlined,
          ),
          if (highlight != null)
            _moment(
              'Atuação em destaque',
              '${_date(highlight.date!)} · Contra ${data.opponent(highlight)}'
                  '${highlight.performance.avgRating == null ? '' : ' · Nota ${highlight.performance.avgRating!.toStringAsFixed(1).replaceAll('.', ',')}'}'
                  '\n${highlight.goals} gols · ${highlight.assists} assistências',
              Icons.auto_awesome_outlined,
            ),
          if (best != null)
            _moment(
              'Temporada de destaque · ${data.seasonLabel(best.id)}',
              '${best.totals.matches} jogos · ${data.goalkeeper && data.hasSaves ? '${best.totals.saves} defesas' : '${best.totals.goals} gols · ${best.totals.assists} assistências'}',
              Icons.workspace_premium_outlined,
            ),
        ],
      ),
    );
  }

  Widget _results() {
    final results = data.results;
    final known = results.values.fold(0, (a, b) => a + b);
    if (known == 0) return const SizedBox.shrink();
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Retrospecto com ele em campo',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final (result, label, color) in [
                (FixtureResult.win, 'Vitórias', AppColors.of(context).success),
                (FixtureResult.draw, 'Empates', AppColors.of(context).warning),
                (FixtureResult.lose, 'Derrotas', AppColors.of(context).danger),
              ])
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${results[result]}',
                        style: TextStyle(
                          color: color,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        label,
                        style: TextStyle(
                          color: AppColors.of(context).muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => TransferTheme(
    child: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 880),
          child: Dialog(
            key: const ValueKey('player-farewell'),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            backgroundColor: AppColors.of(context).background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: AppColors.of(context).warning,
                        size: 18,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          data.transfer['rosterDepartureRecord'] == true
                              ? 'Saída registrada'
                              : 'Venda confirmada',
                          style: TextStyle(
                            color: AppColors.of(context).warning,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar despedida',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: AnimatedBuilder(
                    animation: _animation,
                    builder: (context, _) => SingleChildScrollView(
                      key: const ValueKey('farewell-scroll'),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _portrait(),
                          _reveal(
                            .05,
                            Column(
                              children: [
                                Text(
                                  'OBRIGADO POR TUDO',
                                  style: TextStyle(
                                    color: AppColors.of(context).warning,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.6,
                                  ),
                                ),
                                const SizedBox(height: 9),
                                Text(
                                  data.name,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 25,
                                    height: 1.25,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Sua história no clube',
                                  style: TextStyle(
                                    color: AppColors.of(context).muted,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 22),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _club(
                                      data.clubName,
                                      data.clubId,
                                      data.clubLeagueId,
                                    ),
                                    if (data.destinationId != null)
                                      Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: Icon(
                                          Icons.east,
                                          color: AppColors.of(context).accent,
                                          size: 20,
                                        ),
                                      ),
                                    if (data.destinationId != null)
                                      _club(
                                        data.destinationName,
                                        data.destinationId,
                                        data.destinationLeagueId,
                                      ),
                                  ],
                                ),
                                if (data.releaseDate != null) ...[
                                  const SizedBox(height: 14),
                                  Text(
                                    'Saída em ${_date(data.releaseDate!)}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.of(context).muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 26),
                          if (data.recordsAvailable)
                            _reveal(
                              .18,
                              Column(
                                children: [
                                  _statRow(
                                    _stat(
                                      'Jogos pelo clube',
                                      data.totals.matches,
                                      Icons.sports_soccer,
                                    ),
                                    _stat(
                                      'Nota média',
                                      data.totals.rating,
                                      Icons.star_outline,
                                      decimal: true,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _statRow(
                                    _stat(
                                      'Gols',
                                      data.totals.goals,
                                      Icons.sports_soccer_outlined,
                                    ),
                                    _stat(
                                      'Assistências',
                                      data.totals.assists,
                                      Icons.assistant_outlined,
                                    ),
                                  ),
                                  if (data.goalkeeper && data.hasSaves) ...[
                                    const SizedBox(height: 12),
                                    _statRow(
                                      _stat(
                                        'Defesas',
                                        data.totals.saves,
                                        Icons.back_hand_outlined,
                                      ),
                                      _stat(
                                        'Pênaltis defendidos',
                                        data.penaltySaves,
                                        Icons.shield_outlined,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 14,
                                    runSpacing: 8,
                                    children: [
                                      Text(
                                        '${data.totals.motm}× melhor em campo',
                                        style: TextStyle(
                                          color: AppColors.of(context).warning,
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (data.hatTricks > 0)
                                        Text(
                                          '${data.hatTricks}× hat-trick',
                                          style: TextStyle(
                                            color: AppColors.of(context).accent,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 22),
                          _reveal(
                            .32,
                            Text(
                              data.retrospective,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.of(context).muted,
                                fontSize: 13,
                                height: 1.65,
                              ),
                            ),
                          ),
                          if (data.matches.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            _reveal(.42, _results()),
                            const SizedBox(height: 16),
                            _reveal(.48, _memories()),
                          ],
                          const SizedBox(height: 22),
                          Text(
                            'Atuações registradas até ${_date(data.agreementDate)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.of(context).muted,
                              fontSize: 10,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('close-player-farewell'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.of(context).accent,
                        foregroundColor: AppColors.of(context).text,
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Continuar'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
