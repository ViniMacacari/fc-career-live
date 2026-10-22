import '../utils/AppColors.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../utils/themes.dart';
import '../utils/Components/CareerPageWidgets.dart';

import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../models/Person.dart';
import '../utils/Components/TeamLogo.dart';
import '../utils/GameCatalog.dart';
import '../utils/SqlService.dart';
import 'HeadToHeadDetailPage.dart';
import 'HeadToHeadStats.dart';
import 'HeadToHeadWidgets.dart';

class HeadToHeadPage extends StatefulWidget {
  const HeadToHeadPage({
    super.key,
    required this.person,
    this.preloadedFixtures,
  });
  final Person person;

  @visibleForTesting
  final List<Map<String, Object?>>? preloadedFixtures;

  @override
  State<HeadToHeadPage> createState() => _HeadToHeadPageState();
}

typedef _Opponent = ({
  String id,
  String? leagueId,
  String name,
  HeadToHeadStats stats,
});

class _HeadToHeadPageState extends State<HeadToHeadPage> {
  late Future<List<_Opponent>> _data = _load();
  final _search = TextEditingController();

  Future<List<_Opponent>> _load() async {
    final fixtures =
        widget.preloadedFixtures ??
        await SqlService.instance.getFixtures(
          widget.person.id,
          widget.person.category,
        );
    final catalog = await GameCatalog.load();
    final groups = <String, List<Map<String, Object?>>>{};
    for (final fixture in fixtures) {
      groups.putIfAbsent('${fixture['oppositeTeamId']}', () => []).add(fixture);
    }
    final opponents = [
      for (final MapEntry(key: id, value: rows) in groups.entries)
        () {
          final stats = HeadToHeadStats(rows);
          final leagueId =
              stats.fixtures.first['oppositeTeamLeagueId'] as String?;
          return (
            id: id,
            leagueId: leagueId,
            name: catalog.teamLabel(
              widget.person.fifaVersion,
              id,
              leagueId: leagueId,
            ),
            stats: stats,
          );
        }(),
    ];
    opponents.sort(
      (a, b) => a.stats.games != b.stats.games
          ? b.stats.games.compareTo(a.stats.games)
          : HeadToHeadStats.date(b.stats.fixtures.first)
                .compareTo(HeadToHeadStats.date(a.stats.fixtures.first)),
    );
    return opponents;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(_Opponent opponent) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => HeadToHeadDetailPage(
          person: widget.person,
          opponentId: opponent.id,
          opponentLeagueId: opponent.leagueId,
        ),
      ),
    );
    if (mounted) setState(() => _data = _load());
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: careerDetailTheme(context),
    child: Scaffold(
      backgroundColor: AppColors.of(context).background,
      appBar: AppBar(
        backgroundColor: AppColors.of(context).background,
        foregroundColor: AppColors.of(context).text,
        title: Text('fixtures.headToHead'.tr()),
      ),
      body: FutureBuilder<List<_Opponent>>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                '${snapshot.error}',
                style: TextStyle(color: AppColors.of(context).text),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;
          if (all.isEmpty) {
            return Center(
              child: Text(
                'Nenhuma partida cadastrada.',
                style: TextStyle(color: AppColors.of(context).muted),
              ),
            );
          }
          final query = _search.text.trim().toLowerCase();
          final opponents = query.isEmpty
              ? all
              : all.where((o) => o.name.toLowerCase().contains(query)).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              CareerPageHeader(
                title: 'Cada rival, uma história',
                eyebrow: 'Confrontos diretos',
                subtitle:
                    '${all.length} adversários. Explore resultados, tendências e jogos marcantes.',
                icon: Icons.compare_arrows_rounded,
              ),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: AppColors.of(context).text),
                decoration: InputDecoration(
                  hintText: 'Buscar adversário',
                  hintStyle: TextStyle(color: AppColors.of(context).muted),
                  prefixIcon: Icon(
                    TablerIcons.search,
                    color: AppColors.of(context).muted,
                  ),
                  filled: true,
                  fillColor: AppColors.of(context).panel,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  '${all.length} adversários',
                  style: TextStyle(
                    color: AppColors.of(context).muted,
                    fontSize: 12.5,
                  ),
                ),
              ),
              for (final opponent in opponents)
                _OpponentCard(
                  person: widget.person,
                  opponent: opponent,
                  onTap: () => _open(opponent),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _OpponentCard extends StatelessWidget {
  const _OpponentCard({
    required this.person,
    required this.opponent,
    required this.onTap,
  });
  final Person person;
  final _Opponent opponent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stats = opponent.stats;
    final last = HeadToHeadStats.date(stats.fixtures.first);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.of(context).panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: AppColors.of(context).line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    TeamLogo.lookup(
                      fifaVersion: person.fifaVersion,
                      teamId: opponent.id,
                      leagueId: opponent.leagueId,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            opponent.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.of(context).text,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${stats.games} ${stats.games == 1 ? 'jogo' : 'jogos'} · '
                            'último em ${DateFormat('dd/MM/yyyy').format(last)}',
                            style: TextStyle(
                              color: AppColors.of(context).muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      TablerIcons.chevronRight,
                      color: AppColors.of(context).muted,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: H2HRecordPills(
                        wins: stats.wins,
                        draws: stats.draws,
                        losses: stats.losses,
                        fontSize: 12.5,
                      ),
                    ),
                    Text(
                      '${(stats.pointsShare * 100).round()}%',
                      style: TextStyle(
                        color: AppColors.of(context).text,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                H2HRecordBar(
                  wins: stats.wins,
                  draws: stats.draws,
                  losses: stats.losses,
                  height: 6,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
