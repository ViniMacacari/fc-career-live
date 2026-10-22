import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../models/TournamentResult.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/SqlService.dart';
import 'TournamentResultFormPage.dart';

class SeasonTournamentResultsPage extends StatefulWidget {
  const SeasonTournamentResultsPage({
    super.key,
    required this.person,
    required this.season,
  });
  final Person person;
  final Season season;

  @override
  State<SeasonTournamentResultsPage> createState() =>
      _SeasonTournamentResultsPageState();
}

class _SeasonTournamentResultsPageState
    extends State<SeasonTournamentResultsPage> {
  late Future<(List<TournamentResult>, Map<String, String>)> _data = _load();

  Future<(List<TournamentResult>, Map<String, String>)> _load() async {
    final catalog = await GameCatalog.load();
    final builtIn = await catalog.tournaments(widget.person.fifaVersion);
    final custom = await SqlService.instance.getCustomTournaments(
      widget.person.fifaVersion,
    );
    final labels = <String, String>{
      for (final item in builtIn) item.id: item.label,
      for (final item in custom) item.id: item.name,
      for (final item in catalog.leagues(widget.person.fifaVersion))
        'league:${item.id}': item.label,
    };
    final results = await SqlService.instance.getTournamentResults(
      widget.person.id,
      seasonId: widget.season.id,
    );
    results.sort(
      (a, b) => (labels[a.tournamentId] ?? a.tournamentId).compareTo(
        labels[b.tournamentId] ?? b.tournamentId,
      ),
    );
    return (results, labels);
  }

  Future<void> _open(TournamentResult? result) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TournamentResultFormPage(
          person: widget.person,
          season: widget.season,
          existing: result,
        ),
      ),
    );
    if (changed == true && mounted) setState(() => _data = _load());
  }

  Future<void> _delete(TournamentResult result) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('tournaments.removeResult'.tr()),
        content: Text('tournaments.removeResultConfirmation'.tr()),
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
    await SqlService.instance.deleteTournamentResult(
      widget.person.id,
      result.id,
    );
    if (mounted) setState(() => _data = _load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '${widget.season.startDate.year}/${widget.season.endDate.year}',
      ),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () => _open(null),
      tooltip: 'tournaments.createNewResult'.tr(),
      child: const Icon(Icons.add),
    ),
    body: FutureBuilder<(List<TournamentResult>, Map<String, String>)>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (results, labels) = snapshot.data!;
        if (results.isEmpty) {
          return Center(child: Text('tournaments.noResults'.tr()));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
          itemCount: results.length,
          itemBuilder: (context, index) {
            final result = results[index];
            return Card(
              child: ListTile(
                leading: Icon(
                  result.isWinner == true
                      ? Icons.emoji_events
                      : Icons.sports_soccer,
                ),
                title: Text(labels[result.tournamentId] ?? result.tournamentId),
                subtitle: Text(result.result),
                onTap: () => _open(result),
                trailing: IconButton(
                  tooltip: 'tournaments.removeResult'.tr(),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(result),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
