import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/utils/competitions/CompetitionFormats.dart';
import 'package:mcmanager/utils/competitions/TournamentOutcomes.dart';

Map<String, Object?> _match(
  String date,
  String stage,
  int us,
  int them, {
  String tournament = '89',
  String opponent = 'rival',
  int? position,
  int? ourPens,
  int? theirPens,
}) => {
  'id': '$tournament-$date',
  'date': date,
  'tournamentId': tournament,
  'stage': stage,
  'playerTeamId': 'club',
  'oppositeTeamId': opponent,
  'playerTeamScore': us,
  'oppositeTeamScore': them,
  'position': ?position,
  'playerTeamPenaltiesScore': ?ourPens,
  'oppositeTeamPenaltiesScore': ?theirPens,
};

TournamentOutcome _outcome(
  List<Map<String, Object?>> fixtures, {
  bool seasonOver = false,
}) => TournamentOutcome.compute(
  fixtures,
  formatOf: (id) => CompetitionFormat.of(id, 'FC26'),
  seasonOver: seasonOver,
).single;

void main() {
  final tournaments = (jsonDecode(
    File('assets/game_tournaments.json').readAsStringSync(),
  ) as Map<String, dynamic>);
  final awards = {
    for (final a in jsonDecode(
      File('assets/game_awards.json').readAsStringSync(),
    ) as List)
      a['id']: a,
  };

  test('todo estágio de toda competição vira texto e volta igual', () {
    for (final MapEntry(key: version, value: items) in tournaments.entries) {
      for (final item in items as List) {
        final format = CompetitionFormat.of(item['id'] as String, version);
        for (final stage in format.stages) {
          for (final leg in StageLeg.values) {
            final current = stage.phase == null
                ? stage
                : MatchStage.phase(stage.phase!, leg: leg);
            expect(
              format.parse(format.label(current)),
              current,
              reason: '${item['label']} $version: ${format.label(current)}',
            );
          }
        }
      }
    }
  });

  test('cada competição com troféu aponta para um troféu de time', () {
    for (final MapEntry(key: version, value: items) in tournaments.entries) {
      for (final item in items as List) {
        final award = CompetitionFormat.of(
          item['id'] as String,
          version,
        ).awardId;
        if (award == null) continue;
        expect(
          awards[award]?['owner'],
          'team',
          reason: '${item['label']} → $award',
        );
      }
    }
  });

  test('próximo estágio', () {
    final copa = CompetitionFormat.of('89', 'FC26');
    expect(copa.label(copa.next(null)!), '1ª fase');
    expect(copa.label(copa.next(copa.parse('2ª fase'))!), '3ª fase · Ida');
    expect(
      copa.label(copa.next(copa.parse('3ª fase · Ida'))!),
      '3ª fase · Volta',
    );
    expect(copa.next(copa.parse('Final · Volta')), isNull);

    final brasileirao = CompetitionFormat.of('86', 'FC26');
    expect(
      brasileirao.label(brasileirao.next(brasileirao.parse('Rodada 9'))!),
      'Rodada 10',
    );
    expect(brasileirao.next(brasileirao.parse('Rodada 38')), isNull);
    expect(brasileirao.parse('Final'), const MatchStage.finale());
    expect(copa.label(copa.parse('Final · Ida')!), 'Finale · Ida');
    expect(brasileirao.parse('Fase de grupos · Rodada 1'), isNull);

    final mls = CompetitionFormat.of('64', 'FC26');
    expect(
      mls.label(mls.next(mls.parse('Rodada 34'))!),
      'Rodada 1 dos playoffs',
    );

    final ucl = CompetitionFormat.of('1', 'FC26');
    expect(
      ucl.label(ucl.next(ucl.parse('Fase de liga · Rodada 8'))!),
      'Playoff · Ida',
    );
    expect(
      CompetitionFormat.of('1', 'FC24').parse('Fase de grupos · Rodada 6'),
      isNotNull,
    );
  });

  test('Brasileirão: campeão na última rodada', () {
    final outcome = _outcome([
      _match('2028-11-20', 'Rodada 37', 2, 0, tournament: '86', position: 1),
      _match('2028-12-01', 'Rodada 38', 1, 1, tournament: '86', position: 1),
    ]);
    expect(outcome.status, OutcomeStatus.champion);
    expect(outcome.definitive, isTrue);
    expect(outcome.decisive?['date'], '2028-12-01');

    final midway = _outcome([
      _match('2028-05-01', 'Rodada 9', 3, 3, tournament: '86', position: 5),
    ]);
    expect(midway.status, OutcomeStatus.inProgress);
    expect(midway.resultText, 'Em andamento · Rodada 9 · 5º lugar');
    expect(midway.definitive, isFalse);
  });

  test('Saved API league stages and catalog de-para recognize the Brazilian final round', () {
    for (final id in ['86', '87', 'league:100', 'league:101']) {
      final format = CompetitionFormat.of(id, 'FC26');
      expect(format.rounds, 38, reason: id);
      for (final stage in [
        'League · Rodada 38',
        'Liga · Rodada 38',
        'Regular Season · Rodada 38',
        'Rodada 38',
      ]) {
        expect(
          format.parse(stage),
          const MatchStage.round(38),
          reason: '$id $stage',
        );
        final outcome = _outcome([
          _match('2028-11-29', stage, 0, 2, tournament: id, position: 1),
        ]);
        expect(outcome.won, isTrue);
        expect(outcome.definitive, isTrue);
      }
      expect(format.parse('Fase de grupos · Rodada 38'), isNull);
      expect(format.parse('Group Stage · Rodada 38'), isNull);
    }
    expect(CompetitionFormat.of('league:unknown', 'FC26').rounds, 0);
  });

  test('League title needs the final rank, not an old lead or a win before round 38', () {
    expect(
      _outcome([
        _match(
          '2028-11-22',
          'League · Rodada 37',
          5,
          0,
          tournament: '86',
          position: 1,
        ),
      ]).won,
      isFalse,
    );
    for (final position in [null, 2]) {
      expect(
        _outcome([
          _match(
            '2028-11-22',
            'League · Rodada 37',
            5,
            0,
            tournament: '86',
            position: 1,
          ),
          _match(
            '2028-11-29',
            'League · Rodada 38',
            5,
            0,
            tournament: '86',
            position: position,
          ),
        ]).won,
        isFalse,
      );
    }
  });

  test('Copa do Brasil: final de ida e volta decidida nos pênaltis', () {
    final outcome = _outcome([
      _match('2028-03-01', '1ª fase', 2, 0, opponent: 'a'),
      _match('2028-10-01', 'Final · Ida', 1, 0, opponent: 'f'),
      _match(
        '2028-10-08',
        'Final · Volta',
        0,
        1,
        opponent: 'f',
        ourPens: 4,
        theirPens: 3,
      ),
    ]);
    expect(outcome.status, OutcomeStatus.champion);
    expect(outcome.resultText, 'Campeão');
    expect(outcome.path, ['1ª fase', 'Finale']);

    final firstLegOnly = _outcome([
      _match('2028-10-01', 'Final · Ida', 1, 0, opponent: 'f'),
    ]);
    expect(firstLegOnly.status, OutcomeStatus.inProgress);
  });

  test('eliminado nas quartas', () {
    final outcome = _outcome([
      _match('2028-08-01', 'Quartas de final · Ida', 1, 0, opponent: 'q'),
      _match('2028-08-08', 'Quartas de final · Volta', 0, 2, opponent: 'q'),
    ]);
    expect(outcome.status, OutcomeStatus.eliminated);
    expect(outcome.resultText, 'Eliminado nas quartas de final');
    expect(outcome.definitive, isTrue);
  });

  test('Libertadores: fase de grupos só termina com a temporada', () {
    final groups = [
      _match('2028-04-01', 'Fase de grupos · Rodada 6', 0, 1, tournament: '5'),
    ];
    expect(_outcome(groups).definitive, isFalse);
    final over = _outcome(groups, seasonOver: true);
    expect(over.status, OutcomeStatus.eliminated);
    expect(over.resultText, 'Eliminado na fase de grupos');
  });

  test('texto livre antigo não gera resultado', () {
    final outcome = _outcome([
      _match('2028-04-01', 'jogo bom', 2, 1, tournament: '86'),
    ]);
    expect(outcome.recognized, isFalse);
    expect([outcome.wins, outcome.goalsFor], [1, 2]);
  });

  test('Finale decide o título de torneio personalizado sem formato', () {
    TournamentOutcome custom(List<Map<String, Object?>> fixtures) =>
        TournamentOutcome.compute(
          fixtures,
          formatOf: (_) => const CompetitionFormat.open(),
          seasonOver: false,
        ).single;
    final won = custom([
      _match('2028-02-01', 'Semi', 2, 1, tournament: 'meu-torneio'),
      _match('2028-02-08', 'Finale · Ida', 0, 0, tournament: 'meu-torneio'),
      _match('2028-02-15', 'Finale · Volta', 2, 1, tournament: 'meu-torneio'),
    ]);
    expect(won.status, OutcomeStatus.champion);
    expect(won.definitive, isTrue);
    expect(won.decisive?['date'], '2028-02-15');

    final lost = custom([
      _match('2028-02-15', 'Finale', 1, 3, tournament: 'meu-torneio'),
    ]);
    expect(lost.status, OutcomeStatus.runnerUp);

    final nothing = custom([
      _match('2028-02-01', 'Semi', 2, 1, tournament: 'meu-torneio'),
    ]);
    expect(nothing.recognized, isFalse);
  });
}
