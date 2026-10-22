import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../FcScore/FcScoreApi.dart';
import '../../FcScore/FcScoreCareerIdentity.dart';
import '../../FcScore/FcScoreModels.dart' show FcScoreLink;
import '../../FcScore/FcScoreRepository.dart';
import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../models/TeamTransferItem.dart';
import '../../utils/ManagerStatService.dart';
import '../../utils/PlayerClubLookup.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/GamePlayers.dart';
import '../../utils/SqlService.dart';
import '../../utils/databaseUtils.dart';
import 'WorldPlayers.dart';

export 'WorldPlayers.dart';

const _accents = 'àáâãäåèéêëìíîïòóôõöøùúûüýÿçñ';
const _plain = 'aaaaaaeeeeiiiioooooouuuuyycn';
final _folded = {
  for (var i = 0; i < _accents.length; i++)
    _accents.codeUnitAt(i): _plain.codeUnitAt(i),
};

String searchFold(String text) {
  final buffer = StringBuffer();
  for (final unit in text.toLowerCase().codeUnits) {
    buffer.writeCharCode(_folded[unit] ?? unit);
  }
  return buffer.toString();
}

String? positionLine(String? id) => switch (id) {
  '0' => 'GOL',
  '2' || '3' || '5' || '7' || '8' => 'DEF',
  '10' || '12' || '14' || '16' || '18' => 'MEI',
  '21' || '23' || '25' || '27' => 'ATA',
  _ => null,
};

const positionLines = ['GOL', 'DEF', 'MEI', 'ATA'];

const _secondaryLeagues = {'1003', '1014', '42'};

enum OtherPlayerOrigin { api, manual, departed, catalog }

class OtherPlayer {
  OtherPlayer({
    required this.name,
    required this.origin,
    this.playerId,
    this.catalog,
    this.positionId,
    this.nationalityId,
    this.realPlayerId,
    this.avatar,
    this.foot,
    this.overall,
    this.potential,
    this.age,
    this.shirtNumber,
    this.height,
    this.weight,
    this.firstSeasonAge,
    this.birthdate,
    this.team,
    this.clubUnknown = false,
  });

  final String? playerId;
  final GamePlayer? catalog;
  final String name;
  final String? positionId, nationalityId, realPlayerId, avatar, foot;
  final int? overall, potential, age, shirtNumber, height, weight;
  final int? firstSeasonAge;
  final Object? birthdate;

  final CatalogItem? team;

  final bool clubUnknown;
  final OtherPlayerOrigin origin;

  String get key => playerId ?? 'catalog:${catalog!.id}';
  String? get line => positionLine(positionId);
  bool get fromCatalog => origin == OtherPlayerOrigin.catalog;

  String nationality = '', positionLabel = '';

  late final String searchKey = searchFold(
    [
      name,
      team?.label ?? 'Sem clube',
      positionLabel,
      positionShortLabels[positionId] ?? '',
      line ?? '',
      nationality,
    ].join(' '),
  );

  Map<String, Object?> profileRow(String? seasonId) => {
    'playerId': playerId ?? '',
    'customName': name,
    'customPositionId': positionId,
    'customPotential': potential,
    'overall': overall,
    'realPlayerId': realPlayerId,
    'seasonId': seasonId,
    'shirtNumber': shirtNumber,
    'otherTeam': true,
    'clubUnknown': clubUnknown,
    'teamId': team?.id,
    'leagueId': team?.leagueId,
    if (!fromCatalog) ...{
      'customFoot': foot,
      'customAvatarFilePath': avatar,
      'nationalityId': nationalityId,
      'birthdate': birthdate,
      'playerHeight': height,
      'playerWeight': weight,
      'firstSeasonAge': firstSeasonAge,
    },
  };
}

class OtherTeam {
  OtherTeam(this.team, this.league, this.players, {this.imported = false});

  final CatalogItem? team;
  final CatalogItem? league;
  final List<OtherPlayer> players;
  final bool imported;
  String get id => team?.id ?? '';
  String get label => team?.label ?? 'Sem clube';

  double? get averageOverall {
    final best = players.map((p) => p.overall).whereType<int>().toList()
      ..sort((a, b) => b - a);
    if (best.isEmpty) return null;
    final top = best.take(11);
    return top.reduce((a, b) => a + b) / top.length;
  }

  int get careerPlayers => players.where((p) => !p.fromCatalog).length;
}

class OtherPlayersFilter {
  const OtherPlayersFilter({
    this.lines = const {},
    this.leagueId,
    this.nationalityId,
    this.minOverall,
    this.maxAge,
    this.careerOnly = false,
  });
  final Set<String> lines;
  final String? leagueId, nationalityId;
  final int? minOverall, maxAge;
  final bool careerOnly;

