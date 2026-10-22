import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../Common/SelectTeam/SelectTeamPage.dart';
import '../../../models/Person.dart';
import '../../../utils/AppColors.dart';
import '../../../utils/CareerDatePicker.dart';
import '../../../utils/GameCatalog.dart';
import '../../../utils/ThousandsSeparatorInputFormatter.dart';
import '../../OtherPlayers/OtherPlayerWidgets.dart';
import '../../OtherPlayers/OtherPlayersData.dart';
import 'PlayerProfileVisuals.dart';

class WorldTransferDraft {
  WorldTransferDraft({
    required this.date,
    required this.type,
    this.from,
    this.to,
    this.value,
    this.move = false,
  });
  DateTime date;
  String type;
  CatalogItem? from, to;
  int? value;
  bool move;
}

Future<WorldTransferDraft?> showWorldTransferSheet(
  BuildContext context, {
  required Person person,
  required WorldTransferDraft draft,
  required String currency,
  bool editing = false,
  bool canMove = true,
}) => showModalBottomSheet<WorldTransferDraft>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: AppColors.of(context).background,
  builder: (_) => _TransferSheet(
    person: person,
    draft: draft,
    currency: currency,
    editing: editing,
    canMove: canMove,
  ),
);

class _TransferSheet extends StatefulWidget {
  const _TransferSheet({
    required this.person,
    required this.draft,
    required this.currency,
    required this.editing,
    required this.canMove,
  });
  final Person person;
  final WorldTransferDraft draft;
  final String currency;
  final bool editing, canMove;
  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  late final WorldTransferDraft d = widget.draft;
  late final _value = TextEditingController(
    text: d.value == null
        ? ''
        : ThousandsSeparatorInputFormatter.format('${d.value}'),
  );
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _pickTeam(bool destination) async {
    final current = destination ? d.to : d.from;
    final team = await Navigator.push<CatalogItem>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectTeamPage(
          fifaVersion: widget.person.fifaVersion,
          selectedTeamId: current?.id,
          selectedLeagueId: current?.leagueId,
        ),
      ),
    );
    if (team == null || !mounted) return;
    setState(() {
      _error = null;
      if (destination) {
        d.to = team;
      } else {
        d.from = team;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showCareerDatePicker(
      context: context,
      personId: widget.person.id,
      initialDate: d.date,
      firstDate: DateTime(1950),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => d.date = picked);
  }

  void _save() {
    if (d.type != 'release' && d.to == null) {
      setState(() => _error = 'Escolha o clube de destino.');
      return;
    }
    if (d.move && d.to?.id == widget.person.teamId) {
      setState(
        () => _error =
            'Para trazer o jogador ao seu clube, registre em Transferências.',
      );
      return;
    }
    if (d.type == 'release') d.to = null;
    d.value = ThousandsSeparatorInputFormatter.parse(_value.text);
    Navigator.pop(context, d);
  }

  Widget _team(String label, CatalogItem? team, bool destination) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.panel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: ValueKey('transfer-${destination ? 'to' : 'from'}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => _pickTeam(destination),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .6,
                    ),
                  ),
                ),
                Expanded(
                  child: team == null && destination
                      ? Text(
                          'Escolher clube',
                          style: TextStyle(color: c.muted, fontSize: 14),
                        )
                      : ClubLine(
                          version: widget.person.fifaVersion,
                          club: team,
                          size: 22,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                if (team != null && !destination)
                  IconButton(
                    tooltip: 'Sem clube',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => d.from = null),
                    icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
                  )
                else
                  Icon(Icons.chevron_right_rounded, color: c.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.editing
                    ? 'Editar transferência'
                    : 'Registrar transferência',
                style: TextStyle(
                  color: c.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final MapEntry(:key, :value)
                      in worldTransferTypes.entries)
                    ChoiceChip(
                      key: ValueKey('transfer-type/$key'),
                      label: Text(value),
                      selected: d.type == key,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => d.type = key),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _team('DE', d.from, false),
              if (d.type != 'release') _team('PARA', d.to, true),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('transfer-date'),
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Text(DateFormat('dd/MM/yyyy').format(d.date)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('transfer-value'),
                      controller: _value,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsSeparatorInputFormatter()],
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Valor (opcional)',
                        suffixText: widget.currency,
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.canMove)
                SwitchListTile(
                  key: const ValueKey('transfer-move'),
                  contentPadding: EdgeInsets.zero,
                  value: d.move,
                  onChanged: (value) => setState(() => d.move = value),
                  title: const Text(
                    'Atualizar o clube atual',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    d.type == 'release'
                        ? 'O jogador fica sem clube.'
                        : 'O jogador passa a aparecer no elenco de destino.',
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _error!,
                    style: TextStyle(color: c.danger, fontSize: 12.5),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('transfer-save'),
                onPressed: _save,
                child: const Text('Salvar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayerTransfersTab extends StatefulWidget {
  const PlayerTransfersTab({
    super.key,
    required this.person,
    required this.playerId,
    required this.repository,
    required this.currentClub,
    required this.currency,
    required this.ensurePlayer,
    required this.onChanged,
    this.ownSquad = false,
  });
  final Person person;
  final String playerId;
  final OtherPlayersRepository repository;
  final CatalogItem? currentClub;
  final String currency;

  final Future<String> Function() ensurePlayer;
  final VoidCallback onChanged;

  final bool ownSquad;
  @override
  State<PlayerTransfersTab> createState() => _PlayerTransfersTabState();
}

class _PlayerTransfersTabState extends State<PlayerTransfersTab> {
  late Future<List<PlayerTransferEntry>> _entries = _load();

  Future<List<PlayerTransferEntry>> _load() =>
      widget.repository.transfers(widget.person, widget.playerId);

  @override
  void didUpdateWidget(PlayerTransfersTab old) {
    super.didUpdateWidget(old);
    if (old.playerId != widget.playerId) _entries = _load();
  }

  CatalogItem? _club(String? id, String? leagueId) => id == null || id.isEmpty
      ? null
      : GameCatalog.current?.team(
              widget.person.fifaVersion,
              id,
              leagueId: leagueId,
            ) ??
            CatalogItem(id, 'Clube não informado', leagueId: leagueId);

  Future<void> _edit([PlayerTransferEntry? entry]) async {
    final date = await widget.repository.sql.getCareerDate(widget.person.id);
    if (!mounted) return;
    final draft = await showWorldTransferSheet(
      context,
      person: widget.person,
      currency: widget.currency,
      editing: entry != null,
      canMove: !widget.ownSquad,
      draft: entry == null
          ? WorldTransferDraft(
              date: date ?? DateTime.now(),
              type: 'transfer',
              from: widget.currentClub,
              move: !widget.ownSquad,
            )
          : WorldTransferDraft(
              date: entry.date,
              type: entry.type,
              from: _club(entry.fromTeamId, entry.fromLeagueId),
              to: _club(entry.toTeamId, entry.toLeagueId),
              value: entry.value,
            ),
    );
    if (draft == null) return;
    final playerId = await widget.ensurePlayer();
    await widget.repository.saveTransfer(
      widget.person,
      playerId,
      id: entry?.id,
      date: draft.date,
      type: draft.type,
      from: draft.from,
      to: draft.to,
      value: draft.value,
      move: draft.move,
    );
    if (!mounted) return;
    setState(
      () => _entries = widget.repository.transfers(widget.person, playerId),
    );
    widget.onChanged();
  }

  Future<void> _delete(PlayerTransferEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir transferência?'),
        content: const Text(
          'O registro sai do histórico. O clube atual do jogador não muda.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deleteTransfer(widget.person, entry.id);
    if (mounted) setState(() => _entries = _load());
  }

  String _money(int value) =>
      '${NumberFormat.decimalPattern('pt_BR').format(value)} ${widget.currency}';

  Widget _entry(PlayerTransferEntry e, bool last) {
    final c = AppColors.of(context);
    final style = TextStyle(
      color: c.text,
      fontSize: 13,
      fontWeight: FontWeight.w700,
    );
    return IntrinsicHeight(
      child: Row(
        key: ValueKey('transfer-entry/${e.id}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 14,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: e.source == 'club' ? c.accent : c.muted,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.only(top: 4),
                      color: c.line,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.date.year <= 1
                        ? 'Data não informada'
                        : DateFormat('dd/MM/yyyy').format(e.date),
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ClubLine(
                        version: widget.person.fifaVersion,
                        club: _club(e.fromTeamId, e.fromLeagueId),
                        size: 18,
                        style: style,
                      ),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 15,
                        color: c.muted,
                      ),
                      ClubLine(
                        version: widget.person.fifaVersion,
                        club: _club(e.toTeamId, e.toLeagueId),
                        size: 18,
                        style: style,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        [
                          transferEntryLabel(e),
                          if (e.value != null && e.value! > 0) _money(e.value!),
                        ].join(' · '),
                        style: TextStyle(color: c.muted, fontSize: 12),
                      ),
                      SourceTag(switch (e.source) {
                        'club' => 'Seu clube',
                        'api' => 'API',
                        _ => 'Manual',
                      }),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (e.editable)
            PopupMenuButton<String>(
              tooltip: 'Opções da transferência',
              icon: Icon(Icons.more_vert_rounded, size: 20, color: c.muted),
              onSelected: (action) => action == 'edit' ? _edit(e) : _delete(e),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(value: 'delete', child: Text('Excluir')),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return FutureBuilder<List<PlayerTransferEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <PlayerTransferEntry>[];
        return PlayerProfileScroll(
          key: const PageStorageKey('player-transfers'),
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            ProfilePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Histórico de transferências',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.ownSquad
                        ? 'Inclui as transferências do seu clube. Registre aqui a carreira anterior do jogador.'
                        : 'Mudanças de clube feitas à mão, vistas nas importações da API ou registradas pelo seu clube.',
                    style: TextStyle(color: c.muted, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  if (snapshot.connectionState != ConnectionState.done)
                    const Center(child: CircularProgressIndicator())
                  else if (entries.isEmpty)
                    Text(
                      'Nenhuma transferência registrada.',
                      style: TextStyle(color: c.muted, fontSize: 13),
                    )
                  else
                    for (final (i, e) in entries.indexed)
                      _entry(e, i == entries.length - 1),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    key: const ValueKey('transfer-add'),
                    onPressed: _edit,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Registrar transferência', maxLines: 1),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
