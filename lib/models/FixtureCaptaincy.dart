import 'dart:convert';

import 'ManagerFixturePlayerPerformance.dart';

class CaptainHandover {
  const CaptainHandover({
    required this.substitutionId,
    required this.fromPlayerId,
    this.playerId,
  });
  final String substitutionId, fromPlayerId;

  final String? playerId;
  Map<String, Object?> toMap() => {
    'substitutionId': substitutionId,
    'fromPlayerId': fromPlayerId,
    'playerId': playerId,
  };
}

typedef CaptainDeparture = ({
  String playerId,
  PerformanceSubstitutionDetails substitution,
  CaptainHandover? handover,
});

class FixtureCaptaincy {
  const FixtureCaptaincy({this.initialPlayerId, this.handovers = const []});
  final String? initialPlayerId;
  final List<CaptainHandover> handovers;
  bool get isRecorded => initialPlayerId != null;

  static FixtureCaptaincy decode(Object? raw) {
    try {
      final r = raw is String ? jsonDecode(raw) : raw;
      if (r is! Map) return const FixtureCaptaincy();
      return FixtureCaptaincy(
        initialPlayerId: r['initialPlayerId'] as String?,
        handovers: [
          for (final h in r['handovers'] as List? ?? [])
            if (h is Map &&
                h['substitutionId'] is String &&
                h['fromPlayerId'] is String)
              CaptainHandover(
                substitutionId: h['substitutionId'] as String,
                fromPlayerId: h['fromPlayerId'] as String,
                playerId: h['playerId'] as String?,
              ),
        ],
      );
    } catch (_) {
      return const FixtureCaptaincy();
    }
  }

  String? encode() => !isRecorded
      ? null
      : jsonEncode({
          'initialPlayerId': initialPlayerId,
          'handovers': [for (final h in handovers) h.toMap()],
        });

  static int? eventOrder(PerformanceTimeDetails event) => event.minute == null
      ? null
      : event.minute! * 1000 + (event.addedMinute ?? 0);
  static bool starter(ManagerFixturePlayerPerformance p) =>
      p.recordedStarted ??
      !p.substitutionDetails.any((s) => s.type == SubstitutionType.inGame);

  static List<String> eligible(
    Iterable<ManagerFixturePlayerPerformance> performances,
    CaptainDeparture departure,
  ) {
    final at = eventOrder(departure.substitution);
    return [
      for (final p in performances)
        if (p.playerInstanceId != departure.playerId &&
            !p.substitutionDetails.any(
              (s) =>
                  s.type == SubstitutionType.outGame &&
                  at != null &&
                  eventOrder(s) != null &&
                  eventOrder(s)! <= at,
            ) &&
            !p.substitutionDetails.any(
              (s) =>
                  s.type == SubstitutionType.inGame &&
                  at != null &&
                  eventOrder(s) != null &&
                  eventOrder(s)! > at,
            ))
          p.playerInstanceId,
    ];
  }

  List<CaptainDeparture> departures(
    Iterable<ManagerFixturePlayerPerformance> performances,
  ) {
    final all = performances.toList();
    final result = <CaptainDeparture>[];
    final visited = <String>{};
    var current = initialPlayerId;
    int? previousOrder;
    while (current != null && visited.add(current)) {
      final p = all.where((p) => p.playerInstanceId == current).firstOrNull;
      if (p == null) break;
      final outs =
          p.substitutionDetails
              .where((s) => s.type == SubstitutionType.outGame)
              .toList()
            ..sort(
              (a, b) => (eventOrder(a) ?? 1 << 30).compareTo(
                eventOrder(b) ?? 1 << 30,
              ),
            );
      if (outs.isEmpty) break;
      final out = outs.first;
      final order = eventOrder(out);
      if (order != null && previousOrder != null && order < previousOrder) {
        break;
      }
      final h = handovers
          .where((h) => h.fromPlayerId == current && h.substitutionId == out.id)
          .firstOrNull;
      final departure = (playerId: current, substitution: out, handover: h);
      final valid =
          h?.playerId == null ||
          (!visited.contains(h!.playerId) &&
              eligible(all, departure).contains(h.playerId));
      result.add((
        playerId: current,
        substitution: out,
        handover: valid ? h : null,
      ));
      if (h == null || !valid) break;
      current = h.playerId;
      previousOrder = order ?? previousOrder;
    }
    return result;
  }

  CaptainDeparture? pending(
    Iterable<ManagerFixturePlayerPerformance> performances,
  ) => departures(performances).where((d) => d.handover == null).firstOrNull;

  List<String> candidates(
    Iterable<ManagerFixturePlayerPerformance> performances,
    CaptainDeparture departure,
  ) {
    final earlier = departures(performances)
        .takeWhile((d) => d.substitution.id != departure.substitution.id)
        .map((d) => d.playerId)
        .toSet();
    return eligible(
      performances,
      departure,
    ).where((id) => !earlier.contains(id)).toList();
  }

  FixtureCaptaincy assign(CaptainDeparture departure, String? playerId) =>
      FixtureCaptaincy(
        initialPlayerId: initialPlayerId,
        handovers: [
          ...handovers.where(
            (h) => h.substitutionId != departure.substitution.id,
          ),
          CaptainHandover(
            substitutionId: departure.substitution.id,
            fromPlayerId: departure.playerId,
            playerId: playerId,
          ),
        ],
      );

  Set<String> players(Iterable<ManagerFixturePlayerPerformance> performances) =>
      {
        ?initialPlayerId,
        for (final d in departures(performances))
          if (d.handover?.playerId != null) d.handover!.playerId!,
      };

  FixtureCaptaincy reconciled(
    Iterable<ManagerFixturePlayerPerformance> performances,
  ) {
    final all = performances.toList();
    if (!all.any((p) => p.playerInstanceId == initialPlayerId && starter(p))) {
      return const FixtureCaptaincy();
    }
    return FixtureCaptaincy(
      initialPlayerId: initialPlayerId,
      handovers: [
        for (final d in departures(all))
          if (d.handover != null) d.handover!,
      ],
    );
  }
}
