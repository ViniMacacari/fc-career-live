import '../../utils/AppColors.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../RootPage/DrawerWidget.dart';
import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../utils/Components/ManagerFormStyle.dart';
import '../../utils/Components/TeamLogo.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/SqlService.dart';
import '../Fixtures/ViewManagerFixturePage.dart';
import 'TeamAnalyticsCharts.dart';
import 'TeamAnalyticsData.dart';

class TeamAnalyticsSnapshot {
  const TeamAnalyticsSnapshot({
    required this.fixtures,
    this.seasons = const [],
    this.teams = const {},
    this.competitions = const {},
  });
  final List<AnalyticsRow> fixtures;
  final List<Season> seasons;
  final Map<String, CatalogItem> teams;
  final Map<String, String> competitions;

  static Future<TeamAnalyticsSnapshot> load(Person person) async {
    final sql = SqlService.instance;
    final fixtures = await sql.getFixtures(person.id, PersonCategory.manager);
    final seasons = await sql.getSeasons(person.id);
    final catalog = await GameCatalog.load();
    final tournaments = await catalog.tournaments(person.fifaVersion);
    final custom = await (await sql.database).query(
      'Tournament',
      columns: ['id', 'name'],
    );
    final teams = <String, CatalogItem>{};
    for (final row in fixtures) {
      for (final side in ['player', 'opposite']) {
        final id = row['${side}TeamId']?.toString();
        if (id == null) continue;
        teams[id] =
            catalog.team(
              person.fifaVersion,
              id,
              leagueId: row['${side}TeamLeagueId']?.toString(),
            ) ??
            CatalogItem(id, id);
      }
    }
    return TeamAnalyticsSnapshot(
      fixtures: fixtures,
      seasons: seasons,
      teams: teams,
      competitions: {
        for (final t in tournaments) t.id: t.label,
        for (final t in custom) '${t['id']}': '${t['name']}',
      },
    );
  }
}

class ManagerGraphics extends StatefulWidget {
  const ManagerGraphics({super.key, required this.person, this.load});
  final Person person;
  final Future<TeamAnalyticsSnapshot> Function(Person)? load;
  @override
  State<ManagerGraphics> createState() => _ManagerGraphicsState();
}

