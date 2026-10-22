import '../../../utils/AppColors.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../Common/FixtureDetailsPage.dart';
import '../../../Common/FixtureResultTile.dart';
import '../../../models/Person.dart';
import '../../../utils/CareerDatePicker.dart';
import '../../../utils/ManagerStatService.dart';
import '../../../utils/GameCatalog.dart';
import '../../../utils/GamePlayers.dart';
import '../../../utils/SqlService.dart';
import '../../../utils/ThousandsSeparatorInputFormatter.dart';
import '../../../utils/databaseUtils.dart';
import '../../../utils/themes.dart';
import '../../../utils/Components/ManagerFormStyle.dart';
import 'ComparePlayers/ComparePlayers.dart';
import 'EditTeamPlayerPage.dart';
import 'PlayerProfileCharts.dart';
import 'PlayerDetailsCards.dart';
import '../../../Common/FixtureCaptainPanel.dart';
import 'PlayerPerformanceInsights.dart';
import 'PlayerProfileData.dart';
import 'PlayerScoringInsights.dart';
import 'PlayerDetailedStats.dart';
import 'PlayerAnalysis.dart';
import '../../PlayersStat/PlayersStatData.dart' show PlayersStatMetric;
import '../../../models/Season.dart';
import 'PlayerProfileVisuals.dart';
import 'PlayerSummary/PlayerSummaryData.dart';
import 'PlayerSummary/PlayerSummaryTab.dart';
import 'PlayerTransfersTab.dart';
import 'PlayerWorldStats.dart';
import '../../OtherPlayers/OtherPlayerWidgets.dart';
import '../../OtherPlayers/OtherPlayersData.dart';
import '../../OtherPlayers/WorldStatsSync.dart';
import '../../../FcScore/FcScoreApi.dart' show FcScoreException;

class ViewPlayerPage extends StatefulWidget {
  const ViewPlayerPage({
    super.key,
    required this.person,
    required this.row,
    this.realPlayer,
    this.profileData,
    this.summarySource,
    this.sql,
    this.otherPlayers,
    this.worldSync,
  });
  final Person person;
  final Map<String, Object?> row;
  final GamePlayer? realPlayer;
  final Future<PlayerProfileData>? profileData;

  @visibleForTesting
  final PlayerSummarySource? summarySource;
  @visibleForTesting
  final SqlService? sql;

  final OtherPlayersRepository? otherPlayers;
  final WorldStatsSync? worldSync;
  @override
  State<ViewPlayerPage> createState() => _ViewPlayerPageState();
}

class _ViewPlayerPageState extends State<ViewPlayerPage> {
  late Map<String, Object?> row = widget.row;
  SqlService get sql => widget.sql ?? SqlService.instance;
  late Future<PlayerProfileData> _data =
      widget.profileData ??
      PlayerProfileData.load(widget.person, playerId, sql: sql);
  String? seasonId, tournamentId;
  String careerCategory = 'Resumo';
  String _matchesPeriod = 'current';
  late final OtherPlayersRepository _world =
      widget.otherPlayers ?? OtherPlayersRepository(sql: sql);
  late Future<CatalogItem?> _club = _loadClub();
  late Future<Map<String, List<CompetitionLine>>> _lines = _world.seasonLines(
    widget.person,
    playerId,
  );
  int _transfersVersion = 0;
  late final WorldStatsSync _sync =
      widget.worldSync ?? WorldStatsSync(sql: sql);
  bool _syncing = false;
  String? _syncError;
  WorldStatsResult? _transient;

  bool get _other => row['otherTeam'] == true;
  bool get _ownSquad => !_other && row['statisticsReadOnlyRoster'] != true;

