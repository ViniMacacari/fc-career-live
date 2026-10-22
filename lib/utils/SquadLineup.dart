import 'package:sqflite/sqflite.dart';

import 'FootballFormations.dart';

typedef SquadSlot = ({int x, int y});

class SquadLineup {
  static Future<void> ensureSchema(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS SquadLineup(
      personId TEXT NOT NULL, seasonId TEXT NOT NULL, formation TEXT NOT NULL,
      PRIMARY KEY(personId, seasonId))''');

  static Future<String> ensure(
    DatabaseExecutor db,
    String personId,
    String seasonId, {
    bool materialize = true,
  }) async {
    await ensureSchema(db);
    final saved =
        (await db.query(
              'SquadLineup',
              where: 'personId = ? AND seasonId = ?',
              whereArgs: [personId, seasonId],
            )).firstOrNull?['formation']
            as String?;
    if (!materialize && footballFormations.containsKey(saved)) return saved!;
    final rows = await db.rawQuery(
      '''
      SELECT tp.id, tp.x, tp.y, cp.positionId FROM TeamPlayer tp
      LEFT JOIN CustomCreatedPlayer cp ON cp.id = tp.playerId AND cp.personId = tp.personId
      WHERE tp.personId = ? AND tp.seasonId = ? AND tp.isBench = 0
      ORDER BY tp.rowid''',
      [personId, seasonId],
    );
    final formation = footballFormations.containsKey(saved)
        ? saved!
        : inferSquadFormation(rows);
    if (saved != formation) await save(db, personId, seasonId, formation);
    if (!materialize || rows.length > 11) return formation;
    final slots = squadPositions(rows, formation);
    for (final row in rows) {
      if (row['x'] != null && row['y'] != null) continue;
      final slot = slots['${row['id']}'];
      if (slot != null && (row['x'] != slot.x || row['y'] != slot.y)) {
        await db.update(
          'TeamPlayer',
          {'x': slot.x, 'y': slot.y},
          where: 'id = ? AND personId = ? AND seasonId = ?',
          whereArgs: [row['id'], personId, seasonId],
        );
      }
    }
    return formation;
  }

  static Future<void> save(
    DatabaseExecutor db,
    String personId,
    String seasonId,
    String formation,
  ) async {
    if (!footballFormations.containsKey(formation)) {
      throw ArgumentError.value(formation, 'formation');
    }
    await ensureSchema(db);
    await db.insert('SquadLineup', {
      'personId': personId,
      'seasonId': seasonId,
      'formation': formation,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

String inferSquadFormation(List<Map<String, Object?>> players) {
  final located = players.where((p) => p['x'] is int && p['y'] is int).toList();
  if (located.isEmpty) {
    final inferred = inferFootballFormation(
      players.map((p) => p['positionId'] as String?),
    );
    return footballFormations.containsKey(inferred) ? inferred! : '4-3-3';
  }
  final counts = <int, int>{};
  for (final row in located) {
    final y = row['y'] as int;
    counts[y] = (counts[y] ?? 0) + 1;
  }
  String best = '4-3-3';
  int? bestCost;
  for (final entry in footballFormations.entries) {
    final shape = entry.value;
    if (located.any((p) {
      final x = p['x'] as int, y = p['y'] as int;
      return y < 0 || y >= shape.length || x < 0 || x >= shape[y];
    })) {
      continue;
    }
    var cost = 0;
    for (var y = 0; y < shape.length; y++) {
      final missing = shape[y] - (counts[y] ?? 0);
      cost += missing * missing * 100;
    }
    for (final row in located) {
      cost += footballPositionCost(
        row['positionId'] as String?,
        footballSlotPosition(shape, row['x'] as int, row['y'] as int),
      );
    }
    if (bestCost == null || cost < bestCost) {
      best = entry.key;
      bestCost = cost;
    }
  }
  return best;
}

Map<String, SquadSlot> squadPositions(
  List<Map<String, Object?>> players,
  String formation, {
  bool preserve = true,
}) {
  final shape = footballFormationShape(formation);
  final result = <String, SquadSlot>{};
  if (preserve) {
    for (final row in players) {
      final x = row['x'], y = row['y'];
      if (x is int &&
          y is int &&
          y >= 0 &&
          y < shape.length &&
          x >= 0 &&
          x < shape[y] &&
          !result.containsValue((x: x, y: y))) {
        result['${row['id']}'] = (x: x, y: y);
      }
    }
  }
  final slots = [
    for (var y = 0; y < shape.length; y++)
      for (var x = 0; x < shape[y]; x++)
        if (!result.containsValue((x: x, y: y))) (x: x, y: y),
  ];
  final remaining = players
      .where((p) => !result.containsKey('${p['id']}'))
      .take(slots.length)
      .toList();
  if (remaining.isEmpty) return result;
  final n = slots.length;
  int cost(int player, int slot) {
    if (player >= remaining.length) return 0;
    final row = remaining[player], s = slots[slot];
    final role = footballSlotPosition(shape, s.x, s.y);
    final fit = footballPositionCost(row['positionId'] as String?, role);
    final oldX = row['x'], oldY = row['y'];
    final distance = oldX is int && oldY is int
        ? (oldX - s.x).abs() + (oldY - s.y).abs()
        : 0;
    return fit * 100 + distance;
  }

  final u = List.filled(n + 1, 0), v = List.filled(n + 1, 0);
  final p = List.filled(n + 1, 0), way = List.filled(n + 1, 0);
  for (var i = 1; i <= n; i++) {
    p[0] = i;
    var j0 = 0;
    final minv = List.filled(n + 1, 1 << 30);
    final used = List.filled(n + 1, false);
    do {
      used[j0] = true;
      final i0 = p[j0];
      var delta = 1 << 30, j1 = 0;
      for (var j = 1; j <= n; j++) {
        if (used[j]) continue;
        final current = cost(i0 - 1, j - 1) - u[i0] - v[j];
        if (current < minv[j]) {
          minv[j] = current;
          way[j] = j0;
        }
        if (minv[j] < delta) {
          delta = minv[j];
          j1 = j;
        }
      }
      for (var j = 0; j <= n; j++) {
        if (used[j]) {
          u[p[j]] += delta;
          v[j] -= delta;
        } else {
          minv[j] -= delta;
        }
      }
      j0 = j1;
    } while (p[j0] != 0);
    do {
      final j1 = way[j0];
      p[j0] = p[j1];
      j0 = j1;
    } while (j0 != 0);
  }
  for (var j = 1; j <= n; j++) {
    if (p[j] <= remaining.length) {
      result['${remaining[p[j] - 1]['id']}'] = slots[j - 1];
    }
  }
  return result;
}
