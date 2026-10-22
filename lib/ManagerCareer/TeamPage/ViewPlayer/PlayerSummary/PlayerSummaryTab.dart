import '../../../../utils/AppColors.dart';

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../Common/FixtureResultTile.dart' show fixtureResult;
import '../../../../Common/HeadToHeadWidgets.dart';
import '../../../../models/ManagerFixturePlayerPerformance.dart';
import '../../../../models/Person.dart';
import '../../../../utils/GameCatalog.dart';
import '../../../../utils/SqlService.dart';
import '../../../Fixtures/Performances/SelectGoalTypePage.dart'
    show goalTypeLabel;
import '../../../Fixtures/Performances/TeamPlayersPerformanceGrid.dart'
    show performanceRatingColor;
import '../ComparePlayers/ComparisonCharts.dart';
import '../PlayerProfileData.dart';
import '../PlayerPerformanceInsights.dart';
import '../PlayerScoringInsights.dart';
import '../PlayerDetailedStats.dart';
import '../PlayerProfileVisuals.dart';
import '../../../../models/Season.dart';
import '../PlayerAnalysis.dart';
import 'PlayerSummaryData.dart';

final _goalColor = comparisonColor(0);
final _assistColor = comparisonColor(1);

TextStyle _value(BuildContext context) => TextStyle(
  color: AppColors.of(context).text,
  fontSize: 12,
  fontWeight: FontWeight.w600,
);
TextStyle _note(BuildContext context) =>
    TextStyle(color: AppColors.of(context).muted, fontSize: 11, height: 1.35);

String _decimal(num? value, [int digits = 2]) => value == null
    ? '–'
    : NumberFormat(
        digits == 0 ? '0' : '0.${'0' * digits}',
        'pt_BR',
      ).format(value);

String _minute(PerformanceTimeDetails item) => item.minute == null
    ? ''
    : " ${item.minute}${(item.addedMinute ?? 0) > 0 ? '+${item.addedMinute}' : ''}'";

class PlayerSummaryTab extends StatefulWidget {
  const PlayerSummaryTab({
    super.key,
    required this.person,
    required this.data,
    this.source,
    this.sql,
  });
  final Person person;
  final PlayerProfileData data;
  final SqlService? sql;

  @visibleForTesting
  final PlayerSummarySource? source;

  @override
  State<PlayerSummaryTab> createState() => _PlayerSummaryTabState();
}

