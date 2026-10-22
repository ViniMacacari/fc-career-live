import '../../Common/FixtureResultTile.dart' show FixtureResult, fixtureResult;
import 'CompetitionFormats.dart';

enum OutcomeStatus {
  inProgress,
  champion,
  runnerUp,
  third,
  fourth,
  eliminated,

  finished,
}

int _int(Object? value) => value is num ? value.toInt() : 0;

class TournamentOutcome {
  TournamentOutcome._(this.tournamentId, this.format, this.fixtures);

  final String tournamentId;
  final CompetitionFormat format;

  final List<Map<String, Object?>> fixtures;

  int wins = 0, draws = 0, losses = 0, goalsFor = 0, goalsAgainst = 0;
  OutcomeStatus status = OutcomeStatus.inProgress;

  int? position;

  MatchStage? furthest;
  String resultText = '';

  final path = <String>[];

  bool definitive = false;

  Map<String, Object?>? decisive;

  bool get recognized => furthest != null;
  int get games => fixtures.length;
  bool get won => status == OutcomeStatus.champion;

  static List<TournamentOutcome> compute(
    Iterable<Map<String, Object?>> seasonFixtures, {
    required CompetitionFormat Function(String tournamentId) formatOf,
    required bool seasonOver,
  }) {
    final groups = <String, List<Map<String, Object?>>>{};
    for (final fixture in seasonFixtures) {
      final id = fixture['tournamentId']?.toString() ?? '';
      if (id.isEmpty) continue;
      (groups[id] ??= []).add(fixture);
    }
    return [
      for (final MapEntry(:key, :value) in groups.entries)
        TournamentOutcome._(
          key,
          formatOf(key),
          value..sort((a, b) => '${a['date']}'.compareTo('${b['date']}')),
        ).._evaluate(seasonOver),
    ];
  }

  void _evaluate(bool seasonOver) {
    for (final fixture in fixtures) {
      switch (fixtureResult(fixture)) {
        case FixtureResult.win:
          wins++;
        case FixtureResult.draw:
          draws++;
        case FixtureResult.lose:
          losses++;
      }
      goalsFor += _int(fixture['playerTeamScore']);
      goalsAgainst += _int(fixture['oppositeTeamScore']);
    }
    final staged = [
      for (final fixture in fixtures)
        if (format.parse(fixture['stage']?.toString()) case final stage?)
          (fixture, stage),
    ];
    if (staged.isEmpty) {
      resultText = format.structured
          ? 'Estágio das partidas não informado'
          : '$games jogo${games == 1 ? '' : 's'}';
      return;
    }
    furthest = staged
        .map((s) => s.$2)
        .reduce((a, b) => format.progress(b) >= format.progress(a) ? b : a);
    _path(staged);
    if (staged.any((s) => format.isFinal(s.$2)) && _final(staged, seasonOver)) {
      return;
    }
    if (!format.structured) {
      resultText = 'Em andamento';
      return;
    }
    if (format.kind == CompetitionKind.league) {
      _league(staged, seasonOver);
    } else {
      _knockout(staged, seasonOver);
    }
  }

  void _path(List<(Map<String, Object?>, MatchStage)> staged) {
    if (staged.any((s) => s.$2.group)) path.add(format.groupLabel);
    if (staged.any((s) => s.$2.round != null && !s.$2.group)) {
      path.add('Liga');
    }
    final phases = {
      for (final (_, stage) in staged)
        if (stage.phase != null) stage.phase!,
    }.toList()..sort();
    for (final phase in phases) {
      path.add(format.phases[phase].label);
    }
    if (staged.any((s) => s.$2.thirdPlace)) path.add(thirdPlaceLabel);
    if (staged.any((s) => s.$2.finale)) path.add(finaleLabel);
  }

  bool _final(
    List<(Map<String, Object?>, MatchStage)> staged,
    bool seasonOver,
  ) {
    final won = _tie(staged, format.isFinal);
    if (won == null && !seasonOver) {
      status = OutcomeStatus.inProgress;
      resultText = 'Em andamento · $finaleLabel';
      return true;
    }
    status = switch (won) {
      true => OutcomeStatus.champion,
      false => OutcomeStatus.runnerUp,
      null => OutcomeStatus.finished,
    };
    resultText = switch (won) {
      true => 'Campeão',
      false => 'Vice-campeão',
      null => 'Finalista',
    };
    definitive = true;
    return true;
  }

  bool? _tie(
    List<(Map<String, Object?>, MatchStage)> staged,
    bool Function(MatchStage) inPhase,
  ) {
    final matches = [
      for (final (fixture, stage) in staged)
        if (inPhase(stage)) (fixture, stage),
    ];
    if (matches.isEmpty) return null;
    final opponent = matches.last.$1['oppositeTeamId'];
    final tie = matches
        .where((m) => m.$1['oppositeTeamId'] == opponent)
        .toList();
    final firstLeg = tie.any((m) => m.$2.leg == StageLeg.first);
    final secondLeg = tie.any((m) => m.$2.leg == StageLeg.second);
    if (firstLeg && !secondLeg) return null;
    var us = 0, them = 0;
    for (final (fixture, _) in tie) {
      us += _int(fixture['playerTeamScore']);
      them += _int(fixture['oppositeTeamScore']);
    }
    decisive = tie.last.$1;
    if (us != them) return us > them;
    final last = tie.last.$1;
    final ourPens = last['playerTeamPenaltiesScore'];
    final theirPens = last['oppositeTeamPenaltiesScore'];
    if (ourPens is num && theirPens is num && ourPens != theirPens) {
      return ourPens > theirPens;
    }
    return null;
  }

