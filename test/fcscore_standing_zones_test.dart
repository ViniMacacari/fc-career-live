import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/FcScore/FcScoreStandingZones.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';

FcJson zone(String type, {int? entry, String? name, List<int>? positions}) => {
  'type': type,
  'entry': ?entry,
  if (name != null) 'competition': {'id': name, 'name': name},
  'positions': ?positions,
};

void main() {
  test('Continental entry is a route, not a second competition tier', () {
    final direct = FcStandingZone(
      zone('continental', entry: 1, name: 'Libertadores'),
    );
    final preliminary = FcStandingZone(
      zone('continental', entry: 2, name: 'Libertadores'),
    );
    expect(direct.label(), 'Libertadores');
    expect(preliminary.label(), 'Libertadores · fase preliminar');
    expect(
      preliminary.label(competitionName: (_) => 'Taça do aplicativo'),
      'Taça do aplicativo · fase preliminar',
    );
    expect(direct.key, isNot(preliminary.key));
    expect(
      FcStandingZone(zone('continental', entry: 3, name: 'Outra copa')).label(),
      'Outra copa · fase preliminar',
    );
  });
  test('Group positions and row zones coexist without duplicates or invented quotas', () {
    final group = zone('relegation', positions: [17, 18, 19, 20]);
    final continental = zone(
      'continental',
      entry: 1,
      name: 'Sudamericana',
      positions: [7, 8],
    );
    final rows = <FcJson>[
      {
        'position': 8,
        'zones': [zone('continental', entry: 1, name: 'Sudamericana')],
      },
      {'position': 17},
      {'position': 10},
    ];
    final zones = fcStandingZones(rows, [group, continental, zone('unknown')]);
    expect(zones, hasLength(2));
    expect(fcRowZones(rows[0], zones), hasLength(1));
    expect(fcRowZones(rows[1], zones).single.type, 'relegation');
    expect(fcRowZones(rows[2], zones), isEmpty);
    expect(fcStandingZones([], []), isEmpty);
  });
  test('Tiers follow table positions in any league, whatever the names', () {
    final rows = <FcJson>[
      for (var i = 1; i <= 10; i++)
        {
          'position': i,
          if (i == 10) 'zones': [zone('continental', entry: 1, name: 'Copa C')],
        },
    ];
    final zones = fcStandingZones(rows, [
      zone('champion', positions: [1]),
      zone('continental', entry: 2, name: 'Copa A', positions: [5, 6]),
      zone('continental', entry: 1, name: 'Copa B', positions: [7, 8, 9]),
      zone('continental', entry: 1, name: 'Copa A', positions: [1, 2, 3, 4]),
    ]);
    final tiers = fcContinentalTiers(rows, zones);
    int tier(String name, int entry) =>
        tiers[zones
            .firstWhere(
              (z) => z.competition['name'] == name && z.entry == entry,
            )
            .key]!;
    expect(tier('Copa A', 1), 1);
    expect(tier('Copa A', 2), 1);
    expect(tier('Copa B', 1), 2);
    expect(tier('Copa C', 1), 3);
    expect(tiers, hasLength(4));
    expect(fcZoneStart(rows, zones.last), 10);
  });
  test('Promotion keeps the mapped destination league and relegation never names one', () {
    for (final (type, label) in [
      ('promotion', 'Acesso · Liga do aplicativo'),
      ('promotionPlayoff', 'Playoff de acesso · Liga do aplicativo'),
      ('relegation', 'Rebaixamento'),
      ('relegationPlayoff', 'Playoff de rebaixamento'),
    ]) {
      final z = FcStandingZone({
        ...zone(type),
        'league': {'id': 3, 'name': 'Nome da API'},
      });
      expect(z.label(leagueName: (_) => 'Liga do aplicativo'), label);
    }
  });
}