  bool get active =>
      lines.isNotEmpty ||
      leagueId != null ||
      nationalityId != null ||
      minOverall != null ||
      maxAge != null ||
      careerOnly;

  bool matches(OtherPlayer p) =>
      (lines.isEmpty || lines.contains(p.line)) &&
      (leagueId == null || p.team?.leagueId == leagueId) &&
      (nationalityId == null || p.nationalityId == nationalityId) &&
      (minOverall == null || (p.overall ?? 0) >= minOverall!) &&
      (maxAge == null || (p.age != null && p.age! <= maxAge!)) &&
      (!careerOnly || !p.fromCatalog);
}

class OtherPlayersSnapshot {
  OtherPlayersSnapshot({
    required this.season,
    required this.teams,
    required this.leagues,
    this.unplaced = const [],
  });
  final Season? season;
  final List<OtherTeam> teams;
  final Map<String, CatalogItem> leagues;

  final List<OtherPlayer> unplaced;
  late final List<OtherPlayer> players = [
    for (final t in teams) ...t.players,
    ...unplaced,
  ];

  List<OtherPlayer> search(String query, OtherPlayersFilter filter) {
    final tokens = searchFold(query)
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    return [
      for (final p in players)
        if (filter.matches(p) && tokens.every(p.searchKey.contains)) p,
    ]..sort((a, b) {
      final overall = (b.overall ?? 0).compareTo(a.overall ?? 0);
      return overall != 0 ? overall : a.name.compareTo(b.name);
    });
  }

  OtherTeam? teamOf(String? teamId) =>
      teams.where((t) => t.id == (teamId ?? '')).firstOrNull;
}

class CompetitionLine {
  CompetitionLine({
    required this.key,
    required this.name,
    this.tournamentId,
    this.teamId,
    this.leagueId,
    this.appearances,
    this.goals,
    this.assists,
    this.minutes,
    this.rating,
    this.yellowCards,
    this.redCards,
    this.cleanSheets,
    this.manualId,
    this.overridesApi = false,
    this.remoteTeamId,
    this.teamName,
    this.date,
  });
  final String key, name;
  final String? tournamentId, teamId, leagueId;
  final String? remoteTeamId, teamName;
  final DateTime? date;
  final int? appearances, goals, assists, minutes;
  final int? yellowCards, redCards, cleanSheets;
  final double? rating;

  final String? manualId;
  final bool overridesApi;
  bool get fromApi => manualId == null;

  static CompetitionLine total(List<CompetitionLine> lines) {
    int? sum(int? Function(CompetitionLine) f) {
      final values = lines.map(f).whereType<int>();
      return values.isEmpty ? null : values.reduce((a, b) => a + b);
    }

    var weight = 0, rated = 0.0;
    for (final l in lines) {
      if (l.rating != null && (l.appearances ?? 0) > 0) {
        weight += l.appearances!;
        rated += l.rating! * l.appearances!;
      }
    }
    final dates = lines.map((l) => l.date).whereType<DateTime>();
    return CompetitionLine(
      key: 'total',
      name: 'Total',
      date: dates.isEmpty ? null : dates.reduce((a, b) => a.isAfter(b) ? a : b),
      appearances: sum((l) => l.appearances),
      goals: sum((l) => l.goals),
      assists: sum((l) => l.assists),
      minutes: sum((l) => l.minutes),
      yellowCards: sum((l) => l.yellowCards),
      redCards: sum((l) => l.redCards),
      cleanSheets: sum((l) => l.cleanSheets),
      rating: weight == 0 ? null : rated / weight,
    );
  }
}

class PlayerTransferEntry {
  const PlayerTransferEntry({
    required this.id,
    required this.date,
    required this.type,
    required this.source,
    this.fromTeamId,
    this.fromLeagueId,
    this.toTeamId,
    this.toLeagueId,
    this.value,
  });
  final String id, type, source;
  final DateTime date;
  final String? fromTeamId, fromLeagueId, toTeamId, toLeagueId;
  final int? value;

  bool get editable => source != 'club';
}

const worldTransferTypes = {
  'transfer': 'Transferência',
  'loan': 'Empréstimo',
  'loanReturn': 'Fim de empréstimo',
  'free': 'Transferência livre',
  'release': 'Rescisão',
};

String transferEntryLabel(PlayerTransferEntry entry) =>
    worldTransferTypes[entry.type] ??
    transferTypeLabel(
      TeamTransferType.values.where((t) => t.name == entry.type).firstOrNull ??
          TeamTransferType.buy,
    );

class OtherPlayersRepository {
  OtherPlayersRepository({SqlService? sql, this.catalogPlayers})
    : sql = sql ?? SqlService.instance;
  final SqlService sql;

  final List<GamePlayer>? catalogPlayers;