class _PlayerSummaryTabState extends State<PlayerSummaryTab>
    with AutomaticKeepAliveClientMixin {
  late Future<PlayerSummarySource> _source = _load();

  String? _seasonId;

  final _sectionKeys = <String, GlobalKey>{};

  @override
  bool get wantKeepAlive => true;

  Future<PlayerSummarySource> _load() => widget.source != null
      ? Future.value(widget.source)
      : PlayerSummarySource.load(widget.person, widget.data, sql: widget.sql);

  @override
  void didUpdateWidget(PlayerSummaryTab old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) _source = _load();
  }

  String _seasonLabel(String? id) {
    final season = widget.data.seasons.where((s) => s.id == id).firstOrNull;
    return season == null ? 'Temporada' : _name(season);
  }

  static String _name(Season season) =>
      season.startDate.year == season.endDate.year
      ? '${season.startDate.year}'
      : '${season.startDate.year}/${season.endDate.year}';

  String _shortSeason(String id) {
    final season = widget.data.seasons.where((s) => s.id == id).firstOrNull;
    if (season == null) return '?';
    String year(int y) => (y % 100).toString().padLeft(2, '0');
    return season.startDate.year == season.endDate.year
        ? '${season.startDate.year}'
        : '${year(season.startDate.year)}/${year(season.endDate.year)}';
  }

  String _opponent(Map<String, Object?> row) {
    final id = row['oppositeTeamId']?.toString() ?? '';
    return GameCatalog.current?.teamLabel(
          widget.person.fifaVersion,
          id,
          leagueId: row['oppositeTeamLeagueId']?.toString(),
        ) ??
        id;
  }

  Widget _panel(String title, List<Widget> children, {String? subtitle}) =>
      ProfilePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                color: AppColors.of(context).text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: AppColors.of(context).muted,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );

  Widget _seasonPicker() {
    final played = {for (final m in widget.data.matches) m.seasonId};
    final seasons =
        widget.data.seasons.where((s) => played.contains(s.id)).toList()
          ..sort((a, b) => b.startDate.compareTo(a.startDate));
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.only(left: 14, right: 10),
      decoration: BoxDecoration(
        color: AppColors.of(context).panel,
        border: Border.all(color: AppColors.of(context).line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_month_outlined,
            size: 18,
            color: AppColors.of(context).accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _seasonId ?? '',
                isExpanded: true,
                dropdownColor: AppColors.of(context).panel,
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Todas as temporadas'),
                  ),
                  for (final season in seasons)
                    DropdownMenuItem(
                      value: season.id,
                      child: Text('Temporada ${_name(season)}'),
                    ),
                ],
                onChanged: (value) => setState(
                  () =>
                      _seasonId = value == null || value.isEmpty ? null : value,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<(String, String)> _sections(PlayerSummary s) => [
    ('overview', 'Visão geral'),
    ('evolution', 'Evolução em campo'),
    if (s.totals.ratedMatches > 0) ('ratings', 'Atuações e notas'),
    if (s.contributions > 0) ('minutes', 'Gols e assistências por minuto'),
    if (s.withHim.games > 0) ('withWithout', 'Com ele e sem ele'),
    if (s.minutesOn > 0) ('onPitch', 'Em campo e fora de campo'),
    ('decisive', 'Jogos decisivos'),
    if (s.contributions > 0) ('partners', 'Parcerias'),
    if (s.goalTypes.isNotEmpty) ('goalTypes', 'Tipos de gol'),
    ('scoring', 'Mapas e cobranças'),
    ('captaincy', 'Capitania'),
    ('detailed', 'Estatísticas detalhadas'),
    if (s.competitions.length > 1 && s.contributions > 0)
      ('competitions', 'Por competição'),
    if (_seasonId == null && s.seasons.length > 1) ('seasons', 'Por temporada'),
  ];

  Widget _content(PlayerSummary s, String section) => switch (section) {
    'scoring' => PlayerScoringInsights(matches: s.matches),
    'captaincy' => PlayerCaptainInsights(matches: s.matches),
    'detailed' => PlayerDetailedStats(matches: s.matches),
    'evolution' => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: PlayerPerformanceTrend(matches: s.matches),
    ),
    'ratings' => _ratings(s),
    'minutes' => _minutes(s),
    'withWithout' => _withWithout(s),
    'onPitch' => _onPitch(s),
    'decisive' => _decisive(s),
    'partners' => _partners(s),
    'goalTypes' => _goalTypes(s),
    'competitions' => _competitions(s),
    'seasons' => _seasons(s),
    _ => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: PlayerPerformanceOverview(
        matches: s.matches,
        title: 'Visão geral',
        subtitle: _seasonId == null
            ? 'Toda a trajetória do jogador.'
            : 'Desempenho em ${_seasonLabel(_seasonId)}.',
      ),
    ),
  };

  Widget _bar(String label, int value, int max, Color color, {String? text}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.of(context).muted,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.of(context).line,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    Container(
                      height: 10,
                      width: max == 0 ? 0 : box.maxWidth * value / max,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 58,
              child: Text(
                text ?? '$value',
                textAlign: TextAlign.right,
                style: _value(context),
              ),
            ),
          ],
        ),
      );

  Widget _legend(List<(Color, String)> items) => Wrap(
    spacing: 16,
    runSpacing: 6,
    children: [
      for (final (color, label) in items)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: AppColors.of(context).text, fontSize: 12),
            ),
          ],
        ),
    ],
  );

  static const _shortcuts = {
    'evolution': 'Evolução',
    'ratings': 'Notas',
    'minutes': 'Minuto a minuto',
    'withWithout': 'Com e sem ele',
    'onPitch': 'Em campo',
    'decisive': 'Decisivos',
    'partners': 'Parceiros',
    'goalTypes': 'Tipos',
    'scoring': 'Mapas',
    'captaincy': 'Braçadeira',
    'detailed': 'Detalhes',
    'competitions': 'Competições',
    'seasons': 'Temporadas',
  };

  Widget _jumpBar(List<(String, String)> sections) => SizedBox(
    height: 44,
    child: ListView(
      key: const ValueKey('player-summary-jump'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      children: [
        for (final (section, _) in sections.skip(1))
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              key: ValueKey('player-summary-jump/$section'),
              visualDensity: VisualDensity.compact,
              label: Text(
                _shortcuts[section] ?? section,
                style: const TextStyle(fontSize: 11.5),
              ),
              onPressed: () {
                final target = _sectionKeys[section]?.currentContext;
                if (target != null) {
                  Scrollable.ensureVisible(
                    target,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                  );
                }
              },
            ),
          ),
      ],
    ),
  );

  Widget _ratings(PlayerSummary s) {
    final rated = s.ratingBands.fold(0, (a, b) => a + b);
    final most = s.ratingBands.reduce(math.max);
    final form = s.recentForm;
    return _panel(
      'Atuações',
      subtitle:
          'Quantas partidas ele fez em cada faixa de nota · média '
          '${_decimal(s.totals.rating)} em $rated jogos avaliados.',
      [
        for (final (i, label) in summaryRatingBands.indexed)
          _bar(
            label,
            s.ratingBands[i],
            most,
            performanceRatingColor(5.5 + i),
            text:
                '${s.ratingBands[i]} · ${(s.ratingBands[i] * 100 / math.max(rated, 1)).round()}%',
          ),
        if (form.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Últimos jogos, do mais antigo ao mais recente',
            style: TextStyle(color: AppColors.of(context).muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (i, match) in form.indexed) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(child: _formChip(match)),
              ],
              for (var i = form.length; i < 10; i++) ...[
                const SizedBox(width: 4),
                const Expanded(child: SizedBox()),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _formChip(PlayerMatchData match) {
    final rating = match.performance.avgRating!;
    final result = fixtureResult(match.row);
    final date = match.date;
    return Tooltip(
      message:
          '${_opponent(match.row)} · ${match.row['playerTeamScore'] ?? 0}x${match.row['oppositeTeamScore'] ?? 0}'
          '${date == null ? '' : ' · ${DateFormat('dd/MM/yy').format(date)}'}',
      triggerMode: TooltipTriggerMode.tap,
      child: Column(
        children: [
          Container(
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: performanceRatingColor(rating),
              borderRadius: BorderRadius.circular(6),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _decimal(rating, 1),
                style: TextStyle(
                  color: AppColors.of(context).text,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: h2hResultColor(result),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _minutes(PlayerSummary s) {
    final bands = [
      for (var i = 0; i < summaryMinuteBands.length; i++)
        if (i < 6 || s.goalsByBand[i] + s.assistsByBand[i] > 0) i,
    ];
    final missing = [
      if (s.goalsWithoutMinute > 0)
        '${s.goalsWithoutMinute} gol${s.goalsWithoutMinute == 1 ? '' : 's'}',
      if (s.assistsWithoutMinute > 0)
        '${s.assistsWithoutMinute} assistência${s.assistsWithoutMinute == 1 ? '' : 's'}',
    ];
    return _panel(
      'Gols e assistências por minuto',
      subtitle: 'Em que momento do jogo ele aparece, em faixas de 15 minutos.',
      [
        _legend([(_goalColor, 'Gols'), (_assistColor, 'Assistências')]),
        const SizedBox(height: 12),
        _MinuteChart(
          labels: [for (final i in bands) summaryMinuteBands[i]],
          goals: [for (final i in bands) s.goalsByBand[i]],
          assists: [for (final i in bands) s.assistsByBand[i]],
        ),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${missing.join(' e ')} sem minuto registrado.',
            style: _note(context),
          ),
        ],
      ],
    );
  }

  Widget _recordRow(String label, TeamRecord record) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: AppColors.of(context).text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${record.games} jogo${record.games == 1 ? '' : 's'}',
              style: TextStyle(
                color: AppColors.of(context).muted,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        H2HRecordBar(
          wins: record.wins,
          draws: record.draws,
          losses: record.losses,
        ),
        const SizedBox(height: 6),
        H2HRecordPills(
          wins: record.wins,
          draws: record.draws,
          losses: record.losses,
          fontSize: 12,
        ),
      ],
    ),
  );

  Widget _withWithout(PlayerSummary s) {
    final withHim = s.withHim, without = s.withoutHim;
    final entries = [
      ComparisonEntry(0, 'Com ele', '${withHim.games} jogos'),
      ComparisonEntry(1, 'Sem ele', '${without.games} jogos'),
    ];
    ComparisonBarGroup group(
      String label,
      double? Function(TeamRecord) value, {
      int digits = 2,
      String suffix = '',
      double? scaleMax,
    }) {
      final values = [value(withHim), value(without)];
      return ComparisonBarGroup(
        label: label,
        values: values,
        texts: [
          for (final v in values)
            v == null ? '–' : '${_decimal(v, digits)}$suffix',
        ],
        scaleMax: scaleMax,
      );
    }

    return _panel(
      'Com ele e sem ele',
      subtitle: 'Resultados do time nos jogos em que ele jogou e nos que não.',
      [
        _recordRow('Com ele', withHim),
        if (without.games > 0) ...[
          _recordRow('Sem ele', without),
          const SizedBox(height: 4),
          ComparisonLegend(entries: entries),
          const SizedBox(height: 16),
          ComparisonGroupedBars(
            entries: entries,
            height: 130,
            groups: [
              group(
                'Aproveitamento',
                (r) => r.pointsShare,
                digits: 0,
                suffix: '%',
                scaleMax: 100,
              ),
              group('Gols pró por jogo', (r) => r.perGame(r.goalsFor)),
              group('Gols sofridos por jogo', (r) => r.perGame(r.goalsAgainst)),
            ],
          ),
        ] else
          Text(
            'Ele esteve em todas as partidas do time no período.',
            style: TextStyle(color: AppColors.of(context).muted, fontSize: 12),
          ),
        const SizedBox(height: 12),
        Text(
          'Partidas do clube nas temporadas em que ele jogou. Decisão por '
          'pênaltis conta como vitória ou derrota.',
          style: _note(context),
        ),
      ],
    );
  }

  Widget _onPitch(PlayerSummary s) {
    final on = (
      s.per90(s.forOn, s.minutesOn),
      s.per90(s.againstOn, s.minutesOn),
    );
    final off = (
      s.per90(s.forOff, s.minutesOff),
      s.per90(s.againstOff, s.minutesOff),
    );
    final minutes = NumberFormat.decimalPattern('pt_BR');
    final entries = [
      ComparisonEntry(0, 'Em campo', "${minutes.format(s.minutesOn)} min"),
      ComparisonEntry(
        1,
        'Fora de campo',
        "${minutes.format(s.minutesOff)} min",
      ),
    ];
    ComparisonBarGroup group(String label, double? a, double? b) =>
        ComparisonBarGroup(
          label: label,
          values: [a, b],
          texts: [_decimal(a), _decimal(b)],
        );
    return _panel(
      'Em campo e fora de campo',
      subtitle:
          'Gols do time a cada 90 minutos com ele em campo e sem ele, '
          'contando substituições e expulsão.',
      [
        Text(
          'Com ele em campo o time marca ${_decimal(on.$1)} e sofre '
          '${_decimal(on.$2)} gols a cada 90 minutos'
          '${s.minutesOff == 0 ? '.' : '; sem ele, marca ${_decimal(off.$1)} e sofre ${_decimal(off.$2)}.'}',
          style: TextStyle(
            color: AppColors.of(context).text,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        ComparisonLegend(entries: entries),
        const SizedBox(height: 16),
        ComparisonGroupedBars(
          entries: entries,
          height: 130,
          groups: [
            group('Gols pró por 90 min', on.$1, off.$1),
            group('Gols sofridos por 90 min', on.$2, off.$2),
          ],
        ),
        if (s.unassignedGoals > 0) ...[
          const SizedBox(height: 10),
          Text(
            '${s.unassignedGoals} gol${s.unassignedGoals == 1 ? '' : 's'} sem '
            'minuto, em jogos que ele não jogou inteiros, ficaram de fora.',
            style: _note(context),
          ),
        ],
      ],
    );
  }

  Widget _decisive(PlayerSummary s) {
    final recent = s.decisive.reversed.take(6).toList();
    return _panel(
      'Decisivo',
      subtitle:
          'Jogos em que, sem os gols dele e os gols que ele deu assistência, '
          'o time somaria menos pontos.',
      [
        AnalysisStrip(
          items: [
            ('${s.decidedMatches}', 'Jogos decididos'),
            ('${s.pointsSecured}', 'Pontos garantidos'),
            ('${s.winsSecured}', 'Vitórias'),
            ('${s.drawsSaved}', 'Empates'),
          ],
        ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (final item in recent) _decisiveRow(item),
        ],
        const SizedBox(height: 8),
        Text(
          'Conta o placar do jogo; a disputa de pênaltis vale como empate.',
          style: _note(context),
        ),
      ],
    );
  }

  Widget _decisiveRow(DecisiveMatch item) {
    final row = item.match.row;
    final goals = item.match.performance.goalDetails;
    final assists = item.match.performance.assistDetails;
    final date = item.match.date;
    final parts = [
      if (goals.isNotEmpty)
        '${goals.length == 1 ? 'Gol' : '${goals.length} gols'}${goals.map(_minute).join(',')}',
      if (assists.isNotEmpty)
        '${assists.length == 1 ? 'Assist.' : '${assists.length} assist.'}${assists.map(_minute).join(',')}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          H2HResultChip(fixtureResult(row)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row['playerTeamScore'] ?? 0}x${row['oppositeTeamScore'] ?? 0} '
                  'contra ${_opponent(row)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.of(context).text,
                    fontSize: 13,
                  ),
                ),
                Text(
                  [
                    if (date != null) DateFormat('dd/MM/yy').format(date),
                    parts.join(' · '),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.of(context).muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '+${item.points} pt${item.points == 1 ? '' : 's'}',
            style: _value(context)
                .copyWith(color: AppColors.of(context).accent),
          ),
        ],
      ),
    );
  }

  Widget _partners(PlayerSummary s) {
    Widget list(String title, List<(String, int)> people) {
      final most = people.isEmpty ? 0 : people.first.$2;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(color: AppColors.of(context).muted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          if (people.isEmpty)
            Text(
              'Nenhuma assistência registrada com o jogador.',
              style: TextStyle(
                color: AppColors.of(context).muted,
                fontSize: 12,
              ),
            )
          else
            for (final (name, count) in people)
              _bar(name, count, most, _assistColor),
        ],
      );
    }

    return _panel('Parcerias', [
      list('Quem mais deu assistência para ele', s.assistedBy),
      const SizedBox(height: 16),
      list('Para quem ele mais deu assistência', s.assistedTo),
    ]);
  }

  Widget _goalTypes(PlayerSummary s) {
    final most = s.goalTypes.first.$2;
    return _panel(
      'Tipos de gol',
      subtitle: 'Um gol pode ter mais de um tipo.',
      [
        for (final (type, count) in s.goalTypes.take(8))
          _bar(goalTypeLabel(type), count, most, _goalColor),
      ],
    );
  }

  Widget _competitions(PlayerSummary s) {
    final most = s.competitions.map((c) => c.$3 + c.$4).fold(0, math.max);
    return _panel('Por competição', [
      _legend([(_goalColor, 'Gols'), (_assistColor, 'Assistências')]),
      const SizedBox(height: 10),
      for (final (id, games, goals, assists) in s.competitions.take(8))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.data.tournamentNames[id] ?? id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.of(context).muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    '$goals G · $assists A · $games J',
                    style: _value(context),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _StackedBar(goals: goals, assists: assists, max: most),
            ],
          ),
        ),
    ]);
  }

  Widget _seasons(PlayerSummary s) => _panel(
    'Por temporada',
    subtitle: 'Toque numa temporada para ver os jogos e a média.',
    [
      _legend([(_goalColor, 'Gols'), (_assistColor, 'Assistências')]),
      const SizedBox(height: 12),
      _SeasonChart(
        labels: [for (final season in s.seasons) _shortSeason(season.$1)],
        goals: [for (final season in s.seasons) season.$3],
        assists: [for (final season in s.seasons) season.$4],
        details: [
          for (final (id, games, _, _, rating) in s.seasons)
            '${_seasonLabel(id)}\n$games jogos · média ${_decimal(rating)}',
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<PlayerSummarySource>(
      future: _source,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Erro ao montar o resumo: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final summary = PlayerSummary(
          allMatches: widget.data.matches,
          source: snapshot.data!,
          seasonId: _seasonId,
        );
        final sections = _sections(summary);
        return PlayerProfileScroll(
          key: const PageStorageKey('player-summary-statistics'),
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _seasonPicker(),
                if (summary.matches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(25),
                    child: Text(
                      'Nenhuma atuação registrada.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else ...[
                  _jumpBar(sections),
                  for (final (section, _) in sections)
                    KeyedSubtree(
                      key: _sectionKeys.putIfAbsent(
                        section,
                        () => GlobalKey(
                          debugLabel: 'player-summary-section/$section',
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey('player-summary-section/$section'),
                        child: _content(summary, section),
                      ),
                    ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}

class _StackedBar extends StatelessWidget {
  const _StackedBar({
    required this.goals,
    required this.assists,
    required this.max,
  });
  final int goals, assists, max;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final unit = max == 0 ? 0.0 : box.maxWidth / max;
      final parts = [
        (goals, _goalColor),
        (assists, _assistColor),
      ].where((p) => p.$1 > 0).toList();
      return Stack(
        children: [
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.of(context).line,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          Row(
            children: [
              for (final (i, (count, color)) in parts.indexed) ...[
                if (i > 0) const SizedBox(width: 2),
                Container(
                  height: 10,
                  width: math.max(0, unit * count - (i > 0 ? 2 : 0)),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.horizontal(
                      left: i == 0 ? const Radius.circular(5) : Radius.zero,
                      right: i == parts.length - 1
                          ? const Radius.circular(5)
                          : Radius.zero,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    },
  );
}

double _niceStep(int highest) =>
    highest <= 4 ? 1 : (highest / 4).ceilToDouble();

BarChartRodData _rod(int value, Color color) => BarChartRodData(
  toY: value.toDouble(),
  width: 11,
  color: color,
  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
);

FlTitlesData _titles(
  BuildContext context,
  List<String> labels,
  double step,
) => FlTitlesData(
  leftTitles: const AxisTitles(),
  topTitles: const AxisTitles(),
  rightTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: 26,
      interval: step,
      getTitlesWidget: (value, meta) => SideTitleWidget(
        meta: meta,
        space: 6,
        child: Text(
          '${value.round()}',
          style: TextStyle(color: AppColors.of(context).muted, fontSize: 10),
        ),
      ),
    ),
  ),
  bottomTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: 26,
      getTitlesWidget: (value, meta) {
        final i = value.toInt();
        if (i < 0 || i >= labels.length) return const SizedBox.shrink();
        return SideTitleWidget(
          meta: meta,
          space: 6,
          child: Text(
            labels[i],
            style: TextStyle(color: AppColors.of(context).muted, fontSize: 10),
          ),
        );
      },
    ),
  ),
);

BarChartData _groupedBars(
  BuildContext context, {
  required List<String> labels,
  required List<int> goals,
  required List<int> assists,
  required String Function(int group, int rod) tooltip,
}) {
  final highest = [...goals, ...assists].fold(0, math.max);
  final step = _niceStep(highest);
  return BarChartData(
    minY: 0,
    maxY: math.max(step, ((highest / step).floor() + 1) * step),
    alignment: BarChartAlignment.spaceAround,
    gridData: FlGridData(
      drawVerticalLine: false,
      horizontalInterval: step,
      getDrawingHorizontalLine: (_) => FlLine(
        color: AppColors.of(context).text.withValues(alpha: .10),
        strokeWidth: 1,
        dashArray: [4, 5],
      ),
    ),
    borderData: FlBorderData(
      border: Border(
        bottom: BorderSide(
          color: AppColors.of(context).text.withValues(alpha: .20),
        ),
      ),
    ),
    titlesData: _titles(context, labels, step),
    barGroups: [
      for (var i = 0; i < labels.length; i++)
        BarChartGroupData(
          x: i,
          barsSpace: 2,
          barRods: [_rod(goals[i], _goalColor), _rod(assists[i], _assistColor)],
        ),
    ],
    barTouchData: BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (_) => AppColors.of(context).background,
        tooltipBorderRadius: BorderRadius.circular(10),
        tooltipBorder: BorderSide(
          color: AppColors.of(context).text.withValues(alpha: .25),
        ),
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        maxContentWidth: 220,
        getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
          tooltip(groupIndex, rodIndex),
          TextStyle(
            color: AppColors.of(context).text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

class _MinuteChart extends StatelessWidget {
  const _MinuteChart({
    required this.labels,
    required this.goals,
    required this.assists,
  });
  final List<String> labels;
  final List<int> goals, assists;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 190,
    child: BarChart(
      _groupedBars(
        context,
        labels: labels,
        goals: goals,
        assists: assists,
        tooltip: (group, rod) =>
            "${labels[group]}'\n${rod == 0 ? 'Gols: ${goals[group]}' : 'Assistências: ${assists[group]}'}",
      ),
    ),
  );
}

class _SeasonChart extends StatelessWidget {
  const _SeasonChart({
    required this.labels,
    required this.goals,
    required this.assists,
    required this.details,
  });
  final List<String> labels, details;
  final List<int> goals, assists;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 200,
    child: BarChart(
      _groupedBars(
        context,
        labels: labels,
        goals: goals,
        assists: assists,
        tooltip: (group, _) =>
            '${details[group]}\n${goals[group]} gols · ${assists[group]} assistências',
      ),
    ),
  );
}
