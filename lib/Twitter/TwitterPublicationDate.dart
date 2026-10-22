import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

DateTime resolveTwitterPublicationDate({
  DateTime? selected,
  DateTime? parent,
  DateTime? latestFixture,
  DateTime? now,
}) {
  final base = parent ?? latestFixture ?? now ?? DateTime.now();
  final date = selected == null
      ? base
      : DateTime(
          selected.year,
          selected.month,
          selected.day,
          base.hour,
          base.minute,
          base.second,
          base.millisecond,
          base.microsecond,
        );
  if (parent != null && date.isBefore(parent)) {
    throw const FormatException(
      'A resposta não pode ser publicada antes do post original.',
    );
  }
  return date;
}

class TwitterPublicationDateField extends StatelessWidget {
  const TwitterPublicationDateField({
    super.key,
    required this.date,
    required this.onChanged,
    this.firstDate,
    this.enabled = true,
  });
  final DateTime date;
  final DateTime? firstDate;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => InkWell(
    key: const ValueKey('publication-date'),
    borderRadius: BorderRadius.circular(16),
    onTap: !enabled
        ? null
        : () async {
            FocusScope.of(context).unfocus();
            final selected = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: firstDate ?? DateTime(1900),
              lastDate: DateTime(2200, 12, 31),
              helpText: 'Dia da publicação',
            );
            if (selected != null) onChanged(selected);
          },
    child: InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Dia da publicação',
        prefixIcon: Icon(Icons.calendar_month_outlined),
        suffixIcon: Icon(Icons.edit_calendar_outlined),
        helperText: 'O post aparece neste dia na linha do tempo da carreira.',
        helperMaxLines: 2,
      ),
      child: Text(DateFormat('dd/MM/yyyy').format(date)),
    ),
  );
}
