import 'package:flutter/material.dart';

import '../models/Person.dart';
import '../models/Season.dart';
import '../utils/Components/CareerPageWidgets.dart';
import '../utils/GameCatalog.dart';
import '../utils/PlayerClubLookup.dart';
import 'FcScoreApi.dart';
import 'FcScoreMappingIssues.dart';
import 'FcScoreModels.dart';
import 'FcScoreRepository.dart';
import 'FcScoreWidgets.dart';
import 'FcScoreWorldData.dart';
import 'FcScoreWorldMatchesPage.dart';
import 'FcScoreWorldPlayerReview.dart';
import 'FcScoreWorldPlayerDialog.dart';
import 'FcScorePlayerCreation.dart';
import 'CareerCompetitionsPage.dart';
import 'FcScoreSyncProgress.dart';
import 'FcScoreClubCatalog.dart';
import 'FcScoreClubMappingWidgets.dart';
import 'FcScoreUpdateOptions.dart';

class FcScoreWorldImportPage extends StatefulWidget {
  const FcScoreWorldImportPage({
    super.key,
    required this.api,
    required this.remote,
    required this.repository,
    required this.person,
    required this.link,
    this.automatic = false,
    this.syncProgress,
    this.onCustomize,
    this.personalize = false,
    this.updateOptions,
  });
  final FcScoreApi api;
  final FcScoreRemoteCareer remote;
  final FcScoreRepository repository;
  final Person person;
  final FcScoreLink link;
  final bool automatic;
  final FcScoreSyncProgress? syncProgress;
  final VoidCallback? onCustomize;
  final bool personalize;
  final FcScoreUpdateOptions? updateOptions;
  @override
  State<FcScoreWorldImportPage> createState() => _FcScoreWorldImportPageState();
}

class _FcScoreWorldImportPageState extends State<FcScoreWorldImportPage> {
  late FcScoreLink _link = widget.link.copy();
  FcScoreLink? _confirmedLink;
  bool _updating = false, _automaticCanceled = false;
  late bool _customizing = widget.personalize;
  bool get _quickMode => _updating && !_customizing;
  final _selected = <String>{};
  List<FcJson> _calendar = [], _competitions = [];
  List<Season> _seasons = [];
  List<CatalogItem> _teams = [],
      _leagues = [],
      _tournaments = [],
      _players = [];
  FcScoreWorldData? _data;
  FcWorldPlayerReview? _playerReview;
  List<FcWorldPlayerIssue> get _playerIssues =>
      _playerReview?.issues(_link.players) ?? [];
  FcWorldImportResult? _result;
  PlayerClubLookup? _playerClubs;
  List<FcWorldMatchPreview> _matches = [];
  final _matchKeys = <String>{};
  bool _matchesReady = false;
  bool _mappingReviewed = false, _preserveOwnPlayers = true;
  bool _busy = true,
      _saving = false,
      _ownMatches = true,
      _ownSquad = false,
      _overalls = true;
  String? _error;
  List<FcWorldMappingIssue> _mappingIssues = [];
  String _progress = 'Carregando competições da carreira';
  @override
  void initState() {
    super.initState();
    if (widget.automatic) {
      _runAutomatic();
    } else {
      _load();
    }
  }

  Future<void> _runAutomatic() async {
    await _load();
    if (!mounted || _error != null || _automaticCanceled) return;
    await _update();
    if (!mounted || _automaticCanceled) return;
    if (_result != null) {
      widget.syncProgress?.advance(1, 'Atualização concluída');
    } else if (_error == null) {
      setState(
        () => _error = 'Atualização cancelada. Nenhum dado foi importado.',
      );
    }
  }

