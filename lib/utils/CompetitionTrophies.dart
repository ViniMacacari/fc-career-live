import 'package:sqflite/sqflite.dart';

import 'SqlService.dart';

class CompetitionTrophy {
  const CompetitionTrophy({
    required this.competitionId,
    required this.version,
    required this.name,
    this.imagePath,
    this.imageUrl,
  });
  final String competitionId, version, name;
  final String? imagePath, imageUrl;
  String get awardId => 'competition:$version:$competitionId';
  Map<String, Object?> toMap() => {
    'competitionId': competitionId,
    'fifaVersion': version,
    'name': name,
    'imagePath': imagePath,
    'imageUrl': imageUrl,
  };
  factory CompetitionTrophy.fromMap(Map<String, Object?> row) =>
      CompetitionTrophy(
        competitionId: row['competitionId'] as String,
        version: row['fifaVersion'] as String,
        name: row['name'] as String,
        imagePath: row['imagePath'] as String?,
        imageUrl: row['imageUrl'] as String?,
      );
}

abstract final class CompetitionTrophies {
  static Future<void> ensureSchema(DatabaseExecutor db) => db.execute(
    '''
    CREATE TABLE IF NOT EXISTS CompetitionTrophy(
      competitionId TEXT NOT NULL, fifaVersion TEXT NOT NULL, name TEXT NOT NULL,
      imagePath TEXT, imageUrl TEXT, PRIMARY KEY(competitionId, fifaVersion))''',
  );

  static Future<List<CompetitionTrophy>> all({Database? database}) async {
    final db = database ?? await SqlService.instance.database;
    await ensureSchema(db);
    return (await db.query('CompetitionTrophy'))
        .map(CompetitionTrophy.fromMap)
        .toList();
  }

  static Future<CompetitionTrophy?> find(
    String competitionId,
    String version,
  ) async {
    final db = await SqlService.instance.database;
    await ensureSchema(db);
    final rows = await db.query(
      'CompetitionTrophy',
      where: 'competitionId = ? AND fifaVersion = ?',
      whereArgs: [competitionId, version],
    );
    return rows.isEmpty ? null : CompetitionTrophy.fromMap(rows.first);
  }

  static Future<void> save(
    DatabaseExecutor db,
    CompetitionTrophy trophy,
  ) async {
    await ensureSchema(db);
    await db.insert(
      'CompetitionTrophy',
      trophy.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
