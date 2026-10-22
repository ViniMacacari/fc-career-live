import 'package:flutter/material.dart';

import '../../RootPage/DrawerWidget.dart';
import '../../models/Person.dart';
import '../../utils/AppColors.dart';
import '../../utils/Components/PlayerAvatar.dart';
import '../../utils/Components/SelectionSearchField.dart';
import '../../utils/SqlService.dart';
import '../../utils/databaseUtils.dart';
import 'PlayerActivityPage.dart';
import 'PlayerStatWidgets.dart';
import 'PlayersStatData.dart';
import 'PlayersStatPageFilterModal.dart';
import 'PlayersStatPageSortModal.dart';
import 'RecordedPlayerStats.dart';

class PlayersStatPage extends StatefulWidget {
  const PlayersStatPage({
    super.key,
    required this.person,
    this.sql,
    this.initialData,
  });
  final Person person;
  final SqlService? sql;
  final Future<PlayersStatData>? initialData;
  @override
  State<PlayersStatPage> createState() => _PlayersStatPageState();
}

class _PlayersStatPageState extends State<PlayersStatPage> {
  late Future<PlayersStatData> _data =
      widget.initialData ??
      PlayersStatData.load(widget.person, sql: widget.sql);
  PlayersStatFilters _filters = const PlayersStatFilters();
  PlayersStatSort _sort = const PlayersStatSort();
  PlayersStatGroup _group = PlayersStatGroup.summary;
  bool _initialized = false;
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static List<PlayersStatMetric> _columns(PlayersStatGroup group) =>
      switch (group) {
        PlayersStatGroup.summary => [
          PlayersStatMetric.matches,
          PlayersStatMetric.goals,
          PlayersStatMetric.assists,
          PlayersStatMetric.rating,
        ],
        PlayersStatGroup.shooting => [
          PlayersStatMetric.goals,
          PlayersStatMetric.shots,
          PlayersStatMetric.shotAccuracy,
          PlayersStatMetric.penalties,
        ],
        PlayersStatGroup.teamwork => [
          PlayersStatMetric.assists,
          PlayersStatMetric.keyPasses,
          PlayersStatMetric.passes,
          PlayersStatMetric.passAccuracy,
        ],
        PlayersStatGroup.defense => [
          PlayersStatMetric.tackles,
          PlayersStatMetric.saves,
          PlayersStatMetric.yellowCards,
          PlayersStatMetric.redCards,
        ],
      };

  static String _heading(PlayersStatMetric metric) => switch (metric) {
    PlayersStatMetric.assists => 'Assist.',
    PlayersStatMetric.rating => 'Nota',
    PlayersStatMetric.shots => 'Chutes',
    PlayersStatMetric.shotAccuracy => 'No alvo',
    PlayersStatMetric.penalties => 'Pênaltis',
    PlayersStatMetric.keyPasses => 'Chave',
    PlayersStatMetric.passAccuracy => 'Precisão',
    _ => metric.title,
  };

  static String _cell(PlayersStatMetric metric, num? value) => value == null
      ? '–'
      : metric.percentage
      ? '${value.round()}%'
      : metric.format(value).replaceAll('.', ',');

  Future<void> _quickFilter(String field, PlayersStatData data) async {
    final (title, options, current) = switch (field) {
      'season' => (
        'Temporada',
        playersStatSeasonOptions(data),
        _filters.seasonId,
      ),
      'tournament' => (
        'Competição',
        playersStatTournamentOptions(data),
        _filters.tournamentId,
      ),
      _ => (
        'Time',
        playersStatTeamOptions(data, widget.person),
        _filters.teamId,
      ),
    };
    final selected = await choosePlayersStatFilter(
      context,
      title,
      options,
      current,
    );
    if (mounted && selected != null) {
      setState(
        () => _filters = PlayersStatFilters(
          seasonId: field == 'season' ? selected.id : _filters.seasonId,
          tournamentId: field == 'tournament'
              ? selected.id
              : _filters.tournamentId,
          teamId: field == 'team' ? selected.id : _filters.teamId,
        ),
      );
    }
  }

