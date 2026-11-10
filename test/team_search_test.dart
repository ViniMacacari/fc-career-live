import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/TeamSearch.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<TeamChoice> choices;

  setUpAll(() async {
    final catalog = await GameCatalog.load();
    choices = [
      for (final league in catalog.getAllLeagues('FC26'))
        for (final team in league.teams) (league: league.league, team: team),
    ];
  });

  List<TeamChoice> find(
    String query, {
    String? selected,
    String? selectedLeague,
    Set<String> preferred = const {},
    List<TeamChoice> extra = const [],
  }) => uniqueClubs(
    searchTeams([...choices, ...extra], query, preferredTeamIds: preferred),
    selectedTeamId: selected,
    selectedLeagueId: selectedLeague,
    preferredTeamIds: preferred,
  );

  test('A club listed in two competitions appears once', () {
    for (final query in ['sao paulo', 'flamengo', 'boca juniors', 'santos']) {
      final found = find(query)
          .where((c) => clubNameKey(c.team.label) == clubNameKey(query))
          .toList();
      expect(found, hasLength(1), reason: query);
      expect(continentalLeagueIds, isNot(contains(found.single.league.id)));
    }
  });

  test('The selected or career club wins over its duplicate', () {
    expect(
      find(
        'sao paulo',
        selected: '40-13',
        selectedLeague: '1014',
      ).map((c) => c.team.id),
      contains('40-13'),
    );
    final linked = find('flamengo', preferred: {'39-14'});
    expect(linked.first.team.id, '39-14');
    expect(linked.where((c) => c.team.label == 'Flamengo'), hasLength(1));
  });

  test('Different clubs and women teams with the same name remain', () {
    final liverpool = find('liverpool').map((c) => c.league.id).toSet();
    expect(liverpool, containsAll(['13', '1003', '62-w']));
    final racing = find('racing').map((c) => c.team.id).toSet();
    expect(racing, containsAll(['1-20', '33-17']));
  });

  test('A custom club repeated by name is merged', () {
    const league = CatalogItem('custom-league', 'Liga', isCustom: true);
    final found = find(
      'meu clube',
      extra: [
        for (final id in ['a', 'b'])
          (league: league, team: CatalogItem(id, 'Meu Clube', isCustom: true)),
      ],
    );
    expect(found, hasLength(1));
  });

  test('Name matches come before league matches and words can be partial', () {
    final found = find('premier');
    expect(found, isNotEmpty);
    expect(found.every((c) => c.league.label.contains('Premier')), isTrue);
    final words = find('atl min');
    expect(words.first.team.label, contains('Mineiro'));
    expect(find('does-not-exist'), isEmpty);
  });
}
