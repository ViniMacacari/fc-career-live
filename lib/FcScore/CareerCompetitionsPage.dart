import 'package:flutter/material.dart';

import '../models/Person.dart';
import '../models/Season.dart';
import '../RootPage/DrawerWidget.dart';
import '../utils/Components/CareerUiStyle.dart';
import '../utils/Components/PlayerAvatar.dart';
import '../utils/Components/TeamLogo.dart';
import '../utils/GameCatalog.dart';
import 'FcScoreApi.dart';
import 'FcScoreModels.dart';
import 'FcScoreSeasonStats.dart';
import 'FcScoreRepository.dart';
import 'FcScoreWidgets.dart';
import 'FcScoreCareerIdentity.dart';
import 'FcScoreCompetitionStructure.dart';
import 'CareerCompetitionWidgets.dart';
import 'FcScoreStandingZones.dart';
import '../Common/FixtureDetailsPage.dart';

class CareerCompetitionsPage extends StatefulWidget {
  const CareerCompetitionsPage({
    super.key,
    required this.person,
    this.repository,
    this.initialSeasonId,
  });
  final Person person;
  final FcScoreRepository? repository;
  final String? initialSeasonId;
  @override
  State<CareerCompetitionsPage> createState() => _CareerCompetitionsPageState();
}

class _CareerCompetitionsPageState extends State<CareerCompetitionsPage> {
  late final _repo = widget.repository ?? FcScoreRepository();
  late Future<void> _future = _load();
  FcScoreCareerIdentity? _identity;
  List<FcJson> _competitions = [];
  List<Season> _seasons = [];
  String? _seasonId;
  Future<void> _load() async {
    _identity = await FcScoreCareerIdentity.load(_repo.sql, widget.person);
    _competitions = await _repo.careerCompetitions(widget.person.id);
    _seasons = await _repo.sql.getSeasons(widget.person.id);
    _seasonId ??=
        widget.initialSeasonId ??
        _competitions.firstOrNull?['seasonId'] as String?;
    if (mounted) setState(() {});
  }

  String _seasonLabel(String? id) {
    final s = _seasons.where((s) => s.id == id).firstOrNull;
    return s == null
        ? 'Selecionar temporada'
        : s.startDate.year == s.endDate.year
        ? '${s.startDate.year}'
        : '${s.startDate.year}/${s.endDate.year}';
  }

