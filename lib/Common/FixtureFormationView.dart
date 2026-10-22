import '../utils/AppColors.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/FixtureFormation.dart';
import '../models/ManagerFixturePlayerPerformance.dart';
import '../models/Person.dart';
import '../utils/Components/CareerUiStyle.dart';
import '../utils/Components/FootballPitch.dart';
import '../utils/Components/FixturePitchPlayer.dart';
import '../utils/Components/PlayerAvatar.dart';
import '../utils/FootballFormations.dart';
import '../utils/databaseUtils.dart';
import 'MatchUi.dart';
import 'PitchPlayerMenu.dart';

class FixtureFormationView extends StatefulWidget {
  const FixtureFormationView({
    super.key,
    required this.person,
    required this.available,
    required this.performances,
    required this.header,
    this.onSave,
    this.editable = false,
    this.embedded = false,
    this.playerActionLabel = 'Ver jogador',
    this.saved,
    this.onPlayerTap,
    this.onPlayerAction,
    this.canViewPlayer,
    this.captainIds = const {},
  });
  final Person person;
  final Set<String> captainIds;
  final FixtureFormation available;
  final FixtureFormation? saved;
  final List<ManagerFixturePlayerPerformance> performances;
  final Widget header;
  final Future<void> Function(FixtureFormation)? onSave;
  final bool editable, embedded;
  final String playerActionLabel;
  final ValueChanged<String>? onPlayerTap;
  final Future<void> Function(String id, String event)? onPlayerAction;
  final bool Function(String)? canViewPlayer;
  @override
  State<FixtureFormationView> createState() => _FixtureFormationViewState();
}

