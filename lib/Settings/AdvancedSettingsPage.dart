import 'package:shared_preferences/shared_preferences.dart';

abstract class AdvancedSettings {
  static const String countPreSeasonKey = 'count_pre_season_matches';
  static const String autoFillTeamScoreKey = 'auto_fill_team_score';
  static const String autoFillTeamShotsCountKey = 'auto_fill_team_shots_count';

  static Future<bool> countPreSeasonMatches() async =>
      (await SharedPreferences.getInstance()).getBool(countPreSeasonKey) ??
      true;

  static Future<bool> autoFillTeamScore() async => true;

  static Future<bool> autoFillTeamShotsCount() async =>
      (await SharedPreferences.getInstance()).getBool(
        autoFillTeamShotsCountKey,
      ) ??
      false;
}
