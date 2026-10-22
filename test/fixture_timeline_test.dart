import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/utils/FixtureTimeline.dart';

ManagerFixturePlayerPerformance performance(
  String id, {
  List<PerformanceGoalDetails>? goals,
  List<PerformanceAssistDetails>? assists,
  List<PerformanceSubstitutionDetails>? subs,
  List<PerformanceTimeDetails>? ownGoals,
  List<PerformanceTimeDetails>? yellow,
  List<PerformanceTimeDetails>? red,
  List<PerformanceTimeDetails>? injuries,
  List<PerformanceTimeDetails>? missed,
}) => ManagerFixturePlayerPerformance(
  personId: 'career',
  fixtureId: 'match',
  playerInstanceId: id,
  goalDetails: goals,
  assistDetails: assists,
  substitutionDetails: subs,
  ownGoalDetails: ownGoals,
  yellowCardDetails: yellow,
  redCardDetails: red,
  injuryDetails: injuries,
  missedPenaltyDetails: missed,
);

List<FixtureTimelineEvent> timeline(
  List<ManagerFixturePlayerPerformance> players, {
  Map<String, Object?> fixture = const {},
}) => fixtureTimeline(
  fixture: fixture,
  performances: players,
  names: const {'a': 'Atacante', 'b': 'Meia', 'c': 'Reserva'},
);

void main() {
  test('Timeline orders every recorded event including stoppage time', () {
    final events = timeline([
      performance(
        'a',
        goals: [PerformanceGoalDetails(minute: 90, addedMinute: 3)],
        yellow: [PerformanceTimeDetails(minute: 45, addedMinute: 2)],
        red: [PerformanceTimeDetails(minute: 90, addedMinute: 4)],
        injuries: [PerformanceTimeDetails(minute: 62)],
        missed: [PerformanceTimeDetails(minute: 15)],
        ownGoals: [PerformanceTimeDetails(minute: 7)],
        assists: [PerformanceAssistDetails(goalscorerName: 'Outro')],
      ),
    ]);
    expect(events.map((e) => e.kind), [
      FixtureEventKind.ownGoal,
      FixtureEventKind.missedPenalty,
      FixtureEventKind.yellowCard,
      FixtureEventKind.injury,
      FixtureEventKind.goal,
      FixtureEventKind.redCard,
      FixtureEventKind.assist,
    ]);
    expect(events.last.minute, isNull);
    expect(events.first.ownTeam, isTrue);
    expect(events.first.scoresForOwnTeam, isFalse);
  });

  test(
    'An assist recorded separately becomes the goal detail in either order',
    () {
      final scorer = performance(
        'a',
        goals: [PerformanceGoalDetails(minute: 30)],
      );
      final passer = performance(
        'b',
        assists: [PerformanceAssistDetails(minute: 30, goalscorerId: 'a')],
      );
      for (final players in [
        [scorer, passer],
        [passer, scorer],
      ]) {
        final events = timeline(players);
        expect(events, hasLength(1));
        expect(events.single.kind, FixtureEventKind.goal);
        expect(events.single.detail, 'Meia');
      }
    },
  );

  test('Explicit assistants do not produce duplicate assist rows', () {
    final events = timeline([
      performance(
        'a',
        goals: [PerformanceGoalDetails(minute: 50, assistantId: 'b')],
      ),
      performance('b', assists: [PerformanceAssistDetails(minute: 50)]),
    ]);
    expect(events, hasLength(1));
    expect(events.single.detail, 'Meia');
  });

  test('Unknown times cannot merge otherwise independent events', () {
    final events = timeline([
      performance('a', goals: [PerformanceGoalDetails(assistantId: 'b')]),
      performance('b', assists: [PerformanceAssistDetails(goalscorerId: 'a')]),
    ]);
    expect(events, hasLength(2));
    expect(events.every((e) => e.minute == null), isTrue);
    expect(events.every((e) => e.homeScore == null), isTrue);
  });

  test(
    'Reciprocal substitution records merge into one incoming/outgoing pair',
    () {
      final events = timeline([
        performance(
          'a',
          subs: [
            PerformanceSubstitutionDetails(
              minute: 68,
              type: SubstitutionType.outGame,
              anotherPlayerId: 'c',
            ),
          ],
        ),
        performance(
          'c',
          subs: [
            PerformanceSubstitutionDetails(
              minute: 68,
              type: SubstitutionType.inGame,
              anotherPlayerId: 'a',
            ),
          ],
        ),
        performance(
          'b',
          subs: [
            PerformanceSubstitutionDetails(
              minute: 72,
              type: SubstitutionType.outGame,
            ),
          ],
        ),
      ]);
      expect(events, hasLength(2));
      expect(events.first.player, 'Reserva');
      expect(events.first.detail, 'Atacante');
      expect(events.first.incoming, isTrue);
      expect(events.last.player, 'Meia');
      expect(events.last.incoming, isFalse);
    },
  );

  test('An unspecified substitution does not invent entry or exit', () {
    final events = timeline([
      performance('a', subs: [PerformanceSubstitutionDetails(minute: 60)]),
    ]);
    expect(events.single.incoming, isNull);
    expect(events.single.player, 'Atacante');
  });

  for (final location in ['home', 'away']) {
    test(
      'Progression credits both own goals correctly with $location fixture',
      () {
        final events = timeline(
          [
            performance(
              'a',
              goals: [PerformanceGoalDetails(minute: 10)],
              ownGoals: [PerformanceTimeDetails(minute: 20)],
            ),
          ],
          fixture: {
            'location': location,
            'playerTeamScore': 2,
            'oppositeTeamScore': 2,
            'opponentGoalDetails':
                '[{"id":"og1","scorerName":"Adversário 1",'
                '"minute":30,"isOwnGoal":true},{"id":"g2",'
                '"scorerName":"Adversário 2","minute":40}]',
          },
        );
        expect(events.map((e) => e.ownTeam), [true, true, false, false]);
        expect(events.map((e) => e.scoresForOwnTeam), [
          true,
          false,
          true,
          false,
        ]);
        expect(
          events.map((e) => '${e.homeScore}-${e.awayScore}'),
          location == 'home'
              ? ['1-0', '1-1', '2-1', '2-2']
              : ['0-1', '1-1', '1-2', '2-2'],
        );
      },
    );
  }

  test('Partial goal records never invent goals or intermediate scores', () {
    final events = timeline(
      [
        performance('a', goals: [PerformanceGoalDetails(minute: 10)]),
      ],
      fixture: {'playerTeamScore': 3, 'oppositeTeamScore': 0},
    );
    expect(events, hasLength(1));
    expect(events.single.homeScore, isNull);
  });

  test('A goal without a minute also suppresses unreliable progression', () {
    final events = timeline(
      [
        performance('a', goals: [PerformanceGoalDetails()]),
      ],
      fixture: {'playerTeamScore': 1, 'oppositeTeamScore': 0},
    );
    expect(events.single.homeScore, isNull);
  });
}
