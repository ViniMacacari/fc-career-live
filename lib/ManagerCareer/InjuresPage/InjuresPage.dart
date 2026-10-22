import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../utils/Components/CareerPageWidgets.dart';

import 'package:intl/date_symbol_data_local.dart';

import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../utils/Components/PlayerAvatar.dart';
import '../../utils/Components/TeamLogo.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/SqlService.dart';
import '../../utils/InjuryStatus.dart';
import '../../utils/databaseUtils.dart';
import 'EditInjuryPage.dart';

class InjuresPage extends StatefulWidget {
  const InjuresPage({
    super.key,
    required this.person,
    this.initialOnlyInjured = false,
  });
  final Person person;
  final bool initialOnlyInjured;

  @override
  State<InjuresPage> createState() => _InjuresPageState();
}

class InjuryData {
  const InjuryData({
    required this.seasons,
    required this.injuries,
    required this.players,
    required this.fixtures,
    required this.played,
    required this.careerDate,
    required this.catalog,
  });
  final List<Season> seasons;
  final List<Map<String, Object?>> injuries;

  final Map<String, Map<String, Object?>> players;
  final List<Map<String, Object?>> fixtures;

  final Set<String> played;

  final DateTime careerDate;
  final GameCatalog catalog;
}

class _InjuresPageState extends State<InjuresPage> {
  late Future<InjuryData> _data = _load();
  String? _seasonId, _playerId;
  late bool _onlyInjured = widget.initialOnlyInjured;

  Future<InjuryData> _load() async {
    await initializeDateFormatting();
    final sql = SqlService.instance;
    await sql.syncMatchInjuries(widget.person.id);
    final seasons = await sql.getSeasons(widget.person.id);
    final injuries = await sql.getInjuries(widget.person.id);
    final players = await sql.getCustomPlayers(
      widget.person.id,
      includeCurrentOverall: false,
    );
    final matches = await sql.getInjuryMatchContext(widget.person.id);
    final latest = await sql.getCareerDate(widget.person.id);
    return InjuryData(
      seasons: seasons,
      injuries: injuries,
      players: {for (final p in players) p['id'] as String: p},
      fixtures: matches.fixtures,
      played: matches.played,
      careerDate: latest ?? DateTime.now(),
      catalog: await GameCatalog.load(),
    );
  }

  void _refresh() => setState(() => _data = _load());

