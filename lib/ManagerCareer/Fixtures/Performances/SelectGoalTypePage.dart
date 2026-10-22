import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../models/ManagerFixturePlayerPerformance.dart';

const goalTypeSections = <String, List<GoalType>>{
  'fixtures.goalTypes.situation': [
    GoalType.openplay,
    GoalType.penalty,
    GoalType.directfreekick,
    GoalType.indirectfreekick,
    GoalType.cornercick,
    GoalType.counterattack,
  ],
  'fixtures.goalTypes.finish': [
    GoalType.header,
    GoalType.longshot,
    GoalType.volley,
    GoalType.chip,
    GoalType.bicyclekick,
    GoalType.solo,
  ],
  'fixtures.goalTypes.characteristics': [
    GoalType.cross,
    GoalType.rebound,
    GoalType.deflected,
  ],
};

String goalTypeLabel(GoalType type) => 'fixtures.goalTypes.${type.name}'.tr();

class SelectGoalTypePage extends StatefulWidget {
  const SelectGoalTypePage({super.key, required this.selected});
  final List<GoalType> selected;

  @override
  State<SelectGoalTypePage> createState() => _SelectGoalTypePageState();
}

class _SelectGoalTypePageState extends State<SelectGoalTypePage> {
  late final Set<GoalType> _selected = {...widget.selected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    bool visible(GoalType type) =>
        query.isEmpty || goalTypeLabel(type).toLowerCase().contains(query);
    return Scaffold(
      appBar: AppBar(title: Text('fixtures.selectGoalType'.tr())),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pop(
          context,
          GoalType.values.where(_selected.contains).toList(),
        ),
        label: Text('common.apply'.tr()),
        icon: const Icon(Icons.check),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          TextField(
            decoration: InputDecoration(
              labelText: 'customConfiguration.searchByName'.tr(),
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          for (final section in goalTypeSections.entries)
            if (section.value.any(visible)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                child: Text(
                  section.key.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final type in section.value.where(visible))
                Card(
                  child: CheckboxListTile(
                    value: _selected.contains(type),
                    title: Text(goalTypeLabel(type)),
                    subtitle: Text('fixtures.goalTypes.${type.name}_hint'.tr()),
                    onChanged: (checked) => setState(
                      () => checked == true
                          ? _selected.add(type)
                          : _selected.remove(type),
                    ),
                  ),
                ),
            ],
        ],
      ),
    );
  }
}
