import 'dart:ui' as ui;

import 'package:flutter/services.dart';

Future<void> loadPreviewFonts() async {
  final font = await rootBundle.load('assets/fonts/Manrope.ttf');
  final bytes = font.buffer.asUint8List();
  for (final family in [
    'Roboto',
    'Manrope',
    'Manrope_regular',
    for (var weight = 100; weight <= 900; weight += 100) 'Manrope_$weight',
  ]) {
    await ui.loadFontFromList(bytes, fontFamily: family);
  }
  final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
  await ui.loadFontFromList(
    icons.buffer.asUint8List(),
    fontFamily: 'MaterialIcons',
  );
  final tabler = await rootBundle.load(
    'packages/tabler_icons_plus/lib/fonts/tabler-icons.ttf',
  );
  await ui.loadFontFromList(
    tabler.buffer.asUint8List(),
    fontFamily: 'packages/tabler_icons_plus/tabler-icons',
  );
  final filled = await rootBundle.load(
    'packages/tabler_icons_plus/lib/fonts/tabler-icons-filled.ttf',
  );
  await ui.loadFontFromList(
    filled.buffer.asUint8List(),
    fontFamily: 'packages/tabler_icons_plus/tabler-icons-filled',
  );
}
