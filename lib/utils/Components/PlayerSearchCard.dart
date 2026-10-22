import 'package:flutter/material.dart';

import '../../ManagerCareer/TeamPage/ViewPlayer/PlayerProfileVisuals.dart'
    show ProfilePortrait;
import '../AppColors.dart';
import '../GameCatalog.dart';
import '../GamePlayers.dart';
import 'TeamLogo.dart';

class PlayerClubCaption extends StatelessWidget {
  const PlayerClubCaption({super.key, this.club});
  final CatalogItem? club;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      children: [
        TeamLogo.fromItem(
          club ?? const CatalogItem('', '', leagueId: ''),
          size: 18,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            club?.label ?? 'Clube não informado',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: AppColors.of(context).muted),
          ),
        ),
      ],
    ),
  );
}

class PlayerSearchCard extends StatelessWidget {
  factory PlayerSearchCard.fromRow({
    Key? key,
    required Map<String, Object?> player,
    required String name,
    required String version,
    required VoidCallback onTap,
    CatalogItem? club,
  }) {
    final positions = player['positions'];
    final position = positions is List
        ? positions.join(', ')
        : positionShortLabels[player['positionId']?.toString()];
    return PlayerSearchCard(
      key: key,
      name: name,
      version: version,
      realPlayerId: player['realPlayerId']?.toString(),
      avatar: player['customAvatarFilePath']?.toString(),
      details: [
        if (position?.isNotEmpty == true) position!,
        if (player['overall'] != null) 'GER ${player['overall']}',
      ].join(' • '),
      club: club,
      onTap: onTap,
    );
  }

  const PlayerSearchCard({
    super.key,
    required this.name,
    required this.version,
    required this.onTap,
    this.realPlayerId,
    this.avatar,
    this.details,
    this.club,
    this.trailing,
  });
  final String name, version;
  final String? realPlayerId, avatar, details;
  final CatalogItem? club;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    color: AppColors.of(context).panel,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: ProfilePortrait(
        version: version,
        realPlayerId: realPlayerId,
        customAvatarFilePath: avatar,
        width: 38,
        height: 49,
      ),
      title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (details?.isNotEmpty == true)
            Text(details!, maxLines: 2, overflow: TextOverflow.ellipsis),
          PlayerClubCaption(club: club),
        ],
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}
