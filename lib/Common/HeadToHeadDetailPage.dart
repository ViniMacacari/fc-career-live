import '../utils/AppColors.dart';

import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../utils/themes.dart';

import '../ManagerCareer/Fixtures/ViewManagerFixturePage.dart';
import '../PlayerCareer/Fixtures/ViewPlayerFixturePage.dart';
import '../models/Person.dart';
import '../models/Tournament.dart';
import '../utils/Components/TeamLogo.dart';
import '../utils/GameCatalog.dart';
import '../utils/SqlService.dart';
import 'FixtureResultTile.dart';
import 'HeadToHeadStats.dart';
import 'HeadToHeadWidgets.dart';

class HeadToHeadDetailPage extends StatefulWidget {
  const HeadToHeadDetailPage({
    super.key,
    required this.person,
    required this.opponentId,
    this.opponentLeagueId,
    this.preloadedFixtures,
  });
  final Person person;
  final String opponentId;
  final String? opponentLeagueId;

  @visibleForTesting
  final List<Map<String, Object?>>? preloadedFixtures;

  @override
  State<HeadToHeadDetailPage> createState() => _HeadToHeadDetailPageState();
}

class _H2HData {
  const _H2HData({
    required this.stats,
    required this.catalog,
    required this.tournaments,
    required this.logos,
    required this.scorers,
  });
  final HeadToHeadStats stats;
  final GameCatalog catalog;
  final Map<String, String> tournaments, logos;

  final List<(String, int, int)> scorers;
}

class _HeadToHeadDetailPageState extends State<HeadToHeadDetailPage> {
  late Future<_H2HData> _data = _load();

  bool get _manager => widget.person.category == PersonCategory.manager;
  String get _version => widget.person.fifaVersion;

  Future<_H2HData> _load() async {
    final service = SqlService.instance;
    final preloaded = widget.preloadedFixtures;
    final fixtures =
        preloaded ??
        await service.getFixtures(widget.person.id, widget.person.category);
    final catalog = await GameCatalog.load();
    final tournaments = await catalog.tournaments(_version);
    final custom = preloaded != null
        ? const <Tournament>[]
        : await service.getCustomTournaments(_version);
    final stats = HeadToHeadStats(
      fixtures.where((f) => f['oppositeTeamId'] == widget.opponentId),
    );
    final scorers = _manager && preloaded != null
        ? <(String, int, int)>[]
        : _manager
        ? [
            for (final row in await service.getHeadToHeadScorers(
              widget.person.id,
              widget.opponentId,
            ))
              (
                '${row['name'] ?? '?'}',
                (row['goals'] as num?)?.toInt() ?? 0,
                (row['games'] as num?)?.toInt() ?? 0,
              ),
          ]
        : [
            (
              widget.person.name,
              stats.fixtures.fold<int>(
                0,
                (sum, f) => sum + ((f['goalsCount'] as num?)?.toInt() ?? 0),
              ),
              stats.games,
            ),
          ].where((s) => s.$2 > 0).toList();
    return _H2HData(
      stats: stats,
      catalog: catalog,
      tournaments: {
        for (final item in tournaments) item.id: item.label,
        for (final Tournament item in custom) item.id: item.name,
        for (final item in catalog.leagues(_version))
          'league:${item.id}': item.label,
      },
      logos: {
        for (final item in tournaments)
          if (item.assetPath != null) item.id: item.assetPath!,
      },
      scorers: scorers,
    );
  }

  String _team(_H2HData data, Object? id, Object? league) =>
      data.catalog.teamLabel(_version, '$id', leagueId: league?.toString());

  String _tournament(_H2HData data, Map<String, Object?> f) =>
      data.tournaments['${f['tournamentId']}'] ?? '${f['tournamentId']}';

  static String _score(Map<String, Object?> f) {
    final penalties = f['playerTeamPenaltiesScore'] == null
        ? ''
        : ' (pên. ${f['playerTeamPenaltiesScore']}x${f['oppositeTeamPenaltiesScore']})';
    return '${f['playerTeamScore']}x${f['oppositeTeamScore']}$penalties';
  }

