library;

enum CompetitionKind { league, knockout, groups, single, friendly, open }

enum StageLeg { single, first, second }

class KnockoutPhase {
  const KnockoutPhase(this.label, {this.twoLegs = false});
  final String label;

  final bool twoLegs;
}

class MatchStage {
  const MatchStage.round(this.round)
    : phase = null,
      leg = StageLeg.single,
      group = false,
      thirdPlace = false,
      finale = false;
  const MatchStage.groupRound(this.round)
    : phase = null,
      leg = StageLeg.single,
      group = true,
      thirdPlace = false,
      finale = false;
  const MatchStage.phase(int this.phase, {this.leg = StageLeg.single})
    : round = null,
      group = false,
      thirdPlace = false,
      finale = false;
  const MatchStage.thirdPlace()
    : round = null,
      phase = null,
      leg = StageLeg.single,
      group = false,
      thirdPlace = true,
      finale = false;

  const MatchStage.finale({this.leg = StageLeg.single})
    : round = null,
      phase = null,
      group = false,
      thirdPlace = false,
      finale = true;

  final int? round;

  final int? phase;
  final StageLeg leg;
  final bool group, thirdPlace, finale;

  bool get isKnockout => phase != null || thirdPlace || finale;

  @override
  bool operator ==(Object other) =>
      other is MatchStage &&
      other.round == round &&
      other.phase == phase &&
      other.leg == leg &&
      other.group == group &&
      other.thirdPlace == thirdPlace &&
      other.finale == finale;

  @override
  int get hashCode => Object.hash(round, phase, leg, group, thirdPlace, finale);
}

const thirdPlaceLabel = 'Disputa de 3º lugar';

const finaleLabel = 'Finale';

String _withLeg(String name, StageLeg leg) => switch (leg) {
  StageLeg.single => name,
  StageLeg.first => '$name · Ida',
  StageLeg.second => '$name · Volta',
};

class CompetitionFormat {
  const CompetitionFormat._(
    this.kind, {
    this.rounds = 0,
    this.groupLabel = 'Fase de grupos',
    this.phases = const [],
    this.playoffsDecideTitle = false,
    this.thirdPlace = false,
    this.awardId,
    this.national = false,
  });

  const CompetitionFormat.league(
    int rounds, {
    List<KnockoutPhase> playoffs = const [],
    bool playoffsDecideTitle = false,
    String? awardId,
  }) : this._(
         CompetitionKind.league,
         rounds: rounds,
         phases: playoffs,
         playoffsDecideTitle: playoffsDecideTitle,
         awardId: awardId,
       );

  const CompetitionFormat.knockout(
    List<KnockoutPhase> phases, {
    bool thirdPlace = false,
    String? awardId,
    bool national = false,
  }) : this._(
         CompetitionKind.knockout,
         phases: phases,
         thirdPlace: thirdPlace,
         awardId: awardId,
         national: national,
       );

  const CompetitionFormat.groups(
    int rounds,
    List<KnockoutPhase> phases, {
    String groupLabel = 'Fase de grupos',
    bool thirdPlace = false,
    String? awardId,
    bool national = false,
  }) : this._(
         CompetitionKind.groups,
         rounds: rounds,
         groupLabel: groupLabel,
         phases: phases,
         thirdPlace: thirdPlace,
         awardId: awardId,
         national: national,
       );

  const CompetitionFormat.single({String? awardId})
    : this._(
        CompetitionKind.single,
        phases: const [KnockoutPhase(finaleLabel)],
        awardId: awardId,
      );

  const CompetitionFormat.friendly() : this._(CompetitionKind.friendly);

  const CompetitionFormat.open() : this._(CompetitionKind.open);

  static CompetitionFormat manualStages(CompetitionKind kind) => switch (kind) {
    CompetitionKind.groups => const CompetitionFormat.groups(
      0,
      _genericGroupKnockout,
    ),
    CompetitionKind.knockout => const CompetitionFormat.knockout(
      _genericKnockout,
    ),
    _ => const CompetitionFormat.league(0),
  };

