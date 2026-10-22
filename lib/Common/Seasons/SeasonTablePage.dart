import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/Person.dart';
import '../../models/SeasonReview.dart';
import '../../utils/Components/CareerPageWidgets.dart';
import '../../utils/Components/CareerUiStyle.dart';
import '../../utils/Components/TeamLogo.dart';
import '../../utils/GameCatalog.dart';
import '../SelectTeam/SelectTeamPage.dart';

class SeasonTablePage extends StatefulWidget {
  const SeasonTablePage({
    super.key,
    required this.person,
    required this.table,
    required this.ownTeamId,
    required this.onSave,
  });
  final Person person;
  final SeasonFinalTable table;
  final String ownTeamId;
  final Future<void> Function(SeasonFinalTable) onSave;
  @override
  State<SeasonTablePage> createState() => _SeasonTablePageState();
}

class _SeasonTablePageState extends State<SeasonTablePage> {
  late final List<SeasonStanding> _rows = [...widget.table.rows];
  late bool _full = _rows.length > 1;
  bool _saving = false;
  bool _reviewOrder = false;
  String? _error;

  void _renumber() {
    final ordered = [
      for (final (i, r) in _rows.indexed)
        SeasonStanding(
          teamId: r.teamId,
          name: r.name,
          leagueId: r.leagueId,
          position: i + 1,
          stats: r.stats,
        ),
    ];
    _rows
      ..clear()
      ..addAll(ordered);
  }

