import '../../utils/AppColors.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../models/Person.dart';
import '../../utils/GamePlayers.dart';
import '../../utils/databaseUtils.dart';
import '../../utils/FootballFormations.dart';
import '../../utils/SquadLineup.dart';
import 'PlayerWidget.dart';
import '../../utils/Components/FootballPitch.dart';

class ManagerRosterView extends StatefulWidget {
  const ManagerRosterView({
    super.key,
    required this.person,
    required this.roster,
    required this.gamePlayers,
    required this.onPlayerTap,
    required this.onAdd,
    required this.onMove,
    required this.onLineupChanged,
    this.formation,
    this.onFormationChanged,
  });
  final Person person;
  final List<Map<String, Object?>> roster;
  final Map<String, GamePlayer> gamePlayers;
  final void Function(Map<String, Object?>, GamePlayer?) onPlayerTap;
  final VoidCallback onAdd;
  final Future<void> Function(
    Map<String, Object?>,
    bool,
    Map<String, Object?>?, {
    ({int x, int y})? targetPosition,
  })
  onMove;
  final Future<void> Function(Map<String, ({int x, int y})>) onLineupChanged;
  final String? formation;
  final Future<void> Function(String, Map<String, SquadSlot>)?
  onFormationChanged;

  @override
  State<ManagerRosterView> createState() => _ManagerRosterViewState();
}

class _ManagerRosterViewState extends State<ManagerRosterView> {
  static const formations = footballFormations;
  String? selectedFormation;
  Map<String, SquadSlot>? _pendingPositions;

