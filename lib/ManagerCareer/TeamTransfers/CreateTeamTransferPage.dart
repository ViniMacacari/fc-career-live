import '../../utils/AppColors.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../Common/SelectTeam/SelectTeamPage.dart';
import '../../Twitter/TwitterGenerationService.dart';
import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../models/TeamTransferItem.dart';
import '../../models/TransferPreviousClubStats.dart';
import '../../utils/Components/TeamLogo.dart';
import '../../utils/CareerDatePicker.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/SqlService.dart';
import '../TeamPage/ViewPlayer/PlayerProfileVisuals.dart' show ProfilePortrait;
import 'SelectTransferPlayerPage.dart';
import 'SelectTransferTypePage.dart';
import 'TransferStyle.dart';
import 'PlayerFarewellData.dart';
import 'PlayerFarewellDialog.dart';
import 'TransferPreviousClubStatsDialog.dart';

class CreateTeamTransferPage extends StatefulWidget {
  const CreateTeamTransferPage({
    super.key,
    required this.person,
    required this.season,
    required this.roster,
    required this.names,
    this.existing,
    this.initialPlayer,
    this.sql,
    this.transferNotifier,
  });
  final Person person;
  final Season season;
  final List<Map<String, Object?>> roster;
  final Map<String, String> names;
  final Map<String, Object?>? existing;
  final TransferPlayerChoice? initialPlayer;
  @visibleForTesting
  final SqlService? sql;
  @visibleForTesting
  final Future<void> Function(Person person, String id)? transferNotifier;
  @override
  State<CreateTeamTransferPage> createState() => _CreateTeamTransferPageState();
}

class _CreateTeamTransferPageState extends State<CreateTeamTransferPage> {
  SqlService get _sql => widget.sql ?? SqlService.instance;
  final _formKey = GlobalKey<FormState>();
  late final _initial = _loadInitial();
  late TransferPlayerChoice? _player = widget.initialPlayer;
  TransferPlayerChoice? _includedPlayer;
  late TransferPreviousClubStats? _previousStats =
      TransferPreviousClubStats.decode(widget.existing?['previousClubStats']);
  TransferPreviousClubStats? _includedPreviousStats;
  bool _previousStatsConfirmed = false, _includedStatsConfirmed = false;
  late List<Map<String, Object?>> _roster = [...widget.roster];
  late TeamTransferType _type = widget.existing == null
      ? TeamTransferType.buy
      : transferTypeFromRow(widget.existing!);
  late DateTime _date =
      DateTime.tryParse(widget.existing?['date']?.toString() ?? '') ??
      (DateTime.now().isBefore(widget.season.startDate) ||
              DateTime.now().isAfter(widget.season.endDate)
          ? widget.season.startDate
          : DateTime.now());
  CatalogItem? _fromTeam, _toTeam;
  late DateTime? _releaseDate = DateTime.tryParse(
    widget.existing?['releaseDate']?.toString() ?? '',
  );
  late String _endOfLoanDirection =
      widget.existing?['endOfLoanDirection']?.toString() ?? 'toYouClub';
  late final _wage = TextEditingController(
    text: transferMoney(widget.existing?['wage']),
  );
  late final _yearlyWage = TextEditingController(
    text: transferMoney(widget.existing?['yearlyWage']),
  );
  late final _transferValue = TextEditingController(
    text: transferMoney(widget.existing?['transferValue']),
  );
  bool _saving = false, _keepInSquad = false, _committed = false;

  bool get _endsLoan =>
      _type == TeamTransferType.endOfLoan ||
      _type == TeamTransferType.prematureEndOfLoan;
  bool get _isOutgoing => switch (_type) {
    TeamTransferType.sell ||
    TeamTransferType.sellFromLoan ||
    TeamTransferType.outLoan ||
    TeamTransferType.endOfContract ||
    TeamTransferType.retired => true,
    TeamTransferType.endOfLoan || TeamTransferType.prematureEndOfLoan =>
      _endOfLoanDirection == 'fromYourClub',
    TeamTransferType.freeTransfer => _fromTeam?.id == widget.person.teamId,
    _ => false,
  };
  bool get _hasFee => const {
    TeamTransferType.buy,
    TeamTransferType.sell,
    TeamTransferType.buyFromLoan,
    TeamTransferType.sellFromLoan,
    TeamTransferType.inLoan,
    TeamTransferType.outLoan,
  }.contains(_type);
  bool get _hasExchange => const {
    TeamTransferType.buy,
    TeamTransferType.sell,
    TeamTransferType.buyFromLoan,
    TeamTransferType.sellFromLoan,
  }.contains(_type);
  bool get _canRecordPreviousStats =>
      !_isOutgoing &&
      const {
        TeamTransferType.buy,
        TeamTransferType.buyFromLoan,
        TeamTransferType.inLoan,
        TeamTransferType.freeTransfer,
      }.contains(_type);
  bool get _canKeep => const {
    TeamTransferType.sell,
    TeamTransferType.sellFromLoan,
    TeamTransferType.endOfContract,
    TeamTransferType.retired,
  }.contains(_type);
  Set<String> get _rosterIds => {
    for (final row in _roster) row['playerId'] as String,
  };

