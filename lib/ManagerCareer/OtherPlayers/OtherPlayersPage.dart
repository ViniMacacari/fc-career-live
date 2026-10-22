import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../RootPage/DrawerWidget.dart';
import '../../models/Person.dart';
import '../../utils/AppColors.dart';
import '../../utils/Components/CompactDashboardWidgets.dart';
import '../../utils/Components/SelectionSearchField.dart';
import '../../utils/Components/TeamLogo.dart';
import '../../utils/SqlService.dart';
import 'OtherPlayerWidgets.dart';
import 'OtherPlayersData.dart';
import 'OtherTeamPage.dart';

class OtherPlayersPage extends StatefulWidget {
  const OtherPlayersPage({
    super.key,
    required this.person,
    this.sql,
    this.repository,
  });
  final Person person;
  final SqlService? sql;
  @visibleForTesting
  final OtherPlayersRepository? repository;
  @override
  State<OtherPlayersPage> createState() => _OtherPlayersPageState();
}

class _OtherPlayersPageState extends State<OtherPlayersPage> {
  late final OtherPlayersRepository _repo =
      widget.repository ?? OtherPlayersRepository(sql: widget.sql);
  final _search = TextEditingController();
  OtherPlayersSnapshot? _snapshot;
  Object? _error;
  String _query = '';
  OtherPlayersFilter _filter = const OtherPlayersFilter();
  Set<String>? _expanded;

  static const _shown = 200;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final snapshot = await _repo.load(widget.person);
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  String _groupKey(OtherTeam t) =>
      t.team == null ? 'free' : t.league?.id ?? 'other';

