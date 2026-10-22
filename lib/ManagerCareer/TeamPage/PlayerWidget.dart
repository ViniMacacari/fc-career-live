import '../../utils/AppColors.dart';

import 'package:flutter/material.dart';

import '../../utils/Components/PlayerAvatar.dart';
import '../../utils/Components/PitchPlayerCard.dart';

class PlayerWidget extends StatelessWidget {
  const PlayerWidget({
    super.key,
    required this.name,
    required this.position,
    required this.fifaVersion,
    required this.onTap,
    this.realPlayerId,
    this.customAvatarFilePath,
    this.overall,
    this.showPosition = true,
  });

  final String name, position, fifaVersion;
  final String? realPlayerId, customAvatarFilePath;
  final int? overall;
  final bool showPosition;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PitchPlayerCard(
    name: name,
    position: position,
    onTap: onTap,
    showPosition: showPosition,
    avatar: (radius) => PlayerAvatar(
      fifaVersion: fifaVersion,
      realPlayerId: realPlayerId,
      customAvatarFilePath: customAvatarFilePath,
      radius: radius,
    ),
    marker: overall == null
        ? null
        : CircleAvatar(
            radius: 11,
            backgroundColor: AppColors.of(context).accent,
            child: Text(
              '$overall',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.of(context).onAccent,
              ),
            ),
          ),
  );
}