  static CompetitionFormat manualStagesFor(String? text) {
    for (final kind in [
      CompetitionKind.league,
      CompetitionKind.groups,
      CompetitionKind.knockout,
    ]) {
      final format = manualStages(kind);
      final stage = format.parse(text);
      if (stage != null) {
        return stage.isKnockout
            ? manualStages(CompetitionKind.knockout)
            : format;
      }
    }
    return manualStages(CompetitionKind.league);
  }

  final CompetitionKind kind;
  final int rounds;
  final String groupLabel;
  final List<KnockoutPhase> phases;
  final bool playoffsDecideTitle, thirdPlace, national;

  final String? awardId;

  bool get structured =>
      kind != CompetitionKind.open && kind != CompetitionKind.friendly;

  int get finaleIndex => phases.indexWhere((p) => p.label == finaleLabel);

  bool isFinal(MatchStage stage) =>
      stage.finale || (stage.phase != null && stage.phase == finaleIndex);

  MatchStage finale(StageLeg leg) => finaleIndex >= 0
      ? MatchStage.phase(finaleIndex, leg: leg)
      : MatchStage.finale(leg: leg);

  String label(MatchStage stage) {
    if (stage.thirdPlace) return thirdPlaceLabel;
    if (stage.finale) return _withLeg(finaleLabel, stage.leg);
    if (stage.phase != null) {
      return _withLeg(phases[stage.phase!].label, stage.leg);
    }
    return stage.group
        ? '$groupLabel · Rodada ${stage.round}'
        : 'Rodada ${stage.round}';
  }

  static final _round = RegExp(
    r'^(?:(?:league|liga|regular season|temporada regular|fase regular)\s*·\s*)?rodada\s+(\d+)$',
  );
  static final _groupRound = RegExp(
    r'^(fase de grupos|fase de liga|.+) · rodada (\d+)$',
  );

  MatchStage? parse(String? text) {
    final value = text?.trim() ?? '';
    if (value.isEmpty) return null;
    final lower = value.toLowerCase();
    if (lower == thirdPlaceLabel.toLowerCase()) {
      return thirdPlace ? const MatchStage.thirdPlace() : null;
    }
    var leg = StageLeg.single;
    var name = lower;
    if (name.endsWith(' · ida')) {
      leg = StageLeg.first;
      name = name.substring(0, name.length - 6);
    } else if (name.endsWith(' · volta')) {
      leg = StageLeg.second;
      name = name.substring(0, name.length - 8);
    }
    if (name == finaleLabel.toLowerCase() || name == 'final') {
      return finale(leg);
    }
    if (!structured) return null;
    for (final (index, phase) in phases.indexed) {
      if (phase.label.toLowerCase() == name) {
        return MatchStage.phase(index, leg: leg);
      }
    }
    if (kind == CompetitionKind.league) {
      final round = _round.firstMatch(lower);
      if (round != null) return MatchStage.round(int.parse(round.group(1)!));
    }
    if (kind == CompetitionKind.groups) {
      final round = _groupRound.firstMatch(lower);
      if (round != null && round.group(1) == groupLabel.toLowerCase()) {
        return MatchStage.groupRound(int.parse(round.group(2)!));
      }
    }
    return null;
  }

  List<MatchStage> get stages => [
    if (kind == CompetitionKind.league)
      for (var r = 1; r <= (rounds == 0 ? 50 : rounds); r++)
        MatchStage.round(r),
    if (kind == CompetitionKind.groups)
      for (var r = 1; r <= rounds; r++) MatchStage.groupRound(r),
    for (var i = 0; i < phases.length; i++) MatchStage.phase(i),
    if (thirdPlace) const MatchStage.thirdPlace(),
  ];

  double progress(MatchStage stage) {
    if (stage.finale) return 2000;
    if (stage.round != null) return stage.round!.toDouble();
    if (stage.thirdPlace) return 1000 + phases.length - 1.5;
    return 1000 + stage.phase!.toDouble();
  }

