import '../../utils/AppColors.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/Season.dart';
import '../../models/TransferPreviousClubStats.dart';
import 'TransferStyle.dart';

class TransferPreviousClubStatsResult {
  const TransferPreviousClubStatsResult(this.stats);
  final TransferPreviousClubStats? stats;
}

Future<TransferPreviousClubStatsResult?> showTransferPreviousClubStats(
  BuildContext context, {
  required String playerName,
  required String clubName,
  required Season season,
  required DateTime date,
  TransferPreviousClubStats? initial,
}) => showDialog<TransferPreviousClubStatsResult>(
  context: context,
  builder: (_) => TransferTheme(
    child: TransferPreviousClubStatsDialog(
      playerName: playerName,
      clubName: clubName,
      season: season,
      date: date,
      initial: initial,
    ),
  ),
);

class TransferPreviousClubStatsDialog extends StatefulWidget {
  const TransferPreviousClubStatsDialog({
    super.key,
    required this.playerName,
    required this.clubName,
    required this.season,
    required this.date,
    this.initial,
  });
  final String playerName, clubName;
  final Season season;
  final DateTime date;
  final TransferPreviousClubStats? initial;

  @override
  State<TransferPreviousClubStatsDialog> createState() =>
      _TransferPreviousClubStatsDialogState();
}

class _TransferPreviousClubStatsDialogState
    extends State<TransferPreviousClubStatsDialog> {
  final _form = GlobalKey<FormState>();
  late final _matches = TextEditingController(
    text: widget.initial?.matches?.toString() ?? '',
  );
  late final _goals = TextEditingController(
    text: widget.initial?.goals?.toString() ?? '',
  );
  late final _assists = TextEditingController(
    text: widget.initial?.assists?.toString() ?? '',
  );
  late final _rating = TextEditingController(
    text:
        widget.initial?.averageRating
            ?.toStringAsFixed(1)
            .replaceAll('.', ',') ??
        '',
  );
  late final _notes = TextEditingController(text: widget.initial?.notes ?? '');

  @override
  void dispose() {
    for (final controller in [_matches, _goals, _assists, _rating, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _count(String label, String key, TextEditingController controller) =>
      TextFormField(
        key: ValueKey(key),
        controller: controller,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Não informado',
        ),
        validator: (value) {
          if (value == null || value.isEmpty) return null;
          final count = int.tryParse(value);
          if (count == null || count < 0) return 'Número inválido.';
          if (controller != _matches &&
              count > 0 &&
              int.tryParse(_matches.text) == 0) {
            return 'Confira o número de jogos.';
          }
          return null;
        },
      );

  void _continue() {
    if (!_form.currentState!.validate()) return;
    final stats = TransferPreviousClubStats(
      asOfDate: widget.date,
      matches: int.tryParse(_matches.text),
      goals: int.tryParse(_goals.text),
      assists: int.tryParse(_assists.text),
      averageRating: double.tryParse(_rating.text.replaceAll(',', '.')),
      notes: _notes.text.trim(),
    );
    Navigator.pop(
      context,
      TransferPreviousClubStatsResult(stats.hasInformation ? stats : null),
    );
  }

  Widget _ratingField() => TextFormField(
    key: const ValueKey('previous-club-rating'),
    controller: _rating,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textInputAction: TextInputAction.next,
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
    decoration: const InputDecoration(
      labelText: 'Nota média',
      hintText: '0 a 10',
    ),
    validator: (value) {
      if (value == null || value.isEmpty) return null;
      final rating = double.tryParse(value.replaceAll(',', '.'));
      return rating == null || !rating.isFinite || rating < 0 || rating > 10
          ? 'Use uma nota de 0 a 10.'
          : null;
    },
  );

  Widget _statsFields(BuildContext context) {
    final fields = [
      _count('Jogos', 'previous-club-matches', _matches),
      _count('Gols', 'previous-club-goals', _goals),
      _count('Assistências', 'previous-club-assists', _assists),
      _ratingField(),
    ];
    final narrow =
        MediaQuery.sizeOf(context).width < 380 ||
        MediaQuery.textScalerOf(context).scale(14) > 17;
    return Column(
      children: [
        if (narrow)
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            fields[i],
          ]
        else
          for (var i = 0; i < fields.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: fields[i]),
                const SizedBox(width: 12),
                Expanded(child: fields[i + 1]),
              ],
            ),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.of(context).panel,
    insetPadding: EdgeInsets.symmetric(
      horizontal: MediaQuery.sizeOf(context).width < 380 ? 20 : 40,
      vertical: 24,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    title: Row(
      children: [
        const Expanded(
          child: Text(
            'Clube anterior',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Cancelar',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, size: 20),
        ),
      ],
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.playerName,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                widget.clubName,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  color: AppColors.of(context).accent,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${widget.season.startDate.year} - ${widget.season.endDate.year} · até ${DateFormat('dd/MM/yyyy').format(widget.date)}',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  color: AppColors.of(context).muted,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Preencha o que souber. Os campos em branco ficam como não informados.',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  color: AppColors.of(context).muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              _statsFields(context),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('previous-club-notes'),
                controller: _notes,
                minLines: 2,
                maxLines: 3,
                maxLength: 600,
                decoration: const InputDecoration(
                  labelText: 'Observações (opcional)',
                  hintText: 'Era titular, vinha em boa fase, voltava de lesão…',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('skip-previous-club-stats'),
        onPressed: () =>
            Navigator.pop(context, const TransferPreviousClubStatsResult(null)),
        child: const Text('Não informar'),
      ),
      FilledButton(
        key: const ValueKey('confirm-previous-club-stats'),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.of(context).accent,
          foregroundColor: AppColors.of(context).text,
        ),
        onPressed: _continue,
        child: const Text('Continuar'),
      ),
    ],
  );
}