  Future<void> _open(_H2HData data, Map<String, Object?> fixture) async {
    final opponent = _team(
      data,
      fixture['oppositeTeamId'],
      fixture['oppositeTeamLeagueId'],
    );
    final tournament = _tournament(data, fixture);
    final logo = data.logos['${fixture['tournamentId']}'];
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _manager
            ? ViewManagerFixturePage(
                person: widget.person,
                fixture: fixture,
                opponent: opponent,
                tournament: tournament,
                tournamentLogo: logo,
              )
            : ViewPlayerFixturePage(
                person: widget.person,
                fixture: fixture,
                opponent: opponent,
                tournament: tournament,
                tournamentLogo: logo,
              ),
      ),
    );
    if (mounted) setState(() => _data = _load());
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: careerDetailTheme(context),
    child: Scaffold(
      backgroundColor: AppColors.of(context).background,
      appBar: AppBar(
        backgroundColor: AppColors.of(context).background,
        foregroundColor: AppColors.of(context).text,
        title: Text('fixtures.headToHead'.tr()),
      ),
      body: FutureBuilder<_H2HData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                '${snapshot.error}',
                style: TextStyle(color: AppColors.of(context).text),
              ),
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final stats = data.stats;
          if (stats.games == 0) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'fixtures.headToHeadEmptyMessage'.tr(
                    namedArgs: {
                      'name': _team(
                        data,
                        widget.opponentId,
                        widget.opponentLeagueId,
                      ),
                    },
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.of(context).muted),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              _header(data),
              _goals(stats),
              H2HCard(
                title: 'Saldo de gols por jogo',
                subtitle: stats.games > _GoalDifferenceChart.maxMatches
                    ? 'Últimos ${_GoalDifferenceChart.maxMatches} jogos, do mais antigo ao mais recente. Toque numa barra para ver o jogo.'
                    : 'Do mais antigo ao mais recente. Toque numa barra para ver o jogo.',
                child: _GoalDifferenceChart(
                  fixtures: stats.fixtures
                      .take(_GoalDifferenceChart.maxMatches)
                      .toList()
                      .reversed
                      .toList(),
                  describe: (f) =>
                      '${DateFormat('dd/MM/yy').format(HeadToHeadStats.date(f))} · '
                      '${_tournament(data, f)}',
                ),
              ),
              _splits(
                'Por local',
                stats.by((f) => '${f['location']}'),
                (key) => switch (key) {
                  'home' => 'fixtures.home'.tr(),
                  'away' => 'fixtures.away'.tr(),
                  _ => 'fixtures.neutral'.tr(),
                },
              ),
              _splits(
                'Por competição',
                stats.by((f) => '${f['tournamentId']}'),
                (key) => data.tournaments[key] ?? key,
                limit: 6,
              ),
              _highlights(data),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                child: Text(
                  'Todos os jogos (${stats.games})',
                  style: TextStyle(
                    color: AppColors.of(context).text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final group in groupByConsecutiveTournament(
                stats.fixtures,
                (f) => '${f['tournamentId']}',
              ))
                FixtureTournamentCard(
                  fifaVersion: _version,
                  tournamentId: '${group.first['tournamentId']}',
                  tournamentName: _tournament(data, group.first),
                  logoAsset: data.logos['${group.first['tournamentId']}'],
                  boxedLogo: true,
                  children: [
                    for (final fixture in group)
                      FixtureResultTile(
                        fifaVersion: _version,
                        fixture: fixture,
                        trailing: H2HResultChip(fixtureResult(fixture)),
                        onTap: () => _open(data, fixture),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    ),
  );

  Widget _header(_H2HData data) {
    final stats = data.stats;
    final latest = stats.fixtures.first;
    Widget club(Object? id, Object? league) => Expanded(
      child: Column(
        children: [
          TeamLogo.lookup(
            fifaVersion: _version,
            teamId: '$id',
            leagueId: league?.toString(),
            size: 56,
          ),
          const SizedBox(height: 8),
          Text(
            _team(data, id, league),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.of(context).text, fontSize: 13),
          ),
        ],
      ),
    );
    Widget tile(int count, FixtureResult result, String label) => Expanded(
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: AppColors.of(context).text,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: h2hResultColor(result),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.of(context).muted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return H2HCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              club(latest['playerTeamId'], latest['playerTeamLeagueId']),
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Column(
                  children: [
                    Text(
                      '${stats.games}',
                      style: TextStyle(
                        color: AppColors.of(context).text,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      stats.games == 1 ? 'jogo' : 'jogos',
                      style: TextStyle(
                        color: AppColors.of(context).muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              club(widget.opponentId, latest['oppositeTeamLeagueId']),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              tile(stats.wins, FixtureResult.win, 'fixtures.winsFull'.tr()),
              tile(stats.draws, FixtureResult.draw, 'fixtures.drawsFull'.tr()),
              tile(stats.losses, FixtureResult.lose, 'fixtures.losesFull'.tr()),
            ],
          ),
          const SizedBox(height: 14),
          H2HRecordBar(
            wins: stats.wins,
            draws: stats.draws,
            losses: stats.losses,
            height: 10,
          ),
          const SizedBox(height: 8),
          Text(
            'Aproveitamento de ${(stats.pointsShare * 100).round()}% dos pontos',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.of(context).muted,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _goals(HeadToHeadStats stats) {
    String perGame(int goals) =>
        '${(goals / stats.games).toStringAsFixed(1)} por jogo';
    final difference = stats.goalsFor - stats.goalsAgainst;
    Widget tile(String value, String label, [String? detail]) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.of(context).background.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: AppColors.of(context).text,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.of(context).text,
                fontSize: 12.5,
              ),
            ),
            if (detail != null)
              Text(
                detail,
                style: TextStyle(
                  color: AppColors.of(context).muted,
                  fontSize: 11.5,
                ),
              ),
          ],
        ),
      ),
    );
    return H2HCard(
      title: 'Gols',
      child: Column(
        children: [
          Row(
            children: [
              tile(
                '${stats.goalsFor}',
                'fixtures.goalsScored'.tr(),
                perGame(stats.goalsFor),
              ),
              const SizedBox(width: 10),
              tile(
                '${stats.goalsAgainst}',
                'Gols sofridos',
                perGame(stats.goalsAgainst),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              tile(difference > 0 ? '+$difference' : '$difference', 'Saldo'),
              const SizedBox(width: 10),
              tile('${stats.cleanSheets}', 'fixtures.cleanSheets'.tr()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _splits(
    String title,
    Map<String, HeadToHeadStats> groups,
    String Function(String key) label, {
    int? limit,
  }) {
    final entries = groups.entries.toList()
      ..sort((a, b) => b.value.games.compareTo(a.value.games));
    final shown = limit == null ? entries : entries.take(limit).toList();
    return H2HCard(
      title: title,
      child: Column(
        children: [
          for (final (i, MapEntry(key: key, value: stats))
              in shown.indexed) ...[
            if (i > 0) const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    label(key),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.of(context).text,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                Text(
                  '${stats.games} ${stats.games == 1 ? 'jogo' : 'jogos'}',
                  style: TextStyle(
                    color: AppColors.of(context).muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            H2HRecordBar(
              wins: stats.wins,
              draws: stats.draws,
              losses: stats.losses,
              height: 6,
            ),
            const SizedBox(height: 6),
            H2HRecordPills(
              wins: stats.wins,
              draws: stats.draws,
              losses: stats.losses,
              fontSize: 12,
            ),
          ],
        ],
      ),
    );
  }

  Widget _highlights(_H2HData data) {
    final stats = data.stats;
    final win = stats.biggestWin, loss = stats.biggestLoss;
    final streak = stats.streak!;
    final run = switch (streak.result) {
      FixtureResult.win when streak.length >= 2 =>
        '${streak.length} vitórias seguidas',
      FixtureResult.lose when streak.length >= 2 =>
        '${streak.length} derrotas seguidas',
      FixtureResult.draw when streak.length >= 2 =>
        '${streak.length} empates seguidos',
      _ when stats.unbeaten >= 3 => 'invicto há ${stats.unbeaten} jogos',
      _ when stats.winless >= 3 => 'há ${stats.winless} jogos sem vencer',
      FixtureResult.win => 'venceu o último jogo',
      FixtureResult.lose => 'perdeu o último jogo',
      FixtureResult.draw => 'empatou o último jogo',
    };
    String match(Map<String, Object?> f) =>
        '${_score(f)} · ${DateFormat('dd/MM/yyyy').format(HeadToHeadStats.date(f))} · '
        '${_tournament(data, f)}';
    Widget line(
      IconData icon,
      String label,
      String value, {
      VoidCallback? onTap,
    }) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.of(context).muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: AppColors.of(context).muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      color: AppColors.of(context).text,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                color: AppColors.of(context).muted,
                size: 20,
              ),
          ],
        ),
      ),
    );
    return H2HCard(
      title: 'Destaques',
      child: Column(
        children: [
          line(Icons.trending_up, 'Sequência atual', run),
          if (win != null)
            line(
              Icons.emoji_events_outlined,
              'Maior vitória',
              match(win),
              onTap: () => _open(data, win),
            ),
          if (loss != null)
            line(
              Icons.trending_down,
              'Maior derrota',
              match(loss),
              onTap: () => _open(data, loss),
            ),
          if (data.scorers.isNotEmpty)
            line(
              Icons.sports_soccer,
              _manager ? 'Artilheiros no confronto' : 'Seus gols no confronto',
              [
                for (final (name, goals, games) in data.scorers)
                  '$name: $goals ${goals == 1 ? 'gol' : 'gols'} em $games ${games == 1 ? 'jogo' : 'jogos'}',
              ].join('\n'),
            ),
        ],
      ),
    );
  }
}

class _GoalDifferenceChart extends StatelessWidget {
  const _GoalDifferenceChart({required this.fixtures, required this.describe});

  static const maxMatches = 20;

  final List<Map<String, Object?>> fixtures;
  final String Function(Map<String, Object?>) describe;

  @override
  Widget build(BuildContext context) {
    final differences = [
      for (final f in fixtures) HeadToHeadStats.goalDifference(f),
    ];
    final top = math
        .max(1, differences.map((d) => d.abs()).fold(0, math.max))
        .toDouble();
    final interval = top <= 4 ? 1.0 : (top / 4).ceilToDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = ((constraints.maxWidth - 32) / fixtures.length * 0.55)
                .clamp(6.0, 18.0);
            return SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  minY: -top - 0.5,
                  maxY: top + 0.5,
                  alignment: BarChartAlignment.spaceAround,
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: 0,
                        color: AppColors.of(context).line,
                        strokeWidth: 1,
                      ),
                    ],
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    bottomTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: interval,
                        getTitlesWidget: (value, meta) {
                          if (value.abs() > top ||
                              value != value.roundToDouble()) {
                            return const SizedBox.shrink();
                          }
                          final v = value.round();
                          return SideTitleWidget(
                            meta: meta,
                            space: 6,
                            child: Text(
                              v > 0 ? '+$v' : '$v',
                              style: TextStyle(
                                color: AppColors.of(context).muted,
                                fontSize: 11,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (final (i, difference) in differences.indexed)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            fromY: difference == 0 ? -0.12 : 0,
                            toY: difference == 0 ? 0.12 : difference.toDouble(),
                            width: width,
                            color: difference > 0
                                ? h2hWin
                                : difference < 0
                                ? h2hLoss
                                : h2hDraw,
                            borderRadius: difference > 0
                                ? const BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  )
                                : difference < 0
                                ? const BorderRadius.vertical(
                                    bottom: Radius.circular(4),
                                  )
                                : BorderRadius.circular(2),
                          ),
                        ],
                      ),
                  ],
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => AppColors.of(context).background,
                      tooltipBorderRadius: BorderRadius.circular(10),
                      tooltipBorder: BorderSide(
                        color: AppColors.of(context).line,
                      ),
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      maxContentWidth: 220,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final f = fixtures[groupIndex];
                        return BarTooltipItem(
                          '${h2hResultLetter(fixtureResult(f))}  '
                          '${_HeadToHeadDetailPageState._score(f)}\n',
                          TextStyle(
                            color: AppColors.of(context).text,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          children: [
                            TextSpan(
                              text: describe(f),
                              style: TextStyle(
                                color: AppColors.of(context).muted,
                                fontWeight: FontWeight.normal,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                duration: const Duration(milliseconds: 220),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          children: [
            for (final (color, label) in [
              (h2hWin, 'Vitória (acima)'),
              (h2hDraw, 'Empate no placar'),
              (h2hLoss, 'Derrota (abaixo)'),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      color: AppColors.of(context).muted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
