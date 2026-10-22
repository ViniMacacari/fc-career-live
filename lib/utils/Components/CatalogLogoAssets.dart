import 'package:flutter/services.dart';

class CatalogLogoAssets {
  static final _leagues = <String, Future<String?>>{};
  static Future<List<String>>? _loading;
  static Future<List<String>> get files =>
      _loading ??= AssetManifest.loadFromAssetBundle(rootBundle).then(
        (m) => m
            .listAssets()
            .where((p) => p.startsWith('assets/images/tournamentLogos/'))
            .toList(),
      );

  static String normalize(String label) => label
      .toLowerCase()
      .replaceAll(RegExp('[áàâãä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòôõö]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp('[^a-z0-9]'), '');

  static List<String> _ordered(List<String> input, String? version) {
    final order = {?version, 'FC27', 'FC26', 'FC25', 'FC24', 'FIFA23'}.toList();
    return [...input]..sort((a, b) {
      int rank(String path) {
        final i = order.indexWhere((v) => path.contains('/$v/'));
        return i < 0 ? order.length : i;
      }

      return rank(a).compareTo(rank(b));
    });
  }

  static Future<String?> tournament(String id, String version) async {
    final escaped = RegExp.escape(id);
    final variant = RegExp('^$escaped-(?:w|[0-9]+)-');
    return _ordered(
      (await files).where((p) {
        final name = p.split('/').last;
        return name.startsWith('$id-') && !variant.hasMatch(name);
      }).toList(),
      version,
    ).firstOrNull;
  }

  static Future<String?> league(String label, [String? version]) =>
      _leagues.putIfAbsent('$version/$label', () => _league(label, version));

  static Future<String?> _league(String label, String? version) async {
    const aliases = {
      '1aproleague': 'proleague',
      'ligue1mcdonalds': 'ligue1',
      'ligue2bkt': 'ligue2',
      'serieaenilive': 'seriea',
      'isl': 'heroisl',
      'kleague1': 'kl1ague1',
      'scottishpremiership': 'cinchprem',
      'laligaeasports': 'laliga',
      'creditsuissesuperleague': 'cssl',
      'trendyolsuperlig': 'superlig',
      'majorleaguesoccer': 'mls',
      'barclayswsl': 'wsl',
      'arkemapl': 'arkemapremierligue',
    };
    final normalized = normalize(label);
    final wanted = aliases[normalized] ?? normalized;
    if (wanted.isEmpty) return null;
    return _ordered(
      (await files).where((p) {
        final name = p
            .split('/')
            .last
            .replaceFirst(RegExp(r'^[0-9]+(?:-(?:w|[0-9]+))?-'), '')
            .replaceFirst(RegExp(r'\.[^.]+$'), '');
        return normalize(name) == wanted;
      }).toList(),
      version,
    ).firstOrNull;
  }
}