  MatchStage? next(MatchStage? last) {
    MatchStage phaseStart(int index) => MatchStage.phase(
      index,
      leg: phases[index].twoLegs ? StageLeg.first : StageLeg.single,
    );
    if (last == null) {
      return switch (kind) {
        CompetitionKind.league => const MatchStage.round(1),
        CompetitionKind.groups => const MatchStage.groupRound(1),
        CompetitionKind.knockout ||
        CompetitionKind.single => phases.isEmpty ? null : phaseStart(0),
        _ => null,
      };
    }
    if (last.thirdPlace) return null;
    if (last.finale) {
      return last.leg == StageLeg.first
          ? const MatchStage.finale(leg: StageLeg.second)
          : null;
    }
    if (last.round != null) {
      final more = rounds == 0 || last.round! < rounds;
      if (more) {
        return last.group
            ? MatchStage.groupRound(last.round! + 1)
            : MatchStage.round(last.round! + 1);
      }
      return phases.isEmpty ? null : phaseStart(0);
    }
    if (last.leg == StageLeg.first) {
      return MatchStage.phase(last.phase!, leg: StageLeg.second);
    }
    final following = last.phase! + 1;
    return following < phases.length ? phaseStart(following) : null;
  }

  static String inPhase(String label) {
    final lower = label.toLowerCase();
    final article = lower.startsWith('oitavas') || lower.startsWith('quartas')
        ? 'nas'
        : lower.contains('avos') || lower.startsWith('playoffs')
        ? 'nos'
        : lower.startsWith('playoff')
        ? 'no'
        : 'na';
    return '$article ${RegExp(r'^\d').hasMatch(label) ? label : lower}';
  }

  static CompetitionFormat decode(String? value) {
    final parts = (value ?? '').split(':');
    final number = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return switch (parts.first) {
      'league' => CompetitionFormat.league(number),
      'knockout' => const CompetitionFormat.knockout(_genericKnockout),
      'groups' => CompetitionFormat.groups(
        number == 0 ? 6 : number,
        _genericGroupKnockout,
      ),
      'single' => const CompetitionFormat.single(),
      'friendly' => const CompetitionFormat.friendly(),
      _ => const CompetitionFormat.open(),
    };
  }

  static CompetitionFormat of(
    String tournamentId,
    String fifaVersion, {
    String? customFormat,
  }) {
    if (tournamentId.startsWith('league:')) {
      if (tournamentId == 'league:100') return _builtIn('86', fifaVersion)!;
      if (tournamentId == 'league:101') return _builtIn('87', fifaVersion)!;
      return const CompetitionFormat.league(0);
    }
    return _builtIn(tournamentId, fifaVersion) ?? decode(customFormat);
  }

  static const _genericKnockout = [
    KnockoutPhase('1ª fase'),
    KnockoutPhase('2ª fase'),
    KnockoutPhase('3ª fase'),
    KnockoutPhase('16 avos de final'),
    KnockoutPhase('Oitavas de final'),
    KnockoutPhase('Quartas de final'),
    KnockoutPhase('Semifinal'),
    KnockoutPhase(finaleLabel),
  ];

  static const _genericGroupKnockout = [
    KnockoutPhase('16 avos de final'),
    KnockoutPhase('Oitavas de final'),
    KnockoutPhase('Quartas de final'),
    KnockoutPhase('Semifinal'),
    KnockoutPhase(finaleLabel),
  ];

