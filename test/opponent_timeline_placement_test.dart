import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/models/ManagerFixture.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/models/OpponentLineup.dart';
import 'package:mcmanager/utils/FixtureTimeline.dart';

OpponentLineup namedTeam() {
  var lineup = OpponentLineup.empty();
  for (var i = 0; i < 11; i++) {
    lineup = lineup.rename(lineup.startingIds[i], 'Adversário $i');
  }
  return lineup.addReserve('Reserva');
}

ManagerFixturePlayerPerformance perf(
  String id, {
  List<PerformanceGoalDetails>? goals,
  List<PerformanceAssistDetails>? assists,
  List<PerformanceSubstitutionDetails>? subs,
  List<PerformanceTimeDetails>? yellow,
  List<PerformanceTimeDetails>? red,
  List<PerformanceTimeDetails>? injuries,
}) => ManagerFixturePlayerPerformance(
  personId: 'career',
  fixtureId: 'match',
  playerInstanceId: id,
  goalDetails: goals,
  assistDetails: assists,
  substitutionDetails: subs,
  yellowCardDetails: yellow,
  redCardDetails: red,
  injuryDetails: injuries,
);

List<FixtureTimelineEvent> build(
  OpponentLineup lineup, {
  String id = 'fixture-1',
  int own = 0,
  int other = 0,
  List<OpponentGoalDetails>? goals,
  List<ManagerFixturePlayerPerformance> performances = const [],
}) => fixtureTimeline(
  fixture: {
    'id': id,
    'location': 'home',
    'playerTeamScore': own,
    'oppositeTeamScore': other,
    'opponentLineup': lineup.encode(),
    'opponentGoalDetails': encodeOpponentGoals(goals ?? lineup.goals),
  },
  performances: performances,
  names: const {'a': 'Atacante'},
);

void main() {
  test('An opponent assist without minute joins a manual opponent goal', () {
    var lineup = namedTeam();
    final passer = lineup.startingIds[5];
    lineup = lineup.editPerformance(
      perf(passer, assists: [PerformanceAssistDetails(id: 'as')]),
    );
    final events = build(
      lineup,
      other: 1,
      goals: [
        OpponentGoalDetails(id: 'g', scorerName: 'Artilheiro', minute: 10),
      ],
    );
    final goal = events.singleWhere((e) => e.kind == FixtureEventKind.goal);
    expect(goal.minute, 10);
    expect(goal.detail, 'Adversário 5');
    expect(events.where((e) => e.kind == FixtureEventKind.assist), isEmpty);
    expect(goal.awayScore, 1);
  });

  test('Opponent events without minute receive stable coherent moments', () {
    var lineup = namedTeam();
    final scorer = lineup.startingIds[9], booked = lineup.startingIds[3];
    final leaving = lineup.startingIds[7], reserve = lineup.squad.bench.single;
    lineup = lineup
        .editPerformance(
          perf(scorer, goals: [PerformanceGoalDetails(id: 'g1')]),
        )
        .editPerformance(
          perf(reserve, goals: [PerformanceGoalDetails(id: 'g2')]),
        )
        .editPerformance(
          perf(
            booked,
            yellow: [
              PerformanceTimeDetails(id: 'y1'),
              PerformanceTimeDetails(id: 'y2'),
            ],
            red: [PerformanceTimeDetails(id: 'r')],
          ),
        )
        .editPerformance(
          perf(
            leaving,
            injuries: [PerformanceTimeDetails(id: 'i')],
            subs: [
              PerformanceSubstitutionDetails(
                id: 's',
                type: SubstitutionType.outGame,
                anotherPlayerId: reserve,
                anotherPlayerName: 'Reserva',
              ),
            ],
          ),
        );
    for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) {
      final events = build(lineup, id: id, other: 2);
      final opponent = events.where((e) => !e.ownTeam).toList();
      expect(opponent.every((e) => e.minute != null && e.inferred), isTrue);
      expect(
        opponent.where((e) => e.kind == FixtureEventKind.substitution),
        hasLength(1),
      );
      final sub = opponent.singleWhere(
        (e) => e.kind == FixtureEventKind.substitution,
      );
      final injury = opponent.singleWhere(
        (e) => e.kind == FixtureEventKind.injury,
      );
      final reserveGoal = opponent.singleWhere(
        (e) => e.kind == FixtureEventKind.goal && e.player == 'Reserva',
      );
      expect(injury.minute, lessThanOrEqualTo(sub.minute!));
      expect(reserveGoal.minute, greaterThan(sub.minute!));
      final yellows = opponent
          .where((e) => e.kind == FixtureEventKind.yellowCard)
          .map((e) => e.minute!);
      final red = opponent.singleWhere(
        (e) => e.kind == FixtureEventKind.redCard,
      );
      expect(red.minute, yellows.reduce((a, b) => a > b ? a : b));
      expect(events.lastWhere((e) => e.scores).awayScore, 2);
      expect(
        build(lineup, id: id, other: 2).map((e) => e.minute),
        events.map((e) => e.minute),
      );
    }
  });

  test('Own team events without minute stay without minute', () {
    final events = build(
      namedTeam(),
      own: 1,
      performances: [
        perf('a', goals: [PerformanceGoalDetails()]),
      ],
    );
    expect(events.single.minute, isNull);
  });
}
