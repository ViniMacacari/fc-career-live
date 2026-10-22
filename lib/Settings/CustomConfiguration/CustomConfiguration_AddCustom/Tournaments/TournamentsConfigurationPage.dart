import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../utils/Components/TeamLogo.dart';
import '../../../../utils/databaseUtils.dart';
import '../../CustomConfigurationComponents.dart';
import 'CreateCustomTournamentPage.dart';
import 'EditCustomTournamentPage.dart';

class TournamentsConfigurationPage extends StatefulWidget {
  const TournamentsConfigurationPage({super.key});
  @override
  State<TournamentsConfigurationPage> createState() =>
      _TournamentsConfigurationPageState();
}

class _TournamentsConfigurationPageState
    extends State<TournamentsConfigurationPage> {
  late Future<List<CustomTournamentRow>> _rows =
      CustomContentService.getAllCustomTournaments();
  String _query = '';

  Future<void> _open(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<Object?>(builder: (_) => page));
    if (mounted) {
      setState(() => _rows = CustomContentService.getAllCustomTournaments());
    }
  }

  @override
  Widget build(BuildContext context) => CustomConfigurationTheme(
    child: Scaffold(
      appBar: AppBar(
        title: Text('customConfiguration.tournamentsConfiguration'.tr()),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'customConfiguration.createTournament'.tr(),
        onPressed: () => _open(const CreateCustomTournamentPage()),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          children: [
            CustomSearchField(
              hint: 'customConfiguration.searchByName'.tr(),
              onChanged: (value) => setState(() => _query = value),
            ),
            Expanded(
              child: FutureBuilder<List<CustomTournamentRow>>(
                future: _rows,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _list(snapshot.data!);
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _list(List<CustomTournamentRow> all) {
    if (all.isEmpty) return const CustomEmptyState();
    final query = _query.trim().toLowerCase();
    final rows = all
        .where((row) => row.tournament.name.toLowerCase().contains(query))
        .toList();
    if (rows.isEmpty) return const CustomEmptyState(textKey: 'common.noItems');
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final tournament = row.tournament;
        return CustomListCard(
          onTap: () => _open(
            EditCustomTournamentPage(
              tournament: tournament,
              imagePath: row.imagePath,
            ),
          ),
          child: ListTile(
            leading: TeamLogo(
              imageUrl: tournament.imageName,
              imagePath: row.imagePath,
              width: 40,
              height: 40,
              fallbackIcon: Icons.emoji_events_outlined,
            ),
            title: Text(tournament.name),
            subtitle: Text(
              [
                if (tournament.abbreviation != null) tournament.abbreviation!,
                (tournament.fifaVersions ?? '').split(',').join(', '),
              ].where((part) => part.isNotEmpty).join(' · '),
            ),
          ),
        );
      },
    );
  }
}
