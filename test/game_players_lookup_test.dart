import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/utils/GamePlayers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'An empty lookup needs no catalog, even for an unknown edition',
    () async {
      expect(await GamePlayers.lookup('none', []), isEmpty);
    },
  );

  for (final version in ['FC26', 'FC27']) {
    test('$version subset matches the complete JSON/gzip catalog', () async {
      final subset = await GamePlayers.lookup(version, [
        '158023',
        '20801',
        'missing',
      ]);
      expect(subset.keys, unorderedEquals(['158023', '20801']));
      final repeated = await GamePlayers.lookup(version, ['158023', 'missing']);
      expect(identical(repeated['158023'], subset['158023']), isTrue);
      final all = await GamePlayers.load(version);
      for (final entry in subset.entries) {
        final full = all.singleWhere((p) => p.id == entry.key);
        final selected = entry.value;
        expect(
          [
            selected.name,
            selected.overall,
            selected.potential,
            selected.position,
            selected.positionIds,
            selected.foot,
            selected.height,
            selected.weight,
            selected.birthdate,
            selected.nationalityCode,
            selected.nationalityName,
            selected.realFace,
            selected.teamId,
            selected.teamName,
          ],
          [
            full.name,
            full.overall,
            full.potential,
            full.position,
            full.positionIds,
            full.foot,
            full.height,
            full.weight,
            full.birthdate,
            full.nationalityCode,
            full.nationalityName,
            full.realFace,
            full.teamId,
            full.teamName,
          ],
        );
      }
      final fromFull = await GamePlayers.lookup(version, ['20801']);
      expect(fromFull.keys, ['20801']);
      expect(subset['158023']!.teamId, '112893');
    });
  }
}