  Future<Database> _db() async {
    final db = await sql.database;
    await WorldPlayers.ensureSchema(db);
    return db;
  }

  Future<OtherPlayersSnapshot> load(Person person) async {
    final db = await _db();
    final seasons = await sql.getSeasons(person.id);
    final season = seasons.firstOrNull;
    final catalog = await GameCatalog.load();
    await WorldPlayers.backfill(db, person.id, person.teamId);
    final lookup = await PlayerClubLookup.load(
      sql: sql,
      person: person,
      seasonId: season?.id,
    );
    final own = season == null
        ? <String>{}
        : {
            for (final row in await db.query(
              'TeamPlayer',
              columns: ['playerId'],
              where: 'personId = ? AND seasonId = ?',
              whereArgs: [person.id, season.id],
            ))
              '${row['playerId']}',
          };
    final world = {
      for (final row in await db.query(
        'WorldPlayer',
        where: 'personId = ?',
        whereArgs: [person.id],
      ))
        '${row['playerId']}': row,
    };
    final careerTeams = {
      for (final row in world.values)
        if (row['teamId'] != null) '${row['teamId']}',
      ...lookup.byPlayer.values,
    };
    String? identityOf(CatalogItem t) {
      final identity = t.clubIdentity ?? lookup.teams[t.id]?.clubIdentity;
      return identity == null || identity.isEmpty
          ? null
          : '$identity|${searchFold(t.label)}';
    }

    final byIdentity = <String, List<CatalogItem>>{};
    for (final t in lookup.teams.values) {
      final identity = identityOf(t);
      if (!t.isCustom && identity != null) {
        (byIdentity[identity] ??= []).add(t);
      }
    }
    CatalogItem canonical(CatalogItem team) {
      final group = byIdentity[identityOf(team)];
      if (group == null || group.length < 2) return team;
      return group.where((t) => careerTeams.contains(t.id)).firstOrNull ??
          group
              .where((t) => !_secondaryLeagues.contains(t.leagueId))
              .firstOrNull ??
          team;
    }

    final ownIdentity = switch (lookup.teams[person.teamId]) {
      final CatalogItem team => identityOf(team),
      null => null,
    };
    bool isOwn(CatalogItem? t) =>
        t != null &&
        (t.id == person.teamId ||
            (ownIdentity != null && identityOf(t) == ownIdentity));
    final imported = {
      for (final row in world.values)
        if (row['source'] == 'api' && row['teamId'] != null)
          switch (lookup.teams['${row['teamId']}']) {
            final CatalogItem team => canonical(team).id,
            null => '${row['teamId']}',
          },
    };
    final ids = {
      for (final entry in lookup.byPlayer.entries)
        if (entry.value != person.teamId &&
            !own.contains(entry.key) &&
            world[entry.key]?['hidden'] != 1)
          entry.key,
    };
    final identities = await sql.getCustomPlayers(person.id, playerIds: ids);
    final realIds = {
      for (final row in await db.query(
        'CustomCreatedPlayer',
        columns: ['realPlayerId'],
        where: 'personId = ? AND realPlayerId IS NOT NULL',
        whereArgs: [person.id],
      ))
        '${row['realPlayerId']}',
    };
    int? age(Object? birthdate, int? firstSeasonAge) {
      if (season == null) return firstSeasonAge;
      final born = birthdate is num
          ? DateTime.fromMillisecondsSinceEpoch(birthdate.toInt())
          : birthdate is DateTime
          ? birthdate
          : DateTime.tryParse('${birthdate ?? ''}');
      return calcPlayerAge(
        fifaVersion: person.fifaVersion,
        seasonStart: season.startDate,
        seasonEnd: season.endDate,
        birthdate: born,
        firstSeasonAge: firstSeasonAge,
      );
    }

    CatalogItem? club(String? id, String? leagueId) {
      if (id == null || id.isEmpty) return null;
      return canonical(
        lookup.teams[id] ??
            catalog.team(person.fifaVersion, id, leagueId: leagueId) ??
            CatalogItem(id, 'Clube não informado', leagueId: leagueId),
      );
    }

    final players = <OtherPlayer>[];
    for (final row in identities) {
      final id = '${row['id']}';
      final record = world[id];
      final team = club(
        lookup.byPlayer[id],
        record?['leagueId'] as String? ??
            lookup.teams[lookup.byPlayer[id]]?.leagueId,
      );
      if (isOwn(team)) continue;
      players.add(
        OtherPlayer(
          playerId: id,
          name: '${row['name'] ?? 'Jogador'}',
          positionId: row['positionId'] as String?,
          nationalityId: row['nationalityId']?.toString(),
          realPlayerId: row['realPlayerId']?.toString(),
          avatar: row['customAvatarFilePath'] as String?,
          foot: row['foot'] as String?,
          overall: (row['overall'] as num?)?.toInt(),
          potential: (row['potential'] as num?)?.toInt(),
          height: (row['height'] as num?)?.toInt(),
          weight: (row['weight'] as num?)?.toInt(),
          firstSeasonAge: (row['firstSeasonAge'] as num?)?.toInt(),
          birthdate: row['birthdate'],
          age: age(row['birthdate'], (row['firstSeasonAge'] as num?)?.toInt()),
          shirtNumber: (record?['shirtNumber'] as num?)?.toInt(),
          team: team,
          origin: switch (record?['source']) {
            'api' => OtherPlayerOrigin.api,
            null => OtherPlayerOrigin.departed,
            _ => OtherPlayerOrigin.manual,
          },
        ),
      );
    }
    final nationalities = {
      for (final n in catalog.nationalities) n.label.toLowerCase(): n.id,
    };
    for (final p
        in catalogPlayers ?? await GamePlayers.load(person.fifaVersion)) {
      if (realIds.contains(p.id)) continue;
      final placed = p.teamId != null || p.teamName != null;
      final found = placed ? lookup.club(player: p) : null;
      final team = found == null || found.id.isEmpty ? null : canonical(found);
      if (isOwn(team) || imported.contains(team?.id)) continue;
      players.add(
        OtherPlayer(
          catalog: p,
          name: p.name,
          positionId: p.mainPositionId,
          nationalityId:
              p.nationalityCode ??
              nationalities[p.nationalityName?.toLowerCase()],
          realPlayerId: p.id,
          foot: p.foot,
          overall: p.overall,
          potential: p.potential,
          height: p.height,
          weight: p.weight,
          birthdate: p.birthdate,
          age: age(p.birthdate, p.age),
          team: team,
          clubUnknown: !placed,
          origin: OtherPlayerOrigin.catalog,
        ),
      );
    }
    final countryLabels = {
      for (final n in catalog.nationalities) n.id: 'countries.${n.label}'.tr(),
    };
    final positionLabels = <String?, String>{};
    for (final p in players) {
      p.nationality = countryLabels[p.nationalityId] ?? '';
      p.positionLabel = positionLabels[p.positionId] ??= positionShortName(
        p.positionId,
      );
    }
    final byTeam = <String, List<OtherPlayer>>{};
    final teams = <String, CatalogItem?>{};
    for (final p in players.where((p) => !p.clubUnknown)) {
      final id = p.team?.id ?? '';
      (byTeam[id] ??= []).add(p);
      teams.putIfAbsent(id, () => p.team);
    }
    final leagues = <String, CatalogItem>{};
    for (final team in teams.values.whereType<CatalogItem>()) {
      final id = team.leagueId;
      if (id == null || id.isEmpty || leagues.containsKey(id)) continue;
      final league = catalog.league(person.fifaVersion, id);
      if (league != null) leagues[id] = league;
    }
    int lineOrder(OtherPlayer p) => switch (p.line) {
      'GOL' => 0,
      'DEF' => 1,
      'MEI' => 2,
      'ATA' => 3,
      _ => 4,
    };
    final result = [
      for (final entry in byTeam.entries)
        OtherTeam(
          teams[entry.key],
          leagues[teams[entry.key]?.leagueId],
          entry.value..sort((a, b) {
            final line = lineOrder(a).compareTo(lineOrder(b));
            if (line != 0) return line;
            final overall = (b.overall ?? 0).compareTo(a.overall ?? 0);
            return overall != 0 ? overall : a.name.compareTo(b.name);
          }),
          imported: imported.contains(entry.key),
        ),
    ];
    final withData = {
      for (final t in result)
        if (t.careerPlayers > 0) t.league?.id,
    };
    int rank(OtherTeam t) => t.team == null
        ? 4
        : t.league?.id == person.leagueId
        ? 0
        : withData.contains(t.league?.id)
        ? 1
        : t.league == null
        ? 3
        : 2;
    result.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final league = searchFold(a.league?.label ?? '')
          .compareTo(searchFold(b.league?.label ?? ''));
      if (league != 0) return league;
      return searchFold(a.label).compareTo(searchFold(b.label));
    });
    return OtherPlayersSnapshot(
      season: season,
      teams: result,
      leagues: leagues,
      unplaced: [
        for (final p in players)
          if (p.clubUnknown) p,
      ],
    );
  }

  Future<CatalogItem?> clubOf(
    Person person, {
    String? playerId,
    GamePlayer? catalogPlayer,
  }) async {
    await _db();
    final lookup = await PlayerClubLookup.load(sql: sql, person: person);
    final club = lookup.club(
      playerId: playerId,
      player: catalogPlayer,
      realPlayerId: catalogPlayer?.id,
    );
    return club == null || club.id.isEmpty ? null : club;
  }

  Future<String> materialize(
    Person person,
    GamePlayer player, {
    CatalogItem? team,
  }) async {
    final db = await _db();
    final catalog = await GameCatalog.load();
    return db.transaction((txn) async {
      final existing = await txn.query(
        'CustomCreatedPlayer',
        columns: ['id'],
        where: 'personId = ? AND realPlayerId = ?',
        whereArgs: [person.id, player.id],
        limit: 1,
      );
      if (existing.isNotEmpty) return '${existing.first['id']}';
      final id = const Uuid().v4();
      final name = player.nationalityName?.toLowerCase();
      await txn.insert('CustomCreatedPlayer', {
        'id': id,
        'personId': person.id,
        'realPlayerId': player.id,
        'name': player.name,
        'positionId': player.mainPositionId ?? '14',
        'overall': player.overall ?? 0,
        'potential': player.potential ?? player.overall ?? 0,
        'birthdate': player.birthdate?.millisecondsSinceEpoch,
        'firstSeasonAge': player.age,
        'height': player.height,
        'weight': player.weight,
        'nationalityId':
            player.nationalityCode ??
            catalog.nationalities
                .where((n) => n.label.toLowerCase() == name)
                .firstOrNull
                ?.id,
        'realFace': player.realFace == false ? 0 : 1,
        'fromRealPlayer': 1,
        'customAvatarFilePath': null,
        'foot': player.foot ?? 'Right',
      });
      await txn.insert('WorldPlayer', {
        'personId': person.id,
        'playerId': id,
        'teamId': team?.id,
        'leagueId': team?.leagueId,
        'since': null,
        'source': 'catalog',
        'hidden': 0,
        'updatedAt': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return id;
    });
  }

  Future<void> _upsert(
    DatabaseExecutor db,
    String personId,
    String playerId,
    Map<String, Object?> values,
  ) async {
    final now = DateTime.now().toIso8601String();
    final updated = await db.update(
      'WorldPlayer',
      {...values, 'updatedAt': now},
      where: 'personId = ? AND playerId = ?',
      whereArgs: [personId, playerId],
    );
    if (updated == 0) {
      await db.insert('WorldPlayer', {
        'personId': personId,
        'playerId': playerId,
        'source': 'manual',
        'hidden': 0,
        ...values,
        'updatedAt': now,
      });
    }
  }

  Future<void> assign(
    Person person,
    String playerId,
    CatalogItem? team, {
    DateTime? since,
  }) async => _upsert(await _db(), person.id, playerId, {
    'teamId': team?.id,
    'leagueId': team?.leagueId,
    'since': since?.toIso8601String(),
    'source': 'manual',
    'hidden': 0,
  });

  Future<Map<String, Object?>?> worldRow(
    Person person,
    String playerId,
  ) async => (await (await _db()).query(
    'WorldPlayer',
    where: 'personId = ? AND playerId = ?',
    whereArgs: [person.id, playerId],
    limit: 1,
  )).firstOrNull;

  Future<void> setShirtNumber(
    Person person,
    String playerId,
    int? shirtNumber,
  ) async =>
      _upsert(await _db(), person.id, playerId, {'shirtNumber': shirtNumber});

  Future<void> hide(Person person, String playerId) async =>
      _upsert(await _db(), person.id, playerId, {'hidden': 1});

  Future<void> saveTransfer(
    Person person,
    String playerId, {
    String? id,
    required DateTime date,
    required String type,
    CatalogItem? from,
    CatalogItem? to,
    int? value,
    bool move = true,
  }) async {
    final db = await _db();
    await db.transaction((txn) async {
      final row = {
        'personId': person.id,
        'playerId': playerId,
        'date': date.toIso8601String(),
        'fromTeamId': from?.id,
        'fromLeagueId': from?.leagueId,
        'toTeamId': to?.id,
        'toLeagueId': to?.leagueId,
        'type': type,
        'value': value,
      };
      if (id == null) {
        await txn.insert('WorldTransfer', {
          ...row,
          'id': const Uuid().v4(),
          'source': 'manual',
          'createdAt': DateTime.now().toIso8601String(),
        });
      } else {
        await txn.update(
          'WorldTransfer',
          row,
          where: 'id = ? AND personId = ?',
          whereArgs: [id, person.id],
        );
      }
      if (move) {
        await _upsert(txn, person.id, playerId, {
          'teamId': to?.id,
          'leagueId': to?.leagueId,
          'since': date.toIso8601String(),
          'source': 'manual',
          'hidden': 0,
          if (to?.id != from?.id) 'shirtNumber': null,
        });
      }
    });
  }

  Future<void> deleteTransfer(Person person, String id) async =>
      (await _db()).delete(
        'WorldTransfer',
        where: 'id = ? AND personId = ?',
        whereArgs: [id, person.id],
      );

  Future<List<PlayerTransferEntry>> transfers(
    Person person,
    String playerId,
  ) async {
    if (playerId.isEmpty) return [];
    final db = await _db();
    final club = [
      for (final row in await db.query(
        'TeamTransferItem',
        where: 'personId = ? AND playerInstanceId = ?',
        whereArgs: [person.id, playerId],
      ))
        PlayerTransferEntry(
          id: '${row['id']}',
          date: teamTransferEffectiveDate(row) ?? DateTime(0),
          type: '${row['type']}',
          source: 'club',
          fromTeamId: row['fromTeamId'] as String?,
          fromLeagueId: row['fromLeagueId'] as String?,
          toTeamId: row['toTeamId'] as String?,
          toLeagueId: row['toLeagueId'] as String?,
          value: (row['transferValue'] as num?)?.toInt(),
        ),
    ];
    final world = [
      for (final row in await db.query(
        'WorldTransfer',
        where: 'personId = ? AND playerId = ?',
        whereArgs: [person.id, playerId],
      ))
        PlayerTransferEntry(
          id: '${row['id']}',
          date: DateTime.tryParse('${row['date']}') ?? DateTime(0),
          type: '${row['type']}',
          source: '${row['source']}',
          fromTeamId: row['fromTeamId'] as String?,
          fromLeagueId: row['fromLeagueId'] as String?,
          toTeamId: row['toTeamId'] as String?,
          toLeagueId: row['toLeagueId'] as String?,
          value: (row['value'] as num?)?.toInt(),
        ),
    ];
    bool repeated(PlayerTransferEntry e) =>
        e.source == 'api' &&
        club.any(
          (c) =>
              c.toTeamId == e.toTeamId &&
              c.date.difference(e.date).inDays.abs() <= 120,
        );
    return [...club, ...world.where((e) => !repeated(e))]
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<Map<String, List<CompetitionLine>>> seasonLines(
    Person person,
    String playerId,
  ) async {
    if (playerId.isEmpty) return {};
    final db = await _db();
    final rows = await db.query(
      'FcScoreWorldPlayer',
      columns: ['seasonId', 'remoteTeamId', 'rawJson'],
      where: 'personId = ? AND playerId = ?',
      whereArgs: [person.id, playerId],
    );
    final fetched = {
      for (final row in await db.query(
        'WorldPlayerSeason',
        where: 'personId = ? AND playerId = ?',
        whereArgs: [person.id, playerId],
      ))
        '${row['seasonId']}': row,
    };
    final names = await _seasonNames(db, person, {
      for (final r in rows) '${r['seasonId']}',
      ...fetched.keys,
    });
    final mapping = await _apiMapping(person);
    final result = <String, Map<String, CompetitionLine>>{};
    for (final seasonId in {
      for (final r in rows) '${r['seasonId']}',
      ...fetched.keys,
    }) {
      final rosters = <String, ({DateTime? date, FcJson raw})>{
        for (final row in rows.where((r) => r['seasonId'] == seasonId))
          '${row['remoteTeamId']}': () {
            final raw = fcObject(jsonDecode('${row['rawJson']}'));
            return (
              date:
                  DateTime.tryParse(fcId(raw['statsDate'])) ??
                  names.imported[seasonId],
              raw: raw,
            );
          }(),
      };
      final full = fetched[seasonId];
      final fullDate = DateTime.tryParse('${full?['statsDate'] ?? ''}');
      final entries = <(FcJson, String, DateTime?)>[
        if (full != null)
          for (final s in fcList(
            fcObject(jsonDecode('${full['statsJson']}'))['competitions'],
          ))
            if (!_rosterIsNewer(
              rosters[fcId(fcObject(s['team'])['id'])]?.date,
              fullDate,
            ))
              (s, fcId(fcObject(s['team'])['id']), fullDate),
      ];
      final lines = result[seasonId] ??= {};
      for (final MapEntry(key: remoteTeam, value: roster) in rosters.entries) {
        if (full != null && !_rosterIsNewer(roster.date, fullDate)) continue;
        final stats = fcObject(roster.raw['seasonStats']);
        final listed = fcList(stats['competitions']);
        for (final s in listed) {
          entries.add((s, remoteTeam, roster.date));
        }
        final team = names.teams['$seasonId:$remoteTeam'];
        if (listed.isEmpty && stats['totals'] is Map) {
          lines['api:total'] = _apiLine(
            'api:total',
            'Todas as competições',
            fcObject(stats['totals']),
            team: team,
            remoteTeamId: remoteTeam,
            date: roster.date,
          );
        } else if (listed.isEmpty && roster.raw['leagueGoals'] != null) {
          lines['api:league'] = _apiLine(
            'api:league',
            'Liga',
            {
              'goals': roster.raw['leagueGoals'],
              'appearances': roster.raw['leagueAppearances'],
              'yellowCards': roster.raw['yellowCards'],
              'redCards': roster.raw['redCards'],
            },
            team: team,
            remoteTeamId: remoteTeam,
            date: roster.date,
          );
        }
      }
      for (final (s, remoteTeam, date) in entries) {
        _addApiLine(lines, names, mapping, seasonId, s, remoteTeam, date);
      }
    }
    for (final row in await db.query(
      'WorldPlayerStats',
      where: 'personId = ? AND playerId = ?',
      whereArgs: [person.id, playerId],
    )) {
      final lines = result['${row['seasonId']}'] ??= {};
      final key = '${row['competition']}';
      lines[key] = CompetitionLine(
        key: key,
        name: '${row['name'] ?? lines[key]?.name ?? 'Competição'}',
        tournamentId: row['tournamentId'] as String?,
        teamId: row['teamId'] as String? ?? lines[key]?.teamId,
        leagueId: row['leagueId'] as String? ?? lines[key]?.leagueId,
        appearances: (row['appearances'] as num?)?.toInt(),
        goals: (row['goals'] as num?)?.toInt(),
        assists: (row['assists'] as num?)?.toInt(),
        minutes: (row['minutes'] as num?)?.toInt(),
        rating: (row['averageRating'] as num?)?.toDouble(),
        yellowCards: (row['yellowCards'] as num?)?.toInt(),
        redCards: (row['redCards'] as num?)?.toInt(),
        cleanSheets: (row['cleanSheets'] as num?)?.toInt(),
        manualId: '${row['id']}',
        overridesApi: lines[key]?.fromApi ?? false,
        remoteTeamId: lines[key]?.remoteTeamId,
        teamName: lines[key]?.teamName,
      );
    }
    return {
      for (final entry in result.entries)
        entry.key: entry.value.values.toList()
          ..sort((a, b) => (b.appearances ?? 0).compareTo(a.appearances ?? 0)),
    };
  }

  Future<Map<String, CompetitionLine>> seasonTotals(
    Person person,
    String seasonId,
    Iterable<String> playerIds, {
    String? teamId,
  }) async {
    final result = <String, CompetitionLine>{};
    for (final id in playerIds) {
      final lines = [
        for (final line
            in (await seasonLines(person, id))[seasonId] ??
                const <CompetitionLine>[])
          if (teamId == null || line.teamId == teamId) line,
      ];
      if (lines.isNotEmpty) result[id] = CompetitionLine.total(lines);
    }
    return result;
  }

  static bool _rosterIsNewer(DateTime? roster, DateTime? full) =>
      full == null || (roster != null && roster.isAfter(full));

  static CompetitionLine _apiLine(
    String key,
    String name,
    FcJson stats, {
    String? tournamentId,
    ({String teamId, String? leagueId})? team,
    String? remoteTeamId,
    String? teamName,
    DateTime? date,
  }) => CompetitionLine(
    key: key,
    name: name,
    tournamentId: tournamentId,
    teamId: team?.teamId,
    leagueId: team?.leagueId,
    remoteTeamId: remoteTeamId,
    teamName: teamName == null || teamName.isEmpty ? null : teamName,
    date: date,
    appearances: fcInt(stats['appearances']),
    goals: fcInt(stats['goals']),
    assists: fcInt(stats['assists']),
    minutes: fcInt(stats['minutes']),
    rating: num.tryParse('${stats['averageRating'] ?? ''}')?.toDouble(),
    yellowCards: fcInt(stats['yellowCards']),
    redCards: fcInt(stats['redCards']),
    cleanSheets: fcInt(stats['cleanSheets']),
  );

  Future<({FcScoreCareerIdentity identity, FcScoreLink? link})>? _mapping;

  Future<({FcScoreCareerIdentity identity, FcScoreLink? link})> _apiMapping(
    Person person,
  ) => _mapping ??= () async {
    return (
      identity: await FcScoreCareerIdentity.load(sql, person),
      link: await FcScoreRepository(sql: sql).linkFor(person.id),
    );
  }();

  void _addApiLine(
    Map<String, CompetitionLine> lines,
    ({
      Map<String, String> competitions,
      Map<String, ({String teamId, String? leagueId})> teams,
      Map<String, DateTime> imported,
    })
    names,
    ({FcScoreCareerIdentity identity, FcScoreLink? link}) mapping,
    String? seasonId,
    FcJson stats,
    String remoteTeam,
    DateTime? date,
  ) {
    final remote = fcId(fcObject(stats['competition'])['id']);
    final tournamentId =
        names.competitions['$seasonId:$remote'] ??
        _mapped(mapping.link?.competitions[remote]);
    var key = tournamentId ?? 'api:$remote';
    if (lines[key] != null && lines[key]!.remoteTeamId != remoteTeam) {
      key = '$key|$remoteTeam';
    }
    final linked = _mapped(mapping.link?.teams[remoteTeam]);
    final team =
        names.teams['$seasonId:$remoteTeam'] ??
        (linked == null ? null : (teamId: linked, leagueId: null));
    lines[key] = _apiLine(
      key,
      mapping.identity.competitions[tournamentId]?.label ??
          fcName(fcObject(stats['competition'])['name']),
      stats,
      tournamentId: tournamentId,
      team: team,
      remoteTeamId: remoteTeam,
      teamName: team == null
          ? fcName(fcObject(stats['team'])['name'], '')
          : mapping.identity.club(team.teamId, team.leagueId)?.label ??
                fcName(fcObject(stats['team'])['name'], ''),
      date: date,
    );
  }

  static String? _mapped(String? id) =>
      id == null || id.isEmpty || id.startsWith('new:') ? null : id;

  Future<List<CompetitionLine>> apiLines(
    Person person,
    String? seasonId,
    FcJson stats,
    DateTime date,
  ) async {
    final db = await _db();
    final names = await _seasonNames(db, person, {?seasonId});
    final mapping = await _apiMapping(person);
    final lines = <String, CompetitionLine>{};
    for (final s in fcList(stats['competitions'])) {
      _addApiLine(
        lines,
        names,
        mapping,
        seasonId,
        s,
        fcId(fcObject(s['team'])['id']),
        date,
      );
    }
    return lines.values.toList()
      ..sort((a, b) => (b.appearances ?? 0).compareTo(a.appearances ?? 0));
  }

  Future<
    ({
      Map<String, String> competitions,
      Map<String, ({String teamId, String? leagueId})> teams,
      Map<String, DateTime> imported,
    })
  >
  _seasonNames(Database db, Person person, Set<String> seasonIds) async {
    final competitions = <String, String>{};
    final teams = <String, ({String teamId, String? leagueId})>{};
    final imported = <String, DateTime>{};
    if (seasonIds.isNotEmpty) {
      final marks = List.filled(seasonIds.length, '?').join(',');
      for (final c in await db.rawQuery(
        'SELECT seasonId, remoteId, tournamentId, currentDate FROM FcScoreCompetition WHERE personId = ? AND seasonId IN ($marks)',
        [person.id, ...seasonIds],
      )) {
        final seasonId = '${c['seasonId']}';
        competitions['$seasonId:${c['remoteId']}'] = '${c['tournamentId']}';
        final date = DateTime.tryParse('${c['currentDate']}');
        if (date != null &&
            (imported[seasonId] == null || date.isAfter(imported[seasonId]!))) {
          imported[seasonId] = date;
        }
      }
      for (final t in await db.rawQuery(
        'SELECT seasonId, remoteId, teamId, leagueId FROM FcScoreWorldTeam WHERE personId = ? AND seasonId IN ($marks)',
        [person.id, ...seasonIds],
      )) {
        teams['${t['seasonId']}:${t['remoteId']}'] = (
          teamId: '${t['teamId']}',
          leagueId: t['leagueId'] as String?,
        );
      }
    }
    return (competitions: competitions, teams: teams, imported: imported);
  }

  Future<void> saveLine(
    Person person,
    String playerId,
    String seasonId,
    CompetitionLine line,
  ) async {
    final db = await _db();
    final row = {
      'personId': person.id,
      'playerId': playerId,
      'seasonId': seasonId,
      'competition': line.key,
      'tournamentId': line.tournamentId,
      'name': line.name,
      'teamId': line.teamId,
      'leagueId': line.leagueId,
      'appearances': line.appearances,
      'goals': line.goals,
      'assists': line.assists,
      'minutes': line.minutes,
      'averageRating': line.rating,
      'yellowCards': line.yellowCards,
      'redCards': line.redCards,
      'cleanSheets': line.cleanSheets,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await db.transaction((txn) async {
      await txn.delete(
        'WorldPlayerStats',
        where: 'personId = ? AND playerId = ? AND seasonId = ? AND competition = ?',
        whereArgs: [person.id, playerId, seasonId, line.key],
      );
      if (line.manualId != null) {
        await txn.delete(
          'WorldPlayerStats',
          where: 'id = ? AND personId = ?',
          whereArgs: [line.manualId, person.id],
        );
      }
      await txn.insert('WorldPlayerStats', {
        ...row,
        'id': line.manualId ?? const Uuid().v4(),
      });
    });
  }

  Future<void> deleteLine(Person person, String manualId) async =>
      (await _db()).delete(
        'WorldPlayerStats',
        where: 'id = ? AND personId = ?',
        whereArgs: [manualId, person.id],
      );
}
