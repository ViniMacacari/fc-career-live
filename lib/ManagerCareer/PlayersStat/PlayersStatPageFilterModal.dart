import '../../utils/AppColors.dart';

import 'package:flutter/material.dart';

import '../../models/Person.dart';
import '../TeamTransfers/TransferStyle.dart';
import 'PlayersStatData.dart';

class PlayersStatOption {
  const PlayersStatOption(this.id, this.label);
  final String? id;
  final String label;
}

Future<PlayersStatOption?> choosePlayersStatFilter(
  BuildContext context,
  String title,
  List<PlayersStatOption> options,
  String? selected,
) => showModalBottomSheet<PlayersStatOption>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppColors.of(context).background,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(title, style: const TextStyle(fontSize: 18)),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final option in options)
                  ListTile(
                    title: Text(option.label),
                    trailing: option.id == selected
                        ? Icon(Icons.check, color: AppColors.of(context).accent)
                        : null,
                    onTap: () => Navigator.pop(context, option),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);

List<PlayersStatOption> playersStatSeasonOptions(PlayersStatData data) => [
  const PlayersStatOption(null, 'Todas as Temporadas'),
  for (final season in data.seasons)
    PlayersStatOption(
      season.id,
      season.startDate.year == season.endDate.year
          ? '${season.startDate.year}'
          : '${season.startDate.year}/${season.endDate.year}',
    ),
];

List<PlayersStatOption> playersStatTournamentOptions(PlayersStatData data) {
  final options = [
    for (final id in data.recordedTournamentIds)
      PlayersStatOption(id, data.tournamentNames[id] ?? 'Torneio $id'),
  ];
  options.sort(
    (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
  );
  return [const PlayersStatOption(null, 'Todos os Torneios'), ...options];
}

List<PlayersStatOption> playersStatTeamOptions(
  PlayersStatData data,
  Person person,
) {
  final options = [
    for (final id in data.recordedTeamIds(person))
      PlayersStatOption(id, data.catalog.teamLabel(person.fifaVersion, id)),
  ];
  options.sort(
    (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
  );
  return [const PlayersStatOption(null, 'Todos os Times'), ...options];
}

String playersStatFilterLabel(List<PlayersStatOption> options, String? id) =>
    options.where((option) => option.id == id).firstOrNull?.label ??
    options.first.label;

Future<PlayersStatFilters?> showPlayersStatFilters(
  BuildContext context,
  PlayersStatData data,
  Person person,
  PlayersStatFilters current,
) => showModalBottomSheet<PlayersStatFilters>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppColors.of(context).background,
  showDragHandle: true,
  builder: (_) =>
      PlayersStatPageFilterModal(data: data, person: person, initial: current),
);

class PlayersStatPageFilterModal extends StatefulWidget {
  const PlayersStatPageFilterModal({
    super.key,
    required this.data,
    required this.person,
    required this.initial,
  });
  final PlayersStatData data;
  final Person person;
  final PlayersStatFilters initial;
  @override
  State<PlayersStatPageFilterModal> createState() =>
      _PlayersStatPageFilterModalState();
}

class _PlayersStatPageFilterModalState
    extends State<PlayersStatPageFilterModal> {
  late String? _season = widget.initial.seasonId,
      _tournament = widget.initial.tournamentId,
      _team = widget.initial.teamId;

  Future<void> _choose(
    String title,
    List<PlayersStatOption> options,
    String? selected,
    void Function(String?) save,
  ) async {
    final result = await choosePlayersStatFilter(
      context,
      title,
      options,
      selected,
    );
    if (mounted && result != null) setState(() => save(result.id));
  }

  @override
  Widget build(BuildContext context) => TransferTheme(
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filtros', style: TextStyle(fontSize: 19)),
            const SizedBox(height: 16),
            TransferPickerField(
              label: 'Temporada',
              value: playersStatFilterLabel(
                playersStatSeasonOptions(widget.data),
                _season,
              ),
              onTap: () => _choose(
                'Temporada',
                playersStatSeasonOptions(widget.data),
                _season,
                (id) => _season = id,
              ),
            ),
            const SizedBox(height: 14),
            TransferPickerField(
              label: 'Torneio',
              value: playersStatFilterLabel(
                playersStatTournamentOptions(widget.data),
                _tournament,
              ),
              onTap: () => _choose(
                'Torneio',
                playersStatTournamentOptions(widget.data),
                _tournament,
                (id) => _tournament = id,
              ),
            ),
            const SizedBox(height: 14),
            TransferPickerField(
              label: 'Time',
              value: playersStatFilterLabel(
                playersStatTeamOptions(widget.data, widget.person),
                _team,
              ),
              onTap: () => _choose(
                'Time',
                playersStatTeamOptions(widget.data, widget.person),
                _team,
                (id) => _team = id,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    PlayersStatFilters(
                      seasonId: _season,
                      tournamentId: _tournament,
                      teamId: _team,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.of(context).accent,
                    foregroundColor: AppColors.of(context).text,
                  ),
                  child: const Text('Aplicar'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
