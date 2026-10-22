import 'package:flutter/material.dart';

import '../utils/Components/CareerPageWidgets.dart';
import '../utils/Components/CareerUiStyle.dart';
import '../utils/Components/PlayerSearchCard.dart';
import '../utils/GameCatalog.dart';
import 'FcScoreApi.dart';
import 'FcScoreModels.dart';
import 'FcScoreHubPage.dart' show FcFixtureCard;
import 'FcScoreWidgets.dart';

enum FcScoreView {
  club('Clube', 'Finanças, técnico e recordes', Icons.business_outlined, ''),
  standings(
    'Classificação',
    'Tabela, grupos e campanha',
    Icons.leaderboard_outlined,
    'league',
  ),
  fixtures(
    'Partidas',
    'Calendário e resultados',
    Icons.calendar_month,
    'fixtures',
  ),
  reports(
    'Relatórios',
    'Desempenho e importação',
    Icons.description_outlined,
    'matches',
  ),
  squad(
    'Elenco',
    'Jogadores, notas e contratos',
    Icons.groups_outlined,
    'squad',
  ),
  competitions(
    'Competições',
    'Fases e participações',
    Icons.emoji_events_outlined,
    'competitions',
  ),
  history('Retrospecto', 'Temporadas e conquistas', Icons.history, 'history'),
  transfers(
    'Mercado',
    'Transferências e empréstimos',
    Icons.swap_horiz,
    'transfers',
  ),
  youth('Base', 'Academia e olheiros', Icons.school_outlined, 'youth'),
  tactics(
    'Tática',
    'Escalações e planos de jogo',
    Icons.dashboard_outlined,
    'tactics',
  );

  const FcScoreView(this.title, this.subtitle, this.icon, this.endpoint);
  final String title, subtitle, endpoint;
  final IconData icon;
}

class FcScoreDataPage extends StatefulWidget {
  const FcScoreDataPage({
    super.key,
    required this.api,
    required this.remote,
    required this.kind,
    required this.onMatch,
    this.competitionId,
    this.playerId,
    this.onImport,
    this.updatingCareer = false,
  });
  final FcScoreApi api;
  final FcScoreRemoteCareer remote;
  final FcScoreView kind;
  final Future<void> Function(FcScoreMatch) onMatch;
  final String? competitionId, playerId;
  final Future<void> Function()? onImport;
  final bool updatingCareer;
  @override
  State<FcScoreDataPage> createState() => _FcScoreDataPageState();
}

