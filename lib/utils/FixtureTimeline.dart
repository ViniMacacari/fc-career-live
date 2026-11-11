import 'dart:math';

import '../models/ManagerFixture.dart';
import '../models/ManagerFixturePlayerPerformance.dart';
import '../models/OpponentLineup.dart';

enum FixtureEventKind {
  goal,
  ownGoal,
  yellowCard,
  redCard,
  substitution,
  injury,
  missedPenalty,
  assist,
}

class FixtureTimelineEvent {
  FixtureTimelineEvent({
    required this.id,
    required this.kind,
    required this.player,
    required this.ownTeam,
    this.minute,
    this.addedMinute,
    this.detail,
    this.incoming,
    this.penalty = false,
    this.inferred = false,
    this.goalTypes = const [],
  });
  final String id, player;
  final FixtureEventKind kind;
  final bool ownTeam, penalty, inferred;
  final int? minute, addedMinute;
  final String? detail;
  final bool? incoming;
  final List<GoalType> goalTypes;
  int? homeScore, awayScore;
  bool get scores =>
      kind == FixtureEventKind.goal || kind == FixtureEventKind.ownGoal;
  bool get scoresForOwnTeam =>
      kind == FixtureEventKind.ownGoal ? !ownTeam : ownTeam;
  FixtureTimelineEvent copyWith({
    int? minute,
    String? detail,
    bool? inferred,
  }) => FixtureTimelineEvent(
    id: id,
    kind: kind,
    player: player,
    ownTeam: ownTeam,
    minute: minute ?? this.minute,
    addedMinute: addedMinute,
    detail: detail ?? this.detail,
    incoming: incoming,
    penalty: penalty,
    inferred: inferred ?? this.inferred,
    goalTypes: goalTypes,
  );
}

