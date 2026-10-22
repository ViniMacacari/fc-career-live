import 'package:flutter/material.dart';

import '../Common/FixtureDetailsPage.dart';
import '../Common/FixtureResultTile.dart';
import '../models/Person.dart';
import '../utils/AppColors.dart';
import '../utils/Components/CompactDashboardWidgets.dart';
import '../utils/Components/PlayerAvatar.dart';
import '../utils/SqlService.dart';
import 'TrophyGalleryData.dart';

class TrophyCampaignView extends StatefulWidget {
  const TrophyCampaignView({
    super.key,
    required this.person,
    required this.trophy,
    required this.competitionId,
    required this.record,
    required this.name,
    this.sql,
  });
  final Person person;
  final Map<String, Object?> trophy;
  final String? competitionId;
  final Widget record;
  final String name;
  final SqlService? sql;
  @override
  State<TrophyCampaignView> createState() => _TrophyCampaignViewState();
}

class _TrophyCampaignViewState extends State<TrophyCampaignView> {
  late final _data = TrophyCampaignData.load(
    widget.person,
    widget.trophy,
    widget.competitionId,
    sql: widget.sql,
  );
  void _fixture(TrophyCampaignData data, Map<String, Object?> f) =>
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => FixtureDetailsPage(
            person: widget.person,
            fixture: f,
            opponent: data.catalog.teamLabel(
              widget.person.fifaVersion,
              '${f['oppositeTeamId']}',
            ),
            tournament: widget.name,
            sql: widget.sql,
          ),
        ),
      );
  Widget _leaders(
    String title,
    List<TrophyContributor> players,
    bool goals,
  ) => DashboardSection(
    title: title,
    subtitle: 'Produção nas atuações cadastradas desta campanha.',
    child: Column(
      children: [
        for (final p in players.take(5))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: PlayerAvatar(
              fifaVersion: widget.person.fifaVersion,
              realPlayerId: p.player['realPlayerId']?.toString(),
              customAvatarFilePath: p.player['customAvatarFilePath']
                  ?.toString(),
              radius: 19,
            ),
            title: Text(
              '${p.player['name']}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${p.games} atuações${p.rating == null ? '' : ' · nota ${p.rating!.toStringAsFixed(1)} (${p.ratings} avaliações)'}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Text(
              '${goals ? p.goals : p.assists}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<TrophyCampaignData>(
    future: _data,
    builder: (context, snapshot) {
      Widget message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
      if (snapshot.hasError) {
        return TabBarView(
          children: [
            message(
              'Não foi possível carregar a campanha. O registro da conquista continua disponível.',
            ),
            message('Campanha indisponível.'),
            widget.record,
          ],
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data!, c = AppColors.of(context);
      final decisive = data.fixtures
          .where((f) => f['id'] == widget.trophy['fixtureId'])
          .firstOrNull;
      return TabBarView(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DashboardSection(
                title: widget.name,
                subtitle:
                    '${widget.trophy['count'] ?? 1} conquista(s) neste registro',
                child: CompactMetrics(
                  columns: 4,
                  items: [
                    ('${data.fixtures.length}', 'Jogos registrados'),
                    ('${data.resultCount(FixtureResult.win)}', 'Vitórias'),
                    ('${data.resultCount(FixtureResult.draw)}', 'Empates'),
                    ('${data.resultCount(FixtureResult.lose)}', 'Derrotas'),
                  ],
                ),
              ),
              if (!data.linked || data.fixtures.isEmpty)
                DashboardSection(
                  title: 'Campanha sem partidas vinculadas',
                  child: Text(
                    !data.linked
                        ? 'Este troféu antigo não informa uma competição de forma inequívoca. O registro da conquista está preservado na aba Registro.'
                        : 'A conquista está registrada, mas não há partidas cadastradas para este clube, competição e período.',
                  ),
                ),
              if (data.fixtures.isNotEmpty)
                DashboardSection(
                  title: 'A campanha em números',
                  child: CompactMetrics(
                    items: [
                      ('${data.sum('playerTeamScore')}', 'Gols marcados'),
                      ('${data.sum('oppositeTeamScore')}', 'Gols sofridos'),
                      (
                        '${data.sum('playerTeamScore') - data.sum('oppositeTeamScore')}',
                        'Saldo de gols',
                      ),
                    ],
                  ),
                ),
              if (decisive != null)
                DashboardSection(
                  title: 'Partida da conquista',
                  child: RecordedFixtureTile(
                    fixture: decisive,
                    version: widget.person.fifaVersion,
                    catalog: data.catalog,
                    onTap: () => _fixture(data, decisive),
                  ),
                ),
              if (data.scorers.isNotEmpty)
                _leaders('Quem mais marcou', data.scorers, true),
              if (data.assistants.isNotEmpty)
                _leaders('Quem mais deu assistências', data.assistants, false),
              if (data.fixtures.isNotEmpty && data.contributors.isEmpty)
                DashboardSection(
                  title: 'Desempenho individual',
                  child: Text(
                    'Nenhuma atuação individual foi cadastrada para estas partidas.',
                    style: TextStyle(color: c.muted),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'O resumo considera somente as partidas e atuações registradas até a data da conquista, para este clube e esta competição.',
                  style: TextStyle(color: c.muted, fontSize: 11, height: 1.5),
                ),
              ),
            ],
          ),
          data.fixtures.isEmpty
              ? message('Nenhuma partida registrada para esta campanha.')
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: data.fixtures.length,
                  itemBuilder: (context, index) {
                    final f = data.fixtures[index];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        child: RecordedFixtureTile(
                          fixture: f,
                          version: widget.person.fifaVersion,
                          catalog: data.catalog,
                          detail: f['id'] == widget.trophy['fixtureId']
                              ? 'Conquista'
                              : 'Jogo ${index + 1}',
                          onTap: () => _fixture(data, f),
                        ),
                      ),
                    );
                  },
                ),
          widget.record,
        ],
      );
    },
  );
}
