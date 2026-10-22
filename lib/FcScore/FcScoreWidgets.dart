import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

import '../utils/Components/CareerUiStyle.dart';
import '../utils/GameCatalog.dart';
import '../utils/PlayerClubLookup.dart';
import '../utils/Components/PlayerSearchCard.dart';
import 'FcScoreApi.dart';
import 'FcScoreModels.dart';
import 'FcScorePlayerCreation.dart';
import 'FcScoreSeasonStats.dart';
import 'FcScoreClubMappingWidgets.dart';

String fcMoney(Object? value) => fcNumber(value) == null
    ? '—'
    : NumberFormat.decimalPattern('pt_BR').format(fcNumber(value));
String fcValue(Object? value) => value == null ? '—' : '$value';
String fcDay(Object? value) {
  final date = DateTime.tryParse(fcId(value));
  return date == null
      ? 'Data não informada'
      : DateFormat('dd/MM/yyyy').format(date);
}

class FcPanel extends StatelessWidget {
  const FcPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: CareerUiColors(context).panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: CareerUiColors(context).line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    ),
  );
}

class FcSection extends StatelessWidget {
  const FcSection(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: TextStyle(
              color: CareerUiColors(context).muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ],
    ),
  );
}

class FcFact extends StatelessWidget {
  const FcFact(this.label, this.value, {super.key});
  final String label;
  final Object? value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: CareerUiColors(context).muted),
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            fcValue(value),
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class FcSeasonStatistics extends StatelessWidget {
  const FcSeasonStatistics({super.key, required this.stats});
  final FcJson stats;
  List<Widget> _facts(FcJson record) => [
    for (final key in fcStatLabels.keys)
      if (record[key] != null)
        FcFact(
          fcStatLabels[key]!.replaceAll(' (goleiros)', ''),
          key == 'averageRating'
              ? fcNumber(record[key])?.toStringAsFixed(2)
              : record[key],
        ),
  ];
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const FcSection('Estatísticas da temporada'),
      ..._facts(fcObject(stats['totals'])),
      for (final c in fcList(stats['competitions'])) ...[
        const SizedBox(height: 16),
        FcSection(
          fcName(fcObject(c['competition'])['name']),
          subtitle: fcName(fcObject(c['team'])['name']),
        ),
        ..._facts(c),
        if (fcList(c['recentMatches']).isNotEmpty) ...[
          const FcSection('Últimos jogos'),
          for (final m in fcList(c['recentMatches']))
            FcFact(
              fcDay(m['date']),
              '${fcValue(m['minutes'])} min · ${fcValue(m['goals'])} gols · nota ${fcNumber(m['rating'])?.toStringAsFixed(1) ?? '—'}',
            ),
        ],
      ],
    ],
  );
}

class FcNotice extends StatelessWidget {
  const FcNotice(this.text, {super.key, this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.error_outline : Icons.info_outline,
          size: 20,
          color: error
              ? CareerUiColors(context).red
              : CareerUiColors(context).accent,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: error
                  ? CareerUiColors(context).red
                  : CareerUiColors(context).muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
}

class FcChoice extends StatelessWidget {
  const FcChoice({
    super.key,
    required this.title,
    required this.value,
    required this.onTap,
    this.icon = Icons.link,
    this.leading,
  });
  final String title, value;
  final VoidCallback? onTap;
  final IconData icon;
  final Widget? leading;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: CareerUiColors(context).panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: CareerUiColors(context).line),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: leading ?? Icon(icon, color: CareerUiColors(context).accent),
        title: Text(title, style: const TextStyle(fontSize: 12)),
        subtitle: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
      ),
    ),
  );
}

InputDecoration fcInput(String label, {IconData? icon, String? hint}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    );

