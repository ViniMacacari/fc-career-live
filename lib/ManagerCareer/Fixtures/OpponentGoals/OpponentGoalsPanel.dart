import '../../../utils/AppColors.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../models/ManagerFixture.dart';
import '../../../models/ManagerFixturePlayerPerformance.dart';
import '../../../models/Person.dart';
import '../../../models/OpponentLineup.dart';
import '../../../FcScore/FcScoreRepository.dart';
import '../../../utils/Components/PlayerAvatar.dart';
import '../../../utils/GamePlayers.dart';
import '../../../utils/FootballFormations.dart';
import '../../../utils/eventTimeUtils.dart';
import '../../TeamPage/SelectRealPlayerPage.dart';
import '../Performances/SelectGoalTypePage.dart';
import 'NameInputPage.dart';
import '../OpponentPlayerIdentityDialog.dart';

class OpponentGoalsPanel extends StatelessWidget {
  const OpponentGoalsPanel({
    super.key,
    required this.person,
    required this.goals,
    required this.onChanged,
    this.lineup,
    this.onLineupChanged,
    this.opponentTeamId,
    this.opponentLeagueId,
    this.seasonId,
    this.date,
    this.loadPlayers,
  });
  final Person person;
  final List<OpponentGoalDetails> goals;
  final ValueChanged<List<OpponentGoalDetails>> onChanged;
  final OpponentLineup? lineup;
  final ValueChanged<OpponentLineup>? onLineupChanged;
  final String? opponentTeamId, opponentLeagueId, seasonId;
  final DateTime? date;
  final Future<List<Map<String, Object?>>> Function()? loadPlayers;

