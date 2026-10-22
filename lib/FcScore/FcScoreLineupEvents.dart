import '../models/ManagerFixturePlayerPerformance.dart';
import 'FcScoreApi.dart';
import 'FcScoreModels.dart' show fcPlayerName;

void fcApplySubstitutions(
  List<FcJson> remote,
  List<ManagerFixturePlayerPerformance> performances,
  Map<String, String> ids,
) {
  final byId = {for (final p in performances) p.playerInstanceId: p};
  final duration = remote
      .map((p) => fcInt(fcObject(p['stats'])['minutesPlayed']) ?? 0)
      .fold<int>(0, (a, b) => a > b ? a : b);
  if (duration < 45 || duration > 150) return;
  final outgoing = <int, List<String>>{}, incoming = <int, List<String>>{};
  for (final p in remote.where((p) => p['played'] == true)) {
    final id = ids[fcId(p['id'])], stats = fcObject(p['stats']);
    final minutes = fcInt(stats['minutesPlayed']);
    if (id == null ||
        !byId.containsKey(id) ||
        minutes == null ||
        minutes <= 0 ||
        minutes >= duration) {
      continue;
    }
    if (p['started'] == true && (fcInt(stats['redDismissals']) ?? 0) == 0) {
      outgoing.putIfAbsent(minutes, () => []).add(id);
    } else if (p['started'] != true) {
      incoming.putIfAbsent(duration - minutes, () => []).add(id);
    }
  }
  for (final entry in outgoing.entries) {
    final ins = incoming[entry.key] ?? [];
    if (ins.length != entry.value.length) continue;
    for (final (players, type, others) in [
      (entry.value, SubstitutionType.outGame, ins),
      (ins, SubstitutionType.inGame, entry.value),
    ]) {
      for (final id in players) {
        final p = byId[id]!;
        if (p.substitutionDetails.any((s) => s.type == type)) continue;
        final end = duration > 105 ? 120 : 90;
        final base = entry.key > end ? end : entry.key;
        final other = others.length == 1 ? others.single : null;
        p.substitutionDetails.add(
          PerformanceSubstitutionDetails(
            id: 'fc-sub:$id:${type.name}:${entry.key}',
            minute: base,
            addedMinute: entry.key > base ? entry.key - base : null,
            type: type,
            anotherPlayerId: other,
            anotherPlayerName: other == null
                ? null
                : fcPlayerName(
                    fcObject(
                      remote
                          .where((r) => ids[fcId(r['id'])] == other)
                          .firstOrNull?['profile'],
                    ),
                  ),
            inferred: true,
          ),
        );
      }
    }
  }
}
