import 'package:flutter/material.dart';

import '../AppColors.dart';

class PitchPlayerCard extends StatelessWidget {
  const PitchPlayerCard({
    super.key,
    required this.name,
    required this.position,
    required this.avatar,
    this.onTap,
    this.marker,
    this.showPosition = true,
    this.overlays = const [],
    this.avatarKey,
    this.nameKey,
  });
  final String name, position;
  final Widget Function(double radius) avatar;
  final VoidCallback? onTap;
  final Widget? marker;
  final bool showPosition;
  final List<Widget> overlays;
  final Key? avatarKey, nameKey;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 96,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 62;
        final twoLines = !showPosition || constraints.maxHeight >= 94;
        final scaler = MediaQuery.textScalerOf(context);
        final font = compact ? 11.0 : 12.0;
        final positionFont = compact ? 9.0 : 10.0;
        final textHeight =
            ((showPosition ? 11.0 : 0.0) + (twoLines ? 27.0 : 14.0) + 8) *
            scaler.scale(12) /
            12;
        final diameter = (constraints.maxHeight - textHeight)
            .clamp(compact ? 24.0 : 32.0, 52.0)
            .clamp(24.0, (constraints.maxWidth - 16).clamp(24.0, 52.0));
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: constraints.maxWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        SizedBox.square(
                          key: avatarKey,
                          dimension: diameter,
                          child: avatar(diameter / 2),
                        ),
                        if (marker != null)
                          Positioned(right: -8, bottom: -2, child: marker!),
                        ...overlays,
                      ],
                    ),
                    SizedBox(height: compact ? 3 : 4),
                    if (showPosition)
                      Text(
                        position,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.of(context).muted,
                          fontSize: positionFont,
                          height: 1.1,
                        ),
                      ),
                    Text(
                      name,
                      key: nameKey,
                      maxLines: twoLines ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.of(context).text,
                        fontSize: font,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