  Future<void> _openTeam(OtherTeam team) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => OtherTeamPage(
          person: widget.person,
          repository: _repo,
          snapshot: _snapshot!,
          teamId: team.id,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _openPlayer(OtherPlayer player) async {
    await openOtherPlayer(
      context,
      person: widget.person,
      repository: _repo,
      snapshot: _snapshot!,
      player: player,
    );
    await _reload();
  }

  Future<String?> _choose(
    String title,
    List<(String, String, Widget?)> items,
  ) => showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.of(context).background,
    builder: (context) {
      var query = '';
      final controller = TextEditingController();
      return StatefulBuilder(
        builder: (context, update) {
          final key = searchFold(query);
          final shown = [
            for (final item in items)
              if (searchFold(item.$2).contains(key)) item,
          ];
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * .7,
            child: Column(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectionSearchField(
                    controller: controller,
                    hint: 'Buscar',
                    dense: true,
                    onChanged: (value) => update(() => query = value),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) => ListTile(
                      leading: shown[i].$3,
                      title: Text(shown[i].$2),
                      onTap: () => Navigator.pop(context, shown[i].$1),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  Future<void> _openFilters() async {
    final s = _snapshot!;
    var draft = _filter;
    final leagues = s.leagues.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    final countries = <String, String>{
      for (final p in s.players)
        if (p.nationalityId != null && p.nationality.isNotEmpty)
          p.nationalityId!: p.nationality,
    };
    final applied = await showModalBottomSheet<OtherPlayersFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.of(context).background,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) {
          final c = AppColors.of(sheetContext);
          Widget title(String text) => Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 8),
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                color: c.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
              ),
            ),
          );
          OtherPlayersFilter copy({
            Set<String>? lines,
            Object? leagueId = _keep,
            Object? nationalityId = _keep,
            Object? minOverall = _keep,
            Object? maxAge = _keep,
            bool? careerOnly,
          }) => OtherPlayersFilter(
            lines: lines ?? draft.lines,
            leagueId: leagueId == _keep ? draft.leagueId : leagueId as String?,
            nationalityId: nationalityId == _keep
                ? draft.nationalityId
                : nationalityId as String?,
            minOverall: minOverall == _keep
                ? draft.minOverall
                : minOverall as int?,
            maxAge: maxAge == _keep ? draft.maxAge : maxAge as int?,
            careerOnly: careerOnly ?? draft.careerOnly,
          );
          Widget choices<T>(
            List<(T?, String)> options,
            T? selected,
            void Function(T?) pick,
          ) => Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final (value, label) in options)
                ChoiceChip(
                  label: Text(label),
                  selected: selected == value,
                  showCheckmark: false,
                  onSelected: (_) => update(() => pick(value)),
                ),
            ],
          );
          Widget picker(String label, String? value, VoidCallback onTap) =>
              Material(
                color: c.panel,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  dense: true,
                  onTap: onTap,
                  title: Text(
                    value ?? 'Todas',
                    style: TextStyle(color: c.text, fontSize: 14),
                  ),
                  subtitle: Text(label),
                  trailing: Icon(Icons.chevron_right_rounded, color: c.muted),
                ),
              );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Filtros',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    title('Posição'),
                    Wrap(
                      spacing: 7,
                      children: [
                        for (final line in positionLines)
                          FilterChip(
                            key: ValueKey('filter-line/$line'),
                            label: Text(line),
                            selected: draft.lines.contains(line),
                            showCheckmark: false,
                            onSelected: (on) => update(
                              () => draft = copy(
                                lines: on
                                    ? {...draft.lines, line}
                                    : ({...draft.lines}..remove(line)),
                              ),
                            ),
                          ),
                      ],
                    ),
                    title('Overall mínimo'),
                    choices<int>(
                      [
                        (null, 'Qualquer'),
                        for (final v in [65, 70, 75, 80, 85]) (v, '$v+'),
                      ],
                      draft.minOverall,
                      (v) => draft = copy(minOverall: v),
                    ),
                    title('Idade máxima'),
                    choices<int>(
                      [
                        (null, 'Qualquer'),
                        for (final v in [19, 21, 23, 25, 30]) (v, 'Até $v'),
                      ],
                      draft.maxAge,
                      (v) => draft = copy(maxAge: v),
                    ),
                    title('Liga'),
                    picker(
                      'Liga do clube atual',
                      s.leagues[draft.leagueId]?.label,
                      () async {
                        final id = await _choose('Liga', [
                          ('', 'Todas', null),
                          for (final l in leagues)
                            (l.id, l.label, TeamLogo.fromItem(l, size: 26)),
                        ]);
                        if (id != null) {
                          update(
                            () =>
                                draft = copy(leagueId: id.isEmpty ? null : id),
                          );
                        }
                      },
                    ),
                    title('Nacionalidade'),
                    picker(
                      'País do jogador',
                      countries[draft.nationalityId],
                      () async {
                        final sorted = countries.entries.toList()
                          ..sort((a, b) => a.value.compareTo(b.value));
                        final id = await _choose('Nacionalidade', [
                          ('', 'Todas', null),
                          for (final e in sorted) (e.key, e.value, null),
                        ]);
                        if (id != null) {
                          update(
                            () => draft = copy(
                              nationalityId: id.isEmpty ? null : id,
                            ),
                          );
                        }
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: draft.careerOnly,
                      onChanged: (v) =>
                          update(() => draft = copy(careerOnly: v)),
                      title: const Text('Só jogadores da carreira'),
                      subtitle: Text(
                        'Importados, editados ou que passaram pelo seu clube.',
                        style: TextStyle(color: c.muted, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(
                              sheetContext,
                              const OtherPlayersFilter(),
                            ),
                            child: const Text('Limpar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            key: const ValueKey('filter-apply'),
                            onPressed: () => Navigator.pop(sheetContext, draft),
                            child: const Text('Aplicar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (applied != null) setState(() => _filter = applied);
  }

  Widget _activeFilters(OtherPlayersSnapshot s) {
    final f = _filter;
    final chips = <(String, OtherPlayersFilter)>[
      for (final line in f.lines)
        (
          line,
          OtherPlayersFilter(
            lines: {...f.lines}..remove(line),
            leagueId: f.leagueId,
            nationalityId: f.nationalityId,
            minOverall: f.minOverall,
            maxAge: f.maxAge,
            careerOnly: f.careerOnly,
          ),
        ),
      if (f.minOverall != null)
        (
          'Overall ${f.minOverall}+',
          OtherPlayersFilter(
            lines: f.lines,
            leagueId: f.leagueId,
            nationalityId: f.nationalityId,
            maxAge: f.maxAge,
            careerOnly: f.careerOnly,
          ),
        ),
      if (f.maxAge != null)
        (
          'Até ${f.maxAge} anos',
          OtherPlayersFilter(
            lines: f.lines,
            leagueId: f.leagueId,
            nationalityId: f.nationalityId,
            minOverall: f.minOverall,
            careerOnly: f.careerOnly,
          ),
        ),
      if (f.leagueId != null)
        (
          s.leagues[f.leagueId]?.label ?? 'Liga',
          OtherPlayersFilter(
            lines: f.lines,
            nationalityId: f.nationalityId,
            minOverall: f.minOverall,
            maxAge: f.maxAge,
            careerOnly: f.careerOnly,
          ),
        ),
      if (f.nationalityId != null)
        (
          s.players
                  .where((p) => p.nationalityId == f.nationalityId)
                  .firstOrNull
                  ?.nationality ??
              'País',
          OtherPlayersFilter(
            lines: f.lines,
            leagueId: f.leagueId,
            minOverall: f.minOverall,
            maxAge: f.maxAge,
            careerOnly: f.careerOnly,
          ),
        ),
      if (f.careerOnly)
        (
          'Da carreira',
          OtherPlayersFilter(
            lines: f.lines,
            leagueId: f.leagueId,
            nationalityId: f.nationalityId,
            minOverall: f.minOverall,
            maxAge: f.maxAge,
          ),
        ),
    ];
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final (label, without) in chips)
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 6),
              child: InputChip(
                label: Text(label, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                onDeleted: () => setState(() => _filter = without),
              ),
            ),
          TextButton(
            onPressed: () =>
                setState(() => _filter = const OtherPlayersFilter()),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
  }

  Widget _summary(OtherPlayersSnapshot s) {
    final c = AppColors.of(context);
    final career = s.players.where((p) => !p.fromCatalog).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatStrip(
            items: [
              (
                NumberFormat.decimalPattern('pt_BR')
                    .format(s.teams.where((t) => t.team != null).length),
                'Times',
                null,
              ),
              (
                NumberFormat.decimalPattern('pt_BR').format(s.players.length),
                'Jogadores',
                null,
              ),
              (
                NumberFormat.decimalPattern('pt_BR').format(career),
                'Da carreira',
                c.accent,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Elencos da API, jogadores que você editou ou que saíram do seu clube. Times sem elenco da carreira usam o catálogo do jogo.',
            style: TextStyle(color: c.muted, fontSize: 11.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _leagueHeader(String key, OtherTeam first, int count) {
    final c = AppColors.of(context);
    final open = _expanded!.contains(key);
    final label = switch (key) {
      'free' => 'Sem clube',
      'other' => 'Outros clubes',
      _ => first.league?.label ?? 'Liga',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: c.panel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: ValueKey('other-league/$key'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(
            () => open ? _expanded!.remove(key) : _expanded!.add(key),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  height: 26,
                  child: first.league != null
                      ? TeamLogo.fromItem(first.league, size: 26)
                      : Icon(
                          key == 'free'
                              ? Icons.person_off_outlined
                              : Icons.shield_outlined,
                          size: 20,
                          color: c.muted,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  key == 'free'
                      ? '${first.players.length}'
                      : '$count ${count == 1 ? 'time' : 'times'}',
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
                Icon(
                  open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: c.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _teams(OtherPlayersSnapshot s) {
    final groups = <String, List<OtherTeam>>{};
    for (final t in s.teams) {
      (groups[_groupKey(t)] ??= []).add(t);
    }
    _expanded ??= {
      for (final entry in groups.entries)
        if (entry.key == widget.person.leagueId ||
            entry.value.any((t) => t.careerPlayers > 0))
          entry.key,
    };
    final items = <Widget Function()>[() => _summary(s)];
    for (final MapEntry(:key, value: teams) in groups.entries) {
      items.add(() => _leagueHeader(key, teams.first, teams.length));
      if (!_expanded!.contains(key)) continue;
      for (final team in teams) {
        items.add(
          () => key == 'free'
              ? Column(
                  children: [
                    for (final p in team.players.take(_shown))
                      OtherPlayerRow(
                        player: p,
                        version: widget.person.fifaVersion,
                        onTap: () => _openPlayer(p),
                      ),
                  ],
                )
              : OtherTeamTile(
                  team: team,
                  version: widget.person.fifaVersion,
                  onTap: () => _openTeam(team),
                ),
        );
      }
    }
    return ListView.builder(
      key: const PageStorageKey('other-teams'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i](),
    );
  }

  Widget _results(OtherPlayersSnapshot s) {
    final c = AppColors.of(context);
    final players = s.search(_query, _filter);
    final key = searchFold(_query);
    final teams = key.isEmpty
        ? const <OtherTeam>[]
        : s.teams
              .where((t) => t.team != null && searchFold(t.label).contains(key))
              .take(5)
              .toList();
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: c.muted,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: .6,
        ),
      ),
    );
    final items = <Widget Function()>[
      if (teams.isNotEmpty) () => heading('Times'),
      for (final t in teams)
        () => OtherTeamTile(
          team: t,
          version: widget.person.fifaVersion,
          onTap: () => _openTeam(t),
        ),
      () => heading(
        'Jogadores · ${NumberFormat.decimalPattern('pt_BR').format(players.length)}',
      ),
      if (players.isEmpty)
        () => Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Nenhum jogador encontrado. Tente outro nome, clube ou posição.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted),
          ),
        ),
      for (final p in players.take(_shown))
        () => OtherPlayerRow(
          player: p,
          version: widget.person.fifaVersion,
          onTap: () => _openPlayer(p),
        ),
      if (players.length > _shown)
        () => Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(
            'Mostrando os $_shown de maior overall. Refine a busca ou use os filtros.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
        ),
    ];
    return ListView.builder(
      key: const PageStorageKey('other-results'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i](),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _snapshot;
    final c = AppColors.of(context);
    final count = [
      _filter.lines.isNotEmpty,
      _filter.minOverall != null,
      _filter.maxAge != null,
      _filter.leagueId != null,
      _filter.nationalityId != null,
      _filter.careerOnly,
    ].where((on) => on).length;
    return Scaffold(
      appBar: AppBar(
        leading: RootDrawerScope.leading(context),
        title: const Text('Outros jogadores'),
      ),
      body: s == null
          ? Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Não foi possível carregar os elencos.'),
                          TextButton(
                            onPressed: () {
                              setState(() => _error = null);
                              _reload();
                            },
                            child: const Text('Tentar novamente'),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 14),
                        Text(
                          'Montando os elencos…',
                          style: TextStyle(color: c.muted),
                        ),
                      ],
                    ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectionSearchField(
                          key: const ValueKey('other-search'),
                          controller: _search,
                          hint: 'Jogador, clube, posição ou país',
                          dense: true,
                          onChanged: (value) => setState(() => _query = value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Badge(
                        isLabelVisible: count > 0,
                        label: Text('$count'),
                        child: IconButton.filledTonal(
                          key: const ValueKey('other-filters'),
                          tooltip: 'Filtros',
                          onPressed: _openFilters,
                          icon: const Icon(Icons.tune_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_filter.active) _activeFilters(s),
                Expanded(
                  child: _query.trim().isEmpty && !_filter.active
                      ? _teams(s)
                      : _results(s),
                ),
              ],
            ),
    );
  }
}

const _keep = Object();
