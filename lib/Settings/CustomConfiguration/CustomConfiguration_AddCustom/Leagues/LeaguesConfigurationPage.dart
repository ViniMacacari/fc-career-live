import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../utils/Components/TeamLogo.dart';
import '../../../../utils/GameCatalog.dart';
import '../../CustomConfigurationComponents.dart';
import 'CreateCustomLeaguePage.dart';
import 'EditCustomLeaguePage.dart';

class LeaguesConfigurationPage extends StatefulWidget {
  const LeaguesConfigurationPage({super.key});
  @override
  State<LeaguesConfigurationPage> createState() =>
      _LeaguesConfigurationPageState();
}

class _LeaguesConfigurationPageState extends State<LeaguesConfigurationPage> {
  final Future<GameCatalog> _catalog = GameCatalog.load();
  String _query = '';

  Future<void> _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) => CustomConfigurationTheme(
    child: Scaffold(
      appBar: AppBar(
        title: Text('customConfiguration.leaguesConfiguration'.tr()),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'customConfiguration.createLeague'.tr(),
        onPressed: () => _open(const CreateCustomLeaguePage()),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          children: [
            CustomSearchField(
              hint: 'teams.searchLeague'.tr(),
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
    final all = catalog.customLeagueEntries()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final query = _query.trim().toLowerCase();
    final leagues = all
        .where((entry) => entry.label.toLowerCase().contains(query))
        .toList();
    if (all.isEmpty) return const CustomEmptyState();
    if (leagues.isEmpty) {
      return const CustomEmptyState(textKey: 'common.noItems');
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: leagues.length,
      itemBuilder: (context, index) {
        final entry = leagues[index];
        final league = catalog.customLeague(entry.id);
        return CustomListCard(
          onTap: league == null
              ? null
              : () => _open(EditCustomLeaguePage(league: league)),
          child: ListTile(
            leading: TeamLogo.fromItem(entry.league, size: 40),
            title: Row(
              children: [
                Flexible(
                  child: Text(entry.label, overflow: TextOverflow.ellipsis),
                ),
                WomanLeagueIcon(visible: entry.isWoman),
              ],
            ),
            subtitle: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  'customConfiguration.leagueTeamsCount'.tr(
                    args: ['${entry.teams.length}'],
                  ),
                ),
                Text((entry.league.fifaVersion ?? '').split(',').join(', ')),
              ],
            ),
          ),
        );
      },
    );
  }
}