  Future<void> _open(InjuryData data, [Map<String, Object?>? row]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditInjuryPage(
          person: widget.person,
          data: data,
          existing: row,
          initialSeasonId: _seasonId,
        ),
      ),
    );
    if (changed == true) _refresh();
  }

  bool get _filtering => _seasonId != null || _playerId != null || _onlyInjured;

  Future<void> _openFilters(InjuryData data) async {
    String? season = _seasonId, player = _playerId;
    var injured = _onlyInjured;
    final players = {
      for (final i in data.injuries)
        if (data.players[i['playerId']] case final p?)
          i['playerId'] as String: p['name']?.toString() ?? '?',
    }.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'common.filters'.tr(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String?>(
                  initialValue: season,
                  isExpanded: true,
                  decoration: injuryFieldDecoration('seasons.season'.tr()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todas')),
                    for (final s in data.seasons)
                      DropdownMenuItem(value: s.id, child: Text(seasonText(s))),
                  ],
                  onChanged: (value) => setSheet(() => season = value),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: player,
                  isExpanded: true,
                  decoration: injuryFieldDecoration('players.player'.tr()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    for (final p in players)
                      DropdownMenuItem(value: p.key, child: Text(p.value)),
                  ],
                  onChanged: (value) => setSheet(() => player = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('injuries.injured'.tr()),
                  subtitle: const Text('Mostrar só quem ainda está lesionado'),
                  value: injured,
                  onChanged: (value) => setSheet(() => injured = value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          season = null;
                          player = null;
                          injured = false;
                          Navigator.pop(context, true);
                        },
                        child: const Text('Limpar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Aplicar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (apply == true) {
      setState(() {
        _seasonId = season;
        _playerId = player;
        _onlyInjured = injured;
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<InjuryData>(
    future: _data,
    builder: (context, snapshot) {
      final data = snapshot.data;
      return Scaffold(
        appBar: AppBar(
          title: Text('injuries.injuries'.tr()),
          actions: [
            if (data != null)
              IconButton(
                tooltip: 'common.filters'.tr(),
                onPressed: () => _openFilters(data),
                icon: Badge(
                  isLabelVisible: _filtering,
                  smallSize: 8,
                  child: const Icon(Icons.filter_alt_outlined),
                ),
              ),
          ],
        ),
        floatingActionButton: data == null || data.seasons.isEmpty
            ? null
            : FloatingActionButton(
                tooltip: 'injuries.addInjury'.tr(),
                onPressed: () => _open(data),
                child: const Icon(Icons.add),
              ),
        body: switch (snapshot) {
          AsyncSnapshot(:final error?) => Center(child: Text('Erro: $error')),
          AsyncSnapshot(data: null) => const Center(
            child: CircularProgressIndicator(),
          ),
          _ when data!.seasons.isEmpty => Center(
            child: Text('common.noSeasonsMessage'.tr()),
          ),
          _ => _list(data),
        },
      );
    },
  );

  Widget _list(InjuryData data) {
    final items =
        [
              for (final row in data.injuries)
                InjuryView.of(row, data, widget.person.fifaVersion),
            ]
            .where(
              (i) =>
                  (_seasonId == null || i.row['seasonId'] == _seasonId) &&
                  (_playerId == null || i.row['playerId'] == _playerId) &&
                  (!_onlyInjured || i.injured),
            )
            .toList()
          ..sort(
            (a, b) => a.injured != b.injured
                ? (a.injured ? -1 : 1)
                : b.start.compareTo(a.start),
          );
    if (items.isEmpty) {
      return CareerEmptyState(
        title: 'injuries.noInjuries'.tr(),
        subtitle: 'Acompanhe a recuperação e a disponibilidade dos jogadores por aqui.',
        icon: Icons.healing_outlined,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        CareerPageHeader(
          title: 'Disponibilidade do elenco',
          eyebrow: 'Departamento médico',
          subtitle:
              '${items.where((item) => item.injured).length} lesões em andamento • ${items.length} registros neste recorte.',
          icon: Icons.healing_outlined,
        ),
        if (_playerId != null) _PlayerSummary(items: items),
        for (final item in items)
          _InjuryCard(
            item: item,
            fifaVersion: widget.person.fifaVersion,
            onTap: () => _open(data, item.row),
          ),
      ],
    );
  }
}

class InjuryView {
  InjuryView._(
    this.row, {
    required this.name,
    required this.player,
    required this.teamName,
    required this.start,
    required this.end,
    required this.injured,
    required this.missedMatches,
    required this.missedDays,
    this.match,
  });

  factory InjuryView.of(
    Map<String, Object?> row,
    InjuryData data,
    String fifaVersion,
  ) {
    final player = data.players[row['playerId']];
    final start = DateTime.tryParse('${row['startDate']}') ?? data.careerDate;
    final end = DateTime.tryParse('${row['endDate']}');
    final until = end ?? data.careerDate;
    final injured = isActiveInjury(row, data.careerDate);
    final playerId = row['playerId'];
    final startDay = DateTime(start.year, start.month, start.day);
    final missed = data.fixtures.where((f) {
      final date = DateTime.tryParse('${f['date']}');
      return date != null &&
          f['playerTeamId'] == row['teamId'] &&
          !date.isBefore(startDay) &&
          !date.isAfter(until) &&
          !data.played.contains('${f['id']}:$playerId');
    }).length;
    final key = SqlService.matchInjuryKey('${row['id']}');
    final fixture = key == null
        ? null
        : data.fixtures.where((f) => f['id'] == key.fixtureId).firstOrNull;
    return InjuryView._(
      row,
      name: player?['name']?.toString() ?? '?',
      player: player,
      teamName: data.catalog.teamLabel(
        fifaVersion,
        '${row['teamId']}',
        leagueId: row['leagueId']?.toString(),
      ),
      start: start,
      end: end,
      injured: injured,
      missedMatches: missed,
      missedDays: until.difference(startDay).inDays.clamp(0, 100000),
      match: fixture == null
          ? null
          : data.catalog.teamLabel(
              fifaVersion,
              '${fixture['oppositeTeamId']}',
              leagueId: fixture['oppositeTeamLeagueId']?.toString(),
            ),
    );
  }

  final Map<String, Object?> row;
  final String name, teamName;
  final Map<String, Object?>? player;
  final DateTime start;
  final DateTime? end;
  final bool injured;
  final int missedMatches, missedDays;

  final String? match;

  String get description {
    final text = row['description']?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
    return match == null ? '' : 'Lesionado na partida contra $match';
  }
}

String seasonText(Season season) =>
    '${season.startDate.year} - ${season.endDate.year}';

InputDecoration injuryFieldDecoration(
  String label, {
  Widget? suffixIcon,
  String? suffixText,
}) => InputDecoration(
  labelText: label,
  suffixIcon: suffixIcon,
  suffixText: suffixText,
  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
);

class _InjuryCard extends StatelessWidget {
  const _InjuryCard({
    required this.item,
    required this.fifaVersion,
    required this.onTap,
  });
  final InjuryView item;
  final String fifaVersion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = context.locale.toString();
    final date = DateFormat.yMMMd(
      DateFormat.localeExists(locale) ? locale : context.locale.languageCode,
    );
    final muted = theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.65);
    final player = item.player;
    final position = positionShortName(player?['positionId']?.toString());
    final expected = item.row['expectedRecoveryDays'] as int?;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PlayerAvatar(
                    fifaVersion: fifaVersion,
                    realPlayerId: player?['realPlayerId']?.toString(),
                    customAvatarFilePath: player?['customAvatarFilePath']
                        ?.toString(),
                    radius: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            TeamLogo.lookup(
                              fifaVersion: fifaVersion,
                              teamId: '${item.row['teamId']}',
                              leagueId: item.row['leagueId']?.toString(),
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '${item.teamName}  |  $position',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: muted, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(injured: item.injured),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.description.isNotEmpty)
                          Text(
                            item.description,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(height: 2),
                        Text(
                          '${date.format(item.start)} → '
                          '${item.end == null ? '...' : date.format(item.end!)}',
                          style: TextStyle(color: muted),
                        ),
                        if (item.injured && expected != null && expected > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${'injuries.expected'.tr()}: '
                              '${'injuries.timing_var.days'.tr(namedArgs: {'count': '$expected'})}',
                              style: TextStyle(color: muted, fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _MissedBox(count: item.missedMatches),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.injured});
  final bool injured;

  @override
  Widget build(BuildContext context) {
    final color = injured ? Colors.redAccent : Colors.greenAccent.shade400;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        injured ? 'injuries.injured'.tr() : 'injuries.recovered'.tr(),
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MissedBox extends StatelessWidget {
  const _MissedBox({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'injuries.missedMatches'.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PlayerSummary extends StatelessWidget {
  const _PlayerSummary({required this.items});
  final List<InjuryView> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget stat(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Row(
          children: [
            stat('${items.length}', 'injuries.injuries'.tr()),
            stat(
              '${items.fold<int>(0, (t, i) => t + i.missedMatches)}',
              'injuries.missedMatches'.tr(),
            ),
            stat(
              '${items.fold<int>(0, (t, i) => t + i.missedDays)}',
              'injuries.missedDays'.tr(),
            ),
          ],
        ),
      ),
    );
  }
}
