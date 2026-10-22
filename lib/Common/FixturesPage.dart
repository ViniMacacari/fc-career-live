import '../utils/AppColors.dart';

import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../ManagerCareer/Fixtures/CreateManagerFixturePage.dart';
import '../FcScore/FcScoreCareerUpdate.dart';
import '../ManagerCareer/Fixtures/ViewManagerFixturePage.dart';
import '../PlayerCareer/Fixtures/AddPlayerFixture.dart';
import '../PlayerCareer/Fixtures/ViewPlayerFixturePage.dart';
import '../RootPage/DrawerWidget.dart';
import '../models/Person.dart';
import '../models/Season.dart';
import '../utils/Components/CareerUiStyle.dart';
import '../utils/Components/ManagerFormStyle.dart';
import '../utils/Components/TeamLogo.dart';
import '../utils/GameCatalog.dart';
import '../utils/SqlService.dart';
import 'FixtureHomeMatchCard.dart';
import 'FixtureCalendar.dart';
import 'FixtureResultTile.dart';
import 'FixturesInsights.dart';
import 'Seasons/CreateSeason.dart';
import 'Seasons/SeasonArchivePage.dart';

class FixturesData {
  const FixturesData(
    this.seasons,
    this.rows,
    this.redCards,
    this.catalog,
    this.tournaments,
    this.logos,
  );
  final List<Season> seasons;
  final List<Map<String, Object?>> rows;
  final Map<String, int> redCards;
  final GameCatalog catalog;
  final Map<String, String> tournaments, logos;

  static Future<FixturesData> load(Person person) async {
    final service = SqlService.instance;
    final seasons = await service.getSeasons(person.id);
    final rows = await service.getFixtures(person.id, person.category);
    final catalog = await GameCatalog.load();
    final tournaments = await catalog.tournaments(person.fifaVersion);
    final custom = await service.getCustomTournaments(person.fifaVersion);
    return FixturesData(
      seasons,
      rows,
      person.category == PersonCategory.manager
          ? await service.getManagerFixtureRedCards(person.id)
          : const {},
      catalog,
      {
        for (final t in tournaments) t.id: t.label,
        for (final t in custom) t.id: t.name,
        for (final league in catalog.leagues(person.fifaVersion))
          'league:${league.id}': league.label,
      },
      {
        for (final t in tournaments)
          if (t.assetPath != null) t.id: t.assetPath!,
      },
    );
  }
}

class FixturesPage extends StatefulWidget {
  const FixturesPage({super.key, required this.person, this.load});
  final Person person;
  final Future<FixturesData> Function(Person)? load;
  @override
  State<FixturesPage> createState() => _FixturesPageState();
}

class _FixturesPageState extends State<FixturesPage> {
  String? _seasonId, _tournamentFilter, _locationFilter;
  String _viewMode = 'list';
  bool _selectNewest = true;
  bool _summaryExpanded = false;
  final _scroll = ScrollController();
  String _section = 'games';
  late Future<FixturesData> _data = _load();
  bool get _isManager => widget.person.category == PersonCategory.manager;
  CareerUiColors get _c => CareerUiColors(context);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<FixturesData> _load() async {
    final data = await (widget.load ?? FixturesData.load)(widget.person);
    if (_isManager && _selectNewest && data.seasons.isNotEmpty) {
      _seasonId = data.seasons.first.id;
      _selectNewest = false;
    }
    return data;
  }

  Future<void> _reload() async {
    final future = _load();
    setState(() {
      _data = future;
    });
    try {
      await future;
    } catch (_) {}
  }

