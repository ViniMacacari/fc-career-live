import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'BackgroundData.dart';

const positionShortLabels = <String, String>{
  '0': 'GK',
  '2': 'RWB',
  '3': 'RB',
  '5': 'CB',
  '7': 'LB',
  '8': 'LWB',
  '10': 'CDM',
  '12': 'RM',
  '14': 'CM',
  '16': 'LM',
  '18': 'CAM',
  '21': 'CF',
  '23': 'RW',
  '25': 'ST',
  '27': 'LW',
};

String? positionIdFromShortLabel(String? shortLabel) {
  final label = shortLabel?.trim().toUpperCase();
  for (final entry in positionShortLabels.entries) {
    if (entry.value == label) return entry.key;
  }
  return null;
}

class GamePlayer {
  const GamePlayer(
    this.id,
    this.name,
    this.position,
    this.overall, {
    this.potential,
    this.foot,
    this.height,
    this.weight,
    this.age,
    this.birthdate,
    this.nationalityCode,
    this.nationalityName,
    this.positionIds = const [],
    this.realFace,
    this.teamId,
    this.teamName,
  });
  final String id, name, position;
  final int? overall, potential, height, weight, age;
  final String? foot;
  final DateTime? birthdate;
  final String? nationalityCode, nationalityName;

  final List<String> positionIds;
  final bool? realFace;
  final String? teamId, teamName;

  String? get mainPositionId => positionIds.isEmpty ? null : positionIds.first;
}

class GamePlayers {
  GamePlayers._();

  static final Map<String, Future<List<GamePlayer>>> _cache = {};
  static Future<List<GamePlayer>> load(String version) =>
      _cache.putIfAbsent(version, () => _read(version));

  static final _selected = <String, Map<String, GamePlayer?>>{};
  static Future<Map<String, GamePlayer>> lookup(
    String version,
    Iterable<String> ids,
  ) async {
    final wanted = ids.where((id) => id.isNotEmpty).toSet();
    if (wanted.isEmpty) return const {};
    final full = _cache[version];
    if (full != null) {
      return {
        for (final p in await full)
          if (wanted.contains(p.id)) p.id: p,
      };
    }
    final cache = _selected.putIfAbsent(version, () => {});
    final result = <String, GamePlayer>{};
    final missing = <String>{};
    for (final id in wanted) {
      if (!cache.containsKey(id)) {
        missing.add(id);
      } else {
        final player = cache.remove(id);
        cache[id] = player;
        if (player != null) result[id] = player;
      }
    }
    if (missing.isNotEmpty) {
      final found = await _read(version, only: missing);
      for (final id in missing) {
        cache[id] = null;
      }
      for (final player in found) {
        result[player.id] = player;
        cache[player.id] = player;
      }
      while (cache.length > 256) {
        cache.remove(cache.keys.first);
      }
    }
    return result;
  }

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  static Future<List<GamePlayer>> _read(
    String version, {
    Set<String>? only,
  }) async {
    final file = switch (version) {
      'FIFA23' => 'fifa23_players.json',
      'FC24' => 'fc24_players.json',
      'FC25' => 'fc25_players.json',
      'FC26' => 'fc26_players.json',
      'FC27' => 'fc27_players.json.gz',
      _ => throw ArgumentError.value(version, 'version'),
    };
    if (file.endsWith('.gz')) {
      final bytes = await rootBundle.load('assets/$file');
      return BackgroundData.run(_decode, (
        source: null,
        compressed: bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        ),
        only: only,
      ), label: 'player catalog');
    }
    final source = await rootBundle.loadString('assets/$file', cache: false);
    return BackgroundData.run(_decode, (
      source: source,
      compressed: null,
      only: only,
    ), label: 'player catalog');
  }

  static List<GamePlayer> _decode(
    ({String? source, Uint8List? compressed, Set<String>? only}) request,
  ) {
    final source =
        request.source ?? utf8.decode(gzip.decode(request.compressed!));
    final rows = jsonDecode(source) as List<dynamic>;
    return rows
        .where(
          (raw) =>
              request.only == null ||
              request.only!.contains(
                raw is List ? '${raw[0]}' : '${(raw as Map)['player_id']}',
              ),
        )
        .map((raw) {
          if (raw is List<dynamic>) {
            final positions = raw.length > 11 && raw[11] is List
                ? (raw[11] as List).map((item) => item.toString()).toList()
                : const <String>[];
            return GamePlayer(
              raw[0].toString(),
              raw[1].toString(),
              positions.map((id) => positionShortLabels[id] ?? id).join(', '),
              raw.length > 7 ? _int(raw[7]) : null,
              potential: raw.length > 6 ? _int(raw[6]) : null,
              height: raw.length > 8 ? _int(raw[8]) : null,
              weight: raw.length > 9 ? _int(raw[9]) : null,
              foot: raw.length > 10 ? (raw[10] == 0 ? 'Left' : 'Right') : null,
              age: _int(raw[2]),
              birthdate: raw.length > 3
                  ? DateTime.tryParse(raw[3]?.toString() ?? '')
                  : null,
              nationalityCode: raw.length > 5 ? raw[5]?.toString() : null,
              positionIds: positions,
              realFace: raw.length > 12 ? raw[12] == true : null,
              teamId: raw.length > 4 ? raw[4]?.toString() : null,
            );
          }
          final row = raw as Map<String, dynamic>;
          final positions = (row['player_positions'] ?? '').toString();
          return GamePlayer(
            row['player_id'].toString(),
            (row['short_name'] ?? row['full_name'] ?? '').toString(),
            positions,
            _int(row['overall']),
            potential: _int(row['potential']),
            height: _int(row['height_cm']),
            weight: _int(row['weight_kg']),
            foot: row['preferred_foot']?.toString(),
            age: _int(row['age']),
            birthdate: DateTime.tryParse(row['dob']?.toString() ?? ''),
            nationalityName: (row['nationality'] ?? row['nationality_name'])
                ?.toString(),
            positionIds: positions
                .split(',')
                .map(positionIdFromShortLabel)
                .whereType<String>()
                .toList(),
            realFace: row['real_face'] == null
                ? null
                : row['real_face'] == true || row['real_face'] == 'Yes',
            teamId:
                RegExp(r'/team/(\d+)/')
                    .firstMatch(row['team_id']?.toString() ?? '')
                    ?.group(1) ??
                row['team_id']?.toString(),
            teamName: row['team_name']?.toString(),
          );
        })
        .toList();
  }
}
