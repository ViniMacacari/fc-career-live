import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../GameCatalog.dart';
import '../databaseUtils.dart';
import '../AppColors.dart';
import 'CatalogLogoAssets.dart';

class TeamLogo extends StatelessWidget {
  const TeamLogo({
    super.key,
    this.imageUrl,
    this.imagePath,
    this.localAsset,
    this.width = 30,
    this.height = 30,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.assetLabel,
    this.fallbackIcon = Icons.shield_outlined,
  });

  factory TeamLogo.fromItem(
    CatalogItem? item, {
    Key? key,
    double size = 30,
    BoxFit fit = BoxFit.contain,
    Widget? placeholder,
  }) => TeamLogo(
    key: key,
    imageUrl: item?.imageUrl,
    imagePath: item?.imagePath,
    localAsset: _assetFor(item),
    width: size,
    height: size,
    fit: fit,
    placeholder: placeholder,
    assetLabel: item != null && !item.isCustom && item.leagueId == null
        ? item.label
        : null,
    fallbackIcon: item != null && item.leagueId == null
        ? Icons.emoji_events_outlined
        : Icons.shield_outlined,
  );

  factory TeamLogo.lookup({
    Key? key,
    required String fifaVersion,
    required String teamId,
    String? leagueId,
    double size = 30,
    BoxFit fit = BoxFit.contain,
    Widget? placeholder,
  }) {
    final item = GameCatalog.current?.team(
      fifaVersion,
      teamId,
      leagueId: leagueId,
    );
    return TeamLogo(
      key: key,
      imageUrl: item?.imageUrl,
      imagePath: item?.imagePath,
      localAsset: _assetFor(item),
      width: size,
      height: size,
      fit: fit,
      placeholder: placeholder,
    );
  }

  static String? _assetFor(CatalogItem? item) {
    if (item == null || item.isCustom || item.customizationId != null) {
      return null;
    }
    if (item.label.toLowerCase() == 'sao paulo' ||
        item.label.toLowerCase() == 'são paulo') {
      return 'assets/images/clubLogos/sao-paulo.png';
    }
    return item.assetPath;
  }

  final String? imageUrl, imagePath, localAsset;
  final double width, height;
  final BoxFit fit;

  final Widget? placeholder;
  final String? assetLabel;
  final IconData fallbackIcon;

  Widget _fallback(BuildContext context) =>
      placeholder ??
      SizedBox(
        width: width,
        height: height,
        child: Icon(
          fallbackIcon,
          size: (width < height ? width : height) * .8,
          color: AppColors.of(context).muted,
        ),
      );

  bool _svg(String value) =>
      Uri.tryParse(value)?.path.toLowerCase().endsWith('.svg') == true;

  Widget _remote(BuildContext context) {
    final configuredUrl = imageUrl?.trim();
    final url = configuredUrl?.isNotEmpty == true
        ? configuredUrl
        : (imagePath?.startsWith('http') == true ? imagePath?.trim() : null);
    if (url == null || url.isEmpty) return _fallback(context);
    if (url.startsWith('assets/')) {
      return _asset(context, url, remoteFallback: false);
    }
    if (_svg(url)) {
      return SvgPicture.network(
        url,
        width: width,
        height: height,
        fit: fit,
        placeholderBuilder: (_) => _fallback(context),
        errorBuilder: (_, _, _) => _fallback(context),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      placeholder: (_, _) => _fallback(context),
      errorWidget: (_, _, _) => _fallback(context),
    );
  }

  Widget _asset(
    BuildContext context,
    String asset, {
    bool remoteFallback = true,
  }) {
    Widget failed() => remoteFallback ? _remote(context) : _fallback(context);
    if (_svg(asset)) {
      return SvgPicture.asset(
        asset,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => failed(),
      );
    }
    return Image.asset(
      asset,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => failed(),
    );
  }

  bool _isValidLocalImage(String? path) {
    if (path == null) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  Widget _build(BuildContext context) {
    final local = CustomImageFiles.absolute(imagePath);
    if (_isValidLocalImage(local)) {
      if (_svg(local!)) {
        return SvgPicture.file(
          File(local),
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, _, _) => _remote(context),
        );
      }
      return Image.file(
        File(local),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => _remote(context),
      );
    }
    if (localAsset != null) {
      return _asset(context, localAsset!);
    }
    if (imagePath?.startsWith('assets/') == true) {
      return _asset(context, imagePath!);
    }
    if (assetLabel != null) {
      return FutureBuilder<String?>(
        future: CatalogLogoAssets.league(assetLabel!),
        builder: (context, snapshot) => snapshot.data == null
            ? _remote(context)
            : _asset(context, snapshot.data!),
      );
    }
    return _remote(context);
  }

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    if (path != null &&
        CustomImageFiles.isRelative(path) &&
        CustomImageFiles.cachedDocsDir == null) {
      return FutureBuilder<String>(
        future: CustomImageFiles.docsDir(),
        builder: (context, snapshot) =>
            snapshot.connectionState == ConnectionState.done
            ? _build(context)
            : SizedBox(width: width, height: height),
      );
    }
    return _build(context);
  }
}
