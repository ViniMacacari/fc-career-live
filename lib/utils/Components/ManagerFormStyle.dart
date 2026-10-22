import 'package:flutter/material.dart';

InputDecoration managerFieldDecoration(
  BuildContext context,
  String label, {
  IconData? icon,
  Widget? suffix,
  String? hint,
  String? helper,
}) {
  final colors = Theme.of(context).colorScheme;
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: color),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: 2,
    prefixIcon: icon == null
        ? null
        : Icon(icon, size: 21, color: colors.primary),
    suffixIcon: suffix,
    filled: true,
    fillColor: Theme.of(context).cardColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    counterText: '',
    border: border(colors.outlineVariant),
    enabledBorder: border(colors.outlineVariant),
    focusedBorder: border(colors.primary),
    errorBorder: border(colors.error),
    focusedErrorBorder: border(colors.error),
  );
}
