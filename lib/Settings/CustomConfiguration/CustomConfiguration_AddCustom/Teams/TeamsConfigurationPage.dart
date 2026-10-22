import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../utils/Components/TeamLogo.dart';
import '../../../../utils/GameCatalog.dart';
import '../../CustomConfigurationComponents.dart';
import 'CreateCustomTeamPage.dart';
import 'EditCustomTeamPage.dart';

class TeamsConfigurationPage extends StatefulWidget {
  const TeamsConfigurationPage({super.key});
  @override
  State<TeamsConfigurationPage> createState() => _TeamsConfigurationPageState();
}

class _TeamsConfigurationPageState extends State<TeamsConfigurationPage> {
  final Future<GameCatalog> _catalog = GameCatalog.load();
  String _query = '';

  Future<void> _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) => CustomConfigurationTheme(
    child: Scaffold(
      appBar: AppBar(
        title: Text('customConfiguration.teamsConfiguration'.tr()),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'teams.createTeam'.tr(),
        onPressed: () => _open(const CreateCustomTeamPage()),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          children: [
            CustomSearchField(
              hint: 'teams.searchByText'.tr(),
              onChanged: (value) => setState(() => _query = value),
            ),
            Expanded(
              child: FutureBuilder<GameCatalog>(
                future: _catalog,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ValueListenableBuilder<int>(
                    valueListenable: GameCatalog.customDataRevision,
                    builder: (context, _, _) => _list(snapshot.data!),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _list(GameCatalog catalog) {
    if (catalog.customClubs.isEmpty) return const CustomEmptyState();
    final query = _query.trim().toLowerCase();
    final listed = <String>{};
    final groups = <(CatalogItem, List<CatalogItem>)>[];
    for (final entry in catalog.getAllLeagues()) {
      final teams = entry.teams.where((team) => team.isCustom).toList();
      if (teams.isEmpty) continue;
      listed.addAll(teams.map((team) => team.id));
      groups.add((entry.league, teams));
    }
    final orphans = [
      for (final club in catalog.customClubs)
        if (!listed.contains(club.id)) catalog.team(club.fifaVersion, club.id)!,
    ];
    if (orphans.isNotEmpty) {
      groups.add((const CatalogItem('', '—'), orphans));
    }
    final visible =
        [
          for (final (league, teams) in groups)
            (
              league,
              teams
                  .where((team) => team.label.toLowerCase().contains(query))
                  .toList(),
            ),
        ].where((group) => group.$2.isNotEmpty).toList()..sort(
          (a, b) =>
              a.$1.label.toLowerCase().compareTo(b.$1.label.toLowerCase()),
        );
    if (visible.isEmpty) {
      return const CustomEmptyState(textKey: 'common.noItems');
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final (league, teams) = visible[index];
        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey(
              'custom-teams-${league.id}-${query.isNotEmpty}',
            ),
            initiallyExpanded: query.isNotEmpty,
            leading: TeamLogo.fromItem(league, size: 32),
            title: Row(
              children: [
                Flexible(
                  child: Text(league.label, overflow: TextOverflow.ellipsis),
                ),
                WomanLeagueIcon(visible: league.isWoman),
              ],
            ),
            subtitle: Text(
              'customConfiguration.leagueTeamsCount'.tr(
                args: ['${teams.length}'],
              ),
            ),
            children: [
              for (final team in teams)
                CustomListCard(
                  onTap: () {
                    final club = catalog.customClub(team.id);
                    if (club != null) _open(EditCustomTeamPage(club: club));
                  },
                  child: ListTile(
                    leading: TeamLogo.fromItem(team, size: 36),
                    title: Text(team.label),
                    subtitle: Text(team.fifaVersion ?? ''),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
