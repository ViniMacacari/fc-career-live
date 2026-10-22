import '../../utils/AppColors.dart';
import '../../utils/themes.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../utils/GameCatalog.dart';
import '../../utils/databaseUtils.dart';
import '../TeamPage/ViewPlayer/PlayerProfileVisuals.dart' show ProfilePortrait;
import 'Performances/TeamPlayersPerformanceGrid.dart'
    show performanceRatingColor;

class SelectedTeamPlayer {
  const SelectedTeamPlayer(this.id, this.name);
  final String id, name;
}

class SelectTeamPlayerPage extends StatefulWidget {
  const SelectTeamPlayerPage({
    super.key,
    required this.fifaVersion,
    this.title,
    required this.roster,
    required this.names,
    required this.positions,
    this.excludeId,
    this.multiple = false,
    this.usedIds = const {},
    this.seasonStats,
  });

  final String fifaVersion;
  final String? title;
  final List<Map<String, Object?>> roster;
  final Map<String, String> names, positions;
  final String? excludeId;
  final bool multiple;
  final Set<String> usedIds;

  final Future<List<Map<String, Object?>>>? seasonStats;

  @override
  State<SelectTeamPlayerPage> createState() => _SelectTeamPlayerPageState();
}

class _SelectTeamPlayerPageState extends State<SelectTeamPlayerPage> {
  String _query = '';
  final Set<String> _positionFilter = {};
  final Set<String> _selectedIds = {};
  Map<String, Map<String, Object?>> _stats = const {};

  @override
  void initState() {
    super.initState();
    widget.seasonStats?.then((rows) {
      if (!mounted) return;
      setState(
        () =>
            _stats = {for (final row in rows) row['playerId'].toString(): row},
      );
    });
  }

