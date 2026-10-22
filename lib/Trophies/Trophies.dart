import 'package:flutter/material.dart';

import '../models/Person.dart';
import '../RootPage/DrawerWidget.dart';
import '../utils/AppColors.dart';
import '../utils/Components/CareerPageWidgets.dart';
import '../utils/Components/CompactDashboardWidgets.dart';
import '../utils/Components/SelectionSearchField.dart';
import '../utils/Components/TeamLogo.dart';
import '../utils/SqlService.dart';
import '../utils/competitions/TournamentAutomation.dart';
import 'AddTrophyPage.dart';
import 'ViewTrophyPage.dart';
import 'TrophyGalleryData.dart';

class TrophiesPage extends StatefulWidget {
  const TrophiesPage({super.key, required this.person, this.sql});
  final Person person;
  final SqlService? sql;
  @override
  State<TrophiesPage> createState() => _TrophiesPageState();
}

class _TrophiesPageState extends State<TrophiesPage> {
  late Future<TrophyGalleryData> _data = _load();
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<TrophyGalleryData> _load() async {
    if (widget.sql == null) await TournamentAutomation.trySync(widget.person);
    return TrophyGalleryData.load(widget.person, sql: widget.sql);
  }

  Future<void> _create() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddTrophyPage(person: widget.person)),
    );
    if (changed == true && mounted) setState(() => _data = _load());
  }

  Future<void> _open(
    TrophyGalleryData data,
    TrophyCompetitionGroup group,
    TrophyEdition edition,
  ) async {
    final row = edition.row;
    final team = row['isNational'] == 1
        ? data.catalog.nationalities
                  .where((n) => n.id == row['teamId'])
                  .firstOrNull
                  ?.label ??
              'Seleção'
        : data.catalog.teamLabel(
            widget.person.fifaVersion,
            '${row['teamId']}',
            leagueId: row['leagueId']?.toString(),
          );
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ViewTrophyPage(
          person: widget.person,
          trophy: row,
          awardName: group.name,
          teamName: team,
          competitionId: edition.competitionId,
          sql: widget.sql,
        ),
      ),
    );
    if (changed == true && mounted) setState(() => _data = _load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: RootDrawerScope.leading(context),
      title: const Text('Troféus'),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: _create,
      tooltip: 'Adicionar troféu',
      child: const Icon(Icons.add),
    ),
    body: FutureBuilder<TrophyGalleryData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Não foi possível carregar os troféus. Abra a tela novamente para tentar carregar.',
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!, c = AppColors.of(context);
        final groups = data.groups
            .where(
              (g) =>
                  selectionSearchKey(g.name)
                      .contains(selectionSearchKey(_search.text)),
            )
            .toList();
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _data = _load());
            await _data;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              DashboardSection(
                title: 'Galeria de troféus',
                subtitle: 'Abra uma competição e escolha o ano para reviver a campanha.',
                child: CompactMetrics(
                  items: [
                    ('${data.count}', 'Conquistas'),
                    ('${data.groups.length}', 'Competições'),
                    (
                      '${{for (final g in data.groups)
                        for (final e in g.editions)
                          if (e.year != 'Ano não informado') e.year}.length}',
                      'Temporadas com títulos',
                    ),
                  ],
                ),
              ),
              if (data.groups.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SelectionSearchField(
                    controller: _search,
                    hint: 'Buscar competição',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              if (data.groups.isEmpty)
                const CareerEmptyState(
                  title: 'Sua história de conquistas começa aqui',
                  subtitle: 'Os troféus registrados e as competições vencidas aparecem nesta galeria.',
                  icon: Icons.emoji_events_outlined,
                ),
              if (groups.isEmpty && data.groups.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nenhuma competição encontrada.'),
                ),
              for (final group in groups)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    key: PageStorageKey('trophy-group-${group.id}'),
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    leading: TeamLogo(
                      imagePath: group.picture?.imagePath,
                      imageUrl: group.picture?.imageUrl,
                      localAsset: group.picture?.imageName == null
                          ? null
                          : 'assets/images/cupsLogos/${group.picture!.imageName}',
                      fallbackIcon: Icons.emoji_events_outlined,
                      width: 38,
                      height: 44,
                    ),
                    title: Text(
                      group.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      '${group.count} ${group.count == 1 ? 'vez campeão' : 'vezes campeão'} · ${group.editions.map((e) => e.year).toSet().take(3).join(', ')}',
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                    children: [
                      for (final edition in group.editions)
                        ListTile(
                          key: ValueKey('trophy-edition-${edition.row['id']}'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                          ),
                          leading: Icon(
                            Icons.emoji_events_outlined,
                            color: c.warning,
                            size: 22,
                          ),
                          title: Text(
                            edition.year,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            edition.count > 1
                                ? '${edition.count} conquistas neste registro · ver resumo'
                                : 'Ver resumo e caminho até a conquista',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _open(data, group, edition),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
