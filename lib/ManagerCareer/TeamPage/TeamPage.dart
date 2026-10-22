import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../utils/Components/PlayerAvatar.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/GamePlayers.dart';
import '../../utils/SqlService.dart';
import '../../utils/databaseUtils.dart';
import '../TeamTransfers/PlayerFarewellData.dart';
import '../TeamTransfers/PlayerFarewellDialog.dart';
import 'CreateCustomPlayerPage.dart';
import 'CustomPlayerActions.dart';
import 'ManagerRosterView.dart';
import 'RosterDepartureConfirmation.dart';
import 'SelectRealPlayerPage.dart';
import 'ViewPlayer/ViewPlayerPage.dart';

enum _PlayerAction { remove, statistics }

class TeamPage extends StatefulWidget {
  const TeamPage({super.key, required this.person, this.sql});
  final Person person;
  @visibleForTesting
  final SqlService? sql;

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  SqlService get _sql => widget.sql ?? SqlService.instance;
  bool _departing = false;
  late final Future<List<Season>> _seasons = _sql.getSeasons(widget.person.id);
  String? _seasonId;
  Future<List<Map<String, Object?>>>? _roster;
  String? _rosterSeasonId;
  List<Map<String, Object?>>? _lookupRoster;
  Future<Map<String, GamePlayer>>? _lookup;
  final Map<String, String> _formations = {};

  Future<List<Map<String, Object?>>> _rosterFor(String seasonId) {
    if (_roster == null || _rosterSeasonId != seasonId) {
      _rosterSeasonId = seasonId;
      _roster = _loadRoster(seasonId);
    }
    return _roster!;
  }

  void _refresh() => setState(() {
    final seasonId = _rosterSeasonId;
    if (seasonId != null) _roster = _loadRoster(seasonId);
  });

  Future<List<Map<String, Object?>>> _loadRoster(String seasonId) async {
    try {
      await CustomImageFiles.docsDir();
    } catch (error) {
      debugPrint('Squad photo directory: $error');
    }
    var rows = await _sql.getTeamPlayers(
      widget.person.id,
      seasonId,
      prepareLineup: true,
    );
    if (rows.where((row) => row['isBench'] != 1).length > 11) {
      await _sql.trimStartingEleven(widget.person.id, seasonId);
      rows = await _sql.getTeamPlayers(
        widget.person.id,
        seasonId,
        prepareLineup: true,
      );
    }
    _formations[seasonId] = await _sql.getSquadFormation(
      widget.person.id,
      seasonId,
    );
    return [...rows]..sort(
      (a, b) =>
          getPositionPriority(a['customPositionId'] as String?)
              .compareTo(getPositionPriority(b['customPositionId'] as String?)),
    );
  }

  Future<Map<String, GamePlayer>> _fallbackPlayers(
    List<Map<String, Object?>> roster,
  ) {
    if (!identical(_lookupRoster, roster)) {
      _lookupRoster = roster;
      _lookup = GamePlayers.lookup(widget.person.fifaVersion, [
        for (final row in roster)
          if (row['customName'] == null || row['customPositionId'] == null)
            (row['realPlayerId'] ?? row['playerId'])?.toString() ?? '',
      ]);
    }
    return _lookup!;
  }

  Widget _rosterView(
    Season season,
    List<Map<String, Object?>> roster,
    Map<String, GamePlayer> players,
  ) => ManagerRosterView(
    key: ValueKey('roster-${season.id}'),
    person: widget.person,
    roster: roster,
    gamePlayers: players,
    onAdd: () => _showAdd(season, {
      for (final row in roster)
        (row['realPlayerId'] ?? row['playerId'])?.toString() ?? '',
    }),
    onMove: _movePlayer,
    onLineupChanged: _saveLineup,
    formation: _formations[season.id],
    onFormationChanged: (formation, positions) =>
        _saveLineup(positions, seasonId: season.id, formation: formation),
    onPlayerTap: _showPlayerActions,
  );