class _FcScoreDataPageState extends State<FcScoreDataPage> {
  final _search = TextEditingController();
  Object? _data;
  String? _error;
  bool _busy = true, _world = false;
  String _status = '';
  String? _competition;
  final _items = <FcJson>[];
  int _total = 0;
  @override
  void initState() {
    super.initState();
    _competition = widget.competitionId;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final save = widget.remote.saveId;
      final path = widget.playerId != null
          ? widget.api.careerPath(
              save,
              'players/${Uri.encodeComponent(widget.playerId!)}',
            )
          : widget.competitionId != null
          ? widget.api.careerPath(
              save,
              'competitions/${Uri.encodeComponent(widget.competitionId!)}',
            )
          : widget.kind == FcScoreView.reports
          ? 'matches'
          : widget.api.careerPath(save, widget.kind.endpoint);
      final data = await widget.api.request(
        path,
        query: widget.kind == FcScoreView.fixtures
            ? {
                'limit': '50',
                'offset': more ? '${_items.length}' : '0',
                if (_status.isNotEmpty) 'status': _status,
                'competitionId': ?_competition,
              }
            : null,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        if (widget.kind == FcScoreView.fixtures) {
          if (!more) _items.clear();
          _items.addAll(fcList(fcObject(data)['items']));
          _total = fcInt(fcObject(data)['total']) ?? _items.length;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _report(FcJson summary) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await widget.api.report(
        widget.remote.saveId,
        fcId(summary['id']),
      );
      if (mounted) await widget.onMatch(FcScoreMatch.fromReport(report));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _player(FcJson player) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => FcScoreDataPage(
        api: widget.api,
        remote: widget.remote,
        kind: FcScoreView.squad,
        playerId: fcId(player['id']),
        onMatch: widget.onMatch,
      ),
    ),
  );
  void _competitionPage(FcJson competition) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => FcScoreDataPage(
        api: widget.api,
        remote: widget.remote,
        kind: FcScoreView.standings,
        competitionId: fcId(competition['id']),
        onMatch: widget.onMatch,
        onImport: widget.onImport,
        updatingCareer: widget.updatingCareer,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.playerId != null
            ? 'Jogador'
            : widget.competitionId != null
            ? 'Competição'
            : widget.kind.title,
      ),
      actions: [
        IconButton(
          tooltip: 'Atualizar',
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.playerId == null)
              CareerPageHeader(
                title: widget.kind.title,
                subtitle:
                    '${fcName(widget.remote.club['name'])} · ${fcDay(widget.remote.overview['currentDate'])}',
                icon: widget.kind.icon,
                eyebrow: 'Dados do save',
              ),
            if (widget.onImport != null &&
                widget.playerId == null &&
                [
                  FcScoreView.standings,
                  FcScoreView.fixtures,
                  FcScoreView.squad,
                  FcScoreView.competitions,
                ].contains(widget.kind)) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : widget.onImport,
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  widget.updatingCareer
                      ? 'Atualizar carreira'
                      : 'Importar para carreira',
                ),
              ),
              const SizedBox(height: 18),
            ],
            if (_error != null) ...[
              FcNotice(_error!, error: true),
              OutlinedButton(
                onPressed: _busy ? null : _load,
                child: const Text('Tentar novamente'),
              ),
            ],
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_data != null) ..._content(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
  List<Widget> _content() {
    final data = fcObject(_data);
    if (widget.playerId != null) return _playerDetails(data);
    return switch (widget.kind) {
      FcScoreView.club => _club(data),
      FcScoreView.standings => _standings(data),
      FcScoreView.fixtures => _fixtures(),
      FcScoreView.reports => _reports(fcList(_data)),
      FcScoreView.squad => _squad(data),
      FcScoreView.competitions => _competitions(fcList(_data)),
      FcScoreView.history => _history(fcList(_data)),
      FcScoreView.transfers => _transfers(data),
      FcScoreView.youth => _youth(data),
      FcScoreView.tactics => _tactics(data),
    };
  }

  List<Widget> _club(FcJson data) {
    final manager = fcObject(data['manager']),
        budgets = fcObject(data['budgets']),
        records = fcObject(data['records']);
    final managerName = [
      fcId(manager['firstName']),
      fcId(manager['lastName']),
    ].where((s) => s.isNotEmpty).join(' ');
    return [
      FcPanel(
        child: Column(
          children: [
            const FcSection('Clube e técnico'),
            FcFact('Clube', fcName(fcObject(data['club'])['name'])),
            FcFact('Liga', fcName(fcObject(data['league'])['name'])),
            if (fcObject(data['nationalTeam']).isNotEmpty)
              FcFact('Seleção', fcName(fcObject(data['nationalTeam'])['name'])),
            FcFact('Técnico', managerName.isEmpty ? null : managerName),
            FcFact('Confiança da diretoria', manager['boardConfidence']),
            FcFact('Reputação', manager['reputation']),
            FcFact('Temporadas concluídas', data['completedSeasons']),
          ],
        ),
      ),
      FcPanel(
        child: Column(
          children: [
            const FcSection('Finanças'),
            const FcNotice('Valores na unidade monetária do save.'),
            FcFact('Transferências', fcMoney(budgets['transfer'])),
            FcFact('Salários', fcMoney(budgets['wage'])),
            FcFact(
              'Transferências no início da temporada',
              fcMoney(budgets['startOfSeasonTransfer']),
            ),
            FcFact(
              'Salários no início da temporada',
              fcMoney(budgets['startOfSeasonWage']),
            ),
            FcFact('Salário do técnico', fcMoney(manager['wage'])),
          ],
        ),
      ),
      const FcSection('Recordes'),
      for (final record in {
        'biggestWin': 'Maior vitória',
        'biggestLoss': 'Maior derrota',
      }.entries)
        if (records[record.key] != null)
          FcPanel(
            child: Column(
              children: [
                FcSection(record.value),
                FcFact('Placar', fcObject(records[record.key])['score']),
                FcFact(
                  'Adversário',
                  fcName(
                    fcObject(fcObject(records[record.key])['opponent'])['name'],
                  ),
                ),
                FcFact('Data', fcDay(fcObject(records[record.key])['date'])),
              ],
            ),
          ),
      FcFact('Sequência de derrotas', records['losingStreak']),
      FcFact('Liberados nesta temporada', records['playersReleasedThisSeason']),
    ];
  }

  List<Widget> _standings(FcJson data) => [
    FcSection(
      fcName(fcObject(data['competition'])['name']),
      subtitle:
          '${fcValue(fcObject(data['fixtures'])['played'])} jogos realizados',
    ),
    const FcNotice(
      'Deslize a tabela para ver todas as colunas. A ordem e os pontos são os calculados pela API a partir dos jogos do save.',
    ),
    if (fcList(data['stages']).isEmpty)
      const FcNotice('Não há tabela disponível nesta competição.'),
    for (final stage in fcList(data['stages'])) ...[
      FcSection(fcName(stage['name'], fcId(stage['code']))),
      for (final group in fcList(stage['groups'])) ...[
        if (fcList(stage['groups']).length > 1)
          FcSection('Grupo ${fcValue(group['code'])}'),
        if (fcList(group['rows']).isEmpty)
          const FcNotice('Esta fase ainda não tem classificação.'),
        if (fcList(group['rows']).isNotEmpty)
          FcPanel(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                horizontalMargin: 0,
                columns: [
                  for (final label in [
                    '#',
                    'Equipe',
                    'PTS',
                    'PJ',
                    'V',
                    'E',
                    'D',
                    'GP',
                    'GC',
                    'SG',
                    'Forma',
                  ])
                    DataColumn(label: Text(label)),
                ],
                rows: [
                  for (final row in fcList(group['rows']))
                    DataRow(
                      color: row['isUserClub'] == true
                          ? WidgetStatePropertyAll(
                              CareerUiColors(context).accent
                                  .withValues(alpha: .12),
                            )
                          : null,
                      cells: [
                        DataCell(Text(fcValue(row['position']))),
                        DataCell(
                          SizedBox(
                            width: 160,
                            child: Text(fcName(fcObject(row['team'])['name'])),
                          ),
                        ),
                        for (final key in [
                          'points',
                          'played',
                          'wins',
                          'draws',
                          'losses',
                          'goalsFor',
                          'goalsAgainst',
                          'goalDifference',
                        ])
                          DataCell(Text(fcValue(row[key]))),
                        DataCell(
                          Row(
                            children: [
                              for (final form in (row['form'] as List? ?? []))
                                Container(
                                  margin: const EdgeInsets.only(right: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (form == 'W'
                                                ? CareerUiColors(context).green
                                                : form == 'D'
                                                ? CareerUiColors(context).amber
                                                : CareerUiColors(context).red)
                                            .withValues(alpha: .15),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    form == 'W'
                                        ? 'V'
                                        : form == 'D'
                                        ? 'E'
                                        : 'D',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    ],
  ];
  List<Widget> _fixtures() => [
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final status in {
          '': 'Todos',
          'played': 'Resultados',
          'scheduled': 'Próximos',
        }.entries)
          ChoiceChip(
            label: Text(status.value),
            selected: _status == status.key,
            onSelected: _busy
                ? null
                : (_) {
                    setState(() => _status = status.key);
                    _load();
                  },
          ),
      ],
    ),
    const SizedBox(height: 16),
    DropdownButtonFormField<String>(
      initialValue: _competition ?? '',
      isExpanded: true,
      decoration: fcInput('Competição'),
      items: [
        const DropdownMenuItem(value: '', child: Text('Todas as competições')),
        for (final c in widget.remote.competitions)
          DropdownMenuItem(
            value: fcId(c['id']),
            child: Text(fcName(c['name']), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _busy
          ? null
          : (value) {
              setState(() => _competition = value == '' ? null : value);
              _load();
            },
    ),
    const SizedBox(height: 16),
    FcSection('$_total partidas'),
    if (_items.isEmpty)
      const FcNotice('Nenhum jogo encontrado com estes filtros.'),
    for (final fixture in _items)
      FcFixtureCard(
        fixture: fixture,
        onTap: fixture['played'] == true
            ? () => widget.onMatch(
                FcScoreMatch.fromFixture(fixture, widget.remote.saveId),
              )
            : null,
      ),
    if (_items.length < _total)
      OutlinedButton(
        onPressed: _busy ? null : () => _load(more: true),
        child: const Text('Carregar mais'),
      ),
  ];
  List<Widget> _reports(List<FcJson> reports) => [
    const FcNotice(
      'Relatórios exportados pelo jogo, do mais recente ao mais antigo. Confira o save, a data e os times antes de importar.',
    ),
    if (reports.isEmpty)
      const FcNotice(
        'Nenhum relatório detalhado encontrado. Exporte uma partida para a pasta configurada no PC.',
      ),
    for (final report in reports)
      FcChoice(
        title:
            '${fcName(report['competition'])} · exportação v${fcValue(report['exportVersion'])}',
        value:
            '${fcName(report['home'])} ${fcValue(fcObject(report['score'])['home'])} – ${fcValue(fcObject(report['score'])['away'])} ${fcName(report['away'])}',
        icon: Icons.description_outlined,
        onTap: _busy ? null : () => _report(report),
      ),
  ];
  late final CatalogItem _squadClub = _resolveSquadClub();

  CatalogItem _resolveSquadClub() {
    final catalog = GameCatalog.current;
    final club = widget.remote.club;
    final source = catalog?.team('FC27', fcId(club['id']));
    final teams = catalog?.teams(widget.remote.gameVersion) ?? <CatalogItem>[];
    final item = teams
        .where(
          (team) =>
              !team.isSupplementalClub &&
              ((source != null && team.clubIdentity == source.clubIdentity) ||
                  (!team.isWoman &&
                      fcNormalize(team.label) ==
                          fcNormalize(fcName(club['name'])))),
        )
        .firstOrNull;
    return item ??
        CatalogItem(
          fcId(club['id']),
          fcName(club['name']),
          leagueId: fcId(widget.remote.league['id']),
        );
  }

  Widget _playerTile(FcJson player) => PlayerSearchCard(
    key: ValueKey('fc-squad-player-${fcId(player['id'])}'),
    name: fcPlayerName(player),
    version: widget.remote.gameVersion,
    realPlayerId: fcId(player['id']),
    details:
        '${(player['positions'] as List? ?? []).join(' / ')} · ${fcValue(player['age'])} anos · GER ${fcValue(player['overall'])}',
    club: _squadClub,
    onTap: () => _player(player),
  );
  List<Widget> _squad(FcJson data) {
    final query = fcNormalize(_search.text);
    final players = fcList(data['players'])
        .where((p) => fcNormalize(fcPlayerName(p)).contains(query))
        .toList();
    return [
      TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: fcInput('Buscar jogador', icon: Icons.search),
      ),
      const SizedBox(height: 16),
      FcSection('${players.length} jogadores'),
      for (final p in players) _playerTile(p),
    ];
  }

  List<Widget> _competitions(List<FcJson> progress) => [
    if (progress.isEmpty)
      const FcNotice('Nenhuma participação registrada no save.'),
    for (final p in progress)
      FcChoice(
        title:
            'Temporada ${fcValue(p['season'])} · ${fcName(fcObject(p['team'])['name'])}',
        value:
            '${fcName(fcObject(p['competition'])['name'])}${p['won'] == true ? ' · Campeão' : ''}',
        icon: Icons.emoji_events_outlined,
        onTap: () => _competitionPage(fcObject(p['competition'])),
      ),
  ];
  List<Widget> _history(List<FcJson> history) => [
    if (history.isEmpty) const FcNotice('Nenhuma temporada concluída no save.'),
    for (final s in history.reversed)
      FcPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FcSection(
              'Temporada ${fcValue(s['season'])}',
              subtitle:
                  '${fcName(fcObject(s['team'])['name'])} · ${fcName(fcObject(s['league'])['name'])}',
            ),
            FcFact('Partidas', s['gamesPlayed']),
            FcFact(
              'Campanha',
              '${fcValue(s['wins'])} V · ${fcValue(s['draws'])} E · ${fcValue(s['losses'])} D',
            ),
            FcFact(
              'Gols',
              '${fcValue(s['goalsFor'])} marcados · ${fcValue(s['goalsAgainst'])} sofridos',
            ),
            FcFact(
              'Liga',
              '${fcValue(s['leaguePosition'])}º · ${fcValue(s['points'])} pontos',
            ),
            for (final t in {
              'league': 'Ligas',
              'domesticCup': 'Copas nacionais',
              'continental': 'Continentais',
            }.entries)
              FcFact(t.value, fcObject(s['trophies'])[t.key]),
            if (s['biggestSigning'] != null)
              FcFact(
                'Maior contratação',
                '${fcName(fcObject(s['biggestSigning'])['playerName'])} · ${fcMoney(fcObject(s['biggestSigning'])['fee'])}',
              ),
            if (s['biggestSale'] != null)
              FcFact(
                'Maior venda',
                '${fcName(fcObject(s['biggestSale'])['playerName'])} · ${fcMoney(fcObject(s['biggestSale'])['fee'])}',
              ),
          ],
        ),
      ),
  ];
  List<Widget> _transfers(FcJson data) => [
    Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Do clube'),
          selected: !_world,
          onSelected: (_) => setState(() => _world = false),
        ),
        ChoiceChip(
          label: const Text('Mundo'),
          selected: _world,
          onSelected: (_) => setState(() => _world = true),
        ),
      ],
    ),
    const SizedBox(height: 16),
    const FcNotice(
      'Consulta do mercado no save. Transferências locais continuam sendo registradas na aba de transferências do aplicativo.',
    ),
    if (fcList(data[_world ? 'world' : 'involvingClub']).isEmpty)
      const FcNotice('Nenhuma transferência encontrada.'),
    for (final t in fcList(data[_world ? 'world' : 'involvingClub']))
      FcPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FcSection(
              fcName(fcObject(t['player'])['name']),
              subtitle:
                  '${fcName(fcObject(t['from'])['name'])} → ${fcName(fcObject(t['to'])['name'])}',
            ),
            FcFact('Valor', fcMoney(t['fee'])),
            FcFact('Salário', fcMoney(t['wage'])),
            FcFact('Assinado', fcDay(t['signedAt'])),
            FcFact('Liberação', fcDay(t['completesAt'])),
            if (t['isLoanToBuy'] == true)
              const Text('Empréstimo com opção de compra'),
            if (t['isSwap'] == true) const Text('Troca de jogadores'),
          ],
        ),
      ),
    if (!_world) ...[
      const FcSection('Empréstimos'),
      if (fcList(data['loans']).isEmpty)
        const FcNotice('Nenhum empréstimo ativo.'),
      for (final loan in fcList(data['loans']))
        FcPanel(
          child: Column(
            children: [
              FcFact('Jogador', fcName(fcObject(loan['player'])['name'])),
              FcFact('Origem', fcName(fcObject(loan['from'])['name'])),
              FcFact('Até', fcDay(loan['until'])),
            ],
          ),
        ),
      const FcSection('Lista de transferências'),
      for (final row in fcList(data['transferList']))
        FcFact(
          fcName(fcObject(row['player'])['name']),
          row['permanent'] == true ? 'Venda' : 'Empréstimo',
        ),
    ],
  ];
  List<Widget> _youth(FcJson data) => [
    const FcSection('Academia'),
    if (fcList(data['academy']).isEmpty)
      const FcNotice('A academia está vazia.'),
    for (final p in fcList(data['academy'])) _playerTile(p),
    const FcSection('Promovidos'),
    for (final p in fcList(data['graduates']))
      FcPanel(
        child: Column(
          children: [
            FcFact('Jogador', fcName(fcObject(p['player'])['name'])),
            FcFact('Partidas', p['appearances']),
            FcFact('Gols', p['goals']),
          ],
        ),
      ),
    const FcSection('Olheiros'),
    for (final s in fcList(data['scouts']))
      FcPanel(
        child: Column(
          children: [
            FcFact('Nome', fcName(s['name'])),
            FcFact('País', fcName(fcObject(s['nationality'])['name'])),
            FcFact('Experiência', s['experience']),
            FcFact('Conhecimento', s['knowledge']),
          ],
        ),
      ),
    const FcSection('Missões'),
    for (final m in fcList(data['missions']))
      FcPanel(
        child: Column(
          children: [
            FcFact('País', fcName(fcObject(m['nationality'])['name'])),
            FcFact('Retorno', fcDay(m['returnsAt'])),
            FcFact('Custo', fcMoney(m['cost'])),
            FcFact('Posições', (m['positions'] as List? ?? []).join(' / ')),
          ],
        ),
      ),
  ];
  List<Widget> _tactics(FcJson data) => [
    for (final tactic in fcList(data['tactics']))
      FcPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FcSection(
              '${fcName(tactic['name'], fcId(tactic['code']))}${tactic['active'] == true ? ' · Ativa' : ''}',
            ),
            FcFact('Profundidade defensiva', tactic['defensiveDepth']),
            for (final p in fcList(tactic['lineup']))
              FcFact(
                fcValue(p['position']),
                fcName(fcObject(p['player'])['name'], 'Vazio'),
              ),
          ],
        ),
      ),
    const FcSection('Escalações salvas'),
    for (final sheet in fcList(data['teamSheets']))
      FcPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FcSection(
              '${fcName(sheet['name'])}${sheet['favourite'] == true ? ' · Favorita' : ''}',
            ),
            const FcSection('Titulares'),
            for (final p in (sheet['starters'] as List? ?? []))
              Text(fcName(fcObject(p)['name'], 'Vazio')),
            const FcSection('Reservas'),
            for (final p in fcList(sheet['bench'])) Text(fcName(p['name'])),
            FcFact('Capitão', fcName(fcObject(sheet['captain'])['name'])),
            FcFact('Pênaltis', fcName(fcObject(sheet['penaltyTaker'])['name'])),
          ],
        ),
      ),
    if (fcList(data['tactics']).isEmpty && fcList(data['teamSheets']).isEmpty)
      const FcNotice('Nenhum plano de jogo disponível.'),
  ];
  List<Widget> _playerDetails(FcJson data) {
    final contract = fcObject(data['contract']);
    return [
      CareerPageHeader(
        title: fcPlayerName(data),
        subtitle:
            '${(data['positions'] as List? ?? []).join(' / ')} · ${fcValue(data['age'])} anos',
        icon: Icons.person_outline,
        eyebrow: 'Jogador do save',
      ),
      FcPanel(
        child: Column(
          children: [
            FcFact('Overall', data['overall']),
            FcFact('Potencial', data['potential']),
            FcFact(
              'Nacionalidade',
              fcName(fcObject(data['nationality'])['name']),
            ),
            FcFact('Nascimento', fcDay(data['birthDate'])),
            FcFact(
              'Pé',
              data['preferredFoot'] == 'left'
                  ? 'Esquerdo'
                  : data['preferredFoot'] == 'right'
                  ? 'Direito'
                  : '—',
            ),
            FcFact(
              'Altura',
              data['height'] == null ? null : '${data['height']} cm',
            ),
            FcFact(
              'Peso',
              data['weight'] == null ? null : '${data['weight']} kg',
            ),
          ],
        ),
      ),
      FcPanel(
        child: Column(
          children: [
            const FcSection('Contrato'),
            FcFact('Salário', fcMoney(contract['wage'])),
            FcFact('Assinado', fcDay(contract['signedAt'])),
            FcFact('Duração', '${fcValue(contract['durationMonths'])} meses'),
          ],
        ),
      ),
      if (data['seasonStats'] != null)
        FcPanel(
          child: FcSeasonStatistics(stats: fcObject(data['seasonStats'])),
        ),
      for (final group in fcObject(data['attributes']).entries)
        FcPanel(
          child: Column(
            children: [
              FcSection(_attributeLabel(group.key)),
              for (final entry in fcObject(group.value).entries)
                FcFact(_attributeLabel(entry.key), entry.value),
            ],
          ),
        ),
      if (data['injury'] != null)
        FcPanel(
          child: Column(
            children: [
              const FcSection('Lesão'),
              for (final entry in fcObject(data['injury']).entries)
                FcFact(_attributeLabel(entry.key), entry.value),
            ],
          ),
        ),
      if (fcList(data['matchRatings']).isNotEmpty) ...[
        const FcSection('Notas registradas'),
        for (final rating in fcList(data['matchRatings']))
          FcFact(
            fcDay(rating['date']),
            fcNumber(rating['rating']) == null
                ? null
                : (fcNumber(rating['rating'])! / 10).toStringAsFixed(1),
          ),
      ],
    ];
  }
}

