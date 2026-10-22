import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../utils/FootballFormations.dart';
import '../utils/managerFixturePerformanceUtils.dart';
import 'FixtureFormation.dart';
import 'ManagerFixture.dart';
import 'ManagerFixturePlayerPerformance.dart';

class OpponentLineup {
  OpponentLineup({required this.squad, this.performances = const []});
  final FixtureFormation squad;
  final List<ManagerFixturePlayerPerformance> performances;
  Map<String, String> get names => {
    for (final e in squad.players.entries) e.key: '${e.value['name'] ?? ''}',
  };
  bool get hasNames => squad.players.values.any(hasFootballIdentity);

  OpponentLineup resolved() {
    final named = {
      for (final e in squad.players.entries)
        if (hasFootballIdentity(e.value)) e.key: e.value,
    };
    final byId = {for (final p in performances) p.playerInstanceId: p};
    bool reserve(String id) {
      final p = byId[id];
      if (p?.recordedStarted != null) return !p!.recordedStarted!;
      final changes = [...?p?.substitutionDetails]
        ..sort((a, b) => (a.minute ?? 999).compareTo(b.minute ?? 999));
      return changes.firstOrNull?.type == SubstitutionType.inGame;
    }

    final recorded = named.keys
        .where((id) => byId[id]?.recordedStarted == true)
        .toList();
    final starting = <String>{
      ...recorded,
      ...squad.starters.keys.where(
        (id) => named.containsKey(id) && !reserve(id),
      ),
      ...named.keys.where((id) => !squad.bench.contains(id) && !reserve(id)),
    }.take(11).toList();
    final manual =
        squad.layoutSource == 'manual' ||
        (squad.layoutSource == null &&
            !squad.players.values.any(
              (p) => p['apiPlayerId'] != null || p['apiStarted'] != null,
            ));
    final label = manual && squad.formation.isNotEmpty
        ? squad.formation
        : inferFootballFormation(
                starting.map((id) => named[id]?['positionId'] as String?),
              ) ??
              (squad.formation.isNotEmpty ? squad.formation : '4-3-3');
    var fixed =
        FixtureFormation(
          formation: label,
          players: named,
          starters: {},
          bench: named.keys.where((id) => !starting.contains(id)).toList(),
          layoutSource: squad.layoutSource,
        ).withFormation(
          label,
          starting: starting,
          source: squad.layoutSource ?? 'api',
        );
    if (manual && label == squad.formation) {
      fixed = fixed.withPreservedSlots(squad.starters);
    }
    return copy(squad: fixed.copy(players: squad.players));
  }

  List<String> get startingIds =>
      (squad.starters.entries.toList()..sort(
            (a, b) => b.value.y.compareTo(a.value.y) != 0
                ? b.value.y.compareTo(a.value.y)
                : a.value.x.compareTo(b.value.x),
          ))
          .map((e) => e.key)
          .toList();

  static OpponentLineup unselected() => OpponentLineup(
    squad: FixtureFormation(
      formation: '',
      players: {},
      starters: {},
      bench: [],
    ),
  );

  static OpponentLineup empty({String formation = '4-3-3'}) {
    final shape = footballFormationShape(formation);
    final players = <String, Map<String, Object?>>{};
    final slots = <String, FixturePitchSlot>{};
    for (var y = shape.length - 1; y >= 0; y--) {
      for (var x = 0; x < shape[y]; x++) {
        final id = 'opponent-${const Uuid().v4()}';
        players[id] = {
          'id': id,
          'name': '',
          'positionId': slotPosition(shape, x, y),
        };
        slots[id] = (x: x, y: y);
      }
    }
    return OpponentLineup(
      squad: FixtureFormation(
        formation: formation,
        layoutSource: 'manual',
        players: players,
        starters: slots,
        bench: [],
      ),
    );
  }

  static String slotPosition(List<int> shape, int x, int y) {
    if (y == shape.length - 1) return '0';
    if (y == shape.length - 2) {
      if (shape[y] >= 4 && x == 0) return '7';
      if (shape[y] >= 4 && x == shape[y] - 1) return '3';
      return '5';
    }
    if (y == 0) {
      if (shape[y] >= 3 && x == 0) return '27';
      if (shape[y] >= 3 && x == shape[y] - 1) return '23';
      return '25';
    }
    if (shape[y] >= 4) {
      if (x == 0) return shape[shape.length - 2] == 3 ? '8' : '16';
      if (x == shape[y] - 1) return shape[shape.length - 2] == 3 ? '2' : '12';
    }
    if (shape.length >= 5 && y == shape.length - 3 && shape[y] <= 2) {
      return '10';
    }
    if (shape.length >= 5 && y == 1 && shape[y] >= 3) {
      if (x == 0) return '16';
      if (x == shape[y] - 1) return '12';
    }
    return shape.length >= 5 && y == 1 ? '18' : '14';
  }

