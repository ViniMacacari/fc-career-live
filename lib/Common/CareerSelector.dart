import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/Person.dart';
import '../utils/GameCatalog.dart';
import '../utils/SqlService.dart';
import '../utils/Components/CareerPageWidgets.dart';
import '../utils/Components/TeamLogo.dart';

class CareerSelector extends StatelessWidget {
  const CareerSelector({
    super.key,
    required this.category,
    required this.onSelected,
    required this.onCreate,
  });
  final PersonCategory category;
  final ValueChanged<Person> onSelected;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        category == PersonCategory.manager
            ? 'careers.selectManagerCareer'.tr()
            : 'careers.selectPlayerCareer'.tr(),
      ),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: onCreate,
      tooltip: 'careers.createNewCareer'.tr(),
      child: const Icon(Icons.add),
    ),
    body: FutureBuilder<List<Object>>(
      future: Future.wait<Object>([
        SqlService.instance.getPersons(category),
        GameCatalog.load(),
      ]),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final people = snapshot.data![0] as List<Person>;
        final catalog = snapshot.data![1] as GameCatalog;
        if (people.isEmpty) {
          return CareerEmptyState(
            title: 'Nenhuma carreira salva.',
            subtitle: 'Comece uma história e acompanhe cada temporada.',
            icon: Icons.flag_outlined,
            action: FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text('careers.createNewCareer'.tr()),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: people.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return CareerPageHeader(
                title: 'Escolha sua carreira',
                subtitle:
                    '${people.length} histórias salvas. Continue de onde parou.',
                icon: category == PersonCategory.manager
                    ? Icons.manage_accounts_outlined
                    : Icons.sports_soccer_outlined,
                eyebrow: category == PersonCategory.manager
                    ? 'Modo técnico'
                    : 'Modo jogador',
              );
            }
            final person = people[index - 1];
            return Card(
              child: ListTile(
                leading: TeamLogo.fromItem(
                  catalog.team(
                    person.fifaVersion,
                    person.teamId,
                    leagueId: person.leagueId,
                  ),
                  size: 42,
                ),
                title: Text(person.name),
                subtitle: Text(
                  '${person.fifaVersion} • '
                  '${catalog.teamLabel(person.fifaVersion, person.teamId)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await SqlService.instance.setActivePersonId(person.id);
                  onSelected(person);
                },
              ),
            );
          },
        );
      },
    ),
  );
}
