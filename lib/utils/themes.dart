import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'AppColors.dart';

final Color linkColor = AppColors.light.accent;

final Color expandableTileBgDark = AppColors.dark.raised;

final Color expandableTileBgLight = AppColors.light.raised;

const Color disabledCardColorDark = AppColors.disabledCard;

final ThemeData managerLightTheme = buildAppTheme(Brightness.light);
final ThemeData managerDarkTheme = buildAppTheme(Brightness.dark);
final ThemeData playerLightTheme = managerLightTheme;
final ThemeData playerDarkTheme = managerDarkTheme;

TextTheme _manropeTextTheme(TextTheme theme) =>
    theme.apply(fontFamily: 'Manrope');

ThemeData buildAppTheme(Brightness brightness, {AppColors? colors}) {
  final isDark = brightness == Brightness.dark;
  final c = colors ?? (isDark ? AppColors.dark : AppColors.light);
  final base = ThemeData(brightness: brightness);
  final primary = c.accent, foreground = c.text, muted = c.muted;
  final panel = c.panel, line = c.line, scaffold = c.background;
  final error = c.danger;
  const round = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );
  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
  return ThemeData(
    extensions: [c],
    textTheme: _manropeTextTheme(base.textTheme)
        .apply(bodyColor: foreground, displayColor: foreground),
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      surfaceContainerLowest: scaffold,
      surfaceContainerLow: panel,
      surfaceContainer: c.field,
      surfaceContainerHigh: c.raised,
      surfaceContainerHighest: c.raised,
      inverseSurface: foreground,
      onInverseSurface: scaffold,
      brightness: brightness,
      primary: primary,
      onPrimary: c.onAccent,
      secondary: primary,
      onSecondary: c.onAccent,
      error: error,
      onError: isDark ? AppColors.ink : Colors.white,
      surface: panel,
      onSurface: foreground,
      onSurfaceVariant: muted,
      outline: line,
      outlineVariant: line,
    ),
    primaryColor: primary,
    primaryColorDark: primary,
    primaryColorLight: primary,
    primarySwatch: Colors.grey,
    brightness: brightness,
    iconTheme: IconThemeData(color: foreground),
    disabledColor: muted.withValues(alpha: .45),
    scaffoldBackgroundColor: scaffold,
    cardColor: panel,
    dividerColor: line,
    drawerTheme: DrawerThemeData(backgroundColor: scaffold),
    hintColor: muted,
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: line),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      iconColor: primary,
      textColor: foreground,
      titleTextStyle: TextStyle(
        fontFamily: 'Manrope',
        color: foreground,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: 'Manrope',
        color: muted,
        fontSize: 12,
        height: 1.5,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: c.onAccent,
        minimumSize: const Size(0, 46),
        shape: round,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: c.onAccent,
        elevation: 0,
        minimumSize: const Size(0, 46),
        shape: round,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        shape: round,
        side: BorderSide(color: line),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        shape: round,
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(shape: round),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: panel,
      selectedColor: primary.withValues(alpha: .18),
      side: BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: TextStyle(
        fontFamily: 'Manrope',
        color: foreground,
        fontSize: 12,
      ),
      secondaryLabelStyle: TextStyle(
        fontFamily: 'Manrope',
        color: primary,
        fontWeight: FontWeight.w700,
      ),
      checkmarkColor: primary,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: primary,
      unselectedLabelColor: muted,
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        color: primary.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(12),
      ),
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(primary.withValues(alpha: .1)),
      dividerThickness: .5,
      headingTextStyle: TextStyle(
        fontFamily: 'Manrope',
        color: primary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      dataTextStyle: TextStyle(
        fontFamily: 'Manrope',
        color: foreground,
        fontSize: 12,
      ),
      horizontalMargin: 16,
      columnSpacing: 24,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: line),
      ),
      titleTextStyle: TextStyle(
        fontFamily: 'Manrope',
        color: foreground,
        fontSize: 19,
        fontWeight: FontWeight.w800,
      ),
      contentTextStyle: TextStyle(
        fontFamily: 'Manrope',
        color: muted,
        fontSize: 13,
        height: 1.5,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: line),
      ),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: primary,
      collapsedIconColor: muted,
      textColor: foreground,
      collapsedTextColor: foreground,
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      headerBackgroundColor: primary.withValues(alpha: .1),
      headerForegroundColor: foreground,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.raised,
      contentTextStyle: TextStyle(color: foreground),
      actionTextColor: primary,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: line),
        borderRadius: BorderRadius.all(Radius.circular(15)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: inputBorder(line),
      enabledBorder: inputBorder(line),
      focusedBorder: inputBorder(primary, 1.5),
      errorBorder: inputBorder(error),
      focusedErrorBorder: inputBorder(error, 1.5),
      labelStyle: TextStyle(color: muted, fontSize: 13),
      hintStyle: TextStyle(color: muted, fontSize: 13),
      helperStyle: TextStyle(color: muted, fontSize: 11),
      prefixIconColor: primary,
      suffixIconColor: muted,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: c.onAccent,
      elevation: 0,
      highlightElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    appBarTheme: AppBarTheme(
      systemOverlayStyle: appSystemUiStyle(brightness),
      backgroundColor: scaffold,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: foreground),
      actionsIconTheme: IconThemeData(color: foreground),
      titleTextStyle: TextStyle(
        fontFamily: 'Manrope',
        color: foreground,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

ThemeData careerDetailTheme(BuildContext context) => Theme.of(context);

SystemUiOverlayStyle appSystemUiStyle(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = dark ? AppColors.dark : AppColors.light;
  final icons = dark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: brightness,
    statusBarIconBrightness: icons,
    systemNavigationBarColor: colors.background,
    systemNavigationBarIconBrightness: icons,
    systemNavigationBarDividerColor: colors.background,
    systemNavigationBarContrastEnforced: false,
  );
}

class ThemedSystemBars extends StatelessWidget {
  const ThemedSystemBars({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: appSystemUiStyle(Theme.of(context).brightness),
    child: child,
  );
}
