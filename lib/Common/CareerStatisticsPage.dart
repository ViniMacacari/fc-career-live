import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/Person.dart';
import '../models/Season.dart';
import '../utils/SqlService.dart';
import '../utils/Components/CareerPageWidgets.dart';
import '../RootPage/DrawerWidget.dart';

class CareerStatisticsPage extends StatefulWidget {
  const CareerStatisticsPage({super.key, required this.person});
  final Person person;
  @override
  State<CareerStatisticsPage> createState() => _CareerStatisticsPageState();
}

class _CareerStatisticsPageState extends State<CareerStatisticsPage> {
  String? _seasonId;
  late Future<(List<Season>, List<Map<String, Object?>>)> _data = _load();

  Future<(List<Season>, List<Map<String, Object?>>)> _load() async {
    final seasons = await SqlService.instance.getSeasons(widget.person.id);
    final fixtures = await SqlService.instance.getFixtures(
      widget.person.id,
      widget.person.category,
      seasonId: _seasonId,
    );
    return (seasons, fixtures);
  }

  int _sum(List<Map<String, Object?>> rows, String field) =>
      rows.fold(0, (sum, row) => sum + ((row[field] as num?)?.toInt() ?? 0));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: RootDrawerScope.leading(context),
      title: Text('sections.careerStatistics'.tr()),
    ),
    body: FutureBuilder<(List<Season>, List<Map<String, Object?>>)>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (seasons, rows) = snapshot.data!;
        final wins = rows
            .where(
              (row) =>
                  (row['playerTeamScore'] as int) >
                  (row['oppositeTeamScore'] as int),
            )
            .length;
        final draws = rows
            .where(
              (row) =>
                  (row['playerTeamScore'] as int) ==
                  (row['oppositeTeamScore'] as int),
            )
            .length;
        final losses = rows.length - wins - draws;
        final cleanSheets = rows
            .where((row) => (row['oppositeTeamScore'] as int) == 0)
            .length;
        final stats = <(String, String)>[
          ('stats.matches'.tr(), '${rows.length}'),
          ('fixtures.winsFull'.tr(), '$wins'),
          ('fixtures.drawsFull'.tr(), '$draws'),
          ('fixtures.losesFull'.tr(), '$losses'),
          ('fixtures.goalsScored'.tr(), '${_sum(rows, 'playerTeamScore')}'),
          ('stats.totalConcGoals'.tr(), '${_sum(rows, 'oppositeTeamScore')}'),
          ('fixtures.cleanSheets'.tr(), '$cleanSheets'),
          if (widget.person.category == PersonCategory.player) ...[
            ('fixtures.goals'.tr(), '${_sum(rows, 'goalsCount')}'),
            ('fixtures.assists'.tr(), '${_sum(rows, 'assistsCount')}'),
            ('fixtures.saves'.tr(), '${_sum(rows, 'savesCount')}'),
            ('fixtures.minutesPlayed'.tr(), '${_sum(rows, 'minsPlayed')}'),
            ('fixtures.yellowCards'.tr(), '${_sum(rows, 'yellowCards')}'),
            ('fixtures.redCards'.tr(), '${_sum(rows, 'redCards')}'),
          ],
        ];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CareerPageHeader(
              title: 'A carreira em números',
              subtitle: '${rows.length} partidas no período selecionado.',
              icon: Icons.query_stats_rounded,
              eyebrow: widget.person.name,
            ),
            DropdownButtonFormField<String>(
              initialValue: _seasonId,
              decoration: InputDecoration(labelText: 'seasons.season'.tr()),
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text('seasons.allSeasons'.tr()),
                ),
                ...seasons.map(
                  (season) => DropdownMenuItem(
                    value: season.id,
                    child: Text(
                      '${season.startDate.year}/${season.endDate.year}',
                    ),
                  ),
                ),
              ],
              onChanged: (value) => setState(() {
                _seasonId = value;
                _data = _load();
              }),
            ),
            const SizedBox(height: 16),
            ...stats.map(
              (entry) => CareerMetricTile(
                label: entry.$1,
                value: entry.$2,
                icon: Icons.analytics_outlined,
              ),
            ),
          ],
        );
      },
    ),
  );
}