List<FixtureTimelineEvent> fixtureTimeline({
  required Map<String, Object?> fixture,
  required List<ManagerFixturePlayerPerformance> performances,
  required Map<String, String> names,
}) {
  final events = <FixtureTimelineEvent>[];
  final substitutions = <String, FixtureTimelineEvent>{};
  final assists = <String>{};
  final linkedAssists = <String>{};
  String name(String id) => names[id] ?? id;
  for (final p in performances) {
    final player = name(p.playerInstanceId);
    for (final g in p.goalDetails) {
      String? recordedAssistant;
      if (g.minute != null) {
        for (final passer in performances) {
          final linked = passer.assistDetails
              .where(
                (a) =>
                    a.minute == g.minute &&
                    (a.addedMinute ?? 0) == (g.addedMinute ?? 0) &&
                    (a.goalscorerId == p.playerInstanceId ||
                        a.goalscorerName == player),
              )
              .firstOrNull;
          if (linked != null) {
            recordedAssistant = name(passer.playerInstanceId);
            linkedAssists.add(linked.id);
            break;
          }
        }
      }
      final assistant =
          g.assistantName ??
          (g.assistantId == null ? recordedAssistant : name(g.assistantId!));
      events.add(
        FixtureTimelineEvent(
          id: g.id,
          kind: FixtureEventKind.goal,
          player: player,
          ownTeam: true,
          minute: g.minute,
          addedMinute: g.addedMinute,
          detail: assistant,
          penalty: g.isPenalty,
          goalTypes: g.type,
        ),
      );
      if (g.assistantId != null && g.minute != null) {
        assists.add('${g.assistantId}:${g.minute}:${g.addedMinute ?? 0}');
      }
      if (assistant != null && g.minute != null) {
        assists.add('$assistant:${g.minute}:${g.addedMinute ?? 0}');
      }
    }
    for (final a in p.assistDetails) {
      events.add(
        FixtureTimelineEvent(
          id: a.id,
          kind: FixtureEventKind.assist,
          player: player,
          ownTeam: true,
          minute: a.minute,
          addedMinute: a.addedMinute,
          detail:
              a.goalscorerName ??
              (a.goalscorerId == null ? null : name(a.goalscorerId!)),
        ),
      );
    }
    for (final (list, kind) in [
      (p.ownGoalDetails, FixtureEventKind.ownGoal),
      (p.yellowCardDetails, FixtureEventKind.yellowCard),
      (p.redCardDetails, FixtureEventKind.redCard),
      (p.injuryDetails, FixtureEventKind.injury),
      (p.missedPenaltyDetails, FixtureEventKind.missedPenalty),
    ]) {
      for (final e in list) {
        events.add(
          FixtureTimelineEvent(
            id: e.id,
            kind: kind,
            player: player,
            ownTeam: true,
            minute: e.minute,
            addedMinute: e.addedMinute,
          ),
        );
      }
    }
    for (final s in p.substitutionDetails) {
      if (s.type == null) {
        events.add(
          FixtureTimelineEvent(
            id: s.id,
            inferred: s.inferred,
            kind: FixtureEventKind.substitution,
            player: player,
            ownTeam: true,
            minute: s.minute,
            addedMinute: s.addedMinute,
          ),
        );
        continue;
      }
      final other =
          s.anotherPlayerName ??
          (s.anotherPlayerId == null ? null : name(s.anotherPlayerId!));
      final isIn = s.type == SubstitutionType.inGame;
      final incoming = isIn ? player : other, outgoing = isIn ? other : player;
      final pair = [incoming ?? '', outgoing ?? '']..sort();
      final key = s.minute == null
          ? s.id
          : '${s.minute}:${s.addedMinute ?? 0}:${pair.join('|')}';
      substitutions.putIfAbsent(
        key,
        () => FixtureTimelineEvent(
          id: s.id,
          inferred: s.inferred,
          kind: FixtureEventKind.substitution,
          player: incoming ?? outgoing ?? player,
          detail: incoming == null ? null : outgoing,
          incoming: incoming == null ? false : true,
          ownTeam: true,
          minute: s.minute,
          addedMinute: s.addedMinute,
        ),
      );
    }
  }
  events.removeWhere(
    (e) =>
        e.kind == FixtureEventKind.assist &&
        (linkedAssists.contains(e.id) ||
            assists.contains('${e.player}:${e.minute}:${e.addedMinute ?? 0}')),
  );
  events.addAll(substitutions.values);
  final opponent = OpponentLineup.decode(fixture['opponentLineup']);
  final opponentEvents = opponent == null
      ? <FixtureTimelineEvent>[]
      : fixtureTimeline(
          fixture: const {},
          performances: opponent.performances,
          names: opponent.names,
        );
  for (final e in opponentEvents) {
    events.add(
      FixtureTimelineEvent(
        id: 'opponent:${e.id}',
        kind: e.kind,
        player: e.player,
        ownTeam: false,
        minute: e.minute,
        addedMinute: e.addedMinute,
        detail: e.detail,
        incoming: e.incoming,
        inferred: e.inferred,
        penalty: e.penalty,
        goalTypes: e.goalTypes,
      ),
    );
  }
  for (final g in decodeOpponentGoals(fixture['opponentGoalDetails'])) {
    if (opponentEvents.any(
      (e) =>
          e.scores &&
          (e.id == g.id ||
              (g.minute != null &&
                  e.player.trim().toLowerCase() ==
                      g.scorerName.trim().toLowerCase() &&
                  e.minute == g.minute &&
                  (e.addedMinute ?? 0) == (g.addedMinute ?? 0) &&
                  (e.kind == FixtureEventKind.ownGoal) == g.isOwnGoal)),
    )) {
      continue;
    }
    events.add(
      FixtureTimelineEvent(
        id: g.id,
        kind: g.isOwnGoal ? FixtureEventKind.ownGoal : FixtureEventKind.goal,
        player: g.scorerName.trim().isEmpty ? 'Adversário' : g.scorerName,
        ownTeam: false,
        minute: g.minute,
        addedMinute: g.addedMinute,
        penalty: g.type.contains(GoalType.penalty),
        goalTypes: g.type,
      ),
    );
  }
  _placeOpponentEvents(events, '${fixture['id'] ?? ''}');
  events.sort((a, b) {
    final byMinute = (a.minute ?? 999).compareTo(b.minute ?? 999);
    if (byMinute != 0) return byMinute;
    final byAdded = (a.addedMinute ?? 0).compareTo(b.addedMinute ?? 0);
    return byAdded != 0 ? byAdded : a.kind.index.compareTo(b.kind.index);
  });
  final ownGoals = events.where((e) => e.scores && e.scoresForOwnTeam).length;
  final otherGoals = events
      .where((e) => e.scores && !e.scoresForOwnTeam)
      .length;
  if (ownGoals == fixture['playerTeamScore'] &&
      otherGoals == fixture['oppositeTeamScore'] &&
      events.where((e) => e.scores).every((e) => e.minute != null)) {
    var own = 0, other = 0;
    final away = fixture['location'] == 'away';
    for (final e in events.where((e) => e.scores)) {
      if (e.scoresForOwnTeam) {
        own++;
      } else {
        other++;
      }
      e.homeScore = away ? other : own;
      e.awayScore = away ? own : other;
    }
  }
  return events;
}

int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