  Future<void> _addLeague() async {
    final catalog = await GameCatalog.load();
    if (!mounted) return;
    final leagueId =
        _rows
            .where((r) => r.teamId == widget.ownTeamId)
            .firstOrNull
            ?.leagueId ??
        catalog.team(widget.person.fifaVersion, widget.ownTeamId)?.leagueId ??
        widget.person.leagueId;
    final clubs =
        catalog
            .teams(widget.person.fifaVersion)
            .where(
              (t) =>
                  t.leagueId == leagueId && !_rows.any((r) => r.teamId == t.id),
            )
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));
    if (clubs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum outro clube desta liga. Use Adicionar clube.'),
        ),
      );
      return;
    }
    final selected = clubs.map((t) => t.id).toSet();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Clubes da liga'),
          content: SizedBox(
            width: 340,
            height: 380,
            child: ListView(
              children: [
                const Text(
                  'Selecione os participantes. Depois, organize a classificação final.',
                ),
                const SizedBox(height: 12),
                for (final club in clubs)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      club.label,
                      style: const TextStyle(fontSize: 13),
                    ),
                    value: selected.contains(club.id),
                    onChanged: (v) => update(() {
                      if (v == true) {
                        selected.add(club.id);
                      } else {
                        selected.remove(club.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Adicionar selecionados'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted || selected.isEmpty) return;
    setState(() {
      final ownIndex = _rows.indexWhere((r) => r.teamId == widget.ownTeamId);
      final ownPosition = _rows[ownIndex].position;
      _rows.addAll(
        clubs
            .where((t) => selected.contains(t.id))
            .map(
              (t) => SeasonStanding(
                teamId: t.id,
                name: t.label,
                leagueId: t.leagueId,
                position: 0,
              ),
            ),
      );
      if (ownPosition > 1 && ownPosition <= _rows.length) {
        final own = _rows.removeAt(ownIndex);
        _rows.insert(ownPosition - 1, own);
      }
      _renumber();
      _reviewOrder = true;
    });
  }

  Widget _club(SeasonStanding row, int index) => Card(
    key: ValueKey(row.teamId),
    child: ListTile(
      leading: CareerIconBadge(
        icon: row.teamId == widget.ownTeamId
            ? Icons.shield_outlined
            : Icons.groups_outlined,
      ),
      title: Text(
        row.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${row.position > 0 ? '${row.position}º lugar' : 'Informe a posição final'} · ${row.stats['points'] ?? '—'} PTS',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (row.teamId != widget.ownTeamId)
            IconButton(
              tooltip: 'Retirar clube',
              onPressed: _saving
                  ? null
                  : () => setState(() => _rows.remove(row)),
              icon: const Icon(Icons.close, size: 18),
            ),
          if (_full)
            ReorderableDragStartListener(
              index: index,
              enabled: !_saving,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_indicator, size: 20),
              ),
            )
          else
            const Icon(Icons.edit_outlined, size: 19),
        ],
      ),
      onTap: _saving ? null : () => _edit(row),
    ),
  );

  Future<void> _edit(SeasonStanding row) async {
    final updated = await showModalBottomSheet<SeasonStanding>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _StandingEditor(row: row),
    );
    if (updated != null && mounted) {
      setState(() {
        _rows[_rows.indexOf(row)] = updated;
        _rows.sort((a, b) => a.position.compareTo(b.position));
        _error = null;
      });
    }
  }

  Future<void> _add() async {
    final club = await Navigator.push<CatalogItem>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectTeamPage(fifaVersion: widget.person.fifaVersion),
      ),
    );
    if (club == null || !mounted) return;
    if (_rows.any((r) => r.teamId == club.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este clube já está na tabela.')),
      );
      return;
    }
    final row = SeasonStanding(
      teamId: club.id,
      name: club.label,
      leagueId: club.leagueId,
      position: 0,
    );
    final edited = await showModalBottomSheet<SeasonStanding>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _StandingEditor(row: row),
    );
    if (edited != null && mounted) {
      setState(() {
        _full = true;
        _rows.add(edited);
        _rows.sort((a, b) => a.position.compareTo(b.position));
      });
    }
  }

  Future<void> _save() async {
    if (_reviewOrder) {
      setState(
        () => _error = 'Confira a ordem em Mais clubes e marque a confirmação antes de salvar.',
      );
      return;
    }
    final table = SeasonFinalTable(
      id: widget.table.id,
      tournamentId: widget.table.tournamentId,
      name: widget.table.name,
      ownTeamId: widget.table.ownTeamId ?? widget.ownTeamId,
      rows: [..._rows],
      closedAt: DateTime.now(),
    );
    try {
      table.validate();
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(table);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Não foi possível salvar a tabela. $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    final visible = _rows
        .where((r) => _full || r.teamId == widget.ownTeamId)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Fechar tabela')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          CareerPageHeader(
            title: widget.table.name,
            subtitle: 'Registre a classificação final. Você pode preencher só seu time ou incluir os outros clubes.',
            icon: Icons.table_chart_outlined,
            eyebrow: 'O resultado da campanha',
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Meu time'),
                icon: Icon(Icons.shield_outlined),
              ),
              ButtonSegment(
                value: true,
                label: Text('Mais clubes'),
                icon: Icon(Icons.format_list_numbered),
              ),
            ],
            selected: {_full},
            onSelectionChanged: _saving
                ? null
                : (s) => setState(() => _full = s.single),
          ),
          const SizedBox(height: 18),
          Text(
            'Toque em um clube para informar posição, pontos e estatísticas. Campos vazios ficam sem informação.',
            style: TextStyle(color: c.muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 14),
          if (_full) ...[
            Text(
              'Arraste pela alça para ordenar os clubes. As posições serão numeradas pela ordem da lista.',
              style: TextStyle(color: c.muted, fontSize: 11, height: 1.5),
            ),
            const SizedBox(height: 10),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (oldIndex, newIndex) => setState(() {
                final moved = _rows.removeAt(oldIndex);
                _rows.insert(newIndex, moved);
                _renumber();
                _reviewOrder = true;
              }),
              children: [for (final (i, row) in visible.indexed) _club(row, i)],
            ),
            if (_reviewOrder)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: false,
                title: const Text(
                  'Conferi a classificação final',
                  style: TextStyle(fontSize: 12),
                ),
                subtitle: const Text(
                  'A lista inicial de clubes não representa a classificação real.',
                ),
                onChanged: _saving
                    ? null
                    : (_) => setState(() => _reviewOrder = false),
              ),
          ] else
            for (final row in visible) _club(row, 0),
          if (_full)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _add,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar clube'),
              ),
            ),
          if (_full)
            OutlinedButton.icon(
              onPressed: _saving ? null : _addLeague,
              icon: const Icon(Icons.playlist_add),
              label: const Text('Adicionar clubes da liga'),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!, style: TextStyle(color: c.red)),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(_saving ? 'Salvando…' : 'Salvar tabela final'),
          ),
          const SizedBox(height: 12),
          Text(
            'A tabela pode ser corrigida depois. Se a temporada já estiver encerrada, sua retrospectiva será atualizada.',
            style: TextStyle(color: c.muted, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _StandingEditor extends StatefulWidget {
  const _StandingEditor({required this.row});
  final SeasonStanding row;
  @override
  State<_StandingEditor> createState() => _StandingEditorState();
}

class _StandingEditorState extends State<_StandingEditor> {
  final _form = GlobalKey<FormState>();
  late final _position = TextEditingController(
    text: widget.row.position > 0 ? '${widget.row.position}' : '',
  );
  late final _stats = {
    for (final k in standingStats.keys)
      k: TextEditingController(text: widget.row.stats[k]?.toString() ?? ''),
  };
  @override
  void dispose() {
    _position.dispose();
    for (final c in _stats.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const labels = {
      'points': 'Pontos',
      'matchesPlayed': 'Jogos',
      'wins': 'Vitórias',
      'draws': 'Empates',
      'loses': 'Derrotas',
      'goalsFor': 'Gols pró',
      'goalsAgainst': 'Gols contra',
    };
    Widget input(
      TextEditingController controller,
      String label, {
      bool required = false,
    }) => TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        hintText: required ? 'Ex.: 3' : 'Opcional',
      ),
      validator: (v) => required && (int.tryParse(v ?? '') ?? 0) < 1
          ? 'Informe a posição'
          : null,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        24,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.row.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('Dados finais da competição'),
              const SizedBox(height: 22),
              input(_position, 'Posição final', required: true),
              const SizedBox(height: 16),
              for (final pair in [
                ['points', 'matchesPlayed'],
                ['wins', 'draws'],
                ['loses', 'goalsFor'],
              ]) ...[
                Row(
                  children: [
                    Expanded(child: input(_stats[pair[0]]!, labels[pair[0]]!)),
                    const SizedBox(width: 12),
                    Expanded(child: input(_stats[pair[1]]!, labels[pair[1]]!)),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              input(_stats['goalsAgainst']!, labels['goalsAgainst']!),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (!_form.currentState!.validate()) return;
                    Navigator.pop(
                      context,
                      SeasonStanding(
                        teamId: widget.row.teamId,
                        name: widget.row.name,
                        leagueId: widget.row.leagueId,
                        position: int.parse(_position.text),
                        stats: {
                          for (final e in _stats.entries)
                            e.key: int.tryParse(e.value.text),
                        },
                      ),
                    );
                  },
                  child: const Text('Aplicar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SeasonStandingsCard extends StatelessWidget {
  const SeasonStandingsCard({
    super.key,
    required this.table,
    required this.ownTeamId,
    required this.version,
    this.onEdit,
  });
  final SeasonFinalTable table;
  final String ownTeamId, version;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    final rows = [...table.rows]
      ..sort((a, b) => a.position.compareTo(b.position));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    table.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    tooltip: 'Editar tabela',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
              ],
            ),
            Text(
              '${table.isClosed ? 'Tabela final' : 'Tabela importada'} · ${rows.length == 1 ? 'Posição do seu time' : '${rows.length} clubes registrados'}',
              style: TextStyle(color: c.muted, fontSize: 11),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 32,
                dataRowMinHeight: 48,
                dataRowMaxHeight: 56,
                columnSpacing: 18,
                horizontalMargin: 6,
                columns: [
                  const DataColumn(label: Text('#')),
                  const DataColumn(label: Text('Clube')),
                  for (final label in standingStats.values)
                    DataColumn(label: Text(label), numeric: true),
                  const DataColumn(label: Text('SG'), numeric: true),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      color: WidgetStatePropertyAll(
                        row.teamId == ownTeamId
                            ? c.accent.withValues(alpha: .08)
                            : null,
                      ),
                      cells: [
                        DataCell(Text('${row.position}')),
                        DataCell(
                          Row(
                            children: [
                              TeamLogo.lookup(
                                teamId: row.teamId,
                                fifaVersion: version,
                                leagueId: row.leagueId,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 125,
                                child: Text(
                                  row.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: row.teamId == ownTeamId
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final key in standingStats.keys)
                          DataCell(Text('${row.stats[key] ?? '—'}')),
                        DataCell(Text('${row.balance ?? '—'}')),
                      ],
                    ),
                ],
              ),
            ),
            if (rows.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Deslize para ver todas as estatísticas →',
                  style: TextStyle(color: c.muted, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
