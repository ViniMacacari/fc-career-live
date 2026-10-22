import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../models/Person.dart';
import '../../utils/AppColors.dart';
import '../../utils/Components/CareerPageWidgets.dart';
import '../../utils/Components/CompactDashboardWidgets.dart';
import '../../utils/Components/SelectionSearchField.dart';
import '../TeamPage/CreateCustomPlayerPage.dart';
import '../TeamPage/ViewPlayer/PlayerTransfersTab.dart';
import '../TeamPage/ViewPlayer/ViewPlayerPage.dart';
import 'OtherPlayerWidgets.dart';
import 'OtherPlayersData.dart';
import 'WorldStatsSync.dart';

Future<void> openOtherPlayer(
  BuildContext context, {
  required Person person,
  required OtherPlayersRepository repository,
  required OtherPlayersSnapshot snapshot,
  required OtherPlayer player,
}) => Navigator.push<void>(
  context,
  MaterialPageRoute(
    builder: (_) => ViewPlayerPage(
      person: person,
      row: player.profileRow(snapshot.season?.id),
      realPlayer: player.catalog,
      sql: repository.sql,
      otherPlayers: repository,
    ),
  ),
);

const _lineTitles = {
  'GOL': 'Goleiros',
  'DEF': 'Defensores',
  'MEI': 'Meio-campistas',
  'ATA': 'Atacantes',
};

class OtherTeamPage extends StatefulWidget {
  const OtherTeamPage({
    super.key,
    required this.person,
    required this.repository,
    required this.snapshot,
    required this.teamId,
    this.worldSync,
  });
  final Person person;
  final OtherPlayersRepository repository;
  final OtherPlayersSnapshot snapshot;
  final String teamId;
  final WorldStatsSync? worldSync;
  @override
  State<OtherTeamPage> createState() => _OtherTeamPageState();
}

