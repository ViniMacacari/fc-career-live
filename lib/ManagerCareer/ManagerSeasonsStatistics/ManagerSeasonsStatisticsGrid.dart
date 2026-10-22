import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../models/Season.dart';

class ManagerSeasonsStatisticsGrid extends StatelessWidget {
  const ManagerSeasonsStatisticsGrid({
    super.key,
    required this.seasons,
    required this.fixtures,
  });

  final List<Season> seasons;
  final List<Map<String, Object?>> fixtures;

  _SeasonStats _stats(Iterable<Map<String, Object?>> rows) {
    var matches = 0;
    var wins = 0;
    var draws = 0;
    var losses = 0;
    var goalsFor = 0;
    var goalsAgainst = 0;
    var cleanSheets = 0;
    for (final row in rows) {
      final own = (row['playerTeamScore'] as num?)?.toInt() ?? 0;
      final other = (row['oppositeTeamScore'] as num?)?.toInt() ?? 0;
      matches++;
      goalsFor += own;
      goalsAgainst += other;
      if (other == 0) cleanSheets++;
      if (own > other) {
        wins++;
      } else if (own == other) {
        draws++;
      } else {
        losses++;
      }
    }
    return _SeasonStats(
      matches,
      wins,
      draws,
      losses,
      goalsFor,
      goalsAgainst,
      cleanSheets,
    );
  }

  DataRow _row(String label, _SeasonStats stats, {bool summary = false}) {
    final style = summary ? const TextStyle(fontWeight: FontWeight.bold) : null;
    DataCell cell(String value) => DataCell(Text(value, style: style));
    final winRate = stats.matches == 0
        ? '—'
        : '${(stats.wins * 100 / stats.matches).toStringAsFixed(1)}%';
    return DataRow(
      cells: [
        cell(label),
        cell('${stats.matches}'),
        cell('${stats.wins}'),
        cell('${stats.draws}'),
        cell('${stats.losses}'),
        cell(winRate),
        cell('${stats.goalsFor}'),
        cell('${stats.goalsAgainst}'),
        cell('${stats.cleanSheets}'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bySeason = <String, List<Map<String, Object?>>>{};
    for (final row in fixtures) {
      final id = row['seasonId']?.toString();
      if (id == null) continue;
      (bySeason[id] ??= []).add(row);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(
          Theme.of(context).colorScheme.primaryContainer,
        ),
        columns: [
          DataColumn(label: Text('seasons.season'.tr())),
          DataColumn(label: Text('stats.matches'.tr()), numeric: true),
          DataColumn(label: Text('fixtures.winsFull'.tr()), numeric: true),
          DataColumn(label: Text('fixtures.drawsFull'.tr()), numeric: true),
          DataColumn(label: Text('fixtures.losesFull'.tr()), numeric: true),
          const DataColumn(label: Text('%'), numeric: true),
          DataColumn(label: Text('fixtures.goalsScored'.tr()), numeric: true),
          DataColumn(label: Text('stats.totalConcGoals'.tr()), numeric: true),
          DataColumn(label: Text('fixtures.cleanSheets'.tr()), numeric: true),
        ],
        rows: [
          for (final season in seasons)
            _row(
              '${season.startDate.year}/${season.endDate.year}',
              _stats(bySeason[season.id] ?? const []),
            ),
          _row('stats.total'.tr(), _stats(fixtures), summary: true),
        ],
      ),
    );
  }
}

class _SeasonStats {
  const _SeasonStats(
    this.matches,
    this.wins,
    this.draws,
    this.losses,
    this.goalsFor,
    this.goalsAgainst,
    this.cleanSheets,
  );
  final int matches, wins, draws, losses, goalsFor, goalsAgainst, cleanSheets;
}
