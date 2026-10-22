import '../utils/AppColors.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../ManagerCareer/TeamPage/ViewPlayer/PlayerProfileVisuals.dart'
    show TournamentBadge;
import '../utils/Components/TeamLogo.dart';
import '../utils/GameCatalog.dart';

List<List<T>> groupByConsecutiveTournament<T>(
  List<T> items,
  String Function(T item) tournamentId,
) {
  final groups = <List<T>>[];
  for (final item in items) {
    if (groups.isNotEmpty &&
        tournamentId(groups.last.first) == tournamentId(item)) {
      groups.last.add(item);
    } else {
      groups.add([item]);
    }
  }
  return groups;
}

enum FixtureResult { win, draw, lose }

int? _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

FixtureResult fixtureResult(Map<String, Object?> fixture) {
  var own = _int(fixture['playerTeamScore']) ?? 0;
  var opponent = _int(fixture['oppositeTeamScore']) ?? 0;
  if (own == opponent) {
    own = _int(fixture['playerTeamPenaltiesScore']) ?? 0;
    opponent = _int(fixture['oppositeTeamPenaltiesScore']) ?? 0;
  }
  return own > opponent
      ? FixtureResult.win
      : own < opponent
      ? FixtureResult.lose
      : FixtureResult.draw;
}

class FixtureTournamentCard extends StatelessWidget {
  const FixtureTournamentCard({
    super.key,
    required this.fifaVersion,
    required this.tournamentId,
    required this.tournamentName,
    required this.children,
    this.logoAsset,
    this.boxedLogo = false,
  });
  final String fifaVersion, tournamentId, tournamentName;
  final List<Widget> children;
  final String? logoAsset;

  final bool boxedLogo;

  @override
  Widget build(BuildContext context) {
    final size = 20.0;
    Widget logo = logoAsset == null
        ? TournamentBadge(
            version: fifaVersion,
            tournamentId: tournamentId,
            size: size,
          )
        : Image.asset(
            logoAsset!,
            width: size,
            height: size,
            errorBuilder: (_, _, _) => TournamentBadge(
              version: fifaVersion,
              tournamentId: tournamentId,
              size: size,
            ),
          );
    if (boxedLogo) {
      logo = Container(
        width: 27,
        height: 27,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.of(context).text,
          borderRadius: BorderRadius.circular(4),
        ),
        child: logo,
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 5),
      padding: const EdgeInsets.fromLTRB(20, 5, 10, 4),
      decoration: BoxDecoration(
        color: AppColors.of(context).panel,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(top: boxedLogo ? 0 : 6, bottom: 2),
            child: Row(
              children: [
                logo,
                SizedBox(width: boxedLogo ? 6 : 11),
                Expanded(
                  child: Text(
                    tournamentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class FixtureResultTile extends StatelessWidget {
  const FixtureResultTile({
    super.key,
    required this.fifaVersion,
    required this.fixture,
    required this.trailing,
    this.ownIcons = const [],
    this.ownNameIcons = const [],
    this.onTap,
  });
  final String fifaVersion;
  final Map<String, Object?> fixture;
  final Widget trailing;
  final List<Widget> ownIcons, ownNameIcons;
  final VoidCallback? onTap;

  Widget _team(
    BuildContext context, {
    required String teamId,
    required String? leagueId,
    required Object? score,
    required Object? penalties,
    required bool winner,
    required bool own,
  }) {
    final color = winner
        ? AppColors.of(context).text
        : AppColors.of(context).muted;
    final style = TextStyle(fontSize: 13, color: color);
    return SizedBox(
      height: 23,
      child: Row(
        children: [
          TeamLogo.lookup(
            fifaVersion: fifaVersion,
            teamId: teamId,
            leagueId: leagueId,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    GameCatalog.current?.teamLabel(
                          fifaVersion,
                          teamId,
                          leagueId: leagueId,
                        ) ??
                        teamId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
                if (own) ...ownNameIcons,
              ],
            ),
          ),
          if (own) ...ownIcons,
          const SizedBox(width: 4),
          Text(
            penalties == null
                ? '${score ?? '–'}'
                : '${score ?? '–'} ($penalties)',
            style: style,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(fixture['date']?.toString() ?? '');
    final stage = fixture['stage']?.toString() ?? '';
    final result = fixtureResult(fixture);
    final hasPenalties =
        fixture['playerTeamPenaltiesScore'] != null &&
        fixture['oppositeTeamPenaltiesScore'] != null;
    final own = _team(
      context,
      teamId: fixture['playerTeamId']?.toString() ?? '',
      leagueId: fixture['playerTeamLeagueId']?.toString(),
      score: fixture['playerTeamScore'],
      penalties: hasPenalties ? fixture['playerTeamPenaltiesScore'] : null,
      winner: result == FixtureResult.win,
      own: true,
    );
    final opponent = _team(
      context,
      teamId: fixture['oppositeTeamId']?.toString() ?? '',
      leagueId: fixture['oppositeTeamLeagueId']?.toString(),
      score: fixture['oppositeTeamScore'],
      penalties: hasPenalties ? fixture['oppositeTeamPenaltiesScore'] : null,
      winner: result == FixtureResult.lose,
      own: false,
    );
    final away = fixture['location'] == 'away';
    final muted = TextStyle(color: AppColors.of(context).muted, fontSize: 11);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Column(
                children: [
                  Text(
                    date == null ? '–' : DateFormat('dd/MM/yyyy').format(date),
                    style: muted,
                  ),
                  if (stage.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      stage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(children: away ? [opponent, own] : [own, opponent]),
            ),
            const SizedBox(width: 18),
            trailing,
          ],
        ),
      ),
    );
  }
}

class FixtureResultBadge extends StatelessWidget {
  const FixtureResultBadge(this.result, {super.key});
  final FixtureResult result;
  @override
  Widget build(BuildContext context) => Container(
    width: 25,
    height: 25,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: switch (result) {
        FixtureResult.win => AppColors.ratingGood,
        FixtureResult.draw => AppColors.neutralResult,
        FixtureResult.lose => AppColors.lowRating,
      },
    ),
    child: Text(
      switch (result) {
        FixtureResult.win => 'fixtures.winShort',
        FixtureResult.draw => 'fixtures.drawShort',
        FixtureResult.lose => 'fixtures.loseShort',
      }.tr(),
      style: TextStyle(
        color: AppColors.onColor(switch (result) {
          FixtureResult.win => AppColors.ratingGood,
          FixtureResult.draw => AppColors.neutralResult,
          FixtureResult.lose => AppColors.lowRating,
        }),
        fontSize: 12.5,
      ),
    ),
  );
}

class FixtureCardIcon extends StatelessWidget {
  const FixtureCardIcon({super.key, this.red = false});
  final bool red;
  @override
  Widget build(BuildContext context) => Container(
    width: red ? 6 : 10,
    height: red ? 9 : 14,
    margin: const EdgeInsets.symmetric(horizontal: 2),
    decoration: BoxDecoration(
      color: red ? AppColors.redCard : AppColors.yellowCard,
      borderRadius: BorderRadius.circular(red ? 1 : 2),
    ),
  );
}
