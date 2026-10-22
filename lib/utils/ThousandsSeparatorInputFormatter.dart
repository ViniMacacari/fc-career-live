import 'package:flutter/services.dart';

class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  static final _nonDigits = RegExp(r'\D');
  static final _groups = RegExp(r'\B(?=(\d{3})+(?!\d))');

  static String format(String value) =>
      value.replaceAll(_nonDigits, '').replaceAll(_groups, '.');

  static int? parse(String value) =>
      int.tryParse(value.replaceAll(_nonDigits, ''));

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    var input = newValue;
    final offset = newValue.selection.baseOffset;
    if (oldValue.selection.isCollapsed &&
        newValue.selection.isCollapsed &&
        newValue.text.length == oldValue.text.length - 1 &&
        offset >= 0 &&
        offset < oldValue.text.length &&
        oldValue.text[offset] == '.' &&
        newValue.text == oldValue.text.replaceRange(offset, offset + 1, '')) {
      final backspace = oldValue.selection.baseOffset == offset + 1;
      final delete = oldValue.selection.baseOffset == offset;
      final digit = backspace ? offset - 1 : offset;
      if ((backspace || delete) && digit >= 0 && digit < input.text.length) {
        input = TextEditingValue(
          text: input.text.replaceRange(digit, digit + 1, ''),
          selection: TextSelection.collapsed(
            offset: backspace ? digit : offset,
          ),
        );
      }
    }
    final text = format(input.text);
    int cursor(int offset) {
      if (offset < 0) return text.length;
      final count = input.text
          .substring(0, offset.clamp(0, input.text.length))
          .replaceAll(_nonDigits, '')
          .length;
      var index = 0, digits = 0;
      while (index < text.length && digits < count) {
        if (text[index] != '.') digits++;
        index++;
      }
      return index;
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: cursor(input.selection.baseOffset),
        extentOffset: cursor(input.selection.extentOffset),
        affinity: input.selection.affinity,
        isDirectional: input.selection.isDirectional,
      ),
    );
  }
}
