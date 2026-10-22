import '../utils/AppColors.dart';

import 'package:flutter/material.dart';

import '../models/OpponentLineup.dart';
import '../utils/databaseUtils.dart';
import '../models/ManagerFixturePlayerPerformance.dart';
import '../utils/Components/CareerUiStyle.dart';
import '../utils/Components/FixturePitchPlayer.dart';
import '../utils/Components/FootballPitch.dart';
import '../utils/Components/PlayerAvatar.dart';
import '../utils/Components/TeamLogo.dart';
import 'MatchUi.dart';

class FixtureFormationsPage extends StatefulWidget {
  const FixtureFormationsPage({
    super.key,
    required this.own,
    required this.ownName,
    required this.opponentName,
    required this.header,
    required this.fifaVersion,
    this.ownTeam,
    this.opponentTeam,
    this.opponent,
    this.onOpponentPlayerTap,
  });
  final Widget own, header;
  final String ownName, opponentName;
  final String fifaVersion;
  final ({String id, String? leagueId})? ownTeam, opponentTeam;
  final OpponentLineup? opponent;
  final void Function(OpponentLineup, String)? onOpponentPlayerTap;
  @override
  State<FixtureFormationsPage> createState() => _FixtureFormationsPageState();
}

class _FixtureFormationsPageState extends State<FixtureFormationsPage>
    with AutomaticKeepAliveClientMixin {
  bool _other = false;
  @override
  bool get wantKeepAlive => true;

  Widget? _crest(({String id, String? leagueId})? team) => team == null
      ? null
      : TeamLogo.lookup(
          fifaVersion: widget.fifaVersion,
          teamId: team.id,
          leagueId: team.leagueId,
          size: 18,
        );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: MatchSegmented<bool>(
            value: _other,
            onChanged: (other) => setState(() => _other = other),
            items: [
              MatchSegment(
                false,
                widget.ownName,
                key: const ValueKey('formation-team-own'),
                leading: _crest(widget.ownTeam),
              ),
              MatchSegment(
                true,
                widget.opponentName,
                key: const ValueKey('formation-team-opponent'),
                leading: _crest(widget.opponentTeam),
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _other ? 1 : 0,
            children: [
              widget.own,
              _OpponentPitch(
                lineup: widget.opponent,
                header: widget.header,
                fifaVersion: widget.fifaVersion,
                onPlayerTap: widget.onOpponentPlayerTap,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OpponentPitch extends StatelessWidget {
  const _OpponentPitch({
    required this.lineup,
    required this.header,
    required this.fifaVersion,
    this.onPlayerTap,
  });
  final String fifaVersion;
  final OpponentLineup? lineup;
  final Widget header;
  final void Function(OpponentLineup, String)? onPlayerTap;

  Widget _avatar(
    BuildContext context,
    OpponentLineup data,
    String id,
    double radius,
  ) {
    final photo = data.squad.players[id]?['customAvatarFilePath'] as String?;
    return photo == null
        ? _initials(context, data.names[id] ?? '', radius)
        : PlayerAvatar(
            fifaVersion: fifaVersion,
            customAvatarFilePath: photo,
            radius: radius,
          );
  }

  Widget _initials(BuildContext context, String name, double radius) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final initials = words.isEmpty
        ? '?'
        : '${words.first.characters.first}${words.length < 2 ? '' : words.last.characters.first}'
              .toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.of(context).line,
      child: Text(
        initials,
        style: TextStyle(
          color: AppColors.of(context).text,
          fontSize: radius * .65,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = CareerUiColors(context), data = lineup?.resolved();
    final performances = {
      for (final p in data?.performances ?? []) p.playerInstanceId: p,
    };
    return ListView(
      key: const PageStorageKey('fixture-opponent-formation'),
      primary: false,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 36),
      children: [
        header,
        const SizedBox(height: 12),
        if (data == null || !data.hasNames || data.squad.formation.isEmpty)
          Container(
            decoration: colors.surface(radius: 20),
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.groups_outlined, color: colors.muted, size: 36),
                const SizedBox(height: 16),
                const Text(
                  'Escalação ainda não informada',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  'Edite a partida e, em Escalação → Adversário, cadastre os jogadores.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.muted, height: 1.6),
                ),
              ],
            ),
          )
        else ...[
          MatchFormationBar(
            title: 'Formação do adversário',
            formation: data.squad.formation,
            count: '${data.squad.starters.length}/11',
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, box) => SizedBox(
              height: SquadPitchMetrics.forMatch(context),
              child: FootballPitch(
                key: const ValueKey('fixture-opponent-pitch'),
                formation: data.squad.formation,
                slotBuilder: (x, y) {
                  final id = data.squad.starters.entries
                      .where((e) => e.value == (x: x, y: y))
                      .firstOrNull
                      ?.key;
                  final name = data.names[id] ?? '';
                  final p = performances[id];
                  return Center(
                    child: name.isEmpty
                        ? const SizedBox.shrink()
                        : FixturePitchPlayer(
                            id: id!,
                            onTap: onPlayerTap == null
                                ? null
                                : () => onPlayerTap!(data, id),
                            name: name,
                            position: positionShortName(
                              data.squad.players[id]?['positionId'] as String?,
                            ),
                            shirtNumber: data.squad.players[id]?['shirtNumber'],
                            avatar: (radius) =>
                                _avatar(context, data, id, radius),
                            rating: p?.avgRating,
                            performance: p,
                            yellow: p?.yellowCardDetails.isNotEmpty == true,
                            red: p?.redCardDetails.isNotEmpty == true,
                            substitutionIn:
                                p?.substitutionDetails.any(
                                  (s) => s.type == SubstitutionType.inGame,
                                ) ==
                                true,
                            substitutionOut:
                                p?.substitutionDetails.any(
                                  (s) => s.type != SubstitutionType.inGame,
                                ) ==
                                true,
                          ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (data.performances.any(
            (p) => p.substitutionDetails.any((s) => s.inferred),
          ))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: MatchHint(
                '~ Minuto estimado pelos minutos jogados informados pela API.',
              ),
            ),
          MatchBenchPanel(
            count: data.squad.bench.length,
            children: [
              for (final id in data.squad.bench)
                if (data.names[id]!.isNotEmpty)
                  MatchPlayerRow(
                    key: ValueKey('opponent-bench-$id'),
                    avatar: _avatar(context, data, id, 19),
                    name: data.names[id]!,
                    detail: positionShortName(
                      data.squad.players[id]?['positionId'] as String?,
                    ),
                    events: FixturePitchEvents(performance: performances[id]),
                    rating: performances[id]?.avgRating,
                    onTap: onPlayerTap == null
                        ? null
                        : () => onPlayerTap!(data, id),
                  ),
            ],
          ),
        ],
      ],
    );
  }
}
