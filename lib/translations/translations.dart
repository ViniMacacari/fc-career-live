import 'dart:convert';

import 'package:flutter/services.dart';

const translationLanguages = [
  'en',
  'it',
  'pt_PT',
  'pt_BR',
  'ru',
  'fr',
  'de',
  'es',
  'tr',
  'id',
];

final Map<String, Map<String, dynamic>> _loaded = {};

Future<Map<String, dynamic>> getTranslationsFromString(String language) async {
  final code = translationLanguages.contains(language) ? language : 'en';
  final cached = _loaded[code];
  if (cached != null) return cached;
  final raw = await rootBundle.loadString('assets/translations/$code.json');
  final translations = jsonDecode(raw) as Map<String, dynamic>;
  (translations['sections'] as Map<String, dynamic>)['twitter'] = 'Twitter';
  return _loaded[code] = translations;
}
