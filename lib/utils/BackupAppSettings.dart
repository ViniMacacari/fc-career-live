import 'package:shared_preferences/shared_preferences.dart';

import 'SecureStorageService.dart';

class BackupAppSettings {
  BackupAppSettings._(this.preferences, this.secureSettings);
  final Map<String, Object?>? preferences;
  final Map<String, String>? secureSettings;

  static const _strings = {
    'appLang',
    'themeMode',
    'twitter_ai_language',
    'twitter_ai_instructions',
  };
  static const _bools = {
    'count_pre_season_matches',
    'auto_fill_team_score',
    'auto_fill_team_shots_count',
  };
  static const _ints = {'twitter_ai_max_tokens'};
  static const _secureKeys = {'openrouter_api_key', 'openrouter_model'};
  static bool _isListKey(String key) =>
      key.startsWith('auto_results_dismissed_') ||
      key.startsWith('auto_trophies_dismissed_');
  static bool _isAppKey(String key) =>
      _strings.contains(key) ||
      _bools.contains(key) ||
      _ints.contains(key) ||
      _isListKey(key);

  static Future<BackupAppSettings> capture() async {
    final prefs = await SharedPreferences.getInstance();
    final values = <String, Object?>{
      for (final key in prefs.getKeys())
        if (_isAppKey(key)) key: prefs.get(key),
    };
    final apiKey = await SecureStorageService.readOpenRouterApiKey();
    final model = await SecureStorageService.readOpenRouterModel();
    return BackupAppSettings._(values, {
      'openrouter_api_key': ?apiKey,
      'openrouter_model': ?model,
    });
  }

  Map<String, Object?> toMetadata() => {
    'preferences': preferences,
    'secureSettings': secureSettings,
  };

  static BackupAppSettings? fromMetadata(Map marker) {
    if (!marker.containsKey('preferences') &&
        !marker.containsKey('secureSettings')) {
      return null;
    }
    Map<String, Object?>? values;
    Map<String, String>? secure;
    if (marker.containsKey('preferences')) {
      final raw = marker['preferences'];
      if (raw is! Map) {
        throw const FormatException('Configurações do backup inválidas.');
      }
      values = {};
      for (final entry in raw.entries) {
        final key = entry.key, value = entry.value;
        if (key is! String || !_isAppKey(key)) continue;
        final valid =
            _strings.contains(key) && value is String ||
            _bools.contains(key) && value is bool ||
            _ints.contains(key) && value is int ||
            _isListKey(key) &&
                value is List &&
                value.every((item) => item is String);
        if (!valid) {
          throw const FormatException('Configurações do backup inválidas.');
        }
        values[key] = _isListKey(key)
            ? List<String>.from(value as List)
            : value;
      }
    }
    if (marker.containsKey('secureSettings')) {
      final raw = marker['secureSettings'];
      if (raw is! Map) {
        throw const FormatException('Configurações da IA no backup inválidas.');
      }
      secure = {};
      for (final entry in raw.entries) {
        if (!_secureKeys.contains(entry.key)) continue;
        if (entry.value is! String) {
          throw const FormatException(
            'Configurações da IA no backup inválidas.',
          );
        }
        secure[entry.key as String] = entry.value as String;
      }
    }
    return BackupAppSettings._(values, secure);
  }

  Future<void> restore() async {
    final values = preferences;
    if (values != null) {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().where(_isAppKey)) {
        if (!values.containsKey(key) && !await prefs.remove(key)) {
          throw StateError('Não foi possível restaurar as configurações.');
        }
      }
      for (final entry in values.entries) {
        final value = entry.value;
        final ok = switch (value) {
          String() => await prefs.setString(entry.key, value),
          bool() => await prefs.setBool(entry.key, value),
          int() => await prefs.setInt(entry.key, value),
          List<String>() => await prefs.setStringList(entry.key, value),
          _ => false,
        };
        if (!ok) {
          throw StateError('Não foi possível restaurar as configurações.');
        }
      }
    }
    final secure = secureSettings;
    if (secure != null) {
      final key = secure['openrouter_api_key'],
          model = secure['openrouter_model'];
      if (key == null) {
        await SecureStorageService.deleteOpenRouterApiKey();
      } else {
        await SecureStorageService.writeOpenRouterApiKey(key);
      }
      if (model == null) {
        await SecureStorageService.deleteOpenRouterModel();
      } else {
        await SecureStorageService.writeOpenRouterModel(model);
      }
    }
  }
}
