import 'package:flutter/material.dart';

import '../../utils/AppColors.dart';
import '../../utils/Components/TeamLogo.dart';
import '../../utils/GameCatalog.dart';
import '../TeamPage/ViewPlayer/PlayerProfileVisuals.dart';
import 'OtherPlayersData.dart';

Color overallColor(int? overall) => overall == null
    ? AppColors.ratingUnknown
    : overall >= 85
    ? AppColors.ratingExcellent
    : overall >= 75
    ? AppColors.ratingGood
    : overall >= 65
    ? AppColors.ratingAverage
    : AppColors.ratingBelowAverage;

class OverallPill extends StatelessWidget {
  const OverallPill(this.overall, {super.key, this.size = 34});
  final int? overall;
  final double size;
  @override
  Widget build(BuildContext context) {
    final color = overallColor(overall);
    return Container(
      width: size,
      height: size * .82,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        overall?.toString() ?? '–',
        style: TextStyle(
          color: AppColors.onColor(color),
          fontSize: size * .4,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class ClubLine extends StatelessWidget {
  const ClubLine({
    super.key,
    required this.version,
    required this.club,
    this.size = 16,
    this.style,
    this.unknown = false,
  });
  final String version;
  final CatalogItem? club;
  final double size;
  final TextStyle? style;

  final bool unknown;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text =
        style ??
        TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w600);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (club == null)
          Icon(
            unknown ? Icons.help_outline_rounded : Icons.person_off_outlined,
            size: size,
            color: c.muted,
          )
        else
          ClubLogo(version: version, club: club!, size: size),
        SizedBox(width: size * .4),
        Flexible(
          child: Text(
            club?.label ?? (unknown ? 'Clube não informado' : 'Sem clube'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text,
          ),
        ),
      ],
    );
  }
}

class OtherPlayerRow extends StatelessWidget {
  const OtherPlayerRow({
    super.key,
    required this.player,
    required this.version,
    required this.onTap,
    this.showClub = true,
    this.stats,
  });
  final OtherPlayer player;
  final String version;
  final VoidCallback onTap;
  final bool showClub;

  final String? stats;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final details = [
      if (!showClub && player.shirtNumber != null) '#${player.shirtNumber}',
      player.positionLabel,
      if (player.age != null) '${player.age} anos',
      if (!showClub && player.nationality.isNotEmpty) player.nationality,
    ].join(' · ');
    return InkWell(
      key: ValueKey('other-player/${player.key}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ProfilePortrait(
                version: version,
                realPlayerId: player.realPlayerId,
                customAvatarFilePath: player.avatar,
                width: 38,
                height: 44,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (showClub)
                    ClipRect(
                      child: Row(
                        children: [
                          Flexible(
                            child: ClubLine(
                              version: version,
                              club: player.team,
                              unknown: player.clubUnknown,
                              size: 14,
                              style: TextStyle(color: c.muted, fontSize: 11.5),
                            ),
                          ),
                          Text(
                            '  ·  $details',
                            maxLines: 1,
                            style: TextStyle(color: c.muted, fontSize: 11.5),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.muted, fontSize: 11.5),
                    ),
                  if (stats != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      stats!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.text.withValues(alpha: .8),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            OverallPill(player.overall),
          ],
        ),
      ),
    );
  }
}

class OtherTeamTile extends StatelessWidget {
  const OtherTeamTile({
    super.key,
    required this.team,
    required this.version,
    required this.onTap,
  });
  final OtherTeam team;
  final String version;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final average = team.averageOverall;
    return InkWell(
      key: ValueKey('other-team/${team.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: team.team == null
                  ? Icon(Icons.person_off_outlined, color: c.muted)
                  : ClubLogo(version: version, club: team.team!, size: 34),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    team.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      '${team.players.length} ${team.players.length == 1 ? 'jogador' : 'jogadores'}',
                      if (average != null)
                        'média ${average.toStringAsFixed(0)}',
                    ].join(' · '),
                    style: TextStyle(color: c.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            if (team.imported || team.careerPlayers > 0)
              SourceTag(team.imported ? 'API' : 'Carreira'),
            Icon(Icons.chevron_right_rounded, color: c.muted),
          ],
        ),
      ),
    );
  }
}

class ClubLogo extends StatelessWidget {
  const ClubLogo({
    super.key,
    required this.version,
    required this.club,
    this.size = 30,
  });
  final String version;
  final CatalogItem club;
  final double size;
  @override
  Widget build(BuildContext context) =>
      club.imageUrl != null || club.imagePath != null
      ? TeamLogo.fromItem(club, size: size)
      : TeamLogo.lookup(
          fifaVersion: version,
          teamId: club.id,
          leagueId: club.leagueId,
          size: size,
        );
}

class SourceTag extends StatelessWidget {
  const SourceTag(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c.accent,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String? seasonSummary(CompetitionLine? line) {
  if (line == null) return null;
  final parts = [
    if (line.appearances != null) '${line.appearances} J',
    if (line.goals != null) '${line.goals} G',
    if (line.assists != null) '${line.assists} A',
    if (line.rating != null)
      'nota ${line.rating!.toStringAsFixed(1).replaceAll('.', ',')}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}
