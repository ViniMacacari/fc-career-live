import '../FcScore/FcScoreClubCatalog.dart';
import '../FcScore/FcScoreModels.dart' show fcNormalize;
import '../ManagerCareer/OtherPlayers/WorldPlayers.dart';
import '../models/TeamTransferItem.dart';
import '../models/Person.dart';
import 'GameCatalog.dart';
import 'GamePlayers.dart';
import 'SqlService.dart';

class PlayerClubLookup {
  PlayerClubLookup(
    this.teams,
    this.byPlayer,
    this.byRealPlayer, {
    Map<String, CatalogItem>? catalogTeams,
    this.sofifaTeams = const {},
  }) : catalogTeams = catalogTeams ?? teams;
  final Map<String, CatalogItem> teams;
  final Map<String, CatalogItem> catalogTeams;

  final Map<String, List<CatalogItem>> sofifaTeams;

  static CatalogItem? _pick(List<CatalogItem>? options, String? name) {
    if (options == null || options.isEmpty) return null;
    final first = fcNormalize(options.first.label);
    if (options.every((c) => fcNormalize(c.label) == first)) {
      return options.first;
    }
    final wanted = fcNormalize(name ?? '');
    return options.where((c) => fcNormalize(c.label) == wanted).firstOrNull;
  }

  final Map<String, String> byPlayer, byRealPlayer;

  static Future<PlayerClubLookup> load({
    required SqlService sql,
    required Person person,
    String? seasonId,
  }) async {
    final clubs = await FcScoreClubCatalog.load(sql, person.fifaVersion);
    final db = await sql.database;
    seasonId ??= (await sql.getSeasons(person.id)).firstOrNull?.id;
    final local = <String, String>{}, real = <String, String>{};
    for (final row in await db.rawQuery(
      '''
      SELECT p.playerId, p.remotePlayerId, t.teamId
      FROM FcScoreWorldPlayer p JOIN FcScoreWorldTeam t
        ON t.personId = p.personId AND t.seasonId = p.seasonId
        AND t.remoteId = p.remoteTeamId
      WHERE p.personId = ? AND p.seasonId = ?
    ''',
      [person.id, seasonId],
    )) {
      local['${row['playerId']}'] = '${row['teamId']}';
      real['${row['remotePlayerId']}'] = '${row['teamId']}';
    }
    await SqlService.ensureTransferReleaseSchema(db);
    final transfers = await sql.getTeamTransfers(person.id);
    final applied =
        transfers.where((row) => row['movementApplied'] != 0).toList()..sort(
          (a, b) => (teamTransferEffectiveDate(a) ?? DateTime(0)).compareTo(
            teamTransferEffectiveDate(b) ?? DateTime(0),
          ),
        );
    for (final row in [
      ...transfers.reversed.where((row) => row['movementApplied'] == 0),
      ...applied,
    ]) {
      final pending = row['movementApplied'] == 0;
      final id = row['playerInstanceId']?.toString();
      if (id == null) continue;
      final team = row[pending ? 'fromTeamId' : 'toTeamId']?.toString() ?? '';
      if (pending && local.containsKey(id)) continue;
      local[id] = team;
    }
    await WorldPlayers.ensureSchema(db);
    final moved = <String, DateTime>{
      for (final row in applied)
        if (row['playerInstanceId'] != null)
          '${row['playerInstanceId']}':
              teamTransferEffectiveDate(row) ?? DateTime(0),
    };
    for (final row in await db.query(
      'WorldPlayer',
      where: 'personId = ? AND hidden = 0',
      whereArgs: [person.id],
    )) {
      final id = '${row['playerId']}';
      final since = DateTime.tryParse('${row['since'] ?? ''}');
      final transfer = moved[id];
      if (transfer != null && (since == null || transfer.isAfter(since))) {
        continue;
      }
      local[id] = '${row['teamId'] ?? ''}';
    }
    for (final row in await db.query(
      'TeamPlayer',
      columns: ['playerId'],
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [person.id, seasonId],
    )) {
      if (row['playerId'] != null) local['${row['playerId']}'] = person.teamId;
    }
    for (final row in await db.query(
      'CustomCreatedPlayer',
      columns: ['id', 'realPlayerId'],
      where: 'personId = ?',
      whereArgs: [person.id],
    )) {
      final team = local[row['id']];
      final id = row['realPlayerId']?.toString();
      if (team != null && id != null) real[id] = team;
    }
    final teams = {for (final club in clubs.teams) club.id: club};
    final identities = <String?, List<CatalogItem>>{};
    for (final club in clubs.teams.where(
      (t) => !t.isCustom && !t.isSupplementalClub,
    )) {
      (identities[club.clubIdentity] ??= []).add(club);
    }
    final catalog = await GameCatalog.load();
    final catalogTeams = <String, CatalogItem>{
      for (final club in catalog.teams('FC27').where((t) => !t.isCustom))
        if (_pick(identities[club.clubIdentity], club.label)
            case final CatalogItem item)
          club.id: item,
    };
    final sofifaTeams = <String, List<CatalogItem>>{
      for (final MapEntry(:key, :value) in identities.entries)
        if (int.tryParse(key ?? '') case final int doubled when doubled.isEven)
          '${doubled ~/ 2}': value,
    };
    final names = <String, CatalogItem?>{};
    for (final club in clubs.teams.where((t) => !t.isWoman)) {
      final name = fcNormalize(club.label);
      names[name] = names.containsKey(name) ? null : club;
    }
    return PlayerClubLookup(
      teams,
      local,
      real,
      catalogTeams: catalogTeams,
      sofifaTeams: sofifaTeams,
    ).._byName.addAll(names);
  }

  final _byName = <String, CatalogItem?>{};

  CatalogItem? club({
    String? playerId,
    GamePlayer? player,
    String? realPlayerId,
  }) {
    final current =
        byPlayer[playerId] ?? byRealPlayer[realPlayerId ?? player?.id];
    final id = current ?? player?.teamId;
    if (current == '') return const CatalogItem('', 'Sem clube', leagueId: '');
    if (id == '0' || id == '-1' || id == '111592') {
      return const CatalogItem('', 'Sem clube', leagueId: '');
    }
    if (id == null || id.isEmpty) {
      final name = player?.teamName;
      return name == null || name.isEmpty
          ? null
          : CatalogItem('', name, leagueId: '');
    }
    return (current != null
            ? teams[id]
            : catalogTeams[id] ??
                  _pick(sofifaTeams[id], player?.teamName) ??
                  _byName[fcNormalize(player?.teamName ?? '')]) ??
        CatalogItem(
          id,
          (current == null ? player?.teamName : null) ?? 'Clube não informado',
          leagueId: '',
        );
  }
}
