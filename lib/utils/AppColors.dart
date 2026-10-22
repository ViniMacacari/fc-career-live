import 'package:flutter/material.dart';

enum AppColorRole {
  background,
  panel,
  raised,
  field,
  line,
  text,
  muted,
  accent,
  onAccent,
  success,
  warning,
  danger,
  headerStart,
  pitchStart,
  pitchEnd,
  pitchLine,
}

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors._(this.values);
  final Map<AppColorRole, Color> values;

  static const dark = AppColors._({
    AppColorRole.background: Color(0xff080808),
    AppColorRole.panel: Color(0xff141414),
    AppColorRole.raised: Color(0xff202020),
    AppColorRole.field: Color(0xff1a1a1a),
    AppColorRole.line: Color(0xff393939),
    AppColorRole.text: Color(0xfff5f5f5),
    AppColorRole.muted: Color(0xffb0b0b0),
    AppColorRole.accent: Color(0xffb4f51c),
    AppColorRole.onAccent: Color(0xff101600),
    AppColorRole.success: Color(0xff76d668),
    AppColorRole.warning: Color(0xffedc578),
    AppColorRole.danger: Color(0xffff8c96),
    AppColorRole.headerStart: Color(0xff20251a),
    AppColorRole.pitchStart: Color(0xff192014),
    AppColorRole.pitchEnd: Color(0xff111610),
    AppColorRole.pitchLine: Color(0xff526345),
  });

  static const light = AppColors._({
    AppColorRole.background: Color(0xffffffff),
    AppColorRole.panel: Color(0xfff7f7f7),
    AppColorRole.raised: Color(0xffececec),
    AppColorRole.field: Color(0xfff2f2f2),
    AppColorRole.line: Color(0xffd3d3d3),
    AppColorRole.text: Color(0xff171717),
    AppColorRole.muted: Color(0xff626262),
    AppColorRole.accent: Color(0xff477800),
    AppColorRole.onAccent: Color(0xffffffff),
    AppColorRole.success: Color(0xff267932),
    AppColorRole.warning: Color(0xff936100),
    AppColorRole.danger: Color(0xffba263b),
    AppColorRole.headerStart: Color(0xffedf5e1),
    AppColorRole.pitchStart: Color(0xffeef4e7),
    AppColorRole.pitchEnd: Color(0xfff7faf3),
    AppColorRole.pitchLine: Color(0xff9bad88),
  });

  static final xDark = dark.copyWith(
    values: {
      AppColorRole.background: const Color(0xff000000),
      AppColorRole.panel: const Color(0xff000000),
      AppColorRole.raised: const Color(0xff16181c),
      AppColorRole.field: const Color(0xff202327),
      AppColorRole.line: const Color(0xff2f3336),
      AppColorRole.text: const Color(0xffe7e9ea),
      AppColorRole.muted: const Color(0xff71767b),
      AppColorRole.accent: const Color(0xffeff3f4),
      AppColorRole.onAccent: const Color(0xff0f1419),
      AppColorRole.headerStart: const Color(0xff000000),
    },
  );
  static final xLight = light.copyWith(
    values: {
      AppColorRole.background: const Color(0xffffffff),
      AppColorRole.panel: const Color(0xffffffff),
      AppColorRole.raised: const Color(0xfff7f9f9),
      AppColorRole.field: const Color(0xffeff3f4),
      AppColorRole.line: const Color(0xffeff3f4),
      AppColorRole.text: const Color(0xff0f1419),
      AppColorRole.muted: const Color(0xff536471),
      AppColorRole.accent: const Color(0xff0f1419),
      AppColorRole.onAccent: const Color(0xffffffff),
      AppColorRole.headerStart: const Color(0xffffffff),
    },
  );
  static const socialBlue = Color(0xff1d9bf0);

  static AppColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  Color get background => values[AppColorRole.background]!;
  Color get panel => values[AppColorRole.panel]!;
  Color get raised => values[AppColorRole.raised]!;
  Color get field => values[AppColorRole.field]!;
  Color get line => values[AppColorRole.line]!;
  Color get text => values[AppColorRole.text]!;
  Color get muted => values[AppColorRole.muted]!;
  Color get accent => values[AppColorRole.accent]!;
  Color get onAccent => values[AppColorRole.onAccent]!;
  Color get success => values[AppColorRole.success]!;
  Color get warning => values[AppColorRole.warning]!;
  Color get danger => values[AppColorRole.danger]!;
  Color get headerStart => values[AppColorRole.headerStart]!;
  Color get pitchStart => values[AppColorRole.pitchStart]!;
  Color get pitchEnd => values[AppColorRole.pitchEnd]!;
  Color get pitchLine => values[AppColorRole.pitchLine]!;

  static const ink = Color(0xff080808);
  static const logoBackdrop = Color(0xff101010);
  static const resultWin = Color(0xff16a37f);
  static const resultDraw = Color(0xff8b98a0);
  static const resultLoss = Color(0xfff2555a);
  static const ratingExcellent = Color(0xff8ccb16);
  static const ratingGood = Color(0xff4caf50);
  static const ratingAverage = Color(0xffffa726);
  static const ratingBelowAverage = Color(0xffef6c00);
  static const ratingPoor = Color(0xfff44336);
  static const ratingUnknown = Color(0xff646464);
  static const comparisonSeries = [
    Color(0xff3d9be3),
    Color(0xffd27424),
    Color(0xff199e70),
    Color(0xffc98500),
    Color(0xffdf6595),
    Color(0xff3c9a3c),
    Color(0xff9085e9),
    Color(0xffe66767),
  ];

  static const eventRed = Color(0xffed443b);
  static const missedEvent = Color(0xffff9200);
  static const neutralResult = Color(0xff9e9e9e);
  static const lowRating = Color(0xffe34e45);
  static const redCard = Color(0xffe53935);
  static const yellowCard = Color(0xfffdd835);
  static const markerShadow = Color(0x88080808);
  static const markerHighlight = Color(0xffffd17a);
  static const markerMiddle = Color(0xffffa326);
  static const markerEdge = Color(0xffec8612);
  static const markerInk = Color(0xfffff3de);
  static const internationalTier1Dark = Color(0xffb4f51c);
  static const internationalTier1Light = Color(0xff477800);
  static const internationalTier2Dark = Color(0xffc3a6ff);
  static const internationalTier2Light = Color(0xff7446cf);
  static const internationalTier3Dark = Color(0xff5fd3dc);
  static const internationalTier3Light = Color(0xff00808b);
  static const newBadge = Color(0xfffb8c00);
  static const trophyGold = Color(0xffe6b65c);
  static const socialRepost = Color(0xff00ba7c);
  static const socialLike = Color(0xfff91880);
  static const disabledCard = Color(0x1fffffff);
  static const injury = Color(0xffff6b7b);
  static const pitchCard = Color(0xffefc66f);
  static const tournamentGold = Color(0xffd9a62e);
  static const tournamentSilver = Color(0xffa7b0b6);
  static const negativeTint = Color(0xff4a2a2e);
  static const goodRating = Color(0xff51ad53);
  static const averageRating = Color(0xffffb541);
  static const badRating = Color(0xffef5350);
  static const transferIncoming = Color(0xff51b354);
  static const goalsSeries = Color(0xff58b861);
  static const assistsSeries = Color(0xff078b9e);
  static const passingSeries = Color(0xff19c1cb);
  static const defensiveSeries = Color(0xff349647);
  static const possessionSeries = Color(0xff6ac966);
  static const profileGoodRating = Color(0xff50ad50);
  static const profileAverageRating = Color(0xfff4a727);
  static const goalMarker = Color(0xff4da854);
  static const salaryPositive = Color(0xff58ae59);
  static const subtleOverlay = Color(0x14ffffff);

  static Color onColor(Color background) =>
      background.computeLuminance() > .18 ? ink : Colors.white;

  @override
  AppColors copyWith({Map<AppColorRole, Color>? values}) =>
      AppColors._({...this.values, ...?values});

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors._({
      for (final role in AppColorRole.values)
        role: Color.lerp(values[role], other.values[role], t)!,
    });
  }
}