  void _status(String value) {
    if (_automaticCanceled) {
      throw const FcScoreException(
        'Atualização automática interrompida para personalizar.',
      );
    }
    if (!mounted) throw const FcScoreException('Leitura cancelada.');
    if (mounted) setState(() => _progress = value);
    widget.syncProgress?.advance(widget.syncProgress!.value, value);
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.repository.linkFor(widget.person.id);
      if (saved?.belongsTo(widget.remote, widget.person) == true) {
        _confirmedLink = saved!.copy();
        _link = _link.withSavedMappings(saved);
      }
      final catalog = await GameCatalog.load();
      await GameCatalog.reloadCustomData();
      final clubs = await FcScoreClubCatalog.load(
        widget.repository.sql,
        widget.person.fifaVersion,
      );
      _teams = clubs.teams;
      _leagues = clubs.leagues;
      _tournaments = [
        ...await catalog.tournaments(widget.person.fifaVersion),
        for (final l in _leagues) CatalogItem('league:${l.id}', l.label),
        for (final t in await widget.repository.sql.getCustomTournaments(
          widget.person.fifaVersion,
        ))
          CatalogItem(t.id, t.name),
      ];
      _players = (await widget.repository.sql.getCustomPlayers(
        widget.person.id,
      )).map((p) => CatalogItem(fcId(p['id']), fcId(p['name']))).toList();
      _seasons = (await widget.repository.sql.getSeasons(widget.person.id))
          .where((s) => !s.isClosed)
          .toList();
      final current = DateTime.tryParse(
        fcId(widget.remote.overview['currentDate']),
      );
      final fits = _seasons
          .where(
            (s) =>
                current != null &&
                !current.isBefore(s.startDate) &&
                !current.isAfter(s.endDate),
          )
          .toList();
      if (fits.length == 1) _link.seasonId = fits.single.id;
      _calendar = await FcScoreWorldData.fixturesFor(
        widget.api,
        _link.saveId,
        onProgress: _status,
      );
      widget.syncProgress?.advance(.25, 'Calendário conferido');
      final byId = <String, FcJson>{
        for (final c in widget.remote.competitions) fcId(c['id']): c,
      };
      for (final f in _calendar) {
        final c = fcObject(f['competition']);
        if (fcId(c['id']).isNotEmpty) byId[fcId(c['id'])] = c;
      }
      _competitions = byId.values.toList()
        ..sort((a, b) => fcName(a['name']).compareTo(fcName(b['name'])));
      await _restoreChoices();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restoreChoices() async {
    _playerClubs = null;
    final previous = await widget.repository.previousWorldSync(
      widget.person,
      _link,
    );
    _updating = previous != null || _confirmedLink != null;
    final past = _link.worldSync.values.toList()
      ..sort((a, b) => fcId(b.importedAt).compareTo(fcId(a.importedAt)));
    final preferences = previous ?? past.firstOrNull;
    _selected.clear();
    _selected.addAll(
      previous?.competitionIds ??
          widget.remote.competitions.map((c) => fcId(c['id'])),
    );
    _selected.retainAll(_competitions.map((c) => fcId(c['id'])).toSet());
    if (_selected.isEmpty) {
      _selected.addAll(widget.remote.competitions.map((c) => fcId(c['id'])));
    }
    _preserveOwnPlayers = preferences?.preserveOwnPlayers ?? true;
    _ownSquad = preferences?.bringOwnSquad ?? false;
    _overalls = preferences?.updateOveralls ?? true;
    _ownMatches = !widget.automatic;
    final options = widget.updateOptions;
    if (options != null) {
      _ownSquad = options.ownSquad;
      _preserveOwnPlayers = !options.ownSquad;
      _overalls = options.overalls;
      _link.updateOptions = options;
    }
    if (previous != null) _link.worldSync[_link.seasonId] = previous;
  }

  Future<void> _update() async {
    setState(() => _error = null);
    if (_data == null || !_matchesReady) await _prepare();
    if (!mounted ||
        _data == null ||
        _error != null ||
        !_matchesReady ||
        _automaticCanceled) {
      return;
    }
    await _save();
  }

  Future<void> _prepare() async {
    setState(() {
      _busy = true;
      _error = null;
      _mappingReviewed = false;
    });
    try {
      final season = _seasons.where((s) => s.id == _link.seasonId).firstOrNull;
      if (season == null) {
        throw const FcScoreException('Escolha uma temporada aberta.');
      }
      final data = await FcScoreWorldData.load(
        api: widget.api,
        remote: widget.remote,
        season: season,
        calendar: _calendar,
        competitionIds: _selected,
        updateOptions: widget.updateOptions,
        onProgress: _status,
        onFraction: (v) =>
            widget.syncProgress?.advance(.25 + .5 * v, _progress),
      );
      for (final c in data.competitions) {
        final ref = fcObject(c['competition']), id = fcId(ref['id']);
        _suggestEntity(_link.competitions, id, ref, _tournaments);
      }
      final localPlayers = await widget.repository.sql.getCustomPlayers(
        widget.person.id,
      );
      final ownLeagueId = fcId(widget.remote.league['id']);
      if (ownLeagueId.isNotEmpty) {
        _link.leagues.putIfAbsent(ownLeagueId, () => _link.localLeagueId);
      }
      for (final t in data.teams) {
        final league = fcObject(t['league']), id = fcId(league['id']);
        if (id.isNotEmpty) {
          if (fcId(t['id']) == _link.remoteClubId) {
            _link.leagues.putIfAbsent(id, () => _link.localLeagueId);
          }
          _suggestEntity(_link.leagues, id, league, _leagues);
        }
        if (fcId(t['id']) == _link.remoteClubId) {
          _link.teams[_link.remoteClubId] = _link.localClubId;
        } else {
          _suggestEntity(
            _link.teams,
            fcId(t['id']),
            t,
            _teams,
            leagueId: _link.leagues[id],
          );
        }
      }
      final ownPlayers = await widget.repository.sql.getTeamPlayers(
        widget.person.id,
        _link.seasonId,
      );
      _link.players.addAll(
        fcSuggestWorldPlayers(
          data,
          localPlayers,
          mapping: _link.players,
          ownClubId: _link.remoteClubId,
          ownPlayerIds: ownPlayers.map((p) => fcId(p['playerId'])).toSet(),
        ),
      );
      _data = data;
      await _checkPlayers();
      await _refreshMatches(reset: true);
      widget.syncProgress?.advance(.8, 'Conferindo novidades e vínculos');
      _mappingReviewed =
          _updating &&
          [
            'Competições',
            'Equipes',
            'Ligas',
            'Jogadores',
          ].every((kind) => _pendingIds(kind).isEmpty);
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  void _suggestEntity(
    Map<String, String> mapping,
    String id,
    FcJson ref,
    List<CatalogItem> items, {
    String? leagueId,
  }) {
    final old = mapping[id];
    if (old == null || old.startsWith('new:')) {
      mapping[id] =
          fcSuggestReference(ref, items, leagueId: leagueId) ??
          old ??
          'new:${fcName(ref['name'])}';
    }
  }

  Future<void> _checkPlayers() async {
    _playerReview = await widget.repository.reviewWorldPlayers(
      person: widget.person,
      link: _link,
      data: _data!,
      preserveOwnPlayers: _preserveOwnPlayers,
    );
    if (_playerReview!.issues(_link.players).isNotEmpty) {
      _playerClubs ??= await PlayerClubLookup.load(
        sql: widget.repository.sql,
        person: widget.person,
        seasonId: _link.seasonId,
      );
    }
    _players = [
      for (final p in _playerReview!.local.entries)
        CatalogItem(p.key, fcId(p.value['name'])),
    ];
  }

  Future<bool> _correctPlayers() async {
    final corrected = await fcCorrectWorldPlayers(
      context,
      review: _playerReview!,
      mapping: _link.players,
      playerVersion: widget.person.fifaVersion,
      playerClubs: _playerClubs,
    );
    if (!mounted) return false;
    if (corrected == null) {
      setState(() {});
      return false;
    }
    setState(() {
      _link.players.addAll(corrected);
      _error = null;
    });
    return _playerIssues.isEmpty;
  }

  Future<bool> _correctMappings() async {
    while (mounted) {
      final issues = await widget.repository.worldMappingIssues(
        person: widget.person,
        link: _link,
        data: _data!,
      );
      if (!mounted) return false;
      setState(() {
        _mappingIssues = issues;
        _busy = false;
        _saving = false;
        _error = issues.isEmpty
            ? null
            : issues.map((i) => i.message).join('\n\n');
      });
      if (issues.isEmpty) return true;
      final issue = issues.first;
      final edit = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(
            'Corrigir vínculos · ${issues.length} ${issues.length == 1 ? 'pendência' : 'pendências'}',
          ),
          content: SingleChildScrollView(child: Text(issue.message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Agora não'),
            ),
            if (!issue.sourceProblem)
              FilledButton(
                key: const Key('fc-correct-mapping'),
                onPressed: () => Navigator.pop(c, true),
                child: Text(
                  issue.restoreOwnClub
                      ? 'Manter meu clube'
                      : 'Corrigir este vínculo',
                ),
              ),
          ],
        ),
      );
      if (!mounted || edit != true) return false;
      if (issue.restoreOwnClub) {
        _link.teams[_link.remoteClubId] = _link.localClubId;
      } else {
        if (!await _review(
          issue.kind,
          requiredReview: true,
          onlyIds: issue.remoteIds,
        )) {
          return false;
        }
      }
    }
    return false;
  }

  Future<bool> _review(
    String kind, {
    bool requiredReview = false,
    Set<String>? onlyIds,
  }) async {
    final data = _data!;
    final rows = <String, FcJson>{};
    if (kind == 'Competições') {
      for (final c in data.competitions) {
        final ref = fcObject(c['competition']);
        rows[fcId(ref['id'])] = ref;
      }
    } else if (kind == 'Equipes') {
      for (final t in data.teams) {
        rows[fcId(t['id'])] = t;
      }
    } else if (kind == 'Ligas') {
      for (final t in data.teams) {
        final l = fcObject(t['league']);
        if (fcId(l['id']).isNotEmpty) rows[fcId(l['id'])] = l;
      }
    } else {
      for (final t in data.teams) {
        for (final p in fcList(t['roster'])) {
          rows[fcId(p['id'])] = p;
        }
      }
    }
    final mapping = kind == 'Competições'
        ? _link.competitions
        : kind == 'Equipes'
        ? _link.teams
        : kind == 'Ligas'
        ? _link.leagues
        : _link.players;
    if (onlyIds != null) rows.removeWhere((id, _) => !onlyIds.contains(id));
    if (kind == 'Jogadores') {
      _playerClubs ??= await PlayerClubLookup.load(
        sql: widget.repository.sql,
        person: widget.person,
        seasonId: _link.seasonId,
      );
      if (!mounted) return false;
    }
    final completed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _WorldMappingPage(
          title: kind,
          rows: rows,
          mapping: mapping,
          items: kind == 'Competições'
              ? _tournaments
              : kind == 'Equipes'
              ? _teams
              : kind == 'Ligas'
              ? _leagues
              : _players,
          player: kind == 'Jogadores',
          playerVersion: widget.person.fifaVersion,
          playerClubs: _playerClubs,
          requiredReview: requiredReview,
          configuredIds: _updating && onlyIds == null
              ? _configuredIds(kind)
              : const {},
          updating: _updating,
          playerReview: kind == 'Jogadores' ? _playerReview : null,
          ownClubId: _link.remoteClubId,
          leagues: _leagues,
          leagueMapping: _link.leagues,
          onConfirm: kind == 'Jogadores'
              ? () async {
                  await _checkPlayers();
                  return _playerIssues.isEmpty || await _correctPlayers();
                }
              : onlyIds == null
              ? null
              : () async {
                  final issues = await widget.repository.worldMappingIssues(
                    person: widget.person,
                    link: _link,
                    data: _data!,
                  );
                  final related = issues
                      .where(
                        (i) =>
                            i.kind == kind && i.remoteIds.any(onlyIds.contains),
                      )
                      .toList();
                  if (related.isEmpty) return true;
                  if (!mounted) return false;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(related.first.message)),
                  );
                  return false;
                },
          fixedId: kind == 'Equipes'
              ? _link.remoteClubId
              : kind == 'Ligas'
              ? fcId(widget.remote.league['id'])
              : null,
        ),
      ),
    );
    if (!mounted) return false;
    if (kind == 'Competições' || kind == 'Equipes') {
      setState(() => _busy = true);
      try {
        await _refreshMatches();
      } catch (e) {
        _error = '$e';
      }
      if (!mounted) return false;
      setState(() => _busy = false);
    } else {
      try {
        if (kind == 'Jogadores') await _checkPlayers();
      } catch (e) {
        _error = '$e';
      }
      if (mounted) setState(() {});
    }
    return completed == true;
  }

  Set<String> _entityConflicts(String kind) {
    final mapping = kind == 'Competições'
        ? _link.competitions
        : kind == 'Equipes'
        ? _link.teams
        : _link.leagues;
    final items = kind == 'Competições'
        ? _tournaments
        : kind == 'Equipes'
        ? _teams
        : _leagues;
    final ids = kind == 'Competições'
        ? _data!.competitions
              .map((c) => fcId(fcObject(c['competition'])['id']))
              .toSet()
        : kind == 'Equipes'
        ? _data!.teams.map((t) => fcId(t['id'])).toSet()
        : _data!.teams
              .map((t) => fcId(fcObject(t['league'])['id']))
              .where((id) => id.isNotEmpty)
              .toSet();
    final conflicts = <String>{}, seen = <String, String>{};
    for (final id in ids) {
      final choice = mapping[id];
      final isNew = choice?.startsWith('new:') == true;
      final valid =
          choice != null &&
          (isNew
              ? fcNormalize(choice.substring(4)).isNotEmpty
              : items.any((i) => i.id == choice));
      if (!valid) {
        conflicts.add(id);
        continue;
      }
      if (kind == 'Ligas') continue;
      final identity = isNew
          ? 'new:${fcNormalize(choice.substring(4))}'
          : choice;
      final other = seen[identity];
      if (other != null) conflicts.addAll([id, other]);
      seen[identity] = id;
    }
    return conflicts;
  }

  Map<String, String> _mapping(String kind, FcScoreLink link) =>
      kind == 'Competições'
      ? link.competitions
      : kind == 'Equipes'
      ? link.teams
      : kind == 'Ligas'
      ? link.leagues
      : link.players;
  Set<String> _sourceIds(String kind) => kind == 'Competições'
      ? _data!.competitions
            .map((c) => fcId(fcObject(c['competition'])['id']))
            .toSet()
      : kind == 'Equipes'
      ? _data!.teams.map((t) => fcId(t['id'])).toSet()
      : kind == 'Ligas'
      ? _data!.teams
            .map((t) => fcId(fcObject(t['league'])['id']))
            .where((id) => id.isNotEmpty)
            .toSet()
      : _playerReview!.players.keys.toSet();
  Set<String> _configuredIds(String kind) {
    final saved = _confirmedLink;
    if (!_updating || saved == null) return {};
    final previous = _mapping(kind, saved), current = _mapping(kind, _link);
    final conflicts = kind == 'Jogadores'
        ? {
            for (final issue in _playerIssues)
              for (final p in issue.players) p.id,
          }
        : _entityConflicts(kind);
    return {
      for (final id in _sourceIds(kind))
        if (!conflicts.contains(id))
          if (kind == 'Jogadores' && _playerReview!.isProtected(id) ||
              previous[id] == current[id] &&
                  current[id] != null &&
                  (kind == 'Jogadores'
                      ? !fcIsPlayerCreation(current[id])
                      : !current[id]!.startsWith('new:')))
            id,
    };
  }

  Set<String> _pendingIds(String kind) =>
      _sourceIds(kind).difference(_configuredIds(kind));

  Future<void> _reviewAll() async {
    for (final kind in ['Competições', 'Equipes', 'Ligas', 'Jogadores']) {
      if (_updating && _pendingIds(kind).isEmpty) continue;
      if (!await _review(kind, requiredReview: true) || !mounted) return;
    }
    if (mounted) setState(() => _mappingReviewed = true);
  }

  Future<void> _setOwnPlayers(bool update) async {
    setState(() {
      _preserveOwnPlayers = !update;
      if (!update) _ownSquad = false;
      _mappingReviewed = false;
      if (_data != null) _busy = true;
    });
    if (_data == null) return;
    try {
      await _checkPlayers();
      _mappingReviewed =
          _updating &&
          [
            'Competições',
            'Equipes',
            'Ligas',
            'Jogadores',
          ].every((kind) => _pendingIds(kind).isEmpty);
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _playerOptions() => Column(
    children: [
      SwitchListTile(
        key: const Key('fc-update-own-players'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Atualizar jogadores do meu clube'),
        subtitle: const Text(
          'Desligado: mantém seu elenco e overalls. Os dados da API continuam disponíveis nas competições.',
        ),
        value: !_preserveOwnPlayers,
        onChanged: _busy ? null : _setOwnPlayers,
      ),
      if (!_preserveOwnPlayers &&
          widget.person.category == PersonCategory.manager)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Adicionar meu elenco à central'),
          subtitle: const Text('Jogadores novos entram como reservas.'),
          value: _ownSquad,
          onChanged: _busy ? null : (v) => setState(() => _ownSquad = v),
        ),
    ],
  );

  Future<void> _refreshMatches({bool reset = false}) async {
    _matchesReady = false;
    final matches = await widget.repository.previewWorldMatches(
      person: widget.person,
      link: _link,
      data: _data!,
    );
    final available = matches
        .where((item) => !item.exists)
        .map((item) => item.match.remoteKey)
        .toSet();
    if (widget.automatic) {
      _matchKeys.clear();
    } else if (reset) {
      _matchKeys.clear();
      _matchKeys.addAll(
        matches
            .where((item) => !item.exists && !item.ignored)
            .map((item) => item.match.remoteKey),
      );
    } else {
      _matchKeys.retainAll(available);
    }
    _matches = matches;
    _matchesReady = true;
  }

  Future<void> _chooseMatches() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Conferindo partidas já cadastradas';
    });
    try {
      await _refreshMatches();
      if (!mounted) return;
      final selected = await Navigator.push<Set<String>>(
        context,
        MaterialPageRoute(
          builder: (_) => FcScoreWorldMatchesPage(
            matches: _matches,
            selectedKeys: _matchKeys,
          ),
        ),
      );
      if (selected != null) {
        _matchKeys.clear();
        _matchKeys.addAll(selected);
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    if (_automaticCanceled) return;
    if (!_mappingReviewed && !_quickMode) {
      await _reviewAll();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Conferindo vínculos dos jogadores';
    });
    try {
      if (!await _correctMappings() || !mounted) return;
      setState(() => _busy = true);
      await _checkPlayers();
      if (!mounted || _automaticCanceled) return;
      if (_playerIssues.isNotEmpty) {
        setState(() => _busy = false);
        if (!await _correctPlayers()) return;
      }
      if (!mounted) return;
      if (widget.automatic && !await _confirmAdditions()) return;
      if (!mounted || _automaticCanceled) return;
      setState(() {
        _busy = true;
        _saving = true;
        _progress = 'Salvando na carreira';
      });
      widget.syncProgress?.advance(.85, _progress);
      final result = await widget.repository.importWorld(
        person: widget.person,
        link: _link,
        data: _data!,
        importOwnMatches: _ownMatches,
        rememberSkippedOwnMatches: !widget.automatic,
        selectedOwnMatchKeys: _matchKeys,
        bringOwnSquad: _ownSquad,
        updateOveralls: _overalls,
        preserveOwnPlayers: _preserveOwnPlayers,
        updateOptions: widget.updateOptions,
        onProgress: (v) =>
            widget.syncProgress?.advance(.85 + .14 * v, _progress),
      );
      widget.link.teams.addAll(_link.teams);
      widget.link.players.addAll(_link.players);
      widget.link.competitions.addAll(_link.competitions);
      widget.link.leagues.addAll(_link.leagues);
      widget.link.seasonId = _link.seasonId;
      widget.link.worldSync.addAll(_link.worldSync);
      _result = result;
    } on FcWorldMappingException catch (e) {
      _mappingIssues = e.issues;
      _error = '$e';
      if (mounted) {
        setState(() {
          _saving = false;
          _busy = false;
        });
        await _correctMappings();
      }
    } on FcWorldPlayerMappingException catch (e) {
      _playerReview = e.review;
      if (mounted) {
        setState(() {
          _saving = false;
          _busy = false;
        });
        await _correctPlayers();
      }
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _saving = false;
        });
      }
    }
  }

  Future<bool> _confirmAdditions() async {
    final additions = await widget.repository.previewWorldAdditions(
      person: widget.person,
      link: _link,
      data: _data!,
      selectedMatchKeys: _matchKeys,
      includeCalendarMatches: !widget.automatic,
    );
    if (!mounted || _automaticCanceled) return false;
    if (additions.teams == 0 && additions.matches == 0) return true;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Novidades na carreira'),
            titleTextStyle: Theme.of(context).dialogTheme.titleTextStyle
                ?.copyWith(fontFamily: 'Manrope'),
            contentTextStyle: Theme.of(context).dialogTheme.contentTextStyle
                ?.copyWith(fontFamily: 'Manrope'),
            content: Text(
              'A atualização vai incluir ${additions.matches} ${additions.matches == 1 ? 'partida' : 'partidas'} e '
              '${additions.teams} ${additions.teams == 1 ? 'equipe' : 'equipes'}. Deseja continuar? Os jogos já configurados '
              'e as partidas ignoradas serão preservados.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancelar'),
              ),
              if (widget.onCustomize != null)
                TextButton(
                  onPressed: () {
                    Navigator.pop(c, false);
                    _customizeAutomatic();
                  },
                  child: const Text('Personalizar'),
                ),
              FilledButton(
                key: const Key('fc-sync-confirm'),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Atualizar'),
              ),
            ],
          ),
        ) ==
        true;
  }

  void _customizeAutomatic() {
    if (_automaticCanceled) return;
    _automaticCanceled = true;
    widget.onCustomize?.call();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data, result = _result;
    if (widget.automatic) {
      return PopScope(
        canPop: !_saving,
        child: FcScoreSyncProgressView(
          progress: widget.syncProgress!,
          complete: result != null,
          error: _error,
          summary: result == null
              ? null
              : '${result.competitions} ${result.competitions == 1 ? 'competição atualizada' : 'competições atualizadas'}.\n'
                    '${result.fixtures} jogos no calendário · ${result.ownMatches} adicionados em Partidas.\n'
                    'Jogadores: ${result.newPlayers} novos · ${result.reusedPlayers} reutilizados.',
          onClose: _saving
              ? null
              : () => Navigator.pop(context, result != null ? 'updated' : null),
          onCustomize: _saving || widget.onCustomize == null
              ? null
              : _customizeAutomatic,
        ),
      );
    }
    final selectedSeason = _seasons
        .where((s) => s.id == _link.seasonId)
        .firstOrNull;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _updating ? 'Atualizar carreira' : 'Importar para carreira',
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (!_quickMode)
                const CareerPageHeader(
                  title: 'O campeonato na sua carreira',
                  subtitle: 'Tabelas, jogos e elencos das equipes ficam salvos nesta temporada e disponíveis sem o PC.',
                  icon: Icons.download_rounded,
                  eyebrow: 'FC Score',
                ),
              if (_busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 14),
                Text(_progress),
                const SizedBox(height: 20),
              ],
              if (_error != null) FcNotice(_error!, error: true),
              if (_mappingIssues.isNotEmpty && !_busy)
                TextButton.icon(
                  key: const Key('fc-review-mapping-issues'),
                  onPressed: _correctMappings,
                  icon: const Icon(Icons.link),
                  label: const Text('Corrigir vínculos indicados'),
                ),
              if (result != null) ...[
                FcPanel(
                  child: Column(
                    children: [
                      FcSection(
                        _updating
                            ? 'Atualização concluída'
                            : 'Importação concluída',
                      ),
                      FcFact('Competições', result.competitions),
                      FcFact('Equipes', result.teams),
                      FcFact('Jogadores', result.players),
                      FcFact('Jogadores novos', result.newPlayers),
                      FcFact('Jogadores reutilizados', result.reusedPlayers),
                      FcFact('Jogos no calendário', result.fixtures),
                      FcFact(
                        'Partidas do seu clube adicionadas',
                        result.ownMatches,
                      ),
                      FcFact(
                        'Partidas existentes preservadas',
                        result.preservedMatches,
                      ),
                      FcFact(
                        'Partidas não selecionadas',
                        result.skippedMatches,
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CareerCompetitionsPage(
                        person: widget.person,
                        repository: widget.repository,
                        initialSeasonId: _link.seasonId,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('Ver competições da carreira'),
                ),
              ] else if (_quickMode) ...[
                FcPanel(
                  child: Column(
                    children: [
                      const FcSection('Atualizar dados da carreira'),
                      FcFact(
                        'Temporada',
                        selectedSeason == null
                            ? 'Selecionar'
                            : '${selectedSeason.startDate.year}/${selectedSeason.endDate.year}',
                      ),
                      FcFact('Torneios', _selected.length),
                      if (_link.worldSync[_link.seasonId]?.importedAt != null)
                        FcFact(
                          'Última atualização',
                          fcDay(_link.worldSync[_link.seasonId]?.importedAt),
                        ),
                      if (data != null)
                        FcFact('Partidas novas', _matchKeys.length),
                    ],
                  ),
                ),
                const FcNotice(
                  'Seus vínculos e escolhas serão reutilizados. Partidas já cadastradas ou ignoradas não entram novamente; somente jogos novos. Se houver conflitos, você poderá resolvê-los antes de salvar.',
                ),
                FilledButton.icon(
                  key: const Key('fc-world-update'),
                  onPressed: _busy || _selected.isEmpty ? null : _update,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Atualizar carreira'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('fc-world-customize'),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _customizing = true;
                          _mappingReviewed = false;
                        }),
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Personalizar atualização'),
                ),
                if (data == null && _error != null)
                  TextButton(
                    onPressed: _busy ? null : _load,
                    child: const Text('Tentar carregar novamente'),
                  ),
              ] else if (data == null) ...[
                FcChoice(
                  title: 'Temporada no aplicativo',
                  value: selectedSeason == null
                      ? 'Selecionar temporada'
                      : '${fcDay(selectedSeason.startDate)} a ${fcDay(selectedSeason.endDate)}',
                  onTap: _busy
                      ? null
                      : () async {
                          final selected = await fcPick(
                            context,
                            title: 'Temporada da importação',
                            items: [
                              for (final s in _seasons)
                                CatalogItem(
                                  s.id,
                                  '${fcDay(s.startDate)} a ${fcDay(s.endDate)}',
                                ),
                            ],
                          );
                          if (selected != null && mounted) {
                            setState(() {
                              _link.seasonId = selected;
                              _busy = true;
                            });
                            await _restoreChoices();
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                ),
                const FcSection(
                  'Competições',
                  subtitle: 'Selecione as que deseja acompanhar. Os participantes e seus elencos serão incluídos.',
                ),
                if (_competitions.isNotEmpty)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            if (_selected.length == _competitions.length) {
                              _selected.clear();
                            } else {
                              _selected.addAll(
                                _competitions.map((c) => fcId(c['id'])),
                              );
                            }
                          }),
                    child: Text(
                      _selected.length == _competitions.length
                          ? 'Desmarcar todas'
                          : 'Selecionar todas',
                    ),
                  ),
                for (final c in _competitions)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(fcName(c['name'])),
                    value: _selected.contains(fcId(c['id'])),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            v == true
                                ? _selected.add(fcId(c['id']))
                                : _selected.remove(fcId(c['id']));
                          }),
                  ),
                const SizedBox(height: 16),
                _playerOptions(),
                FilledButton.icon(
                  onPressed: _busy || _selected.isEmpty ? null : _prepare,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(
                    _updating ? 'Preparar atualização' : 'Preparar importação',
                  ),
                ),
                if (_error != null)
                  TextButton(
                    onPressed: _busy ? null : _load,
                    child: const Text('Tentar carregar novamente'),
                  ),
              ] else ...[
                if (_playerIssues.isNotEmpty)
                  FcChoice(
                    title: 'Vínculos precisam de correção',
                    value:
                        '${_playerIssues.length} ${_playerIssues.length == 1 ? 'etapa' : 'etapas'} · Corrigir agora',
                    icon: Icons.warning_amber_rounded,
                    onTap: _busy ? null : _correctPlayers,
                  ),
                FcPanel(
                  child: Column(
                    children: [
                      FcFact('Competições', data.competitions.length),
                      FcFact('Equipes', data.teams.length),
                      FcFact('Jogadores nos elencos', data.playerCount),
                      FcFact(
                        'Jogos e próximos confrontos',
                        data.fixtures.length,
                      ),
                      FcFact('Data do save', fcDay(data.currentDate)),
                    ],
                  ),
                ),
                if (data.excludedFixtures > 0)
                  FcNotice(
                    '${data.excludedFixtures} jogos sem data/equipes definidas ou fora desta temporada não serão incluídos.',
                  ),
                FcNotice(
                  _mappingReviewed
                      ? (_updating
                            ? 'Vínculos salvos reutilizados. Confira as opções da atualização.'
                            : 'De-para revisado. Confira o resumo antes de importar.')
                      : (_updating
                            ? 'Revise somente os vínculos novos ou que precisam de correção. Os já configurados são reutilizados.'
                            : 'Revise competições, equipes, ligas e jogadores antes de importar. Nenhum cadastro será gravado durante a revisão.'),
                ),
                for (final kind in [
                  'Competições',
                  'Equipes',
                  'Ligas',
                  'Jogadores',
                ])
                  FcChoice(
                    title: 'De-para',
                    value: kind,
                    onTap: _busy
                        ? null
                        : () async {
                            setState(() => _mappingReviewed = false);
                            await _review(kind);
                          },
                  ),
                if (widget.person.category == PersonCategory.manager) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _updating
                          ? 'Adicionar jogos novos do meu clube'
                          : 'Importar jogos do meu clube',
                    ),
                    subtitle: const Text(
                      'Escolha abaixo quais resultados entram em Partidas e nas estatísticas. Jogos já configurados são preservados.',
                    ),
                    value: _ownMatches,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _ownMatches = v),
                  ),
                  if (_ownMatches) ...[
                    FcChoice(
                      title: 'Revisar partidas',
                      value:
                          '${_matchKeys.length} selecionadas · ${_matches.where((item) => item.exists).length} já cadastradas · ${_matches.where((item) => item.ignored && !item.exists).length} ignoradas',
                      icon: Icons.fact_check_outlined,
                      onTap: _busy ? null : _chooseMatches,
                    ),
                    if (_matches.isEmpty && _matchesReady)
                      const FcNotice(
                        'Nenhum jogo realizado do seu clube nas competições selecionadas.',
                      ),
                  ],
                ],
                _playerOptions(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Registrar overalls atuais'),
                  subtitle: Text(
                    _preserveOwnPlayers
                        ? 'Somente dos outros clubes. Os overalls do seu elenco serão mantidos.'
                        : 'Dos jogadores incluídos nesta importação.',
                  ),
                  value: _overalls,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _overalls = v),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy || !_matchesReady ? null : _save,
                  key: const Key('fc-world-primary'),
                  icon: Icon(
                    _mappingReviewed
                        ? Icons.download_rounded
                        : Icons.fact_check_outlined,
                  ),
                  label: Text(
                    _mappingReviewed
                        ? (_updating
                              ? 'Atualizar carreira'
                              : 'Importar para carreira')
                        : (_updating ? 'Revisar novidades' : 'Revisar de-para'),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _data = null),
                  child: const Text('Alterar seleção'),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorldMappingPage extends StatefulWidget {
  const _WorldMappingPage({
    required this.title,
    required this.rows,
    required this.mapping,
    required this.items,
    required this.player,
    required this.playerVersion,
    this.playerClubs,
    this.fixedId,
    this.requiredReview = false,
    this.playerReview,
    this.ownClubId,
    this.onConfirm,
    this.configuredIds = const {},
    this.updating = false,
    this.leagues = const [],
    this.leagueMapping = const {},
  });
  final String title;
  final String playerVersion;
  final PlayerClubLookup? playerClubs;
  final Map<String, FcJson> rows;
  final Map<String, String> mapping;
  final List<CatalogItem> items;
  final bool player;
  final String? fixedId;
  final bool requiredReview;
  final FcWorldPlayerReview? playerReview;
  final String? ownClubId;
  final Future<bool> Function()? onConfirm;
  final Set<String> configuredIds;
  final bool updating;
  final List<CatalogItem> leagues;
  final Map<String, String> leagueMapping;
  @override
  State<_WorldMappingPage> createState() => _WorldMappingPageState();
}

