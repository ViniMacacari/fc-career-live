import '../../utils/AppColors.dart';
import '../../utils/themes.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/Person.dart';

String transferCurrency(Person person) =>
    switch (person.currency?.toUpperCase()) {
      'USD' || 'DOLLAR' || 'DOLLARS' || '\$' => '\$',
      'GBP' || 'POUND' || 'POUNDS' || '£' => '£',
      'BRL' || 'REAL' || 'REAIS' || 'R\$' => 'R\$',
      _ => '€',
    };

String transferMoney(Object? value) {
  if (value == null) return '';
  final digits = value.toString().replaceAll(RegExp(r'[^0-9]'), '');
  return digits.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]} ',
  );
}

int? parseTransferMoney(String value) =>
    int.tryParse(value.replaceAll(RegExp(r'\s'), ''));

class TransferMoneyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = transferMoney(newValue.text);
    final before = newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final digitsBefore = newValue.text
        .substring(0, before)
        .replaceAll(RegExp(r'[^0-9]'), '')
        .length;
    var offset = 0;
    var digits = 0;
    while (offset < formatted.length && digits < digitsBefore) {
      if (formatted[offset] != ' ') digits++;
      offset++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

class TransferTheme extends StatelessWidget {
  const TransferTheme({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Theme(data: careerDetailTheme(context), child: child);
}

class TransferPickerField extends StatelessWidget {
  const TransferPickerField({
    super.key,
    required this.label,
    required this.onTap,
    this.value,
    this.leading,
    this.trailing,
  });
  final String label;
  final String? value;
  final Widget? leading, trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(15),
    child: InputDecorator(
      decoration: InputDecoration(labelText: value == null ? null : label),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Text(
              value ?? label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, color: AppColors.of(context).text),
            ),
          ),
          const SizedBox(width: 8),
          trailing ??
              Icon(Icons.arrow_right, color: AppColors.of(context).muted),
        ],
      ),
    ),
  );
}