String _attributeLabel(String key) =>
    const {
      'pace': 'Velocidade',
      'shooting': 'Finalização',
      'passing': 'Passe',
      'dribbling': 'Drible',
      'defending': 'Defesa',
      'physical': 'Físico',
      'goalkeeping': 'Goleiro',
      'acceleration': 'Aceleração',
      'sprintSpeed': 'Pique',
      'finishing': 'Finalização',
      'shotPower': 'Força do chute',
      'longShots': 'Chutes de longe',
      'volleys': 'Voleios',
      'penalties': 'Pênaltis',
      'vision': 'Visão',
      'crossing': 'Cruzamentos',
      'freeKickAccuracy': 'Cobrança de falta',
      'shortPassing': 'Passe curto',
      'longPassing': 'Passe longo',
      'curve': 'Curva',
      'agility': 'Agilidade',
      'balance': 'Equilíbrio',
      'reactions': 'Reações',
      'ballControl': 'Controle de bola',
      'composure': 'Compostura',
      'interceptions': 'Interceptações',
      'headingAccuracy': 'Cabeceio',
      'defensiveAwareness': 'Consciência defensiva',
      'standingTackle': 'Desarme em pé',
      'slidingTackle': 'Carrinho',
      'jumping': 'Impulsão',
      'stamina': 'Fôlego',
      'strength': 'Força',
      'aggression': 'Agressividade',
      'gkDiving': 'Elasticidade',
      'gkHandling': 'Manejo',
      'gkKicking': 'Reposição',
      'gkPositioning': 'Posicionamento',
      'gkReflexes': 'Reflexos',
      'returnsAt': 'Retorno',
      'type': 'Tipo',
      'daysRemaining': 'Dias restantes',
    }[key] ??
    const {
      'sprintspeed': 'Pique',
      'shotpower': 'Força do chute',
      'longshots': 'Chutes de longe',
      'positioning': 'Posicionamento',
      'freekickaccuracy': 'Cobrança de falta',
      'shortpassing': 'Passe curto',
      'longpassing': 'Passe longo',
      'ballcontrol': 'Controle de bola',
      'headingaccuracy': 'Cabeceio',
      'defensiveawareness': 'Consciência defensiva',
      'standingtackle': 'Desarme em pé',
      'slidingtackle': 'Carrinho',
      'gkdiving': 'Elasticidade',
      'gkhandling': 'Manejo',
      'gkkicking': 'Reposição',
      'gkpositioning': 'Posicionamento',
      'gkreflexes': 'Reflexos',
      'since': 'Desde',
      'durationDays': 'Duração em dias',
    }[key] ??
    key;
