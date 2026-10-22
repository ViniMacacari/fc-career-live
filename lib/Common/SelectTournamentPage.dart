import '../utils/themes.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../Settings/CustomConfiguration/CustomConfiguration_AddCustom/Tournaments/CreateCustomTournamentPage.dart';
import '../models/Tournament.dart';
import '../utils/GameCatalog.dart';
import '../utils/SqlService.dart';
import '../utils/Components/CompetitionLogo.dart';

class SelectTournamentPage extends StatefulWidget {
  const SelectTournamentPage({super.key, required this.fifaVersion});
  final String fifaVersion;
  @override
  State<SelectTournamentPage> createState() => _SelectTournamentPageState();
}

class _SelectTournamentPageState extends State<SelectTournamentPage> {
  String _query = '';
  bool _showLeagues = false;
  late final Future<List<CatalogItem>> _items = _load();
  late final Future<GameCatalog> _catalog = GameCatalog.load();

  Future<List<CatalogItem>> _load() async {
    final catalog = await GameCatalog.load();
    final builtIn = await catalog.tournaments(widget.fifaVersion);
    final custom = await SqlService.instance.getCustomTournaments(
      widget.fifaVersion,
    );
    return [
      ...builtIn,
      ...custom.map((item) => CatalogItem(item.id, item.name)),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<Tournament>(
      MaterialPageRoute(
        builder: (_) =>
            CreateCustomTournamentPage(fifaVersion: widget.fifaVersion),
      ),
    );
    if (!mounted || created == null) return;
    Navigator.pop(context, CatalogItem(created.id, created.name));
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: careerDetailTheme(context),
    child: Scaffold(
      appBar: AppBar(title: Text('tournaments.selectTournament'.tr())),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        tooltip: 'customConfiguration.createTournament'.tr(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text('customConfiguration.tournaments'.tr()),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('customConfiguration.leagues'.tr()),
                ),
              ],
              selected: {_showLeagues},
              onSelectionChanged: (selection) =>
                  setState(() => _showLeagues = selection.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'tournaments.searchTournament'.tr(),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
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
                final catalog = snapshot.data!;
                if (!_showLeagues) {
                  return FutureBuilder<List<CatalogItem>>(
                    future: _items,
                    builder: (context, tournaments) {
                      if (tournaments.hasError) {
                        return Center(child: Text('${tournaments.error}'));
                      }
                      if (!tournaments.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _list(tournaments.data!);
                    },
                  );
                }
                return _list(
                  catalog
                      .leagues(widget.fifaVersion)
                      .map(
                        (league) => CatalogItem(
                          'league:${league.id}',
                          league.label,
                          leagueId: league.id,
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  Widget _list(List<CatalogItem> source) {
    final items =
        source
            .where(
              (item) => item.label.toLowerCase().contains(_query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));
    if (items.isEmpty) {
      return Center(child: Text('common.noItems'.tr()));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) => ListTile(
        leading: CompetitionLogo(
          version: widget.fifaVersion,
          competitionId: items[index].id,
        ),
        title: Text(items[index].label),
        onTap: () => Navigator.pop(context, items[index]),
      ),
    );
  }
}
