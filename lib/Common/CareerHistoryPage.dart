import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/Person.dart';
import '../Twitter/TwitterGenerationService.dart';
import '../utils/GameCatalog.dart';
import '../utils/SqlService.dart';
import '../utils/Components/CareerPageWidgets.dart';
import 'CareerHistoryForm.dart';
import '../RootPage/DrawerWidget.dart';

class CareerHistoryPage extends StatefulWidget {
  const CareerHistoryPage({super.key, required this.person});
  final Person person;
  @override
  State<CareerHistoryPage> createState() => _CareerHistoryPageState();
}

class _CareerHistoryPageState extends State<CareerHistoryPage> {
  late Future<(List<Map<String, Object?>>, GameCatalog)> _data = _load();

  Future<(List<Map<String, Object?>>, GameCatalog)> _load() async => (
    await SqlService.instance.getCareerHistory(
      widget.person.id,
      widget.person.category,
    ),
    await GameCatalog.load(),
  );

  Future<void> _edit([Map<String, Object?>? row]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CareerHistoryForm(person: widget.person, existing: row),
      ),
    );
    if (changed == true) setState(() => _data = _load());
  }

  Future<void> _delete(Map<String, Object?> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('history.removeHistoryItem'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('common.remove'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SqlService.instance.deleteCareerHistory(
      widget.person.category,
      row['id'] as String,
    );
    if (widget.person.category == PersonCategory.player) {
      await TwitterGenerationService.instance.onTransferDeleted(
        widget.person,
        row['id'] as String,
      );
    }
    setState(() => _data = _load());
  }

  String _nationalityLabel(GameCatalog catalog, String id) {
    for (final item in catalog.nationalities) {
      if (item.id == id) return item.label;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: RootDrawerScope.leading(context),
      title: Text('history.careerPath'.tr()),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () => _edit(),
      tooltip: 'history.createItem'.tr(),
      child: const Icon(Icons.add),
    ),
    body: FutureBuilder<(List<Map<String, Object?>>, GameCatalog)>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (rows, catalog) = snapshot.data!;
        if (rows.isEmpty) {
          return CareerEmptyState(
            title: 'common.noItems'.tr(),
            subtitle:
                'Registre os clubes, contratos e momentos da sua carreira.',
            icon: Icons.timeline_rounded,
            action: FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: Text('history.createItem'.tr()),
            ),
          );
        }
        final isPlayer = widget.person.category == PersonCategory.player;
        final labels = <String, String>{
          ...(isPlayer ? playerHistoryLabels : managerHistoryLabels),
          'startCareer': 'history.startedCareerAt'.tr(),
          if (isPlayer)
            'startExistingPlayerCareer': 'history.startedCareerAt'.tr(),
          if (!isPlayer) ...{
            'changeTeam': 'history.clubChange'.tr(),
            'contractChange': 'history.contractRenewal'.tr(),
            'startNationalTeam': 'history.joinedNationalTeam'.tr(),
            'endNationalTeam': 'history.leftNationalTeam'.tr(),
          },
          'retired': 'history.retired'.tr(),
        };
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: rows.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return CareerPageHeader(
                title: 'Sua trajetória',
                subtitle:
                    '${rows.length} registros que contam a história da carreira.',
                icon: Icons.timeline_rounded,
                eyebrow: widget.person.name,
              );
            }
            final row = rows[index - 1];
            final date = DateTime.tryParse(
              (row['transferDate'] ?? row['date']) as String? ?? '',
            );
            final from = row['fromTeamId'] as String?;
            final to = row['toTeamId'] as String?;
            final national = row['nationalTeamId'] as String?;
            final places = [
              if (from != null)
                catalog.teamLabel(widget.person.fifaVersion, from),
              if (to != null) catalog.teamLabel(widget.person.fifaVersion, to),
              if (national != null) _nationalityLabel(catalog, national),
            ];
            return Card(
              child: ListTile(
                leading: const CareerIconBadge(icon: Icons.flag_outlined),
                title: Text(labels[row['type']] ?? row['type'].toString()),
                subtitle: Text(
                  [
                    if (date != null) '${date.day}/${date.month}/${date.year}',
                    ...places,
                  ].join(' • '),
                ),
                onTap: () => _edit(row),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) =>
                      value == 'edit' ? _edit(row) : _delete(row),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('common.edit'.tr()),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('common.remove'.tr()),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