  Future<void> _movePlayer(
    Map<String, Object?> row,
    bool reserve,
    Map<String, Object?>? replace, {
    ({int x, int y})? targetPosition,
  }) async {
    try {
      await _sql.setTeamPlayerPlacement(
        personId: widget.person.id,
        playerId: row['id'] as String,
        reserve: reserve,
        replacePlayerId: replace?['id'] as String?,
        targetPosition: targetPosition,
      );
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _saveLineup(
    Map<String, ({int x, int y})> positions, {
    String? seasonId,
    String? formation,
  }) async {
    try {
      await _sql.setLineupPositions(
        widget.person.id,
        positions,
        seasonId: seasonId ?? _rosterSeasonId,
        formation: formation,
      );
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    if (mounted) _refresh();
  }

  Future<void> _showPlayerActions(
    Map<String, Object?> row,
    GamePlayer? player,
  ) async {
    if (_departing) return;
    final name = row['customName']?.toString() ?? player?.name ?? 'Jogador';
    final colors = Theme.of(context).colorScheme;
    final action = await showModalBottomSheet<_PlayerAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: PlayerAvatar(
                    fifaVersion: widget.person.fifaVersion,
                    realPlayerId: row['realPlayerId'] as String? ?? player?.id,
                    customAvatarFilePath:
                        row['customAvatarFilePath'] as String?,
                    radius: 24,
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
                const Divider(height: 16),
                ListTile(
                  leading: const Icon(Icons.bar_chart_rounded),
                  title: const Text('Estatísticas'),
                  onTap: () =>
                      Navigator.pop(sheetContext, _PlayerAction.statistics),
                ),
                ListTile(
                  leading: Icon(
                    Icons.person_remove_outlined,
                    color: colors.error,
                  ),
                  title: Text(
                    'Remover jogador',
                    style: TextStyle(color: colors.error),
                  ),
                  onTap: () =>
                      Navigator.pop(sheetContext, _PlayerAction.remove),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == _PlayerAction.statistics) {
      final realId =
          row['realPlayerId'] ??
          (row['customName'] == null ? row['playerId'] : null);
      if (player == null && realId != null) {
        try {
          player = (await GamePlayers.lookup(widget.person.fifaVersion, [
            realId.toString(),
          ]))[realId.toString()];
        } catch (error) {
          debugPrint('Player profile catalog: $error');
        }
        if (!mounted) return;
      }
      await _open(
        ViewPlayerPage(
          person: widget.person,
          row: row,
          realPlayer: player,
          sql: widget.sql,
        ),
      );
      return;
    }
    _departing = true;
    bool removed = false;
    try {
      final pending = await _sql.getPendingPlayerTransfers(
        widget.person,
        row['playerId'] as String,
        seasonId: row['seasonId'] as String,
      );
      if (!mounted) return;
      final choice = await confirmRosterDeparture(
        context,
        person: widget.person,
        name: name,
        pending: pending,
      );
      if (choice == null || !mounted) return;
      final departure = await _sql.removeTeamPlayer(
        widget.person.id,
        row['id'] as String,
        transferId: choice.transferId,
      );
      if (!mounted) return;
      _refresh();
      if (departure == null) return;
      removed = true;
      PlayerFarewellData farewell;
      try {
        farewell = await PlayerFarewellData.loadDeparture(
          widget.person,
          departure,
          sql: _sql,
          catalog: GameCatalog.current,
        );
      } catch (error) {
        debugPrint('Roster departure retrospective: $error');
        final linked = departure['transferJson'] == null
            ? <String, Object?>{}
            : Map<String, Object?>.from(
                jsonDecode(departure['transferJson'] as String) as Map,
              );
        farewell = PlayerFarewellData.fromRecords(
          person: widget.person,
          transfer: {
            ...linked,
            'playerInstanceId': row['playerId'],
            'fromTeamId': departure['teamId'],
            'fromLeagueId': departure['leagueId'],
            'date': departure['departureDate'],
            'actualReleaseDate': departure['departureDate'],
            'rosterDepartureRecord': true,
          },
          player: {
            'name': name,
            'realPlayerId': row['realPlayerId'],
            'customAvatarFilePath': row['customAvatarFilePath'],
          },
          clubName:
              GameCatalog.current?.teamLabel(
                widget.person.fifaVersion,
                departure['teamId'] as String,
              ) ??
              'Seu clube',
          destinationName: linked['toTeamId'] == null
              ? 'Saída do elenco'
              : GameCatalog.current?.teamLabel(
                      widget.person.fifaVersion,
                      linked['toTeamId'] as String,
                    ) ??
                    'Destino registrado',
          matchRows: [],
          recordsAvailable: false,
        );
      }
      if (mounted) await showPlayerFarewell(context, farewell);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              removed
                  ? 'Saída registrada. Não foi possível exibir a despedida: $error'
                  : 'Não foi possível remover o jogador: $error',
            ),
          ),
        );
      }
    } finally {
      _departing = false;
    }
  }

