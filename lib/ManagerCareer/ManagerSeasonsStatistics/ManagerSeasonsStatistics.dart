import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../RootPage/DrawerWidget.dart';
import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../models/Tournament.dart';
import '../../utils/Components/TeamLogo.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/SqlService.dart';
import '../../utils/Components/CareerPageWidgets.dart';
import 'ManagerSeasonsStatisticsGrid.dart';

class ManagerSeasonsStatistics extends StatefulWidget {
  const ManagerSeasonsStatistics({super.key, required this.person});
  final Person person;

  @override
  State<ManagerSeasonsStatistics> createState() =>
      _ManagerSeasonsStatisticsState();
}

class _ManagerSeasonsStatisticsState extends State<ManagerSeasonsStatistics> {
  late final Future<
    (List<Season>, List<Map<String, Object?>>, GameCatalog, Map<String, String>)
  >
  _data = _load();
  String? _teamId;
  String? _tournamentId;

  Future<
    (List<Season>, List<Map<String, Object?>>, GameCatalog, Map<String, String>)
  >
  _load() async {
    final seasons = await SqlService.instance.getSeasons(widget.person.id);
    final fixtures = await SqlService.instance.getFixtures(
      widget.person.id,
      PersonCategory.manager,
    );
    final catalog = await GameCatalog.load();
    final tournaments = await catalog.tournaments(widget.person.fifaVersion);
    final custom = await SqlService.instance.getCustomTournaments(
      widget.person.fifaVersion,
    );
    final labels = <String, String>{
      for (final item in tournaments) item.id: item.label,
      for (final Tournament item in custom) item.id: item.name,
      for (final item in catalog.leagues(widget.person.fifaVersion))
        'league:${item.id}': item.label,
    };
    return (seasons, fixtures, catalog, labels);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: RootDrawerScope.leading(context),
      title: Text('sections.careerStatistics'.tr()),
    ),
    body:
        FutureBuilder<
          (
            List<Season>,
            List<Map<String, Object?>>,
            GameCatalog,
            Map<String, String>,
          )
        >(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final (seasons, fixtures, catalog, labels) = snapshot.data!;
            final teamIds =
                fixtures
                    .map((row) => row['playerTeamId']?.toString())
                    .whereType<String>()
                    .toSet()
                    .toList()
                  ..sort(
                    (a, b) => catalog
                        .teamLabel(widget.person.fifaVersion, a)
                        .compareTo(
                          catalog.teamLabel(widget.person.fifaVersion, b),
                        ),
                  );
            final tournamentIds =
                fixtures
                    .map((row) => row['tournamentId']?.toString())
                    .whereType<String>()
                    .toSet()
                    .toList()
                  ..sort((a, b) => (labels[a] ?? a).compareTo(labels[b] ?? b));
            final filtered = fixtures
                .where(
                  (row) =>
                      (_teamId == null || row['playerTeamId'] == _teamId) &&
                      (_tournamentId == null ||
                          row['tournamentId'] == _tournamentId),
                )
                .toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 30),
              children: [
                CareerPageHeader(
                  title: 'A carreira em números',
                  subtitle:
                      '${filtered.length} jogos · ${seasons.length} temporadas. Compare o desempenho do time ao longo dos anos.',
                  icon: Icons.query_stats_rounded,
                  eyebrow: _teamId == null
                      ? 'Todos os clubes'
                      : catalog.teamLabel(widget.person.fifaVersion, _teamId!),
                  leading: TeamLogo.lookup(
                    fifaVersion: widget.person.fifaVersion,
                    teamId: _teamId ?? widget.person.teamId,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  key: ValueKey(_teamId),
                  initialValue: _teamId,
                  decoration: InputDecoration(labelText: 'teams.team'.tr()),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('teams.allTeams'.tr()),
                    ),
                    for (final id in teamIds)
                      DropdownMenuItem<String?>(
                        value: id,
                        child: Text(
                          catalog.teamLabel(widget.person.fifaVersion, id),
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _teamId = value),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  key: ValueKey(_tournamentId),
                  initialValue: _tournamentId,
                  decoration: InputDecoration(
                    labelText: 'tournaments.tournament'.tr(),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('tournaments.allTournaments'.tr()),
                    ),
                    for (final id in tournamentIds)
                      DropdownMenuItem<String?>(
                        value: id,
                        child: Text(labels[id] ?? id),
                      ),
                  ],
                  onChanged: (value) => setState(() => _tournamentId = value),
                ),
                const SizedBox(height: 16),
                if (fixtures.isEmpty)
                  Center(child: Text('common.noItems'.tr()))
                else
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ManagerSeasonsStatisticsGrid(
                      seasons: seasons,
                      fixtures: filtered,
                    ),
                  ),
              ],
            );
          },
        ),
  );
}