  void _top() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  List<Map<String, Object?>> _visibleRows(FixturesData data) =>
      data.rows
          .where(
            (row) =>
                (_seasonId == null || row['seasonId'] == _seasonId) &&
                (_tournamentFilter == null ||
                    row['tournamentId'] == _tournamentFilter) &&
                (_locationFilter == null || row['location'] == _locationFilter),
          )
          .toList()
        ..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));

  Future<void> _create() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _isManager
            ? CreateManagerFixturePage(
                person: widget.person,
                seasonId: _seasonId,
              )
            : AddPlayerFixture(person: widget.person),
      ),
    );
    if (created == true && mounted) await _reload();
  }

  Future<void> _open(Map<String, Object?> row, FixturesData data) async {
    final opponent = data.catalog.teamLabel(
      widget.person.fifaVersion,
      '${row['oppositeTeamId']}',
      leagueId: row['oppositeTeamLeagueId']?.toString(),
    );
    final tournament =
        data.tournaments[row['tournamentId']] ?? '${row['tournamentId']}';
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _isManager
            ? ViewManagerFixturePage(
                person: widget.person,
                fixture: row,
                opponent: opponent,
                tournament: tournament,
                tournamentLogo: data.logos[row['tournamentId']],
              )
            : ViewPlayerFixturePage(
                person: widget.person,
                fixture: row,
                opponent: opponent,
                tournament: tournament,
                tournamentLogo: data.logos[row['tournamentId']],
              ),
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _createSeason() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CreateSeasonPage(personId: widget.person.id, person: widget.person),
      ),
    );
    if (mounted) {
      if (created == true) {
        _seasonId = null;
        _selectNewest = true;
        _tournamentFilter = _locationFilter = null;
      }
      await _reload();
    }
  }

  String _seasonLabel(Season season) =>
      season.startDate.year == season.endDate.year
      ? '${season.startDate.year}'
      : '${season.startDate.year}/${season.endDate.year}';

  Future<void> _selectSeason(FixturesData data) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 12),
              child: Text(
                'seasons.selectSeason'.tr(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.history_rounded, color: _c.accent),
              title: Text('seasons.allSeasons'.tr()),
              trailing: _seasonId == null
                  ? Icon(Icons.check_circle_rounded, color: _c.accent)
                  : null,
              onTap: () => Navigator.pop(sheetContext, 'all'),
            ),
            for (final season in data.seasons)
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                tileColor: season.id == _seasonId
                    ? _c.accent.withValues(alpha: .1)
                    : null,
                leading: Icon(Icons.calendar_month_outlined, color: _c.muted),
                title: Text(_seasonLabel(season)),
                trailing: season.id == _seasonId
                    ? Icon(Icons.check_circle_rounded, color: _c.accent)
                    : null,
                onTap: () => Navigator.pop(sheetContext, season.id),
              ),
            const SizedBox(height: 10),
            ListTile(
              leading: Icon(Icons.auto_awesome_outlined, color: _c.accent),
              title: const Text('Temporadas e retrospectivas'),
              onTap: () => Navigator.pop(sheetContext, 'archive'),
            ),
            ListTile(
              leading: Icon(Icons.add_circle_outline_rounded, color: _c.accent),
              title: Text('seasons.createSeason'.tr()),
              onTap: () => Navigator.pop(sheetContext, 'new'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected == 'archive') {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => SeasonArchivePage(person: widget.person),
        ),
      );
      if (mounted) await _reload();
      return;
    }
    if (selected == 'new') {
      await _createSeason();
      return;
    }
    _top();
    setState(() {
      _seasonId = selected == 'all' ? null : selected;
      _selectNewest = false;
      _tournamentFilter = _locationFilter = null;
    });
  }

  Future<void> _showFilters(FixturesData data) async {
    var competition = _tournamentFilter, location = _locationFilter;
    final ids = data.rows
        .where((r) => _seasonId == null || r['seasonId'] == _seasonId)
        .map((r) => r['tournamentId']?.toString())
        .whereType<String>()
        .toSet();
    final selected =
        await showModalBottomSheet<({String? competition, String? location})>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          builder: (sheetContext) => StatefulBuilder(
            builder: (context, update) => SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Filtrar partidas',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => update(() {
                            competition = location = null;
                          }),
                          child: const Text('Limpar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      key: ValueKey('competition/$competition'),
                      initialValue: competition ?? '',
                      isExpanded: true,
                      decoration: managerFieldDecoration(
                        context,
                        'tournaments.tournament'.tr(),
                        icon: Icons.emoji_events_outlined,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text('tournaments.allTournaments'.tr()),
                        ),
                        for (final id in ids)
                          DropdownMenuItem(
                            value: id,
                            child: Text(
                              data.tournaments[id] ?? id,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) =>
                          update(() => competition = v == '' ? null : v),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: ValueKey('location/$location'),
                      initialValue: location ?? '',
                      decoration: managerFieldDecoration(
                        context,
                        'Mando de campo',
                        icon: Icons.stadium_outlined,
                      ),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('Todos')),
                        DropdownMenuItem(value: 'home', child: Text('Em casa')),
                        DropdownMenuItem(
                          value: 'away',
                          child: Text('Fora de casa'),
                        ),
                        DropdownMenuItem(
                          value: 'neutral',
                          child: Text('Campo neutro'),
                        ),
                      ],
                      onChanged: (v) =>
                          update(() => location = v == '' ? null : v),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, (
                          competition: competition,
                          location: location,
                        )),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text('common.apply'.tr()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    if (selected != null && mounted) {
      _top();
      setState(() {
        _tournamentFilter = selected.competition;
        _locationFilter = selected.location;
      });
    }
  }

  Widget _formBadge(FixtureResult result) {
    final color = switch (result) {
      FixtureResult.win => AppColors.of(context).success,
      FixtureResult.draw => AppColors.of(context).warning,
      FixtureResult.lose => AppColors.of(context).danger,
    };
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Text(
        switch (result) {
          FixtureResult.win => 'V',
          FixtureResult.draw => 'E',
          FixtureResult.lose => 'D',
        },
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _hero(FixturesData data, List<Map<String, Object?>> rows) {
    final compact = MediaQuery.sizeOf(context).height < 740;
    final latest = rows.firstOrNull;
    final teamId = latest?['playerTeamId']?.toString() ?? widget.person.teamId;
    final leagueId =
        latest?['playerTeamLeagueId']?.toString() ?? widget.person.leagueId;
    final team = data.catalog.team(
      widget.person.fifaVersion,
      teamId,
      leagueId: leagueId,
    );
    final season = data.seasons.where((s) => s.id == _seasonId).firstOrNull;
    final date = DateTime.tryParse(latest?['date']?.toString() ?? '');
    final results = rows.map(fixtureResult).toList();
    final counts = [
      for (final result in FixtureResult.values)
        results.where((r) => r == result).length,
    ];
    if (!_summaryExpanded) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 12),
        decoration: _c.surface(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TeamLogo.fromItem(team, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    team?.label ?? widget.person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('fixtures-summary-expand'),
                  tooltip: 'Expandir resumo',
                  onPressed: () => setState(() => _summaryExpanded = true),
                  icon: const Icon(Icons.expand_more_rounded),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    key: const ValueKey('fixture-season'),
                    onTap: () => _selectSeason(data),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_month_outlined,
                            color: _c.accent,
                            size: 17,
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              season == null
                                  ? 'seasons.allSeasons'.tr()
                                  : 'Temporada ${_seasonLabel(season)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.expand_more_rounded,
                            color: _c.muted,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${rows.length}',
                  key: const ValueKey('fixture-count'),
                  style: TextStyle(
                    color: _c.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                Text('jogos', style: TextStyle(color: _c.muted, fontSize: 12)),
                const SizedBox(width: 6),
              ],
            ),
          ],
        ),
      );
    }
    return Container(
      padding: EdgeInsets.all(compact ? 18 : 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _isManager
              ? [AppColors.of(context).headerStart, AppColors.of(context).panel]
              : [
                  AppColors.of(context).headerStart,
                  AppColors.of(context).panel,
                ],
        ),
        border: Border.all(color: _c.accent.withValues(alpha: .3)),
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
                      'CENTRAL DE PARTIDAS',
                      style: TextStyle(
                        color: _isManager
                            ? AppColors.of(context).accent
                            : AppColors.of(context).accent,
                        fontSize: 10,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      team?.label ?? widget.person.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                        color: AppColors.of(context).text,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              TeamLogo.fromItem(team, size: 48),
              IconButton(
                key: const ValueKey('fixtures-summary-collapse'),
                tooltip: 'Recolher resumo',
                onPressed: () => setState(() => _summaryExpanded = false),
                icon: const Icon(Icons.expand_less_rounded),
              ),
            ],
          ),
          SizedBox(height: compact ? 12 : 18),
          InkWell(
            key: const ValueKey('fixture-season'),
            onTap: () => _selectSeason(data),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.of(context).text.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.of(context).text.withValues(alpha: .15),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_month_outlined,
                    color: AppColors.of(context).muted,
                    size: 17,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      season == null
                          ? 'seasons.allSeasons'.tr()
                          : 'Temporada ${_seasonLabel(season)}',
                      style: TextStyle(
                        color: AppColors.of(context).text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.expand_more_rounded,
                    color: AppColors.of(context).muted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_section != 'games')
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                children: [
                  Text(
                    '${rows.length}',
                    key: const ValueKey('fixture-count'),
                    style: TextStyle(
                      color: AppColors.of(context).text,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'partidas no período selecionado',
                      style: TextStyle(
                        color: AppColors.of(context).muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            SizedBox(height: compact ? 16 : 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '${rows.length}',
                  key: const ValueKey('fixture-count'),
                  style: TextStyle(
                    color: AppColors.of(context).text,
                    fontSize: compact ? 34 : 44,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'jogos registrados\nno período selecionado',
                    style: TextStyle(
                      color: AppColors.of(context).muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 12 : 20),
            Divider(height: 1, color: AppColors.of(context).line),
            SizedBox(height: compact ? 12 : 16),
            Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${counts[i]}',
                          style: TextStyle(
                            color: [
                              AppColors.of(context).success,
                              AppColors.of(context).warning,
                              AppColors.of(context).danger,
                            ][i],
                            fontSize: compact ? 20 : 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ['Vitórias', 'Empates', 'Derrotas'][i],
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
            if (rows.isNotEmpty) ...[
              SizedBox(height: compact ? 12 : 18),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Últimos jogos',
                    style: TextStyle(
                      color: AppColors.of(context).muted,
                      fontSize: 10,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final result in results.take(5).toList().reversed)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _formBadge(result),
                        ),
                    ],
                  ),
                ],
              ),
              if (date != null && !compact)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Carreira em ${DateFormat('dd/MM/yyyy').format(date)}',
                    style: TextStyle(
                      color: AppColors.of(context).muted,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _controls(FixturesData data) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(5),
        decoration: _c.surface(radius: 16),
        child: Row(
          children: [
            for (final (id, label, icon) in [
              ('games', 'Jogos', Icons.sports_soccer_outlined),
              ('summary', 'Resumo', Icons.dashboard_outlined),
              ('charts', 'Gráficos', Icons.insights_rounded),
            ])
              Expanded(
                child: Material(
                  color: _section == id
                      ? _c.accent.withValues(alpha: .16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    key: ValueKey('fixtures-section-$id'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      _top();
                      setState(() => _section = id);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 4,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 16,
                            color: _section == id ? _c.accent : _c.muted,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _section == id ? _c.accent : _c.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: Text(
              switch (_section) {
                'summary' => 'Resumo do período',
                'charts' => 'Gráficos do período',
                _ => 'Histórico de jogos',
              },
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          TextButton.icon(
            onPressed: () => _showFilters(data),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: Text(
              _tournamentFilter != null || _locationFilter != null
                  ? 'Filtrados'
                  : 'Filtros',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (_section == 'games')
        Container(
          padding: const EdgeInsets.all(5),
          decoration: _c.surface(radius: 16),
          child: Row(
            children: [
              for (final mode in [
                ('list', 'Lista', Icons.view_agenda_outlined),
                ('calendar', 'Calendário', Icons.calendar_month_outlined),
              ])
                Expanded(
                  child: Material(
                    color: _viewMode == mode.$1
                        ? _c.accent.withValues(alpha: .16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      key: ValueKey('view-${mode.$1}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        _top();
                        setState(() => _viewMode = mode.$1);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              mode.$3,
                              size: 20,
                              color: _viewMode == mode.$1
                                  ? _c.accent
                                  : _c.muted,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                mode.$2,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _viewMode == mode.$1
                                      ? _c.accent
                                      : _c.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      if (_tournamentFilter != null || _locationFilter != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_tournamentFilter == null ? '' : data.tournaments[_tournamentFilter] ?? _tournamentFilter} ${_locationFilter == null
                      ? ''
                      : _locationFilter == 'home'
                      ? '· Em casa'
                      : _locationFilter == 'away'
                      ? '· Fora de casa'
                      : '· Campo neutro'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: _c.accent),
                ),
              ),
              TextButton(
                onPressed: () {
                  _top();
                  setState(() => _tournamentFilter = _locationFilter = null);
                },
                child: const Text('Limpar', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _empty(FixturesData data) => Container(
    padding: const EdgeInsets.all(26),
    decoration: _c.surface(),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.sports_soccer_outlined, size: 44, color: _c.accent),
        const SizedBox(height: 18),
        Text(
          data.seasons.isEmpty
              ? 'Sua temporada começa aqui'
              : 'Nenhum jogo neste recorte',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 9),
        Text(
          data.seasons.isEmpty
              ? 'Crie uma temporada e comece a contar a história do time.'
              : 'Registre uma partida ou ajuste os filtros para explorar outros jogos.',
          style: TextStyle(color: _c.muted, fontSize: 12, height: 1.6),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: data.seasons.isEmpty ? _createSeason : _create,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(
            data.seasons.isEmpty ? 'Criar temporada' : 'Nova partida',
          ),
        ),
      ],
    ),
  );

  Widget _game(Map<String, Object?> row, FixturesData data) =>
      FixtureHomeMatchCard(
        person: widget.person,
        fixture: row,
        tournament:
            data.tournaments[row['tournamentId']] ?? '${row['tournamentId']}',
        redCards: data.redCards[row['id']] ?? 0,
        onTap: () => _open(row, data),
      );

  List<Widget> _gameSlivers(
    List<Map<String, Object?>> rows,
    FixturesData data,
  ) {
    if (_viewMode == 'calendar') {
      return [
        SliverToBoxAdapter(
          child: FixtureCalendar(
            rows: rows,
            locale: context.locale.toString(),
            matchBuilder: (row) => _game(row, data),
          ),
        ),
      ];
    }
    final groups = groupByConsecutiveTournament(
      rows,
      (r) => '${r['tournamentId']}',
    );
    return [
      SliverList.builder(
        itemCount: groups.length,
        itemBuilder: (_, i) {
          final group = groups[i], first = group.first;
          final label =
              data.tournaments[first['tournamentId']] ??
              '${first['tournamentId']}';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 18, 4, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.emoji_events_outlined,
                      color: _c.accent,
                      size: 18,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${group.length} jogos',
                      style: TextStyle(color: _c.muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              for (final row in group) _game(row, data),
            ],
          );
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: RootDrawerScope.leading(context),
      title: Text('sections.fixtures'.tr()),
      actions: [
        FcScoreCareerUpdateButton(
          person: widget.person,
          onUpdated: _reload,
          refreshToken: _data,
        ),
        FutureBuilder<FixturesData>(
          future: _data,
          builder: (context, snapshot) => IconButton(
            tooltip: 'seasons.selectSeason'.tr(),
            onPressed: snapshot.hasData
                ? () => _selectSeason(snapshot.data!)
                : null,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      tooltip: 'fixtures.addFixture'.tr(),
      backgroundColor: _c.accent,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      elevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Icons.add_rounded),
      label: const Text(
        'Nova partida',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
    ),
    body: FutureBuilder<FixturesData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Não foi possível carregar as partidas.'),
                TextButton(
                  onPressed: _reload,
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!, rows = _visibleRows(data);
        return LayoutBuilder(
          builder: (context, box) {
            final inset = math.max(16.0, (box.maxWidth - 900) / 2);
            return RefreshIndicator(
              onRefresh: _reload,
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(inset, 8, inset, 20),
                    sliver: SliverToBoxAdapter(
                      child: AnimatedSize(
                        key: const ValueKey('fixtures-home-summary'),
                        duration: const Duration(milliseconds: 200),
                        alignment: Alignment.topCenter,
                        child: _hero(data, rows),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: inset),
                    sliver: SliverToBoxAdapter(child: _controls(data)),
                  ),
                  if (rows.isEmpty)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(inset, 20, inset, 120),
                      sliver: SliverToBoxAdapter(child: _empty(data)),
                    )
                  else if (_section == 'games')
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(inset, 4, inset, 120),
                      sliver: SliverMainAxisGroup(
                        slivers: _gameSlivers(rows, data),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(inset, 4, inset, 120),
                      sliver: SliverToBoxAdapter(
                        child: FixturesInsights(
                          charts: _section == 'charts',
                          rows: rows,
                          onOpen: (row) => _open(row, data),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}
