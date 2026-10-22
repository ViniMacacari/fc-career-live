import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/CustomClub.dart';
import '../models/CustomLeague.dart';
import 'GameCatalog.dart';

abstract class SharedClubAvailability {
  static Future<void> save(
    Database db,
    GameCatalog catalog,
    CustomClub club,
    String sourceVersion,
  ) async {
    final versions = club.fifaVersions.toSet();
    if (versions.isEmpty ||
        versions.any((v) => !GameCatalog.fifaVersions.contains(v))) {
      throw ArgumentError('Selecione versões válidas do FIFA.');
    }
    final source = catalog
        .getAllLeagues(sourceVersion)
        .where((l) => l.id == club.leagueId)
        .firstOrNull;
    if (source == null) {
      throw StateError('A competição de origem não foi encontrada.');
    }
    final missing = versions
        .where(
          (version) =>
              !catalog.getAllLeagues(version).any((l) => l.id == club.leagueId),
        )
        .toSet();
    await db.transaction((txn) async {
      if (missing.isNotEmpty) {
        final rows = await txn.query(
          'CustomLeague',
          where: 'id = ?',
          whereArgs: [club.leagueId],
        );
        final previous = rows.isEmpty ? null : CustomLeague.fromMap(rows.first);
        final league = CustomLeague(
          id: club.leagueId,
          label: source.league.label,
          fifaVersion: {...?previous?.fifaVersions, ...missing}.join(','),
          isWoman: source.league.isWoman,
          imageUrl: source.league.imageUrl,
          imagePath: source.league.imagePath,
          createdAt: previous?.createdAt ?? club.createdAt,
          updatedAt: club.updatedAt,
        );
        if (previous == null) {
          await txn.insert('CustomLeague', league.toMap());
        } else {
          await txn.update(
            'CustomLeague',
            league.toMap(),
            where: 'id = ?',
            whereArgs: [league.id],
          );
        }
        for (final team in source.teams.where((t) => t.id != club.id)) {
          var id = team.id;
          var rows = await txn.query(
            'CustomClub',
            where: 'id = ?',
            whereArgs: [id],
          );
          if (rows.isNotEmpty && rows.first['leagueId'] != club.leagueId) {
            id = const Uuid().v5(
              Namespace.url.value,
              'mc-ea:league:${club.leagueId}:team:${team.id}',
            );
            rows = await txn.query(
              'CustomClub',
              where: 'id = ?',
              whereArgs: [id],
            );
          }
          final previous = rows.isEmpty ? null : CustomClub.fromMap(rows.first);
          final imported = CustomClub(
            id: id,
            label: previous?.label ?? team.label,
            leagueId: club.leagueId,
            fifaVersion: {...?previous?.fifaVersions, ...missing}.join(','),
            imageUrl: previous?.imageUrl ?? team.imageUrl,
            imagePath: previous?.imagePath ?? team.imagePath,
            createdAt: previous?.createdAt ?? club.createdAt,
            updatedAt: club.updatedAt,
          );
          if (previous == null) {
            await txn.insert('CustomClub', imported.toMap());
          } else {
            await txn.update(
              'CustomClub',
              imported.toMap(),
              where: 'id = ?',
              whereArgs: [id],
            );
          }
        }
      }
      final existing = await txn.query(
        'CustomClub',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [club.id],
      );
      if (existing.isEmpty) {
        await txn.insert('CustomClub', club.toMap());
      } else {
        await txn.update(
          'CustomClub',
          club.toMap(),
          where: 'id = ?',
          whereArgs: [club.id],
        );
      }
    });
  }
}