class _FixtureFormationViewState extends State<FixtureFormationView>
    with AutomaticKeepAliveClientMixin {
  late FixtureFormation _formation = _merged(widget.saved ?? widget.available);
  bool _saving = false;
  FixtureFormation _merged(FixtureFormation value) {
    final players = {
      ...widget.available.players,
      for (final e in value.players.entries)
        e.key: {
          ...?widget.available.players[e.key],
          ...e.value,
          if (!hasFootballIdentity(e.value) || e.value['name'] == e.key)
            'name': widget.available.players[e.key]?['name'],
        },
    };
    final named = widget.editable
        ? players
        : {
            for (final e in players.entries)
              if (hasFootballIdentity(e.value) && e.value['name'] != e.key)
                e.key: e.value,
          };
    final merged = value.copy(
      players: named,
      starters: {
        for (final e in value.starters.entries)
          if (named.containsKey(e.key)) e.key: e.value,
      },
      bench: value.bench.where(named.containsKey).toList(),
    );
    if (widget.performances.isNotEmpty || widget.available.starters.isEmpty) {
      return merged.reconciledWith(
        widget.available.copy(
          players: named,
          starters: {
            for (final e in widget.available.starters.entries)
              if (named.containsKey(e.key)) e.key: e.value,
          },
          bench: widget.available.bench.where(named.containsKey).toList(),
        ),
      );
    }
    return value.layoutSource == 'squad' &&
            value.formation == widget.available.formation
        ? merged.withPreservedSlots(widget.available.starters)
        : merged;
  }

  Map<String, ManagerFixturePlayerPerformance> get _performances => {
    for (final p in widget.performances) p.playerInstanceId: p,
  };
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    if (widget.editable && widget.saved == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _save(_formation);
      });
    }
  }

  @override
  void didUpdateWidget(covariant FixtureFormationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _formation = _merged(widget.saved ?? _formation);
  }

  Future<void> _save(FixtureFormation next) async {
    if (_saving || !widget.editable) return;
    final before = _formation;
    setState(() {
      _formation = next;
      _saving = true;
    });
    try {
      await widget.onSave?.call(next);
    } catch (error) {
      if (mounted) {
        setState(() => _formation = before);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível salvar a formação. Tente novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _name(String id) => '${_formation.players[id]?['name'] ?? id}';
  String? _position(String id) =>
      _formation.players[id]?['positionId'] as String?;
  Future<void> _chooseFormation() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SizedBox(
              height:
                  (MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom) *
                  .76,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                child: Column(
                  children: [
                    const Text(
                      'Escolher formação',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      autocorrect: false,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Buscar formação',
                      ),
                      onChanged: (value) => setSheetState(
                        () => query = value.trim().toLowerCase(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final name in footballFormations.keys.where(
                            (name) => name.toLowerCase().contains(query),
                          ))
                            ListTile(
                              title: Text(name),
                              leading: const Icon(Icons.sports_soccer_rounded),
                              trailing: name == _formation.formation
                                  ? const Icon(Icons.check_circle_rounded)
                                  : null,
                              onTap: () => Navigator.pop(context, name),
                            ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey('custom-formation'),
                      onPressed: () => Navigator.pop(context, 'custom'),
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('Montar outra formação'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (!mounted || selected == null) return;
    if (selected == 'custom') {
      await _customFormation();
    } else {
      await _save(_formation.withFormation(selected));
    }
  }

  Future<void> _customFormation() async {
    final controller = TextEditingController(
          text: _formation.formation.split(' ').first,
        ),
        form = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Formação personalizada'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Digite as linhas da defesa para o ataque, somando 10 jogadores. O goleiro é incluído.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Ex.: 4-2-3-1'),
                validator: (value) =>
                    customFootballFormation(value ?? '') == null
                    ? 'As linhas precisam somar 10 jogadores.'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(
                  context,
                  controller.text
                      .trim()
                      .replaceAll('–', '-')
                      .replaceAll(' ', ''),
                );
              }
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (mounted && result != null) {
      await _save(_formation.withFormation(result));
    }
  }

  Future<List<String>?> _choosePlayers({
    required bool multiple,
    bool onlyReserves = false,
  }) async {
    final selected = _formation.bench.toSet();
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final ids =
                _formation.players.keys
                    .where(
                      (id) =>
                          !(multiple || onlyReserves) ||
                          !_formation.starters.containsKey(id),
                    )
                    .where((id) => _name(id).toLowerCase().contains(query))
                    .toList()
                  ..sort((a, b) {
                    final rank = footballPositionRank(_position(a))
                        .compareTo(footballPositionRank(_position(b)));
                    return rank != 0 ? rank : _name(a).compareTo(_name(b));
                  });
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                height:
                    (MediaQuery.sizeOf(context).height -
                        MediaQuery.viewInsetsOf(context).bottom) *
                    .72,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        multiple ? 'Reservas relacionados' : 'Escolher jogador',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (multiple)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'Marque quem ficou no banco nesta partida.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 14),
                      TextField(
                        autocorrect: false,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Buscar jogador',
                        ),
                        onChanged: (value) => setSheetState(
                          () => query = value.trim().toLowerCase(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ids.isEmpty
                            ? const Center(
                                child: Text('Nenhum jogador disponível.'),
                              )
                            : ListView(
                                children: [
                                  for (final id in ids)
                                    multiple
                                        ? CheckboxListTile(
                                            key: ValueKey('relate-$id'),
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(_name(id)),
                                            subtitle: Text(
                                              positionShortName(_position(id)),
                                            ),
                                            value: selected.contains(id),
                                            secondary: _avatar(id, 18),
                                            onChanged: (checked) =>
                                                setSheetState(() {
                                                  if (checked == true) {
                                                    selected.add(id);
                                                  } else {
                                                    selected.remove(id);
                                                  }
                                                }),
                                          )
                                        : ListTile(
                                            key: ValueKey('choose-$id'),
                                            contentPadding: EdgeInsets.zero,
                                            leading: _avatar(id, 18),
                                            title: Text(_name(id)),
                                            subtitle: Text(
                                              '${positionShortName(_position(id))} · ${_formation.starters.containsKey(id)
                                                  ? 'Titular'
                                                  : _formation.bench.contains(id)
                                                  ? 'Reserva relacionado'
                                                  : 'Disponível'}',
                                            ),
                                            onTap: () =>
                                                Navigator.pop(context, [id]),
                                          ),
                                ],
                              ),
                      ),
                      if (multiple)
                        FilledButton(
                          key: const ValueKey('save-related-bench'),
                          onPressed: () =>
                              Navigator.pop(context, selected.toList()),
                          child: Text(
                            'Relacionar ${selected.length} ${selected.length == 1 ? 'reserva' : 'reservas'}',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _avatar(String id, double radius) => PlayerAvatar(
    fifaVersion: widget.person.fifaVersion,
    radius: radius,
    realPlayerId: _formation.players[id]?['realPlayerId'] as String?,
    customAvatarFilePath:
        _formation.players[id]?['customAvatarFilePath'] as String?,
  );

  Rect _anchor(BuildContext context, String id) {
    Rect? avatar;
    void visit(Element element) {
      if (avatar != null) return;
      if (element.widget.key == ValueKey('pitch-avatar-$id')) {
        final box = element.renderObject;
        if (box is RenderBox && box.hasSize) {
          avatar = box.localToGlobal(Offset.zero) & box.size;
        }
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    if (avatar != null) return avatar!;
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final side = math.min(box.size.height, 44.0);
    return Rect.fromLTWH(
      origin.dx + 8,
      origin.dy + (box.size.height - side) / 2,
      side,
      side,
    );
  }

  Widget _card(Color color) => Container(
    width: 13,
    height: 18,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(3),
    ),
  );

  Future<void> _playerActions(String id, BuildContext anchor) async {
    if (!widget.editable) {
      if (widget.canViewPlayer?.call(id) ?? true) widget.onPlayerTap?.call(id);
      return;
    }
    final c = AppColors.of(context);
    final starter = _formation.starters.containsKey(id);
    final rect = _anchor(anchor, id);
    final action = await showPitchPlayerMenu(
      context,
      anchor: rect,
      avatar: _avatar(id, rect.shortestSide / 2),
      items: [
        if (widget.onPlayerAction != null) ...[
          PitchMenuItem(
            'goal',
            'Gol',
            Icon(Icons.sports_soccer, color: c.accent, size: 22),
          ),
          PitchMenuItem(
            'assist',
            'Assistência',
            SvgPicture.asset(
              'assets/images/assistBoot.svg',
              width: 22,
              height: 22,
              colorFilter: ColorFilter.mode(c.text, BlendMode.srcIn),
            ),
          ),
          PitchMenuItem(
            starter ? 'substitutionOut' : 'substitutionIn',
            'Substituição',
            const Icon(
              Icons.swap_vert_rounded,
              color: AppColors.ratingGood,
              size: 24,
            ),
          ),
          PitchMenuItem(
            'yellowCard',
            'Cartão amarelo',
            _card(AppColors.yellowCard),
          ),
          PitchMenuItem('redCard', 'Cartão vermelho', _card(AppColors.redCard)),
        ],
        if (widget.onPlayerTap != null &&
            (widget.canViewPlayer?.call(id) ?? true))
          PitchMenuItem(
            'view',
            widget.playerActionLabel,
            Icon(Icons.edit_note_rounded, color: c.text, size: 24),
          ),
        PitchMenuItem(
          'replace',
          'Trocar jogador',
          Icon(Icons.swap_horiz_rounded, color: c.text, size: 22),
        ),
        if (starter)
          PitchMenuItem(
            'bench',
            'Mover para os reservas',
            Icon(Icons.event_seat_outlined, color: c.text, size: 22),
          ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'view') {
      widget.onPlayerTap?.call(id);
    } else if (action == 'replace') {
      final target = _formation.starters[id],
          selected = await _choosePlayers(
            multiple: false,
            onlyReserves: target == null,
          );
      if (!mounted || selected == null) return;
      if (target != null) {
        await _save(_formation.place(selected.single, target));
      } else {
        final ids = [..._formation.bench]
          ..remove(id)
          ..add(selected.single);
        await _save(_formation.relateBench(ids));
      }
    } else if (action == 'bench') {
      await _save(
        _formation.copy(
          starters: Map.of(_formation.starters)..remove(id),
          bench: [..._formation.bench, id],
        ),
      );
    } else {
      await widget.onPlayerAction?.call(id, action);
    }
  }

  Widget _player(String id) {
    final performance = _performances[id];
    final card = Builder(
      builder: (cardContext) => FixturePitchPlayer(
        id: id,
        name: _name(id),
        position: positionShortName(
          _formation.players[id]?['positionId'] as String?,
        ),
        captain: widget.captainIds.contains(id),
        shirtNumber: _formation.players[id]?['shirtNumber'],
        avatar: (radius) => _avatar(id, radius),
        rating: performance?.avgRating,
        performance: performance,
        yellow: performance?.yellowCardDetails.isNotEmpty == true,
        red: performance?.redCardDetails.isNotEmpty == true,
        substitutionIn:
            performance?.substitutionDetails.any(
              (s) => s.type == SubstitutionType.inGame,
            ) ==
            true,
        substitutionOut:
            performance?.substitutionDetails.any(
              (s) => s.type != SubstitutionType.inGame,
            ) ==
            true,
        onTap: _saving ? null : () => _playerActions(id, cardContext),
      ),
    );
    if (!widget.editable) {
      return KeyedSubtree(
        key: ValueKey('fixture-pitch-player-$id'),
        child: card,
      );
    }
    return LongPressDraggable<String>(
      key: ValueKey('fixture-pitch-player-$id'),
      data: id,
      delay: const Duration(milliseconds: 250),
      maxSimultaneousDrags: _saving ? 0 : 1,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 90, child: card),
      ),
      childWhenDragging: Opacity(opacity: .3, child: card),
      child: card,
    );
  }

  Widget _slot(int x, int y) {
    final id = _formation.starters.entries
        .where((e) => e.value == (x: x, y: y))
        .firstOrNull
        ?.key;
    if (!widget.editable) {
      return Center(child: id == null ? const SizedBox.shrink() : _player(id));
    }
    return DragTarget<String>(
      key: ValueKey('fixture-slot-$x-$y'),
      onWillAcceptWithDetails: (d) => !_saving && d.data != id,
      onAcceptWithDetails: (d) => _save(_formation.place(d.data, (x: x, y: y))),
      builder: (context, candidates, _) => Container(
        decoration: candidates.isEmpty
            ? null
            : BoxDecoration(
                color: AppColors.of(context).accent.withValues(alpha: .2),
                borderRadius: BorderRadius.circular(14),
              ),
        alignment: Alignment.center,
        child: id == null
            ? InkWell(
                key: ValueKey('empty-fixture-slot-$x-$y'),
                onTap: _saving
                    ? null
                    : () async {
                        final selected = await _choosePlayers(multiple: false);
                        if (mounted && selected != null) {
                          await _save(
                            _formation.place(selected.single, (x: x, y: y)),
                          );
                        }
                      },
                borderRadius: BorderRadius.circular(14),
                child: LayoutBuilder(
                  builder: (context, constraints) => Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: constraints.maxWidth < 50 ? 1 : 8,
                      vertical: 8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_circle_outline_rounded,
                          color: AppColors.of(context).muted,
                          size: math.min(24, constraints.maxWidth - 2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Escolher',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.of(context).muted,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : _player(id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = CareerUiColors(context);
    final children = <Widget>[
      widget.header,
      if (widget.header is! SizedBox) const SizedBox(height: 12),
      MatchFormationBar(
        key: const ValueKey('choose-fixture-formation'),
        title: 'Formação inicial',
        formation: _formation.formation,
        count: '${_formation.starters.length}/11',
        onTap: !widget.editable || _saving ? null : _chooseFormation,
        trailing: _saving
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
      ),
      const SizedBox(height: 14),
      LayoutBuilder(
        builder: (context, constraints) => AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          child: SizedBox(
            key: ValueKey('fixture-pitch-${_formation.formation}'),
            height: SquadPitchMetrics.forMatch(
              context,
              hasReserves: widget.available.players.length > 11,
            ),
            child: FootballPitch(
              formation: _formation.formation,
              slotBuilder: _slot,
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (widget.editable)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: MatchHint(
            'Toque num jogador para lances, troca e reservas. Segure e arraste para ajustar o campinho.',
            icon: Icons.touch_app_outlined,
          ),
        ),
      if (widget.performances.any(
        (p) => p.substitutionDetails.any((s) => s.inferred),
      ))
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: MatchHint(
            '~ Minuto estimado pelos minutos jogados informados pela API.',
          ),
        ),
      DragTarget<String>(
        key: const ValueKey('fixture-bench-area'),
        onWillAcceptWithDetails: (d) =>
            widget.editable &&
            !_saving &&
            _formation.starters.containsKey(d.data),
        onAcceptWithDetails: (d) => _save(
          _formation.copy(
            starters: Map.of(_formation.starters)..remove(d.data),
            bench: [..._formation.bench, d.data],
          ),
        ),
        builder: (context, candidates, _) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: candidates.isEmpty
                ? null
                : Border.all(color: colors.accent, width: 1.5),
          ),
          child: MatchBenchPanel(
            count: _formation.bench.length,
            empty: widget.editable
                ? 'Nenhum reserva relacionado. Use o botão ao lado para escolher o banco desta partida.'
                : 'Nenhum reserva relacionado.',
            action: widget.editable
                ? IconButton(
                    key: const ValueKey('relate-fixture-bench'),
                    tooltip: 'Relacionar reservas',
                    visualDensity: VisualDensity.compact,
                    onPressed: _saving
                        ? null
                        : () async {
                            final selected = await _choosePlayers(
                              multiple: true,
                            );
                            if (mounted && selected != null) {
                              await _save(_formation.relateBench(selected));
                            }
                          },
                    icon: Icon(
                      Icons.playlist_add_check_rounded,
                      color: colors.accent,
                    ),
                  )
                : null,
            children: [
              for (final id in _formation.bench)
                Builder(
                  key: ValueKey('fixture-bench-$id'),
                  builder: (rowContext) => MatchPlayerRow(
                    avatar: _avatar(id, 19),
                    name: _name(id),
                    detail: positionShortName(
                      _formation.players[id]?['positionId'] as String?,
                    ),
                    events: FixturePitchEvents(performance: _performances[id]),
                    rating: _performances[id]?.avgRating,
                    onTap: _saving
                        ? null
                        : () => _playerActions(id, rowContext),
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return ListView(
      primary: false,
      key: const PageStorageKey('fixture-formation'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
      children: children,
    );
  }
}
