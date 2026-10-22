import '../models/Person.dart';
import '../utils/GameCatalog.dart';
import '../utils/SqlService.dart';
import 'FcScoreApi.dart';
import 'FcScoreModels.dart';

class FcScoreCareerIdentity {
  FcScoreCareerIdentity(
    this.catalog,
    this.version,
    this.competitions,
    this.clubs,
    this.customizations,
  );
  final GameCatalog catalog;
  final String version;
  final Map<String, CatalogItem> competitions, clubs;
  final List<Map<String, Object?>> customizations;
  static bool _supports(Object? value, String version) =>
      fcId(value)
          .split(',')
          .any((v) => fcVersion(v.trim()) == fcVersion(version));

  static Future<Map<String, CatalogItem>> competitionCatalog(
    SqlService sql,
    String version,
  ) async {
    final catalog = await GameCatalog.load();
    final db = await sql.database;
    final result = <String, CatalogItem>{
      for (final t in await catalog.tournaments(version)) t.id: t,
      for (final l in catalog.leagues(version)) 'league:${l.id}': l,
      for (final l in (await db.query(
        'CustomLeague',
      )).where((l) => _supports(l['fifaVersion'], version)))
        'league:${l['id']}': CatalogItem(
          'league:${l['id']}',
          fcId(l['label']),
          imageUrl: l['imageUrl'] as String?,
          imagePath: l['imagePath'] as String?,
          isCustom: true,
        ),
    };
    for (final t in (await db.query('Tournament')).where(
      (t) =>
          fcId(t['fifaVersions']).isEmpty ||
          fcVersion(fcId(t['fifaVersions'])).contains(fcVersion(version)),
    )) {
      final old = result[fcId(t['id'])];
      result[fcId(t['id'])] = CatalogItem(
        fcId(t['id']),
        fcId(t['name']),
        imagePath: t['imagePath'] as String? ?? old?.imagePath,
        imageUrl: old?.imageUrl,
        assetPath: fcId(t['imageName']).startsWith('assets/')
            ? fcId(t['imageName'])
            : old?.assetPath,
        isCustom: true,
      );
    }
    return result;
  }

  static Future<FcScoreCareerIdentity> load(
    SqlService sql,
    Person person,
  ) async {
    final catalog = await GameCatalog.load();
    final db = await sql.database;
    return FcScoreCareerIdentity(
      catalog,
      person.fifaVersion,
      await competitionCatalog(sql, person.fifaVersion),
      {
        for (final t in (await db.query(
          'CustomClub',
        )).where((t) => _supports(t['fifaVersion'], person.fifaVersion)))
          fcId(t['id']): CatalogItem(
            fcId(t['id']),
            fcId(t['label']),
            leagueId: fcId(t['leagueId']),
            imageUrl: t['imageUrl'] as String?,
            imagePath: t['imagePath'] as String?,
            isCustom: true,
          ),
      },
      (await db.query('ClubCustomizationModel'))
          .where((c) => _supports(c['fifaVersion'], person.fifaVersion))
          .toList(),
    );
  }

  CatalogItem? competition(FcJson row) =>
      competitions[fcId(row['tournamentId'])];
  CatalogItem? club(String id, String? league) {
    final base = clubs[id] ?? catalog.team(version, id, leagueId: league);
    final edits = customizations
        .where((c) => c['originalTeamId'] == id)
        .toList();
    final edit =
        edits.where((c) => c['originalLeagueId'] == league).firstOrNull ??
        (edits.length == 1 ? edits.single : null);
    if (edit == null) return base;
    return CatalogItem(
      id,
      fcId(edit['clubName']),
      leagueId: league,
      imageUrl: edit['imageUrl'] as String? ?? base?.imageUrl,
      imagePath: edit['imagePath'] as String? ?? base?.imagePath,
      customizationId: fcId(edit['id']),
    );
  }
}