  OpponentLineup copy({
    FixtureFormation? squad,
    List<ManagerFixturePlayerPerformance>? performances,
  }) => OpponentLineup(
    squad: squad ?? this.squad,
    performances: performances ?? this.performances,
  );

  OpponentLineup rename(String id, String name) {
    if (!squad.players.containsKey(id)) return this;
    final players = {
      for (final e in squad.players.entries)
        e.key: Map<String, Object?>.of(e.value),
    };
    players[id]!['name'] = name.trim();
    final perfs = performances.map((p) => p.copy()).toList();
    for (final p in perfs) {
      for (final g in p.goalDetails.where((g) => g.assistantId == id)) {
        g.assistantName = name.trim();
      }
      for (final a in p.assistDetails.where((a) => a.goalscorerId == id)) {
        a.goalscorerName = name.trim();
      }
      for (final s in p.substitutionDetails.where(
        (s) => s.anotherPlayerId == id,
      )) {
        s.anotherPlayerName = name.trim();
      }
    }
    return copy(
      squad: squad.copy(players: players),
      performances: perfs,
    );
  }

  OpponentLineup withFormation(String label) {
    if (squad.formation.isEmpty) {
      final template = OpponentLineup.empty(formation: label).squad;
      final placed = squad
          .copy(formation: label)
          .withFormation(label, starting: squad.players.keys.take(11).toList());
      final used = placed.starters.values.toSet();
      return copy(
        squad: placed.copy(
          layoutSource: 'manual',
          players: {
            ...placed.players,
            for (final e in template.starters.entries)
              if (!used.contains(e.value)) e.key: template.players[e.key]!,
          },
          starters: {
            ...placed.starters,
            for (final e in template.starters.entries)
              if (!used.contains(e.value)) e.key: e.value,
          },
          bench: squad.players.keys
              .where((id) => !placed.starters.containsKey(id))
              .toList(),
        ),
      );
    }
    final next = squad.withFormation(label);
    final players = {
      for (final e in next.players.entries)
        e.key: Map<String, Object?>.of(e.value),
    };
    for (final e in next.starters.entries) {
      players[e.key]!['positionId'] = slotPosition(
        next.shape,
        e.value.x,
        e.value.y,
      );
    }
    return copy(squad: next.copy(players: players));
  }

  OpponentLineup withIdentity(
    String id, {
    required String name,
    String? photo,
  }) {
    final next = rename(id, name);
    if (!next.squad.players.containsKey(id)) return next;
    final players = {
      for (final e in next.squad.players.entries)
        e.key: Map<String, Object?>.of(e.value),
    };
    players[id]!['customAvatarFilePath'] = photo;
    return next.copy(squad: next.squad.copy(players: players));
  }

  OpponentLineup addReserve(String name) {
    final id = 'opponent-${const Uuid().v4()}';
    return copy(
      squad: squad.copy(
        players: {
          ...squad.players,
          id: {'id': id, 'name': name.trim(), 'positionId': null},
        },
        bench: [...squad.bench, id],
      ),
    );
  }

  OpponentLineup removeReserve(String id) {
    if (!squad.bench.contains(id)) return this;
    final perfs = performances
        .where((p) => p.playerInstanceId != id)
        .map((p) => p.copy())
        .toList();
    removePerformanceAndRelatedLinks(id, perfs);
    return copy(
      squad: squad.copy(
        players: Map.of(squad.players)..remove(id),
        bench: [...squad.bench]..remove(id),
      ),
      performances: perfs,
    );
  }

  OpponentLineup forNewMatch() =>
      OpponentLineup(squad: FixtureFormation.decode(squad.encode())!);

  OpponentLineup editPerformance(
    ManagerFixturePlayerPerformance edited, {
    bool deleted = false,
  }) {
    final all = performances
        .where((p) => p.playerInstanceId != edited.playerInstanceId)
        .map((p) => p.copy())
        .toList();
    if (deleted) {
      removePerformanceAndRelatedLinks(edited.playerInstanceId, all);
    } else {
      final value = edited.copy();
      all.add(value);
      final partners = {
        ...value.goalDetails.map((g) => g.assistantId),
        ...value.assistDetails.map((a) => a.goalscorerId),
      };
      for (final id in partners) {
        if (id != null &&
            id != value.playerInstanceId &&
            names[id]?.trim().isNotEmpty == true &&
            !all.any((p) => p.playerInstanceId == id)) {
          all.add(
            ManagerFixturePlayerPerformance(
              personId: edited.personId,
              fixtureId: edited.fixtureId,
              playerInstanceId: id,
            ),
          );
        }
      }
      syncSubstitutions(
        value,
        all,
        names[value.playerInstanceId] ?? '',
        (id) => ManagerFixturePlayerPerformance(
          personId: edited.personId,
          fixtureId: edited.fixtureId,
          playerInstanceId: id,
        ),
      );
      syncGoalsAndAssists(value, all, names[value.playerInstanceId] ?? '');
      value
        ..goalsCount = value.goalDetails.length
        ..assistsCount = value.assistDetails.length;
    }
    return copy(performances: all);
  }

