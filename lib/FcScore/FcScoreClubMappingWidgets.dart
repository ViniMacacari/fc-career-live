import 'package:flutter/material.dart';

import '../utils/Components/CareerUiStyle.dart';
import '../utils/Components/TeamLogo.dart';
import '../utils/GameCatalog.dart';
import 'FcScoreModels.dart';

class FcClubLogo extends StatelessWidget {
  const FcClubLogo({super.key, required this.item});
  final CatalogItem? item;
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 36, height: 36, child: TeamLogo.fromItem(item, size: 36));
}

class FcClubLeagueGroup<T> {
  const FcClubLeagueGroup(this.id, this.label, this.rows);
  final String id, label;
  final List<T> rows;
}

List<FcClubLeagueGroup<CatalogItem>> fcGroupClubs(
  List<CatalogItem> teams,
  List<CatalogItem> leagues,
) {
  final labels = {for (final l in leagues) l.id: l.label};
  final groups = <String, List<CatalogItem>>{};
  for (final t in teams) {
    final id = labels.containsKey(t.leagueId) ? t.leagueId! : 'other';
    (groups[id] ??= []).add(t);
  }
  return [
    for (final e in groups.entries)
      FcClubLeagueGroup(
        e.key,
        labels[e.key] ?? 'Outras equipes',
        e.value..sort(
          (a, b) => fcNormalize(a.label).compareTo(fcNormalize(b.label)),
        ),
      ),
  ]..sort((a, b) => fcNormalize(a.label).compareTo(fcNormalize(b.label)));
}

class FcClubLeagueList<T> extends StatefulWidget {
  const FcClubLeagueList({
    super.key,
    required this.groups,
    required this.rowBuilder,
    required this.keyPrefix,
    this.preferredGroupId,
    this.query = '',
    this.padding = EdgeInsets.zero,
    this.prefix,
  });
  final List<FcClubLeagueGroup<T>> groups;
  final Widget Function(BuildContext, T) rowBuilder;
  final String keyPrefix, query;
  final String? preferredGroupId;
  final EdgeInsets padding;
  final Widget? prefix;
  @override
  State<FcClubLeagueList<T>> createState() => _FcClubLeagueListState<T>();
}

class _FcClubLeagueListState<T> extends State<FcClubLeagueList<T>> {
  final _expanded = <String>{}, _closedSearch = <String>{};
  @override
  void initState() {
    super.initState();
    final first =
        widget.groups
            .where((g) => g.id == widget.preferredGroupId)
            .firstOrNull ??
        widget.groups.firstOrNull;
    if (first != null) {
      _expanded.add(first.id);
    }
  }

  @override
  void didUpdateWidget(covariant FcClubLeagueList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _closedSearch.clear();
    }
  }

  bool _open(String id) => widget.query.isNotEmpty
      ? !_closedSearch.contains(id)
      : _expanded.contains(id);

  @override
  Widget build(BuildContext context) {
    final colors = CareerUiColors(context);
    return CustomScrollView(
      key: ValueKey('${widget.keyPrefix}-list'),
      slivers: [
        SliverPadding(
          padding: widget.padding,
          sliver: SliverMainAxisGroup(
            slivers: [
              if (widget.prefix != null)
                SliverToBoxAdapter(child: widget.prefix!),
              for (final group in widget.groups)
                SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: colors.panel,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: colors.line),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            key: ValueKey(
                              '${widget.keyPrefix}-league-${group.id}',
                            ),
                            leading: Icon(
                              Icons.emoji_events_outlined,
                              color: colors.accent,
                            ),
                            title: Text(
                              group.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${group.rows.length} ${group.rows.length == 1 ? 'clube' : 'clubes'}',
                            ),
                            trailing: AnimatedRotation(
                              turns: _open(group.id) ? .5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                Icons.expand_more,
                                color: colors.accent,
                              ),
                            ),
                            onTap: () => setState(() {
                              if (widget.query.isNotEmpty) {
                                _open(group.id)
                                    ? _closedSearch.add(group.id)
                                    : _closedSearch.remove(group.id);
                              } else {
                                _expanded.contains(group.id)
                                    ? _expanded.remove(group.id)
                                    : _expanded.add(group.id);
                              }
                            }),
                          ),
                        ),
                      ),
                    ),
                    if (_open(group.id))
                      SliverList.builder(
                        itemCount: group.rows.length,
                        itemBuilder: (context, index) =>
                            widget.rowBuilder(context, group.rows[index]),
                      ),
                  ],
                ),
              if (widget.groups.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('Nenhum resultado')),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