class _WorldMappingPageState extends State<_WorldMappingPage> {
  final _search = TextEditingController();
  String _scope = 'Todos';
  bool _showConfigured = false;
  bool _confirming = false;
  bool get _clubs => widget.title == 'Equipes';

  String _leagueId(FcJson team) => fcId(fcObject(team['league'])['id']);
  String _leagueLabel(FcJson team) {
    final league = fcObject(team['league']);
    final choice = widget.leagueMapping[fcId(league['id'])];
    if (choice?.startsWith('new:') == true) return choice!.substring(4);
    return widget.leagues.where((l) => l.id == choice).firstOrNull?.label ??
        fcName(league['name'], 'Outras equipes');
  }

  List<FcClubLeagueGroup<MapEntry<String, FcJson>>> _clubGroups(
    List<MapEntry<String, FcJson>> rows,
  ) {
    final grouped = <String, List<MapEntry<String, FcJson>>>{};
    for (final row in rows) {
      (grouped[_leagueId(row.value)] ??= []).add(row);
    }
    final preferred = _leagueId(widget.rows[widget.ownClubId] ?? {});
    return [
      for (final g in grouped.entries)
        FcClubLeagueGroup(g.key, _leagueLabel(g.value.first.value), g.value),
    ]..sort(
      (a, b) => a.id == b.id
          ? 0
          : a.id == preferred
          ? -1
          : b.id == preferred
          ? 1
          : fcNormalize(a.label).compareTo(fcNormalize(b.label)),
    );
  }

