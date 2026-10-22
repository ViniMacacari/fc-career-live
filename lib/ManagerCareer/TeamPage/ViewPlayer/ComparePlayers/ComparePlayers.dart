import '../../../../utils/AppColors.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../models/ManagerFixturePlayerPerformance.dart';
import '../../../../models/Person.dart';
import '../../../../models/Season.dart';
import '../../../../utils/ManagerStatService.dart';
import '../../../../utils/GamePlayers.dart';
import '../../../../utils/SqlService.dart';
import '../../../../utils/databaseUtils.dart';
import '../../../Fixtures/SelectTeamPlayerPage.dart';
import '../PlayerProfileData.dart';
import '../PlayerAnalysis.dart';
import '../PlayerProfileVisuals.dart';
import '../../../../Common/MatchUi.dart';
import 'ComparisonCharts.dart';

class ComparePlayersPage extends StatefulWidget {
  const ComparePlayersPage({
    super.key,
    required this.person,
    required this.initialPlayer,
    this.initialSeasonId,
    this.sql,
  });
  final Person person;
  final Map<String, Object?> initialPlayer;
  final String? initialSeasonId;
  @visibleForTesting
  final SqlService? sql;

  @override
  State<ComparePlayersPage> createState() => _ComparePlayersPageState();
}

class _ComparePlayersPageState extends State<ComparePlayersPage> {
  SqlService get _sql => widget.sql ?? SqlService.instance;
  late Future<void> _initialization;
  List<Season> _seasons = [];
  List<_ComparisonPlayer> _players = [];
  final _profiles = <String, Future<PlayerProfileData>>{};

  List<_PlayerSelection> _selections = [];

  String? _pendingSeasonId;
  Future<List<_SeasonSnapshot>>? _comparison;
  final _collapsed = <String>{};
  String _trendMetric = 'Nota média';

  bool _per90 = false;

  bool _cumulative = false;

  _ComparisonPeriod _period = const _ComparisonPeriod.full();

  DateTime? _latestFixture;

  static const _rowLine = BoxDecoration(
    border: Border(top: BorderSide(color: AppColors.subtleOverlay)),
  );

  @override
  void initState() {
    super.initState();
    _initialization = _load();
  }

