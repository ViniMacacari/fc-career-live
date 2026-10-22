import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/ClubCustomizationModel.dart';
import '../models/CustomClub.dart';
import '../models/CustomLeague.dart';
import '../models/Tournament.dart';
import 'FootballFormations.dart';
import 'GameCatalog.dart';
import 'GamePlayers.dart';
import 'SqlService.dart';
import 'SharedClubAvailability.dart';
import 'CompetitionTrophies.dart';

class CustomImageFiles {
  CustomImageFiles._();

  static const leagues = 'leagues';
  static const teams = 'teams';
  static const teamCustomizations = 'team_customizations';
  static const tournaments = 'tournaments';
  static const trophies = 'trophies';

  static const _allFolders = [
    'faces',
    'holderFaces',
    'moments',
    'leagues',
    'teams',
    'tournaments',
    'trophies',
    'person_faces',
    'team_customizations',
    'twitter_faces',
  ];

  static String? _docsDir;

  static String? get cachedDocsDir => _docsDir;

  static Future<String> docsDir() async =>
      _docsDir ??= (await getApplicationDocumentsDirectory()).path;

  static bool isRelative(String path) =>
      _allFolders.any((folder) => path.startsWith('/$folder/'));

  static String? absolute(String? path) {
    if (path == null || path.isEmpty) return null;
    final docs = _docsDir;
    if (isRelative(path)) return docs == null ? null : '$docs$path';
    if (docs != null && !File(path).existsSync()) {
      for (final folder in _allFolders) {
        final index = path.indexOf('/$folder/');
        if (index > 0) return '$docs${path.substring(index)}';
      }
    }
    return path;
  }

  static Future<String> store(String source, String folder, String id) async {
    final relative = '/$folder/$id/${p.basename(source)}';
    final target = File('${await docsDir()}$relative');
    await target.parent.create(recursive: true);
    await target.writeAsBytes(await File(source).readAsBytes());
    return relative;
  }

  static Future<String?> resolveForSave({
    required String? previous,
    required String? selected,
    required String folder,
    required String id,
  }) async {
    await docsDir();
    if (selected != null &&
        previous != null &&
        (selected == previous || selected == absolute(previous))) {
      return previous;
    }
    if (previous != null) await deleteFile(previous);
    if (selected == null) return null;
    return store(selected, folder, id);
  }

  static Future<void> deleteFile(String? path) async {
    final absolutePath =
        absolute(path) ??
        (path != null && isRelative(path) ? '${await docsDir()}$path' : null);
    if (absolutePath == null) return;
    try {
      final file = File(absolutePath);
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('Falha ao apagar imagem $absolutePath: $error');
    }
  }

  static Future<void> deleteFolder(String folder, String id) async {
    try {
      final dir = Directory('${await docsDir()}/$folder/$id');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (error) {
      debugPrint('Falha ao apagar pasta $folder/$id: $error');
    }
  }
}

typedef UsageError = ({String key, int count});

typedef CustomTournamentRow = ({Tournament tournament, String? imagePath});

class CustomContentService {
  CustomContentService._();

  static Future<Database> get _db => SqlService.instance.database;

  static Future<List<CustomLeague>> getCustomLeagues() async =>
      (await (await _db).query('CustomLeague'))
          .map(CustomLeague.fromMap)
          .toList();

  static Future<List<CustomClub>> getCustomClubs() async =>
      (await (await _db).query('CustomClub')).map(CustomClub.fromMap).toList();

  static Future<List<ClubCustomizationModel>> getClubCustomizations() async =>
      (await (await _db).query('ClubCustomizationModel'))
          .map(ClubCustomizationModel.fromMap)
          .toList();

  static Future<void> createCustomLeague(
    CustomLeague league, {
    CompetitionTrophy? trophy,
  }) async {
    await (await _db).transaction((txn) async {
      await txn.insert('CustomLeague', league.toMap());
      if (trophy != null) await CompetitionTrophies.save(txn, trophy);
    });
    await GameCatalog.reloadCustomData();
  }

