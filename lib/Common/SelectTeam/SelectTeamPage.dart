import '../../utils/themes.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../utils/Components/TeamLogo.dart';
import '../../utils/Components/CareerUiStyle.dart';
import '../../utils/Components/CareerPageWidgets.dart';
import '../../utils/Components/SelectionSearchField.dart';
import '../../utils/GameCatalog.dart';

class SelectTeamPage extends StatefulWidget {
  const SelectTeamPage({
    super.key,
    required this.fifaVersion,
    this.realTeamsOnly = false,
    this.selectedTeamId,
    this.selectedLeagueId,
    this.initialLeagueId,
  });
  final String fifaVersion;
  final bool realTeamsOnly;
  final String? selectedTeamId, selectedLeagueId, initialLeagueId;
  @override
  State<SelectTeamPage> createState() => _SelectTeamPageState();
}

class _SelectTeamPageState extends State<SelectTeamPage> {
  final Future<GameCatalog> _catalog = GameCatalog.load();
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<(CatalogItem, List<CatalogItem>)> _groups(GameCatalog catalog) {
    final version = widget.fifaVersion;
    final List<(CatalogItem, List<CatalogItem>)> groups;
    if (widget.realTeamsOnly) {
      final byLeague = <String, List<CatalogItem>>{};
      for (final team in catalog.catalogTeams(version)) {
        (byLeague[team.leagueId ?? ''] ??= []).add(team);
      }
      groups = [
        for (final league in catalog.catalogLeagues(version))
          (
            league,
            (byLeague[league.id] ?? [])..sort(
              (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
            ),
          ),
      ];
    } else {
      groups = [
        for (final entry in catalog.getAllLeagues(version))
          (entry.league, entry.teams),
      ];
    }
    final query = selectionSearchKey(_query);
    return [
      for (final (league, teams) in groups)
        (
          league,
          teams
              .where(
                (team) =>
                    selectionSearchKey(team.label).contains(query) ||
                    selectionSearchKey(league.label).contains(query),
              )
              .toList(),
        ),
    ].where((group) => group.$2.isNotEmpty).toList()..sort((a, b) {
      final first = a.$1.id == widget.initialLeagueId;
      final second = b.$1.id == widget.initialLeagueId;
      if (first != second) return first ? -1 : 1;
      return a.$1.label.toLowerCase().compareTo(b.$1.label.toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: careerDetailTheme(context),
    child: Builder(builder: _page),
  );

  Widget _page(BuildContext context) {
    final c = CareerUiColors(context);
    return Scaffold(
      appBar: AppBar(title: Text('teams.selectTeam'.tr())),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SelectionSearchField(
                key: const ValueKey('team-selection-search'),
                controller: _search,
                hint: 'teams.searchByText'.tr(),
                onChanged: (v) => setState(() => _query = v),
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
                  final groups = _groups(snapshot.data!);
                  if (groups.isEmpty) {
                    return const CareerEmptyState(
                      title: 'Nenhum time encontrado',
                      subtitle: 'Tente outro nome de clube, seleção ou liga.',
                      icon: Icons.search_off_rounded,
                    );
                  }
                  final searching = _query.trim().isNotEmpty;
                  final results = [
                    for (final (league, teams) in groups)
                      for (final team in teams) (league, team),
                  ];
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                        child: Row(
                          children: [
                            Icon(
                              searching
                                  ? Icons.search_rounded
                                  : Icons.public_rounded,
                              size: 16,
                              color: c.accent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                searching ? 'Resultados' : 'Ligas e seleções',
                                style: TextStyle(
                                  fontFamily: 'Manrope',
                                  color: c.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '${searching ? results.length : groups.length}',
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                color: c.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          key: ValueKey(
                            searching ? 'team-search-results' : 'team-leagues',
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: searching ? results.length : groups.length,
                          itemBuilder: (context, index) => searching
                              ? _teamTile(
                                  context,
                                  results[index].$1,
                                  results[index].$2,
                                )
                              : _league(context, groups[index]),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _league(BuildContext context, (CatalogItem, List<CatalogItem>) group) {
    final (league, teams) = group;
    final c = CareerUiColors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: c.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey('select-team-${league.id}'),
            initiallyExpanded: league.id == widget.initialLeagueId,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
            iconColor: c.accent,
            collapsedIconColor: c.muted,
            leading: _logo(context, league, 36),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    league.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (league.isWoman)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.female,
                      size: 18,
                      color: Colors.pinkAccent,
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              '${teams.length} equipes',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11,
                color: c.muted,
              ),
            ),
            children: [
              for (final team in teams)
                _teamTile(context, league, team, nested: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logo(BuildContext context, CatalogItem item, double size) {
    final c = CareerUiColors(context);
    return Container(
      width: size + 16,
      height: size + 16,
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(15),
      ),
      alignment: Alignment.center,
      child: TeamLogo.fromItem(item, size: size),
    );
  }

  Widget _teamTile(
    BuildContext context,
    CatalogItem league,
    CatalogItem team, {
    bool nested = false,
  }) {
    final c = CareerUiColors(context);
    final selected =
        team.id == widget.selectedTeamId &&
        (widget.selectedLeagueId == null ||
            league.id == widget.selectedLeagueId);
    return Semantics(
      selected: selected,
      child: Padding(
        padding: EdgeInsets.only(bottom: nested ? 8 : 12),
        child: Material(
          key: ValueKey('team-choice-${league.id}-${team.id}'),
          color: Color.alphaBlend(
            c.accent.withValues(
              alpha: selected
                  ? .12
                  : nested
                  ? .035
                  : 0,
            ),
            c.panel,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: selected ? c.accent.withValues(alpha: .6) : c.line,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            leading: _logo(context, team, nested ? 30 : 36),
            title: Text(
              team.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              league.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded,
              color: selected ? c.accent : c.muted.withValues(alpha: .7),
              size: 21,
            ),
            onTap: () => Navigator.pop(context, team),
          ),
        ),
      ),
    );
  }
}