  Future<String?> _pickName(BuildContext context, {String? current}) async {
    final players = <String, Map<String, Object?>>{
      for (final p in lineup?.squad.players.values ?? <Map<String, Object?>>[])
        if (hasFootballIdentity(p)) '${p['id']}': p,
    };
    final picked = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _OpponentGoalPicker(
        person: person,
        players: players.values.toList(),
        loadPlayers:
            loadPlayers ??
            (opponentTeamId == null
                ? null
                : () => FcScoreRepository().opponentPlayers(
                    person: person,
                    teamId: opponentTeamId!,
                    leagueId: opponentLeagueId,
                    seasonId: seasonId,
                    beforeDate: date,
                  )),
        canCreate: lineup != null && onLineupChanged != null,
      ),
    );
    if (picked == null || !context.mounted) return null;
    if (picked['action'] == 'create') {
      final next = lineup!.addReserve('');
      final id = next.squad.bench.last;
      final identity = await showDialog<OpponentPlayerIdentity>(
        context: context,
        builder: (_) =>
            OpponentPlayerIdentityDialog(person: person, playerId: id),
      );
      if (identity == null || !context.mounted) return null;
      onLineupChanged!(
        next.withIdentity(id, name: identity.name, photo: identity.photo),
      );
      return identity.name;
    }
    if (picked['action'] == 'manual') {
      return Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => NameInputPage(initialValue: current)),
      );
    }
    if (picked['action'] == null) {
      final id = '${picked['id']}';
      if (lineup != null &&
          onLineupChanged != null &&
          !lineup!.squad.players.containsKey(id)) {
        onLineupChanged!(
          lineup!.copy(
            squad: lineup!.squad.copy(
              players: {...lineup!.squad.players, id: picked},
              bench: [...lineup!.squad.bench, id],
            ),
          ),
        );
      }
      return picked['name'] as String?;
    }
    final player = await Navigator.push<GamePlayer>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectRealPlayerPage.pick(person: person),
      ),
    );
    return player?.name;
  }

  void _emit(List<OpponentGoalDetails> next) =>
      onChanged(getSortedDetails(next));

  Future<void> _add(BuildContext context, bool ownGoal) async {
    final name = await _pickName(context);
    if (name == null) return;
    _emit([
      ...goals,
      OpponentGoalDetails(scorerName: name, isOwnGoal: ownGoal),
    ]);
  }

  int _defaultMinute() {
    final timed = goals.where((goal) => goal.minute != null).toList();
    if (timed.isEmpty) return 0;
    final last = getSortedDetails(timed).last.minute!;
    return last + 1 > 140 ? 140 : last + 1;
  }

  Widget _chip(
    BuildContext context, {
    required Widget child,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final c = AppColors.of(context);
    final chip = Material(
      color: c.raised.withValues(alpha: .6),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 32,
          constraints: const BoxConstraints(minWidth: 36, maxWidth: 120),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: c.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: child,
          ),
        ),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip, child: chip);
  }

  Widget _row(BuildContext context, OpponentGoalDetails goal) {
    final c = AppColors.of(context);
    final name = goal.scorerName.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                final picked = await _pickName(context, current: name);
                if (picked == null) return;
                goal.scorerName = picked;
                _emit(goals);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      size: 17,
                      color: c.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name.isEmpty ? 'Escolher jogador' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: name.isEmpty ? c.accent : c.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _chip(
            context,
            tooltip: 'fixtures.goalTime'.tr(),
            onTap: () async {
              final value = await getEventTime(
                context,
                'fixtures.goalTime'.tr(),
                goal.minute ?? _defaultMinute(),
                goal.addedMinute,
              );
              if (value == null) return;
              goal
                ..minute = value.minute
                ..addedMinute = value.addedMinute;
              _emit(goals);
            },
            child: goal.minute == null
                ? Icon(Icons.more_time, size: 17, color: c.muted)
                : Text(formatEventMinute(goal.minute, goal.addedMinute)),
          ),
          if (!goal.isOwnGoal) ...[
            const SizedBox(width: 6),
            Flexible(
              child: _chip(
                context,
                tooltip: 'fixtures.selectGoalType'.tr(),
                onTap: () async {
                  final types = await Navigator.push<List<GoalType>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SelectGoalTypePage(selected: goal.type),
                    ),
                  );
                  if (types == null) return;
                  goal.type = types;
                  _emit(goals);
                },
                child: goal.type.isEmpty
                    ? Icon(Icons.category_outlined, size: 17, color: c.muted)
                    : Text(goal.type.map(goalTypeLabel).join(' · ')),
              ),
            ),
          ],
          IconButton(
            tooltip: 'common.remove'.tr(),
            visualDensity: VisualDensity.compact,
            onPressed: () =>
                _emit(goals.where((item) => item.id != goal.id).toList()),
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.muted),
          ),
        ],
      ),
    );
  }

  Widget _block(BuildContext context, String title, bool ownGoal) {
    final c = AppColors.of(context);
    final items = getSortedDetails(
      goals.where((goal) => goal.isOwnGoal == ownGoal),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              TablerIcons.ballFootball,
              size: 17,
              color: ownGoal ? c.danger : c.text,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                items.isEmpty ? title : '$title · ${items.length}',
                style: TextStyle(
                  color: c.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              key: ValueKey('add-opponent-${ownGoal ? 'own-goal' : 'goal'}'),
              onPressed: () => _add(context, ownGoal),
              style: TextButton.styleFrom(
                foregroundColor: c.accent,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(TablerIcons.plus, size: 16),
              label: const Text(
                'Adicionar',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        for (final goal in items) _row(context, goal),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _block(context, 'Gols marcados', false),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Divider(
          height: 1,
          color: AppColors.of(context).line.withValues(alpha: .4),
        ),
      ),
      _block(context, 'Gols contra (a seu favor)', true),
    ],
  );
}

class _OpponentGoalPicker extends StatefulWidget {
  const _OpponentGoalPicker({
    required this.person,
    required this.players,
    required this.canCreate,
    this.loadPlayers,
  });
  final Person person;
  final List<Map<String, Object?>> players;
  final bool canCreate;
  final Future<List<Map<String, Object?>>> Function()? loadPlayers;
  @override
  State<_OpponentGoalPicker> createState() => _OpponentGoalPickerState();
}

class _OpponentGoalPickerState extends State<_OpponentGoalPicker> {
  String query = '';
  late final players = {for (final p in widget.players) '${p['id']}': p};
  bool failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved =
          await widget.loadPlayers?.call() ?? <Map<String, Object?>>[];
      if (mounted) {
        setState(() {
          for (final p in saved.where(hasFootballIdentity)) {
            final previous = players['${p['id']}'];
            if (previous == null || !hasFootballIdentity(previous)) {
              players['${p['id']}'] = p;
            }
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Jogador do adversário',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('opponent-goal-search'),
              decoration: const InputDecoration(
                hintText: 'Buscar jogador',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  if (widget.canCreate)
                    ListTile(
                      leading: const Icon(Icons.person_add_alt),
                      title: const Text('Criar jogador neste adversário'),
                      subtitle: const Text('Nome e foto'),
                      onTap: () => Navigator.pop(context, <String, Object?>{
                        'action': 'create',
                      }),
                    ),
                  ListTile(
                    leading: const Icon(Icons.person_search),
                    title: Text('players.selectRealPlayer'.tr()),
                    onTap: () => Navigator.pop(context, <String, Object?>{
                      'action': 'real',
                    }),
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: Text('common.enterManually'.tr()),
                    onTap: () => Navigator.pop(context, <String, Object?>{
                      'action': 'manual',
                    }),
                  ),
                  const Divider(),
                  if (failed)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Não foi possível buscar os demais cadastros. O elenco disponível continua abaixo.',
                      ),
                    ),
                  for (final p in players.values.where(
                    (p) =>
                        hasFootballIdentity(p) &&
                        '${p['name']}'.toLowerCase().contains(query),
                  ))
                    ListTile(
                      leading: PlayerAvatar(
                        fifaVersion: widget.person.fifaVersion,
                        realPlayerId: p['realPlayerId'] as String?,
                        customAvatarFilePath:
                            p['customAvatarFilePath'] as String?,
                      ),
                      title: Text('${p['name']}'),
                      subtitle: const Text('Elenco adversário'),
                      onTap: () => Navigator.pop(context, p),
                    ),
                  if (players.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Nenhum jogador salvo para este adversário.'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
