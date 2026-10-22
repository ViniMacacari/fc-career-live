import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../databaseUtils.dart';

class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.fifaVersion,
    this.realPlayerId,
    this.customAvatarFilePath,
    this.radius = 20,
  });
  final String fifaVersion;
  final String? realPlayerId, customAvatarFilePath;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = CircleAvatar(
      radius: radius,
      child: Icon(Icons.person, size: radius),
    );
    final diameter = radius * 2;
    final pixels =
        ((diameter * MediaQuery.devicePixelRatioOf(context) / 32).ceil() * 32)
            .clamp(32, 1024);
    Widget remote() {
      final url = getPlayerImageUrl(realPlayerId, fifaVersion);
      if (url == null) return placeholder;
      return CachedNetworkImage(
        imageUrl: url,
        width: diameter,
        height: diameter,
        memCacheWidth: pixels,
        fit: BoxFit.cover,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      );
    }

    final local = CustomImageFiles.absolute(customAvatarFilePath);
    return ClipOval(
      child: SizedBox.square(
        dimension: diameter,
        child: local == null
            ? remote()
            : Image.file(
                File(local),
                width: diameter,
                height: diameter,
                cacheWidth: pixels,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                frameBuilder: (_, child, frame, synchronous) =>
                    synchronous || frame != null ? child : placeholder,
                errorBuilder: (_, _, _) => remote(),
              ),
      ),
    );
  }
}
