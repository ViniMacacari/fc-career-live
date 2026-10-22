import 'dart:convert';

import '../utils/FootballFormations.dart';
import '../utils/SquadLineup.dart';
import 'ManagerFixturePlayerPerformance.dart';

typedef FixturePitchSlot = ({int x, int y});

class FixtureFormation {
  FixtureFormation({
    required this.formation,
    required this.players,
    required this.starters,
    required this.bench,
    this.layoutSource,
  });
  final String formation;
  final Map<String, Map<String, Object?>> players;
  final Map<String, FixturePitchSlot> starters;
  final List<String> bench;
  final String? layoutSource;
  List<int> get shape => footballFormationShape(formation);

  static FixtureFormation? decode(Object? raw) {
    if (raw == null) return null;
    try {
      final map = raw is String ? jsonDecode(raw) : raw;
      if (map is! Map || map['players'] is! Map || map['starters'] is! Map) {
        return null;
      }
      final players = <String, Map<String, Object?>>{
        for (final e in (map['players'] as Map).entries)
          if (e.value is Map)
            '${e.key}': Map<String, Object?>.from(e.value as Map),
      };
      final label = '${map['formation'] ?? '4-3-3'}';
      final shape = footballFormationShape(label);
      final slots = <String>{};
      final starters = <String, FixturePitchSlot>{};
      for (final e in (map['starters'] as Map).entries) {
        if (!players.containsKey('${e.key}') || e.value is! Map) continue;
        final slot = e.value as Map;
        final x = (slot['x'] as num?)?.toInt(),
            y = (slot['y'] as num?)?.toInt();
        if (x == null ||
            y == null ||
            y < 0 ||
            y >= shape.length ||
            x < 0 ||
            x >= shape[y] ||
            !slots.add('$x:$y')) {
          continue;
        }
        starters['${e.key}'] = (x: x, y: y);
      }
      return FixtureFormation(
        formation: label,
        layoutSource: map['layoutSource'] as String?,
        players: players,
        starters: starters,
        bench: (map['bench'] as List? ?? const [])
            .map((id) => '$id')
            .where((id) => players.containsKey(id) && !starters.containsKey(id))
            .toSet()
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  static FixtureFormation initial({
    required List<Map<String, Object?>> roster,
    required Map<String, String> names,
    required Map<String, String?> positions,
    required List<ManagerFixturePlayerPerformance> performances,
    bool useRosterWhenEmpty = true,
    Map<String, ({String? realPlayerId, String? path})> avatars = const {},
  }) {
    final players = <String, Map<String, Object?>>{};
    for (final row in roster) {
      final id = (row['playerId'] ?? row['id'])?.toString();
      if (id == null) continue;
      players[id] = {
        'id': id,
        'name': names[id] ?? row['customName'] ?? row['name'] ?? id,
        'positionId':
            positions[id] ?? row['customPositionId'] ?? row['positionId'],
        'shirtNumber': row['shirtNumber'],
        'realPlayerId': avatars[id]?.realPlayerId ?? row['realPlayerId'],
        'customAvatarFilePath':
            avatars[id]?.path ?? row['customAvatarFilePath'],
      };
    }
    for (final p in performances) {
      final id = p.playerInstanceId;
      players.putIfAbsent(
        id,
        () => {
          'id': id,
          'name': names[id] ?? id,
          'positionId': positions[id],
          'realPlayerId': avatars[id]?.realPlayerId,
          'customAvatarFilePath': avatars[id]?.path,
        },
      );
    }
    bool substitute(ManagerFixturePlayerPerformance p) {
      if (p.recordedStarted != null) return !p.recordedStarted!;
      final substitutions =
          p.substitutionDetails.where((s) => s.type != null).toList()
            ..sort((a, b) {
              final minute = (a.minute ?? 999).compareTo(b.minute ?? 999);
              return minute != 0
                  ? minute
                  : (a.addedMinute ?? 0).compareTo(b.addedMinute ?? 0);
            });
      return substitutions.firstOrNull?.type == SubstitutionType.inGame;
    }

    final starting = performances.isEmpty && useRosterWhenEmpty
        ? roster
              .where((r) => r['isBench'] != 1)
              .map((r) => '${r['playerId'] ?? r['id']}')
              .toList()
        : performances
              .where((p) => !substitute(p))
              .map((p) => p.playerInstanceId)
              .toList();
    final bench = performances.isEmpty && useRosterWhenEmpty
        ? roster
              .where((r) => r['isBench'] == 1)
              .map((r) => '${r['playerId'] ?? r['id']}')
              .toSet()
              .toList()
        : <String>{
            ...performances.where(substitute).map((p) => p.playerInstanceId),
            ...starting.skip(11),
          }.toList();
    final counts = <int, int>{};
    for (final r in roster.where((r) => r['isBench'] != 1)) {
      if (r['y'] case final int y) counts[y] = (counts[y] ?? 0) + 1;
    }
    final formation =
        roster
            .map((r) => r['lineupFormation'])
            .whereType<String>()
            .where(footballFormations.containsKey)
            .firstOrNull ??
        footballFormations.entries
            .where(
              (e) =>
                  counts.length == e.value.length &&
                  e.value.asMap().entries.every(
                    (r) => counts[r.key] == r.value,
                  ),
            )
            .firstOrNull
            ?.key ??
        '4-3-3';
    var result = FixtureFormation(
      formation: formation,
      layoutSource: 'squad',
      players: players,
      starters: {},
      bench: bench,
    );
    result = result.withFormation(
      formation,
      starting: starting.take(11).toList(),
      source: 'squad',
    );
    final original = <String, FixturePitchSlot>{};
    final used = <String>{};
    for (final r in roster) {
      final id = '${r['playerId'] ?? r['id']}', x = r['x'], y = r['y'];
      if (result.starters.containsKey(id) &&
          x is int &&
          y is int &&
          y >= 0 &&
          y < result.shape.length &&
          x >= 0 &&
          x < result.shape[y] &&
          used.add('$x:$y')) {
        original[id] = (x: x, y: y);
      }
    }
    result = result.withPreservedSlots(original);
    return result;
  }

  FixtureFormation copy({
    String? formation,
    Map<String, FixturePitchSlot>? starters,
    List<String>? bench,
    Map<String, Map<String, Object?>>? players,
    String? layoutSource,
  }) => FixtureFormation(
    formation: formation ?? this.formation,
    players: players ?? this.players,
    starters: starters ?? this.starters,
    bench: bench ?? this.bench,
    layoutSource: layoutSource ?? this.layoutSource,
  );

  FixtureFormation withFormation(
    String label, {
    List<String>? starting,
    String source = 'manual',
  }) {
    final ids = [...(starting ?? starters.keys)]
        .where(players.containsKey)
        .toSet()
        .toList();
    final result = squadPositions(
      [
        for (final id in ids)
          {'id': id, 'positionId': players[id]?['positionId']},
      ],
      label,
      preserve: false,
    );
    return copy(
      formation: label,
      layoutSource: source,
      starters: {for (final id in ids) id: ?result[id]},
      bench: bench.where((id) => !result.containsKey(id)).toList(),
    );
  }

  FixtureFormation withPreservedSlots(Map<String, FixturePitchSlot> original) {
    final result = squadPositions([
      for (final id in starters.keys)
        {
          'id': id,
          'positionId': players[id]?['positionId'],
          'x': original[id]?.x,
          'y': original[id]?.y,
        },
    ], formation);
    return copy(starters: {for (final id in starters.keys) id: ?result[id]});
  }

  FixtureFormation reconciledWith(FixtureFormation selected) {
    final identities = {...selected.players, ...players};
    final desired = selected.starters.keys.toSet();
    final fixed = layoutSource == 'manual'
        ? {
            for (final entry in starters.entries)
              if (desired.contains(entry.key)) entry.key: entry.value,
          }
        : selected.formation == formation
        ? selected.starters
        : const <String, FixturePitchSlot>{};
    return copy(players: identities)
        .withFormation(
          formation,
          starting: desired.toList(),
          source: layoutSource ?? 'squad',
        )
        .withPreservedSlots(fixed)
        .copy(
          bench: {...bench, ...selected.bench}
              .where(
                (id) => identities.containsKey(id) && !desired.contains(id),
              )
              .toList(),
        );
  }

  FixtureFormation place(String id, FixturePitchSlot target) {
    if (!players.containsKey(id) ||
        target.y < 0 ||
        target.y >= shape.length ||
        target.x < 0 ||
        target.x >= shape[target.y]) {
      return this;
    }
    final old = starters[id];
    final occupant = starters.entries
        .where((e) => e.value == target)
        .firstOrNull
        ?.key;
    final next = Map<String, FixturePitchSlot>.of(starters)..remove(id);
    final reserves = [...bench]..remove(id);
    if (occupant != null) {
      next.remove(occupant);
      if (old != null) {
        next[occupant] = old;
      } else if (!reserves.contains(occupant)) {
        reserves.add(occupant);
      }
    }
    next[id] = target;
    return copy(starters: next, bench: reserves, layoutSource: 'manual');
  }

  FixtureFormation relateBench(Iterable<String> ids) => copy(
    bench: ids
        .where((id) => players.containsKey(id) && !starters.containsKey(id))
        .toSet()
        .toList(),
  );

  String encode() => jsonEncode({
    'formation': formation,
    if (layoutSource != null) 'layoutSource': layoutSource,
    'players': players,
    'starters': {
      for (final e in starters.entries) e.key: {'x': e.value.x, 'y': e.value.y},
    },
    'bench': bench,
  });
}