  static Future<void> updateCustomLeague(
    CustomLeague league, {
    CompetitionTrophy? trophy,
  }) async {
    await (await _db).transaction((txn) async {
      await txn.update(
        'CustomLeague',
        league.toMap(),
        where: 'id = ?',
        whereArgs: [league.id],
      );
      if (trophy != null) await CompetitionTrophies.save(txn, trophy);
    });
    await GameCatalog.reloadCustomData();
  }

  static Future<void> removeCustomLeague(String id) async {
    await (await _db).delete('CustomLeague', where: 'id = ?', whereArgs: [id]);
    await CustomImageFiles.deleteFolder(CustomImageFiles.leagues, id);
    await GameCatalog.reloadCustomData();
  }

  static Future<void> createCustomClub(CustomClub club) async {
    await (await _db).insert('CustomClub', club.toMap());
    await GameCatalog.reloadCustomData();
  }

  static Future<void> saveSharedCustomClub(
    CustomClub club,
    String sourceVersion,
  ) async {
    await SharedClubAvailability.save(
      await _db,
      await GameCatalog.load(),
      club,
      sourceVersion,
    );
    await GameCatalog.reloadCustomData();
  }

  static Future<void> updateCustomClub(CustomClub club) async {
    await (await _db).update(
      'CustomClub',
      club.toMap(),
      where: 'id = ?',
      whereArgs: [club.id],
    );
    await GameCatalog.reloadCustomData();
  }

  static Future<void> removeCustomTeam(String id) async {
    await (await _db).delete('CustomClub', where: 'id = ?', whereArgs: [id]);
    await CustomImageFiles.deleteFolder(CustomImageFiles.teams, id);
    await GameCatalog.reloadCustomData();
  }

  static Future<List<UsageError>> isCustomTeamInUse(String teamId) async {
    const checks = <(String, List<String>, String)>[
      ('Persons', ['teamId'], 'isUsedInPerson'),
      (
        'PlayerTransferItem',
        ['fromTeamId', 'toTeamId'],
        'isUsedInPlayerHistory',
      ),
      (
        'PlayerFixtures',
        ['oppositeTeamId', 'playerTeamId'],
        'isUsedInPlayerFixture',
      ),
      ('Trophies', ['teamId'], 'isUsedInTrophies'),
      (
        'ManagerFixtures',
        ['oppositeTeamId', 'playerTeamId'],
        'isUsedInManagerFixture',
      ),
      (
        'ManagerCareerHistoryItem',
        ['fromTeamId', 'toTeamId'],
        'isUsedInManagerHistory',
      ),
      ('TeamTransferItem', ['fromTeamId', 'toTeamId'], 'isUsedInTeamTransfers'),
      (
        'TournamentResultTableItem',
        ['teamId'],
        'isUsedInTournamentResultTable',
      ),
      (
        'TournamentResultBracketItem',
        ['team_A_Id', 'team_B_Id'],
        'isUsedInTournamentResultBracket',
      ),
      ('GlobalAward', ['teamId'], 'isUsedInGlobalAwards'),
      ('Injury', ['teamId'], 'isUsedInInjuries'),
      ('AcademyPlayer', ['teamId'], 'isUsedInAcademyPlayers'),
      ('TeamRecordHolder', ['teamId'], 'isUsedInRecordHolders'),
      ('YTFixture', ['oppositeTeamId', 'playerTeamId'], 'isUsedInYTFixture'),
    ];
    return _usage(teamId, checks, 'customConfiguration.teamErrors.');
  }

  static Future<void> createClubCustomization(ClubCustomizationModel c) async {
    await (await _db).insert('ClubCustomizationModel', c.toMap());
    await GameCatalog.reloadCustomData();
  }

  static Future<void> updateClubCustomization(ClubCustomizationModel c) async {
    await (await _db).update(
      'ClubCustomizationModel',
      c.toMap(),
      where: 'id = ?',
      whereArgs: [c.id],
    );
    await GameCatalog.reloadCustomData();
  }

  static Future<void> removeClubCustomization(String id) async {
    await (await _db).delete(
      'ClubCustomizationModel',
      where: 'id = ?',
      whereArgs: [id],
    );
    await CustomImageFiles.deleteFolder(
      CustomImageFiles.teamCustomizations,
      id,
    );
    await GameCatalog.reloadCustomData();
  }

