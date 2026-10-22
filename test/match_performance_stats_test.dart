import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/FcScore/FcScoreLineupEvents.dart';
import 'package:mcmanager/FcScore/FcScoreRepository.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/models/MatchPerformanceStats.dart';
import 'package:mcmanager/models/OpponentLineup.dart';
import 'package:mcmanager/utils/managerFixturePerformanceUtils.dart';

void main() {
  ManagerFixturePlayerPerformance perf(String id) =>
      ManagerFixturePlayerPerformance(
        personId: 'p',
        fixtureId: 'f',
        playerInstanceId: id,
      );
  test('Detailed stats preserve zero, decimals, future fields and manual edits when completing', () {
    final mine = perf('a')
      ..apiStats = {
        'npkExpectedGoals': 0,
        'expectedAssists': null,
        'futureField': 'keep',
      };
    final api = perf('a')
      ..apiStats = {
        'npkExpectedGoals': 1.23,
        'expectedAssists': .54,
        'passesCompleted': 20,
      };
    final merged = fcCompletePerformance(mine, api);
    expect(merged.apiStats['npkExpectedGoals'], 0);
    expect(merged.apiStats['expectedAssists'], .54);
    final decoded = ManagerFixturePlayerPerformance.fromMap(merged.toMap());
    expect(decoded.apiStats, merged.apiStats);
    decoded.apiStats['expectedAssists'] = 1.2;
    expect(merged.apiStats['expectedAssists'], .54);
  });
  test('Percentages use weighted totals, with missing values excluded and no fake zero', () {
    final stat = performanceStats.firstWhere(
      (s) => s.key == 'pressurePassAccuracy',
    );
    expect(
      stat.total([
        {'passesUnderPressure': 10, 'passesCompletedUnderPressure': 5},
        {'passesUnderPressure': 90, 'passesCompletedUnderPressure': 90},
        {},
      ]),
      95,
    );
    expect(
      stat.total([
        {},
        {'passesUnderPressure': 0, 'passesCompletedUnderPressure': 0},
      ]),
      isNull,
    );
    expect(
      performanceStats.first.total([
        {},
        {'npkExpectedGoals': 0},
      ]),
      0,
    );
    expect(performanceStats.first.total([{}]), isNull);
  });
  test(
    'New opponents have no phantom XI until a formation is explicitly chosen',
    () {
      var o = OpponentLineup.unselected();
      expect(o.squad.players, isEmpty);
      o = o.addReserve('João');
      final id = o.squad.bench.single;
      o = o.withFormation('4-4-2');
      expect(o.squad.starters, hasLength(11));
      expect(o.squad.starters, contains(id));
      expect(o.names[id], 'João');
    },
  );
  test('Substitution inference preserves minutes, marks estimates and never invents simultaneous pairings', () {
    final data = <FcJson>[
      {
        'id': 'full',
        'started': true,
        'played': true,
        'stats': {'minutesPlayed': 93},
      },
      for (final id in ['a', 'b'])
        {
          'id': id,
          'started': true,
          'played': true,
          'stats': {'minutesPlayed': 76},
        },
      for (final id in ['c', 'd'])
        {
          'id': id,
          'started': false,
          'played': true,
          'stats': {'minutesPlayed': 17},
        },
      {
        'id': 'red',
        'started': true,
        'played': true,
        'stats': {'minutesPlayed': 60, 'redDismissals': 1},
      },
      {
        'id': 'unknown',
        'started': false,
        'played': true,
        'stats': {'minutesPlayed': 9},
      },
    ];
    final all = [for (final row in data) perf(row['id'])];
    fcApplySubstitutions(data, all, {
      for (final row in data) row['id']: row['id'],
    });
    for (final p in all.where(
      (p) => ['a', 'b', 'c', 'd'].contains(p.playerInstanceId),
    )) {
      expect(p.substitutionDetails.single.minute, 76);
      expect(p.substitutionDetails.single.anotherPlayerId, isNull);
      expect(p.copy().substitutionDetails.single.inferred, isTrue);
    }
    expect(all.first.substitutionDetails, isEmpty);
    expect(all[5].substitutionDetails, isEmpty);
    expect(all.last.substitutionDetails, isEmpty);
    fcApplySubstitutions(data, all, {
      for (final row in data) row['id']: row['id'],
    });
    expect(all[1].substitutionDetails, hasLength(1));
  });
  test('Choosing a partner for an inferred simultaneous change reuses its event and minute corrections', () {
    final a = perf('a')
      ..substitutionDetails = [
        PerformanceSubstitutionDetails(
          id: 'out',
          minute: 84,
          type: SubstitutionType.outGame,
          inferred: true,
        ),
      ];
    final c = perf('c')
      ..substitutionDetails = [
        PerformanceSubstitutionDetails(
          id: 'in',
          minute: 84,
          type: SubstitutionType.inGame,
          inferred: true,
        ),
      ];
    a.substitutionDetails.single
      ..anotherPlayerId = 'c'
      ..minute = 85
      ..inferred = false;
    syncSubstitutions(a, [a, c], 'Jogador A', perf);
    expect(c.substitutionDetails, hasLength(1));
    expect(c.substitutionDetails.single.id, 'in');
    expect(c.substitutionDetails.single.minute, 85);
    expect(c.substitutionDetails.single.inferred, isFalse);
    expect(c.substitutionDetails.single.anotherPlayerId, 'a');
  });
  test('Extra-time substitutions stay in the extra-time minute range', () {
    final data = <FcJson>[
      {
        'id': 'full',
        'played': true,
        'started': true,
        'stats': {'minutesPlayed': 123},
      },
      {
        'id': 'out',
        'played': true,
        'started': true,
        'stats': {'minutesPlayed': 107},
      },
      {
        'id': 'in',
        'played': true,
        'started': false,
        'stats': {'minutesPlayed': 16},
      },
    ];
    final all = [perf('full'), perf('out'), perf('in')];
    fcApplySubstitutions(data, all, {'full': 'full', 'out': 'out', 'in': 'in'});
    expect(all[1].substitutionDetails.single.minute, 107);
    expect(all[1].substitutionDetails.single.addedMinute, isNull);
    expect(all[1].substitutionDetails.single.anotherPlayerId, 'in');
  });
}