  Widget _row(MapEntry<String, FcJson> row) => FcChoice(
    key: ValueKey('fc-world-mapping-${row.key}'),
    title: widget.player
        ? '${fcPlayerName(row.value)} · ${widget.playerReview?.players[row.key]?.teams.join(' / ') ?? ''}'
        : fcName(row.value['name']),
    value: _label(row.key),
    leading: _clubs
        ? FcClubLogo(
            item: widget.items
                .where((t) => t.id == widget.mapping[row.key])
                .firstOrNull,
          )
        : null,
    onTap: row.key == widget.fixedId || _protected(row.key) || _confirming
        ? null
        : () async {
            final selected = await fcPick(
              context,
              title: fcName(row.value['name']),
              items: widget.items,
              clubLeagues: _clubs ? widget.leagues : null,
              selectedId: _clubs ? widget.mapping[row.key] : null,
              preferredLeagueId: _clubs
                  ? widget.leagueMapping[_leagueId(row.value)]
                  : null,
              newPlayer: widget.player,
              playerVersion: widget.player ? widget.playerVersion : null,
              playerRows: widget.playerReview?.local ?? const {},
              playerClubs: widget.playerClubs,
              playerSource: widget.player ? row.value : null,
              playerChoice: widget.player ? widget.mapping[row.key] : null,
              createName: widget.player ? null : fcName(row.value['name']),
            );
            if (selected != null && mounted) {
              setState(() => widget.mapping[row.key] = selected);
            }
          },
  );