  List<OpponentGoalDetails> get goals => [
    for (final p in performances) ...[
      for (final g in p.goalDetails)
        OpponentGoalDetails(
          id: g.id,
          scorerName: names[p.playerInstanceId] ?? '',
          minute: g.minute,
          addedMinute: g.addedMinute,
          type: g.type,
        ),
      for (final g in p.ownGoalDetails)
        OpponentGoalDetails(
          id: g.id,
          scorerName: names[p.playerInstanceId] ?? '',
          minute: g.minute,
          addedMinute: g.addedMinute,
          isOwnGoal: true,
        ),
    ],
  ];

  List<OpponentGoalDetails> mergeGoals(
    List<OpponentGoalDetails> recorded, {
    OpponentLineup? before,
  }) {
    final generated = goals,
        oldIds = before?.goals.map((g) => g.id).toSet() ?? <String>{};
    String key(OpponentGoalDetails g) =>
        '${g.scorerName.trim().toLowerCase()}:${g.minute}:${g.addedMinute ?? 0}:${g.isOwnGoal}';
    return [
      ...recorded.where(
        (g) =>
            !oldIds.contains(g.id) &&
            !generated.any(
              (n) => n.id == g.id || (n.minute != null && key(n) == key(g)),
            ),
      ),
      ...generated,
    ];
  }

  OpponentLineup withRecordedGoals(List<OpponentGoalDetails> recorded) {
    final all = performances.map((p) => p.copy()).toList();
    for (final id in squad.players.keys) {
      final name = names[id]!.trim().toLowerCase();
      if (name.isEmpty ||
          names.values.where((n) => n.trim().toLowerCase() == name).length !=
              1) {
        continue;
      }
      final linked = recorded
          .where((g) => g.scorerName.trim().toLowerCase() == name)
          .toList();
      final p =
          all.where((p) => p.playerInstanceId == id).firstOrNull ??
          ManagerFixturePlayerPerformance(
            personId: all.firstOrNull?.personId ?? '',
            fixtureId: all.firstOrNull?.fixtureId ?? '',
            playerInstanceId: id,
          );
      p.goalDetails = [
        for (final g in linked.where((g) => !g.isOwnGoal))
          PerformanceGoalDetails(
            id: g.id,
            minute: g.minute,
            addedMinute: g.addedMinute,
            type: g.type,
            goalLocation: p.goalDetails
                .where((old) => old.id == g.id)
                .firstOrNull
                ?.goalLocation,
            fieldLocation: p.goalDetails
                .where((old) => old.id == g.id)
                .firstOrNull
                ?.fieldLocation,
            assistantId: p.goalDetails
                .where((old) => old.id == g.id)
                .firstOrNull
                ?.assistantId,
            assistantName: p.goalDetails
                .where((old) => old.id == g.id)
                .firstOrNull
                ?.assistantName,
          ),
      ];
      p.ownGoalDetails = [
        for (final g in linked.where((g) => g.isOwnGoal))
          PerformanceTimeDetails(
            id: g.id,
            minute: g.minute,
            addedMinute: g.addedMinute,
          ),
      ];
      if (linked.isNotEmpty || all.contains(p)) {
        if (!all.contains(p)) {
          all.add(p);
        }
        syncGoalsAndAssists(p, all, names[id]!);
      }
    }
    return copy(performances: all);
  }

  String encode() => jsonEncode({
    'squad': jsonDecode(squad.encode()),
    'performances': [for (final p in performances) p.toMap()],
  });

  static OpponentLineup? decode(Object? raw) {
    try {
      final value = raw is String ? jsonDecode(raw) : raw;
      if (value is! Map) return null;
      final squad = FixtureFormation.decode(value['squad']);
      if (squad == null) return null;
      return OpponentLineup(
        squad: squad,
        performances: [
          for (final p in value['performances'] as List? ?? [])
            if (p is Map && squad.players.containsKey(p['playerInstanceId']))
              ManagerFixturePlayerPerformance.fromMap(
                Map<String, Object?>.from(p),
              ),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}