  Future<void> _load() async {
    final db = _sql;
    final rowsTask = db.getComparisonPlayerRows(widget.person.id);
    final seasonsTask = db.getSeasons(widget.person.id);
    final latestTask = db.getLatestFixtureDate(widget.person.id);
    final rows = await rowsTask;
    final seasons = await seasonsTask;
    final realIndex = await GamePlayers.lookup(
      widget.person.fifaVersion,
      rows.map((row) => row['realPlayerId']).whereType<String>(),
    );
    _latestFixture = await latestTask;
    final groups = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      groups.putIfAbsent(row['playerId'].toString(), () => []).add(row);
    }
    final initialId = widget.initialPlayer['playerId']?.toString();
    if (initialId != null && !groups.containsKey(initialId)) {
      groups[initialId] = [widget.initialPlayer];
    }
    _seasons = [...seasons]..sort((a, b) => b.startDate.compareTo(a.startDate));
    _players = [
      for (final entry in groups.entries)
        _ComparisonPlayer(
          entry.key,
          entry.value,
          realIndex[entry.value.first['realPlayerId']?.toString()],
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final seasonId = _seasons.any((s) => s.id == widget.initialSeasonId)
        ? widget.initialSeasonId
        : _seasons.firstOrNull?.id;
    final initial = _players.where((p) => p.id == initialId).firstOrNull;
    _selections = [if (initial != null) _PlayerSelection(initial, seasonId, 0)];
    _pendingSeasonId = seasonId;
    _comparison = _resolve();
  }

  Future<List<_SeasonSnapshot>> _resolve() =>
      Future.wait([for (final selection in _selections) _snapshot(selection)]);

  Future<_SeasonSnapshot> _snapshot(_PlayerSelection selection) async {
    final player = selection.player;
    final data = await _profiles.putIfAbsent(
      player.id,
      () => PlayerProfileData.load(widget.person, player.id, sql: _sql),
    );
    final season = _seasons
        .where((s) => s.id == selection.seasonId)
        .firstOrNull;
    final window = season == null ? null : _period.window(season);
    return _SeasonSnapshot(
      widget.person,
      player,
      data,
      season,
      slot: selection.slot,
      from: window?.$1,
      to: window?.$2,
    );
  }

  void _update(VoidCallback change) => setState(() {
    change();
    _comparison = _resolve();
  });

  int get _freeSlot => List.generate(
    comparisonMaxPlayers,
    (slot) => slot,
  ).firstWhere((slot) => _selections.every((s) => s.slot != slot));

  Future<List<_ComparisonPlayer>> _pick(
    String? seasonId, {
    required bool multiple,
    _PlayerSelection? replacing,
  }) async {
    final roster = <Map<String, Object?>>[
      if (seasonId != null)
        for (final player in _players)
          ?player.rows.where((row) => row['seasonId'] == seasonId).firstOrNull,
    ];
    if (!mounted) return const [];
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectTeamPlayerPage(
          fifaVersion: widget.person.fifaVersion,
          roster: roster,
          names: {for (final p in _players) p.id: p.name},
          positions: {for (final p in _players) p.id: p.position},
          multiple: multiple,
          usedIds: {
            for (final s in _selections)
              if (s.seasonId == seasonId && s != replacing) s.player.id,
          },
          seasonStats: seasonId == null
              ? null
              : _sql.getManagerPlayerStatistics(
                  widget.person.id,
                  seasonId: seasonId,
                ),
        ),
      ),
    );
    final picked = switch (result) {
      final SelectedTeamPlayer player => [player],
      final List<SelectedTeamPlayer> players => players,
      _ => const <SelectedTeamPlayer>[],
    };
    return [
      for (final p in picked) ?_players.where((c) => c.id == p.id).firstOrNull,
    ];
  }

  Future<void> _addPlayers() async {
    final seasonId = _pendingSeasonId;
    final picked = await _pick(seasonId, multiple: true);
    if (picked.isEmpty || !mounted) return;
    final room = comparisonMaxPlayers - _selections.length;
    if (picked.length > room) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A comparação vai até $comparisonMaxPlayers jogadores; '
            '${picked.length - room} ficaram de fora.',
          ),
        ),
      );
    }
    _update(() {
      for (final player in picked.take(room)) {
        _selections.add(_PlayerSelection(player, seasonId, _freeSlot));
      }
    });
  }

  Future<void> _replacePlayer(_PlayerSelection current) async {
    final picked = await _pick(
      current.seasonId,
      multiple: false,
      replacing: current,
    );
    final index = _selections.indexOf(current);
    if (picked.isEmpty || index < 0 || !mounted) return;
    _update(
      () => _selections[index] = _PlayerSelection(
        picked.first,
        current.seasonId,
        current.slot,
      ),
    );
  }

  List<Season> get _comparedSeasons => [
    for (final season in _seasons)
      if (_selections.any((s) => s.seasonId == season.id)) season,
  ];

  DateTime _defaultCut(Season reference) {
    final latest = _latestFixture;
    if (latest != null &&
        !latest.isBefore(reference.startDate) &&
        !latest.isAfter(reference.endDate)) {
      return DateTime(latest.year, latest.month, latest.day);
    }
    return reference.endDate;
  }

  int _seasonMonths(Season season) =>
      (season.endDate.year - season.startDate.year) * 12 +
      season.endDate.month -
      season.startDate.month;

  String _untilLabel(DateTime cut, Season reference, List<Season> seasons) =>
      seasons.every((s) => _sameStart(s.startDate, reference.startDate))
      ? "Até ${DateFormat("d 'de' MMM", 'pt_BR').format(cut)} de cada temporada"
      : 'Primeiros ${cut.difference(reference.startDate).inDays + 1} dias de cada temporada';

  String _periodLabel() {
    final period = _period;
    final seasons = _comparedSeasons;
    return switch (period.kind) {
      _PeriodKind.full => 'Temporada inteira',
      _PeriodKind.until => _untilLabel(period.cut!, period.reference!, seasons),
      _PeriodKind.months =>
        '${_monthNames(seasons)(period.firstMonth!)} a ${_monthNames(seasons)(period.lastMonth!)} de cada temporada',
    };
  }

  Future<void> _choosePeriod() async {
    final compared = _comparedSeasons;
    final reference =
        compared.firstOrNull ??
        _seasons.where((s) => s.id == _pendingSeasonId).firstOrNull;
    if (reference == null) return;
    final seasons = compared.isEmpty ? [reference] : compared;
    final lastMonth = seasons.map(_seasonMonths).reduce(math.max);
    final monthName = _monthNames(seasons);
    var kind = _period.kind;
    final cutReference = _period.reference ?? reference;
    var cut = _period.cut ?? _defaultCut(cutReference);
    var months = RangeValues(
      (_period.firstMonth ?? 0).clamp(0, lastMonth).toDouble(),
      (_period.lastMonth ?? lastMonth).clamp(0, lastMonth).toDouble(),
    );
    final result = await showModalBottomSheet<_ComparisonPeriod>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          Widget option(
            _PeriodKind value,
            String title,
            String subtitle, {
            Widget? trailing,
          }) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              kind == value
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: kind == value
                  ? AppColors.of(context).accent
                  : AppColors.of(context).muted,
            ),
            title: Text(
              title,
              style: TextStyle(color: AppColors.of(context).text),
            ),
            subtitle: Text(
              subtitle,
              style: TextStyle(
                color: AppColors.of(context).muted,
                fontSize: 12,
              ),
            ),
            trailing: trailing,
            onTap: () => setSheet(() => kind = value),
          );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Período da comparação',
                    style: TextStyle(
                      color: AppColors.of(context).text,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vale para todos os jogadores, contado a partir do início de cada temporada.',
                    style: TextStyle(
                      color: AppColors.of(context).muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  option(
                    _PeriodKind.full,
                    'Temporada inteira',
                    'Todos os jogos de cada temporada',
                  ),
                  option(
                    _PeriodKind.until,
                    'Até o mesmo ponto',
                    _untilLabel(cut, cutReference, seasons),
                    trailing: TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: cut.isBefore(cutReference.startDate)
                              ? cutReference.startDate
                              : cut.isAfter(cutReference.endDate)
                              ? cutReference.endDate
                              : cut,
                          firstDate: cutReference.startDate,
                          lastDate: cutReference.endDate,
                          helpText:
                              'Até qual dia de ${cutReference.startDate.year} - ${cutReference.endDate.year}?',
                        );
                        if (picked == null) return;
                        setSheet(() {
                          cut = picked;
                          kind = _PeriodKind.until;
                        });
                      },
                      child: const Text('Alterar'),
                    ),
                  ),
                  option(
                    _PeriodKind.months,
                    'Intervalo de meses',
                    '${monthName(months.start.round())} a ${monthName(months.end.round())} de cada temporada',
                  ),
                  if (kind == _PeriodKind.months && lastMonth > 0)
                    RangeSlider(
                      values: months,
                      max: lastMonth.toDouble(),
                      divisions: lastMonth,
                      labels: RangeLabels(
                        monthName(months.start.round()),
                        monthName(months.end.round()),
                      ),
                      onChanged: (value) => setSheet(() => months = value),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, switch (kind) {
                      _PeriodKind.full => const _ComparisonPeriod.full(),
                      _PeriodKind.until => _ComparisonPeriod.until(
                        cut,
                        cutReference,
                      ),
                      _PeriodKind.months => _ComparisonPeriod.months(
                        months.start.round(),
                        months.end.round(),
                      ),
                    }),
                    child: const Text('Aplicar'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result == null || !mounted) return;
    _update(() => _period = result);
  }

  Widget _periodBar() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: Material(
      color: AppColors.of(context).panel,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _choosePeriod,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          child: Row(
            children: [
              Icon(
                Icons.date_range,
                size: 20,
                color: _period.isFull
                    ? AppColors.of(context).muted
                    : AppColors.of(context).accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Período',
                      style: TextStyle(
                        color: AppColors.of(context).muted,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      _periodLabel(),
                      style: TextStyle(
                        color: AppColors.of(context).text,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (_period.isFull)
                Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(
                    Icons.chevron_right,
                    color: AppColors.of(context).muted,
                  ),
                )
              else
                IconButton(
                  tooltip: 'Voltar para a temporada inteira',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () =>
                      _update(() => _period = const _ComparisonPeriod.full()),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  String _seasonName(Season season) =>
      season.startDate.year == season.endDate.year
      ? '${season.startDate.year}'
      : '${season.startDate.year}/${season.endDate.year}';

  String _shortSeason(Season season) {
    String year(int value) => (value % 100).toString().padLeft(2, '0');
    return season.startDate.year == season.endDate.year
        ? '${season.startDate.year}'
        : '${year(season.startDate.year)}/${year(season.endDate.year)}';
  }

  Future<String?> _chooseSeason(String? current) =>
      showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        backgroundColor: AppColors.of(context).background,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Temporada',
                  style: TextStyle(
                    color: AppColors.of(context).text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final season in _seasons)
                ListTile(
                  title: Text('Temporada ${_seasonName(season)}'),
                  trailing: season.id == current
                      ? Icon(
                          Icons.check_rounded,
                          color: AppColors.of(context).accent,
                        )
                      : null,
                  onTap: () => Navigator.pop(context, season.id),
                ),
            ],
          ),
        ),
      );

  Widget _seasonChip(Key key, String? seasonId, ValueChanged<String> onPicked) {
    final c = AppColors.of(context);
    final season = _seasons.where((s) => s.id == seasonId).firstOrNull;
    return Material(
      color: c.raised.withValues(alpha: .6),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(9),
        onTap: () async {
          final picked = await _chooseSeason(seasonId);
          if (picked != null && mounted) onPicked(picked);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 5, 2, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  season == null ? 'Temporada' : _shortSeason(season),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.expand_more_rounded, size: 15, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cards() => LayoutBuilder(
    builder: (context, constraints) {
      final canAdd = _selections.length < comparisonMaxPlayers;
      const addWidth = 78.0;
      final players = _selections.length;
      final width = players == 0
          ? constraints.maxWidth - 24
          : players <= 2
          ? (constraints.maxWidth -
                    24 -
                    (canAdd ? addWidth + 10 : 0) -
                    (players - 1) * 10) /
                players
          : 190.0;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, selection) in _selections.indexed) ...[
                if (index > 0) const SizedBox(width: 10),
                SizedBox(width: width, child: _playerCard(selection)),
              ],
              if (canAdd) ...[
                if (_selections.isNotEmpty) const SizedBox(width: 10),
                SizedBox(
                  width: players == 0 ? width : addWidth,
                  child: _addCard(),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  Widget _iconAction(IconData icon, String tooltip, VoidCallback onPressed) =>
      SizedBox.square(
        dimension: 27,
        child: IconButton(
          padding: EdgeInsets.zero,
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, size: 18, color: AppColors.of(context).muted),
        ),
      );

  Widget _playerCard(_PlayerSelection selection) {
    final c = AppColors.of(context), player = selection.player;
    final color = comparisonColor(selection.slot);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 8),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .55), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _replacePlayer(selection),
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: ProfilePortrait(
                        version: widget.person.fifaVersion,
                        realPlayerId: player.record['realPlayerId']?.toString(),
                        customAvatarFilePath: player
                            .record['customAvatarFilePath']
                            ?.toString(),
                        width: 36,
                        height: 42,
                      ),
                    ),
                    Positioned(
                      left: -3,
                      top: -3,
                      child: comparisonSwatch(context, selection.slot),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        player.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      Text(
                        player.position,
                        style: TextStyle(color: c.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _seasonChip(
                    ValueKey('season_${selection.slot}_${selection.seasonId}'),
                    selection.seasonId,
                    (value) => _update(() {
                      final index = _selections.indexOf(selection);
                      if (index >= 0) {
                        _selections[index] = _PlayerSelection(
                          player,
                          value,
                          selection.slot,
                        );
                      }
                    }),
                  ),
                ),
              ),
              _iconAction(
                Icons.swap_horiz,
                'Trocar jogador',
                () => _replacePlayer(selection),
              ),
              _iconAction(
                Icons.close,
                'Remover jogador',
                () => _update(() => _selections.remove(selection)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _addCard() {
    final c = AppColors.of(context);
    final compact = _selections.isNotEmpty;
    final season = _seasonChip(
      ValueKey('pending_$_pendingSeasonId'),
      _pendingSeasonId,
      (value) => setState(() => _pendingSeasonId = value),
    );
    return Material(
      key: const ValueKey('compare-add'),
      color: c.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.line),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        onTap: _addPlayers,
        child: Padding(
          padding: EdgeInsets.all(compact ? 6 : 10),
          child: compact
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Tooltip(
                      message: 'Adicionar jogadores',
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: c.accent.withValues(alpha: .12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.add, color: c.accent, size: 20),
                      ),
                    ),
                    const SizedBox(height: 6),
                    season,
                  ],
                )
              : Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: c.accent.withValues(alpha: .12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.add, color: c.accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Selecionar Jogador',
                            style: TextStyle(
                              color: c.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          season,
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _section(String title, Widget child, {VoidCallback? onExpand}) =>
      ComparisonSection(
        title: title,
        expanded: !_collapsed.contains(title),
        onToggle: () => setState(() {
          if (!_collapsed.add(title)) _collapsed.remove(title);
        }),
        onExpand: onExpand,
        child: child,
      );

  Widget _statPanel(
    String title,
    List<_ComparisonMetric> metrics,
    List<_SeasonSnapshot> columns,
  ) => _section(
    title,
    LayoutBuilder(
      builder: (context, constraints) {
        const labelWidth = 112.0, headerHeight = 38.0, rowHeight = 42.0;
        final columnWidth = math.max(
          84.0,
          (constraints.maxWidth - labelWidth) / columns.length,
        );
        final ranks = [for (final metric in metrics) metric.ranking(columns)];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: labelWidth,
              child: Column(
                children: [
                  const SizedBox(height: headerHeight),
                  for (final (index, metric) in metrics.indexed)
                    _labelCell(metric, ranks[index].tie, rowHeight),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (column, snapshot) in columns.indexed)
                      SizedBox(
                        width: columnWidth,
                        child: Column(
                          children: [
                            _columnHeader(snapshot, headerHeight),
                            for (final (index, metric) in metrics.indexed)
                              _valueCell(
                                metric,
                                snapshot,
                                ranks[index].best.contains(column),
                                rowHeight,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _labelCell(
    _ComparisonMetric metric,
    bool tie,
    double height,
  ) => Container(
    height: height,
    decoration: _rowLine,
    padding: const EdgeInsets.only(right: 6),
    alignment: Alignment.centerLeft,
    child: Tooltip(
      message: metric.number == null || !metric.rank
          ? metric.label
          : '${metric.label}: ${metric.lowerBetter ? 'menor' : 'maior'} é melhor',
      child: Row(
        children: [
          Expanded(
            child: Text(
              metric.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.of(context).muted,
                fontSize: 12,
              ),
            ),
          ),
          if (tie)
            Text(
              '=',
              style: TextStyle(
                color: AppColors.of(context).muted,
                fontSize: 12,
              ),
            ),
        ],
      ),
    ),
  );

  Widget _columnHeader(_SeasonSnapshot snapshot, double height) => SizedBox(
    height: height,
    child: Tooltip(
      message: '${snapshot.player.name} · ${_seasonLabel(snapshot)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            comparisonSwatch(context, snapshot.slot),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    snapshot.player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.of(context).text,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _seasonLabel(snapshot),
                    maxLines: 1,
                    style: TextStyle(
                      color: AppColors.of(context).muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _valueCell(
    _ComparisonMetric metric,
    _SeasonSnapshot snapshot,
    bool best,
    double height,
  ) {
    final display = metric.value(snapshot);
    final exact = metric.exact?.call(snapshot) ?? display;
    final color = comparisonColor(snapshot.slot);
    return Container(
      height: height,
      decoration: _rowLine,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      child: Tooltip(
        message:
            '$exact${best ? '\nMelhor resultado · ${metric.lowerBetter ? 'menor' : 'maior'} é melhor' : ''}',
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: best ? color.withValues(alpha: .16) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.of(context).text,
                    fontWeight: best ? FontWeight.w700 : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
              ),
              if (best) ...[
                const SizedBox(width: 3),
                Icon(Icons.check_circle_outline, size: 13, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Map<String, List<_ComparisonMetric>> _metricGroups() {
    _ComparisonMetric n(
      String label,
      num? Function(_SeasonSnapshot) number, {
      int decimals = 0,
      String suffix = '',
      bool lower = false,
      bool rank = true,
      bool timeline = false,
      bool rate = false,
      double? cap,
    }) {
      final perGame = rate && _per90;
      num? value(_SeasonSnapshot s) =>
          perGame ? s.numbers.per90(number(s)) : number(s);
      String format(num value) => analysisNumber(
        value,
        decimals: perGame ? 2 : decimals,
        suffix: suffix,
      );
      return _ComparisonMetric(
        label,
        (s) => value(s) == null ? '–' : format(value(s)!),
        number: value,
        format: format,
        lowerBetter: lower,
        rank: rank,
        timeline: timeline,
        cap: cap ?? (suffix == '%' ? 100 : null),
        axisSuffix: suffix == '%' ? '%' : '',
      );
    }

    final person = widget.person;
    return {
      'Perfil': [
        n('Idade', (s) => s.age, rank: false),
        n('Altura', (s) => _numeric(s.height), suffix: ' cm', rank: false),
        n('Peso', (s) => _numeric(s.weight), suffix: ' kg', rank: false),
        _ComparisonMetric('Posição', (s) => s.position),
        n('Classificação geral', (s) => _numeric(s.overall), timeline: true),
        _ComparisonMetric(
          'Valor de mercado',
          (s) => s.money(s.marketValue),
          exact: (s) => s.money(s.marketValue, compact: false),
          number: (s) => _numeric(s.marketValue),
          format: (value) => _money(person, value),
          timeline: true,
        ),
        _ComparisonMetric(
          'Salário semanal',
          (s) => s.money(s.wage),
          exact: (s) => s.money(s.wage, compact: false),
          number: (s) => _numeric(s.wage),
          format: (value) => _money(person, value),
          lowerBetter: true,
          timeline: true,
        ),
      ],
      'Participação': [
        n('Jogos', (s) => s.total.matches),
        n('Como titular', (s) => s.total.starts),
        n('Minutos', (s) => s.total.minutes),
        n('Melhor em campo', (s) => s.total.motm),
        n('Nota média', (s) => s.total.rating, decimals: 2, cap: 10),
      ],
      'Produção': [
        n('Gols', (s) => s.total.goals, rate: true),
        n('Assistências', (s) => s.total.assists, rate: true),
        n('Gols + assistências', (s) => s.numbers.contributions, rate: true),
        n('Gols de pênalti', (s) => s.numbers.penaltyGoals),
        n('Hat-tricks', (s) => s.numbers.hatTricks),
        n(
          'Minutos por gol',
          (s) => s.numbers.minutesPer(s.total.goals),
          suffix: "'",
          lower: true,
        ),
        n(
          'Minutos por participação',
          (s) => s.numbers.minutesPer(s.numbers.contributions),
          suffix: "'",
          lower: true,
        ),
      ],
      'Finalização': [
        n('Finalizações', (s) => s.numbers.shots, rate: true),
        n('No alvo', (s) => s.numbers.shotAccuracy, suffix: '%'),
        n('Conversão', (s) => s.numbers.conversion, suffix: '%'),
        n(
          'Gols esperados (xG)',
          (s) => s.numbers.expectedGoals,
          decimals: 2,
          rate: true,
        ),
      ],
      'Criação': [
        n('Passes-chave', (s) => s.numbers.keyPasses, rate: true),
        n('Passes', (s) => s.numbers.passes, rate: true),
        n('Precisão de passe', (s) => s.numbers.passAccuracy, suffix: '%'),
        n(
          'Assistências esperadas (xA)',
          (s) => s.numbers.expectedAssists,
          decimals: 2,
          rate: true,
        ),
        n('Dribles', (s) => s.numbers.dribbles, rate: true),
        n('Dribles certos', (s) => s.numbers.dribbleAccuracy, suffix: '%'),
      ],
      'Defesa': [
        n('Desarmes', (s) => s.numbers.tackles, rate: true),
        n('Desarmes certos', (s) => s.numbers.tackleAccuracy, suffix: '%'),
        n('Defesas', (s) => s.numbers.saves, rate: true),
        n('Pênaltis defendidos', (s) => s.numbers.penaltySaves),
        n('Jogos sem sofrer gols', (s) => s.numbers.cleanSheets),
      ],
      'Disciplina': [
        n('Cartões amarelos', (s) => s.total.yellowCards, lower: true),
        n('Cartões vermelhos', (s) => s.total.redCards, lower: true),
      ],
    };
  }

  List<_ComparisonMetric> _visible(
    List<_ComparisonMetric> metrics,
    List<_SeasonSnapshot> snapshots,
  ) => [
    for (final m in metrics)
      if (snapshots.any(
        (s) => m.number == null ? m.value(s) != '–' : m.number!(s) != null,
      ))
        m,
  ];

  String _seasonLabel(_SeasonSnapshot s) {
    final season = s.season;
    if (season == null) return 'Sem temporada';
    final label = _seasonName(season);
    final from = s.from, to = s.to;
    if (from == null || to == null) return label;
    final day = DateFormat('dd/MM', 'pt_BR');
    return '$label · ${day.format(from)}–${day.format(to)}';
  }

  List<ComparisonEntry> _entries(List<_SeasonSnapshot> snapshots) {
    String year(int value) => (value % 100).toString().padLeft(2, '0');
    return [
      for (final s in snapshots)
        ComparisonEntry(
          s.slot,
          s.season != null &&
                  snapshots.where((o) => o.player.id == s.player.id).length > 1
              ? '${s.player.name} (${year(s.season!.startDate.year)}/${year(s.season!.endDate.year)})'
              : s.player.name,
          _seasonLabel(s),
        ),
    ];
  }

  ComparisonTrendSeries _trendSeries(
    _SeasonSnapshot snapshot,
    _ComparisonMetric metric,
    ComparisonEntry entry,
  ) {
    final season = snapshot.season;
    final points = <ComparisonTrendPoint>[];
    if (season != null) {
      final start = season.startDate;
      int monthOf(DateTime date) =>
          (date.year - start.year) * 12 + date.month - start.month;
      void add(int month, _SeasonSnapshot part) {
        final value = metric.number!(part);
        if (value == null || !value.isFinite) return;
        points.add(
          ComparisonTrendPoint(
            month,
            value.toDouble(),
            DateTime(start.year, start.month + month),
          ),
        );
      }

      final byMonth = <int, List<PlayerMatchData>>{};
      for (final match in snapshot.matches) {
        final date = match.date;
        if (date == null) continue;
        final month = monthOf(date);
        if (month >= 0) (byMonth[month] ??= []).add(match);
      }
      final played = byMonth.keys.toList()..sort();
      if (metric.timeline) {
        final limit = snapshot.to ?? season.endDate;
        final first = snapshot.from == null
            ? 0
            : math.max(0, monthOf(snapshot.from!));
        var last = played.lastOrNull ?? first;
        for (final row in [
          ...snapshot.data.overalls,
          ...snapshot.data.marketValues,
          ...snapshot.data.contracts,
        ]) {
          final date = DateTime.tryParse('${row['date']}');
          if (date == null || date.isAfter(limit)) continue;
          last = math.max(last, monthOf(date));
        }
        for (var month = first; month <= last; month++) {
          final end = DateTime(start.year, start.month + month + 1, 0);
          add(
            month,
            snapshot.part(const [], until: end.isAfter(limit) ? limit : end),
          );
        }
      } else if (_cumulative) {
        final sofar = <PlayerMatchData>[];
        for (
          var month = played.firstOrNull ?? 0;
          month <= (played.lastOrNull ?? -1);
          month++
        ) {
          sofar.addAll(byMonth[month] ?? const []);
          add(month, snapshot.part([...sofar]));
        }
      } else {
        for (final month in played) {
          add(month, snapshot.part(byMonth[month]!));
        }
      }
    }
    return ComparisonTrendSeries(entry, points);
  }

  String Function(int) _monthLabel(List<_SeasonSnapshot> snapshots) =>
      _monthNames(snapshots.map((s) => s.season));

  String Function(int) _monthNames(Iterable<Season?> seasons) {
    final starts = seasons.map((s) => s?.startDate).toList();
    final first = starts.firstOrNull;
    if (first == null ||
        starts.any((d) => d == null || d.month != first.month)) {
      return (m) => 'M${m + 1}';
    }
    return (m) => DateFormat(
      'MMM',
      'pt_BR',
    ).format(DateTime(2000, first.month + m)).replaceAll('.', '');
  }

  String _summaryTitle(_ComparisonMetric metric) => metric.timeline
      ? 'Início → fim do período'
      : _cumulative
      ? (_period.isFull ? 'Acumulado na temporada' : 'Acumulado no período')
      : 'Melhor mês';

  String _trendSummary(ComparisonTrendSeries series, _ComparisonMetric metric) {
    final points = series.points;
    if (points.isEmpty) return '–';
    final format = metric.format!;
    if (metric.timeline) {
      return points.length == 1
          ? format(points.single.value)
          : '${format(points.first.value)} → ${format(points.last.value)}';
    }
    if (_cumulative) return format(points.last.value);
    final best = points.reduce(
      (a, b) =>
          (metric.lowerBetter ? b.value < a.value : b.value > a.value) ? b : a,
    );
    final month = DateFormat(
      'MMM/yy',
      'pt_BR',
    ).format(best.date).replaceAll('.', '');
    return '${format(best.value)} · $month';
  }

  ComparisonBarGroup _barGroup(
    String label,
    num? Function(_SeasonSnapshot) value,
    List<_SeasonSnapshot> snapshots, {
    int decimals = 0,
    double? scaleMax,
  }) {
    final format = NumberFormat(
      decimals == 0 ? '0' : '0.${'0' * decimals}',
      'pt_BR',
    );
    final values = [for (final s in snapshots) value(s)];
    return ComparisonBarGroup(
      label: label,
      values: values,
      texts: [for (final v in values) v == null ? '–' : format.format(v)],
      scaleMax: scaleMax,
    );
  }

  Future<void> _expandChart(String title, Widget Function(bool) content) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            backgroundColor: AppColors.of(context).background,
            appBar: AppBar(
              backgroundColor: AppColors.of(context).background,
              title: Text(title),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: content(true),
              ),
            ),
          ),
        ),
      );

  Widget _modeToggle() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MatchSegmented<bool>(
          key: const ValueKey('compare-mode'),
          value: _per90,
          onChanged: (value) => setState(() => _per90 = value),
          items: const [
            MatchSegment(false, 'Totais', key: ValueKey('compare-totals')),
            MatchSegment(true, 'Por 90 min', key: ValueKey('compare-per90')),
          ],
        ),
        if (_per90)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Contagens divididas pelos minutos em campo × 90, para comparar '
              'quem jogou mais com quem jogou menos. Notas, percentuais e '
              'perfil não mudam.',
              style: TextStyle(
                color: AppColors.of(context).muted,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _advantage(
    List<_SeasonSnapshot> snapshots,
    Map<String, List<_ComparisonMetric>> groups,
    List<ComparisonEntry> entries,
  ) {
    final c = AppColors.of(context);
    final wins = List.filled(snapshots.length, 0);
    var ties = 0, decided = 0;
    final leaders = <String, String>{};
    for (final MapEntry(:key, :value) in groups.entries) {
      if (key == 'Perfil') continue;
      final groupWins = List.filled(snapshots.length, 0);
      var compared = false;
      for (final metric in value) {
        final rank = metric.ranking(snapshots);
        if (rank.tie) {
          ties++;
          compared = true;
          continue;
        }
        if (rank.best.isEmpty) continue;
        compared = true;
        decided++;
        for (final i in rank.best) {
          wins[i]++;
          groupWins[i]++;
        }
      }
      if (!compared) continue;
      final top = groupWins.fold(0, math.max);
      final ahead = [
        for (var i = 0; i < snapshots.length; i++)
          if (groupWins[i] == top && top > 0) i,
      ];
      leaders[key] = ahead.length == 1
          ? entries[ahead.single].name
          : 'Equilíbrio';
    }
    final order = [for (var i = 0; i < snapshots.length; i++) i]
      ..sort((a, b) => wins[b].compareTo(wins[a]));
    final most = wins.fold(0, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Estatísticas de jogo em que cada um tem o melhor número'
          '${_per90 ? ', por 90 minutos' : ''}. Perfil, valor e salário ficam de fora.',
          style: TextStyle(color: c.muted, fontSize: 11.5, height: 1.4),
        ),
        const SizedBox(height: 12),
        for (final i in order)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                comparisonSwatch(context, snapshots[i].slot),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entries[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: most == 0 ? 0 : wins[i] / most,
                          minHeight: 6,
                          color: comparisonColor(snapshots[i].slot),
                          backgroundColor: c.raised,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${wins[i]}',
                        style: TextStyle(
                          color: c.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextSpan(
                        text: ' de $decided',
                        style: TextStyle(color: c.muted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (ties > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '$ties ${ties == 1 ? 'estatística empatada' : 'estatísticas empatadas'}.',
              style: TextStyle(color: c.muted, fontSize: 11.5),
            ),
          ),
        if (leaders.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final MapEntry(:key, :value) in leaders.entries)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: c.raised.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 11.5),
                      children: [
                        TextSpan(
                          text: '$key · ',
                          style: TextStyle(color: c.muted),
                        ),
                        TextSpan(
                          text: value,
                          style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _versusPanel(
    String title,
    List<_ComparisonMetric> metrics,
    List<_SeasonSnapshot> pair,
    List<ComparisonEntry> entries,
  ) {
    final c = AppColors.of(context);
    Widget name(int i) => Row(
      mainAxisAlignment: i == 0
          ? MainAxisAlignment.start
          : MainAxisAlignment.end,
      children: [
        if (i == 0) comparisonSwatch(context, pair[0].slot),
        Flexible(
          child: Text(
            entries[i].name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (i == 1) ...[
          const SizedBox(width: 6),
          comparisonSwatch(context, pair[1].slot),
        ],
      ],
    );
    return _section(
      title,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: name(0)),
              const SizedBox(width: 12),
              Expanded(child: name(1)),
            ],
          ),
          const SizedBox(height: 6),
          for (final (i, metric) in metrics.indexed) ...[
            if (i > 0) Divider(height: 1, color: c.line.withValues(alpha: .35)),
            _versusRow(metric, pair),
          ],
        ],
      ),
    );
  }

  Widget _versusRow(_ComparisonMetric metric, List<_SeasonSnapshot> pair) {
    final c = AppColors.of(context);
    final rank = metric.ranking(pair);
    final colors = [for (final s in pair) comparisonColor(s.slot)];
    Widget value(int i) {
      final best = rank.best.contains(i);
      return Text(
        metric.value(pair[i]),
        textAlign: i == 0 ? TextAlign.left : TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: best ? colors[i] : c.text,
          fontSize: 15,
          fontWeight: best ? FontWeight.w800 : FontWeight.w600,
        ),
      );
    }

    final numbers = [for (final s in pair) metric.number?.call(s)];
    final bar =
        metric.rank &&
        !metric.lowerBetter &&
        numbers.every((v) => v != null && v >= 0) &&
        numbers[0]! + numbers[1]! > 0;
    final row = Padding(
      key: ValueKey('versus-${metric.label}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(width: 84, child: value(0)),
              Expanded(
                child: Text(
                  metric.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ),
              SizedBox(width: 84, child: value(1)),
            ],
          ),
          if (bar) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 5,
              child: Row(
                children: [
                  for (final i in [0, 1]) ...[
                    if (i == 1) const SizedBox(width: 3),
                    Expanded(
                      flex: (numbers[i]! * 1000 / (numbers[0]! + numbers[1]!))
                          .round()
                          .clamp(1, 1000),
                      child: Container(
                        decoration: BoxDecoration(
                          color: colors[i].withValues(
                            alpha: rank.best.contains(i) || rank.tie ? 1 : .35,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
    final exact = metric.exact;
    return exact == null
        ? row
        : Tooltip(
            message: [for (final s in pair) '${s.player.name}: ${exact(s)}']
                .join('\n'),
            triggerMode: TooltipTriggerMode.tap,
            child: row,
          );
  }

  Widget _stats(List<_SeasonSnapshot> snapshots) {
    final groups = _metricGroups();
    final entries = _entries(snapshots);
    final trendable = {
      for (final entry in groups.entries)
        entry.key: [
          for (final m in entry.value)
            if (m.number != null && m.rank && m.format != null) m,
        ],
    };
    final candidates = trendable.values.expand((m) => m).toList();
    final metric =
        candidates.where((m) => m.label == _trendMetric).firstOrNull ??
        candidates.first;
    Widget bars(bool large) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ComparisonLegend(entries: entries),
        const SizedBox(height: 18),
        ComparisonGroupedBars(
          entries: entries,
          height: large ? 300 : 150,
          groups: _per90
              ? [
                  _barGroup(
                    "Gols/90'",
                    (s) => s.numbers.per90(s.total.goals),
                    snapshots,
                    decimals: 2,
                  ),
                  _barGroup(
                    "Assist./90'",
                    (s) => s.numbers.per90(s.total.assists),
                    snapshots,
                    decimals: 2,
                  ),
                  _barGroup(
                    "G+A/90'",
                    (s) => s.numbers.per90(s.numbers.contributions),
                    snapshots,
                    decimals: 2,
                  ),
                  _barGroup(
                    'Nota',
                    (s) => s.total.rating,
                    snapshots,
                    decimals: 2,
                    scaleMax: 10,
                  ),
                ]
              : [
                  _barGroup('Gols', (s) => s.total.goals, snapshots),
                  _barGroup('Assistências', (s) => s.total.assists, snapshots),
                  _barGroup('Jogos', (s) => s.total.matches, snapshots),
                  _barGroup(
                    'Nota',
                    (s) => s.total.rating,
                    snapshots,
                    decimals: 2,
                    scaleMax: 10,
                  ),
                ],
        ),
        const SizedBox(height: 12),
        Text(
          'Cada estatística tem a própria escala; a nota vai de 0 a 10. Toque nas barras para ver o jogador e o valor.',
          style: TextStyle(color: AppColors.of(context).muted, fontSize: 11),
        ),
      ],
    );
    Widget trend(bool large) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ComparisonLegend(entries: entries, lines: true),
        const SizedBox(height: 16),
        if (large)
          Text(
            metric.timeline
                ? metric.label
                : '${metric.label} · ${_cumulative ? 'Acumulado' : 'Por mês'}',
            style: TextStyle(color: AppColors.of(context).text, fontSize: 18),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: metric.label,
            isExpanded: true,
            dropdownColor: AppColors.of(context).panel,
            decoration: const InputDecoration(labelText: 'Estatística'),
            items: [
              for (final entry in trendable.entries)
                if (entry.value.isNotEmpty) ...[
                  DropdownMenuItem(
                    enabled: false,
                    value: '#${entry.key}',
                    child: Text(
                      entry.key.toUpperCase(),
                      style: TextStyle(
                        color: AppColors.of(context).muted,
                        fontSize: 11,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  for (final m in entry.value)
                    DropdownMenuItem(value: m.label, child: Text(m.label)),
                ],
            ],
            onChanged: (value) {
              if (value != null) setState(() => _trendMetric = value);
            },
          ),
        if (!large && !metric.timeline) ...[
          const SizedBox(height: 12),
          MatchSegmented<bool>(
            value: _cumulative,
            onChanged: (value) => setState(() => _cumulative = value),
            items: const [
              MatchSegment(false, 'Por mês'),
              MatchSegment(true, 'Acumulado'),
            ],
          ),
        ],
        const SizedBox(height: 16),
        ComparisonTrendChart(
          key: ValueKey(
            '${metric.label}:$_cumulative:$_per90:${[for (final s in snapshots) '${s.slot}-${s.player.id}-${s.season?.id}'].join(',')}',
          ),
          series: [
            for (final (index, s) in snapshots.indexed)
              _trendSeries(s, metric, entries[index]),
          ],
          format: (value) => metric.format!(value),
          monthLabel: _monthLabel(snapshots),
          cap: metric.cap,
          axisSuffix: metric.axisSuffix,
          summaryTitle: _summaryTitle(metric),
          summary: (series) => _trendSummary(series, metric),
          height: large ? 340 : 220,
        ),
        const SizedBox(height: 8),
        Text(
          '${metric.timeline
              ? 'Valor registrado no fim de cada mês.'
              : _cumulative
              ? 'Acumulado: a temporada até o fim de cada mês.'
              : 'Por mês: só os jogos de cada mês.'} Meses contados a partir do início de cada temporada; toque nos pontos para ver os valores.',
          style: TextStyle(color: AppColors.of(context).muted, fontSize: 11),
        ),
      ],
    );
    return Column(
      children: [
        if (snapshots.isNotEmpty) _modeToggle(),
        if (snapshots.length >= 2) ...[
          _section(
            'Quem leva vantagem',
            _advantage(snapshots, groups, entries),
          ),
          _section(
            'Números da temporada',
            bars(false),
            onExpand: () => _expandChart('Números da temporada', bars),
          ),
          _section(
            'Evolução na temporada',
            trend(false),
            onExpand: () => _expandChart('Evolução na temporada', trend),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Selecione pelo menos dois jogadores para ver quem leva vantagem, os gráficos e os destaques.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.of(context).muted,
                fontSize: 12,
              ),
            ),
          ),
        if (snapshots.isNotEmpty)
          for (final entry in groups.entries)
            if (_visible(entry.value, snapshots) case final metrics
                when metrics.isNotEmpty)
              snapshots.length == 2
                  ? _versusPanel(entry.key, metrics, snapshots, entries)
                  : _statPanel(entry.key, metrics, snapshots),
        if (snapshots.length > 2)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              '✓ Melhor resultado   ·   = Todos com o mesmo valor\nCartões, salário e minutos por gol: menor é melhor.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.of(context).muted,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.of(context).background,
    appBar: AppBar(
      backgroundColor: AppColors.of(context).background,
      title: const Text('Comparar jogadores'),
      actions: [
        IconButton(
          tooltip: _collapsed.isEmpty ? 'Recolher tudo' : 'Expandir tudo',
          icon: Icon(
            _collapsed.isEmpty ? Icons.unfold_less : Icons.unfold_more,
          ),
          onPressed: () => setState(() {
            if (_collapsed.isNotEmpty) {
              _collapsed.clear();
            } else {
              _collapsed.addAll([
                'Quem leva vantagem',
                'Números da temporada',
                'Evolução na temporada',
                ..._metricGroups().keys,
              ]);
            }
          }),
        ),
      ],
    ),
    body: SafeArea(
      child: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Não foi possível carregar os jogadores.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(() {
                        _profiles.clear();
                        _initialization = _load();
                      }),
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            child: Column(
              children: [
                _cards(),
                _periodBar(),
                FutureBuilder<List<_SeasonSnapshot>>(
                  future: _comparison,
                  builder: (context, result) {
                    if (result.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Text(
                              'Não foi possível carregar as estatísticas.',
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                _profiles.clear();
                                _comparison = _resolve();
                              }),
                              child: const Text('Tentar novamente'),
                            ),
                          ],
                        ),
                      );
                    }
                    if (result.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(),
                      );
                    }
                    return _stats(result.data ?? const []);
                  },
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

num? _numeric(Object? value) => value is num ? value : null;

String _money(Person person, Object? value, {bool compact = true}) {
  if (value is! num) return '–';
  final currency = switch (person.currency?.toUpperCase()) {
    'BRL' => r'R$',
    'USD' => r'$',
    'EUR' || 'EURO' || null => '€',
    final String code => code,
  };
  return compact
      ? NumberFormat.compactCurrency(
          locale: 'pt_BR',
          symbol: currency,
          decimalDigits: 1,
        ).format(value)
      : '${NumberFormat.decimalPattern('pt_BR').format(value)} $currency';
}

class _ComparisonMetric {
  const _ComparisonMetric(
    this.label,
    this.value, {
    this.exact,
    this.number,
    this.format,
    this.lowerBetter = false,
    this.rank = true,
    this.timeline = false,
    this.cap,
    this.axisSuffix = '',
  });
  final String label;
  final String Function(_SeasonSnapshot) value;
  final String Function(_SeasonSnapshot)? exact;
  final num? Function(_SeasonSnapshot)? number;

  final String Function(num)? format;
  final bool lowerBetter, rank;

  final bool timeline;

  final double? cap;
  final String axisSuffix;

  ({Set<int> best, bool tie}) ranking(List<_SeasonSnapshot> columns) {
    final values = <int, num>{};
    if (rank && number != null) {
      for (final (index, column) in columns.indexed) {
        final value = number!(column);
        if (value != null && value.isFinite) values[index] = value;
      }
    }
    if (values.length < 2) return (best: const <int>{}, tie: false);
    final best = values.values.reduce(
      (a, b) => (lowerBetter ? b < a : b > a) ? b : a,
    );
    final top = {
      for (final MapEntry(:key, :value) in values.entries)
        if ((value - best).abs() < .000001) key,
    };
    return top.length == values.length
        ? (best: const <int>{}, tie: true)
        : (best: top, tie: false);
  }
}

enum _PeriodKind { full, until, months }

class _ComparisonPeriod {
  const _ComparisonPeriod.full()
    : kind = _PeriodKind.full,
      cut = null,
      reference = null,
      firstMonth = null,
      lastMonth = null;

  const _ComparisonPeriod.until(DateTime this.cut, Season this.reference)
    : kind = _PeriodKind.until,
      firstMonth = null,
      lastMonth = null;

  const _ComparisonPeriod.months(int this.firstMonth, int this.lastMonth)
    : kind = _PeriodKind.months,
      cut = null,
      reference = null;

  final _PeriodKind kind;
  final DateTime? cut;
  final Season? reference;
  final int? firstMonth, lastMonth;

  bool get isFull => kind == _PeriodKind.full;

  (DateTime, DateTime)? window(Season season) {
    final start = season.startDate, end = season.endDate;
    DateTime cap(DateTime day) => day.isAfter(end) ? end : day;
    switch (kind) {
      case _PeriodKind.full:
        return null;
      case _PeriodKind.until:
        final origin = reference!.startDate;
        final last = _sameStart(start, origin)
            ? DateTime(
                start.year + cut!.year - origin.year,
                cut!.month,
                cut!.day,
              )
            : start.add(Duration(days: cut!.difference(origin).inDays));
        return (start, cap(last));
      case _PeriodKind.months:
        final from = DateTime(start.year, start.month + firstMonth!);
        return (
          from.isBefore(start) ? start : from,
          cap(DateTime(start.year, start.month + lastMonth! + 1, 0)),
        );
    }
  }
}

bool _sameStart(DateTime a, DateTime b) => a.month == b.month && a.day == b.day;

class _PlayerSelection {
  const _PlayerSelection(this.player, this.seasonId, this.slot);
  final _ComparisonPlayer player;
  final String? seasonId;

  final int slot;
}

class _ComparisonPlayer {
  const _ComparisonPlayer(this.id, this.rows, this.realPlayer);
  final String id;
  final List<Map<String, Object?>> rows;
  final GamePlayer? realPlayer;
  Map<String, Object?> get record => rows.first;
  String get name =>
      record['customName']?.toString() ?? realPlayer?.name ?? 'Jogador';
  String get position => positionShortName(
    record['customPositionId']?.toString() ?? realPlayer?.mainPositionId,
  );
}

class _SeasonSnapshot {
  _SeasonSnapshot(
    this.person,
    this.player,
    this.data,
    this.season, {
    List<PlayerMatchData>? matches,
    DateTime? until,
    this.slot = 0,
    this.from,
    this.to,
  }) : until = until ?? to {
    this.matches =
        matches ??
        [
          if (season != null)
            for (final match in data.filtered(seasonId: season!.id))
              if (_inWindow(match.date)) match,
        ];
    total = PlayerTotals(this.matches);
    roster = player.rows
        .where((row) => row['seasonId'] == season?.id && season != null)
        .firstOrNull;
  }
  final Person person;
  final _ComparisonPlayer player;
  final PlayerProfileData data;
  final Season? season;

  final DateTime? until;

  final DateTime? from, to;

  bool _inWindow(DateTime? date) {
    if (from == null && to == null) return true;
    if (date == null) return false;
    if (from != null && date.isBefore(from!)) return false;
    return to == null ||
        date.isBefore(DateTime(to!.year, to!.month, to!.day + 1));
  }

  final int slot;
  late final List<PlayerMatchData> matches;
  late final PlayerTotals total;
  late final Map<String, Object?>? roster;

  late final PlayerNumbers numbers = PlayerNumbers(matches);

  _SeasonSnapshot part(List<PlayerMatchData> matches, {DateTime? until}) =>
      _SeasonSnapshot(
        person,
        player,
        data,
        season,
        matches: matches,
        until: until,
        slot: slot,
        from: from,
        to: to,
      );

  String get position => player.position;
  Object? get height => player.record.containsKey('playerHeight')
      ? player.record['playerHeight']
      : player.realPlayer?.height;
  Object? get weight => player.record.containsKey('playerWeight')
      ? player.record['playerWeight']
      : player.realPlayer?.weight;

  int? get age {
    final selected = season;
    if (selected == null) return null;
    final raw = player.record['birthdate'];
    final birthdate = raw is num
        ? DateTime.fromMillisecondsSinceEpoch(raw.toInt())
        : DateTime.tryParse(raw?.toString() ?? '') ??
              player.realPlayer?.birthdate;
    return calcPlayerAge(
      fifaVersion: person.fifaVersion,
      seasonStart: selected.startDate,
      seasonEnd: selected.endDate,
      birthdate: birthdate,
      firstSeasonAge:
          (player.record['firstSeasonAge'] as num?)?.toInt() ??
          player.realPlayer?.age,
    );
  }

  Map<String, Object?>? _historyAtSeason(List<Map<String, Object?>> history) {
    final selected = season;
    if (selected == null) return null;
    final end = until ?? selected.endDate;
    final exclusiveEnd = DateTime(end.year, end.month, end.day + 1);
    for (final row in history) {
      final date = DateTime.tryParse(row['date']?.toString() ?? '');
      if (date != null && date.isBefore(exclusiveEnd)) return row;
    }
    return null;
  }

  Object? get overall {
    if (until != null) {
      return _historyAtSeason(data.overalls)?['overall'] ?? roster?['overall'];
    }
    return data.latestOverall ?? player.record['overall'] ?? roster?['overall'];
  }

  Object? get marketValue =>
      _historyAtSeason(data.marketValues)?['value'] ?? roster?['marketValue'];
  Object? get wage {
    final contract = _historyAtSeason(data.contracts);
    final end = DateTime.tryParse(contract?['endDate']?.toString() ?? '');
    if (end != null && season != null && end.isBefore(season!.startDate)) {
      return roster?['wage'];
    }
    return contract?['wage'] ?? roster?['wage'];
  }

  String money(Object? value, {bool compact = true}) =>
      _money(person, value, compact: compact);

  int? sum(int? Function(ManagerFixturePlayerPerformance) field) {
    final values = matches
        .map((m) => field(m.performance))
        .whereType<int>()
        .toList();
    return values.isEmpty ? null : values.reduce((a, b) => a + b);
  }

  double? ratio(num? value) =>
      value == null || total.matches == 0 ? null : value / total.matches;

  double? minutesPer(int value) => value == 0 ? null : total.minutes / value;

  double? average(int? Function(ManagerFixturePlayerPerformance) field) {
    final values = matches
        .map((m) => field(m.performance))
        .whereType<int>()
        .toList();
    return values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;
  }
}
