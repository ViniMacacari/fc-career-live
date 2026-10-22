import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../ManagerCareer/Graphics/TeamAnalyticsCharts.dart';
import '../../ManagerCareer/Graphics/TeamAnalyticsData.dart';
import '../../models/Person.dart';
import '../../models/SeasonReview.dart';
import '../../utils/Components/CareerInsightWidgets.dart';
import '../../utils/Components/CareerPageWidgets.dart';
import '../../utils/Components/CareerUiStyle.dart';
import '../../utils/Components/TeamLogo.dart';
import '../../utils/SeasonClosureService.dart';
import 'SeasonTablePage.dart';

class SeasonRecapPage extends StatefulWidget {
  const SeasonRecapPage({
    super.key,
    required this.person,
    required this.review,
    this.playIntro = false,
    this.service,
  });
  final Person person;
  final SeasonReview review;
  final bool playIntro;
  final SeasonClosureService? service;
  @override
  State<SeasonRecapPage> createState() => _SeasonRecapPageState();
}

class _SeasonRecapPageState extends State<SeasonRecapPage> {
  late SeasonReview _review = widget.review;
  late final _service = widget.service ?? SeasonClosureService();
  int _tab = 0;
  AnalyticsMetric _metric = AnalyticsMetric.form;
  String _ranking = 'goals';
  String? _competition;
  bool _refreshing = false;
  @override
  void initState() {
    super.initState();
    if (widget.playIntro) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _play();
      });
    }
  }

  Future<void> _play() => Navigator.push<void>(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => SeasonStoryPage(review: _review, person: widget.person),
    ),
  );
  Future<void> _editTable(SeasonFinalTable table) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SeasonTablePage(
          person: widget.person,
          table: table,
          ownTeamId: table.ownTeamId ?? _ownTeam(table.tournamentId),
          onSave: (table) async {
            final updated = await _service.saveTable(
              widget.person,
              _review.season,
              table,
            );
            if (mounted) setState(() => _review = updated);
          },
        ),
      ),
    );
  }

  String _ownTeam(String id) =>
      _review.fixtures
          .where((f) => f['tournamentId'] == id)
          .lastOrNull?['playerTeamId']
          ?.toString() ??
      _review.teamId;
  Future<void> _refresh() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Atualizar retrospectiva?'),
        content: const Text(
          'Os números salvos serão substituídos pelos dados atuais desta temporada. Use esta opção após corrigir partidas ou estatísticas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Atualizar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _refreshing = true);
    try {
      final updated = await _service.refresh(widget.person, _review.season);
      if (mounted) setState(() => _review = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível atualizar. $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Widget _panel(String title, Widget child, {String? subtitle}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                subtitle,
                style: TextStyle(
                  color: CareerUiColors(context).muted,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
            ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    ),
  );

  Widget _summary() {
    final c = CareerUiColors(context), a = _review.analytics;
    final home = TeamAnalytics(
      a.matches.where((m) => m.location.toLowerCase() == 'home'),
    );
    final away = TeamAnalytics(
      a.matches.where((m) => m.location.toLowerCase() == 'away'),
    );
    String average(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsightStatGrid(
          items: [
            (
              '${a.played}',
              'Jogos registrados',
              Icons.sports_soccer_outlined,
              c.accent,
            ),
            (
              '${a.efficiency.toStringAsFixed(1)}%',
              'Aproveitamento',
              Icons.trending_up,
              c.green,
            ),
            ('${a.goalsFor}', 'Gols marcados', Icons.sports_soccer, c.green),
            (
              '${a.goalsAgainst}',
              'Gols sofridos',
              Icons.shield_outlined,
              c.amber,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _panel(
          'O retrato da campanha',
          AnalyticsResultsChart(data: a),
          subtitle: 'Vitórias, empates e derrotas pelo placar do jogo, antes dos pênaltis.',
        ),
        _panel(
          'Uma temporada em movimento',
          Column(
            children: [
              DropdownButtonFormField<AnalyticsMetric>(
                initialValue: _metric,
                decoration: const InputDecoration(
                  labelText: 'Estatística do gráfico',
                ),
                items: [
                  for (final m in AnalyticsMetric.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
                onChanged: (m) {
                  if (m != null) setState(() => _metric = m);
                },
              ),
              const SizedBox(height: 24),
              AnalyticsEvolutionChart(
                data: a,
                metric: _metric,
                onSelected: (match) => showModalBottomSheet<void>(
                  context: context,
                  useSafeArea: true,
                  builder: (_) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_date(match.date.toIso8601String())),
                        const SizedBox(height: 12),
                        Text(
                          '${_review.teamName(match.row['playerTeamId'])} ${match.scored}–${match.conceded} ${_review.teamName(match.row['oppositeTeamId'])}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('${match.row['stage'] ?? 'Partida'}'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          subtitle: 'A evolução do time, jogo a jogo. Toque no gráfico para explorar.',
        ),
        _panel(
          'Ataque, defesa e regularidade',
          InsightStatGrid(
            items: [
              (
                (a.scoredPerGame.toStringAsFixed(2)),
                'Gols por jogo',
                Icons.flash_on_outlined,
                c.green,
              ),
              (
                (a.concededPerGame.toStringAsFixed(2)),
                'Sofridos por jogo',
                Icons.security_outlined,
                c.amber,
              ),
              (
                '${a.cleanSheets}',
                'Jogos sem sofrer gols',
                Icons.verified_outlined,
                c.accent,
              ),
              (
                '${a.longestUnbeaten}',
                'Maior série invicta',
                Icons.local_fire_department_outlined,
                c.amber,
              ),
              (
                '${_review.longestWinning}',
                'Vitórias seguidas',
                Icons.bolt_outlined,
                c.green,
              ),
              (
                '${a.balance > 0 ? '+' : ''}${a.balance}',
                'Saldo de gols',
                Icons.compare_arrows,
                c.accent,
              ),
            ],
          ),
        ),
        _panel(
          'Dentro e fora de casa',
          Column(
            children: [
              for (final pair in [('Em casa', home), ('Fora de casa', away)])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    pair.$1 == 'Em casa'
                        ? Icons.home_outlined
                        : Icons.flight_takeoff_outlined,
                    color: c.accent,
                  ),
                  title: Text(pair.$1),
                  subtitle: Text(
                    '${pair.$2.played} jogos · ${pair.$2.wins}V ${pair.$2.draws}E ${pair.$2.losses}D',
                  ),
                  trailing: Text(
                    '${pair.$2.efficiency.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (a.mean((m) => m.possession) != null ||
            a.mean((m) => m.accuracy) != null)
          _panel(
            'A identidade do time',
            InsightStatGrid(
              items: [
                (
                  average(a.mean((m) => m.possession)),
                  'Posse média · ${a.samples((m) => m.possession)} jogos',
                  Icons.donut_large,
                  c.accent,
                ),
                (
                  average(a.mean((m) => m.accuracy)),
                  'Precisão de passe · ${a.samples((m) => m.accuracy)} jogos',
                  Icons.route_outlined,
                  c.green,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _competitions() {
    final c = CareerUiColors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final comp in _review.competitions)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CareerIconBadge(
                        icon: comp['won'] == true
                            ? Icons.emoji_events_outlined
                            : Icons.flag_outlined,
                        color: comp['won'] == true ? c.amber : c.accent,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${comp['name']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${comp['result']}',
                              style: TextStyle(
                                color: comp['won'] == true ? c.amber : c.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${comp['games']} jogos · ${comp['goalsFor']} gols pró · ${comp['goalsAgainst']} gols contra',
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                  if ((comp['path'] as List?)?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final stage in comp['path'] as List)
                            Chip(
                              label: Text(
                                '$stage',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (comp['kind'] == 'league' &&
                      !_review.tables.any((t) => t.tournamentId == comp['id']))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: OutlinedButton.icon(
                        onPressed: () => _editTable(_draftTable(comp)),
                        icon: const Icon(Icons.table_chart_outlined),
                        label: const Text('Fechar tabela'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        for (final t in _review.tables)
          SeasonStandingsCard(
            table: t,
            ownTeamId: t.ownTeamId ?? _ownTeam(t.tournamentId),
            version: widget.person.fifaVersion,
            onEdit: () => _editTable(t),
          ),
        if (_review.competitions.isEmpty)
          const CareerEmptyState(
            title: 'Sem competições registradas',
            subtitle:
                'As partidas e os resultados desta temporada aparecerão aqui.',
            icon: Icons.flag_outlined,
          ),
      ],
    );
  }

  SeasonFinalTable _draftTable(Map<String, Object?> comp) =>
      _review.draftTable('${comp['id']}');

  Widget _highlights() {
    final c = CareerUiColors(context);
    const metrics = {
      'goals': 'Gols',
      'assists': 'Assistências',
      'rating': 'Nota média',
      'matches': 'Jogos',
      'saves': 'Defesas',
      'keyPasses': 'Passes decisivos',
      'tackles': 'Desarmes',
      'minutes': 'Minutos',
    };
    final leaders = _review
        .leaders(_ranking)
        .where((p) => p[_ranking] != null)
        .take(10)
        .toList();
    Widget match(Map<String, Object?>? row, String title, IconData icon) =>
        row == null
        ? const SizedBox.shrink()
        : _panel(
            title,
            Row(
              children: [
                CareerIconBadge(icon: icon, color: c.amber),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_review.teamName(row['playerTeamId'])} × ${_review.teamName(row['oppositeTeamId'])}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _date('${row['date']}'),
                        style: TextStyle(color: c.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${row['playerTeamScore']}–${row['oppositeTeamScore']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                  ),
                ),
              ],
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        match(_review.bestWin, 'A maior vitória', Icons.bolt_outlined),
        match(_review.worstLoss, 'O jogo mais difícil', Icons.shield_outlined),
        _panel(
          widget.person.category == PersonCategory.manager
              ? 'Quem fez a diferença'
              : 'Sua temporada em números',
          Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _ranking,
                decoration: const InputDecoration(labelText: 'Ranking por'),
                items: [
                  for (final e in metrics.entries)
                    if (e.key != 'minutes' ||
                        widget.person.category == PersonCategory.player)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _ranking = v);
                },
              ),
              const SizedBox(height: 18),
              if (leaders.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Nenhuma estatística registrada para este ranking.',
                    style: TextStyle(color: c.muted),
                  ),
                ),
              for (final (i, p) in leaders.indexed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 17,
                    backgroundColor: c.accent.withValues(alpha: .1),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: c.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  title: Text(
                    '${p['name'] ?? 'Jogador'}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${p['matches']} jogos${_ranking == 'rating' ? ' · ${p['ratings']} notas registradas' : ''}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Text(
                    _ranking == 'rating'
                        ? (p[_ranking] as num).toStringAsFixed(2)
                        : '${p[_ranking]}',
                    style: TextStyle(
                      color: c.accent,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: 'Os rankings consideram as atuações registradas. Notas ausentes ficam fora da média.',
        ),
        if (_review.events.isNotEmpty)
          _panel(
            'Além das quatro linhas',
            InsightStatGrid(
              items: [
                (
                  '${_review.events.where((e) => e['type'] == 'transfer').length}',
                  'Movimentações no mercado',
                  Icons.swap_horiz,
                  c.accent,
                ),
                (
                  '${_review.events.where((e) => e['type'] == 'injury').length}',
                  'Lesões registradas',
                  Icons.healing_outlined,
                  c.amber,
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _date(String value) {
    final d = DateTime.tryParse(value);
    return d == null
        ? 'Data não informada'
        : DateFormat('dd/MM/yyyy').format(d);
  }

  Widget _journey() {
    final c = CareerUiColors(context);
    final rows = _review.fixtures
        .where((f) => _competition == null || f['tournamentId'] == _competition)
        .toList();
    final data = TeamAnalytics.fromRows(rows);
    final months = data.months;
    final timeline = [
      for (final f in rows) {...f, 'type': 'match'},
      if (_competition == null) ..._review.events,
    ]..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _competition ?? 'all',
          decoration: const InputDecoration(labelText: 'Filtrar jornada'),
          items: [
            const DropdownMenuItem(
              value: 'all',
              child: Text('Todas as competições'),
            ),
            for (final comp in _review.competitions)
              DropdownMenuItem(
                value: '${comp['id']}',
                child: Text('${comp['name']}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) =>
              setState(() => _competition = v == 'all' ? null : v),
        ),
        const SizedBox(height: 16),
        _panel(
          'Mês a mês',
          CareerTrendChart(
            label: 'Gols marcados',
            otherLabel: 'Gols sofridos',
            points: [
              for (final e in months.entries)
                CareerTrendPoint(
                  e.key.substring(5),
                  e.value.goalsFor.toDouble(),
                  other: e.value.goalsAgainst.toDouble(),
                  detail: '${e.key} · ${e.value.played} jogos',
                ),
            ],
          ),
          subtitle: 'Gols e atividade ao longo da temporada selecionada.',
        ),
        _panel(
          'O caminho até aqui',
          Column(
            children: [
              if (timeline.isEmpty)
                Text(
                  'Nenhum evento registrado nesta temporada.',
                  style: TextStyle(color: c.muted),
                ),
              for (final event in timeline)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(top: 5),
                            decoration: BoxDecoration(
                              color: event['type'] == 'match'
                                  ? c.accent
                                  : c.amber,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Container(width: 1, height: 48, color: c.line),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _date('${event['date']}'),
                              style: TextStyle(color: c.muted, fontSize: 10),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              event['type'] == 'match'
                                  ? '${_review.teamName(event['playerTeamId'])} ${event['playerTeamScore']}–${event['oppositeTeamScore']} ${_review.teamName(event['oppositeTeamId'])}'
                                  : event['type'] == 'transfer'
                                  ? '${event['name']} · movimentação no mercado'
                                  : '${event['name']} · lesão',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              event['type'] == 'match'
                                  ? '${_review.competitions.where((e) => e['id'] == event['tournamentId']).firstOrNull?['name'] ?? ''} · ${event['stage'] ?? 'Partida'}'
                                  : event['type'] == 'injury'
                                  ? '${event['description'] ?? 'Lesão registrada'}${event['days'] != null ? ' · ${event['days']} dias previstos' : ''}'
                                  : '${_review.teamName(event['from'])} → ${_review.teamName(event['to'])}',
                              style: TextStyle(
                                color: c.muted,
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Retrospectiva'),
        actions: [
          IconButton(
            tooltip: 'Rever apresentação',
            onPressed: _play,
            icon: const Icon(Icons.play_circle_outline),
          ),
          IconButton(
            tooltip: 'Atualizar dados da retrospectiva',
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
        children: [
          SeasonRecapHero(
            review: _review,
            person: widget.person,
            onPlay: _play,
          ),
          const SizedBox(height: 20),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, label) in [
                  'Resumo',
                  'Competições',
                  'Destaques',
                  'Jornada',
                ].indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _tab == i,
                      onSelected: (_) => setState(() => _tab = i),
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 280),
            child: KeyedSubtree(
              key: ValueKey(_tab),
              child: switch (_tab) {
                0 => _summary(),
                1 => _competitions(),
                2 => _highlights(),
                _ => _journey(),
              },
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Retrospectiva ${_review.season.isClosed ? 'salva' : 'prévia'} em ${_date(_review.savedAt.toIso8601String())}. ${_review.season.isClosed ? 'Você pode atualizar os dados após corrigir registros.' : 'Encerre a temporada para guardar este capítulo.'}',
            style: TextStyle(color: c.muted, fontSize: 10, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class SeasonRecapHero extends StatelessWidget {
  const SeasonRecapHero({
    super.key,
    required this.review,
    required this.person,
    this.onPlay,
  });
  final SeasonReview review;
  final Person person;
  final VoidCallback? onPlay;
  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(c.accent.withValues(alpha: .2), c.panel),
              c.panel,
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -65,
              top: -50,
              child: IgnorePointer(
                child: Icon(
                  Icons.sports_soccer_outlined,
                  size: 270,
                  color: c.accent.withValues(alpha: .06),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'SEU ANO EM CAMPO',
                        style: TextStyle(
                          color: c.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 2,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        review.season.isClosed
                            ? Icons.check_circle_outline
                            : Icons.timelapse,
                        color: c.accent,
                        size: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    review.label,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Um capítulo para lembrar.',
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      TeamLogo.lookup(
                        fifaVersion: person.fifaVersion,
                        teamId: review.teamId,
                        size: 38,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              review.teamName(review.teamId),
                              style: TextStyle(
                                color: c.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${review.analytics.played} jogos · ${review.titles} título${review.titles == 1 ? '' : 's'}',
                              style: TextStyle(color: c.muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (onPlay != null) ...[
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onPlay,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Rever os melhores momentos'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SeasonStoryPage extends StatefulWidget {
  const SeasonStoryPage({
    super.key,
    required this.review,
    required this.person,
  });
  final SeasonReview review;
  final Person person;
  @override
  State<SeasonStoryPage> createState() => _SeasonStoryPageState();
}

class _SeasonStoryPageState extends State<SeasonStoryPage>
    with SingleTickerProviderStateMixin {
  final _pages = PageController();
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  int _index = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 1;
    } else {
      _animation.forward();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.review, a = r.analytics, c = CareerUiColors(context);
    final scorer = r
        .leaders('goals')
        .where((p) => (p['goals'] as num? ?? 0) > 0)
        .firstOrNull;
    final chapters =
        <
          ({
            String eyebrow,
            String title,
            String detail,
            int number,
            String unit,
            IconData icon,
            Color color,
          })
        >[
          (
            eyebrow: 'TEMPORADA ${r.label}',
            title: 'Cada jogo,\numa história.',
            detail:
                '${r.teamName(r.teamId)}\nO caminho que você construiu nesta temporada.',
            number: a.played,
            unit: 'jogos registrados',
            icon: Icons.sports_soccer_outlined,
            color: c.accent,
          ),
          (
            eyebrow: 'O ATAQUE',
            title: 'A rede\nbalançou.',
            detail:
                '${a.scoredPerGame.toStringAsFixed(2)} gols por jogo.\n${a.wins} vitórias para comemorar.',
            number: a.goalsFor,
            unit: 'gols marcados',
            icon: Icons.bolt_outlined,
            color: c.green,
          ),
          (
            eyebrow: 'A REGULARIDADE',
            title: 'O time\nnão desistiu.',
            detail:
                'Maior série de ${a.longestUnbeaten} jogos invicto.\n${a.cleanSheets} partidas sem sofrer gols.',
            number: r.longestWinning,
            unit: 'vitórias consecutivas',
            icon: Icons.shield_outlined,
            color: c.accent,
          ),
          (
            eyebrow: 'AS CONQUISTAS',
            title: r.titles > 0
                ? 'O esforço\nvirou conquista.'
                : 'Uma campanha\npara aprender.',
            detail:
                r.competitions
                    .where((e) => e['won'] == true)
                    .map((e) => '${e['name']}')
                    .take(3)
                    .join('\n')
                    .isNotEmpty
                ? r.competitions
                      .where((e) => e['won'] == true)
                      .map((e) => '${e['name']}')
                      .take(3)
                      .join('\n')
                : '${r.competitions.length} competições fizeram parte desse capítulo.',
            number: r.titles,
            unit: 'títulos na temporada',
            icon: Icons.emoji_events_outlined,
            color: c.amber,
          ),
          if (scorer != null)
            (
              eyebrow: 'QUEM FEZ A DIFERENÇA',
              title: '${scorer['name'] ?? 'Seu artilheiro'}',
              detail:
                  '${scorer['assists'] ?? '—'} assistências · ${scorer['matches']} jogos\nO destaque entre as atuações registradas.',
              number: (scorer['goals'] as num).toInt(),
              unit: 'gols do artilheiro',
              icon: Icons.star_outline_rounded,
              color: c.amber,
            ),
          (
            eyebrow: 'UM CAPÍTULO COMPLETO',
            title: 'O próximo\ncomeça com você.',
            detail: 'Seus jogos, resultados e destaques ficam guardados aqui para rever quando quiser.',
            number: a.efficiency.round(),
            unit: '% de aproveitamento',
            icon: Icons.auto_awesome_outlined,
            color: c.accent,
          ),
        ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seu ano'),
        leading: IconButton(
          tooltip: 'Fechar apresentação',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ver detalhes'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
              child: Row(
                children: [
                  for (var i = 0; i < chapters.length; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        height: 4,
                        decoration: BoxDecoration(
                          color: i <= _index ? chapters[_index].color : c.line,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: chapters.length,
                onPageChanged: (i) {
                  setState(() => _index = i);
                  if (MediaQuery.disableAnimationsOf(context)) {
                    _animation.value = 1;
                  } else {
                    _animation.forward(from: 0);
                  }
                },
                itemBuilder: (context, i) {
                  final ch = chapters[i];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: AnimatedBuilder(
                      animation: _animation,
                      builder: (context, _) => Opacity(
                        opacity: Curves.easeOut.transform(_animation.value),
                        child: Transform.translate(
                          offset: Offset(
                            0,
                            22 *
                                (1 -
                                    Curves.easeOutCubic.transform(
                                      _animation.value,
                                    )),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 12),
                              Text(
                                ch.eyebrow,
                                style: TextStyle(
                                  color: ch.color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                ch.title,
                                style: TextStyle(
                                  fontSize: 36,
                                  height: 1.12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1,
                                  color: c.text,
                                ),
                              ),
                              const SizedBox(height: 28),
                              Container(
                                height: 240,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(32),
                                  gradient: RadialGradient(
                                    radius: 1,
                                    colors: [
                                      ch.color.withValues(alpha: .17),
                                      c.panel,
                                    ],
                                  ),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: _CelebrationPainter(
                                          ch.color,
                                          _animation.value,
                                        ),
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          ch.icon,
                                          size: 36,
                                          color: ch.color,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          '${(ch.number * Curves.easeOutCubic.transform(_animation.value)).round()}',
                                          style: TextStyle(
                                            color: c.text,
                                            fontSize: 72,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -3,
                                          ),
                                        ),
                                        Text(
                                          ch.unit,
                                          style: TextStyle(
                                            color: ch.color,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                ch.detail,
                                style: TextStyle(
                                  color: c.muted,
                                  fontSize: 14,
                                  height: 1.7,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Row(
                children: [
                  Text(
                    '${_index + 1} / ${chapters.length}',
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () {
                      if (_index == chapters.length - 1) {
                        Navigator.pop(context);
                      } else {
                        _pages.nextPage(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 380),
                          curve: Curves.easeInOutCubic,
                        );
                      }
                    },
                    icon: Icon(
                      _index == chapters.length - 1
                          ? Icons.insights_outlined
                          : Icons.arrow_forward,
                    ),
                    label: Text(
                      _index == chapters.length - 1
                          ? 'Explorar temporada'
                          : 'Próximo',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CelebrationPainter extends CustomPainter {
  _CelebrationPainter(this.color, this.progress);
  final Color color;
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2),
        paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    for (final radius in [75.0, 105.0, 140.0]) {
      paint.color = color.withValues(alpha: .09);
      canvas.drawCircle(center, radius, paint);
    }
    paint.style = PaintingStyle.fill;
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi * 2 / 24 + .12,
          distance =
              85 + 35 * Curves.easeOut.transform(progress) + (i % 3) * 14;
      final p =
          center +
          Offset(math.cos(angle) * distance, math.sin(angle) * distance);
      paint.color = color.withValues(alpha: (i % 3 == 0 ? .6 : .25) * progress);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(angle + progress);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: i % 2 == 0 ? 3 : 5,
            height: 7,
          ),
          const Radius.circular(1),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CelebrationPainter old) =>
      old.progress != progress || old.color != color;
}