  void _league(
    List<(Map<String, Object?>, MatchStage)> staged,
    bool seasonOver,
  ) {
    final leagueMatches = [
      for (final (fixture, stage) in staged)
        if (stage.round != null) fixture,
    ];
    for (final fixture in leagueMatches.reversed) {
      if (fixture['position'] case final num value when value > 0) {
        position = value.toInt();
        break;
      }
    }
    final lastRound = staged
        .map((s) => s.$2.round)
        .whereType<int>()
        .fold<int>(0, (a, b) => b > a ? b : a);
    final leagueOver =
        seasonOver || (format.rounds > 0 && lastRound >= format.rounds);
    final positionText = position == null ? null : '$positionº lugar';
    final playoffPhase = furthest?.phase;
    if (playoffPhase != null) {
      final won = _tie(staged, (s) => s.phase == playoffPhase);
      final isFinal = playoffPhase == format.phases.length - 1;
      final playoffs = format.phases[playoffPhase].label;
      if (format.playoffsDecideTitle) {
        if (won == true && isFinal) {
          status = OutcomeStatus.champion;
          resultText = 'Campeão';
          definitive = true;
        } else if (won == false) {
          status = isFinal ? OutcomeStatus.runnerUp : OutcomeStatus.eliminated;
          resultText = isFinal
              ? 'Vice-campeão'
              : 'Eliminado ${CompetitionFormat.inPhase(playoffs)}';
          definitive = true;
        } else {
          status = seasonOver
              ? OutcomeStatus.finished
              : OutcomeStatus.inProgress;
          resultText = seasonOver
              ? 'Chegou ${CompetitionFormat.inPhase(playoffs)}'
              : 'Em andamento · $playoffs';
          definitive = seasonOver;
        }
        if (positionText != null) resultText = '$resultText · $positionText';
        return;
      }
      final champion = position == 1;
      status = champion ? OutcomeStatus.champion : OutcomeStatus.finished;
      resultText = [
        if (champion) 'Campeão',
        ?positionText,
        if (won == true && isFinal)
          'venceu os playoffs'
        else if (won == false)
          'eliminado ${CompetitionFormat.inPhase(playoffs)}',
      ].join(' · ');
      definitive = won != null || seasonOver;
      decisive ??= leagueMatches.lastOrNull;
      return;
    }
    decisive = leagueMatches.lastOrNull;
    if (!leagueOver) {
      status = OutcomeStatus.inProgress;
      resultText = [
        'Em andamento',
        if (lastRound > 0) 'Rodada $lastRound',
        ?positionText,
      ].join(' · ');
      return;
    }
    definitive = true;
    final finalPosition = leagueMatches.lastOrNull?['position'];
    if (position == 1 && finalPosition == 1 && !format.playoffsDecideTitle) {
      status = OutcomeStatus.champion;
      resultText = 'Campeão';
    } else {
      status = OutcomeStatus.finished;
      resultText = positionText ?? 'Liga encerrada';
    }
  }

  void _knockout(
    List<(Map<String, Object?>, MatchStage)> staged,
    bool seasonOver,
  ) {
    final stage = furthest!;
    if (stage.thirdPlace) {
      final won = _tie(staged, (s) => s.thirdPlace);
      status = won == false ? OutcomeStatus.fourth : OutcomeStatus.third;
      resultText = won == false ? '4º lugar' : '3º lugar';
      definitive = won != null || seasonOver;
      if (won == null && !seasonOver) {
        status = OutcomeStatus.inProgress;
        resultText = 'Em andamento · $thirdPlaceLabel';
      }
      return;
    }
    if (stage.group) {
      final groupLabel = format.groupLabel;
      if (seasonOver) {
        status = OutcomeStatus.eliminated;
        resultText = 'Eliminado ${CompetitionFormat.inPhase(groupLabel)}';
        definitive = true;
      } else {
        resultText = 'Em andamento · $groupLabel';
      }
      return;
    }
    final phase = stage.phase!;
    final label = format.phases[phase].label;
    final isFinal = phase == format.phases.length - 1;
    final won = _tie(staged, (s) => s.phase == phase);
    if (won == true && isFinal) {
      status = OutcomeStatus.champion;
      resultText = 'Campeão';
      definitive = true;
    } else if (won == false) {
      status = isFinal ? OutcomeStatus.runnerUp : OutcomeStatus.eliminated;
      resultText = isFinal
          ? 'Vice-campeão'
          : 'Eliminado ${CompetitionFormat.inPhase(label)}';
      definitive = true;
    } else if (seasonOver) {
      status = OutcomeStatus.finished;
      resultText = 'Chegou ${CompetitionFormat.inPhase(label)}';
      definitive = true;
    } else {
      resultText = 'Em andamento · $label';
    }
  }
}
