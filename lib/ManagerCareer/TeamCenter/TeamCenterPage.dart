import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../Common/FixtureDetailsPage.dart';
import '../../Common/FixtureResultTile.dart';
import '../../Common/Seasons/CreateSeason.dart';
import '../../RootPage/DrawerWidget.dart';
import '../../models/Person.dart';
import '../../utils/AppColors.dart';
import '../../utils/Components/CareerPageWidgets.dart';
import '../../utils/Components/CompactDashboardWidgets.dart';
import '../../utils/Components/PlayerAvatar.dart';
import '../../utils/Components/TeamLogo.dart';
import '../../utils/SqlService.dart';
import '../Academy/AcademyPage.dart';
import '../Academy/AcademyPlayerInfoPage.dart';
import '../InjuresPage/InjuresPage.dart';
import '../OtherPlayers/OtherPlayersPage.dart';
import '../PlayersStat/PlayerActivityPage.dart';
import '../PlayersStat/PlayersStatData.dart';
import '../PlayersStat/PlayersStatPage.dart';
import '../PlayersStat/RecordedPlayerStats.dart';
import '../TeamPage/TeamPage.dart';
import 'TeamCenterData.dart';

class TeamCenterPage extends StatefulWidget {
  const TeamCenterPage({super.key, required this.person, this.sql});
  final Person person;
  final SqlService? sql;
  @override
  State<TeamCenterPage> createState() => _TeamCenterPageState();
}

class _TeamCenterPageState extends State<TeamCenterPage> {
  late Future<TeamCenterData> _data = TeamCenterData.load(
    widget.person,
    sql: widget.sql,
  );
  Future<void> _refresh() async {
    setState(() => _data = TeamCenterData.load(widget.person, sql: widget.sql));
    await _data;
  }

