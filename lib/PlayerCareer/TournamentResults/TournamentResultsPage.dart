import '../../utils/AppColors.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../ManagerCareer/TeamPage/ViewPlayer/PlayerProfileVisuals.dart'
    show TournamentBadge;
import '../../RootPage/DrawerWidget.dart';
import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../models/TournamentResult.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/SqlService.dart';
import '../../utils/Components/CareerPageWidgets.dart';
import '../../utils/competitions/TournamentAutomation.dart';
import '../../utils/competitions/TournamentOutcomes.dart';
import 'TournamentResultFormPage.dart';
import '../../Common/Seasons/SeasonClosingPage.dart';
import '../../Common/Seasons/SeasonRecapPage.dart';
import '../../utils/SeasonClosureService.dart';
import '../../FcScore/CareerCompetitionsPage.dart';

const _gold = AppColors.tournamentGold;

class _Entry {
  const _Entry(this.tournamentId, {this.outcome, this.saved});
  final String tournamentId;
  final TournamentOutcome? outcome;
  final TournamentResult? saved;

  String get result => saved?.result ?? outcome?.resultText ?? '';
  bool get won => saved?.isWinner ?? outcome?.won ?? false;
  bool get automatic => saved == null || TournamentAutomation.isAuto(saved!.id);
  bool get inProgress =>
      saved == null && outcome?.status == OutcomeStatus.inProgress;
}

class _SeasonResults {
  const _SeasonResults(this.season, this.entries);
  final Season season;
  final List<_Entry> entries;
  int get titles => entries.where((e) => e.won).length;
}

class TournamentResultsPage extends StatefulWidget {
  const TournamentResultsPage({super.key, required this.person});
  final Person person;

  @override
  State<TournamentResultsPage> createState() => _TournamentResultsPageState();
}

class _TournamentResultsPageState extends State<TournamentResultsPage> {
  late Future<(List<_SeasonResults>, Map<String, String>)> _data = _load();

  Future<(List<_SeasonResults>, Map<String, String>)> _load() async {
    final person = widget.person;
    final db = SqlService.instance;
    await TournamentAutomation.trySync(person);
    final catalog = await GameCatalog.load();
    final builtIn = await catalog.tournaments(person.fifaVersion);
    final custom = await db.getCustomTournaments(person.fifaVersion);
    final labels = <String, String>{
      for (final item in builtIn) item.id: item.label,
      for (final item in custom) item.id: item.name,
      for (final item in catalog.leagues(person.fifaVersion))
        'league:${item.id}': item.label,
    };
    final seasons = [...await db.getSeasons(person.id)]
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    final fixtures = await db.getFixtures(person.id, person.category);
    final formatOf = await TournamentAutomation.formats(person);
    final saved = await db.getTournamentResults(person.id);
    final result = <_SeasonResults>[];
    for (final season in seasons) {
      final outcomes = await TournamentAutomation.outcomes(
        person,
        season,
        careerFixtures: fixtures,
        formatOf: formatOf,
      );
      final rows = saved.where((r) => r.seasonId == season.id).toList();
      TournamentResult? savedFor(String id) =>
          rows
              .where(
                (r) =>
                    r.tournamentId == id && !TournamentAutomation.isAuto(r.id),
              )
              .firstOrNull ??
          rows.where((r) => r.tournamentId == id).firstOrNull;
      final entries = [
        for (final outcome in outcomes)
          _Entry(
            outcome.tournamentId,
            outcome: outcome,
            saved: savedFor(outcome.tournamentId),
          ),
        for (final row in rows)
          if (!outcomes.any((o) => o.tournamentId == row.tournamentId) &&
              savedFor(row.tournamentId) == row)
            _Entry(row.tournamentId, saved: row),
      ];
      String label(_Entry e) => labels[e.tournamentId] ?? e.tournamentId;
      entries.sort((a, b) {
        if (a.won != b.won) return a.won ? -1 : 1;
        return label(a).toLowerCase().compareTo(label(b).toLowerCase());
      });
      result.add(_SeasonResults(season, entries));
    }
    return (result, labels);
  }

  void _reload() => setState(() => _data = _load());