  Future<void> _showAdd(Season season, Set<String> existingIds) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Adicionar ao elenco',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
              CreateCustomPlayerAction(
                subtitle:
                    'Monte um jogador com nome, foto e atributos próprios.',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _open(
                    CreateCustomPlayerPage(
                      person: widget.person,
                      season: season,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.search),
                title: Text('players.addRealPlayer'.tr()),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _open(
                    SelectRealPlayerPage(
                      person: widget.person,
                      season: season,
                      existingIds: existingIds,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: FutureBuilder<List<Season>>(
        future: _seasons,
        builder: (context, snapshot) {
          final seasons = snapshot.data ?? const <Season>[];
          final season =
              seasons.where((s) => s.id == _seasonId).firstOrNull ??
              seasons.firstOrNull;
          return Text(
            season == null
                ? 'teams.yourTeam'.tr()
                : '${season.startDate.year} - ${season.endDate.year}',
          );
        },
      ),
      actions: [
        FutureBuilder<List<Season>>(
          future: _seasons,
          builder: (context, snapshot) => PopupMenuButton<String>(
            tooltip: 'seasons.season'.tr(),
            icon: const Icon(Icons.calendar_month_outlined),
            onSelected: (value) => setState(() => _seasonId = value),
            itemBuilder: (_) => [
              for (final season in snapshot.data ?? const <Season>[])
                PopupMenuItem(
                  value: season.id,
                  child: Text(
                    '${season.startDate.year} - ${season.endDate.year}',
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
    body: FutureBuilder<List<Season>>(
      future: _seasons,
      builder: (context, seasonsSnapshot) {
        if (seasonsSnapshot.hasError) {
          return Center(child: Text('Erro: ${seasonsSnapshot.error}'));
        }
        if (!seasonsSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final seasons = seasonsSnapshot.data!;
        if (seasons.isEmpty) {
          return Center(child: Text('common.noSeasonsMessage'.tr()));
        }
        final season =
            seasons.where((item) => item.id == _seasonId).firstOrNull ??
            seasons.first;
        return FutureBuilder<List<Map<String, Object?>>>(
          key: ValueKey(season.id),
          future: _rosterFor(season.id),
          builder: (context, rosterSnapshot) {
            if (rosterSnapshot.hasError) {
              return Center(child: Text('Erro: ${rosterSnapshot.error}'));
            }
            if (!rosterSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final roster = rosterSnapshot.data!;
            if (roster.every(
              (row) =>
                  row['customName'] != null && row['customPositionId'] != null,
            )) {
              return _rosterView(season, roster, const {});
            }
            return FutureBuilder<Map<String, GamePlayer>>(
              future: _fallbackPlayers(roster),
              builder: (context, playersSnapshot) =>
                  _rosterView(season, roster, playersSnapshot.data ?? const {}),
            );
          },
        );
      },
    ),
  );
}