  Future<void> _chooseSeason() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (c) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 4, 8, 16),
            child: Text(
              'Selecionar temporada',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
          ),
          for (final s in _seasons)
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: Text(_seasonLabel(s.id)),
              trailing: s.id == _seasonId
                  ? const Icon(Icons.check_circle_rounded)
                  : null,
              onTap: () => Navigator.pop(c, s.id),
            ),
        ],
      ),
    );
    if (selected != null && mounted) setState(() => _seasonId = selected);
  }

  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    return Scaffold(
      appBar: AppBar(
        leading: RootDrawerScope.leading(context),
        title: const Text('Classificação'),
        actions: [
          IconButton(
            key: const Key('classification-season'),
            tooltip: 'Selecionar temporada',
            onPressed: _seasons.isEmpty ? null : _chooseSeason,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = _competitions
              .where((r) => r['seasonId'] == _seasonId)
              .toList();
          return SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                setState(() => _future = _load());
                await _future;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Temporada ${_seasonLabel(_seasonId)}',
                            style: TextStyle(
                              color: c.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Text(
                          '${rows.length} competições',
                          style: TextStyle(color: c.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (_competitions.isEmpty)
                    const FcNotice(
                      'Conecte o FC Score e toque em “Atualizar carreira” para trazer as competições desta temporada.',
                    ),
                  if (_competitions.isNotEmpty && rows.isEmpty)
                    const FcNotice(
                      'Nenhuma competição nesta temporada. Escolha outra temporada pelo calendário.',
                    ),
                  for (final row in rows) _competitionCard(row),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _competitionCard(FcJson row) {
    final c = CareerUiColors(context), item = _identity!.competition(row);
    final stages = fcCompetitionStages(fcObject(row['data']), []);
    final knockout = stages.any((s) => s.kind == FcStageKind.knockout);
    final groups = stages.any((s) => s.kind == FcStageKind.groups);
    final type = knockout
        ? groups
              ? 'Grupos e mata-mata'
              : 'Mata-mata'
        : groups
        ? 'Fase de grupos'
        : 'Liga';
    return CareerCompetitionSurface(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CareerCompetitionPage(
            person: widget.person,
            repository: _repo,
            competition: row,
          ),
        ),
      ),
      child: Row(
        children: [
          careerCompetitionLogo(item),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item?.label ?? fcName(row['name']),
                  style: TextStyle(
                    color: c.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  type,
                  style: TextStyle(
                    color: c.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Atualizada em ${fcDay(row['currentDate'])}',
                  style: TextStyle(color: c.muted, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: c.accent, size: 22),
        ],
      ),
    );
  }
}

class CareerCompetitionPage extends StatefulWidget {
  const CareerCompetitionPage({
    super.key,
    required this.person,
    required this.repository,
    required this.competition,
  });
  final Person person;
  final FcScoreRepository repository;
  final FcJson competition;
  @override
  State<CareerCompetitionPage> createState() => _CareerCompetitionPageState();
}

class _CareerCompetitionPageState extends State<CareerCompetitionPage>
    with SingleTickerProviderStateMixin {
  late final Future<void> _future = _load();
  late final _tabs = TabController(length: 4, vsync: this)
    ..addListener(_tabChanged);
  FcScoreCareerIdentity? _identity;
  FcScoreLink? _link;
  List<FcJson> _teams = [], _fixtures = [];
  List<FcCompetitionStage> _stages = [];
  String? _stageId;
  Future<FcCompetitionScorers>? _scorers;
  String _statMetric = 'goals', _filter = 'Todos', _teamSearch = '';
  final _teamNames = <String, String>{}, _items = <String, CatalogItem>{};
  final _participants = <String>{};
  int _fixtureLimit = 50;
  Map<String, String> _fixtureLinks = {}, _competitionLinks = {};
  bool _openingFixture = false;
  String get _season => fcId(widget.competition['seasonId']);
  Future<void> _load() async {
    final repo = widget.repository;
    _identity = await FcScoreCareerIdentity.load(repo.sql, widget.person);
    _link = await repo.linkFor(widget.person.id);
    _teams = await repo.careerTeams(
      widget.person.id,
      _season,
      includeRosters: false,
    );
    _fixtures = await repo.competitionFixtures(
      widget.person.id,
      _season,
      fcId(widget.competition['remoteId']),
    );
    _fixtureLinks = await repo.competitionFixtureLinks(
      widget.person,
      _season,
      fcId(widget.competition['remoteId']),
    );
    _competitionLinks = {
      for (final c in await (await repo.sql.database).query(
        'FcScoreCompetition',
        columns: ['remoteId', 'tournamentId'],
        where: 'personId = ? AND seasonId = ?',
        whereArgs: [widget.person.id, _season],
      ))
        fcId(c['remoteId']): fcId(c['tournamentId']),
      ...?_link?.competitions,
    };
    for (final t in _teams) {
      final id = fcId(t['remoteId']);
      final item = _identity!.club(fcId(t['teamId']), fcId(t['leagueId']));
      if (item != null) _items[id] = item;
      _teamNames[id] = item?.label ?? fcName(fcObject(t['data'])['name']);
    }
    _stages = fcCompetitionStages(
      fcObject(widget.competition['data']),
      _fixtures,
    );
    _stageId =
        (_stages.where((s) => s.played).lastOrNull ?? _stages.firstOrNull)?.id;
    for (final stage in _stages) {
      for (final group in stage.groups) {
        for (final r in fcList(group['rows'])) {
          _participants.add(fcId(fcObject(r['team'])['id']));
        }
      }
    }
    for (final row in _fixtures) {
      for (final side in ['home', 'away']) {
        _participants.add(
          fcId(fcObject(fcObject(fcObject(row['data'])[side])['team'])['id']),
        );
      }
    }
    for (final s in fcList(
      fcObject(widget.competition['data'])['playerStats'],
    )) {
      _participants.add(fcId(fcObject(s['team'])['id']));
    }
    if (mounted) setState(() {});
  }

  void _tabChanged() {
    if (_tabs.index == 2 && _scorers == null) {
      setState(() {
        _scorers = widget.repository.competitionScorers(
          widget.person,
          widget.competition,
        );
      });
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String _name(String id) => _teamNames[id] ?? 'Equipe';
  Widget _logo(String id, double size) =>
      TeamLogo.fromItem(_items[id], size: size);
  bool _own(String id) => _teams.any(
    (t) => fcId(t['remoteId']) == id && t['teamId'] == widget.person.teamId,
  );
  Future<void> _roster(String id) async {
    final data = _teams.where((t) => fcId(t['remoteId']) == id).firstOrNull;
    if (data == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CareerRosterPage(
          person: widget.person,
          repository: widget.repository,
          seasonId: _season,
          team: data,
          name: _name(id),
          identity: _identity!,
          link: _link,
        ),
      ),
    );
  }

  String _zoneLabel(FcStandingZone zone) => zone.label(
    competitionName: (ref) =>
        _identity!.competitions[_competitionLinks[fcId(ref['id'])]]?.label ??
        fcName(ref['name'], 'Competição internacional'),
    leagueName: (ref) =>
        _identity!
            .competitions['league:${_link?.leagues[fcId(ref['id'])]}']
            ?.label ??
        fcName(ref['name'], ''),
  );

  Future<void> _openFixture(String id, FcJson world) async {
    if (_openingFixture) return;
    _openingFixture = true;
    try {
      final fixture = await widget.repository.sql.getFixture(
        widget.person.category,
        widget.person.id,
        id,
      );
      if (!mounted) return;
      if (fixture == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Esta partida foi removida da carreira.'),
          ),
        );
        return;
      }
      final opponent = _identity!.club(
        fcId(fixture['oppositeTeamId']),
        fcId(fixture['oppositeTeamLeagueId']),
      );
      final ownHome = fixture['location'] == 'home';
      final otherId = fcId(
        fcObject(
          fcObject(fcObject(world['data'])[ownHome ? 'away' : 'home'])['team'],
        )['id'],
      );
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => FixtureDetailsPage(
            person: widget.person,
            fixture: fixture,
            opponent: opponent?.label ?? _name(otherId),
            tournament:
                _identity!.competitions[fcId(fixture['tournamentId'])]?.label ??
                fcName(widget.competition['name']),
            sql: widget.repository.sql,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível abrir esta partida. Tente novamente.',
            ),
          ),
        );
      }
    } finally {
      _openingFixture = false;
      if (mounted) {
        final links = await widget.repository.competitionFixtureLinks(
          widget.person,
          _season,
          fcId(widget.competition['remoteId']),
        );
        if (mounted) setState(() => _fixtureLinks = links);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        _identity?.competition(widget.competition)?.label ??
            fcName(widget.competition['name']),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: TabBar(
            controller: _tabs,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            labelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            tabs: const [
              Tab(
                child: FittedBox(fit: BoxFit.scaleDown, child: Text('Tabela')),
              ),
              Tab(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Partidas'),
                ),
              ),
              Tab(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Artilharia'),
                ),
              ),
              Tab(
                child: FittedBox(fit: BoxFit.scaleDown, child: Text('Equipes')),
              ),
            ],
          ),
        ),
      ),
    ),
    body: SafeArea(
      child: FutureBuilder<void>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return TabBarView(
            controller: _tabs,
            children: [_tables(), _matches(), _goals(), _clubs()],
          );
        },
      ),
    ),
  );
  Widget _tables() {
    final c = CareerUiColors(context),
        stage = _stages.where((s) => s.id == _stageId).firstOrNull;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_stages.length > 1) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('competition-phase-$_stageId'),
            initialValue: _stageId,
            isExpanded: true,
            decoration: fcInput('Fase', icon: Icons.account_tree_outlined),
            items: [
              for (final s in _stages)
                DropdownMenuItem(
                  value: s.id,
                  child: Text(s.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) => setState(() => _stageId = id),
          ),
          const SizedBox(height: 18),
        ],
        if (stage != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  stage.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: c.text,
                  ),
                ),
              ),
              Text(
                stage.kind == FcStageKind.knockout
                    ? 'Mata-mata'
                    : 'Classificação',
                style: TextStyle(
                  fontSize: 10,
                  color: c.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        const SizedBox(height: 6),
        Text(
          'Atualizada em ${fcDay(widget.competition['currentDate'])}',
          style: TextStyle(color: c.muted, fontSize: 10),
        ),
        const SizedBox(height: 18),
        if (stage == null)
          const FcNotice('Classificação indisponível. Consulte as partidas.'),
        if (stage?.kind == FcStageKind.knockout) ...[
          if (stage!.ties.isEmpty)
            const FcNotice(
              'Os confrontos desta fase ainda não foram definidos.',
            ),
          for (final tie in stage.ties)
            CareerKnockoutCard(
              tie: tie,
              name: _name,
              logo: _logo,
              onTeam: _roster,
            ),
        ] else if (stage != null) ...[
          if (stage.groups.isEmpty)
            const FcNotice('Tabela ainda indisponível para esta fase.'),
          for (final (index, group) in stage.groups.indexed) ...[
            if (stage.groups.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 12),
                child: Text(
                  'Grupo ${fcId(group['code']).isEmpty ? index + 1 : fcId(group['code']).replaceFirst(RegExp(r'^G'), '')}',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            CareerStandingsTable(
              key: ValueKey('${stage.id}:${group['id'] ?? group['code']}'),
              rows: fcList(group['rows']),
              zones: fcList(group['zones']),
              zoneLabel: _zoneLabel,
              name: _name,
              logo: _logo,
              onTeam: _roster,
              isOwn: _own,
            ),
          ],
        ],
      ],
    );
  }

  Widget _matches() {
    final rows = _fixtures
        .where(
          (f) =>
              _filter == 'Todos' ||
              (_filter == 'Resultados' ? f['played'] == 1 : f['played'] == 0),
        )
        .toList();
    if (_filter == 'Resultados') {
      rows.sort((a, b) => fcId(b['date']).compareTo(fcId(a['date'])));
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in ['Todos', 'Resultados', 'Próximos'])
              ChoiceChip(
                label: Text(s),
                selected: s == _filter,
                onSelected: (_) => setState(() {
                  _filter = s;
                  _fixtureLimit = 50;
                }),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (rows.isEmpty) const FcNotice('Nenhuma partida neste filtro.'),
        for (final f in rows.take(_fixtureLimit))
          CareerCompetitionMatchCard(
            key: ValueKey('competition-match-${f['remoteKey']}'),
            fixture: fcObject(f['data']),
            name: _name,
            logo: _logo,
            onTap: _fixtureLinks[fcId(f['remoteKey'])] == null
                ? null
                : () => _openFixture(_fixtureLinks[fcId(f['remoteKey'])]!, f),
          ),
        if (rows.length > _fixtureLimit)
          OutlinedButton(
            onPressed: () => setState(() => _fixtureLimit += 50),
            child: Text(
              'Mostrar mais · ${rows.length - _fixtureLimit} restantes',
            ),
          ),
      ],
    );
  }

  Widget _goals() => FutureBuilder<FcCompetitionScorers>(
    future: _scorers,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FcNotice('Não foi possível carregar a artilharia.'),
              OutlinedButton(
                onPressed: () => setState(() {
                  _scorers = widget.repository.competitionScorers(
                    widget.person,
                    widget.competition,
                  );
                }),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final scorers = snapshot.data!, c = CareerUiColors(context);
      final ranking = scorers.complete
          ? fcRankStats(scorers.statistics, _statMetric)
          : scorers.players;
      final metric = scorers.complete ? _statMetric : 'goals';
      return ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: ranking.isEmpty ? 2 : ranking.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              children: [
                if (!scorers.complete) FcNotice(scorers.notice),
                if (scorers.complete)
                  DropdownButtonFormField<String>(
                    initialValue: _statMetric,
                    isExpanded: true,
                    decoration: fcInput(
                      'Estatística',
                      icon: Icons.bar_chart_rounded,
                    ),
                    items: [
                      for (final e in fcStatLabels.entries)
                        DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _statMetric = v);
                    },
                  ),
                const SizedBox(height: 18),
              ],
            );
          }
          if (ranking.isEmpty) {
            return FcNotice(
              metric == 'goals'
                  ? 'Nenhum gol registrado nos dados disponíveis.'
                  : 'Nenhum registro para esta estatística.',
            );
          }
          final p = ranking[index - 1], id = fcId(p['remoteTeamId']);
          return CareerCompetitionSurface(
            onTap: () => _roster(id),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '$index',
                    style: TextStyle(
                      color: index <= 3 ? c.accent : c.muted,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fcName(p['name']),
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          _logo(id, 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _teamNames[id] ?? fcName(p['teamName']),
                              style: TextStyle(color: c.muted, fontSize: 10),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${fcValue(p['appearances'])} jogos',
                        style: TextStyle(color: c.muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      metric == 'averageRating'
                          ? fcNumber(p[metric])?.toStringAsFixed(2) ?? '—'
                          : fcValue(p[metric]),
                      style: TextStyle(
                        color: c.accent,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                    if (metric == 'goals' || metric == 'averageRating')
                      Text(
                        metric == 'goals' ? 'gols' : 'nota',
                        style: TextStyle(fontSize: 9, color: c.muted),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
  Widget _clubs() {
    final c = CareerUiColors(context);
    final teams =
        _teams
            .where(
              (t) =>
                  _participants.contains(fcId(t['remoteId'])) &&
                  fcNormalize(_name(fcId(t['remoteId'])))
                      .contains(fcNormalize(_teamSearch)),
            )
            .toList()
          ..sort(
            (a, b) =>
                _name(fcId(a['remoteId']))
                    .compareTo(_name(fcId(b['remoteId']))),
          );
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: teams.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: TextField(
              decoration: fcInput('Buscar equipe', icon: Icons.search_rounded),
              onChanged: (v) => setState(() => _teamSearch = v),
            ),
          );
        }
        final t = teams[i - 1], id = fcId(t['remoteId']);
        return CareerCompetitionSurface(
          onTap: () => _roster(id),
          child: Row(
            children: [
              _logo(id, 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name(id),
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${fcValue(t['rosterCount'])} jogadores · OVR ${fcValue(fcObject(t['data'])['overall'])}',
                      style: TextStyle(color: c.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.accent, size: 20),
            ],
          ),
        );
      },
    );
  }
}

class _CareerRosterPage extends StatefulWidget {
  const _CareerRosterPage({
    required this.person,
    required this.repository,
    required this.seasonId,
    required this.team,
    required this.name,
    required this.identity,
    this.link,
  });
  final Person person;
  final FcScoreRepository repository;
  final String seasonId, name;
  final FcJson team;
  final FcScoreCareerIdentity identity;
  final FcScoreLink? link;
  @override
  State<_CareerRosterPage> createState() => _CareerRosterPageState();
}

class _CareerRosterPageState extends State<_CareerRosterPage> {
  FcJson _seasonStats(Object? value) {
    final stats = fcObject(value), link = widget.link;
    return {
      ...stats,
      'competitions': [
        for (final row in fcList(stats['competitions']))
          {
            ...row,
            'competition': {
              ...fcObject(row['competition']),
              'name':
                  widget
                      .identity
                      .competitions[link?.competitions[fcId(
                        fcObject(row['competition'])['id'],
                      )]]
                      ?.label ??
                  fcObject(row['competition'])['name'],
            },
            'team': {
              ...fcObject(row['team']),
              'name':
                  widget.identity
                      .club(
                        link?.teams[fcId(fcObject(row['team'])['id'])] ?? '',
                        null,
                      )
                      ?.label ??
                  fcObject(row['team'])['name'],
            },
          },
      ],
    };
  }

  late final _future = widget.repository.careerRoster(
    widget.person.id,
    widget.seasonId,
    fcId(widget.team['remoteId']),
  );
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.name)),
    body: SafeArea(
      child: FutureBuilder<List<FcJson>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final players = snapshot.data!
              .where(
                (p) =>
                    fcNormalize(fcName(p['localName'], fcPlayerName(p)))
                        .contains(fcNormalize(_search.text)),
              )
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: TextField(
                  controller: _search,
                  decoration: fcInput('Buscar jogador', icon: Icons.search),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: players.length,
                  itemBuilder: (context, i) {
                    final p = players[i],
                        name = fcName(p['localName'], fcPlayerName(p));
                    return FcPanel(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: PlayerAvatar(
                          fifaVersion: widget.person.fifaVersion,
                          realPlayerId: fcId(p['id']),
                          customAvatarFilePath: fcId(p['customAvatarFilePath']),
                        ),
                        title: Text('${fcValue(p['jerseyNumber'])}. $name'),
                        subtitle: Text(
                          '${(p['positions'] as List? ?? []).join(' · ')} · ${fcValue(p['age'])} anos',
                        ),
                        trailing: Text(
                          fcValue(p['overall']),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: CareerUiColors(context).accent,
                          ),
                        ),
                        onTap: () => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FcSection(name),
                                FcFact(
                                  'Overall / potencial',
                                  '${fcValue(p['overall'])} / ${fcValue(p['potential'])}',
                                ),
                                FcFact(
                                  'Nacionalidade',
                                  fcName(fcObject(p['nationality'])['name']),
                                ),
                                FcFact(
                                  'Posições',
                                  (p['positions'] as List? ?? []).join(' · '),
                                ),
                                if (p['seasonStats'] != null)
                                  FcSeasonStatistics(
                                    stats: _seasonStats(p['seasonStats']),
                                  )
                                else ...[
                                  FcFact(
                                    'Jogos de liga',
                                    p['leagueAppearances'],
                                  ),
                                  FcFact('Gols de liga', p['leagueGoals']),
                                  FcFact('Cartões amarelos', p['yellowCards']),
                                  FcFact('Cartões vermelhos', p['redCards']),
                                ],
                                FcFact(
                                  'Situação',
                                  p['injured'] == true
                                      ? 'Lesionado'
                                      : 'Disponível',
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