void _placeOpponentEvents(List<FixtureTimelineEvent> events, String seed) {
  String key(String value) => value.trim().toLowerCase();
  bool open(FixtureTimelineEvent e) => !e.ownTeam && e.minute == null;
  final pairs = <String>{};
  events.removeWhere((e) {
    if (!open(e) ||
        e.kind != FixtureEventKind.substitution ||
        e.detail == null) {
      return false;
    }
    final pair = [key(e.player), key(e.detail!)]..sort();
    return !pairs.add(pair.join('|'));
  });
  if (!events.any(open)) return;
  final usedGoalMinutes = <int>{
    for (final e in events)
      if (e.scores && e.minute != null) e.minute!,
  };
  void replace(FixtureTimelineEvent from, FixtureTimelineEvent to) =>
      events[events.indexOf(from)] = to;
  int pick(FixtureTimelineEvent e, int lo, int hi, {bool spread = false}) {
    lo = lo.clamp(1, 90);
    hi = hi.clamp(lo, 90);
    final random = Random(_stableHash('$seed:${e.id}'));
    var minute = lo + random.nextInt(hi - lo + 1);
    for (var i = 0; spread && i < 8 && usedGoalMinutes.contains(minute); i++) {
      minute = lo + random.nextInt(hi - lo + 1);
    }
    return minute;
  }

  bool involves(FixtureTimelineEvent e, String player) =>
      key(e.player) == key(player) ||
      ((e.kind == FixtureEventKind.substitution ||
              e.kind == FixtureEventKind.goal) &&
          e.detail != null &&
          key(e.detail!) == key(player));
  Iterable<int> minutesOf(String player) => events
      .where((e) => !e.ownTeam && e.minute != null && involves(e, player))
      .map((e) => e.minute!);
  int last(String player) => minutesOf(player).fold(0, max);
  int first(String player) => minutesOf(player).fold(91, min);
  String? entering(FixtureTimelineEvent s) =>
      s.incoming == true ? s.player : null;
  String? leaving(FixtureTimelineEvent s) => s.incoming == true
      ? s.detail
      : s.incoming == false
      ? s.player
      : null;
  (int, int) window(String player) {
    var start = 1, end = 90;
    for (final e in events.where((e) => !e.ownTeam && e.minute != null)) {
      final minute = e.minute!;
      if (e.kind == FixtureEventKind.substitution) {
        final inName = entering(e), outName = leaving(e);
        if (inName != null && key(inName) == key(player)) {
          start = max(start, minute + 1);
        }
        if (outName != null && key(outName) == key(player)) {
          end = min(end, minute);
        }
      } else if (e.kind == FixtureEventKind.redCard &&
          key(e.player) == key(player)) {
        end = min(end, minute);
      }
    }
    start = min(start, 90);
    return (start, max(start, end));
  }

  for (final s
      in events
          .where((e) => open(e) && e.kind == FixtureEventKind.substitution)
          .toList()) {
    final inName = entering(s), outName = leaving(s);
    final after = outName == null ? 0 : last(outName),
        before = inName == null ? 91 : first(inName);
    var lo = max(46, after + 1), hi = min(88, before - 1);
    if (lo > hi) {
      lo = after + 1;
      hi = before - 1;
    }
    replace(s, s.copyWith(minute: pick(s, lo, hi), inferred: true));
  }

  for (final a
      in events
          .where((e) => open(e) && e.kind == FixtureEventKind.assist)
          .toList()) {
    final goals = events
        .where((e) => !e.ownTeam && e.kind == FixtureEventKind.goal)
        .toList();
    bool forScorer(FixtureTimelineEvent g) =>
        a.detail != null && key(g.player) == key(a.detail!);
    if (goals.any(
      (g) =>
          g.minute == null &&
          g.detail != null &&
          key(g.detail!) == key(a.player) &&
          (a.detail == null || forScorer(g)),
    )) {
      events.remove(a);
      continue;
    }
    final (start, end) = window(a.player);
    final options = goals
        .where(
          (g) =>
              g.detail == null &&
              key(g.player) != key(a.player) &&
              (g.minute == null || (g.minute! >= start && g.minute! <= end)),
        )
        .toList();
    if (options.isEmpty) continue;
    final named = options.where(forScorer).toList();
    final pool = named.isEmpty ? options : named;
    final target =
        pool[Random(_stableHash('$seed:${a.id}')).nextInt(pool.length)];
    replace(target, target.copyWith(detail: a.player));
    events.remove(a);
  }

  for (final e
      in events
          .where(
            (e) =>
                open(e) &&
                e.kind != FixtureEventKind.redCard &&
                e.kind != FixtureEventKind.assist,
          )
          .toList()) {
    var (start, end) = window(e.player);
    if (e.kind == FixtureEventKind.goal && e.detail != null) {
      final (assistStart, assistEnd) = window(e.detail!);
      if (max(start, assistStart) <= min(end, assistEnd)) {
        start = max(start, assistStart);
        end = min(end, assistEnd);
      }
    }
    if (e.kind == FixtureEventKind.injury && end < 90) {
      start = max(start, end - 4);
    }
    final minute = pick(e, start, end, spread: e.scores);
    if (e.scores) usedGoalMinutes.add(minute);
    replace(e, e.copyWith(minute: minute, inferred: true));
  }

  for (final e
      in events
          .where((e) => open(e) && e.kind == FixtureEventKind.redCard)
          .toList()) {
    final (start, end) = window(e.player);
    final yellows =
        events
            .where(
              (y) =>
                  !y.ownTeam &&
                  y.kind == FixtureEventKind.yellowCard &&
                  y.minute != null &&
                  key(y.player) == key(e.player),
            )
            .map((y) => y.minute!)
            .toList()
          ..sort();
    final minute = yellows.length >= 2
        ? yellows.last
        : pick(e, min(end, max(start, last(e.player) + 1)), end);
    replace(e, e.copyWith(minute: minute, inferred: true));
  }
}