  Future<void> _closeSeason(Season season, {bool tables = false}) async {
    try {
      if (season.isClosed && !tables) {
        final review = await SeasonClosureService().load(widget.person, season);
        if (!mounted) return;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                SeasonRecapPage(person: widget.person, review: review),
          ),
        );
      } else {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => SeasonClosingPage(
              person: widget.person,
              season: season,
              openTables: tables,
            ),
          ),
        );
      }
      if (mounted) _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir a temporada. $e')),
        );
      }
    }
  }

  Future<void> _edit(Season season, _Entry entry) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TournamentResultFormPage(
          person: widget.person,
          season: season,
          existing: entry.saved,
          initialTournamentId: entry.saved == null ? entry.tournamentId : null,
          initialResult: entry.saved == null ? entry.outcome?.resultText : null,
        ),
      ),
    );
    if (changed == true && mounted) _reload();
  }

  Future<void> _add(Season season) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TournamentResultFormPage(person: widget.person, season: season),
      ),
    );
    if (changed == true && mounted) _reload();
  }

  Future<void> _delete(TournamentResult result) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('tournaments.removeResult'.tr()),
        content: Text(
          TournamentAutomation.isAuto(result.id)
              ? 'Este resultado veio das partidas e não volta a ser criado.'
              : 'tournaments.removeResultConfirmation'.tr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('common.remove'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await TournamentAutomation.dismiss(widget.person.id, result.id);
    await SqlService.instance.deleteTournamentResult(
      widget.person.id,
      result.id,
    );
    if (mounted) _reload();
  }

  Widget _entry(Season season, _Entry entry, Map<String, String> labels) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final outcome = entry.outcome;
    final status = entry.won
        ? (Icons.emoji_events, _gold)
        : entry.inProgress
        ? (Icons.timelapse, theme.colorScheme.primary)
        : outcome?.status == OutcomeStatus.runnerUp
        ? (Icons.military_tech_outlined, AppColors.tournamentSilver)
        : (Icons.flag_outlined, muted);
    final record = outcome == null
        ? null
        : '${outcome.games} J · ${outcome.wins}V ${outcome.draws}E '
              '${outcome.losses}D · ${outcome.goalsFor}:${outcome.goalsAgainst}';
    return InkWell(
      onTap: () => _edit(season, entry),
      onLongPress: entry.saved == null ? null : () => _delete(entry.saved!),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TournamentBadge(
              version: widget.person.fifaVersion,
              tournamentId: entry.tournamentId,
              size: 34,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    labels[entry.tournamentId] ?? entry.tournamentId,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(status.$1, size: 16, color: status.$2),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          entry.result.isEmpty ? '–' : entry.result,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: entry.won ? FontWeight.w700 : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (outcome != null && outcome.path.length > 1) ...[
                    const SizedBox(height: 4),
                    Text(
                      outcome.path.join('  →  '),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                  if (record != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      record,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ],
              ),
            ),
            Tooltip(
              message: entry.saved == null
                  ? 'Em andamento: calculado pelas partidas'
                  : entry.automatic
                  ? 'Gerado pelas partidas'
                  : 'Resultado manual',
              child: Icon(
                entry.saved == null || entry.automatic
                    ? Icons.auto_awesome_outlined
                    : Icons.edit_note,
                size: 18,
                color: muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _season(_SeasonResults data, Map<String, String> labels) {
    final theme = Theme.of(context);
    final season = data.season;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    '${season.startDate.year}/${season.endDate.year}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 10),
                if (data.titles > 0)
                  Flexible(
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(
                        Icons.emoji_events,
                        size: 16,
                        color: _gold,
                      ),
                      label: Text(
                        '${data.titles} título${data.titles == 1 ? '' : 's'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: 'tournaments.createNewResult'.tr(),
                  icon: const Icon(Icons.add),
                  onPressed: () => _add(season),
                ),
              ],
            ),
            if (data.entries.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'tournaments.noResults'.tr(),
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              for (final (index, entry) in data.entries.indexed) ...[
                if (index > 0) const Divider(height: 1),
                _entry(season, entry, labels),
              ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CareerCompetitionsPage(
                        person: widget.person,
                        initialSeasonId: season.id,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.leaderboard_outlined, size: 18),
                  label: const Text('Tabelas e artilharia'),
                ),
                TextButton.icon(
                  onPressed: () => _closeSeason(season),
                  icon: Icon(
                    season.isClosed
                        ? Icons.auto_awesome_outlined
                        : Icons.check_circle_outline,
                    size: 18,
                  ),
                  label: Text(
                    season.isClosed ? 'Retrospectiva' : 'Encerrar temporada',
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _closeSeason(season, tables: true),
                  icon: const Icon(Icons.table_chart_outlined, size: 18),
                  label: const Text('Fechar tabela'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: RootDrawerScope.leading(context),
      title: Text('sections.tournamentResults'.tr()),
    ),
    body: FutureBuilder<(List<_SeasonResults>, Map<String, String>)>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (seasons, labels) = snapshot.data!;
        if (seasons.isEmpty) {
          return CareerEmptyState(
            title: 'common.noSeasonsMessage'.tr(),
            subtitle: 'Os torneios e as conquistas de cada temporada ficam reunidos aqui.',
            icon: Icons.emoji_events_outlined,
          );
        }
        final titles = seasons.fold(0, (sum, s) => sum + s.titles);
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.only(top: 6, bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                child: CareerPageHeader(
                  title: 'Campanhas e conquistas',
                  subtitle:
                      '$titles título${titles == 1 ? '' : 's'} em ${seasons.length} temporada${seasons.length == 1 ? '' : 's'}. Toque em uma competição para ver ou editar seu resultado.',
                  icon: Icons.emoji_events_outlined,
                  eyebrow: 'Resultados dos torneios',
                ),
              ),
              for (final season in seasons) _season(season, labels),
            ],
          ),
        );
      },
    ),
  );
}