  Future<GameCatalog> _loadInitial() async {
    final catalog = await GameCatalog.load();
    CatalogItem? team(String? id, String? leagueId) => id == null
        ? null
        : catalog.team(widget.person.fifaVersion, id, leagueId: leagueId) ??
              CatalogItem(
                id,
                catalog.teamLabel(widget.person.fifaVersion, id),
                leagueId: leagueId,
              );
    final row = widget.existing;
    if (row == null) {
      _toTeam = team(widget.person.teamId, widget.person.leagueId);
    } else {
      _fromTeam = team(
        row['fromTeamId']?.toString(),
        row['fromLeagueId']?.toString(),
      );
      _toTeam = team(
        row['toTeamId']?.toString(),
        row['toLeagueId']?.toString(),
      );
      final saved = await _sql.getCustomPlayerById(
        widget.person.id,
        row['playerInstanceId'] as String,
      );
      _player = TransferPlayerChoice(
        id: row['playerInstanceId'] as String,
        name:
            saved?['name']?.toString() ??
            widget.names[row['playerInstanceId']] ??
            'Jogador',
        custom: saved,
      );
      final paired = await _sql.getTeamTransferExchange(
        widget.person.id,
        row['id'] as String,
      );
      if (paired != null) {
        _includedPreviousStats = TransferPreviousClubStats.decode(
          paired['previousClubStats'],
        );
        final included = await _sql.getCustomPlayerById(
          widget.person.id,
          paired['playerInstanceId'] as String,
        );
        _includedPlayer = TransferPlayerChoice(
          id: paired['playerInstanceId'] as String,
          name: included?['name']?.toString() ?? 'Jogador',
          custom: included,
        );
      }
    }
    return catalog;
  }

  @override
  void dispose() {
    _wage.dispose();
    _yearlyWage.dispose();
    _transferValue.dispose();
    super.dispose();
  }

