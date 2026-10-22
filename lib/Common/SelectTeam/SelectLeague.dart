import '../../utils/themes.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../utils/Components/TeamLogo.dart';
import '../../utils/GameCatalog.dart';

class SelectLeaguePage extends StatefulWidget {
  const SelectLeaguePage({
    super.key,
    required this.fifaVersion,
    this.multiple = false,
    this.initialSelection = const [],
  });
  final String fifaVersion;
  final bool multiple;
  final List<String> initialSelection;

  static Future<CatalogItem?> pickOne(
    BuildContext context, {
    required String fifaVersion,
  }) => Navigator.of(context).push<CatalogItem>(
    MaterialPageRoute(
      builder: (_) => SelectLeaguePage(fifaVersion: fifaVersion),
    ),
  );

  static Future<List<CatalogItem>?> pickMany(
    BuildContext context, {
    required String fifaVersion,
    List<String> initialSelection = const [],
  }) => Navigator.of(context).push<List<CatalogItem>>(
    MaterialPageRoute(
      builder: (_) => SelectLeaguePage(
        fifaVersion: fifaVersion,
        multiple: true,
        initialSelection: initialSelection,
      ),
    ),
  );

  @override
  State<SelectLeaguePage> createState() => _SelectLeaguePageState();
}

class _SelectLeaguePageState extends State<SelectLeaguePage> {
  final Future<GameCatalog> _catalog = GameCatalog.load();
  late final Set<String> _selected = {...widget.initialSelection};
  String _query = '';

  List<CatalogItem> _leagues(GameCatalog catalog) => catalog.leagues(
    widget.fifaVersion,
  )..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

  @override
  Widget build(BuildContext context) => Theme(
    data: careerDetailTheme(context),
    child: FutureBuilder<GameCatalog>(
      future: _catalog,
      builder: (context, snapshot) {
        final catalog = snapshot.data;
        final all = catalog == null ? <CatalogItem>[] : _leagues(catalog);
        final query = _query.trim().toLowerCase();
        final leagues = all
            .where((league) => league.label.toLowerCase().contains(query))
            .toList();
        return Scaffold(
          appBar: AppBar(
            title: Text('teams.selectLeague'.tr()),
            actions: [
              if (widget.multiple)
                PopupMenuButton<String>(
                  onSelected: (value) => setState(() {
                    if (value == 'selectAll') {
                      _selected.addAll(all.map((league) => league.id));
                    } else {
                      _selected.clear();
                    }
                  }),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'selectAll',
                      child: Text('common.selectAll'.tr()),
                    ),
                    PopupMenuItem(
                      value: 'unselectAll',
                      child: Text('common.unselectAll'.tr()),
                    ),
                  ],
                ),
            ],
          ),
          floatingActionButton: widget.multiple
              ? FloatingActionButton.extended(
                  onPressed: () => Navigator.pop(
                    context,
                    all
                        .where((league) => _selected.contains(league.id))
                        .toList(),
                  ),
                  icon: const Icon(Icons.check),
                  label: Text('customConfiguration.addLeagues'.tr()),
                )
              : null,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'teams.searchLeague'.tr(),
                      prefixIcon: const Icon(Icons.search),

                      isDense: true,
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                Expanded(
                  child: snapshot.hasError
                      ? Center(child: Text('${snapshot.error}'))
                      : catalog == null
                      ? const Center(child: CircularProgressIndicator())
                      : leagues.isEmpty
                      ? Center(child: Text('common.noItems'.tr()))
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: leagues.length,
                          itemBuilder: (context, index) =>
                              _card(leagues[index]),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _card(CatalogItem league) {
    final selected = _selected.contains(league.id);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: TeamLogo.fromItem(league, size: 36),
        title: Row(
          children: [
            Flexible(
              child: Text(league.label, overflow: TextOverflow.ellipsis),
            ),
            if (league.isWoman)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.female, size: 18, color: Colors.pinkAccent),
              ),
          ],
        ),
        trailing: widget.multiple
            ? Checkbox(value: selected, onChanged: (_) => _toggle(league.id))
            : null,
        onTap: widget.multiple
            ? () => _toggle(league.id)
            : () => Navigator.pop(context, league),
      ),
    );
  }

  void _toggle(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });
}
