import '../../utils/AppColors.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/ManagerFixturePlayerPerformance.dart';
import '../../utils/Components/CareerPageWidgets.dart';
import '../../utils/Components/CareerUiStyle.dart';
import '../../utils/Components/SelectionSearchField.dart';
import '../../utils/themes.dart';
import '../TeamPage/ViewPlayer/PlayerProfileVisuals.dart' show ProfilePortrait;
import 'Performances/TeamPlayersPerformanceGrid.dart'
    show performanceRatingColor;

Future<String?> showPlayerOfMatchPicker(
  BuildContext context, {
  required String fifaVersion,
  required List<ManagerFixturePlayerPerformance> performances,
  required Map<String, Map<String, Object?>> players,
  required Map<String, String> names,
  required Map<String, String> positions,
  String? selectedId,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  backgroundColor: Colors.transparent,
  builder: (context) => Theme(
    data: careerDetailTheme(context),
    child: AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: MediaQuery.viewInsetsOf(context).bottom > 0 ? .98 : .86,
        child: SelectPlayerOfMatchSheet(
          fifaVersion: fifaVersion,
          performances: performances,
          players: players,
          names: names,
          positions: positions,
          selectedId: selectedId,
        ),
      ),
    ),
  ),
);

class SelectPlayerOfMatchSheet extends StatefulWidget {
  const SelectPlayerOfMatchSheet({
    super.key,
    required this.fifaVersion,
    required this.performances,
    required this.players,
    required this.names,
    required this.positions,
    this.selectedId,
  });
  final String fifaVersion;
  final List<ManagerFixturePlayerPerformance> performances;
  final Map<String, Map<String, Object?>> players;
  final Map<String, String> names, positions;
  final String? selectedId;
  @override
  State<SelectPlayerOfMatchSheet> createState() =>
      _SelectPlayerOfMatchSheetState();
}

class _SelectPlayerOfMatchSheetState extends State<SelectPlayerOfMatchSheet> {
  final _search = TextEditingController();
  String _query = '';
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _card(ManagerFixturePlayerPerformance performance) {
    final c = CareerUiColors(context);
    final id = performance.playerInstanceId;
    final player = widget.players[id] ?? const <String, Object?>{};
    final name = widget.names[id] ?? player['name']?.toString() ?? 'Jogador';
    final selected = widget.selectedId == id;
    final position = widget.positions[id];
    final overall = player['overall'];
    final number = player['shirtNumber'];
    Widget metric(Widget icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(fontFamily: 'Manrope', fontSize: 11, color: c.muted),
        ),
      ],
    );
    return Semantics(
      selected: selected,
      button: true,
      child: Card(
        key: ValueKey('motm-player-$id'),
        color: selected
            ? Color.alphaBlend(c.amber.withValues(alpha: .08), c.panel)
            : c.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? c.amber.withValues(alpha: .6) : c.line,
          ),
        ),
        child: InkWell(
          onTap: () => Navigator.pop(context, id),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ProfilePortrait(
                    version: widget.fifaVersion,
                    realPlayerId: player['realPlayerId']?.toString(),
                    customAvatarFilePath: player['customAvatarFilePath']
                        ?.toString(),
                    width: 52,
                    height: 62,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          color: c.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (number != null) '#$number',
                          if (position != null && position.isNotEmpty) position,
                          if (overall != null) 'GER $overall',
                        ].join(' · '),
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 11,
                          color: c.muted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          metric(
                            Icon(
                              Icons.sports_soccer_rounded,
                              size: 14,
                              color: c.muted,
                            ),
                            '${performance.goalsCount ?? performance.goalDetails.length} gols',
                          ),
                          metric(
                            SvgPicture.asset(
                              'assets/images/assistBoot.svg',
                              width: 14,
                              height: 14,
                              colorFilter: ColorFilter.mode(
                                c.muted,
                                BlendMode.srcIn,
                              ),
                            ),
                            '${performance.assistsCount ?? performance.assistDetails.length} assist.',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  children: [
                    Icon(
                      selected
                          ? Icons.star_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected ? c.amber : c.muted.withValues(alpha: .6),
                      size: 22,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: performanceRatingColor(performance.avgRating),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        performance.avgRating?.toStringAsFixed(1) ?? '—',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          color: AppColors.onColor(
                            performanceRatingColor(performance.avgRating),
                          ),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Nota',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 9,
                        color: c.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final visible = widget.performances
        .where(
          (p) => selectionSearchKey(
            widget.names[p.playerInstanceId] ??
                widget.players[p.playerInstanceId]?['name']?.toString() ??
                '',
          ).contains(_query),
        )
        .toList();
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.muted.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, keyboardOpen ? 8 : 18, 12, 0),
              child: Row(
                children: [
                  CareerIconBadge(
                    icon: Icons.star_rounded,
                    color: c.amber,
                    size: keyboardOpen ? 32 : 44,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'fixtures.playerOfTheMatch'.tr(),
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: keyboardOpen ? 16 : 18,
                            fontWeight: FontWeight.w800,
                            color: c.text,
                          ),
                        ),
                        if (!keyboardOpen) ...[
                          const SizedBox(height: 5),
                          Text(
                            'Escolha o destaque da partida',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 11,
                              color: c.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, keyboardOpen ? 8 : 18, 16, 16),
              child: SelectionSearchField(
                key: const ValueKey('motm-player-search'),
                controller: _search,
                hint: 'players.searchPlayer'.tr(),
                onChanged: (value) =>
                    setState(() => _query = selectionSearchKey(value)),
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? const CareerEmptyState(
                      title: 'Nenhum jogador encontrado',
                      subtitle: 'Tente buscar por outro nome.',
                      icon: Icons.search_off_rounded,
                    )
                  : ListView.builder(
                      key: const ValueKey('motm-player-list'),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      itemCount: visible.length,
                      itemBuilder: (_, index) => _card(visible[index]),
                    ),
            ),
            if (widget.selectedId != null && !keyboardOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextButton.icon(
                  key: const ValueKey('clear-motm-selection'),
                  onPressed: () => Navigator.pop(context, ''),
                  icon: const Icon(Icons.star_outline_rounded, size: 18),
                  label: const Text('Remover escolha'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