  static Future<List<CustomTournamentRow>> getAllCustomTournaments() async {
    final rows = await (await _db).query(
      'Tournament',
      orderBy: 'name COLLATE NOCASE',
    );
    return [
      for (final row in rows)
        (
          tournament: Tournament.fromMap(row),
          imagePath: row['imagePath'] as String?,
        ),
    ];
  }

  static Future<void> createCustomTournament(
    Tournament tournament,
    String? imagePath, {
    CompetitionTrophy? trophy,
  }) async {
    await (await _db).transaction((txn) async {
      await txn.insert('Tournament', {
        ...tournament.toMap(),
        'imagePath': imagePath,
      });
      if (trophy != null) await CompetitionTrophies.save(txn, trophy);
    });
    await GameCatalog.reloadCustomData();
  }

  static Future<void> updateCustomTournament(
    Tournament tournament,
    String? imagePath, {
    CompetitionTrophy? trophy,
  }) async {
    await (await _db).transaction((txn) async {
      await txn.update(
        'Tournament',
        {...tournament.toMap(), 'imagePath': imagePath},
        where: 'id = ?',
        whereArgs: [tournament.id],
      );
      if (trophy != null) await CompetitionTrophies.save(txn, trophy);
    });
    await GameCatalog.reloadCustomData();
  }

  static Future<void> removeCustomTournament(String id) async {
    await (await _db).delete('Tournament', where: 'id = ?', whereArgs: [id]);
    await CustomImageFiles.deleteFolder(CustomImageFiles.tournaments, id);
  }

  static Future<List<UsageError>> isCustomTournamentInUse(String id) async {
    const checks = <(String, List<String>, String)>[
      ('PlayerFixtures', ['tournamentId'], 'isUsedInPlayerFixture'),
      ('TournamentResult', ['tournamentId'], 'isUsedInTournamentResult'),
      ('ManagerFixtures', ['tournamentId'], 'isUsedInManagerFixture'),
    ];
    return _usage(id, checks, 'customConfiguration.tournamentErrors.');
  }

  static Future<List<UsageError>> _usage(
    String id,
    List<(String, List<String>, String)> checks,
    String keyPrefix,
  ) async {
    final db = await _db;
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    )).map((row) => row['name']).toSet();
    final errors = <UsageError>[];
    for (final (table, columns, key) in checks) {
      if (!tables.contains(table)) continue;
      try {
        final where = columns.map((column) => '$column = ?').join(' OR ');
        final result = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM $table WHERE $where',
          List.filled(columns.length, id),
        );
        final count = Sqflite.firstIntValue(result) ?? 0;
        if (count > 0) errors.add((key: '$keyPrefix$key', count: count));
      } catch (error) {
        debugPrint('Falha ao verificar uso em $table: $error');
      }
    }
    return errors;
  }
}

String playerImageVersionFolder(String fifaVersion) => switch (fifaVersion) {
  'FIFA23' => '23',
  'FC24' => '24',
  'FC25' => '25',
  'FC26' => '26',
  'FC27' => '27',
  _ => '',
};

DateTime? getInitialSeasonDefaultDate(String fifaVersion) =>
    switch (fifaVersion) {
      'FIFA23' => DateTime(2022, 7, 1),
      'FC24' => DateTime(2023, 7, 1),
      'FC25' => DateTime(2024, 7, 1),
      'FC26' => DateTime(2025, 7, 1),
      'FC27' => DateTime(2026, 7, 1),
      _ => null,
    };

String? getPlayerImageUrl(String? realPlayerId, String version) {
  final id = int.tryParse(realPlayerId ?? '');
  if (id == null) return null;
  return 'https://cmtracker.fra1.cdn.digitaloceanspaces.com/DB/'
      '${playerImageVersionFolder(version)}/heads/p$id.png';
}

String positionShortName(String? positionId) {
  final label = positionShortLabels[canonicalPositionId(positionId)];
  return label == null ? '—' : 'positions.positionsList.$label'.tr();
}

const positionPriorityOrder = [
  '25',
  '21',
  '27',
  '23',
  '18',
  '14',
  '16',
  '12',
  '10',
  '5',
  '8',
  '7',
  '2',
  '3',
  '0',
];

int getPositionPriority(String? positionId) =>
    positionPriorityOrder.indexOf(positionId ?? '-1');