  bool _own(String id) =>
      widget.playerReview?.players[id]?.teamIds.contains(widget.ownClubId) ==
      true;
  bool _protected(String id) => widget.playerReview?.isProtected(id) == true;
  String _label(String id) {
    final choice = widget.mapping[id];
    if (_protected(id) && !widget.playerReview!.local.containsKey(choice)) {
      return 'Somente dados da API · elenco preservado';
    }
    return '${_protected(id) ? 'Preservado · ' : ''}${fcChoiceLabel(choice, widget.items)}';
  }

  List<FcWorldReviewPlayer> get _missingOthers => [
    for (final p
        in widget.playerReview?.players.values ?? <FcWorldReviewPlayer>[])
      if (!_own(p.id) && !widget.playerReview!.valid(p, widget.mapping)) p,
  ];

  void _generateOthers() {
    setState(() {
      for (final p in _missingOthers) {
        widget.mapping[p.id] = fcCreatePlayerChoice(
          p.remote,
          fcGeneratePlayerProfile(p.remote),
          generated: true,
        );
      }
    });
  }

  Future<void> _confirm() async {
    setState(() => _confirming = true);
    try {
      final ready = widget.onConfirm == null || await widget.onConfirm!();
      if (!mounted) return;
      if (ready) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    final rows =
        widget.rows.entries
            .where(
              (e) =>
                  (_showConfigured || !widget.configuredIds.contains(e.key)) &&
                  (fcNormalize(fcName(e.value['name']))
                          .contains(fcNormalize(_search.text)) ||
                      (_clubs &&
                          (fcNormalize(_label(e.key))
                                  .contains(fcNormalize(_search.text)) ||
                              fcNormalize(_leagueLabel(e.value))
                                  .contains(fcNormalize(_search.text))))) &&
                  (_scope == 'Todos' ||
                      (_scope == 'Meu clube' ? _own(e.key) : !_own(e.key))),
            )
            .toList()
          ..sort(
            (a, b) =>
                fcName(a.value['name']).compareTo(fcName(b.value['name'])),
          );
    return Scaffold(
      appBar: AppBar(title: Text('De-para · ${widget.title}')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.requiredReview && !typing) ...[
                    Text(
                      widget.updating
                          ? 'Confira apenas os vínculos novos ou pendentes'
                          : 'Etapa ${['Competições', 'Equipes', 'Ligas', 'Jogadores'].indexOf(widget.title) + 1} de 4 · Confira os vínculos sugeridos',
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    key: const Key('fc-world-mapping-search'),
                    controller: _search,
                    decoration: fcInput('Buscar nome', icon: Icons.search),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (widget.configuredIds.isNotEmpty && !typing) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      key: const Key('fc-world-show-configured'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mostrar vínculos já configurados'),
                      value: _showConfigured,
                      onChanged: (v) => setState(() => _showConfigured = v),
                    ),
                  ],
                  if (widget.player && !typing) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final scope in [
                          'Todos',
                          'Meu clube',
                          'Outros clubes',
                        ])
                          FilterChip(
                            label: Text(scope),
                            selected: _scope == scope,
                            onSelected: (_) => setState(() => _scope = scope),
                          ),
                      ],
                    ),
                    if (widget.playerReview?.protectedPlayerIds.isNotEmpty ==
                        true) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Meu clube preservado: jogadores e overalls não serão alterados.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                    if (_missingOthers.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const Key('fc-generate-other-clubs'),
                        onPressed: _confirming ? null : _generateOthers,
                        icon: const Icon(Icons.shuffle_rounded),
                        label: Text(
                          'Gerar pendências dos outros clubes · ${_missingOthers.length}',
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          widget.configuredIds.isNotEmpty && !_showConfigured
                              ? 'Tudo já vinculado. Seus vínculos serão reutilizados.'
                              : 'Nenhum cadastro neste filtro.',
                        ),
                      ),
                    )
                  : _clubs
                  ? FcClubLeagueList<MapEntry<String, FcJson>>(
                      groups: _clubGroups(rows),
                      keyPrefix: 'fc-world',
                      query: fcNormalize(_search.text),
                      preferredGroupId: _leagueId(
                        widget.rows[widget.ownClubId] ?? {},
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      rowBuilder: (_, row) => _row(row),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        return _row(rows[index]);
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: FilledButton(
                key: const Key('fc-world-confirm-mapping'),
                onPressed: _confirming ? null : _confirm,
                child: Text(
                  widget.updating
                      ? 'Confirmar vínculos'
                      : widget.requiredReview && widget.title != 'Jogadores'
                      ? 'Próxima etapa'
                      : 'Concluir de-para',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
