import 'package:flutter/material.dart';

import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../models/SeasonReview.dart';
import '../../utils/Components/CareerInsightWidgets.dart';
import '../../utils/Components/CareerPageWidgets.dart';
import '../../utils/Components/CareerUiStyle.dart';
import '../../utils/SeasonClosureService.dart';
import 'SeasonRecapPage.dart';
import 'SeasonTablePage.dart';

class SeasonClosingPage extends StatefulWidget {
  const SeasonClosingPage({
    super.key,
    required this.person,
    required this.season,
    this.initialReview,
    this.service,
    this.openTables = false,
  });
  final Person person;
  final Season season;
  final SeasonReview? initialReview;
  final SeasonClosureService? service;
  final bool openTables;
  @override
  State<SeasonClosingPage> createState() => _SeasonClosingPageState();
}

class _SeasonClosingPageState extends State<SeasonClosingPage> {
  late final _service = widget.service ?? SeasonClosureService();
  late Future<SeasonReview> _data = widget.initialReview != null
      ? Future.value(widget.initialReview)
      : _service.load(widget.person, widget.season);
  late int _tab = widget.openTables ? 1 : 0;
  bool _closing = false;
  String? _error;
  Future<void> _table(SeasonReview review, SeasonFinalTable table) async {
    final own =
        table.ownTeamId ??
        review.fixtures
            .where((f) => f['tournamentId'] == table.tournamentId)
            .lastOrNull?['playerTeamId']
            ?.toString() ??
        review.teamId;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SeasonTablePage(
          person: widget.person,
          table: table,
          ownTeamId: own,
          onSave: (t) async {
            final updated = await _service.saveTable(
              widget.person,
              widget.season,
              t,
            );
            if (mounted) setState(() => _data = Future.value(updated));
          },
        ),
      ),
    );
  }

  Future<void> _close() async {
    setState(() {
      _closing = true;
      _error = null;
    });
    try {
      final review = await _service.close(widget.person, widget.season);
      if (!mounted) return;
      await Navigator.pushReplacement<bool, void>(
        context,
        MaterialPageRoute(
          builder: (_) => SeasonRecapPage(
            person: widget.person,
            review: review,
            playIntro: true,
            service: _service,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Não foi possível encerrar a temporada. $e');
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.season.isClosed
              ? 'Tabelas da temporada'
              : 'Encerrar temporada',
        ),
      ),
      body: FutureBuilder<SeasonReview>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return CareerEmptyState(
              title: 'Não foi possível carregar a temporada',
              subtitle: '${snapshot.error}',
              icon: Icons.cloud_off_outlined,
              action: OutlinedButton(
                onPressed: () => setState(
                  () => _data = _service.load(widget.person, widget.season),
                ),
                child: const Text('Tentar novamente'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final r = snapshot.data!, a = r.analytics;
          final leagueComps = r.competitions
              .where((c) => c['kind'] == 'league')
              .toList();
          final drafts = [
            for (final comp in leagueComps)
              if (!r.tables.any((t) => t.tournamentId == comp['id']))
                r.draftTable('${comp['id']}'),
          ];
          if (leagueComps.isEmpty && r.tables.isEmpty) {
            drafts.add(
              r.draftTable(
                'league:${widget.person.leagueId}',
                name: 'Classificação do seu time',
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              CareerPageHeader(
                title: r.season.isClosed
                    ? 'O capítulo ${r.label}'
                    : 'Feche o capítulo ${r.label}',
                subtitle: 'Confira a campanha, registre a tabela final e guarde uma retrospectiva para rever depois.',
                icon: Icons.auto_awesome_outlined,
                eyebrow: 'Encerramento da temporada',
              ),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    label: Text('Revisão'),
                    icon: Icon(Icons.fact_check_outlined),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('Tabelas'),
                    icon: Icon(Icons.table_chart_outlined),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: _closing
                    ? null
                    : (s) => setState(() => _tab = s.single),
              ),
              const SizedBox(height: 22),
              if (_tab == 0) ...[
                InsightStatGrid(
                  items: [
                    (
                      '${a.played}',
                      'Jogos registrados',
                      Icons.sports_soccer_outlined,
                      c.accent,
                    ),
                    (
                      '${r.titles}',
                      'Títulos',
                      Icons.emoji_events_outlined,
                      c.amber,
                    ),
                    (
                      '${a.goalsFor}',
                      'Gols marcados',
                      Icons.bolt_outlined,
                      c.green,
                    ),
                    (
                      '${a.goalsAgainst}',
                      'Gols sofridos',
                      Icons.shield_outlined,
                      c.amber,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Antes do próximo capítulo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'O encerramento salva uma retrospectiva com jogos, gráficos, competições e destaques. Você poderá corrigir registros e atualizar a retrospectiva depois.',
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.table_chart_outlined,
                            color: c.accent,
                          ),
                          title: const Text('Classificação final'),
                          subtitle: Text(
                            '${r.tables.where((t) => t.isClosed).length} tabela(s) fechada(s). O preenchimento é opcional.',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => setState(() => _tab = 1),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.play_circle_outline,
                            color: c.accent,
                          ),
                          title: const Text('Prévia da retrospectiva'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SeasonRecapPage(
                                person: widget.person,
                                review: r,
                                service: _service,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  'Registre a posição final do seu time ou adicione os outros clubes. Não é necessário preencher a tabela para encerrar a temporada.',
                  style: TextStyle(color: c.muted, fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 12),
                for (final table in r.tables)
                  SeasonStandingsCard(
                    table: table,
                    ownTeamId:
                        table.ownTeamId ??
                        r.fixtures
                            .where(
                              (f) => f['tournamentId'] == table.tournamentId,
                            )
                            .lastOrNull?['playerTeamId']
                            ?.toString() ??
                        r.teamId,
                    version: widget.person.fifaVersion,
                    onEdit: _closing ? null : () => _table(r, table),
                  ),
                for (final table in drafts)
                  Card(
                    child: ListTile(
                      leading: CareerIconBadge(
                        icon: Icons.table_chart_outlined,
                      ),
                      title: Text(
                        table.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text('Classificação ainda não informada'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _closing ? null : () => _table(r, table),
                    ),
                  ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_error!, style: TextStyle(color: c.red)),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _closing
                    ? null
                    : r.season.isClosed
                    ? () => Navigator.pushReplacement<void, void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SeasonRecapPage(
                            person: widget.person,
                            review: r,
                            service: _service,
                          ),
                        ),
                      )
                    : _close,
                icon: _closing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _closing
                      ? 'Guardando sua temporada…'
                      : r.season.isClosed
                      ? 'Ver retrospectiva'
                      : 'Encerrar temporada',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Também funciona para temporadas anteriores da sua carreira.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted, fontSize: 11),
              ),
            ],
          );
        },
      ),
    );
  }
}
