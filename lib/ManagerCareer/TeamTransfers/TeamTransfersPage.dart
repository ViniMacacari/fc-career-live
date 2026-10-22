import '../../utils/AppColors.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../RootPage/DrawerWidget.dart';
import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../models/TeamTransferItem.dart';
import '../../utils/Components/TeamLogo.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/SqlService.dart';
import '../../utils/Components/CareerPageWidgets.dart';
import '../TeamPage/CustomPlayerActions.dart';
import '../TeamPage/ViewPlayer/PlayerProfileVisuals.dart' show ProfilePortrait;
import 'CreateTeamTransferPage.dart';
import 'SelectTransferPlayerPage.dart';
import 'TeamTransfersSortModal.dart';
import 'TransferStyle.dart';

class TeamTransfersPage extends StatefulWidget {
  const TeamTransfersPage({super.key, required this.person});
  final Person person;
  @override
  State<TeamTransfersPage> createState() => _TeamTransfersPageState();
}

class _TeamTransfersPageState extends State<TeamTransfersPage> {
  late final _seasons = SqlService.instance.getSeasons(widget.person.id);
  String? _seasonId, _dataSeasonId;
  Future<List<Object>>? _data;
  TransfersSort _sort = (field: TransfersSortField.date, descending: true);

  Future<List<Object>> _load(String seasonId) => Future.wait<Object>([
    SqlService.instance.getTeamPlayers(widget.person.id, seasonId),
    SqlService.instance.getTeamTransfers(widget.person.id, seasonId: seasonId),
    SqlService.instance.getCustomPlayers(widget.person.id),
    GameCatalog.load(),
  ]);

  Future<List<Object>> _dataFor(String seasonId) {
    if (_data == null || _dataSeasonId != seasonId) {
      _dataSeasonId = seasonId;
      _data = _load(seasonId);
    }
    return _data!;
  }

