import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/Person.dart';
import '../models/Season.dart';
import '../utils/Components/CareerPageWidgets.dart';
import '../utils/GameCatalog.dart';
import '../utils/PlayerClubLookup.dart';
import 'FcScoreApi.dart';
import 'FcScoreModels.dart';
import 'FcScoreRepository.dart';
import 'FcScoreWidgets.dart';
import 'FcScoreClubCatalog.dart';
import 'FcScoreClubMappingWidgets.dart';

class FcBoundCareer {
  const FcBoundCareer(this.person, this.link);
  final Person person;
  final FcScoreLink link;
}

class FcScoreMappingPage extends StatefulWidget {
  const FcScoreMappingPage({
    super.key,
    required this.remote,
    required this.repository,
    this.initialPerson,
    this.reviewExisting = false,
  });
  final FcScoreRemoteCareer remote;
  final FcScoreRepository repository;
  final Person? initialPerson;
  final bool reviewExisting;
  @override
  State<FcScoreMappingPage> createState() => _FcScoreMappingPageState();
}

class _FcScoreMappingPageState extends State<FcScoreMappingPage> {
  final _name = TextEditingController();
  List<Person> _persons = [];
  List<Season> _seasons = [];
  List<CatalogItem> _teams = [],
      _leagues = [],
      _competitions = [],
      _players = [];
  FcScoreLink? _link;
  Map<String, Map<String, Object?>> _playerRows = {};
  Person? _person;
  Season? _season;
  String? _error;
  bool _loading = true, _saving = false, _bringSquad = true, _overalls = true;
  bool _reusing = false;
  late bool _editExisting = widget.reviewExisting;
  bool get _compact => _reusing && !_editExisting;
  FcScoreRemoteCareer get _remote => widget.remote;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final catalog = await GameCatalog.load();
      await GameCatalog.reloadCustomData();
      final persons = await widget.repository.sql.getPersons(_remote.category);
      _persons = persons
          .where((p) => fcVersion(p.fifaVersion) == _remote.gameVersion)
          .toList();
      final clubs = await FcScoreClubCatalog.load(
        widget.repository.sql,
        _remote.gameVersion,
      );
      _teams = clubs.teams;
      _leagues = clubs.leagues;
      _competitions = [
        ...await catalog.tournaments(_remote.gameVersion),
        for (final t in await widget.repository.sql.getCustomTournaments(
          _remote.gameVersion,
        ))
          CatalogItem(t.id, t.name),
      ];
      final selected = _persons
          .where((p) => p.id == widget.initialPerson?.id)
          .firstOrNull;
      final sameClub = _persons
          .where((p) => p.teamId == fcId(_remote.club['id']))
          .toList();
      await _select(
        selected ?? (sameClub.length == 1 ? sameClub.single : null),
      );
    } catch (error) {
      _error = '$error';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _select(Person? person) async {
    _person = person;
    _bringSquad = person == null;
    _overalls = person == null;
    _name.text = person?.name ?? _remote.saveName;
    _seasons = person == null
        ? []
        : await widget.repository.sql.getSeasons(person.id);
    final rawPlayers = person == null
        ? <Map<String, Object?>>[]
        : await widget.repository.sql.getCustomPlayers(person.id);
    _players = rawPlayers
        .map((p) => CatalogItem(fcId(p['id']), fcId(p['name'])))
        .toList();
    _playerRows = {for (final p in rawPlayers) fcId(p['id']): p};
    final saved = person == null
        ? null
        : await widget.repository.linkFor(person.id);
    final previous = saved != null && saved.belongsTo(_remote, person!)
        ? saved
        : null;
    _reusing = previous != null;
    final current =
        DateTime.tryParse(fcId(_remote.overview['currentDate'])) ??
        DateTime.now();
    final id = person?.id ?? const Uuid().v4();
    _season =
        _seasons
            .where(
              (s) =>
                  s.id == previous?.seasonId &&
                  !s.isClosed &&
                  !current.isBefore(s.startDate) &&
                  !current.isAfter(s.endDate),
            )
            .firstOrNull ??
        _seasons
            .where(
              (s) =>
                  !s.isClosed &&
                  !current.isBefore(s.startDate) &&
                  !current.isAfter(s.endDate),
            )
            .firstOrNull;
    _season ??= Season(
      id: const Uuid().v4(),
      personId: id,
      startDate: DateTime(current.year, 1, 1),
      endDate: DateTime(current.year, 12, 31),
      createdAt: DateTime.now(),
    );
    _link = FcScoreLink(
      personId: id,
      saveId: _remote.saveId,
      saveName: _remote.saveName,
      gameVersion: _remote.gameVersion,
      remoteClubId: fcId(_remote.club['id']),
      localClubId:
          previous?.localClubId ??
          person?.teamId ??
          fcSuggestReference(_remote.club, _teams) ??
          'new:${fcName(_remote.club['name'])}',
      localLeagueId:
          previous?.localLeagueId ??
          person?.leagueId ??
          fcSuggestReference(_remote.league, _leagues) ??
          'new:${fcName(_remote.league['name'])}',
      seasonId: _season!.id,
      playerId: previous?.playerId ?? person?.realPlayerId,
      connectionAddress: previous?.connectionAddress,
      players: {...?previous?.players},
      teams: {...?previous?.teams},
      competitions: {...?previous?.competitions},
      leagues: {...?previous?.leagues},
      worldSync: {...?previous?.worldSync},
    );
    if (_compact) {
      if (mounted) setState(() {});
      return;
    }
    for (final p in _remote.squad) {
      _link!.players.putIfAbsent(
        fcId(p['id']),
        () => fcSuggestPlayer(p, rawPlayers) ?? 'new',
      );
    }
    for (final c in _remote.competitions) {
      _link!.competitions.putIfAbsent(
        fcId(c['id']),
        () =>
            fcSuggestReference(c, _competitions) ??
            'new:${fcName(c['name'], fcId(c['code']))}',
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _career() async {
    final id = await fcPick(
      context,
      title: 'Carreira no aplicativo',
      items: [
        const CatalogItem('new-career', 'Criar uma nova carreira'),
        for (final p in _persons) CatalogItem(p.id, p.name),
      ],
    );
    if (id != null) {
      setState(() => _loading = true);
      try {
        await _select(_persons.where((p) => p.id == id).firstOrNull);
      } catch (error) {
        _error = '$error';
      }
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _choose(String kind) async {
    final items = kind == 'club' ? _teams : _leagues;
    final name = fcName(
      (kind == 'club' ? _remote.club : _remote.league)['name'],
    );
    final id = await fcPick(
      context,
      title: kind == 'club' ? 'Clube no aplicativo' : 'Liga no aplicativo',
      items: items,
      createName: name,
      clubLeagues: kind == 'club' ? _leagues : null,
      selectedId: kind == 'club' ? _link!.localClubId : null,
      preferredLeagueId: kind == 'club' ? _link!.localLeagueId : null,
    );
    if (id != null && mounted) {
      setState(() {
        if (kind == 'club') {
          _link!.localClubId = id;
        } else {
          _link!.localLeagueId = id;
        }
      });
    }
  }

  Future<void> _chooseSeason() async {
    final choice = await fcPick(
      context,
      title: 'Temporada',
      items: [
        const CatalogItem('new-season', 'Criar temporada'),
        for (final s in _seasons)
          CatalogItem(s.id, '${fcDay(s.startDate)} a ${fcDay(s.endDate)}'),
      ],
    );
    if (choice == null || !mounted) return;
    if (choice != 'new-season') {
      setState(() => _season = _seasons.firstWhere((s) => s.id == choice));
      return;
    }
    final start = await showDatePicker(
      context: context,
      initialDate: _season!.startDate,
      firstDate: DateTime(1990),
      lastDate: DateTime(2200),
    );
    if (start == null || !mounted) return;
    final end = await showDatePicker(
      context: context,
      initialDate: start.add(const Duration(days: 364)),
      firstDate: start.add(const Duration(days: 1)),
      lastDate: DateTime(2201),
    );
    if (end != null && mounted) {
      setState(
        () => _season = Season(
          id: const Uuid().v4(),
          personId: _link!.personId,
          startDate: start,
          endDate: end,
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _mapPlayer(FcJson player) async {
    final person = _person;
    final clubs = person == null
        ? null
        : await PlayerClubLookup.load(
            sql: widget.repository.sql,
            person: person,
            seasonId: _season?.id,
          );
    if (!mounted) return;
    final choice = await fcPick(
      context,
      title: fcPlayerName(player),
      items: _players,
      newPlayer: true,
      playerSource: player,
      playerChoice: _link!.players[fcId(player['id'])],
      playerVersion: _remote.gameVersion,
      playerRows: _playerRows,
      playerClubs: clubs,
    );
    if (choice != null && mounted) {
      setState(() => _link!.players[fcId(player['id'])] = choice);
    }
  }

  Future<void> _competition(FcJson competition) async {
    final choice = await fcPick(
      context,
      title: fcName(competition['name']),
      items: _competitions,
      createName: fcName(competition['name'], fcId(competition['code'])),
    );
    if (choice != null && mounted) {
      setState(() => _link!.competitions[fcId(competition['id'])] = choice);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_name.text.trim().isEmpty) {
        throw const FcScoreException('Informe o nome da carreira.');
      }
      if (_remote.category == PersonCategory.player &&
          _link!.playerId == null) {
        throw const FcScoreException('Escolha o seu jogador no save.');
      }
      final now = DateTime.now();
      final selectedPlayer = _remote.squad
          .where((p) => fcId(p['id']) == _link!.playerId)
          .firstOrNull;
      final newPerson = _person == null
          ? Person(
              id: _link!.personId,
              name: _name.text.trim(),
              category: _remote.category,
              fifaVersion: _remote.gameVersion,
              leagueId: _link!.localLeagueId,
              teamId: _link!.localClubId,
              nationalityId: fcId(
                fcObject(
                  selectedPlayer?['nationality'] ??
                      fcObject(_remote.overview['manager'])['nationality'],
                )['id'],
              ),
              realPlayerId: _link!.playerId,
              positionId: selectedPlayer == null
                  ? null
                  : fcPositionId(selectedPlayer['positions']),
              birthdate: DateTime.tryParse(fcId(selectedPlayer?['birthDate']))
                  ?.millisecondsSinceEpoch,
              foot: selectedPlayer?['preferredFoot'] == 'left'
                  ? 'Left'
                  : selectedPlayer == null
                  ? null
                  : 'Right',
              createdAt: now,
              updatedAt: now,
            )
          : null;
      final link = await widget.repository.bind(
        link: _link!,
        remote: _remote,
        season: _season!,
        newPerson: newPerson,
        bringSquad: _bringSquad,
        updateOveralls: _overalls,
      );
      final persons = await widget.repository.sql.getPersons();
      final person = persons.firstWhere((p) => p.id == link.personId);
      if (mounted) Navigator.pop(context, FcBoundCareer(person, link));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_compact ? 'Atualizar carreira' : 'Vincular carreira'),
    ),
    body: SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _link == null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: FcNotice(
                _error ?? 'Não foi possível carregar os cadastros.',
                error: true,
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                CareerPageHeader(
                  title: fcName(_remote.club['name']),
                  subtitle: _compact
                      ? '${_remote.saveName} · ${_remote.gameVersion}\nSeus vínculos já estão salvos nesta carreira.'
                      : '${_remote.saveName} · ${_remote.gameVersion}\nConfira os vínculos sugeridos. Você pode corrigir cada cadastro.',
                  icon: Icons.link,
                  eyebrow: _compact ? 'Carreira vinculada' : 'De-para',
                ),
                FcChoice(
                  title: 'Destino no aplicativo',
                  value: _person?.name ?? 'Criar nova carreira',
                  onTap: _saving ? null : _career,
                  icon: Icons.folder_open,
                ),
                if (_compact) ...[
                  const FcNotice(
                    'O de-para deste time será reutilizado. A atualização só solicita os vínculos novos ou que precisam de correção.',
                  ),
                  FilledButton.icon(
                    key: const Key('fc-resume-binding'),
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Continuar atualização'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('fc-review-saved-binding'),
                    onPressed: _saving
                        ? null
                        : () => setState(() => _editExisting = true),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Revisar vínculos salvos'),
                  ),
                ] else ...[
                  if (_person == null) ...[
                    TextField(
                      controller: _name,
                      decoration: fcInput('Nome da carreira'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FcChoice(
                    title: 'Clube',
                    value: fcChoiceLabel(_link!.localClubId, _teams),
                    leading: FcClubLogo(
                      item: _teams
                          .where((t) => t.id == _link!.localClubId)
                          .firstOrNull,
                    ),
                    onTap: _saving ? null : () => _choose('club'),
                  ),
                  FcChoice(
                    title: 'Liga',
                    value: fcChoiceLabel(_link!.localLeagueId, _leagues),
                    onTap: _saving ? null : () => _choose('league'),
                  ),
                  FcChoice(
                    title: 'Temporada',
                    value:
                        '${fcDay(_season!.startDate)} a ${fcDay(_season!.endDate)}',
                    onTap: _saving ? null : _chooseSeason,
                    icon: Icons.calendar_month,
                  ),
                  if (_remote.category == PersonCategory.player)
                    FcChoice(
                      title: 'Meu jogador',
                      value:
                          _remote.squad
                              .where((p) => fcId(p['id']) == _link!.playerId)
                              .map(fcPlayerName)
                              .firstOrNull ??
                          'Escolher jogador',
                      onTap: () async {
                        final choice = await fcPick(
                          context,
                          title: 'Meu jogador',
                          playerVersion: _remote.gameVersion,
                          playerRows: {
                            for (final p in _remote.squad)
                              fcId(p['id']): {...p, 'realPlayerId': p['id']},
                          },
                          playerClub: _teams
                              .where((t) => t.id == _link!.localClubId)
                              .firstOrNull,
                          items: [
                            for (final p in _remote.squad)
                              CatalogItem(fcId(p['id']), fcPlayerName(p)),
                          ],
                        );
                        if (choice != null && mounted) {
                          setState(() => _link!.playerId = choice);
                        }
                      },
                      icon: Icons.person,
                    ),
                  const FcSection(
                    'Competições',
                    subtitle: 'Nomes e IDs podem variar com mods. Corrija os vínculos se necessário.',
                  ),
                  for (final c in _remote.competitions)
                    FcChoice(
                      title: fcName(c['name'], fcId(c['code'])),
                      value: fcChoiceLabel(
                        _link!.competitions[fcId(c['id'])],
                        _competitions,
                      ),
                      onTap: _saving ? null : () => _competition(c),
                      icon: Icons.emoji_events_outlined,
                    ),
                  if (_remote.category == PersonCategory.manager) ...[
                    const FcSection(
                      'Jogadores',
                      subtitle: 'IDs ou nomes completos iguais sugerem um vínculo. Os demais recebem um novo cadastro.',
                    ),
                    FcPanel(
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Trazer elenco'),
                            subtitle: const Text(
                              'Novos jogadores entram na reserva. Revise abaixo os cadastros existentes.',
                            ),
                            value: _bringSquad,
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => _bringSquad = v),
                          ),
                          if (_bringSquad)
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Registrar os overalls atuais'),
                              subtitle: Text(
                                'Na data do save: ${fcDay(_remote.overview['currentDate'])}. O histórico anterior é preservado.',
                              ),
                              value: _overalls,
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() => _overalls = v),
                            ),
                        ],
                      ),
                    ),
                    if (_bringSquad)
                      for (final p in _remote.squad)
                        FcChoice(
                          title:
                              '${fcPlayerName(p)} · OVR ${fcValue(p['overall'])}',
                          value: fcChoiceLabel(
                            _link!.players[fcId(p['id'])],
                            _players,
                          ),
                          onTap: _saving ? null : () => _mapPlayer(p),
                          icon: Icons.person_outline,
                        ),
                  ],
                  FilledButton.icon(
                    key: const Key('fc-bind'),
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(_saving ? 'Salvando…' : 'Salvar vínculo'),
                  ),
                ],
                if (_error != null) FcNotice(_error!, error: true),
                const SizedBox(height: 24),
              ],
            ),
    ),
  );
}
