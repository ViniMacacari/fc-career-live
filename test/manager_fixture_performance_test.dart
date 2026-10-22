import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/models/ManagerFixture.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/utils/eventTimeUtils.dart';
import 'package:mcmanager/utils/managerFixturePerformanceUtils.dart';
import 'package:mcmanager/utils/managerPlayerMinutesUtils.dart';

ManagerFixturePlayerPerformance _perf(String player) =>
    ManagerFixturePlayerPerformance(
      personId: 'person',
      fixtureId: 'fixture',
      playerInstanceId: player,
    );

void main() {
  group('serialização', () {
    test('type e posições do gol são texto JSON dentro do objeto', () {
      final perf = _perf('a')
        ..goalDetails.add(
          PerformanceGoalDetails(
            minute: 45,
            addedMinute: 2,
            type: [GoalType.header, GoalType.penalty],
            goalLocation: const GoalShotLocation(0.4, 0.2),
          ),
        );
      final map = perf.toMap();
      final goal = (jsonDecode(map['goalDetails']! as String) as List).single;
      expect(goal['type'], '["header","penalty"]');
      expect(goal['goalLocation'], '{"x":0.4,"y":0.2}');
      final back = ManagerFixturePlayerPerformance.fromMap(map);
      expect(back.goalDetails.single.type, [GoalType.header, GoalType.penalty]);
      expect(back.goalDetails.single.goalLocation?.x, 0.4);
      expect(back.goalDetails.single.addedMinute, 2);
    });

    test('colunas nulas geram itens sem minuto pelos contadores', () {
      final perf = ManagerFixturePlayerPerformance.fromMap({
        'id': 'id',
        'personId': 'person',
        'fixtureId': 'fixture',
        'playerInstanceId': 'a',
        'goalsCount': 2,
        'yellowCards': 1,
      });
      expect(perf.goalDetails, hasLength(2));
      expect(perf.goalDetails.every((goal) => goal.minute == null), isTrue);
      expect(perf.yellowCardDetails, hasLength(1));
      expect(perf.substitutionDetails, isEmpty);
    });

    test('tipo desconhecido vira bicyclekick', () {
      expect(GoalType.fromString('xyz'), GoalType.bicyclekick);
    });

    test('gols do adversário mantêm isOwnGoal e tipos', () {
      final encoded = encodeOpponentGoals([
        OpponentGoalDetails(scorerName: 'X', minute: 10, isOwnGoal: true),
      ]);
      final back = decodeOpponentGoals(encoded).single;
      expect(back.isOwnGoal, isTrue);
      expect(back.scorerName, 'X');
      expect(back.minute, 10);
    });
  });

  group('tempo', () {
    test('formato do minuto e ordenação', () {
      expect(formatEventMinute(45, 2), "45+2'");
      expect(formatEventMinute(12, 0), "12'");
      expect(formatEventMinute(null, 0), '');
      final sorted = getSortedDetails([
        PerformanceTimeDetails(minute: null),
        PerformanceTimeDetails(minute: 45, addedMinute: 3),
        PerformanceTimeDetails(minute: 45, addedMinute: 1),
        PerformanceTimeDetails(minute: 10),
      ]);
      expect(sorted.map((item) => item.minute), [10, 45, 45, null]);
      expect(sorted[1].addedMinute, 1);
    });

    test('duração e minutos jogados pelas substituições', () {
      final perf = _perf('a')
        ..substitutionDetails.add(
          PerformanceSubstitutionDetails(
            type: SubstitutionType.outGame,
            minute: 70,
          ),
        );
      final duration = getManagerFixtureDurationMinutes(
        extraTime: false,
        performance: perf,
      );
      expect(duration, 90);
      expect(getManagerPlayerPlayedMinutes(perf, duration), 70);
      expect(
        getManagerFixtureDurationMinutes(
          extraTime: false,
          opponentGoalMinutes: [95],
        ),
        120,
      );
    });
  });

  group('sincronização', () {
    test('gol com assistente cria e remove a assistência do outro', () {
      final scorer = _perf('a')
        ..goalDetails.add(PerformanceGoalDetails(minute: 30, assistantId: 'b'));
      final assistant = _perf('b');
      final all = [scorer, assistant];
      syncGoalsAndAssists(scorer, all, 'Artilheiro');
      expect(assistant.assistDetails, hasLength(1));
      expect(assistant.assistDetails.single.goalscorerId, 'a');
      expect(assistant.assistDetails.single.minute, 30);
      expect(assistant.assistsCount, 1);

      scorer.goalDetails.single.assistantId = null;
      syncGoalsAndAssists(scorer, all, 'Artilheiro');
      expect(assistant.assistDetails, isEmpty);
      expect(assistant.assistsCount, 0);
    });

    test('substituição é espelhada e cria atuação do parceiro', () {
      final out = _perf('a')
        ..substitutionDetails.add(
          PerformanceSubstitutionDetails(
            type: SubstitutionType.outGame,
            minute: 60,
            anotherPlayerId: 'b',
          ),
        );
      final all = [out];
      syncSubstitutions(out, all, 'Saiu', _perf);
      final partner = all.singleWhere((item) => item.playerInstanceId == 'b');
      expect(partner.substitutionDetails.single.type, SubstitutionType.inGame);
      expect(partner.substitutionDetails.single.anotherPlayerId, 'a');
    });

    test('remover jogador apaga os gols que ele assistiu', () {
      final scorer = _perf('a')
        ..goalDetails.add(PerformanceGoalDetails(assistantId: 'b'))
        ..goalDetails.add(PerformanceGoalDetails());
      removePerformanceAndRelatedLinks('b', [scorer]);
      expect(scorer.goalDetails, hasLength(1));
      expect(scorer.goalsCount, 1);
    });

    test('placar automático não conta gol e assistência duas vezes', () {
      final scorer = _perf('a')
        ..goalDetails.add(PerformanceGoalDetails(minute: 5, assistantId: 'b'));
      final assistant = _perf('b')
        ..assistDetails.add(
          PerformanceAssistDetails(minute: 5, goalscorerId: 'a'),
        );
      final solo = _perf('c')..goalDetails.add(PerformanceGoalDetails());
      expect(
        calculateManagerFixtureAutoFilledTeamScore([scorer, assistant, solo]),
        2,
      );
    });
  });
}
