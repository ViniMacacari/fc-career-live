import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../themes.dart';

enum CareerMode { player, manager }

const String themeModePrefsKey = 'themeMode';

class AppStateNotifier extends ChangeNotifier {
  AppStateNotifier({
    this._themeMode = ThemeMode.system,
    this._careerMode = CareerMode.manager,
  }) {
    _applyCareerThemes();
  }

  ThemeMode _themeMode;
  CareerMode _careerMode;
  ThemeData _lightTheme = playerLightTheme;
  ThemeData _darkTheme = playerDarkTheme;

  ThemeMode get themeMode => _themeMode;
  CareerMode get careerMode => _careerMode;

  ThemeData get lightTheme => _lightTheme;

  ThemeData get darkTheme => _darkTheme;

  static Future<AppStateNotifier> load({
    CareerMode careerMode = CareerMode.manager,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var stored = prefs.getString(themeModePrefsKey);
    if (stored == null) {
      stored = ThemeMode.system.name;
      await prefs.setString(themeModePrefsKey, stored);
    }
    return AppStateNotifier(
      themeMode: themeModeFromName(stored),
      careerMode: careerMode,
    );
  }

  static ThemeMode themeModeFromName(String? name) => ThemeMode.values
      .firstWhere((mode) => mode.name == name, orElse: () => ThemeMode.system);

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  Future<void> setThemeModeAndPersist(ThemeMode mode) async {
    setThemeMode(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(themeModePrefsKey, mode.name);
  }

  void setCareerMode(CareerMode mode, {bool shouldUpdateTheme = true}) {
    _careerMode = mode;
    if (shouldUpdateTheme) {
      _applyCareerThemes();
    }
    notifyListeners();
  }

  void setLightTheme(ThemeData theme) {
    _lightTheme = theme;
    notifyListeners();
  }

  void setDarkTheme(ThemeData theme) {
    _darkTheme = theme;
    notifyListeners();
  }

  void _applyCareerThemes() {
    final manager = _careerMode == CareerMode.manager;
    _lightTheme = manager ? managerLightTheme : playerLightTheme;
    _darkTheme = manager ? managerDarkTheme : playerDarkTheme;
  }
}
