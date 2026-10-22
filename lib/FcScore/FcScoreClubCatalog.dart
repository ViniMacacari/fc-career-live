import '../utils/GameCatalog.dart';
import '../utils/SqlService.dart';
import 'FcScoreApi.dart';
import 'FcScoreModels.dart';

class FcScoreClubCatalog {
  const FcScoreClubCatalog(this.teams, this.leagues);
  final List<CatalogItem> teams, leagues;

  static bool _supports(Object? versions, String version) =>
      fcId(versions)
          .split(',')
          .any((v) => fcVersion(v.trim()) == fcVersion(version));

  static Future<FcScoreClubCatalog> load(SqlService sql, String version) async {
    final catalog = await GameCatalog.load();
    final db = await sql.database;
    final leagues = <String, CatalogItem>{
      for (final l in catalog.leagues(version).where((l) => !l.isCustom))
        l.id: l,
    };
    for (final l in (await db.query(
      'CustomLeague',
    )).where((l) => _supports(l['fifaVersion'], version))) {
      leagues[fcId(l['id'])] = CatalogItem(
        fcId(l['id']),
        fcName(l['label']),
        imageUrl: l['imageUrl'] as String?,
        imagePath: l['imagePath'] as String?,
        isCustom: true,
        isWoman: l['isWoman'] == 1,
        fifaVersion: fcId(l['fifaVersion']),
      );
    }
    final edits = (await db.query('ClubCustomizationModel'))
        .where((c) => _supports(c['fifaVersion'], version))
        .toList();
    final teams = <String, CatalogItem>{};
    for (final t in catalog.teams(version).where((t) => !t.isCustom)) {
      final base = catalog.team(version, t.id, ignoreCustomizations: true) ?? t;
      final edit = edits
          .where(
            (c) =>
                c['originalTeamId'] == t.id &&
                c['originalLeagueId'] == t.leagueId,
          )
          .firstOrNull;
      teams[t.id] = CatalogItem(
        t.id,
        edit == null ? base.label : fcName(edit['clubName'], base.label),
        leagueId: t.leagueId,
        assetPath: base.assetPath,
        imageUrl: edit?['imageUrl'] as String? ?? base.imageUrl,
        imagePath: edit?['imagePath'] as String? ?? base.imagePath,
        isWoman: base.isWoman,
        clubIdentity: base.clubIdentity,
        customizationId: edit == null ? null : fcId(edit['id']),
      );
    }
    for (final t in (await db.query(
      'CustomClub',
    )).where((t) => _supports(t['fifaVersion'], version))) {
      teams[fcId(t['id'])] = CatalogItem(
        fcId(t['id']),
        fcName(t['label']),
        leagueId: fcId(t['leagueId']),
        imageUrl: t['imageUrl'] as String?,
        imagePath: t['imagePath'] as String?,
        isCustom: true,
        fifaVersion: fcId(t['fifaVersion']),
      );
    }
    int compare(CatalogItem a, CatalogItem b) =>
        fcNormalize(a.label).compareTo(fcNormalize(b.label));
    return FcScoreClubCatalog(
      teams.values.toList()..sort(compare),
      leagues.values.toList()..sort(compare),
    );
  }
}
