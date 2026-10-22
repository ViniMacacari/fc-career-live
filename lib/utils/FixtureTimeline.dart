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