  Future<void> _pickType(GameCatalog catalog) async {
    final selected = await Navigator.push<TeamTransferType>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectTransferTypePage(selected: _type),
      ),
    );
    if (!mounted || selected == null || selected == _type) return;
    setState(() {
      _type = selected;
      _endOfLoanDirection = 'toYouClub';
      _includedPlayer = null;
      _previousStats = _includedPreviousStats = null;
      _previousStatsConfirmed = _includedStatsConfirmed = false;
      _keepInSquad = false;
      final own =
          catalog.team(
            widget.person.fifaVersion,
            widget.person.teamId,
            leagueId: widget.person.leagueId,
          ) ??
          CatalogItem(
            widget.person.teamId,
            catalog.teamLabel(widget.person.fifaVersion, widget.person.teamId),
            leagueId: widget.person.leagueId,
          );
      _fromTeam = _isOutgoing ? own : null;
      _toTeam = _isOutgoing ? null : own;
      if (_isOutgoing &&
          !_endsLoan &&
          _player != null &&
          !_rosterIds.contains(_player!.id) &&
          widget.existing == null) {
        _player = null;
      }
    });
  }

  Future<void> _pickPlayer({bool included = false}) async {
    final selected = await Navigator.push<TransferPlayerChoice>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectTransferPlayerPage(
          person: widget.person,
          season: widget.season,
          rosterIds: _rosterIds,
          onlyRoster: included ? !_isOutgoing : _isOutgoing && !_endsLoan,
          excludedIds: {
            if (included && _player != null) _player!.id,
            if (!included && _includedPlayer != null) _includedPlayer!.id,
          },
          optional: included,
        ),
      ),
    );
    if (!mounted || selected == null) return;
    final roster = await _sql.getTeamPlayers(
      widget.person.id,
      widget.season.id,
    );
    if (!mounted) return;
    setState(() {
      _roster = roster;
      if (included) {
        if (_includedPlayer?.id != selected.id) {
          _includedPreviousStats = null;
          _includedStatsConfirmed = false;
        }
        _includedPlayer = selected.id.isEmpty ? null : selected;
      } else {
        if (_player?.id != selected.id) {
          _previousStats = null;
          _previousStatsConfirmed = false;
        }
        _player = selected;
      }
    });
  }

  Future<void> _pickTeam(bool from) async {
    final selected = await Navigator.push<CatalogItem>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectTeamPage(fifaVersion: widget.person.fifaVersion),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      if (from) {
        if (_fromTeam?.id != selected.id) {
          _previousStats = null;
          _previousStatsConfirmed = false;
        }
        _fromTeam = selected;
      } else {
        _toTeam = selected;
      }
      _includedPlayer = null;
      _includedPreviousStats = null;
      _includedStatsConfirmed = false;
    });
  }

  Future<void> _pickDate() async {
    final selected = await showCareerDatePicker(
      context: context,
      personId: widget.person.id,
      firstDate: widget.season.startDate,
      lastDate: widget.season.endDate,
      initialDate: _date,
    );
    if (mounted && selected != null) setState(() => _date = selected);
  }

  Future<void> _pickReleaseDate() async {
    final selected = await showCareerDatePicker(
      context: context,
      personId: widget.person.id,
      firstDate: DateUtils.dateOnly(_date),
      lastDate: DateTime(widget.season.endDate.year + 10, 12, 31),
      initialDate: _releaseDate ?? _date,
    );
    if (mounted && selected != null) setState(() => _releaseDate = selected);
  }

  void _convertWage({bool fromAnnual = false}) {
    final value = parseTransferMoney(
      fromAnnual ? _yearlyWage.text : _wage.text,
    );
    if (value == null) return;
    final converted = fromAnnual
        ? (value / 52.1429).round()
        : (value * 52.1429).round();
    (fromAnnual ? _wage : _yearlyWage).text = transferMoney(converted);
  }

  Future<bool> _editPreviousStats({bool included = false}) async {
    final choice = included ? _includedPlayer : _player;
    if (choice == null) return false;
    FocusScope.of(context).unfocus();
    final result = await showTransferPreviousClubStats(
      context,
      playerName: choice.name,
      clubName: (included ? _toTeam : _fromTeam)?.label ?? 'Clube anterior',
      season: widget.season,
      date: _date,
      initial: included ? _includedPreviousStats : _previousStats,
    );
    if (!mounted || result == null) return false;
    setState(() {
      if (included) {
        _includedPreviousStats = result.stats;
        _includedStatsConfirmed = true;
      } else {
        _previousStats = result.stats;
        _previousStatsConfirmed = true;
      }
    });
    return true;
  }

  String get _hint => switch (_type) {
    TeamTransferType.outLoan =>
      'O jogador será emprestado ao clube em “Transferido Para”.',
    TeamTransferType.inLoan =>
      'O jogador chegará por empréstimo do clube em “Transferido De”.',
    TeamTransferType.endOfLoan || TeamTransferType.prematureEndOfLoan =>
      _endOfLoanDirection == 'toYouClub'
          ? 'O jogador voltará de empréstimo para o seu clube.'
          : 'O jogador será devolvido ao clube de origem.',
    TeamTransferType.sell || TeamTransferType.sellFromLoan =>
      'O jogador será transferido do seu clube para o clube selecionado.',
    TeamTransferType.endOfContract =>
      'O jogador sairá da equipe ao encerrar o contrato.',
    TeamTransferType.retired => 'O jogador sairá da equipe por aposentadoria.',
    TeamTransferType.youthAcademy =>
      'Registra a chegada de um jogador da academia ao time principal.',
    _ => 'Se “Transferido Para” for seu clube atual, o jogador será adicionado à sua equipe atual.',
  };

  Future<void> _save() async {
    if (_saving || _committed || !_formKey.currentState!.validate()) return;
    String? issue;
    if (_releaseDate != null &&
        DateUtils.dateOnly(_releaseDate!).isBefore(DateUtils.dateOnly(_date))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A liberação não pode ser anterior ao acordo.'),
        ),
      );
      return;
    }
    if (_player == null) {
      issue = 'Selecione o jogador.';
    } else if (_fromTeam != null && _fromTeam?.id == _toTeam?.id) {
      issue = 'Os clubes de origem e destino devem ser diferentes.';
    } else if (const {
          TeamTransferType.buy,
          TeamTransferType.sell,
          TeamTransferType.inLoan,
          TeamTransferType.outLoan,
          TeamTransferType.buyFromLoan,
          TeamTransferType.sellFromLoan,
        }.contains(_type) &&
        (_fromTeam == null || _toTeam == null)) {
      issue = 'Selecione os clubes de origem e destino.';
    } else if (_endsLoan &&
        (_endOfLoanDirection == 'toYouClub'
            ? _toTeam?.id != widget.person.teamId
            : _fromTeam?.id != widget.person.teamId)) {
      issue = 'Selecione seu clube no lado correspondente ao movimento do empréstimo.';
    } else if (const {
          TeamTransferType.buy,
          TeamTransferType.inLoan,
          TeamTransferType.buyFromLoan,
          TeamTransferType.youthAcademy,
        }.contains(_type) &&
        _toTeam?.id != widget.person.teamId) {
      issue =
          'Selecione seu clube em “Transferido Para” para registrar a chegada.';
    } else if (const {
          TeamTransferType.sell,
          TeamTransferType.sellFromLoan,
          TeamTransferType.outLoan,
          TeamTransferType.endOfContract,
        }.contains(_type) &&
        _fromTeam?.id != widget.person.teamId) {
      issue = 'Selecione seu clube em “Transferido De” para registrar a saída.';
    } else if (_type != TeamTransferType.retired &&
        _type != TeamTransferType.endOfContract &&
        _fromTeam?.id != widget.person.teamId &&
        _toTeam?.id != widget.person.teamId) {
      issue = 'A transferência deve envolver o seu clube atual.';
    }
    if (issue != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(issue)));
      return;
    }
    setState(() => _saving = true);
    if (widget.existing == null) {
      final needsPrimary = _canRecordPreviousStats && !_previousStatsConfirmed;
      final needsIncluded =
          _hasExchange &&
          _isOutgoing &&
          _includedPlayer != null &&
          !_includedStatsConfirmed;
      if ((needsPrimary && !await _editPreviousStats()) ||
          (needsIncluded && !await _editPreviousStats(included: true))) {
        if (mounted) setState(() => _saving = false);
        return;
      }
    }
    if (!mounted) return;
    final id = widget.existing?['id'] as String? ?? const Uuid().v4();
    final row = <String, Object?>{
      'id': id,
      'personId': widget.person.id,
      'seasonId': widget.season.id,
      'playerInstanceId': _player!.id,
      'fromTeamId': _fromTeam?.id,
      'fromLeagueId': _fromTeam?.leagueId,
      'toTeamId': _toTeam?.id,
      'toLeagueId': _toTeam?.leagueId,
      'wage': parseTransferMoney(_wage.text),
      'yearlyWage': parseTransferMoney(_yearlyWage.text),
      'transferValue': _hasFee ? parseTransferMoney(_transferValue.text) : null,
      'endOfLoanDirection': _endsLoan ? _endOfLoanDirection : null,
      'type': _type.name,
      'date': _date.toIso8601String(),
      'releaseDate': _releaseDate?.toIso8601String(),
      'previousClubStats': _canRecordPreviousStats
          ? _previousStats?.encode()
          : null,
    };
    final included = _hasExchange && _includedPlayer != null
        ? <String, Object?>{
            ...row,
            'id': '$id:exchange',
            'playerInstanceId': _includedPlayer!.id,
            'fromTeamId': _toTeam?.id,
            'fromLeagueId': _toTeam?.leagueId,
            'toTeamId': _fromTeam?.id,
            'toLeagueId': _fromTeam?.leagueId,
            'type': _isOutgoing
                ? TeamTransferType.buy.name
                : TeamTransferType.sell.name,
            'wage': null,
            'yearlyWage': null,
            'transferValue': null,
            'previousClubStats': _isOutgoing
                ? _includedPreviousStats?.encode()
                : null,
          }
        : null;
    try {
      await _sql.saveTeamTransfer(
        row,
        update: widget.existing != null,
        realPlayer: _player!.realPlayer,
        included: included,
        includedRealPlayer: _includedPlayer?.realPlayer,
        keepInSquad: _keepInSquad,
      );
      _committed = true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar transferência: $error')),
        );
      }
      if (mounted) setState(() => _saving = false);
      return;
    }
    try {
      await (widget.transferNotifier ??
          TwitterGenerationService.instance.onTransferSaved)(widget.person, id);
    } catch (error) {
      debugPrint('Transfer notification: $error');
    }
    if (!mounted) return;
    if (widget.existing == null) {
      PlayerFarewellData? farewell;
      try {
        farewell = await PlayerFarewellData.load(
          widget.person,
          id,
          sql: _sql,
          catalog: GameCatalog.current,
        );
      } catch (error) {
        debugPrint('Player farewell: $error');
        final sale = PlayerFarewellData.isClubSale(row, widget.person.teamId)
            ? row
            : included != null &&
                  PlayerFarewellData.isClubSale(included, widget.person.teamId)
            ? included
            : null;
        final choice = sale == row ? _player : _includedPlayer;
        if (sale != null && choice != null) {
          farewell = PlayerFarewellData.fromRecords(
            person: widget.person,
            transfer: sale,
            player: {
              'name': choice.name,
              'realPlayerId': choice.realPlayerId,
              'customAvatarFilePath': choice.avatar,
            },
            clubName: _fromTeam?.id == widget.person.teamId
                ? _fromTeam!.label
                : _toTeam!.label,
            destinationName: _fromTeam?.id == widget.person.teamId
                ? (_toTeam?.label ?? 'Novo clube')
                : (_fromTeam?.label ?? 'Novo clube'),
            matchRows: [],
            recordsAvailable: false,
          );
        }
      }
      if (farewell != null && mounted) {
        setState(() => _saving = false);
        await showPlayerFarewell(context, farewell);
      }
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover item de transferência?'),
        content: const Text(
          'O registro será removido do histórico de transferências.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _sql.deleteTeamTransfer(
        widget.person.id,
        widget.existing!['id'] as String,
      );
      await TwitterGenerationService.instance.onTransferDeleted(
        widget.person,
        widget.existing!['id'] as String,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao remover: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _moneyField(
    String label,
    TextEditingController controller, {
    VoidCallback? onChanged,
  }) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      TransferMoneyFormatter(),
    ],
    decoration: InputDecoration(
      hintText: label,
      labelText: controller.text.isEmpty ? null : label,
      suffixText: transferCurrency(widget.person),
      suffixStyle: TextStyle(fontSize: 25, color: AppColors.of(context).line),
    ),
    onChanged: (_) {
      onChanged?.call();
      setState(() {});
    },
    validator: (value) =>
        value != null && value.isNotEmpty && parseTransferMoney(value) == null
        ? 'Valor inválido'
        : null,
  );

  Widget _playerField(
    String label,
    TransferPlayerChoice? choice,
    bool included,
  ) => TransferPickerField(
    label: label,
    value: choice?.name,
    onTap: _saving ? null : () => _pickPlayer(included: included),
    leading: choice == null
        ? null
        : ProfilePortrait(
            version: widget.person.fifaVersion,
            realPlayerId: choice.realPlayerId,
            customAvatarFilePath: choice.avatar,
            width: 28,
            height: 32,
          ),
  );

  Widget _teamField(String label, CatalogItem? team, bool from) =>
      TransferPickerField(
        label: label,
        value: team?.label,
        leading: team == null ? null : TeamLogo.fromItem(team, size: 28),
        onTap: _saving ? null : () => _pickTeam(from),
      );

  Widget _previousStatsButton({bool included = false}) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      key: ValueKey(
        included
            ? 'edit-included-previous-club-stats'
            : 'edit-previous-club-stats',
      ),
      onPressed: _saving ? null : () => _editPreviousStats(included: included),
      icon: const Icon(Icons.insights_outlined, size: 18),
      label: const Text('Desempenho no clube anterior'),
    ),
  );

  @override
  Widget build(BuildContext context) => TransferTheme(
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null
              ? 'Adicionar Item de Transferência'
              : 'Editar Item de Transferência',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          if (widget.existing != null)
            IconButton(
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: FutureBuilder<GameCatalog>(
        future: _initial,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Não foi possível carregar: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                TransferPickerField(
                  label: 'Tipo de transferência',
                  value: transferTypeLabel(_type),
                  onTap: _saving ? null : () => _pickType(snapshot.data!),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 14,
                  ),
                  child: Text(
                    _hint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.of(context).muted,
                      fontSize: 12,
                    ),
                  ),
                ),
                _playerField('Jogador', _player, false),
                if (_canRecordPreviousStats && _player != null)
                  _previousStatsButton(),
                const SizedBox(height: 18),
                if (_endsLoan) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey(_endOfLoanDirection),
                    initialValue: _endOfLoanDirection,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Movimento do jogador',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'toYouClub',
                        child: Text('Voltar de Empréstimo'),
                      ),
                      DropdownMenuItem(
                        value: 'fromYourClub',
                        child: Text('Devolver ao clube de origem'),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            if (value == null || value == _endOfLoanDirection) {
                              return;
                            }
                            _endOfLoanDirection = value;
                            final from = _fromTeam;
                            _fromTeam = _toTeam;
                            _toTeam = from;
                          }),
                  ),
                  const SizedBox(height: 18),
                ],
                if (_type != TeamTransferType.youthAcademy &&
                    _type != TeamTransferType.retired) ...[
                  _teamField('Transferido De', _fromTeam, true),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Icon(
                      Icons.keyboard_double_arrow_down,
                      color: Colors.redAccent,
                      size: 28,
                    ),
                  ),
                ],
                if (_type != TeamTransferType.retired &&
                    _type != TeamTransferType.endOfContract) ...[
                  _teamField('Transferido Para', _toTeam, false),
                  const SizedBox(height: 18),
                ],
                if (!_isOutgoing) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _moneyField(
                          'Salário semanal',
                          _wage,
                          onChanged: _convertWage,
                        ),
                      ),
                      SizedBox(
                        width: 38,
                        child: IconButton(
                          tooltip: 'Converter salário anual para semanal',
                          onPressed: _saving
                              ? null
                              : () => setState(
                                  () => _convertWage(fromAnnual: true),
                                ),
                          icon: const Icon(Icons.swap_horiz, size: 24),
                        ),
                      ),
                      Expanded(
                        child: _moneyField(
                          'Salário anual',
                          _yearlyWage,
                          onChanged: () => _convertWage(fromAnnual: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
                if (_hasFee) ...[
                  _moneyField('Valor de Transferência', _transferValue),
                  const SizedBox(height: 18),
                ],
                if (_hasExchange) ...[
                  _playerField(
                    'Jogador a incluir (opcional)',
                    _includedPlayer,
                    true,
                  ),
                  if (_isOutgoing && _includedPlayer != null)
                    _previousStatsButton(included: true),
                  const SizedBox(height: 18),
                ],
                TransferPickerField(
                  label: 'Data do acordo',
                  value: DateFormat('dd/MM/yyyy').format(_date),
                  onTap: _saving ? null : _pickDate,
                  trailing: Icon(
                    Icons.calendar_month,
                    color: AppColors.of(context).muted,
                  ),
                ),
                const SizedBox(height: 18),
                TransferPickerField(
                  label: 'Data de liberação (opcional)',
                  value: _releaseDate == null
                      ? 'Na data do acordo'
                      : DateFormat('dd/MM/yyyy').format(_releaseDate!),
                  onTap: _saving ? null : _pickReleaseDate,
                  trailing: Icon(
                    Icons.calendar_month,
                    color: AppColors.of(context).muted,
                  ),
                ),
                if (_releaseDate != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _releaseDate = null),
                      child: const Text('Remover data de liberação'),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'O acordo registra a negociação. O jogador muda de clube na liberação, conforme a data das partidas da carreira.',
                    style: TextStyle(
                      color: AppColors.of(context).muted,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (_canKeep && widget.existing == null && _releaseDate == null)
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: const Text(
                      'Manter no elenco por enquanto',
                      style: TextStyle(fontSize: 14),
                    ),
                    value: _keepInSquad,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _keepInSquad = value),
                  ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  key: const ValueKey('save-team-transfer'),
                  onPressed: _saving || _committed ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.of(context).accent,
                    foregroundColor: AppColors.of(context).onAccent,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_saving ? 'Salvando...' : 'Salvar'),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