  @override
  void initState() {
    super.initState();
    seasonId = row['seasonId']?.toString();
    if (_other) {
      _syncing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncWorld(silent: true);
      });
    }
  }

  Future<void> _syncWorld({bool silent = false}) async {
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    try {
      final id = playerId;
      final result = await _sync.refreshPlayer(
        widget.person,
        playerId: id.isEmpty ? null : id,
        remotePlayerId: id.isEmpty ? widget.realPlayer?.id : null,
      );
      if (!mounted) return;
      setState(() {
        if (id.isEmpty) {
          _transient = result;
        } else {
          _lines = _world.seasonLines(widget.person, id);
        }
        if (result == null && !silent) {
          _syncError = 'jogador não encontrado no save';
        }
      });
    } on WorldStatsNotLinked catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on FcScoreException catch (e) {
      if (!mounted) return;
      setState(() => _syncError = 'sem conexão com o PC');
      if (!silent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) setState(() => _syncError = 'sem conexão com o PC');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String get playerId => row['playerId']?.toString() ?? '';
  String get name =>
      row['customName']?.toString() ?? widget.realPlayer?.name ?? 'Jogador';
  String get position => positionShortName(
    row['customPositionId'] as String? ?? widget.realPlayer?.mainPositionId,
  );
  int? get potential =>
      (row['customPotential'] as num?)?.toInt() ?? widget.realPlayer?.potential;
  int? get overall => (row['overall'] as num?)?.toInt();
  String get currency => switch (widget.person.currency?.toUpperCase()) {
    'BRL' => r'R$',
    'USD' => r'$',
    'EUR' || 'EURO' => '€',
    final String value => value,
    null => '€',
  };
  String number(Object? value) =>
      value is num ? NumberFormat.decimalPattern('pt_BR').format(value) : '–';
  String money(Object? value) =>
      value is num ? '${number(value)} $currency' : '–';
  String date(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? '–' : DateFormat('dd/MM/yyyy').format(parsed);
  }

  void refreshData() => setState(() {
    _data = PlayerProfileData.load(widget.person, playerId, sql: sql);
  });

  Future<CatalogItem?> _loadClub() async {
    final catalog = await GameCatalog.load();
    if (_other) {
      final id = row['teamId']?.toString();
      if (id == null || id.isEmpty) return null;
      final leagueId = row['leagueId']?.toString();
      return catalog.team(widget.person.fifaVersion, id, leagueId: leagueId) ??
          CatalogItem(id, 'Clube não informado', leagueId: leagueId);
    }
    if (_ownSquad) {
      return catalog.team(
        widget.person.fifaVersion,
        widget.person.teamId,
        leagueId: widget.person.leagueId,
      );
    }
    return _world.clubOf(widget.person, playerId: playerId);
  }

  static Map<String, Object?> _identity(Map<String, Object?> player) => {
    'customName': player['name'],
    'customPositionId': player['positionId'],
    'customPotential': player['potential'],
    'customFoot': player['foot'],
    'customAvatarFilePath': player['customAvatarFilePath'],
    'nationalityId': player['nationalityId'],
    'birthdate': player['birthdate'],
    'playerHeight': player['height'],
    'playerWeight': player['weight'],
    'firstSeasonAge': player['firstSeasonAge'],
    'overall': player['overall'],
  };

  Future<String> _ensurePlayer() async {
    if (playerId.isNotEmpty) return playerId;
    final catalogPlayer = widget.realPlayer;
    if (catalogPlayer == null) throw StateError('Jogador sem cadastro.');
    final id = await _world.materialize(
      widget.person,
      catalogPlayer,
      team: await _club,
    );
    row = {...row, 'playerId': id};
    await reload();
    if (_transient != null) _syncWorld(silent: true);
    return id;
  }

  Future<void> _otherReload() async {
    final player = await sql.getCustomPlayerById(widget.person.id, playerId);
    final club = await _world.clubOf(widget.person, playerId: playerId);
    final world = await _world.worldRow(widget.person, playerId);
    if (!mounted) return;
    setState(() {
      row = {
        ...row,
        if (player != null) ..._identity(player),
        'realPlayerId': player?['realPlayerId'] ?? row['realPlayerId'],
        'teamId': club?.id,
        'leagueId': club?.leagueId,
        'shirtNumber': world?['shirtNumber'],
      };
      _club = Future.value(club);
      _data = PlayerProfileData.load(widget.person, playerId, sql: sql);
      _lines = _world.seasonLines(widget.person, playerId);
    });
  }

  Future<void> _transfer() async {
    final club = await _club;
    final date = await sql.getCareerDate(widget.person.id);
    if (!mounted) return;
    final draft = await showWorldTransferSheet(
      context,
      person: widget.person,
      currency: currency,
      draft: WorldTransferDraft(
        date: date ?? DateTime.now(),
        type: club == null ? 'free' : 'transfer',
        from: club,
        move: true,
      ),
    );
    if (draft == null) return;
    final id = await _ensurePlayer();
    await _world.saveTransfer(
      widget.person,
      id,
      date: draft.date,
      type: draft.type,
      from: draft.from,
      to: draft.to,
      value: draft.value,
      move: draft.move,
    );
    _transfersVersion++;
    await reload();
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _release() async {
    final club = await _club;
    if (club == null || !mounted) return;
    if (!await _confirm(
      'Liberar $name?',
      'O jogador sai do ${club.label} e fica sem clube. A rescisão entra no histórico de transferências.',
      'Liberar',
    )) {
      return;
    }
    final id = await _ensurePlayer();
    await _world.saveTransfer(
      widget.person,
      id,
      date: await sql.getCareerDate(widget.person.id) ?? DateTime.now(),
      type: 'release',
      from: club,
    );
    _transfersVersion++;
    await reload();
  }

  Future<void> _hide() async {
    if (!await _confirm(
      'Excluir $name?',
      'Ele deixa de aparecer em Outros jogadores. Partidas e históricos já registrados continuam salvos.',
      'Excluir',
    )) {
      return;
    }
    final id = await _ensurePlayer();
    await _world.hide(widget.person, id);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _editLine(String? season, CompetitionLine? line) async {
    if (season == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Crie uma temporada para registrar os números.'),
        ),
      );
      return;
    }
    final club = await _club;
    if (!mounted) return;
    final result = await showCompetitionLineSheet(
      context,
      person: widget.person,
      line: line,
      team: club,
      goalkeeper:
          (row['customPositionId'] ?? widget.realPlayer?.mainPositionId) == '0',
    );
    if (result == null) return;
    final id = await _ensurePlayer();
    final (action, value) = result;
    if (action == CompetitionLineAction.save) {
      await _world.saveLine(widget.person, id, season, value);
    } else {
      await _world.deleteLine(widget.person, value.manualId!);
    }
    if (mounted) {
      setState(() => _lines = _world.seasonLines(widget.person, id));
    }
  }

  Future<void> reload() async {
    if (_other) return _otherReload();
    final roster = await sql.getTeamPlayers(
      widget.person.id,
      row['seasonId'] as String,
    );
    final updated = roster.where((item) => item['id'] == row['id']).firstOrNull;
    if (updated == null) {
      if (row['statisticsReadOnlyRoster'] == true) {
        final player = await sql.getCustomPlayerById(
          widget.person.id,
          playerId,
        );
        if (player != null && mounted) {
          setState(() {
            row = {...row, ..._identity(player)};
            _data = PlayerProfileData.load(widget.person, playerId, sql: sql);
          });
          return;
        }
      }
      if (mounted) Navigator.pop(context, true);
      return;
    }
    if (mounted) {
      setState(() {
        row = {
          ...updated,
          'statisticsReadOnlyRoster': row['statisticsReadOnlyRoster'],
        };
        _data = PlayerProfileData.load(widget.person, playerId, sql: sql);
      });
    }
  }

  Future<void> edit({String? initialSeasonId}) async {
    if (_other) await _ensurePlayer();
    if (!mounted) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditTeamPlayerPage(
          person: widget.person,
          row: row,
          realPlayer: widget.realPlayer,
          initialSeasonId: initialSeasonId ?? seasonId,
          sql: widget.sql,
          otherPlayers: _other ? _world : null,
        ),
      ),
    );
    if (changed == true) await reload();
  }

  Future<void> compare() => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => ComparePlayersPage(
        person: widget.person,
        initialPlayer: row,
        initialSeasonId: seasonId ?? row['seasonId']?.toString(),
      ),
    ),
  );

  Future<void> move() async {
    final toReserve = row['isBench'] != 1;
    String? replaceId;
    if (!toReserve) {
      final roster = await SqlService.instance.getTeamPlayers(
        widget.person.id,
        row['seasonId'] as String,
      );
      final starters = roster.where((item) => item['isBench'] != 1).toList();
      if (starters.length >= 11 && mounted) {
        final replace = await showModalBottomSheet<Map<String, Object?>>(
          context: context,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(
                  title: Text('Escolha o titular para substituir'),
                ),
                for (final starter in starters)
                  ListTile(
                    title: Text(starter['customName']?.toString() ?? 'Jogador'),
                    onTap: () => Navigator.pop(context, starter),
                  ),
              ],
            ),
          ),
        );
        if (replace == null) return;
        replaceId = replace['id'] as String?;
      }
    }
    try {
      await sql.setTeamPlayerPlacement(
        personId: widget.person.id,
        playerId: row['id'] as String,
        reserve: toReserve,
        replacePlayerId: replaceId,
      );
      await reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> historyEditor(
    String table, {
    Map<String, Object?>? existing,
  }) async {
    if (playerId.isEmpty) await _ensurePlayer();
    if (!mounted) return;
    final field = table == 'Overall'
        ? 'overall'
        : table == 'MarketValue'
        ? 'value'
        : 'wage';
    final label = table == 'Overall'
        ? 'Classificação geral'
        : table == 'MarketValue'
        ? 'Valor de mercado'
        : 'Salário semanal';
    final financial = table != 'Overall';
    final initial = existing?[field]?.toString() ?? '';
    final valueController = TextEditingController(
      text: financial
          ? ThousandsSeparatorInputFormatter.format(initial)
          : initial,
    );
    final roleController = TextEditingController(
      text: existing?['squadRole']?.toString() ?? '',
    );
    DateTime chosenDate =
        DateTime.tryParse(existing?['date']?.toString() ?? '') ??
        DateTime.now();
    DateTime? endDate = DateTime.tryParse(
      existing?['endDate']?.toString() ?? '',
    );
    Future<void>? dialogDismissed;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        dialogDismissed = ModalRoute.of(dialogContext)?.completed.then((_) {});
        return StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(
              existing == null ? 'Adicionar $label' : 'Editar $label',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: valueController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: financial
                      ? [ThousandsSeparatorInputFormatter()]
                      : null,
                  decoration: InputDecoration(labelText: label),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(DateFormat('dd/MM/yyyy').format(chosenDate)),
                  onPressed: () async {
                    final picked = await showCareerDatePicker(
                      context: context,
                      personId: widget.person.id,
                      initialDate: chosenDate,
                      firstDate: DateTime(1950),
                      lastDate: DateTime(2100),
                    );
                    if (context.mounted && picked != null) {
                      update(() => chosenDate = picked);
                    }
                  },
                ),
                if (table == 'ContractItem') ...[
                  TextButton.icon(
                    icon: const Icon(Icons.event),
                    label: Text(
                      endDate == null
                          ? 'Fim do contrato'
                          : DateFormat('dd/MM/yyyy').format(endDate!),
                    ),
                    onPressed: () async {
                      final picked = await showCareerDatePicker(
                        context: context,
                        personId: widget.person.id,
                        initialDate: endDate ?? chosenDate,
                        firstDate: DateTime(1950),
                        lastDate: DateTime(2100),
                      );
                      if (context.mounted && picked != null) {
                        update(() => endDate = picked);
                      }
                    },
                  ),
                  TextField(
                    controller: roleController,
                    decoration: const InputDecoration(labelText: 'Função'),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Salvar'),
              ),
            ],
          ),
        );
      },
    );
    if (submitted == true) {
      final parsed = financial
          ? ThousandsSeparatorInputFormatter.parse(valueController.text)
          : int.tryParse(valueController.text.trim());
      if (parsed == null || parsed < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Informe um valor válido')),
          );
        }
      } else {
        final value = <String, Object?>{
          'id': existing?['id'] ?? const Uuid().v4(),
          'personId': widget.person.id,
          'customPlayerId': playerId,
          'date': chosenDate.toIso8601String(),
          'createdAt':
              existing?['createdAt'] ?? DateTime.now().toIso8601String(),
          field: parsed,
          if (table == 'ContractItem') 'endDate': endDate?.toIso8601String(),
          if (table == 'ContractItem') 'squadRole': roleController.text.trim(),
        };
        try {
          if (existing == null) {
            await sql.addPlayerHistory(table, value);
          } else {
            await sql.updatePlayerHistory(table, widget.person.id, value);
          }
          if (mounted) refreshData();
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('$error')));
          }
        }
      }
    }
    await dialogDismissed;
    valueController.dispose();
    roleController.dispose();
  }

  Future<void> historyList(
    String table,
    List<Map<String, Object?>> records,
  ) async {
    final label = table == 'Overall'
        ? 'Classificação geral'
        : table == 'ContractItem'
        ? 'Salário'
        : 'Valor de mercado';
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text('Histórico: $label')),
            if (records.isEmpty)
              const ListTile(title: Text('Nenhum registro ainda')),
            for (final record in records)
              ListTile(
                title: Text(
                  table == 'Overall'
                      ? '${record['overall']}'
                      : money(
                          record[table == 'ContractItem' ? 'wage' : 'value'],
                        ),
                ),
                subtitle: Text(
                  '${date(record['date'])}${record['isSeasonInitial'] == true ? ' • Início da temporada' : ''}',
                ),
                trailing: record['isSeasonInitial'] == true
                    ? IconButton(
                        tooltip: 'Editar valor inicial da temporada',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          edit(initialSeasonId: record['seasonId']?.toString());
                        },
                      )
                    : IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await sql.deletePlayerHistory(
                            table,
                            widget.person.id,
                            record['id'] as String,
                          );
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          refreshData();
                        },
                      ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (record['isSeasonInitial'] == true) {
                    edit(initialSeasonId: record['seasonId']?.toString());
                  } else {
                    historyEditor(table, existing: record);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(PlayerProfileData? data) => Container(
    margin: const EdgeInsets.fromLTRB(16, 6, 16, 18),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.of(context).headerStart,
          AppColors.of(context).panel,
        ],
      ),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(
        color: AppColors.of(context).accent.withValues(alpha: .3),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PERFIL DO JOGADOR',
          style: TextStyle(
            color: AppColors.of(context).accent,
            fontSize: 10,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              width: 72,
              height: 82,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: AppColors.of(context).text.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(18),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: ProfilePortrait(
                  version: widget.person.fifaVersion,
                  realPlayerId: row['realPlayerId'] as String?,
                  customAvatarFilePath: row['customAvatarFilePath'] as String?,
                  width: 62,
                  height: 72,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 22,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: AppColors.of(context).text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  FutureBuilder<CatalogItem?>(
                    future: _club,
                    builder: (context, snapshot) =>
                        snapshot.connectionState == ConnectionState.done
                        ? ClubLine(
                            key: const ValueKey('player-club'),
                            version: widget.person.fifaVersion,
                            club: snapshot.data,
                            unknown: row['clubUnknown'] == true,
                            size: 18,
                            style: TextStyle(
                              color: AppColors.of(context).text
                                  .withValues(alpha: .85),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : const SizedBox(height: 18),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final label in [
                        position,
                        if (row['shirtNumber'] != null)
                          '#${row['shirtNumber']}',
                        if (!_other)
                          row['isBench'] == 1 ? 'Reserva' : 'Titular',
                      ])
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.of(context).text
                                .withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: AppColors.of(context).muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            for (final (label, value) in [
              ('GER', data?.latestOverall ?? overall),
              if (potential != null) ('POT', potential),
            ]) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.of(context).accent.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: AppColors.of(context).accent.withValues(alpha: .25),
                  ),
                ),
                child: Text(
                  '$label  ${value ?? '—'}',
                  style: TextStyle(
                    color: AppColors.of(context).accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    ),
  );

  List<String> get _tabLabels => _other
      ? const ['Detalhes', 'Temporada', 'Transferências', 'Carreira']
      : const [
          'Detalhes',
          'Temporada',
          'Resumo',
          'Partidas',
          'Carreira',
          'Transferências',
        ];

  Widget _tabs() => Container(
    color: AppColors.of(context).background,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.of(context).panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.of(context).accent.withValues(alpha: .2),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final style = DefaultTextStyle.of(context).style.merge(
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          );
          final share = constraints.maxWidth / _tabLabels.length;
          final scroll = _tabLabels.any((label) {
            final painter = TextPainter(
              text: TextSpan(text: label, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final width = painter.width;
            painter.dispose();
            return width + 12 > share;
          });
          return TabBar(
            indicator: BoxDecoration(
              color: AppColors.of(context).accent.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(12),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: EdgeInsets.zero,
            dividerColor: Colors.transparent,
            labelColor: AppColors.of(context).accent,
            unselectedLabelColor: AppColors.of(context).muted,
            labelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            isScrollable: scroll,
            tabAlignment: scroll ? TabAlignment.start : null,
            labelPadding: scroll
                ? const EdgeInsets.symmetric(horizontal: 13)
                : EdgeInsets.zero,
            tabs: [for (final label in _tabLabels) Tab(text: label)],
          );
        },
      ),
    ),
  );

  Widget _details(PlayerProfileData data) {
    final rawBirthdate = row['birthdate'];
    final birthdate = rawBirthdate is num
        ? DateTime.fromMillisecondsSinceEpoch(rawBirthdate.toInt())
        : DateTime.tryParse(rawBirthdate?.toString() ?? '') ??
              widget.realPlayer?.birthdate;
    final selectedSeason = data.seasons
        .where((season) => season.id == seasonId)
        .firstOrNull;
    final age = selectedSeason == null
        ? null
        : calcPlayerAge(
            fifaVersion: widget.person.fifaVersion,
            seasonStart: selectedSeason.startDate,
            seasonEnd: selectedSeason.endDate,
            birthdate: birthdate,
            firstSeasonAge: (row['firstSeasonAge'] as num?)?.toInt(),
          );
    final catalog = GameCatalog.current;
    final nationalities = catalog?.nationalities ?? const <CatalogItem>[];
    final hasSavedNationality = row.containsKey('nationalityId');
    final nationalityId = hasSavedNationality
        ? row['nationalityId']?.toString()
        : widget.realPlayer?.nationalityCode;
    final nationalityName = widget.realPlayer?.nationalityName?.toLowerCase();
    final nationality =
        nationalities.where((item) => item.id == nationalityId).firstOrNull ??
        (hasSavedNationality
            ? null
            : nationalities
                  .where((item) => item.label.toLowerCase() == nationalityName)
                  .firstOrNull);
    final flag = nationality?.imageUrl == null
        ? null
        : CachedNetworkImage(
            imageUrl: nationality!.imageUrl!,
            width: 19,
            height: 14,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          );
    final height = row.containsKey('playerHeight')
        ? row['playerHeight']
        : widget.realPlayer?.height;
    final weight = row.containsKey('playerWeight')
        ? row['playerWeight']
        : widget.realPlayer?.weight;
    final foot = row['customFoot'] ?? widget.realPlayer?.foot;
    final contract = data.contracts.firstOrNull;
    final weeklyWage = contract?['wage'] ?? row['wage'];
    final annualWage =
        row['yearlyWage'] ?? (weeklyWage is num ? weeklyWage * 52 : null);
    final currentOverall = data.latestOverall ?? overall;
    final currentValue = data.latestMarketValue ?? row['marketValue'];
    final overallPoints = profileHistoryPoints(data.overalls, 'overall');
    if (overallPoints.isEmpty && currentOverall != null) {
      overallPoints.add(ProfileChartPoint(currentOverall.toDouble()));
    }
    return PlayerProfileScroll(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        PlayerInfoGrid(
          title: 'Informações pessoais',
          items: [
            (
              label: 'Nacionalidade',
              value: nationality == null
                  ? '—'
                  : 'countries.${nationality.label}'.tr(),
              leading: flag,
            ),
            (
              label:
                  'Idade${selectedSeason == null ? '' : ' em ${selectedSeason.startDate.year}'}',
              value: age?.toString() ?? '—',
              leading: null,
            ),
            (
              label: 'Altura',
              value: height == null ? '—' : '$height cm',
              leading: null,
            ),
            (
              label: 'Peso',
              value: weight == null ? '—' : '$weight kg',
              leading: null,
            ),
            (
              label: 'Pé preferido',
              value: foot == 'Right'
                  ? 'Direita'
                  : foot == 'Left'
                  ? 'Esquerda'
                  : foot?.toString() ?? '—',
              leading: null,
            ),
            (label: 'Posição', value: position, leading: null),
          ],
        ),
        if (_other) _clubPanel(currentValue),
        if (!_other)
          PlayerInfoGrid(
            title: 'No elenco',
            items: [
              (
                label: 'Número da Camisa',
                value: row['shirtNumber']?.toString() ?? '—',
                leading: null,
              ),
              (
                label: 'Salário semanal',
                value: money(weeklyWage),
                leading: null,
              ),
              (
                label: 'Valor de mercado',
                value: money(currentValue),
                leading: null,
              ),
            ],
          ),
        PlayerHistoryCard(
          title: 'Classificação geral',
          value: '${currentOverall ?? '—'}',
          points: overallPoints,
          onHistory: () => historyList('Overall', data.overalls),
          onAdd: () => historyEditor('Overall'),
        ),
        if (!_other)
          ProfilePanel(
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Contrato atual',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    _squareAction(
                      Icons.edit_outlined,
                      () => historyEditor('ContractItem', existing: contract),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => historyEditor('ContractItem'),
                    icon: const Icon(Icons.add_rounded, size: 17),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    label: const Text(
                      'Oferecer contrato',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ProfileLine('Início do contrato', date(contract?['date'])),
                ProfileLine('Fim do contrato', date(contract?['endDate'])),
                ProfileLine('Semanal', money(weeklyWage)),
                ProfileLine('Anual', money(annualWage)),
                ProfileLine(
                  'Função',
                  contract?['squadRole']?.toString() ?? '–',
                ),
              ],
            ),
          ),
        if (!_other)
          PlayerHistoryCard(
            title: 'Salário',
            value: money(weeklyWage),
            points: profileHistoryPoints(data.contracts, 'wage'),
            compactAxis: true,
            valueFormatter: money,
            onHistory: () => historyList('ContractItem', data.contracts),
            onAdd: () => historyEditor('ContractItem'),
          ),
        PlayerHistoryCard(
          title: 'Valor de mercado',
          value: money(currentValue),
          points: profileHistoryPoints(data.marketValues, 'value'),
          compactAxis: true,
          valueFormatter: money,
          onHistory: () => historyList('MarketValue', data.marketValues),
          onAdd: () => historyEditor('MarketValue'),
        ),
        if (row['id'] != null && row['statisticsReadOnlyRoster'] != true)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: OutlinedButton.icon(
              onPressed: move,
              icon: Icon(
                row['isBench'] == 1 ? Icons.arrow_upward : Icons.arrow_downward,
              ),
              label: Text(
                row['isBench'] == 1
                    ? 'Mover para titular'
                    : 'Mover para reserva',
              ),
            ),
          ),
      ],
    );
  }

  Widget _clubPanel(Object? marketValue) {
    final c = AppColors.of(context);
    return ProfilePanel(
      key: const ValueKey('player-club-panel'),
      child: FutureBuilder<CatalogItem?>(
        future: _club,
        builder: (context, snapshot) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Clube atual',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ClubLine(
              version: widget.person.fifaVersion,
              club: snapshot.data,
              size: 30,
              style: TextStyle(
                color: c.text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ProfileLine(
              'Número da camisa',
              row['shirtNumber']?.toString() ?? '—',
            ),
            ProfileLine('Valor de mercado', money(marketValue)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    key: const ValueKey('player-transfer'),
                    onPressed: _transfer,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('Transferir'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('player-release'),
                    onPressed: snapshot.data == null ? null : _release,
                    icon: const Icon(Icons.person_off_outlined, size: 18),
                    label: const Text('Liberar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _squareAction(IconData icon, VoidCallback action) => SizedBox(
    width: 37,
    height: 37,
    child: FilledButton(
      onPressed: action,
      style: FilledButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: AppColors.of(context).accent.withValues(alpha: .12),
        foregroundColor: AppColors.of(context).accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Icon(icon, size: 20),
    ),
  );

  static String seasonName(Season season) =>
      season.startDate.year == season.endDate.year
      ? '${season.startDate.year}'
      : '${season.startDate.year}/${season.endDate.year}';

  Widget _seasonPicker(PlayerProfileData data) {
    final active =
        data.seasons.where((s) => s.id == seasonId).firstOrNull ??
        data.seasons.firstOrNull;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.only(left: 14, right: 10),
      decoration: BoxDecoration(
        color: AppColors.of(context).panel,
        border: Border.all(color: AppColors.of(context).line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_month_outlined,
            size: 18,
            color: AppColors.of(context).accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: active?.id,
                isExpanded: true,
                dropdownColor: AppColors.of(context).panel,
                hint: const Text('Temporada'),
                items: [
                  for (final season in data.seasons)
                    DropdownMenuItem(
                      value: season.id,
                      child: Text('Temporada ${seasonName(season)}'),
                    ),
                ],
                onChanged: (value) => setState(() => seasonId = value),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ratingsChart(PlayerProfileData data, String? selectedSeason) {
    final season = data.seasons
        .where((s) => s.id == selectedSeason)
        .firstOrNull;
    final matches = data.filtered(seasonId: selectedSeason);
    final groups = <DateTime, List<double>>{};
    for (final match in matches) {
      final day = match.date;
      final rating = match.performance.avgRating;
      if (day != null && rating != null) {
        groups.putIfAbsent(DateTime(day.year, day.month), () => []).add(rating);
      }
    }
    final points = [
      for (final entry in groups.entries)
        ProfileChartPoint(
          entry.value.reduce((a, b) => a + b) / entry.value.length,
          date: entry.key,
          caption: '${entry.value.length} atuações avaliadas',
        ),
    ];
    final total = PlayerTotals(matches);
    final average = total.rating;
    return ProfilePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nota mês a mês',
                      style: TextStyle(
                        color: AppColors.of(context).text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Média das notas de cada mês; a linha tracejada é a média da temporada.',
                      style: TextStyle(
                        color: AppColors.of(context).muted,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (average != null) ...[
                const SizedBox(width: 12),
                ProfileRating(average, small: true),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (season != null && points.isNotEmpty)
            ProfileMonthlyRatingsChart(
              key: ValueKey(season.id),
              points: points,
              start: season.startDate,
              end: season.endDate,
              average: average,
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                season == null
                    ? 'Selecione uma temporada.'
                    : 'Nenhuma nota registrada nesta temporada.',
                style: TextStyle(color: AppColors.of(context).muted),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _seasonTables(List<PlayerMatchData> matches) {
    final n = PlayerNumbers(matches), total = n.totals;
    String count(num? value) => analysisNumber(value);
    String per90(num? value) => analysisNumber(n.per90(value), decimals: 2);
    StatRow? counted(
      String label,
      num? value, {
      String? help,
      int decimals = 0,
    }) => value == null
        ? null
        : StatRow(
            label,
            analysisNumber(value, decimals: decimals),
            per90: per90(value),
            help: help,
          );
    StatRow? percent(String label, double? value, String help) => value == null
        ? null
        : StatRow(
            label,
            analysisPercent(value),
            share: value / 100,
            help: help,
          );
    StatRow? every(String label, int events) {
      final minutes = n.minutesPer(events);
      return minutes == null
          ? null
          : StatRow(
              label,
              "${minutes.round()}'",
              help: 'Minutos em campo divididos pelo total.',
            );
    }

    String accuracy(PlayersStatMetric metric, String what) => n.averaged(metric)
        ? 'Média dos percentuais de $what informados em cada partida.'
        : 'Acertos ÷ tentativas de $what, somando as partidas com os dois números.';
    final keeper =
        (row['customPositionId'] ?? widget.realPlayer?.mainPositionId) == '0' ||
        (n.saves ?? 0) > 0;
    return [
      StatTable(
        title: 'Ataque',
        rows: [
          ?counted('Gols', total.goals),
          ?counted('Gols de pênalti', n.penaltyGoals),
          ?counted(
            'Gols esperados (xG)',
            n.expectedGoals,
            decimals: 2,
            help: 'Gols esperados sem pênaltis, do relatório das partidas.',
          ),
          ?counted('Finalizações', n.shots),
          ?percent(
            'No alvo',
            n.shotAccuracy,
            accuracy(PlayersStatMetric.shotAccuracy, 'finalização'),
          ),
          ?percent(
            'Conversão',
            n.conversion,
            'Gols ÷ finalizações nas partidas com finalizações registradas.',
          ),
          ?every('Minutos por gol', total.goals),
          if (n.hatTricks > 0) StatRow('Hat-tricks', count(n.hatTricks)),
        ],
      ),
      StatTable(
        title: 'Criação',
        rows: [
          ?counted('Assistências', total.assists),
          ?counted(
            'Assistências esperadas (xA)',
            n.expectedAssists,
            decimals: 2,
            help: 'Assistências esperadas, do relatório das partidas.',
          ),
          ?counted('Passes-chave', n.keyPasses),
          ?counted('Passes', n.passes),
          ?percent(
            'Precisão de passe',
            n.passAccuracy,
            accuracy(PlayersStatMetric.passAccuracy, 'passe'),
          ),
          ?counted('Dribles', n.dribbles),
          ?percent(
            'Dribles certos',
            n.dribbleAccuracy,
            accuracy(PlayersStatMetric.dribbleAccuracy, 'drible'),
          ),
          ?every('Minutos por assistência', total.assists),
        ],
      ),
      StatTable(
        title: 'Defesa e disciplina',
        rows: [
          ?counted('Desarmes', n.tackles),
          ?percent(
            'Desarmes certos',
            n.tackleAccuracy,
            accuracy(PlayersStatMetric.tackleAccuracy, 'desarme'),
          ),
          if (keeper) ...[
            ?counted('Defesas', n.saves),
            ?counted('Pênaltis defendidos', n.penaltySaves),
            StatRow(
              'Jogos sem sofrer gols',
              count(n.cleanSheets),
              help: 'Partidas em que o time terminou sem sofrer gols.',
            ),
          ],
          StatRow(
            'Cartões amarelos',
            count(total.yellowCards),
            per90: total.yellowCards == 0 ? null : per90(total.yellowCards),
          ),
          StatRow('Cartões vermelhos', count(total.redCards)),
        ],
      ),
    ];
  }

  Widget _season(PlayerProfileData data) {
    final selected = data.seasons.where((s) => s.id == seasonId).firstOrNull;
    final selectedId = selected?.id ?? data.seasons.firstOrNull?.id;
    final matches = data.filtered(seasonId: selectedId);
    final shown = selected ?? data.seasons.firstOrNull;
    return PlayerProfileScroll(
      key: const PageStorageKey('player-season-statistics'),
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        _seasonPicker(data),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: PlayerPerformanceOverview(
            matches: matches,
            title: 'Resumo da temporada',
            subtitle: shown == null
                ? 'Temporada atual.'
                : 'Temporada ${seasonName(shown)} · toque nos números das tabelas para ver como são calculados.',
          ),
        ),
        _ratingsChart(data, selectedId),
        if (matches.isNotEmpty) ..._seasonTables(matches),
        PlayerScoringInsights(matches: matches),
        PlayerCaptainInsights(matches: matches),
        PlayerDetailedStats(matches: matches),
      ],
    );
  }

  Widget _worldSeason(PlayerProfileData data) {
    final selected = data.seasons.where((s) => s.id == seasonId).firstOrNull;
    final selectedId = selected?.id ?? data.seasons.firstOrNull?.id;
    final matches = data.filtered(seasonId: selectedId);
    return PlayerProfileScroll(
      key: const PageStorageKey('player-world-season'),
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        _seasonPicker(data),
        FutureBuilder<Map<String, List<CompetitionLine>>>(
          future: _lines,
          builder: (context, snapshot) =>
              snapshot.connectionState != ConnectionState.done
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : PlayerWorldSeasonPanel(
                  version: widget.person.fifaVersion,
                  lines:
                      snapshot.data?[selectedId] ??
                      (_transient != null && _transient!.seasonId == selectedId
                          ? _transient!.lines
                          : const []),
                  onRefresh: _syncing ? null : () => _syncWorld(),
                  syncing: _syncing,
                  syncError: _syncError,
                  onEdit: (line) => _editLine(selectedId, line),
                  onAdd: () => _editLine(selectedId, null),
                ),
        ),
        if (matches.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: PlayerPerformanceOverview(
              matches: matches,
              title: 'Pelo seu clube',
              subtitle:
                  'Partidas registradas com a sua equipe nesta temporada.',
            ),
          ),
          ..._seasonTables(matches),
        ],
      ],
    );
  }

  Widget _worldCareer(PlayerProfileData data) => PlayerProfileScroll(
    key: const PageStorageKey('player-world-career'),
    padding: const EdgeInsets.only(top: 8, bottom: 24),
    children: [
      FutureBuilder<Map<String, List<CompetitionLine>>>(
        future: _lines,
        builder: (context, snapshot) => PlayerWorldCareerPanel(
          version: widget.person.fifaVersion,
          seasons: [...data.seasons]
            ..sort((a, b) => b.startDate.compareTo(a.startDate)),
          lines: snapshot.data ?? const {},
        ),
      ),
      if (data.matches.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Text(
            'Pelo seu clube',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        ..._careerChildren(data),
      ],
    ],
  );

  Widget _transfersTab() => FutureBuilder<CatalogItem?>(
    future: _club,
    builder: (context, snapshot) => PlayerTransfersTab(
      key: ValueKey('transfers-$playerId-$_transfersVersion'),
      person: widget.person,
      playerId: playerId,
      repository: _world,
      currentClub: snapshot.data,
      currency: currency,
      ensurePlayer: _ensurePlayer,
      onChanged: _other ? reload : () {},
      ownSquad: _ownSquad,
    ),
  );

  Widget _tournamentFilter(PlayerProfileData data) {
    final ids = data.matches
        .map((match) => match.tournamentId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final label = tournamentId == null
        ? 'Todos os Torneios'
        : data.tournamentNames[tournamentId] ?? tournamentId!;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: OutlinedButton(
          onPressed: () async {
            final selected = await showModalBottomSheet<String>(
              context: context,
              builder: (context) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      title: const Text('Todos os Torneios'),
                      onTap: () => Navigator.pop(context, ''),
                    ),
                    for (final id in ids)
                      ListTile(
                        title: Text(data.tournamentNames[id] ?? id),
                        onTap: () => Navigator.pop(context, id),
                      ),
                  ],
                ),
              ),
            );
            if (selected != null) {
              setState(() => tournamentId = selected.isEmpty ? null : selected);
            }
          },
          style: OutlinedButton.styleFrom(
            backgroundColor: AppColors.of(context).panel,
            foregroundColor: AppColors.of(context).muted,
            side: BorderSide.none,
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
            shape: const StadiumBorder(),
          ),
          child: Text(label),
        ),
      ),
    );
  }

  Future<void> _openMatch(PlayerMatchData match, PlayerProfileData data) async {
    final fixture = await SqlService.instance.getManagerFixtureById(
      widget.person.id,
      match.fixtureId,
    );
    if (fixture == null || !mounted) return;
    final opponentId = match.row['oppositeTeamId']?.toString() ?? '';
    final opponent =
        GameCatalog.current?.teamLabel(widget.person.fifaVersion, opponentId) ??
        opponentId;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FixtureDetailsPage(
          person: widget.person,
          fixture: fixture,
          opponent: opponent,
          tournament:
              data.tournamentNames[match.tournamentId] ?? match.tournamentId,
        ),
      ),
    );
  }

  List<Widget> _eventIcons(PlayerMatchData match) {
    Iterable<Widget> repeat(int count, Widget icon) sync* {
      if (count > 3) {
        yield icon;
        yield Text('$count', style: const TextStyle(fontSize: 11));
      } else {
        for (var i = 0; i < count; i++) {
          yield icon;
        }
      }
    }

    const gap = SizedBox(width: 3);
    return [
      if (match.wasCaptain) const CaptainBadge(size: 15),
      ...repeat(match.performance.yellowCards ?? 0, const FixtureCardIcon()),
      ...repeat(
        match.performance.redCards ?? 0,
        const FixtureCardIcon(red: true),
      ),
      for (final icon in [
        ...repeat(match.assists, const Icon(TablerIcons.shoe, size: 14)),
        ...repeat(match.goals, const Icon(TablerIcons.ballFootball, size: 13)),
      ]) ...[gap, icon],
    ];
  }

  Widget _matchesPeriodPicker(PlayerProfileData data) {
    final current =
        data.seasons.where((s) => s.id == row['seasonId']).firstOrNull ??
        data.seasons.firstOrNull;
    return Builder(
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: DropdownButtonFormField<String>(
          key: const ValueKey('player-matches-period'),
          initialValue: _matchesPeriod,
          isExpanded: true,
          decoration: managerFieldDecoration(
            context,
            'Temporada das partidas',
            icon: Icons.calendar_month_outlined,
          ),
          items: [
            DropdownMenuItem(
              value: 'current',
              child: Text(
                current == null
                    ? 'Temporada atual'
                    : 'Atual · ${seasonName(current)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const DropdownMenuItem(
              value: 'all',
              child: Text('Todas as temporadas'),
            ),
            for (final season in data.seasons)
              DropdownMenuItem(
                value: 'season:${season.id}',
                child: Text(seasonName(season)),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _matchesPeriod = value);
          },
        ),
      ),
    );
  }

  Widget _matches(PlayerProfileData data) {
    final currentSeason =
        data.seasons.where((s) => s.id == row['seasonId']).firstOrNull ??
        data.seasons.firstOrNull;
    final filtered = data.filtered(
      seasonId: _matchesPeriod == 'current'
          ? currentSeason?.id ?? row['seasonId']?.toString()
          : _matchesPeriod == 'all'
          ? null
          : _matchesPeriod.substring('season:'.length),
      tournamentId: tournamentId,
    );
    return PlayerProfileScroll(
      key: const PageStorageKey('player-matches-statistics'),
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        _matchesPeriodPicker(data),
        _tournamentFilter(data),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(25),
            child: Text(
              'Nenhuma atuação registrada.',
              textAlign: TextAlign.center,
            ),
          ),
        for (final group in groupByConsecutiveTournament(
          filtered,
          (match) => match.tournamentId,
        ))
          FixtureTournamentCard(
            fifaVersion: widget.person.fifaVersion,
            tournamentId: group.first.tournamentId,
            tournamentName:
                data.tournamentNames[group.first.tournamentId] ??
                group.first.tournamentId,
            children: [
              for (final match in group)
                FixtureResultTile(
                  fifaVersion: widget.person.fifaVersion,
                  fixture: {
                    ...match.row,
                    'playerTeamId':
                        match.row['playerTeamId'] ?? widget.person.teamId,
                  },
                  ownIcons: _eventIcons(match),
                  trailing: ProfileRating(
                    match.performance.avgRating,
                    small: true,
                  ),
                  onTap: () => _openMatch(match, data),
                ),
            ],
          ),
      ],
    );
  }

  List<String> _careerHeaders() => switch (careerCategory) {
    'Remate' => ['Temp.', 'MP', 'GLS', 'PEN', 'REM', 'PREC', 'MIN'],
    'Jogo em equipe' => ['Temp.', 'MP', 'AST', 'PAS', 'CHV', 'PREC', 'MIN'],
    'Defesa' => ['Temp.', 'MP', 'DES', 'CAR', 'DEF', 'AR', 'MIN'],
    _ => ['Temporada', 'MP', 'GLS', 'AST', 'AR', 'MOTM', 'MIN'],
  };

  List<String> _careerValues(String seasonLabel, PlayerTotals total) =>
      switch (careerCategory) {
        'Remate' => [
          seasonLabel,
          '${total.matches}',
          '${total.goals}',
          total.hasGoalDetails ? '${total.penalties}' : '–',
          total.hasShots ? '${total.shots}' : '–',
          total.hasShots ? total.perGame(total.shots) : '–',
          '${total.minutes}',
        ],
        'Jogo em equipe' => [
          seasonLabel,
          '${total.matches}',
          '${total.assists}',
          total.hasPasses ? '${total.passes}' : '–',
          total.hasPasses ? '${total.keyPasses}' : '–',
          total.hasPasses ? total.perGame(total.passes) : '–',
          '${total.minutes}',
        ],
        'Defesa' => [
          seasonLabel,
          '${total.matches}',
          total.hasTackles ? '${total.tackles}' : '–',
          '${total.yellowCards + total.redCards}',
          '${total.saves}',
          total.ratingLabel,
          '${total.minutes}',
        ],
        _ => [
          seasonLabel,
          '${total.matches}',
          '${total.goals}',
          '${total.assists}',
          total.ratingLabel,
          '${total.motm}',
          '${total.minutes}',
        ],
      };

  Widget _careerRow(
    List<String> values, {
    bool header = false,
    bool total = false,
    bool striped = false,
  }) => Container(
    height: header ? 44 : 43,
    color: total
        ? AppColors.of(context).panel
        : striped
        ? AppColors.of(context).panel
        : AppColors.of(context).background,
    child: Row(
      children: [
        for (var i = 0; i < values.length; i++)
          SizedBox(
            width: i == 0
                ? 80
                : i == 6
                ? 55
                : 45,
            child: Center(
              child: Text(
                values[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: header ? 11 : 13,
                  color: header
                      ? AppColors.of(context).muted
                      : (i == 4 &&
                                careerCategory == 'Resumo' &&
                                values[i] != '–'
                            ? AppColors.salaryPositive
                            : AppColors.of(context).text),
                  fontWeight: total ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _career(PlayerProfileData data) => PlayerProfileScroll(
    padding: const EdgeInsets.only(top: 8, bottom: 24),
    children: _careerChildren(data),
  );

  List<Widget> _careerChildren(PlayerProfileData data) {
    final seasons = [...data.seasons]
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    final all = data.totals(tournamentId: tournamentId);
    return [
      _tournamentFilter(data),
      SizedBox(
        height: 51,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          scrollDirection: Axis.horizontal,
          children: [
            for (final category in const [
              'Resumo',
              'Remate',
              'Jogo em equipe',
              'Defesa',
            ])
              Padding(
                padding: const EdgeInsets.only(right: 9),
                child: ChoiceChip(
                  label: Text(category),
                  selected: careerCategory == category,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => careerCategory = category),
                  selectedColor: AppColors.of(context).accent,
                  backgroundColor: AppColors.of(context).panel,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  labelStyle: TextStyle(color: AppColors.of(context).muted),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          children: [
            _careerRow(_careerHeaders(), header: true),
            for (var i = 0; i < seasons.length; i++)
              _careerRow(
                _careerValues(
                  '${seasons[i].startDate.year % 100}/'
                  '${seasons[i].endDate.year % 100}',
                  data.totals(
                    seasonId: seasons[i].id,
                    tournamentId: tournamentId,
                  ),
                ),
                striped: i.isOdd,
              ),
            _careerRow(_careerValues('', all), total: true),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: careerDetailTheme(context),
    child: DefaultTabController(
      length: _tabLabels.length,
      child: Scaffold(
        backgroundColor: AppColors.of(context).background,
        appBar: AppBar(
          backgroundColor: AppColors.of(context).background,
          title: const Text('Jogador', style: TextStyle(fontSize: 18)),
          actions: [
            if (!_other)
              IconButton(
                onPressed: compare,
                tooltip: 'Comparar jogadores',
                icon: const Icon(Icons.people_outline),
              ),
            IconButton(
              onPressed: edit,
              tooltip: 'Editar jogador',
              icon: const Icon(Icons.edit_outlined),
            ),
            if (_other)
              PopupMenuButton<String>(
                key: const ValueKey('player-other-menu'),
                tooltip: 'Mais opções',
                onSelected: (action) => switch (action) {
                  'transfer' => _transfer(),
                  'release' => _release(),
                  _ => _hide(),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'transfer',
                    child: Text('Transferir para outro clube'),
                  ),
                  PopupMenuItem(
                    value: 'release',
                    child: Text('Liberar (sem clube)'),
                  ),
                  PopupMenuItem(value: 'hide', child: Text('Excluir jogador')),
                ],
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerScrolled) => [
            SliverToBoxAdapter(
              child: FutureBuilder<PlayerProfileData>(
                future: _data,
                builder: (_, snapshot) => _header(snapshot.data),
              ),
            ),
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverPersistentHeader(
                pinned: true,
                delegate: _PlayerTabsHeader(_tabs()),
              ),
            ),
          ],
          body: FutureBuilder<PlayerProfileData>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Erro ao carregar jogador: ${snapshot.error}'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              return TabBarView(
                children: _other
                    ? [
                        _details(data),
                        _worldSeason(data),
                        _transfersTab(),
                        _worldCareer(data),
                      ]
                    : [
                        _details(data),
                        _season(data),
                        PlayerSummaryTab(
                          person: widget.person,
                          data: data,
                          source: widget.summarySource,
                          sql: widget.sql,
                        ),
                        _matches(data),
                        _career(data),
                        _transfersTab(),
                      ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _PlayerTabsHeader extends SliverPersistentHeaderDelegate {
  _PlayerTabsHeader(this.child);
  final Widget child;
  @override
  double get minExtent => 66;
  @override
  double get maxExtent => 66;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;
  @override
  bool shouldRebuild(_PlayerTabsHeader old) => child != old.child;
}
