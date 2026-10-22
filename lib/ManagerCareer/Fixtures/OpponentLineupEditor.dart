import 'package:flutter/material.dart';

import '../../Common/FootballFormationPicker.dart';
import '../../models/ManagerFixturePlayerPerformance.dart';
import '../../models/OpponentLineup.dart';
import '../../models/Person.dart';
import '../../utils/databaseUtils.dart';
import 'OpponentPlayerIdentityDialog.dart';
import 'Performances/PerformanceDetails.dart';
import 'Performances/TeamPlayersPerformanceGrid.dart';

class OpponentLineupEditor extends StatelessWidget {
  const OpponentLineupEditor({
    super.key,
    required this.person,
    required this.fixtureId,
    required this.lineup,
    required this.onChanged,
    this.showTitle = true,
  });
  final Person person;
  final String fixtureId;
  final OpponentLineup lineup;
  final ValueChanged<OpponentLineup> onChanged;
  final bool showTitle;

  static List<String> orderedIds(OpponentLineup data) {
    int priority(String id) {
      final position = data.squad.players[id]?['positionId'] as String?;
      return position == null ? 999 : getPositionPriority(position);
    }

    return [...data.startingIds, ...data.squad.bench]
      ..sort((a, b) => priority(a).compareTo(priority(b)));
  }

  static Future<OpponentLineup?> editIdentity(
    BuildContext context,
    Person person,
    OpponentLineup data,
    String id,
  ) async {
    final identity = await showDialog<OpponentPlayerIdentity>(
      context: context,
      builder: (_) => OpponentPlayerIdentityDialog(
        person: person,
        playerId: id,
        name: data.names[id] ?? '',
        photo: data.squad.players[id]?['customAvatarFilePath'] as String?,
      ),
    );
    if (identity == null) return null;
    return data.withIdentity(id, name: identity.name, photo: identity.photo);
  }

  static Future<void> addPlayer(
    BuildContext context,
    Person person,
    OpponentLineup data,
    ValueChanged<OpponentLineup> onChanged,
  ) async {
    var next = data;
    var id = orderedIds(next)
        .where((id) => next.names[id]!.isEmpty)
        .firstOrNull;
    if (id == null) {
      next = next.addReserve('');
      id = next.squad.bench.last;
    }
    final edited = await editIdentity(context, person, next, id);
    if (edited != null && context.mounted) onChanged(edited);
  }

  static Future<void> chooseFormation(
    BuildContext context,
    OpponentLineup data,
    ValueChanged<OpponentLineup> onChanged,
  ) async {
    final selected = await showFootballFormationPicker(
      context,
      data.squad.formation,
    );
    if (selected != null && context.mounted) {
      onChanged(data.withFormation(selected));
    }
  }

  Future<void> _identity(BuildContext context, String id) async {
    final edited = await editIdentity(context, person, lineup, id);
    if (edited != null && context.mounted) onChanged(edited);
  }

  Future<void> editPerformance(
    BuildContext context,
    String id, {
    String? initialEvent,
  }) async {
    if (lineup.names[id]?.isNotEmpty != true) {
      await _identity(context, id);
      return;
    }
    var current = lineup;
    final names = {
      for (final e in lineup.names.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    };
    final performance =
        lineup.performances
            .where((p) => p.playerInstanceId == id)
            .firstOrNull ??
        ManagerFixturePlayerPerformance(
          personId: person.id,
          fixtureId: fixtureId,
          playerInstanceId: id,
        );
    final result = await Navigator.push<PerformanceDetailsResult>(
      context,
      MaterialPageRoute(
        builder: (editorContext) => PerformanceDetails(
          person: person,
          performance: performance,
          isNew: false,
          names: names,
          positions: {
            for (final e in lineup.squad.players.entries)
              e.key: positionShortName(e.value['positionId'] as String?),
          },
          roster: [
            for (final e in lineup.squad.players.entries)
              if (names.containsKey(e.key))
                {
                  'id': e.key,
                  'playerId': e.key,
                  'customName': names[e.key],
                  'customPositionId': e.value['positionId'],
                  'customAvatarFilePath': e.value['customAvatarFilePath'],
                  'isBench': lineup.squad.bench.contains(e.key) ? 1 : 0,
                },
          ],
          teamLastMinute: lineup.performances.fold<int>(0, (last, p) {
            final value = p.getLastMinuteValue() ?? 0;
            return value > last ? value : last;
          }),
          showPlayerOfMatch: false,
          initialEvent: initialEvent,
          showGoalkeeperStats: lineup.squad.players[id]?['positionId'] == '0',
          onEditPlayerIdentity: () async {
            final edited = await editIdentity(
              editorContext,
              person,
              current,
              id,
            );
            if (edited == null || !editorContext.mounted) return null;
            current = edited;
            names.clear();
            names.addAll({
              for (final e in current.names.entries)
                if (e.value.isNotEmpty) e.key: e.value,
            });
            onChanged(current);
            return names[id];
          },
        ),
      ),
    );
    if (result?.performance != null && context.mounted) {
      onChanged(
        current.editPerformance(result!.performance!, deleted: result.deleted),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showTitle) ...[
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('choose-opponent-formation'),
                onPressed: () => chooseFormation(context, lineup, onChanged),
                child: Text(
                  lineup.squad.formation.isEmpty
                      ? 'Escolher formação'
                      : lineup.squad.formation,
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              key: const ValueKey('add-opponent-player'),
              onPressed: () => addPlayer(context, person, lineup, onChanged),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 14),
      ],
      TeamPlayersPerformanceGrid(
        rows: [
          for (final id in orderedIds(lineup))
            lineup.performances
                    .where((p) => p.playerInstanceId == id)
                    .firstOrNull ??
                ManagerFixturePlayerPerformance(
                  personId: person.id,
                  fixtureId: fixtureId,
                  playerInstanceId: id,
                ),
        ],
        names: lineup.names,
        positions: {
          for (final e in lineup.squad.players.entries)
            e.key: e.value['positionId'] == null
                ? 'RES'
                : positionShortName(e.value['positionId'] as String?),
        },
        playerOfMatchId: null,
        showHeader: false,
        onTap: (p) => editPerformance(context, p.playerInstanceId),
        onLongPress: (p) => _identity(context, p.playerInstanceId),
        onAddPlayer: (p) => _identity(context, p.playerInstanceId),
      ),
    ],
  );
}
