import 'FcScoreApi.dart';

class FcStandingZone {
  FcStandingZone(this.data);
  final FcJson data;
  String get type => fcId(data['type']);
  FcJson get competition => fcObject(data['competition']);
  FcJson get league => fcObject(data['league']);
  int? get entry => fcInt(data['entry']);
  String get key =>
      '$type:${fcId(competition['id'])}:${entry ?? ''}:${fcId(league['id'])}';
  List<int> get positions =>
      (data['positions'] as List? ?? const [])
          .map(fcInt)
          .whereType<int>()
          .where((p) => p > 0)
          .toSet()
          .toList()
        ..sort();
  bool get supported => const {
    'champion',
    'promotion',
    'promotionPlayoff',
    'relegation',
    'relegationPlayoff',
    'continental',
  }.contains(type);

  String label({
    String Function(FcJson)? competitionName,
    String Function(FcJson)? leagueName,
  }) {
    final destination =
        competitionName?.call(competition) ??
        fcName(competition['name'], 'Competição internacional');
    final targetLeague = leagueName?.call(league) ?? fcName(league['name'], '');
    final suffix = targetLeague.isEmpty ? '' : ' · $targetLeague';
    return switch (type) {
      'champion' => 'Campeão',
      'promotion' => 'Acesso$suffix',
      'promotionPlayoff' => 'Playoff de acesso$suffix',
      'relegation' => 'Rebaixamento',
      'relegationPlayoff' => 'Playoff de rebaixamento',
      'continental' =>
        '$destination${entry != null && entry! > 1 ? ' · fase preliminar' : ''}',
      _ => '',
    };
  }
}

List<FcStandingZone> fcStandingZones(
  List<FcJson> rows,
  List<FcJson> groupZones,
) {
  final result = <String, FcStandingZone>{};
  for (final raw in [
    ...groupZones,
    for (final row in rows) ...fcList(row['zones']),
  ]) {
    final zone = FcStandingZone(raw);
    if (zone.supported) result.putIfAbsent(zone.key, () => zone);
  }
  return result.values.toList();
}

List<FcStandingZone> fcRowZones(FcJson row, List<FcStandingZone> zones) {
  final result = <String, FcStandingZone>{};
  for (final raw in fcList(row['zones'])) {
    final zone = FcStandingZone(raw);
    if (zone.supported) {
      result[zone.key] = zone;
    }
  }
  final position = fcInt(row['position']);
  for (final zone in zones) {
    if (position != null && zone.positions.contains(position)) {
      result[zone.key] = zone;
    }
  }
  return result.values.toList();
}

int? fcZoneStart(List<FcJson> rows, FcStandingZone zone) {
  final positions =
      zone.positions.isNotEmpty
            ? zone.positions
            : [
                for (final row in rows)
                  if (fcList(row['zones'])
                      .any((raw) => FcStandingZone(raw).key == zone.key))
                    ?fcInt(row['position']),
              ]
        ..sort();
  return positions.isEmpty ? null : positions.first;
}

Map<String, int> fcContinentalTiers(
  List<FcJson> rows,
  List<FcStandingZone> zones,
) {
  String competition(FcStandingZone zone) {
    final id = fcId(zone.competition['id']);
    return id.isEmpty ? zone.key : id;
  }

  final best = <String, int>{};
  for (final zone in zones.where((z) => z.type == 'continental')) {
    final start = fcZoneStart(rows, zone), id = competition(zone);
    if (start != null && start < (best[id] ?? start + 1)) {
      best[id] = start;
    }
  }
  final order = best.keys.toList()
    ..sort((a, b) => best[a]!.compareTo(best[b]!));
  return {
    for (final zone in zones)
      if (zone.type == 'continental' && order.contains(competition(zone)))
        zone.key: order.indexOf(competition(zone)) + 1,
  };
}
