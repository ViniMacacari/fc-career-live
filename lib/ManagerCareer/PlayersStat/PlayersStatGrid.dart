import '../../utils/AppColors.dart';

import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../models/Person.dart';
import '../../models/TeamTransferItem.dart';
import '../../utils/Components/TeamLogo.dart';
import '../../utils/GameCatalog.dart';
import '../TeamPage/ViewPlayer/PlayerProfileVisuals.dart' show ProfilePortrait;
import '../TeamTransfers/TransferStyle.dart';
import 'PlayersStatData.dart';

class PlayersStatGrid extends StatefulWidget {
  const PlayersStatGrid({
    super.key,
    required this.person,
    required this.catalog,
    required this.entries,
    required this.group,
    required this.sort,
    required this.onSort,
    required this.onOpen,
  });
  final Person person;
  final GameCatalog catalog;
  final List<PlayersStatEntry> entries;
  final PlayersStatGroup group;
  final PlayersStatSort sort;
  final void Function(PlayersStatMetric) onSort;
  final void Function(PlayersStatEntry) onOpen;
  @override
  State<PlayersStatGrid> createState() => _PlayersStatGridState();
}

class _PlayersStatGridState extends State<PlayersStatGrid> {
  final _horizontal = ScrollController();

  @override
  void didUpdateWidget(covariant PlayersStatGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group != widget.group) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _horizontal.hasClients) _horizontal.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  Color _ratingColor(num? value) => value == null
      ? AppColors.of(context).muted
      : value >= 7
      ? AppColors.of(context).success
      : value >= 6
      ? AppColors.of(context).warning
      : AppColors.of(context).danger;

  Widget _cells(
    List<PlayersStatMetric> metrics,
    double width,
    String Function(PlayersStatMetric) text, {
    Color Function(PlayersStatMetric)? color,
    bool footer = false,
  }) => Row(
    children: [
      for (final metric in metrics)
        SizedBox(
          width: width,
          child: Center(
            child: Text(
              text(metric),
              maxLines: 1,
              style: TextStyle(
                fontSize: 12.5,
                color: color?.call(metric) ?? AppColors.of(context).text,
                fontWeight: footer ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
    ],
  );

  Widget _viewport(Widget child, double contentWidth, double offset) =>
      ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: contentWidth,
          maxWidth: contentWidth,
          child: Transform.translate(offset: Offset(-offset, 0), child: child),
        ),
      );

  void _drag(DragUpdateDetails details) {
    if (!_horizontal.hasClients) return;
    _horizontal.jumpTo(
      (_horizontal.offset - details.delta.dx).clamp(
        _horizontal.position.minScrollExtent,
        _horizontal.position.maxScrollExtent,
      ),
    );
  }

  num? _footerValue(PlayersStatMetric metric) {
    final summed = widget.group == PlayersStatGroup.summary
        ? {PlayersStatMetric.goals, PlayersStatMetric.assists}
        : widget.group.metrics
              .where(
                (metric) =>
                    !metric.percentage &&
                    !metric.decimal &&
                    metric != PlayersStatMetric.matches &&
                    metric != PlayersStatMetric.starts,
              )
              .toSet();
    if (!summed.contains(metric)) return null;
    final values = widget.entries
        .map((entry) => entry.totals[metric])
        .whereType<num>();
    return values.isEmpty ? null : values.reduce((a, b) => a + b);
  }

  String _exitTooltip(PlayersStatEntry entry) {
    final date = DateTime.tryParse(
      (entry.exit?['actualReleaseDate'] ?? entry.exit?['date'])?.toString() ??
          '',
    );
    return [
      'Jogador fora do elenco atual',
      if (entry.exit != null) transferCardLabel(entry.exit!),
      if (entry.destinationId != null)
        'Destino registrado: ${widget.catalog.teamLabel(widget.person.fifaVersion, entry.destinationId!)}',
      if (entry.exitValue != null)
        'Valor: ${transferMoney(entry.exitValue)} ${transferCurrency(widget.person)}',
      if (date != null) DateFormat('dd/MM/yyyy').format(date),
    ].join('\n');
  }

  Widget _exitInfo(PlayersStatEntry entry) {
    final club = entry.destinationId;
    return Tooltip(
      message: _exitTooltip(entry),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(42, 0, 12, 6),
        child: Row(
          children: [
            if (club != null) ...[
              Text(
                '→ ',
                style: TextStyle(
                  color: AppColors.of(context).muted,
                  fontSize: 11,
                ),
              ),
              TeamLogo.lookup(
                fifaVersion: widget.person.fifaVersion,
                teamId: club,
                leagueId: entry.destinationLeagueId,
                size: 17,
              ),
              const SizedBox(width: 5),
            ],
            Expanded(
              child: Text(
                club == null
                    ? entry.exit == null
                          ? 'Fora do elenco atual'
                          : transferCardLabel(entry.exit!)
                    : widget.catalog.teamLabel(widget.person.fifaVersion, club),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.of(context).muted,
                ),
              ),
            ),
            if (entry.exitValue != null)
              Text(
                '${transferMoney(entry.exitValue)} ${transferCurrency(widget.person)}',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.of(context).accent,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final metrics = widget.group.metrics;
      final playerWidth = (constraints.maxWidth * .35).clamp(110.0, 210.0);
      final viewportWidth = constraints.maxWidth - playerWidth;
      final cellWidth = math.max(48.0, viewportWidth / 5);
      final contentWidth = cellWidth * metrics.length;
      return AnimatedBuilder(
        animation: _horizontal,
        builder: (context, _) {
          final offset = (_horizontal.hasClients ? _horizontal.offset : 0.0)
              .clamp(0.0, math.max(0.0, contentWidth - viewportWidth))
              .toDouble();
          return Column(
            children: [
              SizedBox(
                height: 38,
                child: Row(
                  children: [
                    SizedBox(
                      width: playerWidth,
                      child: Center(
                        child: Text(
                          'Jogador',
                          style: TextStyle(
                            color: AppColors.of(context).muted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _horizontal,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: contentWidth,
                          child: Row(
                            children: [
                              for (final metric in metrics)
                                Tooltip(
                                  message: metric.label,
                                  child: InkWell(
                                    onTap: () => widget.onSort(metric),
                                    child: SizedBox(
                                      width: cellWidth,
                                      height: 38,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            metric.shortLabel,
                                            style: TextStyle(
                                              color: AppColors.of(context)
                                                  .muted,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                          if (widget.sort.metric == metric)
                                            Icon(
                                              widget.sort.descending
                                                  ? Icons.arrow_downward
                                                  : Icons.arrow_upward,
                                              size: 11,
                                              color: AppColors.of(context)
                                                  .accent,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: widget.entries.isEmpty
                    ? const Center(
                        child: Text('Nenhum jogador para estes filtros.'),
                      )
                    : ListView.builder(
                        itemCount: widget.entries.length,
                        padding: EdgeInsets.zero,
                        itemBuilder: (context, index) {
                          final entry = widget.entries[index];
                          return Material(
                            color: entry.departed
                                ? AppColors.of(context).raised
                                : AppColors.of(context).background,
                            child: InkWell(
                              onTap: () => widget.onOpen(entry),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 44,
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: playerWidth,
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              12,
                                              4,
                                              5,
                                              4,
                                            ),
                                            child: Row(
                                              children: [
                                                ProfilePortrait(
                                                  version:
                                                      widget.person.fifaVersion,
                                                  realPlayerId: entry
                                                      .player['realPlayerId']
                                                      ?.toString(),
                                                  customAvatarFilePath: entry
                                                      .player['customAvatarFilePath']
                                                      ?.toString(),
                                                  width: 28,
                                                  height: 34,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Tooltip(
                                                    message: entry.name,
                                                    child: Text(
                                                      entry.name,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 11.5,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onHorizontalDragUpdate: _drag,
                                            child: _viewport(
                                              _cells(
                                                metrics,
                                                cellWidth,
                                                (metric) => metric.format(
                                                  entry.totals[metric],
                                                ),
                                                color: (metric) =>
                                                    metric ==
                                                        PlayersStatMetric.rating
                                                    ? _ratingColor(
                                                        entry.totals[metric],
                                                      )
                                                    : AppColors.of(context)
                                                          .text,
                                              ),
                                              contentWidth,
                                              offset,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (entry.departed) _exitInfo(entry),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  height: 44,
                  color: AppColors.of(context).panel,
                  child: Row(
                    children: [
                      SizedBox(width: playerWidth),
                      Expanded(
                        child: GestureDetector(
                          onHorizontalDragUpdate: _drag,
                          child: _viewport(
                            _cells(metrics, cellWidth, (metric) {
                              final value = _footerValue(metric);
                              return value == null ? '' : metric.format(value);
                            }, footer: true),
                            contentWidth,
                            offset,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