class _OtherTeamPageState extends State<OtherTeamPage> {
  late OtherPlayersSnapshot _snapshot = widget.snapshot;
  late final OtherTeam _initial = widget.snapshot.teamOf(widget.teamId)!;
  late Future<Map<String, CompetitionLine>> _totals = _loadTotals();
  late final WorldStatsSync _sync =
      widget.worldSync ?? WorldStatsSync(sql: widget.repository.sql);
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    if (_initial.imported) {
      _syncing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncTeam(silent: true);
      });
    }
  }

  Future<void> _syncTeam({bool silent = false}) async {
    setState(() => _syncing = true);
    try {
      final updated = await _sync.refreshTeam(widget.person, widget.teamId);
      if (mounted && updated > 0) setState(() => _totals = _loadTotals());
    } catch (e) {
      if (!silent && mounted && e is! WorldStatsNotLinked) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  OtherTeam get _team =>
      _snapshot.teamOf(widget.teamId) ??
      OtherTeam(_initial.team, _initial.league, const []);
  OtherPlayersRepository get _repo => widget.repository;

  Future<Map<String, CompetitionLine>> _loadTotals() {
    final season = _snapshot.season;
    if (season == null) return Future.value(const {});
    return _repo.seasonTotals(widget.person, season.id, [
      for (final p in _team.players)
        if (p.playerId != null) p.playerId!,
    ], teamId: widget.teamId);
  }

  Future<void> _reload() async {
    final snapshot = await _repo.load(widget.person);
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _totals = _loadTotals();
    });
  }

  Future<void> _open(OtherPlayer player) async {
    await openOtherPlayer(
      context,
      person: widget.person,
      repository: _repo,
      snapshot: _snapshot,
      player: player,
    );
    await _reload();
  }

  Future<void> _create() async {
    Map<String, Object?>? created;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateCustomPlayerPage(
          person: widget.person,
          addToRoster: false,
          service: _repo.sql,
          onCreated: (player) => created = player,
        ),
      ),
    );
    final id = created?['id'] as String?;
    if (id == null) return;
    await _repo.assign(
      widget.person,
      id,
      _team.team,
      since: await _repo.sql.getCareerDate(widget.person.id),
    );
    await _reload();
  }

  Future<void> _bring() async {
    final player = await showModalBottomSheet<OtherPlayer>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.of(context).background,
      builder: (context) => _PlayerPicker(
        snapshot: _snapshot,
        exceptTeamId: widget.teamId,
        version: widget.person.fifaVersion,
      ),
    );
    if (player == null || !mounted) return;
    final date = await _repo.sql.getCareerDate(widget.person.id);
    if (!mounted) return;
    final draft = await showWorldTransferSheet(
      context,
      person: widget.person,
      currency: switch (widget.person.currency?.toUpperCase()) {
        'BRL' => r'R$',
        'USD' => r'$',
        'EUR' || 'EURO' || null => '€',
        final String value => value,
      },
      canMove: false,
      draft: WorldTransferDraft(
        date: date ?? DateTime.now(),
        type: player.team == null ? 'free' : 'transfer',
        from: player.team,
        to: _team.team,
        move: true,
      ),
    );
    if (draft == null) return;
    final id =
        player.playerId ??
        await _repo.materialize(
          widget.person,
          player.catalog!,
          team: player.team,
        );
    await _repo.saveTransfer(
      widget.person,
      id,
      date: draft.date,
      type: draft.type,
      from: draft.from,
      to: draft.to,
      value: draft.value,
      move: draft.to != null,
    );
    await _reload();
  }

  Future<void> _add() async {
    final c = AppColors.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: c.background,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('other-team-create'),
                leading: const CareerIconBadge(icon: Icons.person_add_alt_1),
                title: const Text('Criar jogador'),
                subtitle: const Text('Cadastro novo direto neste elenco.'),
                onTap: () => Navigator.pop(context, 'create'),
              ),
              ListTile(
                key: const ValueKey('other-team-bring'),
                leading: const CareerIconBadge(icon: Icons.swap_horiz_rounded),
                title: const Text('Trazer de outro clube'),
                subtitle: const Text(
                  'Busque qualquer jogador e registre a transferência.',
                ),
                onTap: () => Navigator.pop(context, 'bring'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == 'create') await _create();
    if (action == 'bring') await _bring();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final team = _team;
    final players = team.players;
    final ages = players.map((p) => p.age).whereType<int>().toList();
    final average = team.averageOverall;
    final groups = <String?, List<OtherPlayer>>{};
    for (final p in players) {
      (groups[p.line] ??= []).add(p);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(team.label),
        actions: [
          if (_initial.imported)
            _syncing
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    key: const ValueKey('other-team-refresh'),
                    tooltip: 'Atualizar pela API',
                    onPressed: _syncTeam,
                    icon: const Icon(Icons.sync_rounded),
                  ),
        ],
      ),
      floatingActionButton: team.team == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('other-team-add'),
              onPressed: _add,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Adicionar'),
            ),
      body: FutureBuilder<Map<String, CompetitionLine>>(
        future: _totals,
        builder: (context, snapshot) {
          final totals = snapshot.data ?? const {};
          final goals = totals.values.fold<int>(
            0,
            (sum, line) => sum + (line.goals ?? 0),
          );
          final dates = totals.values.map((l) => l.date).whereType<DateTime>();
          final updated = dates.isEmpty
              ? null
              : dates.reduce((a, b) => a.isAfter(b) ? a : b);
          return ListView(
            key: const PageStorageKey('other-team'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              CareerPageHeader(
                title: team.label,
                subtitle: [
                  if (team.league != null) team.league!.label,
                  team.imported
                      ? 'Elenco da importação pela API'
                      : team.careerPlayers == 0
                      ? 'Elenco do catálogo do jogo'
                      : 'Catálogo do jogo e jogadores da carreira',
                  if (updated != null)
                    'números do save em ${DateFormat('dd/MM/yyyy').format(updated)}',
                ].join(' · '),
                icon: Icons.shield_outlined,
                leading: team.team == null
                    ? null
                    : ClubLogo(
                        version: widget.person.fifaVersion,
                        club: team.team!,
                        size: 48,
                      ),
                footer: StatStrip(
                  items:
                      [
                            ('${players.length}', 'Jogadores', null),
                            (
                              average == null
                                  ? '—'
                                  : average.toStringAsFixed(1),
                              'Média dos 11',
                              null,
                            ),
                            (
                              ages.isEmpty
                                  ? '—'
                                  : (ages.reduce((a, b) => a + b) / ages.length)
                                        .toStringAsFixed(1),
                              'Idade média',
                              null,
                            ),
                            if (totals.isNotEmpty)
                              ('$goals', 'Gols na temporada', null),
                          ]
                          .map((e) => (e.$1.replaceAll('.', ','), e.$2, e.$3))
                          .toList(),
                ),
              ),
              if (players.isEmpty)
                CareerEmptyState(
                  title: 'Elenco vazio',
                  subtitle: 'Crie um jogador ou traga alguém de outro clube com uma transferência.',
                  icon: Icons.groups_outlined,
                ),
              for (final line in [..._lineTitles.keys, null])
                if (groups[line]?.isNotEmpty ?? false)
                  DashboardSection(
                    title:
                        '${_lineTitles[line] ?? 'Sem posição'} · ${groups[line]!.length}',
                    child: Column(
                      children: [
                        for (final (i, p) in groups[line]!.indexed) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              color: c.line.withValues(alpha: .5),
                            ),
                          OtherPlayerRow(
                            player: p,
                            version: widget.person.fifaVersion,
                            showClub: false,
                            stats: seasonSummary(totals[p.playerId]),
                            onTap: () => _open(p),
                          ),
                        ],
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _PlayerPicker extends StatefulWidget {
  const _PlayerPicker({
    required this.snapshot,
    required this.exceptTeamId,
    required this.version,
  });
  final OtherPlayersSnapshot snapshot;
  final String exceptTeamId, version;
  @override
  State<_PlayerPicker> createState() => _PlayerPickerState();
}

class _PlayerPickerState extends State<_PlayerPicker> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final found = _query.trim().isEmpty
        ? const <OtherPlayer>[]
        : widget.snapshot
              .search(_query, const OtherPlayersFilter())
              .where((p) => (p.team?.id ?? '') != widget.exceptTeamId)
              .take(80)
              .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(
        children: [
          const Text(
            'Trazer de outro clube',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SelectionSearchField(
              key: const ValueKey('other-picker-search'),
              controller: _search,
              hint: 'Nome, clube ou posição',
              dense: true,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: found.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _query.trim().isEmpty
                          ? 'Digite para buscar entre todos os jogadores.'
                          : 'Nenhum jogador encontrado.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.muted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: found.length,
                    itemBuilder: (context, i) => OtherPlayerRow(
                      player: found[i],
                      version: widget.version,
                      onTap: () => Navigator.pop(context, found[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
