import 'package:flutter/material.dart';

import '../Common/FixtureDetailsPage.dart';
import '../models/FixtureFormation.dart';
import '../models/OpponentLineup.dart';
import '../models/Person.dart';
import '../models/Season.dart';
import '../utils/Components/CareerPageWidgets.dart';
import '../utils/FootballFormations.dart';
import '../utils/GameCatalog.dart';
import '../utils/PlayerClubLookup.dart';
import 'FcScoreApi.dart';
import 'FcScoreModels.dart';
import 'FcScoreRepository.dart';
import 'FcScoreHubPage.dart' show FcFixtureCard;
import 'FcScoreWidgets.dart';
import 'FcScoreClubCatalog.dart';
import 'FcScoreClubMappingWidgets.dart';

class FcScoreImportPage extends StatefulWidget {
  const FcScoreImportPage({
    super.key,
    required this.repository,
    required this.person,
    required this.link,
    required this.match,
    this.target,
    this.api,
  });
  final FcScoreRepository repository;
  final Person person;
  final FcScoreLink link;
  final FcScoreMatch match;
  final Map<String, Object?>? target;
  final FcScoreApi? api;
  @override
  State<FcScoreImportPage> createState() => _FcScoreImportPageState();
}

class _FcScoreImportPageState extends State<FcScoreImportPage> {
  late final FcScoreLink _link = widget.link.copy();
  List<CatalogItem> _teams = [],
      _leagues = [],
      _competitions = [],
      _players = [];
  List<Season> _seasons = [];
  Map<String, Map<String, Object?>> _playerRows = {};
  FcImportState _state = FcImportState.available;
  String? _error, _savedId;
  bool _loading = true, _saving = false, _extraTime = false;
  String? _formation, _opponentFormation;
  FcScoreMatch get _match => widget.match;
  String get _opponentId =>
      fcId(fcObject(_match.opponent(_link)['team'])['id']);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (_match.saveId != _link.saveId ||
          (_match.homeId != _link.remoteClubId &&
              _match.awayId != _link.remoteClubId)) {
        throw const FcScoreException(
          'Este relatório não corresponde ao clube e save vinculados. Selecione o save correto.',
        );
      }
      final catalog = await GameCatalog.load();
      final clubs = await FcScoreClubCatalog.load(
        widget.repository.sql,
        widget.person.fifaVersion,
      );
      _teams = clubs.teams;
      _leagues = clubs.leagues;
      _competitions = [
        ...await catalog.tournaments(widget.person.fifaVersion),
        for (final t in await widget.repository.sql.getCustomTournaments(
          widget.person.fifaVersion,
        ))
          CatalogItem(t.id, t.name),
      ];
      final rawPlayers = await widget.repository.sql.getCustomPlayers(
        widget.person.id,
      );
      _players = rawPlayers
          .map((p) => CatalogItem(fcId(p['id']), fcId(p['name'])))
          .toList();
      _playerRows = {for (final p in rawPlayers) fcId(p['id']): p};
      _seasons = await widget.repository.sql.getSeasons(widget.person.id);
      final current = _seasons.where((s) => s.id == _link.seasonId).firstOrNull;
      if (widget.target == null &&
          _match.date != null &&
          (current == null ||
              _match.date!.isBefore(current.startDate) ||
              _match.date!.isAfter(current.endDate))) {
        final fits = _seasons
            .where(
              (s) =>
                  !_match.date!.isBefore(s.startDate) &&
                  !_match.date!.isAfter(s.endDate),
            )
            .toList();
        if (fits.length == 1) _link.seasonId = fits.single.id;
      }
      final opponent = fcObject(_match.opponent(_link)['team']);
      final oldOpponent = _link.teams[_opponentId];
      if (widget.target == null &&
          (oldOpponent == null || oldOpponent.startsWith('new:'))) {
        _link.teams[_opponentId] =
            fcSuggestReference(opponent, _teams) ??
            oldOpponent ??
            'new:${fcName(opponent['name'])}';
      }
      if (widget.target == null) {
        _link.competitions.putIfAbsent(
          _match.competitionId,
          () =>
              fcSuggestReference(_match.competition, _competitions) ??
              'new:${fcName(_match.competition['name'])}',
        );
      }
      for (final p in fcList(_match.own(_link)['players'])) {
        if ((fcInt(p['id']) ?? -1) < 0) continue;
        _link.players.putIfAbsent(
          fcId(p['id']),
          () =>
              fcSuggestPlayer({
                ...fcObject(p['profile']),
                'id': p['id'],
              }, rawPlayers) ??
              'new',
        );
      }
      if (widget.target == null) {
        _state = await widget.repository.importState(
          widget.person,
          _link,
          _match,
        );
      }
    } catch (error) {
      _error = '$error';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _choose(String kind) async {
    final opponent = fcObject(_match.opponent(_link)['team']);
    final choice = await fcPick(
      context,
      title: kind == 'team'
          ? 'Adversário no aplicativo'
          : 'Competição no aplicativo',
      items: kind == 'team' ? _teams : _competitions,
      clubLeagues: kind == 'team' ? _leagues : null,
      selectedId: kind == 'team' ? _link.teams[_opponentId] : null,
      preferredLeagueId: kind == 'team' ? _link.localLeagueId : null,
      createName: fcName(
        (kind == 'team' ? opponent : _match.competition)['name'],
      ),
    );
    if (choice == null || !mounted) return;
    if (kind == 'team') {
      _link.teams[_opponentId] = choice;
    } else {
      _link.competitions[_match.competitionId] = choice;
    }
    final state = await widget.repository.importState(
      widget.person,
      _link,
      _match,
    );
    if (mounted) setState(() => _state = state);
  }

  Future<void> _season() async {
    final choice = await fcPick(
      context,
      title: 'Temporada da partida',
      items: [
        for (final s in _seasons)
          CatalogItem(s.id, '${fcDay(s.startDate)} a ${fcDay(s.endDate)}'),
      ],
    );
    if (choice != null && mounted) setState(() => _link.seasonId = choice);
  }

  Future<void> _player(FcJson p) async {
    final clubs = await PlayerClubLookup.load(
      sql: widget.repository.sql,
      person: widget.person,
      seasonId: _link.seasonId,
    );
    if (!mounted) return;
    final choice = await fcPick(
      context,
      title: fcPlayerName(fcObject(p['profile'])),
      items: _players,
      newPlayer: true,
      playerSource: {...fcObject(p['profile']), 'id': p['id']},
      playerChoice: _link.players[fcId(p['id'])],
      playerVersion: widget.person.fifaVersion,
      playerRows: _playerRows,
      playerClubs: clubs,
    );
    if (choice != null && mounted) {
      setState(() => _link.players[fcId(p['id'])] = choice);
    }
  }

  Future<void> _date() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _match.date ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime(2200),
    );
    if (value != null && mounted) {
      _match.date = value;
      final state = await widget.repository.importState(
        widget.person,
        _link,
        _match,
      );
      if (mounted) setState(() => _state = state);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.repository.importMatch(
        person: widget.person,
        link: _link,
        match: _match,
        extraTime: _extraTime,
        formation: _formation,
        opponentFormation: _opponentFormation,
      );
      widget.link.players.addAll(_link.players);
      widget.link.teams.addAll(_link.teams);
      widget.link.competitions.addAll(_link.competitions);
      widget.link.seasonId = _link.seasonId;
      widget.link.playerId = _link.playerId;
      await _refreshStandings();
      if (mounted) {
        setState(() {
          _savedId = result.fixtureId;
          _state = FcImportState.alreadyImported;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _complete() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final preview = await widget.repository.opponentCompletionPreview(
        person: widget.person,
        link: _link,
        match: _match,
        fixtureId: fcId(widget.target!['id']),
      );
      var createOpponentPlayers = false;
      if (preview != null && preview.missing.isNotEmpty) {
        if (!mounted) return;
        final answer = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Criar jogadores do adversário?'),
            content: SingleChildScrollView(
              child: Text(
                '${preview.missing.length} jogadores ainda não estão cadastrados neste adversário. '
                'Eles ficam vinculados ao clube e disponíveis nos próximos jogos. Os dados que você preencheu serão mantidos.\n\n'
                '${preview.missing.map((p) => fcPlayerName(fcObject(p["profile"]))).join("\n")}',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Só os existentes'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Criar e completar'),
              ),
            ],
          ),
        );
        if (answer == null) return;
        createOpponentPlayers = answer;
      }
      await widget.repository.completeFixture(
        person: widget.person,
        link: _link,
        match: _match,
        fixtureId: fcId(widget.target!['id']),
        formation: _formation,
        opponentFormation: _opponentFormation,
        createOpponentPlayers: createOpponentPlayers,
      );
      widget.link.players.addAll(_link.players);
      widget.link.playerId = _link.playerId;
      final standingsLink = _link.copy();
      standingsLink.seasonId = fcId(widget.target!['seasonId']);
      await _refreshStandings(link: standingsLink);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshStandings({FcScoreLink? link}) async {
    final api = widget.api;
    if (api == null) return;
    try {
      await widget.repository.refreshMatchStandings(
        api: api,
        person: widget.person,
        link: link ?? _link,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Partida salva. Não foi possível atualizar a classificação: $error',
            ),
          ),
        );
      }
    }
  }

  Future<void> _view() async {
    final table = widget.person.category == PersonCategory.manager
        ? 'ManagerFixtures'
        : 'PlayerFixtures';
    final db = await widget.repository.sql.database;
    final rows = await db.query(
      table,
      where: 'id = ? AND personId = ?',
      whereArgs: [_savedId, widget.person.id],
    );
    if (!mounted || rows.isEmpty) return;
    final catalog = await GameCatalog.load();
    final tournaments = [
      ...await catalog.tournaments(widget.person.fifaVersion),
      for (final t in await widget.repository.sql.getCustomTournaments(
        widget.person.fifaVersion,
      ))
        CatalogItem(t.id, t.name),
    ];
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => FixtureDetailsPage(
          person: widget.person,
          fixture: rows.single,
          opponent: catalog.teamLabel(
            widget.person.fifaVersion,
            fcId(rows.single['oppositeTeamId']),
          ),
          tournament: fcChoiceLabel(
            fcId(rows.single['tournamentId']),
            tournaments,
          ),
        ),
      ),
    );
  }

  Widget _myPlayer(List<FcJson> ownPlayers) => FcChoice(
    title: 'Meu jogador',
    value:
        ownPlayers
            .where((p) => fcId(p['id']) == _link.playerId)
            .map((p) => fcPlayerName(fcObject(p['profile'])))
            .firstOrNull ??
        'Escolher jogador que atuou',
    onTap: () async {
      final choice = await fcPick(
        context,
        title: 'Meu jogador nesta partida',
        playerVersion: widget.person.fifaVersion,
        playerRows: {
          for (final p in ownPlayers)
            fcId(p['id']): {...fcObject(p['profile']), 'realPlayerId': p['id']},
        },
        playerClub: _teams.where((t) => t.id == _link.localClubId).firstOrNull,
        items: [
          for (final p in ownPlayers)
            CatalogItem(fcId(p['id']), fcPlayerName(fcObject(p['profile']))),
        ],
      );
      if (choice != null && mounted) {
        setState(() => _link.playerId = choice);
      }
    },
  );

  Widget _formationField(
    String label,
    String? value,
    ValueChanged<String?> set,
  ) => DropdownButtonFormField<String>(
    initialValue: value ?? '',
    isExpanded: true,
    decoration: fcInput(label),
    items: [
      const DropdownMenuItem(value: '', child: Text('Organizar pela API')),
      for (final name in footballFormations.keys)
        DropdownMenuItem(value: name, child: Text(name)),
    ],
    onChanged: _saving ? null : (v) => setState(() => set(v == '' ? null : v)),
  );

  Widget _completion(List<FcJson> ownPlayers, List<FcJson> oppositePlayers) {
    final target = widget.target!;
    final manager = widget.person.category == PersonCategory.manager;
    final own = _match.own(_link), opposite = _match.opponent(_link);
    final sameScore =
        fcInt(own['goals']) == fcInt(target['playerTeamScore']) &&
        fcInt(opposite['goals']) == fcInt(target['oppositeTeamScore']);
    final day = DateTime.tryParse(fcId(target['date']));
    final sameDay =
        day != null &&
        _match.date != null &&
        DateUtils.isSameDay(day, _match.date);
    final ownLineup = FixtureFormation.decode(target['matchLineup']) == null;
    final opponentLineup =
        OpponentLineup.decode(target['opponentLineup']) == null;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        CareerPageHeader(
          title: 'Completar partida',
          subtitle:
              '${widget.person.name}\n${_match.detailed ? 'Relatório ${_match.reportId}' : 'Placar registrado no save'}',
          icon: Icons.cloud_download_rounded,
          eyebrow: 'Prévia',
        ),
        FcFixtureCard(
          fixture: {
            'played': true,
            'date': _match.date?.toIso8601String(),
            'time': _match.time,
            'home': _match.home,
            'away': _match.away,
            'competition': _match.competition,
          },
        ),
        const FcNotice(
          'Só o que estiver vazio na sua partida será preenchido. O placar, a data, o adversário, os gols, assistências e cartões que você registrou, com os minutos, as substituições e as escalações continuam como estão.',
        ),
        if (!sameScore)
          FcNotice(
            'No save o placar foi ${fcValue(own['goals'])} x ${fcValue(opposite['goals'])}, e na sua partida está ${fcValue(target['playerTeamScore'])} x ${fcValue(target['oppositeTeamScore'])}. O seu placar será mantido; confira se este é o jogo certo.',
            error: true,
          ),
        if (!sameDay)
          const FcNotice(
            'Este jogo do save é de outro dia. Confira se é a mesma partida.',
            error: true,
          ),
        if (!_match.detailed)
          FcNotice(
            manager
                ? 'Este jogo do save só tem o placar e as estatísticas das equipes. Exporte o relatório da partida para completar as notas e os números de cada jogador.'
                : 'Na carreira de jogador, escolha um jogo com relatório exportado para completar a sua atuação.',
            error: !manager,
          ),
        for (final warning in _match.warnings) FcNotice(warning),
        if (_match.detailed && !manager) _myPlayer(ownPlayers),
        if (_match.detailed && manager && (ownLineup || opponentLineup))
          FcPanel(
            child: Column(
              children: [
                const FcNotice(
                  'A partida ainda não tem escalação. A API informa titulares e reservas, mas não a formação usada; escolha como organizar o campinho.',
                ),
                if (ownLineup)
                  _formationField(
                    'Formação do seu clube',
                    _formation,
                    (v) => _formation = v,
                  ),
                if (ownLineup && opponentLineup) const SizedBox(height: 16),
                if (opponentLineup)
                  _formationField(
                    'Formação do adversário',
                    _opponentFormation,
                    (v) => _opponentFormation = v,
                  ),
              ],
            ),
          ),
        if (_match.detailed && manager) ...[
          FcSection('Seu clube · ${ownPlayers.length} atuações'),
          const FcNotice(
            'Quem você já registrou recebe só os números que faltam. Os demais jogadores que atuaram são adicionados.',
          ),
          for (final p in ownPlayers)
            FcPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summary(p),
                  FcChoice(
                    title: 'Jogador no aplicativo',
                    value: fcChoiceLabel(
                      _link.players[fcId(p['id'])],
                      _players,
                    ),
                    onTap: _saving ? null : () => _player(p),
                    icon: Icons.person_outline,
                  ),
                ],
              ),
            ),
          FcSection('Adversário · ${oppositePlayers.length} atuações'),
          const FcNotice(
            'As atuações dos jogadores já conhecidos também serão completadas. '
            'Antes de criar quem falta no adversário, você escolhe se deseja incluir esses jogadores.',
          ),
          for (final p in oppositePlayers) FcPanel(child: _summary(p)),
        ],
        if (_error != null) FcNotice(_error!, error: true),
        FilledButton.icon(
          key: const Key('fc-complete'),
          onPressed: _loading || _saving || (!manager && !_match.detailed)
              ? null
              : _complete,
          icon: const Icon(Icons.cloud_download),
          label: Text(_saving ? 'Completando…' : 'Completar partida'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final own = _match.own(_link), opposite = _match.opponent(_link);
    final ownPlayers = fcList(own['players'])
        .where((p) => p['played'] == true)
        .toList();
    final oppositePlayers = fcList(opposite['players'])
        .where((p) => p['played'] == true)
        .toList();
    if (widget.target != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Completar com a API')),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _completion(ownPlayers, oppositePlayers),
        ),
      );
    }
    final season = _seasons.where((s) => s.id == _link.seasonId).firstOrNull;
    final canImport =
        !_loading &&
        !_saving &&
        _teams.isNotEmpty &&
        _state != FcImportState.alreadyImported &&
        _match.date != null &&
        (widget.person.category == PersonCategory.manager || _match.detailed);
    return Scaffold(
      appBar: AppBar(title: const Text('Revisar importação')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  CareerPageHeader(
                    title: _match.detailed
                        ? 'Desempenho da partida'
                        : 'Resultado da partida',
                    subtitle:
                        '${widget.person.name}\n${_match.detailed ? 'Relatório ${_match.reportId}' : 'Placar registrado no save'}',
                    icon: Icons.download_rounded,
                    eyebrow: 'Prévia',
                  ),
                  FcFixtureCard(
                    fixture: {
                      'played': true,
                      'date': _match.date?.toIso8601String(),
                      'time': _match.time,
                      'home': _match.home,
                      'away': _match.away,
                      'competition': _match.competition,
                    },
                  ),
                  if (_savedId != null)
                    const FcNotice(
                      'Partida salva. Os dados já estão disponíveis nas estatísticas da carreira.',
                    ),
                  if (_state == FcImportState.alreadyImported &&
                      _savedId == null)
                    const FcNotice(
                      'Esta partida já está cadastrada. Nenhum registro será duplicado ou substituído.',
                    ),
                  if (_state == FcImportState.canComplete)
                    const FcNotice(
                      'O placar já foi importado. Você pode completar esta mesma partida com as estatísticas do relatório.',
                    ),
                  if (!_match.detailed)
                    const FcNotice(
                      'Este registro contém o resultado. Notas e estatísticas individuais precisam do relatório detalhado, que pode ser importado depois.',
                    ),
                  if (widget.person.category == PersonCategory.player &&
                      !_match.detailed)
                    const FcNotice(
                      'Na carreira de jogador, importe um relatório detalhado para registrar sua atuação.',
                      error: true,
                    ),
                  for (final warning in _match.warnings) FcNotice(warning),
                  if (_state != FcImportState.alreadyImported) ...[
                    if (_match.date == null)
                      FcChoice(
                        title: 'Data não resolvida pela API',
                        value: 'Informar a data do jogo',
                        onTap: _date,
                        icon: Icons.event,
                      ),
                    FcChoice(
                      title: 'Temporada',
                      value: season == null
                          ? 'Escolher temporada'
                          : '${fcDay(season.startDate)} a ${fcDay(season.endDate)}',
                      onTap: _saving ? null : _season,
                      icon: Icons.calendar_month,
                    ),
                    FcChoice(
                      title: 'Adversário',
                      value: fcChoiceLabel(_link.teams[_opponentId], _teams),
                      leading: FcClubLogo(
                        item: _teams
                            .where((t) => t.id == _link.teams[_opponentId])
                            .firstOrNull,
                      ),
                      onTap: _saving ? null : () => _choose('team'),
                    ),
                    FcChoice(
                      title: 'Competição',
                      value: fcChoiceLabel(
                        _link.competitions[_match.competitionId],
                        _competitions,
                      ),
                      onTap: _saving ? null : () => _choose('competition'),
                    ),
                    if (_match.detailed &&
                        widget.person.category == PersonCategory.player)
                      _myPlayer(ownPlayers),
                    if (_match.detailed &&
                        widget.person.category == PersonCategory.manager)
                      FcPanel(
                        child: Column(
                          children: [
                            const FcNotice(
                              'A API informa titulares e reservas, mas não a formação usada neste jogo. Escolha a forma\u00e7\u00e3o ou deixe a API sugerir pela posi\u00e7\u00e3o dos titulares. A sugest\u00e3o pode ser ajustada na edi\u00e7\u00e3o. Minutos de acréscimo não indicam prorrogação.',
                            ),
                            _formationField(
                              'Formação do seu clube',
                              _formation,
                              (v) => _formation = v,
                            ),
                            const SizedBox(height: 16),
                            _formationField(
                              'Formação do adversário',
                              _opponentFormation,
                              (v) => _opponentFormation = v,
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Houve prorrogação'),
                              value: _extraTime,
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() => _extraTime = v),
                            ),
                          ],
                        ),
                      ),
                  ],
                  if (_match.detailed) ...[
                    FcPanel(
                      child: Column(
                        children: [
                          const FcSection('Estatísticas das equipes'),
                          for (final stat in {
                            'shots': 'Finalizações',
                            'shotsOnTarget': 'No alvo',
                            'passes': 'Passes',
                            'passesCompleted': 'Passes certos',
                            'npkExpectedGoals': 'Gols esperados sem pênaltis',
                            'saves': 'Defesas',
                            'yellowCardEvents': 'Amarelos',
                            'redDismissals': 'Vermelhos',
                          }.entries)
                            FcFact(
                              stat.value,
                              '${fcValue(fcObject(own['stats'])[stat.key])} / ${fcValue(fcObject(opposite['stats'])[stat.key])}',
                            ),
                          const FcNotice(
                            'Seu clube / adversário. “—” indica um dado não fornecido.',
                          ),
                        ],
                      ),
                    ),
                    const FcNotice(
                      'Gols, assistências, cartões e minutos são importados como registrados. A API não fornece os horários dos eventos nem os pares de substituição.',
                    ),
                    FcSection('Seu clube · ${ownPlayers.length} atuações'),
                    for (final p in ownPlayers)
                      FcPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _summary(p),
                            if (widget.person.category ==
                                    PersonCategory.manager &&
                                _state != FcImportState.alreadyImported)
                              FcChoice(
                                title: 'Jogador no aplicativo',
                                value: fcChoiceLabel(
                                  _link.players[fcId(p['id'])],
                                  _players,
                                ),
                                onTap: _saving ? null : () => _player(p),
                                icon: Icons.person_outline,
                              ),
                          ],
                        ),
                      ),
                    FcSection(
                      'Adversário · ${oppositePlayers.length} atuações',
                    ),
                    for (final p in oppositePlayers)
                      FcPanel(child: _summary(p)),
                  ],
                  if (_error != null) FcNotice(_error!, error: true),
                  if (_savedId != null)
                    FilledButton.icon(
                      onPressed: _view,
                      icon: const Icon(Icons.sports_soccer),
                      label: const Text('Ver partida'),
                    )
                  else
                    FilledButton.icon(
                      key: const Key('fc-import'),
                      onPressed: canImport ? _save : null,
                      icon: const Icon(Icons.download),
                      label: Text(
                        _saving
                            ? 'Importando…'
                            : _state == FcImportState.alreadyImported
                            ? 'Já cadastrada'
                            : _state == FcImportState.canComplete
                            ? 'Completar estatísticas'
                            : 'Importar partida',
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _summary(FcJson p) {
    final stats = fcObject(p['stats']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fcPlayerName({...fcObject(p['profile']), 'id': p['id']}),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            Text(p['started'] == true ? 'Titular' : 'Reserva'),
            Text('${fcValue(stats['minutesPlayed'])} min'),
            Text('Nota ${fcValue(p['rating'])}'),
            Text('${fcValue(stats['goalsDerived'])} G'),
            Text('${fcValue(stats['assists'])} A'),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}
