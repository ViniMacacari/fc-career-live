import 'package:flutter/material.dart';

import '../models/FixtureCaptaincy.dart';
import '../models/ManagerFixturePlayerPerformance.dart';
import '../utils/AppColors.dart';
import '../utils/eventTimeUtils.dart';

class CaptainBadge extends StatelessWidget {
  const CaptainBadge({super.key, this.size = 18});
  final double size;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Capitão',
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.of(context).accent),
        borderRadius: BorderRadius.circular(4),
        color: AppColors.of(context).background,
      ),
      child: Text(
        'C',
        style: TextStyle(
          color: AppColors.of(context).accent,
          fontWeight: FontWeight.w800,
          fontSize: size * .65,
          height: 1,
        ),
      ),
    ),
  );
}

class FixtureCaptainPanel extends StatelessWidget {
  const FixtureCaptainPanel({
    super.key,
    required this.captaincy,
    required this.performances,
    required this.names,
    this.onInitial,
    this.onHandover,
  });
  final FixtureCaptaincy captaincy;
  final List<ManagerFixturePlayerPerformance> performances;
  final Map<String, String> names;
  final VoidCallback? onInitial;
  final ValueChanged<CaptainDeparture>? onHandover;
  String _name(String? id) =>
      id == null ? 'Não informado' : names[id] ?? 'Jogador';
  @override
  Widget build(BuildContext context) {
    if (!captaincy.isRecorded && onInitial == null) {
      return const SizedBox.shrink();
    }
    final c = AppColors.of(context);
    return Container(
      key: const ValueKey('fixture-captaincy'),
      padding: onInitial == null
          ? const EdgeInsets.symmetric(vertical: 4)
          : const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: onInitial == null
          ? null
          : BoxDecoration(
              color: c.raised.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(14),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onInitial,
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: [
                const CaptainBadge(size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Capitão${onInitial == null ? '' : ' · opcional'}',
                        style: TextStyle(color: c.muted, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        captaincy.isRecorded
                            ? '${_name(captaincy.initialPlayerId)} · desde o início'
                            : 'Escolher capitão',
                        style: TextStyle(
                          color: captaincy.isRecorded ? c.text : c.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onInitial != null)
                  const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
          for (final d in captaincy.departures(performances)) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: onHandover == null ? null : () => onHandover!(d),
              borderRadius: BorderRadius.circular(10),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: Icon(Icons.swap_horiz, size: 17, color: c.muted),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${d.substitution.minute == null ? 'Saída de ${_name(d.playerId)}' : '${formatEventMinute(d.substitution.minute, d.substitution.addedMinute)} · ${_name(d.playerId)} sai'}\n'
                      '${d.handover == null ? (onHandover == null ? 'Próximo capitão não informado' : 'Definir quem recebeu a braçadeira') : _name(d.handover!.playerId)}',
                      style: TextStyle(
                        color: d.handover == null ? c.accent : c.text,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                  ),
                  if (onHandover != null)
                    const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<String?> showCaptainPicker(
  BuildContext context, {
  required String title,
  required List<String> eligible,
  required Map<String, String> names,
  String? selectedId,
  String noneLabel = 'Não informar capitão',
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _CaptainPicker(
    title: title,
    eligible: eligible,
    names: names,
    selectedId: selectedId,
    noneLabel: noneLabel,
  ),
);

class _CaptainPicker extends StatefulWidget {
  const _CaptainPicker({
    required this.title,
    required this.eligible,
    required this.names,
    required this.noneLabel,
    this.selectedId,
  });
  final String title, noneLabel;
  final List<String> eligible;
  final Map<String, String> names;
  final String? selectedId;
  @override
  State<_CaptainPicker> createState() => _CaptainPickerState();
}

class _CaptainPickerState extends State<_CaptainPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SizedBox(
        height:
            (MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom) *
            .65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('captain-search'),
              decoration: const InputDecoration(
                hintText: 'Buscar na escalação',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    key: const ValueKey('captain-none'),
                    leading: const Icon(Icons.remove_circle_outline),
                    title: Text(widget.noneLabel),
                    onTap: () => Navigator.pop(context, ''),
                  ),
                  for (final id in widget.eligible.toSet().where(
                    (id) =>
                        (widget.names[id] ?? '').toLowerCase().contains(query),
                  ))
                    ListTile(
                      key: ValueKey('captain-pick-$id'),
                      leading: const CaptainBadge(size: 25),
                      title: Text(widget.names[id] ?? 'Jogador'),
                      trailing: widget.selectedId == id
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(context, id),
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