  Future<void> _open(Widget page) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    if (mounted) await _refresh();
  }

  void _injuries() =>
      _open(InjuresPage(person: widget.person, initialOnlyInjured: true));
  void _statistics() =>
      _open(PlayersStatPage(person: widget.person, sql: widget.sql));

  Widget _avatar(Map<String, Object?> p, [double radius = 18]) => PlayerAvatar(
    fifaVersion: widget.person.fifaVersion,
    realPlayerId: p['realPlayerId']?.toString(),
    customAvatarFilePath: p['customAvatarFilePath']?.toString(),
    radius: radius,
  );

  TextStyle get _name =>
      const TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
  TextStyle get _caption =>
      TextStyle(color: AppColors.of(context).muted, fontSize: 11);

  Widget _hero(TeamCenterData d) {
    final c = AppColors.of(context), season = d.season!;
    final groups = <String, int>{'GOL': 0, 'DEF': 0, 'MEI': 0, 'ATA': 0};
    for (final p in d.roster) {
      final position =
          '${p['customPositionId'] ?? d.statistics.players[p['playerId']]?['positionId'] ?? ''}';
      final label = position == '0'
          ? 'GOL'
          : {'2', '3', '5', '7', '8'}.contains(position)
          ? 'DEF'
          : {'10', '12', '14', '16', '18'}.contains(position)
          ? 'MEI'
          : {'21', '23', '25', '27'}.contains(position)
          ? 'ATA'
          : null;
      if (label != null) groups[label] = groups[label]! + 1;
    }
    final formation = d.roster.firstOrNull?['lineupFormation'];
    Widget tag(String strong, [String? soft]) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.background.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.line.withValues(alpha: .6)),
      ),
      child: Text.rich(
        TextSpan(
          text: strong,
          style: TextStyle(
            color: c.text,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
          children: [
            if (soft != null)
              TextSpan(
                text: ' $soft',
                style: TextStyle(color: c.muted, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
    );
    return CareerPageHeader(
      title: d.catalog.teamLabel(
        widget.person.fifaVersion,
        widget.person.teamId,
      ),
      subtitle: [
        'Temporada ${season.startDate.year}${season.startDate.year == season.endDate.year ? '' : '/${season.endDate.year}'}',
        if (d.date != null) DateFormat('dd/MM/yyyy').format(d.date!),
      ].join(' · '),
      icon: Icons.groups_outlined,
      leading: TeamLogo.lookup(
        fifaVersion: widget.person.fifaVersion,
        teamId: widget.person.teamId,
        leagueId: widget.person.leagueId,
        size: 48,
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatStrip(
            items: [
              ('${d.roster.length}', 'Jogadores', null),
              ('${d.available}', 'Disponíveis', c.success),
              (
                '${d.injuredPlayers}',
                'Lesionados',
                d.injuredPlayers > 0 ? c.danger : null,
              ),
              (
                (d.averageOverall?.toStringAsFixed(1) ?? '—').replaceAll(
                  '.',
                  ',',
                ),
                'Geral médio',
                null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (formation != null) tag('$formation'),
              for (final group in groups.entries)
                tag('${group.value}', group.key),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shortcuts(TeamCenterData d) {
    final c = AppColors.of(context);
    Widget item(
      String label,
      IconData icon,
      VoidCallback onTap, {
      int? badge,
    }) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Badge(
                isLabelVisible: (badge ?? 0) > 0,
                label: Text('$badge'),
                backgroundColor: c.danger,
                textColor: AppColors.onColor(c.danger),
                child: CareerIconBadge(icon: icon, size: 44),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          item(
            'Elenco',
            Icons.groups_outlined,
            () => _open(TeamPage(person: widget.person, sql: widget.sql)),
          ),
          item(
            'Academia',
            Icons.school_outlined,
            () => _open(AcademyPage(person: widget.person)),
          ),
          item(
            'Lesões',
            Icons.healing_outlined,
            _injuries,
            badge: d.injuredPlayers,
          ),
          item('Estatísticas', Icons.query_stats_outlined, _statistics),
          item(
            'Outros times',
            Icons.person_search_outlined,
            () =>
                _open(OtherPlayersPage(person: widget.person, sql: widget.sql)),
          ),
        ],
      ),
    );
  }

  Widget _injuryList(TeamCenterData d) {
    final c = AppColors.of(context);
    final injured = <String, Map<String, Object?>>{};
    for (final i in d.injuries) {
      injured.putIfAbsent('${i['playerId']}', () => i);
    }
    return DashboardSection(
      title: 'Lesões ativas',
      action: DashboardLink('Ver todas', onTap: _injuries),
      child: Column(
        children: [
          for (final i in injured.values.take(3))
            Builder(
              builder: (context) {
                final p =
                    d.statistics.players[i['playerId']] ?? <String, Object?>{};
                final start = DateTime.tryParse('${i['startDate']}');
                final days = (i['expectedRecoveryDays'] as num?)?.toInt();
                final back = start == null || days == null
                    ? null
                    : start.add(Duration(days: days));
                return InkWell(
                  key: ValueKey('active-injury-${i['playerId']}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: _injuries,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        _avatar(p),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${p['name'] ?? 'Jogador'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _name,
                              ),
                              Text(
                                i['description']?.toString().isNotEmpty == true
                                    ? '${i['description']}'
                                    : 'Lesão registrada',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _caption,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              back == null
                                  ? 'Sem previsão'
                                  : DateFormat('dd/MM').format(back),
                              style: TextStyle(
                                color: c.danger,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (back != null) Text('retorno', style: _caption),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          if (injured.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('+${injured.length - 3} lesionados', style: _caption),
            ),
        ],
      ),
    );
  }

  Widget _leaders(TeamCenterData d) {
    final c = AppColors.of(context), season = d.season!;
    final filters = PlayersStatFilters(
      seasonId: season.id,
      teamId: widget.person.teamId,
    );
    final cards = [
      for (final (metric, label) in [
        (PlayersStatMetric.goals, 'Artilharia'),
        (PlayersStatMetric.assists, 'Assistências'),
        (PlayersStatMetric.rating, 'Melhor nota'),
      ])
        if (d.leaders(widget.person, metric).firstOrNull
            case final PlayersStatEntry entry)
          Expanded(
            child: Material(
              color: c.raised.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                key: ValueKey('season-leader-${metric.name}'),
                borderRadius: BorderRadius.circular(14),
                onTap: () => _open(
                  PlayerActivityPage(
                    person: widget.person,
                    data: d.statistics,
                    entry: entry,
                    filters: filters,
                    sql: widget.sql,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label.toUpperCase(),
                          maxLines: 1,
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _avatar(entry.player, 20),
                      const SizedBox(height: 8),
                      Text(
                        RecordedPlayerStats(
                          d.statistics.activity(entry.id, filters),
                        ).format(metric),
                        style: TextStyle(
                          color: c.accent,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    ];
    return DashboardSection(
      title: 'Destaques da temporada',
      action: DashboardLink('Ranking', onTap: _statistics),
      child: cards.isEmpty
          ? Text(
              'Cadastre atuações para acompanhar os destaques do elenco.',
              style: _caption,
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, card) in cards.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  card,
                ],
              ],
            ),
    );
  }

  Widget _recent(TeamCenterData d) {
    final c = AppColors.of(context);
    final form = d.fixtures.take(5).toList().reversed;
    return DashboardSection(
      title: 'Últimas partidas',
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final f in form)
            Builder(
              builder: (context) {
                final (label, color) = switch (fixtureResult(f)) {
                  FixtureResult.win => ('V', c.success),
                  FixtureResult.draw => ('E', c.warning),
                  FixtureResult.lose => ('D', c.danger),
                };
                return Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(left: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      child: Column(
        children: [
          for (final f in d.fixtures.take(3))
            RecordedFixtureTile(
              fixture: f,
              version: widget.person.fifaVersion,
              catalog: d.catalog,
              detail: d.statistics.tournamentNames[f['tournamentId']],
              onTap: () => _open(
                FixtureDetailsPage(
                  person: widget.person,
                  fixture: f,
                  opponent: d.catalog.teamLabel(
                    widget.person.fifaVersion,
                    '${f['oppositeTeamId']}',
                  ),
                  tournament:
                      d.statistics.tournamentNames[f['tournamentId']] ??
                      'Competição',
                  sql: widget.sql,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _academy(TeamCenterData d) {
    final c = AppColors.of(context);
    final prospects = d.academy.toList()
      ..sort(
        (a, b) => ((b['potentialEnd'] ?? b['overall'] ?? 0) as num).compareTo(
          (a['potentialEnd'] ?? a['overall'] ?? 0) as num,
        ),
      );
    return DashboardSection(
      title: 'Talentos da academia',
      action: DashboardLink(
        'Ver base',
        onTap: () => _open(AcademyPage(person: widget.person)),
      ),
      child: Column(
        children: [
          for (final p in prospects.take(3))
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _open(
                AcademyPlayerInfoPage(person: widget.person, existing: p),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    _avatar(p),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${p['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _name,
                          ),
                          Text('Geral ${p['overall'] ?? '—'}', style: _caption),
                        ],
                      ),
                    ),
                    if (p['potentialStart'] != null ||
                        p['potentialEnd'] != null)
                      Tooltip(
                        message: 'Potencial',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: c.accent.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${p['potentialStart'] ?? '—'}–${p['potentialEnd'] ?? '—'}',
                            style: TextStyle(
                              color: c.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: RootDrawerScope.leading(context),
      title: const Text('Central do Elenco'),
    ),
    body: FutureBuilder<TeamCenterData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Não foi possível carregar o elenco.',
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                    onPressed: _refresh,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = snapshot.data!;
        if (d.season == null) {
          return CareerEmptyState(
            title: 'Crie a primeira temporada',
            subtitle: 'Organize o elenco, os talentos da base e a disponibilidade dos jogadores.',
            icon: Icons.groups_outlined,
            action: FilledButton(
              onPressed: () =>
                  _open(CreateSeasonPage(personId: widget.person.id)),
              child: const Text('Criar temporada'),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              _hero(d),
              _shortcuts(d),
              if (d.injuries.isNotEmpty) _injuryList(d),
              _leaders(d),
              if (d.fixtures.isNotEmpty) _recent(d),
              if (d.academy.isNotEmpty) _academy(d),
            ],
          ),
        );
      },
    ),
  );
}
