import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../utils/GamePlayers.dart';
import '../../utils/SqlService.dart';
import '../../utils/PlayerClubLookup.dart';
import '../../utils/Components/PlayerSearchCard.dart';
import '../../utils/Components/SelectionSearchField.dart';
import 'CustomPlayerActions.dart';
import '../../Settings/CustomConfiguration/CustomPlayersPage.dart';

class SelectRealPlayerPage extends StatefulWidget {
  const SelectRealPlayerPage({
    super.key,
    required this.person,
    required this.season,
    required this.existingIds,
    this.sql,
  });

  const SelectRealPlayerPage.pick({super.key, required this.person, this.sql})
    : season = null,
      existingIds = const {};

  final Person person;
  final Season? season;
  final Set<String> existingIds;
  final SqlService? sql;

  @override
  State<SelectRealPlayerPage> createState() => _SelectRealPlayerPageState();
}

class _SelectRealPlayerPageState extends State<SelectRealPlayerPage> {
  String _query = '';
  String? _savingId;
  final _search = TextEditingController();
  late PlayerClubLookup _clubs;
  late Map<String, String> _searchNames;
  late final _sql = widget.sql ?? SqlService.instance;
  late final Future<List<GamePlayer>> _players = GamePlayers.load(
    widget.person.fifaVersion,
  );
  late final Future<Map<String, int>> _overalls = _loadOveralls();

  Future<Map<String, int>> _loadOveralls() async => {
    for (final player in await _sql.getCustomPlayers(widget.person.id))
      if (player['realPlayerId'] case final String id)
        if (player['overall'] case final num overall) id: overall.toInt(),
  };

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _createCustom() async {
    final player = await openCustomPlayerCreator(
      context,
      person: widget.person,
      season: widget.season!,
    );
    if (player != null && mounted) Navigator.pop(context, true);
  }

  Future<void> _useShared() async {
    final player = await Navigator.push<Map<String, Object?>>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomPlayersPage(
          person: widget.person,
          season: widget.season,
          addToRoster: true,
        ),
      ),
    );
    if (player != null && mounted) Navigator.pop(context, true);
  }

  Future<void> _add(GamePlayer player) async {
    if (widget.season == null) {
      Navigator.pop(context, player);
      return;
    }
    if (_savingId != null) return;
    setState(() => _savingId = player.id);
    try {
      await _sql.addRealTeamPlayer(
        personId: widget.person.id,
        seasonId: widget.season!.id,
        player: player,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao adicionar jogador: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('players.selectPlayer'.tr())),
    body: FutureBuilder<(List<GamePlayer>, Map<String, int>)>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Erro ao carregar jogadores: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final query = selectionSearchKey(_query);
        final results = snapshot.data!.$1
            .where(
              (player) =>
                  !widget.existingIds.contains(player.id) &&
                  (query.isEmpty ||
                      _searchNames[player.id]!.contains(query) ||
                      player.id.contains(query)),
            )
            .take(150)
            .toList();
        return Column(
          children: [
            if (widget.season != null &&
                MediaQuery.viewInsetsOf(context).bottom == 0)
              Padding(
                key: const ValueKey('shared-roster-shortcut'),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: OutlinedButton.icon(
                  onPressed: _useShared,
                  icon: const Icon(Icons.groups_outlined),
                  label: const Text('Jogadores personalizados já criados'),
                ),
              ),
            if (widget.season != null &&
                MediaQuery.viewInsetsOf(context).bottom == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: CreateCustomPlayerAction(
                  onTap: _createCustom,
                  subtitle:
                      'Crie um novo jogador para o elenco desta temporada.',
                ),
              ),
            Padding(
              key: const ValueKey('real-player-search'),
              padding: const EdgeInsets.all(16),
              child: SelectionSearchField(
                controller: _search,
                hint: 'players.searchPlayer'.tr(),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? const Center(child: Text('Nenhum jogador encontrado.'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final player = results[index];
                        final overall =
                            snapshot.data!.$2[player.id] ?? player.overall;
                        return PlayerSearchCard(
                          key: ValueKey('real-player-${player.id}'),
                          name: player.name,
                          version: widget.person.fifaVersion,
                          realPlayerId: player.id,
                          club: _clubs.club(player: player),
                          details: [
                            player.position,
                            if (overall != null)
                              '${'history.overallShort'.tr()} $overall',
                            'ID ${player.id}',
                          ].where((part) => part.isNotEmpty).join(' • '),
                          trailing: _savingId == player.id
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  widget.season == null
                                      ? Icons.chevron_right
                                      : Icons.add,
                                ),
                          onTap: _savingId == null ? () => _add(player) : null,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );

  late final Future<(List<GamePlayer>, Map<String, int>)> _data = _loadData();

  Future<(List<GamePlayer>, Map<String, int>)> _loadData() async {
    final players = _players;
    final overalls = _overalls;
    _clubs = await PlayerClubLookup.load(
      sql: _sql,
      person: widget.person,
      seasonId: widget.season?.id,
    );
    final loaded = await players;
    _searchNames = {for (final p in loaded) p.id: selectionSearchKey(p.name)};
    return (loaded, await overalls);
  }
}