String fcChoiceLabel(String? id, List<CatalogItem> items) {
  if (fcIsPlayerDraft(id)) {
    try {
      final draft = fcPlayerDraft(id!), profile = fcObject(draft['profile']);
      return 'Criar: ${fcPlayerName(profile)} · OVR ${profile['overall']}';
    } on FcScoreException {
      return 'Revisar dados do novo jogador';
    }
  }
  return id == null
      ? 'Escolher vínculo'
      : id == 'new'
      ? 'Criar jogador com os dados da API'
      : id.startsWith('new:')
      ? 'Criar: ${id.substring(4)}'
      : items.where((i) => i.id == id).firstOrNull?.label ?? 'Revisar cadastro';
}

Future<String?> fcCreatePlayerHere(
  BuildContext context, {
  required FcJson source,
  String? choice,
  bool generate = false,
}) => showModalBottomSheet<String>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (_) =>
      _FcPlayerCreator(source: source, choice: choice, generate: generate),
);

Future<String?> fcPick(
  BuildContext context, {
  required String title,
  required List<CatalogItem> items,
  String? createName,
  bool newPlayer = false,
  FcJson? playerSource,
  String? playerChoice,
  List<CatalogItem>? clubLeagues,
  String? selectedId,
  String? preferredLeagueId,
  String? playerVersion,
  Map<String, Map<String, Object?>> playerRows = const {},
  PlayerClubLookup? playerClubs,
  CatalogItem? playerClub,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _FcPicker(
    title: title,
    items: items,
    createName: createName,
    newPlayer: playerSource == null
        ? newPlayer
        : fcCanCreatePlayer(playerSource),
    playerSource: playerSource,
    playerChoice: playerChoice,
    clubLeagues: clubLeagues,
    selectedId: selectedId,
    preferredLeagueId: preferredLeagueId,
    playerVersion: playerVersion,
    playerRows: playerRows,
    playerClubs: playerClubs,
    playerClub: playerClub,
  ),
);

class _FcPicker extends StatefulWidget {
  const _FcPicker({
    required this.title,
    required this.items,
    this.createName,
    required this.newPlayer,
    this.playerSource,
    this.playerChoice,
    this.clubLeagues,
    this.selectedId,
    this.preferredLeagueId,
    this.playerVersion,
    this.playerRows = const {},
    this.playerClubs,
    this.playerClub,
  });
  final String title;
  final List<CatalogItem> items;
  final String? createName;
  final bool newPlayer;
  final FcJson? playerSource;
  final String? playerChoice;
  final List<CatalogItem>? clubLeagues;
  final String? selectedId, preferredLeagueId;
  final String? playerVersion;
  final Map<String, Map<String, Object?>> playerRows;
  final PlayerClubLookup? playerClubs;
  final CatalogItem? playerClub;
  @override
  State<_FcPicker> createState() => _FcPickerState();
}

class _FcPickerState extends State<_FcPicker> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (widget.newPlayer) {
      Navigator.pop(context, 'new');
      return;
    }
    var newName = widget.createName ?? '';
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nome no aplicativo'),
        content: TextFormField(
          initialValue: newName,
          onChanged: (value) => newName = value,
          autofocus: true,
          decoration: fcInput('Nome'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (newName.trim().isNotEmpty) {
                Navigator.pop(ctx, newName.trim());
              }
            },
            child: const Text('Usar este nome'),
          ),
        ],
      ),
    );
    if (name != null && mounted) Navigator.pop(context, 'new:$name');
  }

  Future<void> _createPlayer(bool generate) async {
    FocusScope.of(context).unfocus();
    final choice = await fcCreatePlayerHere(
      context,
      source: widget.playerSource!,
      choice: widget.playerChoice,
      generate: generate,
    );
    if (choice != null && mounted) Navigator.pop(context, choice);
  }

  Widget _creationOptions() => Column(
    children: [
      if (widget.playerSource != null) ...[
        ListTile(
          key: const Key('fc-player-create-here'),
          leading: const Icon(Icons.person_add_alt_1_outlined),
          title: const Text('Criar jogador aqui'),
          subtitle: const Text('Preencher ou ajustar os dados nesta tela'),
          onTap: () => _createPlayer(false),
        ),
        ListTile(
          key: const Key('fc-player-generate'),
          leading: const Icon(Icons.shuffle_rounded),
          title: const Text('Gerar aleatório'),
          subtitle: const Text('Preencher o que falta e revisar antes de usar'),
          onTap: () => _createPlayer(true),
        ),
      ],
      if (widget.createName != null || widget.newPlayer)
        ListTile(
          leading: const Icon(Icons.add_circle_outline),
          title: Text(
            widget.newPlayer
                ? 'Criar com os dados da API'
                : 'Criar novo cadastro',
          ),
          subtitle: widget.createName == null ? null : Text(widget.createName!),
          onTap: _create,
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final query = fcNormalize(_search.text);
    final filtered = widget.items
        .where((i) => fcNormalize(i.label).contains(query))
        .toList();
    final preferredLeague =
        widget.items
            .where((i) => i.id == widget.selectedId)
            .firstOrNull
            ?.leagueId ??
        widget.preferredLeagueId;
    final clubGroups =
        widget.clubLeagues == null
              ? <FcClubLeagueGroup<CatalogItem>>[]
              : [
                  for (final group in fcGroupClubs(
                    widget.items,
                    widget.clubLeagues!,
                  ))
                    FcClubLeagueGroup(
                      group.id,
                      group.label,
                      group.rows
                          .where(
                            (t) =>
                                fcNormalize(t.label).contains(query) ||
                                fcNormalize(group.label).contains(query),
                          )
                          .toList(),
                    ),
                ].where((g) => g.rows.isNotEmpty).toList()
          ..sort(
            (a, b) => a.id == b.id
                ? 0
                : a.id == preferredLeague
                ? -1
                : b.id == preferredLeague
                ? 1
                : fcNormalize(a.label).compareTo(fcNormalize(b.label)),
          );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height:
            (MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom -
                80) *
            .68,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FcSection(widget.title),
            TextField(
              key: const Key('fc-picker-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: fcInput('Buscar', icon: Icons.search),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: widget.clubLeagues != null
                  ? FcClubLeagueList<CatalogItem>(
                      groups: clubGroups,
                      keyPrefix: 'fc-picker',
                      query: query,
                      preferredGroupId: preferredLeague,
                      prefix: _creationOptions(),
                      rowBuilder: (context, item) => ListTile(
                        key: ValueKey('fc-picker-club-${item.id}'),
                        leading: FcClubLogo(item: item),
                        title: Text(item.label),
                        subtitle: item.isCustom || item.customizationId != null
                            ? const Text('Personalizado')
                            : null,
                        trailing: item.id == widget.selectedId
                            ? Icon(
                                Icons.check_circle,
                                color: CareerUiColors(context).accent,
                              )
                            : null,
                        onTap: () => Navigator.pop(context, item.id),
                      ),
                    )
                  : CustomScrollView(
                      key: const Key('fc-picker-list'),
                      slivers: [
                        SliverToBoxAdapter(child: _creationOptions()),
                        if (filtered.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(child: Text('Nenhum resultado')),
                          )
                        else
                          SliverList.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, i) =>
                                widget.playerVersion != null
                                ? PlayerSearchCard.fromRow(
                                    key: ValueKey(
                                      'fc-picker-player-${filtered[i].id}',
                                    ),
                                    player:
                                        widget.playerRows[filtered[i].id] ??
                                        const {},
                                    name: filtered[i].label,
                                    version: widget.playerVersion!,
                                    club:
                                        widget.playerClubs?.club(
                                          playerId: filtered[i].id,
                                          realPlayerId: widget
                                              .playerRows[filtered[i]
                                                  .id]?['realPlayerId']
                                              ?.toString(),
                                        ) ??
                                        widget.playerClub,
                                    onTap: () =>
                                        Navigator.pop(context, filtered[i].id),
                                  )
                                : ListTile(
                                    title: Text(filtered[i].label),
                                    onTap: () =>
                                        Navigator.pop(context, filtered[i].id),
                                  ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FcPlayerCreator extends StatefulWidget {
  const _FcPlayerCreator({
    required this.source,
    required this.choice,
    required this.generate,
  });
  final FcJson source;
  final String? choice;
  final bool generate;
  @override
  State<_FcPlayerCreator> createState() => _FcPlayerCreatorState();
}

class _FcPlayerCreatorState extends State<_FcPlayerCreator> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _overall = TextEditingController(),
      _potential = TextEditingController();
  late FcJson _profile;
  late String _position;
  bool _generated = false;
  bool _overallEdited = false,
      _potentialEdited = false,
      _positionEdited = false;

  @override
  void initState() {
    super.initState();
    try {
      _profile = fcPlayerWithChoice(widget.source, widget.choice);
    } on FcScoreException {
      _profile = widget.source;
    }
    _generated = widget.generate;
    if (widget.generate) _profile = fcGeneratePlayerProfile(_profile);
    _fill();
  }

  void _fill() {
    _name.text = fcName(_profile['name'], '').trim();
    _overall.text = fcValidPlayerRating(_profile['overall'])
        ? '${fcInt(_profile['overall'])}'
        : '65';
    _potential.text = fcValidPlayerRating(_profile['potential'])
        ? '${fcInt(_profile['potential'])}'
        : _overall.text;
    final positions = _profile['positions'] is List
        ? _profile['positions'] as List
        : const [];
    _position = fcPositions.take(28).contains(positions.firstOrNull)
        ? '${positions.first}'
        : 'ST';
  }

  void _generate() {
    final base = {..._profile};
    if (_name.text.trim().isNotEmpty) base['name'] = _name.text.trim();
    if (_overallEdited) base['overall'] = int.tryParse(_overall.text);
    if (_potentialEdited) base['potential'] = int.tryParse(_potential.text);
    if (_positionEdited) base['positions'] = [_position];
    setState(() {
      _profile = fcGeneratePlayerProfile(base);
      _generated = true;
      _fill();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _overall.dispose();
    _potential.dispose();
    super.dispose();
  }

  void _use() {
    if (!_form.currentState!.validate()) return;
    final choice = fcCreatePlayerChoice(widget.source, {
      ..._profile,
      'name': _name.text.trim(),
      'overall': int.parse(_overall.text),
      'potential': int.parse(_potential.text),
      'positions': [_position],
    }, generated: _generated);
    FocusScope.of(context).unfocus();
    Navigator.pop(context, choice);
  }

  String? _ratingError(String? value) =>
      fcValidPlayerRating(value) ? null : 'Use um valor de 1 a 99';

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + inset),
      child: SizedBox(
        height: (MediaQuery.sizeOf(context).height - inset - 80) * .85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Criar jogador aqui',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Form(
                key: _form,
                child: ListView(
                  key: const Key('fc-create-fields'),
                  children: [
                    FcNotice(
                      _generated
                          ? 'Os dados faltantes foram gerados. Confira ou ajuste antes de usar.'
                          : 'Complete os dados do jogador sem sair da importação.',
                    ),
                    TextFormField(
                      key: const Key('fc-create-name'),
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: fcInput('Nome do jogador'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Informe o nome'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: const Key('fc-create-position'),
                      initialValue: _position,
                      isExpanded: true,
                      decoration: fcInput('Posição'),
                      items: [
                        for (var i = 0; i < 28; i++)
                          DropdownMenuItem(
                            value: fcPositions[i],
                            child: Text(
                              GameCatalog.current?.positions
                                      .where((p) => p.id == '$i')
                                      .firstOrNull
                                      ?.label ??
                                  fcPositions[i],
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          _position = value;
                          _positionEdited = true;
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('fc-create-overall'),
                      controller: _overall,
                      onChanged: (_) => _overallEdited = true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: fcInput('Overall'),
                      validator: _ratingError,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('fc-create-potential'),
                      controller: _potential,
                      onChanged: (_) => _potentialEdited = true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: fcInput('Potencial'),
                      validator: _ratingError,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _generate,
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Gerar dados faltantes'),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _use, child: const Text('Usar jogador')),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