class _ManagerGraphicsState extends State<ManagerGraphics> {
  TeamAnalyticsSnapshot? _source;
  AnalyticsFilter _filter = const AnalyticsFilter();
  AnalyticsMetric _metric = AnalyticsMetric.form;
  AnalyticsMatch? _selected;
  bool _loading = true, _bySeason = false;
  String? _error;
  int _timelineLimit = 12;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final source = await (widget.load ?? TeamAnalyticsSnapshot.load)(
        widget.person,
      );
      if (mounted) {
        setState(() {
          _source = source;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar a análise.';
          _loading = false;
        });
      }
    }
  }

  TeamAnalytics get _data =>
      TeamAnalytics.fromRows(_source!.fixtures, filter: _filter);
  TeamAnalytics get _all => TeamAnalytics.fromRows(_source!.fixtures);
  AnalyticsColors get _c => AnalyticsColors(context);
  String _team(String id) => _source?.teams[id]?.label ?? id;
  String _competition(String id) => _source?.competitions[id] ?? id;
  String _season(String id) {
    final season = _source?.seasons.where((s) => s.id == id).firstOrNull;
    if (season != null) {
      return season.startDate.year == season.endDate.year
          ? '${season.startDate.year}'
          : '${season.startDate.year}/${season.endDate.year}';
    }
    final match = _all.matches.where((m) => m.seasonId == id).firstOrNull;
    return match == null ? id : '${match.date.year}';
  }

  String _month(String key) =>
      DateFormat('MM/yy').format(DateTime.parse('$key-01'));

  void _apply(AnalyticsFilter filter) => setState(() {
    _filter = filter;
    _selected = null;
    _timelineLimit = 12;
  });

  Future<void> _filters() async {
    if (_source == null) return;
    String? season = _filter.seasonId,
        team = _filter.teamId,
        competition = _filter.competitionId,
        location = _filter.location;
    DateTime? from = _filter.from, to = _filter.to;
    final all = _all;
    Map<String, String> options(
      String Function(AnalyticsMatch) key,
      String Function(String) label,
    ) => {for (final id in all.matches.map(key).toSet()) id: label(id)};
    final chosen = await showModalBottomSheet<AnalyticsFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) {
          final draft = AnalyticsFilter(
            seasonId: season,
            teamId: team,
            competitionId: competition,
            location: location,
            from: from,
            to: to,
          );
          Widget select(
            String label,
            String? value,
            Map<String, String> choices,
            ValueChanged<String?> changed,
          ) {
            final sorted = choices.entries.toList()
              ..sort((a, b) => a.value.compareTo(b.value));
            return DropdownButtonFormField<String>(
              key: ValueKey('$label/$value'),
              initialValue: choices.containsKey(value) ? value : '',
              isExpanded: true,
              decoration: managerFieldDecoration(context, label),
              items: [
                const DropdownMenuItem(value: '', child: Text('Todos')),
                for (final e in sorted)
                  DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) =>
                  update(() => changed(value == '' ? null : value)),
            );
          }

          return SizedBox(
            height: math.min(MediaQuery.sizeOf(context).height * .9, 760),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _c.line,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Explorar a carreira',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => update(() {
                          season = team = competition = location = null;
                          from = to = null;
                        }),
                        child: const Text('Limpar'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                    children: [
                      Text(
                        'Combine os filtros para investigar um momento do time.',
                        style: TextStyle(color: _c.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 22),
                      select(
                        'Temporada',
                        season,
                        options((m) => m.seasonId, _season),
                        (v) => season = v,
                      ),
                      const SizedBox(height: 16),
                      select(
                        'Clube / seleção',
                        team,
                        options((m) => m.teamId, _team),
                        (v) => team = v,
                      ),
                      const SizedBox(height: 16),
                      select(
                        'Competição',
                        competition,
                        options((m) => m.competitionId, _competition),
                        (v) => competition = v,
                      ),
                      const SizedBox(height: 16),
                      select('Mando de campo', location, const {
                        'home': 'Em casa',
                        'away': 'Fora de casa',
                        'neutral': 'Campo neutro',
                      }, (v) => location = v),
                      const SizedBox(height: 16),
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          final range = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2200, 12, 31),
                            initialDateRange: from == null || to == null
                                ? null
                                : DateTimeRange(start: from!, end: to!),
                            helpText: 'Período da análise',
                            saveText: 'Aplicar',
                          );
                          if (range != null) {
                            update(() {
                              from = range.start;
                              to = range.end;
                            });
                          }
                        },
                        child: InputDecorator(
                          decoration: managerFieldDecoration(
                            context,
                            'Período',
                            icon: Icons.date_range_rounded,
                            suffix: from == null
                                ? const Icon(Icons.expand_more)
                                : IconButton(
                                    tooltip: 'Limpar período',
                                    onPressed: () => update(() {
                                      from = to = null;
                                    }),
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                          ),
                          child: Text(
                            from == null
                                ? 'Toda a carreira'
                                : '${DateFormat('dd/MM/yy').format(from!)} → ${DateFormat('dd/MM/yy').format(to!)}',
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '${TeamAnalytics.fromRows(_source!.fixtures, filter: draft).played} jogos neste recorte',
                        style: TextStyle(
                          color: _c.blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, draft),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Ver análise'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (chosen != null && mounted) _apply(chosen);
  }

  Widget _hero(TeamAnalytics data) {
    final c = _c;
    final ids = data.matches.map((m) => m.teamId).toSet();
    final teamId = _filter.teamId ?? (ids.length == 1 ? ids.first : null);
    final title = teamId == null ? 'Sua carreira em campo' : _team(teamId);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.of(context).headerStart,
            AppColors.of(context).panel,
          ],
        ),
        border: Border.all(color: AppColors.of(context).line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RADAR DA CARREIRA',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.of(context).accent,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.of(context).text,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (teamId != null)
                TeamLogo.fromItem(_source!.teams[teamId], size: 48)
              else
                Icon(
                  Icons.insights_rounded,
                  color: AppColors.of(context).accent,
                  size: 38,
                ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                data.efficiency.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 48,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: AppColors.of(context).text,
                  letterSpacing: -2,
                ),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: 4, left: 4),
                child: Text(
                  '%',
                  style: TextStyle(
                    fontSize: 24,
                    color: AppColors.of(context).accent,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'de aproveitamento\nno período selecionado',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.of(context).muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(color: AppColors.of(context).line, height: 1),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${data.played} jogos',
                style: TextStyle(
                  color: AppColors.of(context).text,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              Text(
                data.played == 0
                    ? 'Seu próximo capítulo começa em campo'
                    : '${DateFormat('dd/MM/yy').format(data.matches.first.date)} — ${DateFormat('dd/MM/yy').format(data.matches.last.date)}',
                style: TextStyle(
                  color: AppColors.of(context).muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          if (data.played > 0) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Últimos 5',
                  style: TextStyle(
                    color: AppColors.of(context).muted,
                    fontSize: 11,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final m in data.recent.matches)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _result(m, c),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _result(AnalyticsMatch m, AnalyticsColors c) {
    final color = m.points == 3
        ? c.green
        : m.points == 1
        ? c.amber
        : c.red;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Text(
        m.result,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _quickFilters() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      ActionChip(
        avatar: Icon(Icons.tune_rounded, size: 17, color: _c.blue),
        label: Text(
          _filter.activeCount == 0
              ? 'Filtrar análise'
              : '${_filter.activeCount} filtros ativos',
        ),
        onPressed: _filters,
      ),
      ActionChip(
        label: const Text('Temporada atual'),
        onPressed: _all.matches.isEmpty
            ? null
            : () =>
                  _apply(AnalyticsFilter(seasonId: _all.matches.last.seasonId)),
      ),
      ActionChip(
        label: const Text('Últimos 90 dias'),
        onPressed: _all.matches.isEmpty
            ? null
            : () {
                final end = _all.matches.last.date;
                _apply(
                  AnalyticsFilter(
                    from: DateTime(
                      end.year,
                      end.month,
                      end.day,
                    ).subtract(const Duration(days: 89)),
                    to: end,
                  ),
                );
              },
      ),
      if (_filter.activeCount > 0)
        ActionChip(
          avatar: const Icon(Icons.close, size: 16),
          label: const Text('Toda a carreira'),
          onPressed: () => _apply(const AnalyticsFilter()),
        ),
    ],
  );

  Widget _stats(TeamAnalytics data) {
    final cards = [
      (
        '${data.wins}',
        'VITÓRIAS',
        '${data.draws} E · ${data.losses} D',
        Icons.emoji_events_outlined,
        _c.green,
      ),
      (
        '${data.goalsFor}',
        'GOLS MARCADOS',
        '${data.scoredPerGame.toStringAsFixed(2)} por jogo',
        Icons.sports_soccer_rounded,
        _c.blue,
      ),
      (
        '${data.goalsAgainst}',
        'GOLS SOFRIDOS',
        '${data.concededPerGame.toStringAsFixed(2)} por jogo',
        Icons.shield_outlined,
        _c.red,
      ),
      (
        '${data.balance > 0 ? '+' : ''}${data.balance}',
        'SALDO DE GOLS',
        '${data.cleanSheets} jogos sem sofrer',
        Icons.stacked_line_chart_rounded,
        _c.amber,
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth > 650 ? 4 : 2;
        final width = (box.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final card in cards)
              Container(
                width: width,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _c.panel,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _c.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(card.$4, color: card.$5, size: 20),
                        const Spacer(),
                        Text(
                          card.$1,
                          style: TextStyle(
                            fontSize: 25,
                            color: card.$5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      card.$2,
                      style: TextStyle(
                        color: _c.muted,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .6,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(card.$3, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _insights(TeamAnalytics data) {
    final delta = data.formChange;
    final notes = [
      (
        'Sequência de força',
        '${data.longestUnbeaten} jogos',
        'Maior série invicta neste recorte',
        Icons.local_fire_department_outlined,
        _c.amber,
      ),
      (
        'Momento do time',
        '${data.recent.efficiency.toStringAsFixed(0)}%',
        delta == null
            ? 'Aproveitamento nos últimos ${data.recent.played} jogos'
            : '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} p.p. ante os 5 jogos anteriores',
        delta == null || delta >= 0 ? Icons.trending_up : Icons.trending_down,
        delta == null || delta >= 0 ? _c.green : _c.red,
      ),
    ];
    return Column(
      children: [
        for (final note in notes)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: note.$5.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: note.$5.withValues(alpha: .2)),
            ),
            child: Row(
              children: [
                Icon(note.$4, color: note.$5, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.$1,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        note.$3,
                        style: TextStyle(fontSize: 10, color: _c.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  note.$2,
                  style: TextStyle(
                    color: note.$5,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _evolution(TeamAnalytics data) => AnalyticsPanel(
    title: 'O ritmo do time',
    subtitle: _metric == AnalyticsMetric.balance
        ? 'Saldo acumulado desde o início do recorte.'
        : _metric == AnalyticsMetric.possession
        ? 'Posse registrada em cada partida. Toque para explorar.'
        : 'Média móvel dos últimos 5 jogos do recorte. Toque para explorar.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final metric in AnalyticsMetric.values)
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: ChoiceChip(
                    label: Text(
                      metric.label,
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: _metric == metric,
                    onSelected: (_) => setState(() {
                      _metric = metric;
                      _selected = null;
                    }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AnalyticsEvolutionChart(
          data: data,
          metric: _metric,
          onSelected: (m) => setState(() => _selected = m),
        ),
        if (_selected case final match?) ...[
          const SizedBox(height: 14),
          _matchTile(match, compact: true),
        ],
      ],
    ),
  );

  Widget _technical(TeamAnalytics data) => AnalyticsPanel(
    title: 'A identidade em campo',
    subtitle:
        'Médias calculadas apenas nos jogos com a estatística preenchida.',
    child: LayoutBuilder(
      builder: (context, box) {
        final measures = [
          (
            'Posse',
            data.mean((m) => m.possession),
            data.samples((m) => m.possession),
            '%',
            _c.blue,
          ),
          (
            'Passes certos',
            data.mean((m) => m.accuracy),
            data.samples((m) => m.accuracy),
            '%',
            _c.green,
          ),
          (
            'Finalizações',
            data.mean((m) => m.shots),
            data.samples((m) => m.shots),
            '',
            _c.amber,
          ),
        ];
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final measure in measures)
              SizedBox(
                width: (box.maxWidth - 20) / 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      measure.$1,
                      style: TextStyle(fontSize: 10, color: _c.muted),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      measure.$2 == null
                          ? '—'
                          : '${measure.$2!.toStringAsFixed(1)}${measure.$4}',
                      style: TextStyle(
                        color: measure.$5,
                        fontWeight: FontWeight.w800,
                        fontSize: 21,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      measure.$3 == 0 ? 'Sem registros' : '${measure.$3} jogos',
                      style: TextStyle(fontSize: 10, color: _c.muted),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _seasonComparison(TeamAnalytics data) => AnalyticsPanel(
    title: 'Capítulos da carreira',
    subtitle: 'Aproveitamento por temporada dentro dos filtros atuais.',
    child: Column(
      children: [
        AnalyticsBars(groups: data.seasons, label: _season),
        const SizedBox(height: 16),
        for (final entry in data.seasons.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _c.blue,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _season(entry.key),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${entry.value.played} J · ${entry.value.wins} V · ${entry.value.draws} E · ${entry.value.losses} D',
                        style: TextStyle(color: _c.muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${entry.value.efficiency.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: _c.blue,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  String _location(String value) => switch (value) {
    'home' => 'Casa',
    'away' => 'Fora',
    _ => 'Neutro',
  };

  Widget _matchTile(AnalyticsMatch m, {bool compact = false}) {
    final opponent = _team('${m.row['oppositeTeamId']}');
    final penalties = m.row['playerTeamPenaltiesScore'] == null
        ? ''
        : ' · pên. ${m.row['playerTeamPenaltiesScore']}–${m.row['oppositeTeamPenaltiesScore']}';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => ViewManagerFixturePage(
              person: widget.person,
              fixture: m.row,
              opponent: opponent,
              tournament: _competition(m.competitionId),
            ),
          ),
        );
        if (mounted) _load();
      },
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 4 : 12),
        child: Row(
          children: [
            _result(m, _c),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    opponent,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${DateFormat('dd/MM/yy').format(m.date)} · ${_location(m.location)} · ${_competition(m.competitionId)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: _c.muted),
                  ),
                  if (!compact && _filter.teamId == null)
                    Text(
                      _team(m.teamId),
                      style: TextStyle(fontSize: 10, color: _c.blue),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${m.scored} – ${m.conceded}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (penalties.isNotEmpty)
                  Text(
                    penalties,
                    style: TextStyle(fontSize: 9, color: _c.muted),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeline(TeamAnalytics data) {
    final matches = data.matches.reversed.take(_timelineLimit).toList();
    return AnalyticsPanel(
      title: 'Linha do tempo',
      subtitle: 'Do jogo mais recente ao primeiro. Abra uma partida para ver os detalhes.',
      child: Column(
        children: [
          for (var i = 0; i < matches.length; i++) ...[
            if (i == 0 || matches[i].seasonId != matches[i - 1].seasonId)
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.flag_outlined, size: 15, color: _c.blue),
                    const SizedBox(width: 7),
                    Text(
                      'TEMPORADA ${_season(matches[i].seasonId)}',
                      style: TextStyle(
                        color: _c.blue,
                        fontSize: 10,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            _matchTile(matches[i]),
            if (i < matches.length - 1) Divider(color: _c.line, height: 1),
          ],
          if (data.played > _timelineLimit)
            TextButton.icon(
              onPressed: () => setState(() => _timelineLimit += 20),
              icon: const Icon(Icons.expand_more),
              label: Text('Ver mais jogos (${data.played - _timelineLimit})'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: RootDrawerScope.leading(context),
      title: const Text('Análise do time'),
      actions: [
        IconButton(
          tooltip: 'Filtros',
          onPressed: _source == null ? null : _filters,
          icon: const Icon(Icons.tune_rounded),
        ),
        IconButton(
          tooltip: 'Atualizar análise',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                TextButton(
                  onPressed: _load,
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: LayoutBuilder(
              builder: (context, box) {
                final data = _data;
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    math.max(16, (box.maxWidth - 1000) / 2),
                    8,
                    math.max(16, (box.maxWidth - 1000) / 2),
                    32,
                  ),
                  children: [
                    _hero(data),
                    const SizedBox(height: 16),
                    _quickFilters(),
                    if (_filter.activeCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (_filter.seasonId != null)
                              Text(
                                'Temporada ${_season(_filter.seasonId!)}',
                                style: TextStyle(color: _c.blue, fontSize: 11),
                              ),
                            if (_filter.teamId != null)
                              Text(
                                _team(_filter.teamId!),
                                style: TextStyle(color: _c.blue, fontSize: 11),
                              ),
                            if (_filter.competitionId != null)
                              Text(
                                _competition(_filter.competitionId!),
                                style: TextStyle(color: _c.blue, fontSize: 11),
                              ),
                            if (_filter.location != null)
                              Text(
                                _location(_filter.location!),
                                style: TextStyle(color: _c.blue, fontSize: 11),
                              ),
                            if (_filter.from != null)
                              Text(
                                '${DateFormat('dd/MM/yy').format(_filter.from!)} → ${DateFormat('dd/MM/yy').format(_filter.to!)}',
                                style: TextStyle(color: _c.blue, fontSize: 11),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 18),
                    if (data.played == 0)
                      AnalyticsPanel(
                        title: _all.played == 0
                            ? 'A história começa no próximo jogo'
                            : 'Nenhum jogo neste recorte',
                        subtitle: _all.played == 0
                            ? 'Registre partidas para revelar tendências, comparar temporadas e explorar a evolução do time.'
                            : 'Ajuste os filtros para encontrar outra fase da carreira.',
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Icon(
                              Icons.stacked_line_chart_rounded,
                              size: 64,
                              color: _c.blue,
                            ),
                          ),
                        ),
                      )
                    else ...[
                      _stats(data),
                      const SizedBox(height: 16),
                      _insights(data),
                      const SizedBox(height: 8),
                      _evolution(data),
                      const SizedBox(height: 16),
                      AnalyticsPanel(
                        title: 'Como os jogos terminaram',
                        subtitle: 'Resultados pelo placar antes dos pênaltis.',
                        child: AnalyticsResultsChart(data: data),
                      ),
                      const SizedBox(height: 16),
                      AnalyticsPanel(
                        title: 'Ataque × defesa',
                        subtitle: 'Gols por jogo. Compare a produção e o que o time concede.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              children: [
                                ChoiceChip(
                                  label: const Text('Por mês'),
                                  selected: !_bySeason,
                                  onSelected: (_) =>
                                      setState(() => _bySeason = false),
                                ),
                                ChoiceChip(
                                  label: const Text('Por temporada'),
                                  selected: _bySeason,
                                  onSelected: (_) =>
                                      setState(() => _bySeason = true),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            AnalyticsBars(
                              groups: _bySeason ? data.seasons : data.months,
                              label: _bySeason ? _season : _month,
                              goals: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      AnalyticsPanel(
                        title: 'O peso do mando',
                        subtitle:
                            'Aproveitamento em casa, fora e em campo neutro.',
                        child: AnalyticsBars(
                          groups: data.groupBy((m) => m.location),
                          label: _location,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _technical(data),
                      const SizedBox(height: 16),
                      _seasonComparison(data),
                      const SizedBox(height: 16),
                      _timeline(data),
                      const SizedBox(height: 18),
                      Text(
                        'Aproveitamento = (3 × vitórias + empates) ÷ (3 × jogos). Os filtros se aplicam a todos os gráficos e à linha do tempo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _c.muted,
                          fontSize: 10,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
  );
}
