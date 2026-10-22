import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/Person.dart';
import '../utils/SqlService.dart';
import '../utils/Components/CareerPageWidgets.dart';
import '../utils/Components/CareerUiStyle.dart';
import '../RootPage/DrawerWidget.dart';

class StreaksPage extends StatelessWidget {
  const StreaksPage({super.key, required this.person, this.fixtures});
  final Person person;
  final Future<List<Map<String, Object?>>>? fixtures;

  int _longest(
    List<Map<String, Object?>> rows,
    bool Function(Map<String, Object?>) condition,
  ) {
    var best = 0;
    var current = 0;
    for (final row in rows) {
      current = condition(row) ? current + 1 : 0;
      if (current > best) best = current;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: RootDrawerScope.leading(context),
      title: Text('stats.streaks'.tr()),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future:
          fixtures ??
          SqlService.instance.getFixtures(person.id, person.category),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!.reversed.toList();
        if (rows.isEmpty) {
          return const CareerEmptyState(
            title: 'Nenhuma partida cadastrada.',
            subtitle: 'Registre jogos para descobrir as melhores sequências da carreira.',
            icon: Icons.trending_up_rounded,
          );
        }
        final home = rows.where((row) => row['location'] == 'home').toList();
        bool win(Map<String, Object?> row) =>
            (row['playerTeamScore'] as int) > (row['oppositeTeamScore'] as int);
        bool unbeaten(Map<String, Object?> row) =>
            (row['playerTeamScore'] as int) >=
            (row['oppositeTeamScore'] as int);
        bool loss(Map<String, Object?> row) =>
            (row['playerTeamScore'] as int) < (row['oppositeTeamScore'] as int);
        bool cleanSheet(Map<String, Object?> row) =>
            (row['oppositeTeamScore'] as int) == 0;
        final values = <(String, int)>[
          ('stats.longestWinStreak'.tr(), _longest(rows, win)),
          ('stats.longestLosingStreak'.tr(), _longest(rows, loss)),
          ('stats.longestUnbeatenStreak'.tr(), _longest(rows, unbeaten)),
          ('stats.longestRunWithoutConceding'.tr(), _longest(rows, cleanSheet)),
          ('stats.longestWinStreakAtHome'.tr(), _longest(home, win)),
          ('stats.longestUnbeatenStreakAtHome'.tr(), _longest(home, unbeaten)),
          (
            'stats.longestRunWithoutConcedingAtHome'.tr(),
            _longest(home, cleanSheet),
          ),
          if (person.category == PersonCategory.player) ...[
            (
              'stats.longestScoringStreak'.tr(),
              _longest(rows, (row) => (row['goalsCount'] as int) > 0),
            ),
            (
              'stats.longestAssistingStreak'.tr(),
              _longest(rows, (row) => (row['assistsCount'] as int) > 0),
            ),
          ] else
            (
              'stats.longestScoringStreak'.tr(),
              _longest(rows, (row) => (row['playerTeamScore'] as int) > 0),
            ),
        ];
        Widget group(Iterable<(String, int)> entries, IconData icon) =>
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              children: [
                for (final entry in entries)
                  CareerMetricTile(
                    label: entry.$1,
                    value: '${entry.$2}',
                    icon: icon,
                  ),
              ],
            );
        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: CareerPageHeader(
                  title: 'As marcas da carreira',
                  subtitle:
                      '${rows.length} jogos analisados. Explore suas melhores sequências.',
                  icon: Icons.trending_up_rounded,
                  eyebrow: 'Recordes e sequências',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: CareerUiColors(context).surface(radius: 16),
                  padding: const EdgeInsets.all(5),
                  child: const TabBar(
                    tabs: [
                      Tab(text: 'Geral'),
                      Tab(text: 'Em casa'),
                      Tab(text: 'Produção'),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    group(values.take(4), Icons.trending_up_rounded),
                    group(values.skip(4).take(3), Icons.home_outlined),
                    group(values.skip(7), Icons.sports_soccer_outlined),
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