  void _sortBy(PlayersStatMetric metric) => setState(
    () => _sort = PlayersStatSort(
      metric: metric,
      descending: _sort.metric != metric || !_sort.descending,
    ),
  );

  Future<void> _open(PlayersStatData data, PlayersStatEntry entry) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerActivityPage(
          person: widget.person,
          data: data,
          entry: entry,
          filters: _filters,
          sql: widget.sql,
        ),
      ),
    );
    if (mounted && widget.initialData == null) {
      setState(
        () => _data = PlayersStatData.load(widget.person, sql: widget.sql),
      );
    }
  }

  Widget _filterPill(String label, VoidCallback onTap) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: c.panel,
        shape: StadiumBorder(side: BorderSide(color: c.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.expand_more_rounded, size: 18, color: c.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _groups() {
    final c = AppColors.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.raised.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final group in PlayersStatGroup.values)
            Expanded(
              child: GestureDetector(
                key: ValueKey('stat-group-${group.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _group = group),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _group == group ? c.panel : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    border: _group == group ? Border.all(color: c.line) : null,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      switch (group) {
                        PlayersStatGroup.shooting => 'Ataque',
                        PlayersStatGroup.teamwork => 'Criação',
                        _ => group.label,
                      },
                      style: TextStyle(
                        color: _group == group ? c.accent : c.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(int count, List<PlayersStatMetric> columns, double width) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == 1 ? '1 jogador' : '$count jogadores',
              style: TextStyle(color: c.muted, fontSize: 11),
            ),
          ),
          for (final metric in columns)
            SizedBox(
              width: width,
              child: Tooltip(
                message: 'Ordenar por ${metric.title.toLowerCase()}',
                child: InkWell(
                  key: ValueKey('stat-column-${metric.name}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _sortBy(metric),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 16,
                          child:
                              metric == PlayersStatMetric.yellowCards ||
                                  metric == PlayersStatMetric.redCards
                              ? PlayerMetricIcon(metric, size: 15)
                              : FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _heading(metric),
                                    style: TextStyle(
                                      color: _sort.metric == metric
                                          ? c.accent
                                          : c.muted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                        ),
                        Icon(
                          _sort.descending
                              ? Icons.arrow_drop_down_rounded
                              : Icons.arrow_drop_up_rounded,
                          size: 16,
                          color: _sort.metric == metric
                              ? c.accent
                              : Colors.transparent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(
    PlayersStatData data,
    PlayersStatEntry e,
    RecordedPlayerStats s,
    List<PlayersStatMetric> columns,
    double width,
  ) {
    final c = AppColors.of(context);
    final detail = [
      positionShortName(e.player['positionId']?.toString()),
      if (e.departed) 'Saiu do clube',
      if (e.destinationId != null)
        data.catalog.teamLabel(widget.person.fifaVersion, e.destinationId!),
    ].where((v) => v.isNotEmpty).join(' · ');
    return InkWell(
      key: ValueKey('player-stat-${e.id}'),
      onTap: () => _open(data, e),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Opacity(
              opacity: e.departed ? .55 : 1,
              child: PlayerAvatar(
                fifaVersion: widget.person.fifaVersion,
                realPlayerId: e.player['realPlayerId']?.toString(),
                customAvatarFilePath: e.player['customAvatarFilePath']
                    ?.toString(),
                radius: 17,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: e.departed ? c.muted : c.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.muted, fontSize: 11),
                    ),
                ],
              ),
            ),
            for (final metric in columns)
              SizedBox(
                width: width,
                child: Center(
                  child: metric == PlayersStatMetric.rating && s[metric] != null
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          child: RatingPill(s[metric], size: 12),
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _cell(metric, s[metric]),
                            maxLines: 1,
                            style: TextStyle(
                              color: s[metric] == null
                                  ? c.muted
                                  : _sort.metric == metric
                                  ? c.accent
                                  : c.text,
                              fontSize: 14,
                              fontWeight: _sort.metric == metric
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PlayersStatData>(
    future: _data,
    builder: (context, snapshot) {
      final c = AppColors.of(context), data = snapshot.data;
      if (data != null && !_initialized) {
        _initialized = true;
        _filters = PlayersStatFilters(
          seasonId: data.seasons.firstOrNull?.id,
          teamId: widget.person.teamId,
        );
      }
      final entries =
          data
              ?.entries(widget.person, _filters, _sort)
              .where(
                (e) =>
                    selectionSearchKey(e.name)
                        .contains(selectionSearchKey(_search.text)),
              )
              .toList() ??
          [];
      final activity = data?.activities(_filters) ?? const {};
      final stats = <String, RecordedPlayerStats>{
        for (final entry in entries)
          entry.id: RecordedPlayerStats(activity[entry.id] ?? []),
      };
      if (_sort.metric != null) {
        entries.sort((a, b) {
          if (a.departed != b.departed) return a.departed ? 1 : -1;
          final av = stats[a.id]![_sort.metric!],
              bv = stats[b.id]![_sort.metric!];
          if (av == null || bv == null) {
            return av == bv
                ? a.name.compareTo(b.name)
                : av == null
                ? 1
                : -1;
          }
          final result = av.compareTo(bv);
          return result == 0
              ? a.name.compareTo(b.name)
              : _sort.descending
              ? -result
              : result;
        });
      }
      final columns = _columns(_group);
      final hiddenSort =
          _sort.metric != null && !columns.contains(_sort.metric);
      return Scaffold(
        appBar: AppBar(
          leading: RootDrawerScope.leading(context),
          title: const Text('Estatísticas', style: TextStyle(fontSize: 17)),
          actions: [
            IconButton(
              tooltip: 'Ordenar jogadores',
              icon: const Icon(Icons.sort_rounded),
              onPressed: () async {
                final selected = await showPlayersStatSort(context, _sort);
                if (mounted && selected != null) {
                  setState(() => _sort = selected);
                }
              },
            ),
          ],
        ),
        body: snapshot.hasError
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Não foi possível carregar as estatísticas. Abra a tela novamente para tentar carregar.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : data == null
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                      child: SelectionSearchField(
                        controller: _search,
                        hint: 'Buscar jogador',
                        dense: true,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          for (final (key, options, id) in [
                            (
                              'season',
                              playersStatSeasonOptions(data),
                              _filters.seasonId,
                            ),
                            (
                              'tournament',
                              playersStatTournamentOptions(data),
                              _filters.tournamentId,
                            ),
                            (
                              'team',
                              playersStatTeamOptions(data, widget.person),
                              _filters.teamId,
                            ),
                          ])
                            _filterPill(
                              playersStatFilterLabel(options, id),
                              () => _quickFilter(key, data),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                      child: _groups(),
                    ),
                    if (hiddenSort)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: InputChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              'Ordenado por ${_sort.metric!.title.toLowerCase()} · ${_sort.descending ? 'maiores' : 'menores'}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            onDeleted: () =>
                                setState(() => _sort = const PlayersStatSort()),
                          ),
                        ),
                      ),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Material(
                          color: c.panel,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: c.line),
                          ),
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final scale =
                                  MediaQuery.textScalerOf(context).scale(12) /
                                  12;
                              final width =
                                  ((box.maxWidth - 24 - 44 - 90 * scale) /
                                          columns.length)
                                      .clamp(34.0, 56.0 * scale);
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _header(entries.length, columns, width),
                                  Divider(height: 1, color: c.line),
                                  Flexible(
                                    child: entries.isEmpty
                                        ? Padding(
                                            padding: const EdgeInsets.all(32),
                                            child: Text(
                                              'Nenhum jogador neste recorte.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(color: c.muted),
                                            ),
                                          )
                                        : ListView.separated(
                                            shrinkWrap: true,
                                            padding: const EdgeInsets.only(
                                              bottom: 4,
                                            ),
                                            itemCount: entries.length,
                                            separatorBuilder: (_, _) => Divider(
                                              height: 1,
                                              indent: 58,
                                              color: c.line.withValues(
                                                alpha: .5,
                                              ),
                                            ),
                                            itemBuilder: (context, index) {
                                              final e = entries[index];
                                              return _row(
                                                data,
                                                e,
                                                stats[e.id]!,
                                                columns,
                                                width,
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      );
    },
  );
}
