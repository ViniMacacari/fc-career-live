import 'package:flutter/material.dart';

import '../../utils/AppColors.dart';
import '../../utils/Components/SelectionSearchField.dart';
import 'PlayersStatData.dart';
import 'PlayerStatWidgets.dart';

Future<PlayersStatSort?> showPlayersStatSort(
  BuildContext context,
  PlayersStatSort current,
) => showModalBottomSheet<PlayersStatSort>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => PlayersStatPageSortModal(initial: current),
);

class PlayersStatPageSortModal extends StatefulWidget {
  const PlayersStatPageSortModal({super.key, required this.initial});
  final PlayersStatSort initial;
  @override
  State<PlayersStatPageSortModal> createState() =>
      _PlayersStatPageSortModalState();
}

class _PlayersStatPageSortModalState extends State<PlayersStatPageSortModal> {
  late bool _descending = widget.initial.descending;
  late PlayersStatMetric? _metric = widget.initial.metric;
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget direction(bool descending, String label, IconData icon) {
      final selected = _descending == descending;
      return Expanded(
        child: FilledButton.icon(
          key: ValueKey('sort-direction-$descending'),
          onPressed: () => setState(() => _descending = descending),
          style: FilledButton.styleFrom(
            backgroundColor: selected ? c.accent : c.raised,
            foregroundColor: selected ? c.onAccent : c.text,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: Icon(icon, size: 18),
          label: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      );
    }

    Widget option(PlayersStatMetric? metric) {
      final selected = _metric == metric;
      return ListTile(
        key: ValueKey('sort-metric-${metric?.name ?? 'position'}'),
        dense: true,
        minTileHeight: 48,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: selected ? c.accent.withValues(alpha: .14) : null,
        leading: metric == null
            ? Icon(Icons.format_list_numbered, size: 20, color: c.muted)
            : PlayerMetricIcon(metric, size: 20),
        title: Text(
          metric?.title ?? 'Posição',
          style: TextStyle(
            color: selected ? c.accent : c.text,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        trailing: selected
            ? Icon(Icons.check_circle, color: c.accent, size: 21)
            : null,
        selected: selected,
        onTap: () => setState(() => _metric = metric),
      );
    }

    final query = selectionSearchKey(_search.text);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height:
              (MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom -
                  MediaQuery.paddingOf(context).vertical) *
              .82,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ordenar jogadores',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        direction(true, 'Maiores', Icons.south),
                        const SizedBox(width: 8),
                        direction(false, 'Menores', Icons.north),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SelectionSearchField(
                      controller: _search,
                      hint: 'Buscar indicador',
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    if (query.isEmpty ||
                        selectionSearchKey('posição').contains(query))
                      option(null),
                    for (final metric in PlayersStatMetric.values)
                      if (selectionSearchKey('${metric.title} ${metric.label}')
                          .contains(query))
                        option(metric),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(
                          context,
                          PlayersStatSort(
                            metric: _metric,
                            descending: _descending,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: c.accent,
                          foregroundColor: c.onAccent,
                        ),
                        child: const Text('Aplicar'),
                      ),
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
}