  Future<void> _open(
    Season season,
    List<Map<String, Object?>> roster,
    Map<String, String> names,
    Map<String, Object?>? row, {
    TransferPlayerChoice? initialPlayer,
  }) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateTeamTransferPage(
          person: widget.person,
          season: season,
          roster: roster,
          names: names,
          existing: row,
          initialPlayer: initialPlayer,
        ),
      ),
    );
    if (mounted && changed == true) {
      setState(() {
        _data = _load(season.id);
      });
    }
  }

  Future<void> _createPlayer(
    Season season,
    List<Map<String, Object?>> roster,
    Map<String, String> names,
  ) async {
    final player = await openCustomPlayerCreator(
      context,
      person: widget.person,
      season: season,
      addToRoster: false,
    );
    if (player == null || !mounted) return;
    final choice = TransferPlayerChoice(
      id: player['id'] as String,
      name: player['name'] as String,
      custom: player,
    );
    setState(() {
      _data = _load(season.id);
    });
    await _open(
      season,
      roster,
      {...names, choice.id: choice.name},
      null,
      initialPlayer: choice,
    );
  }

  Future<void> _showAdd(
    Season season,
    List<Map<String, Object?>> roster,
    Map<String, String> names,
  ) async {
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
                  'Adicionar em transferências',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              CreateCustomPlayerAction(
                subtitle: 'Crie um jogador e registre a chegada ao clube.',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _createPlayer(season, roster, names);
                },
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded),
                title: const Text('Registrar transferência'),
                subtitle: const Text(
                  'Escolha um jogador do elenco ou do catálogo.',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _open(season, roster, names, null);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickSeason(List<Season> seasons, Season selected) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.of(context).panel,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Temporada', style: TextStyle(fontSize: 18)),
            ),
            for (final season in seasons)
              ListTile(
                title: Text(
                  '${season.startDate.year} - ${season.endDate.year}',
                ),
                trailing: selected.id == season.id
                    ? Icon(Icons.check, color: AppColors.of(context).accent)
                    : null,
                onTap: () => Navigator.pop(context, season.id),
              ),
          ],
        ),
      ),
    );
    if (mounted && id != null) setState(() => _seasonId = id);
  }

  Future<void> _pickSort() async {
    final value = await showTransfersSortModal(context, _sort);
    if (mounted && value != null) setState(() => _sort = value);
  }

  List<Map<String, Object?>> _sorted(
    List<Map<String, Object?>> source,
    Map<String, String> names,
  ) {
    final result = [...source];
    result.sort((a, b) {
      final comparison = switch (_sort.field) {
        TransfersSortField.date =>
          (DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(1900))
              .compareTo(
                DateTime.tryParse(b['date']?.toString() ?? '') ??
                    DateTime(1900),
              ),
        TransfersSortField.player =>
          (names[a['playerInstanceId']] ?? '').toLowerCase().compareTo(
            (names[b['playerInstanceId']] ?? '').toLowerCase(),
          ),
        TransfersSortField.value =>
          ((a['transferValue'] as num?) ?? 0).compareTo(
            (b['transferValue'] as num?) ?? 0,
          ),
      };
      if (comparison == 0) {
        return a['id'].toString().compareTo(b['id'].toString());
      }
      return _sort.descending ? -comparison : comparison;
    });
    return result;
  }

  Widget _card(
    Season season,
    Map<String, Object?> row,
    bool incoming,
    List<Map<String, Object?>> roster,
    Map<String, String> names,
    Map<String, Map<String, Object?>> players,
    GameCatalog catalog,
  ) {
    final player = players[row['playerInstanceId']];
    final clubId = (incoming ? row['fromTeamId'] : row['toTeamId'])?.toString();
    final leagueId = (incoming ? row['fromLeagueId'] : row['toLeagueId'])
        ?.toString();
    final date = DateTime.tryParse(row['date']?.toString() ?? '');
    final color = incoming
        ? AppColors.of(context).success
        : AppColors.of(context).danger;
    return Card(
      color: AppColors.of(context).panel,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: AppColors.of(context).accent.withValues(alpha: .15),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(season, roster, names, row),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ProfilePortrait(
                  version: widget.person.fifaVersion,
                  realPlayerId: player?['realPlayerId']?.toString(),
                  customAvatarFilePath: player?['customAvatarFilePath']
                      ?.toString(),
                  width: 44,
                  height: 48,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      names[row['playerInstanceId']] ?? 'Jogador',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: transferCardLabel(row)),
                          if (row['transferValue'] != null)
                            TextSpan(
                              text:
                                  '  ${transferMoney(row['transferValue'])} ${transferCurrency(widget.person)}',
                              style: TextStyle(color: color),
                            ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.of(context).muted,
                      ),
                    ),
                    if (row['actualReleaseDate'] != null ||
                        row['releaseDate'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '${row['actualReleaseDate'] == null ? 'Liberação' : 'Saída registrada'}: ${DateFormat('dd/MM/yyyy').format(teamTransferEffectiveDate(row)!)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.of(context).accent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 54,
                child: Column(
                  children: [
                    if (clubId != null)
                      Tooltip(
                        message: catalog.teamLabel(
                          widget.person.fifaVersion,
                          clubId,
                        ),
                        child: TeamLogo.lookup(
                          fifaVersion: widget.person.fifaVersion,
                          teamId: clubId,
                          leagueId: leagueId,
                          size: 28,
                        ),
                      ),
                    if (date != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        DateFormat.MMMd(context.locale.toString()).format(date),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.of(context).muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => TransferTheme(
    child: FutureBuilder<List<Season>>(
      future: _seasons,
      builder: (context, seasonSnapshot) {
        final seasons = seasonSnapshot.data ?? const <Season>[];
        final season =
            seasons.where((item) => item.id == _seasonId).firstOrNull ??
            seasons.firstOrNull;
        return Scaffold(
          appBar: AppBar(
            leading: RootDrawerScope.leading(context),
            title: season == null
                ? const Text('Transferências')
                : InkWell(
                    onTap: () => _pickSeason(seasons, season),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${season.startDate.year} - ${season.endDate.year}',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_drop_down, size: 20),
                      ],
                    ),
                  ),
            actions: [
              IconButton(
                tooltip: 'Ordenar transferências',
                onPressed: _pickSort,
                icon: const Icon(Icons.sort),
              ),
            ],
          ),
          body: seasonSnapshot.hasError
              ? Center(child: Text('Erro: ${seasonSnapshot.error}'))
              : !seasonSnapshot.hasData
              ? const Center(child: CircularProgressIndicator())
              : season == null
              ? Center(child: Text('common.noSeasonsMessage'.tr()))
              : FutureBuilder<List<Object>>(
                  key: ValueKey(season.id),
                  future: _dataFor(season.id),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('Erro: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final roster =
                        snapshot.data![0] as List<Map<String, Object?>>;
                    final transfers =
                        snapshot.data![1] as List<Map<String, Object?>>;
                    final players = {
                      for (final row
                          in snapshot.data![2] as List<Map<String, Object?>>)
                        row['id'] as String: row,
                    };
                    final names = {
                      for (final entry in players.entries)
                        entry.key: entry.value['name']?.toString() ?? 'Jogador',
                    };
                    final catalog = snapshot.data![3] as GameCatalog;
                    final incoming = _sorted(
                      transfers
                          .where(
                            (row) => isIncomingTeamTransfer(
                              row,
                              widget.person.teamId,
                            ),
                          )
                          .toList(),
                      names,
                    );
                    final outgoing = _sorted(
                      transfers
                          .where(
                            (row) => !isIncomingTeamTransfer(
                              row,
                              widget.person.teamId,
                            ),
                          )
                          .toList(),
                      names,
                    );
                    return Stack(
                      children: [
                        ListView(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
                          children: [
                            CareerPageHeader(
                              title: 'Mercado do clube',
                              subtitle:
                                  'Temporada ${season.startDate.year}/${season.endDate.year} · ${incoming.length} chegadas · ${outgoing.length} saídas',
                              icon: Icons.swap_horiz_rounded,
                              eyebrow: 'Transferências',
                            ),
                            if (transfers.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 32),
                                child: Text(
                                  'teams.noTransfersYet'.tr(),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            if (incoming.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(10, 4, 0, 4),
                                child: Text(
                                  'Jogadores Chegaram',
                                  style: TextStyle(
                                    color: AppColors.of(context).success,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              for (final row in incoming)
                                _card(
                                  season,
                                  row,
                                  true,
                                  roster,
                                  names,
                                  players,
                                  catalog,
                                ),
                            ],
                            if (outgoing.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(10, 4, 0, 4),
                                child: Text(
                                  'Jogadores Saíram',
                                  style: TextStyle(
                                    color: AppColors.of(context).danger,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              for (final row in outgoing)
                                _card(
                                  season,
                                  row,
                                  false,
                                  roster,
                                  names,
                                  players,
                                  catalog,
                                ),
                            ],
                          ],
                        ),
                        Positioned(
                          right: 18,
                          bottom: 22,
                          child: SafeArea(
                            child: FloatingActionButton(
                              heroTag: 'add-team-transfer',
                              tooltip: 'Adicionar Item de Transferência',
                              onPressed: () => _showAdd(season, roster, names),
                              child: const Icon(Icons.add, size: 30),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    ),
  );
}