  Widget _statsLine(Map<String, Object?> row, Color color) {
    final stats = _stats[_id(row)];
    int count(String key) => (stats?[key] as num?)?.toInt() ?? 0;
    final rating = (stats?['rating'] as num?)?.toDouble();
    final style = TextStyle(fontSize: 12, color: color);
    Widget item(Widget icon, int value) => Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 3),
          Text('$value', style: style),
        ],
      ),
    );
    return Row(
      children: [
        item(
          Icon(TablerIcons.shirtSport, size: 13, color: color),
          count('matches'),
        ),
        item(
          Icon(TablerIcons.ballFootball, size: 13, color: color),
          count('goals'),
        ),
        item(
          SvgPicture.asset(
            'assets/images/assistBoot.svg',
            width: 13,
            height: 13,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
          count('assists'),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: performanceRatingColor(rating),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            rating?.toStringAsFixed(1) ?? '–',
            style: TextStyle(fontSize: 11, color: AppColors.of(context).text),
          ),
        ),
      ],
    );
  }

  String _id(Map<String, Object?> row) => row['playerId'] as String;
  String? _positionId(Map<String, Object?> row) =>
      row['customPositionId'] as String? ?? row['positionId'] as String?;
  String _name(Map<String, Object?> row) =>
      widget.names[_id(row)] ?? row['customName']?.toString() ?? _id(row);

  late final List<Map<String, Object?>> _players = () {
    final rows = widget.roster
        .where((row) => row['playerId'] != null)
        .where((row) => _id(row) != widget.excludeId)
        .toList();
    final order = {for (var i = 0; i < rows.length; i++) _id(rows[i]): i};
    rows.sort((a, b) {
      final byPosition = getPositionPriority(_positionId(a))
          .compareTo(getPositionPriority(_positionId(b)));
      return byPosition != 0
          ? byPosition
          : order[_id(a)]!.compareTo(order[_id(b)]!);
    });
    return rows;
  }();

  late final List<String> _positionsInRoster = <String>{
    for (final row in _players)
      if (_positionId(row) != null) _positionId(row)!,
  }.toList();

  List<Map<String, Object?>> get _visible {
    final query = _query.trim().toLowerCase();
    return _players
        .where(
          (row) =>
              _positionFilter.isEmpty ||
              _positionFilter.contains(_positionId(row)),
        )
        .where(
          (row) => query.isEmpty || _name(row).toLowerCase().contains(query),
        )
        .toList();
  }

  bool _used(Map<String, Object?> row) => widget.usedIds.contains(_id(row));

  void _tap(Map<String, Object?> row) {
    if (_used(row)) return;
    if (!widget.multiple) {
      Navigator.pop(context, SelectedTeamPlayer(_id(row), _name(row)));
      return;
    }
    setState(() {
      if (!_selectedIds.remove(_id(row))) _selectedIds.add(_id(row));
    });
  }

  void _confirm() => Navigator.pop(context, [
    for (final row in _players)
      if (_selectedIds.contains(_id(row)))
        SelectedTeamPlayer(_id(row), _name(row)),
  ]);

  Widget _flag(Map<String, Object?> row) {
    final id = row['nationalityId']?.toString();
    final url = id == null
        ? null
        : GameCatalog.current?.nationalities
              .where((item) => item.id == id)
              .firstOrNull
              ?.imageUrl;
    if (url == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 18,
        height: 12,
        errorWidget: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _playerCard(Map<String, Object?> row) {
    final used = _used(row);
    final selected = _selectedIds.contains(_id(row));
    final textColor = used
        ? AppColors.of(context).muted
        : AppColors.of(context).text;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 5.5),
      child: Material(
        color: used
            ? AppColors.of(context).raised
            : AppColors.of(context).panel,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: used ? null : () => _tap(row),
          child: SizedBox(
            height: widget.seasonStats == null ? 65 : 76,
            child: Row(
              children: [
                if (widget.multiple) ...[
                  const SizedBox(width: 10),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? AppColors.of(context).accent : null,
                      border: Border.all(
                        color: selected
                            ? AppColors.of(context).accent
                            : AppColors.of(context).muted,
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? const Icon(TablerIcons.check, size: 15)
                        : null,
                  ),
                  const SizedBox(width: 18),
                ] else
                  const SizedBox(width: 16),
                Opacity(
                  opacity: used ? .6 : 1,
                  child: SizedBox(
                    width: 49,
                    child: Center(
                      child: ProfilePortrait(
                        version: widget.fifaVersion,
                        realPlayerId: row['realPlayerId'] as String?,
                        customAvatarFilePath:
                            row['customAvatarFilePath'] as String?,
                        width: 38,
                        height: 49,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name(row),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, color: textColor),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.positions[_id(row)] ??
                                  positionShortName(_positionId(row)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: used
                                    ? AppColors.of(context).muted
                                    : AppColors.of(context).muted,
                              ),
                            ),
                          ),
                          _flag(row),
                        ],
                      ),
                      if (widget.seasonStats != null) ...[
                        const SizedBox(height: 4),
                        _statsLine(
                          row,
                          used
                              ? AppColors.of(context).muted
                              : AppColors.of(context).muted,
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  width: 43,
                  height: 41,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: used
                        ? AppColors.of(context).raised
                        : AppColors.of(context).field,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${row['overall'] ?? '–'}',
                    style: TextStyle(fontSize: 16, color: textColor),
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _search() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
    child: TextField(
      onChanged: (value) => setState(() => _query = value),
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        hintText: 'players.searchPlayer'.tr(),
        hintStyle: TextStyle(color: AppColors.of(context).muted, fontSize: 15),
        prefixIcon: Padding(
          padding: EdgeInsets.only(left: 14, right: 10),
          child: Icon(
            TablerIcons.search,
            size: 24,
            color: AppColors.of(context).text,
          ),
        ),
        filled: true,
        fillColor: AppColors.of(context).field,
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.of(context).line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.of(context).line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.of(context).accent),
        ),
      ),
    ),
  );

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.of(context).accent,
      backgroundColor: AppColors.of(context).panel,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      labelStyle: TextStyle(color: AppColors.of(context).text, fontSize: 13),
    ),
  );

  Widget _filters() => SizedBox(
    height: 48,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      scrollDirection: Axis.horizontal,
      children: [
        _chip(
          'common.all'.tr(),
          _positionFilter.isEmpty,
          () => setState(_positionFilter.clear),
        ),
        for (final positionId in _positionsInRoster)
          _chip(
            positionShortName(positionId),
            _positionFilter.contains(positionId),
            () => setState(() {
              if (!_positionFilter.remove(positionId)) {
                _positionFilter.add(positionId);
              }
            }),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final selectable = _players.where((row) => !_used(row)).toList();
    return Theme(
      data: careerDetailTheme(context),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title ?? 'players.selectPlayer'.tr()),
          actions: [
            if (widget.multiple)
              PopupMenuButton<bool>(
                icon: const Icon(TablerIcons.dotsVertical),
                onSelected: (selectAll) => setState(() {
                  _selectedIds.clear();
                  if (selectAll) _selectedIds.addAll(selectable.map(_id));
                }),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: true,
                    child: Text('common.selectAll'.tr()),
                  ),
                  PopupMenuItem(
                    value: false,
                    child: Text('common.unselectAll'.tr()),
                  ),
                ],
              ),
          ],
        ),
        floatingActionButton: widget.multiple && _selectedIds.isNotEmpty
            ? FloatingActionButton.extended(
                onPressed: _confirm,
                backgroundColor: AppColors.of(context).accent,
                foregroundColor: AppColors.of(context).onAccent,
                icon: const Icon(TablerIcons.plus),
                label: Text(
                  '${'players.addPlayers'.tr()} (${_selectedIds.length})',
                ),
              )
            : null,
        body: _players.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'players.noTeamPlayers'.tr(),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : Column(
                children: [
                  _search(),
                  if (_positionsInRoster.length > 1) _filters(),
                  Expanded(
                    child: visible.isEmpty
                        ? Center(child: Text('common.noItems'.tr()))
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 90),
                            itemCount: visible.length,
                            itemBuilder: (context, index) =>
                                _playerCard(visible[index]),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
