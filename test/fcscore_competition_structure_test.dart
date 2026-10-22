import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/FcScore/FcScoreCompetitionStructure.dart';

FcJson row(int id, {int played = 0, int goals = 0}) => {
  'team': {'id': id},
  'played': played,
  'goalsFor': goals,
};
FcJson group(List<FcJson> rows, {String code = 'G1'}) => {
  'code': code,
  'rows': rows,
};
FcJson stage(String name, List<FcJson> groups, {String? code}) => {
  'id': name,
  'name': name,
  'code': code,
  'groups': groups,
};
FcJson game(
  String stage,
  int home,
  int away, {
  String date = '2028-06-01',
  int? homeGoals,
  int? awayGoals,
  int? homePenalties,
  int? awayPenalties,
}) => {
  'stage': stage,
  'date': date,
  'played': homeGoals != null,
  'home': {
    'team': {'id': home},
    'goals': homeGoals,
    'penalties': homePenalties,
  },
  'away': {
    'team': {'id': away},
    'goals': awayGoals,
    'penalties': awayPenalties,
  },
};

void main() {
  test(
    'Setup and draw stages are hidden even when their copied rows have games',
    () {
      final stages = fcCompetitionStages(
        {
          'stages': [
            stage('Setup Stage', [
              group([row(1, played: 6), row(2, played: 6)]),
            ]),
            stage('Quarter-Finals Draw', [
              group([row(1), row(2)]),
            ]),
            stage('Round 1', [
              group([row(1, played: 1), row(2, played: 1)]),
            ]),
          ],
        },
        [game('Round 1', 1, 2, homeGoals: 2, awayGoals: 0)],
      );
      expect(stages, hasLength(1));
      expect(stages.single.name, '1ª fase');
      expect(stages.single.kind, FcStageKind.knockout);
      expect(stages.single.ties, hasLength(1));
    },
  );
  test(
    'Unplayed internal stages are hidden but actual future groups remain',
    () {
      final stages = fcCompetitionStages({
        'stages': [
          stage('Q6', [
            group([row(1), row(2), row(3)]),
          ], code: 'Q6'),
          stage('Group Stage', [
            group([row(1), row(2), row(3), row(4)]),
          ]),
          stage('Quarter-Finals', [
            group([row(1), row(2)]),
          ]),
        ],
      }, []);
      expect(stages.map((s) => s.name), ['Fase de grupos', 'Quartas de final']);
      expect(stages.first.kind, FcStageKind.groups);
      expect(stages.last.kind, FcStageKind.knockout);
      expect(stages.last.ties.single.score('1'), isNull);
    },
  );
  test('Two-team cup groups are confrontations while a partial league stays a table', () {
    final stages = fcCompetitionStages({
      'stages': [
        stage('League', [
          group([row(1), row(2)]),
        ]),
        stage('Group Stage', [
          group([row(1), row(2)]),
        ]),
      ],
    }, []);
    expect(stages.first.kind, FcStageKind.table);
    expect(stages.last.kind, FcStageKind.knockout);
    expect(stages.last.name, 'Mata-mata');
  });
  test(
    'Home/away legs combine correctly and penalties stay separate from goals',
    () {
      final source = {
        'stages': [
          stage('Round of 16', [
            group([row(1, played: 2, goals: 2), row(2, played: 2, goals: 2)]),
          ]),
        ],
      };
      final phase = fcCompetitionStages(source, [
        game(
          'Round of 16',
          2,
          1,
          date: '2028-06-08',
          homeGoals: 2,
          awayGoals: 1,
          homePenalties: 3,
          awayPenalties: 4,
        ),
        game('Round of 16', 1, 2, homeGoals: 1, awayGoals: 0),
      ]).single;
      final tie = phase.ties.single;
      expect(tie.teams, ['1', '2']);
      expect(tie.games, hasLength(2));
      expect(tie.score('1'), 2);
      expect(tie.score('2'), 2);
      expect(tie.penalties('1'), 4);
      expect(tie.penalties('2'), 3);
      expect(phase.name, 'Oitavas de final');
    },
  );
  test('Future legs never contribute zero scores to the aggregate', () {
    final phase = fcCompetitionStages(
      {
        'stages': [
          stage('Final', [
            group([row(1), row(2)]),
          ]),
        ],
      },
      [
        game('Final', 1, 2, homeGoals: 3, awayGoals: 1),
        game('Final', 2, 1, date: '2028-06-08'),
      ],
    ).single;
    expect(phase.ties.single.played, hasLength(1));
    expect(phase.ties.single.score('1'), 3);
    expect(phase.ties.single.score('2'), 1);
  });
  test(
    'A missing calendar leg uses the phase totals without inventing a match',
    () {
      final phase = fcCompetitionStages(
        {
          'stages': [
            stage('Final', [
              group([row(1, played: 2, goals: 4), row(2, played: 2, goals: 1)]),
            ]),
          ],
        },
        [game('Final', 2, 1, homeGoals: 1, awayGoals: 2)],
      ).single;
      expect(phase.ties.single.games, hasLength(1));
      expect(phase.ties.single.score('1'), 4);
      expect(phase.ties.single.score('2'), 1);
    },
  );
  test('Confrontations can be built from fixtures without table rows', () {
    final phase = fcCompetitionStages(
      {
        'stages': [stage('Semi-Finals', [])],
      },
      [game('Semi-Finals', 1, 2), game('Semi-Finals', 3, 4)],
    ).single;
    expect(phase.ties, hasLength(2));
    expect(phase.ties.first.score('1'), isNull);
  });
  test(
    'Real saved cups hide configuration and show one tie per paired group',
    () {
      final path = Platform.environment['FC_SCORE_STATS_SNAPSHOT']!;
      final snapshot = fcObject(jsonDecode(File(path).readAsStringSync()));
      for (final id in ['1426', '1257']) {
        final competition = fcList(snapshot['competitions'])
            .firstWhere((c) => '${fcObject(c['competition'])['id']}' == id);
        final fixtures = fcList(snapshot['fixtures'])
            .where((f) => '${fcObject(f['competition'])['id']}' == id)
            .toList();
        final phases = fcCompetitionStages(competition, fixtures);
        expect(
          phases.any(
            (s) => s.name.contains('Setup') || s.name.contains('Draw'),
          ),
          isFalse,
        );
        final round = phases.firstWhere((s) => s.name == 'Oitavas de final');
        expect(round.kind, FcStageKind.knockout);
        expect(round.ties, hasLength(8));
        expect(round.ties.every((t) => t.teams.length == 2), isTrue);
      }
    },
    skip: Platform.environment['FC_SCORE_STATS_SNAPSHOT'] == null
        ? 'Optional saved API snapshot'
        : false,
  );
}