  @override
  void didUpdateWidget(ManagerRosterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.roster, widget.roster)) _pendingPositions = null;
    if (oldWidget.formation != widget.formation) selectedFormation = null;
  }

  List<Map<String, Object?>> get starters =>
      widget.roster.where((r) => r['isBench'] != 1).toList();
  List<Map<String, Object?>> get reserves =>
      widget.roster.where((r) => r['isBench'] == 1).toList();
  String id(Map<String, Object?> r) => r['id'].toString();
  GamePlayer? real(Map<String, Object?> r) =>
      widget.gamePlayers[(r['realPlayerId'] ?? r['playerId'])?.toString() ??
          ''];
  String name(Map<String, Object?> r) =>
      r['customName']?.toString() ?? real(r)?.name ?? '?';
  String position(Map<String, Object?> r) => positionShortName(
    r['customPositionId'] as String? ?? real(r)?.mainPositionId,
  );

  String get formation {
    if (selectedFormation != null) return selectedFormation!;
    return selectedFormation =
        widget.formation ?? inferSquadFormation(_players(starters));
  }

  List<Map<String, Object?>> _players(List<Map<String, Object?>> rows) => [
    for (final row in rows)
      {
        ...row,
        'positionId': row['customPositionId'] ?? real(row)?.mainPositionId,
      },
  ];

  Widget playerCard(Map<String, Object?> row, {bool reserve = false}) =>
      PlayerWidget(
        key: ValueKey('player-${id(row)}'),
        name: row['shirtNumber'] == null
            ? name(row)
            : '${row['shirtNumber']}. ${name(row)}',
        position: position(row),
        showPosition: !reserve,
        fifaVersion: widget.person.fifaVersion,
        realPlayerId: row['realPlayerId'] as String?,
        customAvatarFilePath: row['customAvatarFilePath'] as String?,
        overall: (row['overall'] as num?)?.toInt(),
        onTap: () => widget.onPlayerTap(row, real(row)),
      );

  Widget player(Map<String, Object?> row, {bool reserve = false}) =>
      LongPressDraggable<Map<String, Object?>>(
        data: row,
        delay: const Duration(milliseconds: 250),
        rootOverlay: true,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: 88,
            height: 104,
            child: playerCard(row, reserve: reserve),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: .25,
          child: playerCard(row, reserve: reserve),
        ),
        child: playerCard(row, reserve: reserve),
      );

  Future<void> move(
    Map<String, Object?> row,
    bool reserve,
    Map<String, Object?>? replace, {
    ({int x, int y})? targetPosition,
  }) async {
    selectedFormation ??= formation;
    await widget.onMove(row, reserve, replace, targetPosition: targetPosition);
  }

  Widget slot(
    Map<String, Object?>? occupant,
    int x,
    int y,
    Map<String, ({int x, int y})> current,
  ) => DragTarget<Map<String, Object?>>(
    key: ValueKey('lineup-slot-$x-$y'),
    onWillAcceptWithDetails: (details) =>
        id(details.data) != (occupant == null ? '' : id(occupant)),
    onAcceptWithDetails: (details) {
      if (details.data['isBench'] == 1) {
        move(details.data, false, occupant, targetPosition: (x: x, y: y));
        return;
      }
      final updated = Map<String, ({int x, int y})>.of(current);
      final old = updated[id(details.data)];
      if (old == null) return;
      updated[id(details.data)] = (x: x, y: y);
      if (occupant != null) updated[id(occupant)] = old;
      widget.onLineupChanged(updated);
    },
    builder: (_, candidates, _) => Container(
      decoration: candidates.isEmpty
          ? null
          : BoxDecoration(
              color: AppColors.of(context).accent.withValues(alpha: .25),
              borderRadius: BorderRadius.circular(12),
            ),
      alignment: Alignment.center,
      child: occupant == null
          ? Icon(Icons.add_circle_outline, color: AppColors.of(context).line)
          : player(occupant),
    ),
  );

  Widget lineup(Map<String, ({int x, int y})> current) {
    final bySlot = <String, Map<String, Object?>>{
      for (final row in starters)
        if (current.containsKey(id(row)))
          '${current[id(row)]!.x}:${current[id(row)]!.y}': row,
    };
    return FootballPitch(
      key: const ValueKey('lineup-pitch'),
      formation: formation,
      slotBuilder: (x, y) => slot(bySlot['$x:$y'], x, y, current),
    );
  }

  Widget bench(Map<String, ({int x, int y})> current) {
    final benchPlayers = reserves;
    return DragTarget<Map<String, Object?>>(
      key: const ValueKey('reserve-area'),
      onWillAcceptWithDetails: (details) => details.data['isBench'] != 1,
      onAcceptWithDetails: (details) => move(details.data, true, null),
      builder: (_, candidates, _) => Container(
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? AppColors.of(context).panel
              : AppColors.of(context).raised,
          border: Border.all(color: AppColors.of(context).line),
          borderRadius: BorderRadius.circular(22),
        ),
        child: benchPlayers.isEmpty
            ? Center(
                child: Text(
                  'common.noItems'.tr(),
                  style: TextStyle(color: AppColors.of(context).muted),
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) => GridView.builder(
                  key: const ValueKey('reserve-grid'),
                  scrollCacheExtent: const ScrollCacheExtent.pixels(104),
                  padding: const EdgeInsets.all(8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: ((constraints.maxWidth - 16) / 66)
                        .floor()
                        .clamp(3, 7),
                    mainAxisExtent: 104,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: benchPlayers.length,
                  itemBuilder: (context, index) {
                    final row = benchPlayers[index];
                    return DragTarget<Map<String, Object?>>(
                      onWillAcceptWithDetails: (details) =>
                          details.data['isBench'] != 1,
                      onAcceptWithDetails: (details) => move(
                        row,
                        false,
                        details.data,
                        targetPosition: current[id(details.data)],
                      ),
                      builder: (_, candidates, _) => Container(
                        decoration: candidates.isEmpty
                            ? null
                            : BoxDecoration(
                                color: AppColors.of(context).accent
                                    .withValues(alpha: .4),
                                borderRadius: BorderRadius.circular(12),
                              ),
                        child: player(row, reserve: true),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current =
        _pendingPositions ?? squadPositions(_players(starters), formation);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final benchHeight = SquadPitchMetrics(
              constraints.maxHeight,
              hasReserves: reserves.isNotEmpty,
            ).benchHeight;
            return Column(
              children: [
                SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${'teams.start11'.tr()} · ${starters.length}/11',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      DropdownButtonHideUnderline(
                        child: SizedBox(
                          width: 136,
                          child: DropdownButton<String>(
                            value: formation,
                            isExpanded: true,
                            isDense: true,
                            style: Theme.of(context).textTheme.bodyMedium,
                            items: [
                              for (final value in formations.keys)
                                DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              final next = squadPositions(
                                _players(starters),
                                value,
                                preserve: false,
                              );
                              setState(() {
                                selectedFormation = value;
                                _pendingPositions = next;
                              });
                              final save = widget.onFormationChanged;
                              if (save != null) {
                                save(value, next);
                              } else {
                                widget.onLineupChanged(next);
                              }
                            },
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: widget.onAdd,
                        tooltip: 'players.addPlayers'.tr(),
                        icon: const Icon(Icons.person_add_alt_1, size: 22),
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
                Expanded(child: lineup(current)),
                SizedBox(
                  height: 28,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${'teams.reserve'.tr()} · ${reserves.length}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Flexible(
                        flex: 2,
                        child: Text(
                          'Segure e arraste para trocar',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: benchHeight, child: bench(current)),
              ],
            );
          },
        ),
      ),
    );
  }
}
