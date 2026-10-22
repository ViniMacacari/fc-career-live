import 'package:flutter/material.dart';

class SelectionSearchField extends StatelessWidget {
  const SelectionSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.dense = false,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search_rounded, size: 22),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Limpar busca',
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () {
                controller.clear();
                onChanged('');
              },
            ),
      isDense: dense,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: dense ? 11 : 16,
      ),
    ),
    onChanged: onChanged,
  );
}

String selectionSearchKey(String text) {
  var value = text.trim().toLowerCase();
  for (final entry in {
    r'[àáâãäå]': 'a',
    r'[èéêë]': 'e',
    r'[ìíîï]': 'i',
    r'[òóôõöø]': 'o',
    r'[ùúûü]': 'u',
    r'[ýÿ]': 'y',
    'ç': 'c',
    'ñ': 'n',
  }.entries) {
    value = value.replaceAll(RegExp(entry.key), entry.value);
  }
  return value;
}
