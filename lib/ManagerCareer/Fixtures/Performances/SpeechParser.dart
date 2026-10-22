import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../models/ManagerFixturePlayerPerformance.dart';

class ParseResult {
  final stats = <String, double>{};
  final goals = <PerformanceGoalDetails>[];
  final assists = <PerformanceAssistDetails>[];
  final substitutions = <PerformanceSubstitutionDetails>[];
  final yellowCards = <PerformanceCardDetails>[];
  final redCards = <PerformanceCardDetails>[];
  final ownGoals = <PerformanceOwnGoalDetails>[];
  final missedPenalties = <PerformanceMissedPenaltyDetails>[];
  final injuries = <PerformanceInjuryDetails>[];
}

class StatsParser {
  static Future<Map<String, dynamic>>? _configs;

  static Future<ParseResult> parse(String text, String language) async {
    final configs = await (_configs ??= rootBundle
        .loadString('assets/voice_config.json')
        .then((raw) => jsonDecode(raw) as Map<String, dynamic>));
    final code = configs.containsKey(language) ? language : 'en';
    final config = configs[code] as Map<String, dynamic>;
    final numbers = jsonDecode(
      await rootBundle.loadString('assets/numbers/numbers_$code.json'),
    ) as Map<String, dynamic>;
    final aliases = <String, ({String key, bool event})>{};
    for (final kind in ['stats', 'events']) {
      for (final entry in (config[kind] as Map<String, dynamic>).entries) {
        for (final alias in entry.value as List<dynamic>) {
          aliases[alias.toString().toLowerCase()] = (
            key: entry.key,
            event: kind == 'events',
          );
        }
      }
    }
    final sortedAliases = aliases.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final matcher = RegExp(
      '(?<!\\S)(${sortedAliases.map(RegExp.escape).join('|')})(?=\$|\\s|[.,;:!?])',
    );
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final matches = matcher.allMatches(normalized).toList();
    final numberAliases = numbers.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final numberMatcher = RegExp(
      '(?<!\\S)(${numberAliases.map(RegExp.escape).join('|')})(?=\$|\\s|[.,;:!?])',
    );
    final result = ParseResult();
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final alias = aliases[match.group(1)]!;
      var value = normalized
          .substring(
            match.end,
            index + 1 < matches.length
                ? matches[index + 1].start
                : normalized.length,
          )
          .trim();
      value = value.replaceAllMapped(
        numberMatcher,
        (m) => numbers[m.group(1)].toString(),
      );
      for (final decimal
          in (config['decimal'] as List<dynamic>).cast<String>()) {
        if (decimal != ',' && decimal != '.') {
          value = value.replaceAll(
            RegExp('(?<!\\S)${RegExp.escape(decimal)}(?=\$|\\s)'),
            '.',
          );
        }
      }
      value = value.replaceAllMapped(
        RegExp(r'(\d)\s*[.,]\s*(\d)'),
        (m) => '${m[1]}.${m[2]}',
      );
      final values = RegExp(r'-?\d+(?:\.\d+)?')
          .allMatches(value)
          .map((m) => double.parse(m[0]!))
          .toList();
      if (!alias.event) {
        if (values.isNotEmpty && values.first >= 0) {
          result.stats[alias.key] = values.first;
        }
        continue;
      }
      final minutes = values
          .where((v) => v >= 0 && v <= 140 && v == v.roundToDouble())
          .map<int?>((v) => v.toInt())
          .toList();
      if (minutes.isEmpty) minutes.add(null);
      for (final minute in minutes) {
        switch (alias.key) {
          case 'goal':
            result.goals.add(PerformanceGoalDetails(minute: minute));
          case 'assist':
            result.assists.add(PerformanceAssistDetails(minute: minute));
          case 'substitution_in':
            result.substitutions.add(
              PerformanceSubstitutionDetails(
                minute: minute,
                type: SubstitutionType.inGame,
              ),
            );
          case 'substitution_out':
            result.substitutions.add(
              PerformanceSubstitutionDetails(
                minute: minute,
                type: SubstitutionType.outGame,
              ),
            );
          case 'yellowCard':
            result.yellowCards.add(PerformanceTimeDetails(minute: minute));
          case 'redCard':
            result.redCards.add(PerformanceTimeDetails(minute: minute));
          case 'ownGoal':
            result.ownGoals.add(PerformanceTimeDetails(minute: minute));
          case 'missedPenalty':
            result.missedPenalties.add(PerformanceTimeDetails(minute: minute));
          case 'injury':
            result.injuries.add(PerformanceTimeDetails(minute: minute));
        }
      }
    }
    return result;
  }
}
