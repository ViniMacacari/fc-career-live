import '../utils/AppColors.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/Person.dart';
import '../utils/Components/CareerPageWidgets.dart';
import '../utils/SqlService.dart';
import '../utils/competitions/TournamentAutomation.dart';
import 'EditSingleTrophy.dart';
import 'TrophyCampaignView.dart';

class ViewTrophyPage extends StatelessWidget {
  const ViewTrophyPage({
    super.key,
    required this.person,
    required this.trophy,
    required this.awardName,
    required this.teamName,
    this.competitionId,
    this.sql,
  });
  final Person person;
  final Map<String, Object?> trophy;
  final String awardName, teamName;
  final String? competitionId;
  final SqlService? sql;

  Future<void> _edit(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditSingleTrophy(person: person, trophy: trophy),
      ),
    );
    if (context.mounted && changed == true) Navigator.pop(context, true);
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('trophies.removeTrophy'.tr()),
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
    await (sql ?? SqlService.instance).deleteTrophy(trophy['id'] as String);
    await TournamentAutomation.dismiss(
      person.id,
      trophy['id'] as String,
      trophy: true,
    );
    if (context.mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(trophy['date'] as String? ?? '');
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('trophies.trophy'.tr()),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Resumo'),
              Tab(text: 'Partidas'),
              Tab(text: 'Registro'),
            ],
          ),
          actions: [
            IconButton(
              onPressed: () => _edit(context),
              tooltip: 'common.edit'.tr(),
              icon: const Icon(Icons.edit),
            ),
            IconButton(
              onPressed: () => _delete(context),
              tooltip: 'common.remove'.tr(),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: TrophyCampaignView(
          person: person,
          trophy: trophy,
          competitionId: competitionId,
          name: awardName,
          sql: sql,
          record: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              CareerPageHeader(
                title: awardName,
                eyebrow: 'Uma conquista para lembrar',
                subtitle: teamName,
                icon: Icons.emoji_events_outlined,
              ),
              CareerMetricTile(
                label: 'Quantidade de conquistas',
                value: '${trophy['count']}',
                icon: Icons.emoji_events_outlined,
                color: AppColors.trophyGold,
              ),
              Card(
                child: ListTile(
                  leading: const CareerIconBadge(icon: Icons.shield_outlined),
                  title: Text('teams.team'.tr()),
                  subtitle: Text(teamName),
                ),
              ),
              if (date != null)
                Card(
                  child: ListTile(
                    leading: const CareerIconBadge(
                      icon: Icons.calendar_month_outlined,
                    ),
                    title: Text('common.date'.tr()),
                    subtitle: Text('${date.day}/${date.month}/${date.year}'),
                  ),
                ),
              if ((trophy['description'] as String?)?.isNotEmpty == true)
                Card(
                  child: ListTile(
                    leading: const CareerIconBadge(icon: Icons.notes_rounded),
                    title: const Text('Descrição'),
                    subtitle: Text(trophy['description'] as String),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