  static CompetitionFormat? _builtIn(String id, String fifaVersion) {
    final leaguePhase = !const {'FIFA23', 'FC24'}.contains(fifaVersion);
    const twoLegs = true;
    List<KnockoutPhase> cup(List<String> early, {bool twoLegSemis = false}) => [
      for (final label in early) KnockoutPhase(label),
      const KnockoutPhase('Quartas de final'),
      KnockoutPhase('Semifinal', twoLegs: twoLegSemis),
      const KnockoutPhase(finaleLabel),
    ];
    const uefaKnockout = [
      KnockoutPhase('Oitavas de final', twoLegs: twoLegs),
      KnockoutPhase('Quartas de final', twoLegs: twoLegs),
      KnockoutPhase('Semifinal', twoLegs: twoLegs),
      KnockoutPhase(finaleLabel),
    ];
    CompetitionFormat uefa(String award, {required int leagueRounds}) =>
        leaguePhase
        ? CompetitionFormat.groups(
            leagueRounds,
            const [KnockoutPhase('Playoff', twoLegs: twoLegs), ...uefaKnockout],
            groupLabel: 'Fase de liga',
            awardId: award,
          )
        : CompetitionFormat.groups(6, [
            if (award != '1') const KnockoutPhase('Playoff', twoLegs: twoLegs),
            ...uefaKnockout,
          ], awardId: award);
    const finalOnly = CompetitionFormat.single;
    return switch (id) {
      '1' => uefa('1', leagueRounds: 8),
      '2' => uefa('2', leagueRounds: 8),
      '3' => uefa('3', leagueRounds: 6),
      '1-w' => CompetitionFormat.groups(6, [
        KnockoutPhase('Quartas de final', twoLegs: twoLegs),
        KnockoutPhase('Semifinal', twoLegs: twoLegs),
        KnockoutPhase(finaleLabel),
      ], awardId: '1-w'),
      '4' => finalOnly(awardId: '4'),
      '5' => CompetitionFormat.groups(6, [
        KnockoutPhase('Oitavas de final', twoLegs: twoLegs),
        KnockoutPhase('Quartas de final', twoLegs: twoLegs),
        KnockoutPhase('Semifinal', twoLegs: twoLegs),
        KnockoutPhase(finaleLabel),
      ], awardId: '91'),
      '5-1' => CompetitionFormat.groups(6, [
        KnockoutPhase('Playoffs de oitavas', twoLegs: twoLegs),
        KnockoutPhase('Oitavas de final', twoLegs: twoLegs),
        KnockoutPhase('Quartas de final', twoLegs: twoLegs),
        KnockoutPhase('Semifinal', twoLegs: twoLegs),
        KnockoutPhase(finaleLabel),
      ], awardId: '92'),
      '5-2' => CompetitionFormat.knockout([
        KnockoutPhase(finaleLabel, twoLegs: twoLegs),
      ], awardId: '97'),
      '6' => CompetitionFormat.groups(
        leaguePhase ? 8 : 6,
        [
          KnockoutPhase('Oitavas de final', twoLegs: twoLegs),
          KnockoutPhase('Quartas de final'),
          KnockoutPhase('Semifinal'),
          KnockoutPhase(finaleLabel),
        ],
        groupLabel: leaguePhase ? 'Fase de liga' : 'Fase de grupos',
        awardId: '6',
      ),
      '91' =>
        leaguePhase
            ? CompetitionFormat.groups(3, [
                KnockoutPhase('Oitavas de final'),
                KnockoutPhase('Quartas de final'),
                KnockoutPhase('Semifinal'),
                KnockoutPhase(finaleLabel),
              ], awardId: '93')
            : CompetitionFormat.knockout([
                KnockoutPhase('2ª rodada'),
                KnockoutPhase('Semifinal'),
                KnockoutPhase(finaleLabel),
              ], awardId: '93'),
      '93' => CompetitionFormat.knockout([
        KnockoutPhase('1ª rodada', twoLegs: twoLegs),
        KnockoutPhase('Oitavas de final', twoLegs: twoLegs),
        KnockoutPhase('Quartas de final', twoLegs: twoLegs),
        KnockoutPhase('Semifinal', twoLegs: twoLegs),
        KnockoutPhase(finaleLabel),
      ], awardId: '95'),
      '7-1' || '7-2' => CompetitionFormat.groups(
        3,
        [
          KnockoutPhase('16 avos de final'),
          KnockoutPhase('Oitavas de final'),
          KnockoutPhase('Quartas de final'),
          KnockoutPhase('Semifinal'),
          KnockoutPhase(finaleLabel),
        ],
        thirdPlace: true,
        awardId: '7',
        national: true,
      ),
      '7-3' => CompetitionFormat.groups(
        3,
        [
          KnockoutPhase('Oitavas de final'),
          KnockoutPhase('Quartas de final'),
          KnockoutPhase('Semifinal'),
          KnockoutPhase(finaleLabel),
        ],
        thirdPlace: true,
        awardId: '7',
        national: true,
      ),
      '8-1' || '8-2' || '8-3' || '8-4' => CompetitionFormat.groups(
        3,
        [
          KnockoutPhase('Oitavas de final'),
          KnockoutPhase('Quartas de final'),
          KnockoutPhase('Semifinal'),
          KnockoutPhase(finaleLabel),
        ],
        awardId: '8',
        national: true,
      ),
      '85' => CompetitionFormat.groups(
        3,
        [
          KnockoutPhase('Oitavas de final'),
          KnockoutPhase('Quartas de final'),
          KnockoutPhase('Semifinal'),
          KnockoutPhase(finaleLabel),
        ],
        awardId: '85',
        national: true,
      ),
      '92' => CompetitionFormat.groups(
        3,
        [
          KnockoutPhase('Quartas de final'),
          KnockoutPhase('Semifinal'),
          KnockoutPhase(finaleLabel),
        ],
        thirdPlace: true,
        awardId: '94',
        national: true,
      ),
      '94' => CompetitionFormat.groups(
        6,
        [
          KnockoutPhase('Quartas de final', twoLegs: twoLegs),
          KnockoutPhase('Semifinal'),
          KnockoutPhase(finaleLabel),
        ],
        groupLabel: 'Fase de liga',
        thirdPlace: true,
        awardId: '96',
        national: true,
      ),
      '9' => const CompetitionFormat.league(
        10,
        playoffs: [
          KnockoutPhase('Semifinal da repescagem'),
          KnockoutPhase('Final da repescagem'),
        ],
      ),
      '10' => const CompetitionFormat.league(
        18,
        playoffs: [KnockoutPhase('Repescagem')],
      ),
      '11' || '70' => const CompetitionFormat.friendly(),
      '12' => const CompetitionFormat.league(27, awardId: '12'),
      '13' => const CompetitionFormat.league(
        26,
        playoffs: [
          KnockoutPhase('Eliminatória'),
          KnockoutPhase('Semifinal', twoLegs: twoLegs),
          KnockoutPhase(finaleLabel),
        ],
        playoffsDecideTitle: true,
        awardId: '13',
      ),
      '14' => const CompetitionFormat.league(32, awardId: '14'),
      '16' => const CompetitionFormat.league(40, awardId: '16'),
      '18' => const CompetitionFormat.league(30, awardId: '18'),
      '19' => const CompetitionFormat.league(32, awardId: '19'),
      '21' => const CompetitionFormat.league(38, awardId: '21'),
      '21-w' => const CompetitionFormat.league(22, awardId: '21-w'),
      '22' || '23' || '24' => CompetitionFormat.league(
        46,
        playoffs: const [
          KnockoutPhase('Semifinal dos playoffs', twoLegs: twoLegs),
          KnockoutPhase('Final dos playoffs'),
        ],
        awardId: id,
      ),
      '28' => const CompetitionFormat.league(38, awardId: '28'),
      '28-w' => const CompetitionFormat.league(22, awardId: '28-w'),
      '29' => const CompetitionFormat.league(
        38,
        playoffs: [
          KnockoutPhase('Playoff'),
          KnockoutPhase('Final dos playoffs'),
        ],
        awardId: '29',
      ),
      '31' => const CompetitionFormat.league(34, awardId: '31'),
      '31-w' => const CompetitionFormat.league(22, awardId: '31-w'),
      '32' => const CompetitionFormat.league(34, awardId: '32'),
      '33' => const CompetitionFormat.league(38, awardId: '33'),
      '35' => const CompetitionFormat.league(
        24,
        playoffs: [
          KnockoutPhase('Eliminatória'),
          KnockoutPhase('Semifinal', twoLegs: twoLegs),
          KnockoutPhase(finaleLabel),
        ],
        playoffsDecideTitle: true,
        awardId: '35',
      ),
      '36' => const CompetitionFormat.league(38, awardId: '36'),
      '37' => const CompetitionFormat.league(
        38,
        playoffs: [
          KnockoutPhase('Playoff'),
          KnockoutPhase('Semifinal dos playoffs', twoLegs: twoLegs),
          KnockoutPhase('Final dos playoffs', twoLegs: twoLegs),
        ],
        awardId: '37',
      ),
      '40' => const CompetitionFormat.league(36, awardId: '40'),
      '42' => const CompetitionFormat.league(34, awardId: '42'),
      '44' => const CompetitionFormat.league(30, awardId: '44'),
      '46' => const CompetitionFormat.league(34, awardId: '46'),
      '48' => const CompetitionFormat.league(34, awardId: '48'),
      '50' => const CompetitionFormat.league(40, awardId: '50'),
      '53' => const CompetitionFormat.league(38, awardId: '53'),
      '55' => const CompetitionFormat.league(38, awardId: '55'),
      '55-w' => const CompetitionFormat.league(30, awardId: '55-w'),
      '56' => const CompetitionFormat.league(
        42,
        playoffs: [
          KnockoutPhase('Semifinal dos playoffs', twoLegs: twoLegs),
          KnockoutPhase('Final dos playoffs', twoLegs: twoLegs),
        ],
        awardId: '56',
      ),
      '58' => const CompetitionFormat.league(30, awardId: '58'),
      '60' => const CompetitionFormat.league(38, awardId: '60'),
      '62' => const CompetitionFormat.league(38, awardId: '62'),
      '64' => const CompetitionFormat.league(
        34,
        playoffs: [
          KnockoutPhase('Rodada 1 dos playoffs'),
          KnockoutPhase('Semifinal de conferência'),
          KnockoutPhase('Final de conferência'),
          KnockoutPhase(finaleLabel),
        ],
        playoffsDecideTitle: true,
        awardId: '64',
      ),
      '64-w' => const CompetitionFormat.league(
        26,
        playoffs: [
          KnockoutPhase('Quartas de final'),
          KnockoutPhase('Semifinal'),
          KnockoutPhase(finaleLabel),
        ],
        playoffsDecideTitle: true,
        awardId: '64-w',
      ),
      '67' => const CompetitionFormat.league(38, awardId: '67'),
      '68' => const CompetitionFormat.league(34, awardId: '68'),
      '86' => const CompetitionFormat.league(38, awardId: '86'),
      '87' => const CompetitionFormat.league(38, awardId: '87'),
      '88' => const CompetitionFormat.league(
        34,
        playoffs: [
          KnockoutPhase('Repescagem'),
          KnockoutPhase('Quartas de final', twoLegs: twoLegs),
          KnockoutPhase('Semifinal', twoLegs: twoLegs),
          KnockoutPhase(finaleLabel, twoLegs: twoLegs),
        ],
        playoffsDecideTitle: true,
        awardId: '88',
      ),
      '15' => CompetitionFormat.knockout(
        cup(['1ª rodada', '2ª rodada', 'Oitavas de final']),
        awardId: '15',
      ),
      '17' => CompetitionFormat.knockout(
        cup(['1ª rodada', '2ª rodada', 'Oitavas de final'], twoLegSemis: true),
        awardId: '17',
      ),
      '20' => CompetitionFormat.knockout([
        KnockoutPhase('1ª rodada'),
        KnockoutPhase('2ª rodada'),
        KnockoutPhase('3ª rodada'),
        KnockoutPhase('Oitavas de final'),
        KnockoutPhase('Quartas de final', twoLegs: twoLegs),
        KnockoutPhase('Semifinal', twoLegs: twoLegs),
        KnockoutPhase(finaleLabel),
      ], awardId: '20'),
      '25' => CompetitionFormat.knockout(
        cup(['1ª rodada', '2ª rodada', '3ª rodada', '4ª rodada', '5ª rodada']),
        awardId: '25',
      ),
      '26' => CompetitionFormat.knockout(
        cup([
          '1ª rodada',
          '2ª rodada',
          '3ª rodada',
          '4ª rodada',
        ], twoLegSemis: true),
        awardId: '26',
      ),
      '27' => CompetitionFormat.groups(3, [
        KnockoutPhase('2ª rodada'),
        KnockoutPhase('3ª rodada'),
        KnockoutPhase('Quartas de final'),
        KnockoutPhase('Semifinal'),
        KnockoutPhase(finaleLabel),
      ], awardId: '27'),
      '30' => CompetitionFormat.knockout(
        cup(['32 avos de final', '16 avos de final', 'Oitavas de final']),
        awardId: '30',
      ),
      '34' || '43' || '61' => CompetitionFormat.knockout(
        cup(['1ª rodada', '2ª rodada', 'Oitavas de final']),
        awardId: id,
      ),
      '38' => CompetitionFormat.knockout(
        cup([
          '1ª fase',
          '16 avos de final',
          'Oitavas de final',
        ], twoLegSemis: true),
        awardId: '38',
      ),
      '41' => CompetitionFormat.knockout(
        cup(['1ª rodada', '2ª rodada']),
        awardId: '41',
      ),
      '45' => CompetitionFormat.knockout(
        cup(['1ª rodada', '2ª rodada', '3ª rodada', '4ª rodada']),
        awardId: '45',
      ),
      '47' => CompetitionFormat.knockout(
        cup(['1ª rodada', '16 avos de final', 'Oitavas de final']),
        awardId: '47',
      ),
      '49' => CompetitionFormat.knockout(
        cup([
          '3ª eliminatória',
          '4ª eliminatória',
          'Oitavas de final',
        ], twoLegSemis: true),
        awardId: '49',
      ),
      '51' => CompetitionFormat.groups(3, [
        KnockoutPhase('Quartas de final'),
        KnockoutPhase('Semifinal', twoLegs: twoLegs),
        KnockoutPhase(finaleLabel),
      ], awardId: '51'),
      '57' => CompetitionFormat.knockout(
        cup([
          '1ª rodada',
          '2ª rodada',
          '16 avos de final',
          'Oitavas de final',
        ], twoLegSemis: true),
        awardId: '57',
      ),
      '59' => CompetitionFormat.groups(3, [
        KnockoutPhase('Quartas de final'),
        KnockoutPhase('Semifinal'),
        KnockoutPhase(finaleLabel),
      ], awardId: '59'),
      '63' => CompetitionFormat.knockout(
        cup(['1ª rodada', '2ª rodada', '3ª rodada', 'Oitavas de final']),
        awardId: '63',
      ),
      '65' => CompetitionFormat.knockout(
        cup(['Rodada de 32', 'Oitavas de final']),
        awardId: '65',
      ),
      '69' => CompetitionFormat.knockout(
        cup(['32 avos de final', '16 avos de final', 'Oitavas de final']),
        awardId: '69',
      ),
      '89' => CompetitionFormat.knockout([
        KnockoutPhase('1ª fase'),
        KnockoutPhase('2ª fase'),
        KnockoutPhase('3ª fase', twoLegs: twoLegs),
        KnockoutPhase('Oitavas de final', twoLegs: twoLegs),
        KnockoutPhase('Quartas de final', twoLegs: twoLegs),
        KnockoutPhase('Semifinal', twoLegs: twoLegs),
        KnockoutPhase(finaleLabel, twoLegs: twoLegs),
      ], awardId: '89'),
      '77' || '82' => CompetitionFormat.knockout([
        KnockoutPhase('Semifinal'),
        KnockoutPhase(finaleLabel),
      ], awardId: id),
      '72' => finalOnly(),
      '73' ||
      '74' ||
      '75' ||
      '76' ||
      '78' ||
      '79' ||
      '80' ||
      '81' ||
      '83' ||
      '84' ||
      '90' => finalOnly(awardId: id),
      _ => null,
    };
  }
}
