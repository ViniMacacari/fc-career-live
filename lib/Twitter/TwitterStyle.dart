import 'dart:io';

import 'package:flutter/material.dart';

import '../utils/AppColors.dart';
import '../utils/themes.dart';

import '../utils/Components/TeamLogo.dart';
import '../utils/GameCatalog.dart';
import '../utils/databaseUtils.dart';
import 'TwitterModels.dart';

AppColors xColors(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppColors.xDark
    : AppColors.xLight;

ThemeData twitterTheme(BuildContext context) =>
    buildAppTheme(Theme.of(context).brightness, colors: xColors(context));

class XTheme extends StatelessWidget {
  const XTheme({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) => Theme(
    data: twitterTheme(context),
    child: Builder(builder: builder),
  );
}

class XAlertDialog extends AlertDialog {
  const XAlertDialog({
    super.key,
    super.title,
    super.content,
    super.actions,
    super.scrollable,
    super.contentPadding,
    super.actionsPadding,
  });
  @override
  Widget build(BuildContext context) =>
      XTheme(builder: (context) => super.build(context));
}

class XSafeArea extends SafeArea {
  const XSafeArea({
    super.key,
    required super.child,
    super.top,
    super.bottom,
    super.left,
    super.right,
    super.minimum,
    super.maintainBottomViewPadding,
  });
  @override
  Widget build(BuildContext context) =>
      XTheme(builder: (context) => super.build(context));
}

class TwitterAvatar extends StatelessWidget {
  const TwitterAvatar({
    super.key,
    required this.account,
    required this.version,
    this.size = 44,
  });
  final TwitterAccount account;
  final String version;
  final double size;
  @override
  Widget build(BuildContext context) {
    final path = CustomImageFiles.absolute(account.avatarPath);
    Widget? image;
    if (path != null && File(path).existsSync()) {
      image = Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _initial(context),
      );
    } else if (account.teamId != null) {
      image = FutureBuilder<GameCatalog>(
        future: GameCatalog.load(),
        builder: (_, snapshot) => TeamLogo.fromItem(
          snapshot.data?.team(
            version,
            account.teamId!,
            leagueId: account.leagueId,
          ),
          size: size - 8,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.of(context).panel,
      ),
      child: ClipOval(child: image ?? _initial(context)),
    );
  }

  Widget _initial(BuildContext context) => Center(
    child: Text(
      String.fromCharCodes(account.name.runes.take(1)).toUpperCase(),
      style: TextStyle(
        fontSize: size * 0.42,
        fontWeight: FontWeight.w700,
        color: AppColors.of(context).accent,
      ),
    ),
  );
}
