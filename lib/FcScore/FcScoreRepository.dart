import 'FcScoreLineupEvents.dart';

import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../ManagerCareer/OtherPlayers/WorldPlayers.dart';
import '../models/FixtureFormation.dart';
import '../models/ManagerFixture.dart';
import '../models/ManagerFixturePlayerPerformance.dart';
import '../models/OpponentLineup.dart';
import '../models/Person.dart';
import '../models/PlayerFixture.dart';
import '../models/Season.dart';
import '../utils/GameCatalog.dart';
import '../utils/BackgroundData.dart';
import '../utils/SqlService.dart';
import '../utils/SeasonRosterService.dart';
import '../utils/FootballFormations.dart';
import '../utils/GamePlayers.dart';
import '../utils/databaseUtils.dart' show getPositionPriority;
import 'FcScoreApi.dart';
import 'FcScoreMappingIssues.dart';
import 'FcScoreClubCatalog.dart';
import 'FcScoreCareerIdentity.dart';
import 'FcScoreModels.dart';
import 'FcScoreSeasonStats.dart';
import 'FcScoreWorldData.dart';
import 'FcScoreUpdateOptions.dart';
import 'FcScoreWorldPlayerReview.dart';
import 'FcScorePlayerCreation.dart';

part 'FcScoreWorldRepository.dart';
part 'FcScoreMatchStandings.dart';
part 'FcScoreOpponentCompletion.dart';

String _uuid() => const Uuid().v4();

String? fcSuggestPlayer(FcJson remote, List<Map<String, Object?>> local) {
  final id = fcId(remote['id']);
  final byId = local
      .where((p) => fcId(p['realPlayerId']) == id && id.isNotEmpty)
      .toList();
  if (byId.length == 1) return fcId(byId.single['id']);
  if (byId.length > 1) return null;
  final name = fcNormalize(fcPlayerName(remote));
  final byName = local
      .where(
        (p) =>
            fcNormalize(fcId(p['name'])) == name &&
            (fcId(p['realPlayerId']).isEmpty || fcId(p['realPlayerId']) == id),
      )
      .toList();
  return byName.length == 1 ? fcId(byName.single['id']) : null;
}

String? fcSuggestReference(
  FcJson reference,
  List<CatalogItem> local, {
  String? leagueId,
}) {
  final name = fcNormalize(fcName(reference['name']));
  final byName = local.where((v) => fcNormalize(v.label) == name).toList();
  if (byName.length == 1) return byName.single.id;
  final byId = local.where((v) => v.id == fcId(reference['id'])).firstOrNull;
  if (byName.length > 1) {
    if (byId != null && byName.any((v) => v.id == byId.id)) return byId.id;
    final inLeague = byName
        .where((v) => leagueId != null && v.leagueId == leagueId)
        .toList();
    if (inLeague.length == 1) return inLeague.single.id;
    final identities = byName.map((v) => v.clubIdentity).toSet();
    if (identities.length == 1 && identities.single != null) {
      final primary = byName.where((v) => !v.isSupplementalClub).toList();
      if (primary.length == 1) return primary.single.id;
    }
    return null;
  }
  return byId?.id;
}

Map<String, String> fcSuggestWorldPlayers(
  FcScoreWorldData data,
  List<Map<String, Object?>> local, {
  required Map<String, String> mapping,
  required String ownClubId,
  Set<String> ownPlayerIds = const {},
}) {
  final review = FcWorldPlayerReview(data, local);
  final result = Map<String, String>.of(mapping);
  final active = review.players.values.toList();
  bool own(FcWorldReviewPlayer p) => p.teamIds.contains(ownClubId);
  bool exact(FcWorldReviewPlayer p, String? choice) =>
      choice != null && fcId(review.local[choice]?['realPlayerId']) == p.id;
  final grouped = <String, List<FcWorldReviewPlayer>>{};
  for (final p in active) {
    final choice = result[p.id];
    if (!fcIsPlayerCreation(choice) && review.local.containsKey(choice)) {
      (grouped[choice!] ??= []).add(p);
    }
  }
  for (final entry in grouped.entries.where((e) => e.value.length > 1)) {
    var winners = entry.value.where((p) => exact(p, entry.key)).toList();
    if (winners.isEmpty && ownPlayerIds.contains(entry.key)) {
      winners = entry.value.where(own).toList();
    }
    if (winners.length != 1) continue;
    for (final p in entry.value.where((p) => p.id != winners.single.id)) {
      result[p.id] = 'new';
    }
  }
  final occupied = {
    for (final p in active)
      if (!fcIsPlayerCreation(result[p.id])) result[p.id]!,
  };
  active.sort((a, b) {
    int priority(FcWorldReviewPlayer p) =>
        local.any((l) => fcId(l['realPlayerId']) == p.id)
        ? 0
        : own(p)
        ? 1
        : 2;
    final order = priority(a).compareTo(priority(b));
    return order == 0 ? a.id.compareTo(b.id) : order;
  });
  final squad = local
      .where((p) => ownPlayerIds.contains(fcId(p['id'])))
      .toList();
  for (final p in active) {
    final choice = result[p.id];
    if (fcIsPlayerDraft(choice) ||
        (!fcIsPlayerCreation(choice) && review.local.containsKey(choice))) {
      continue;
    }
    final suggested =
        (own(p) ? fcSuggestPlayer(p.remote, squad) : null) ??
        fcSuggestPlayer(p.remote, local);
    if (suggested != null &&
        (!occupied.contains(suggested) || exact(p, suggested))) {
      result[p.id] = suggested;
      occupied.add(suggested);
    } else {
      result.putIfAbsent(p.id, () => 'new');
    }
  }
  return result;
}

enum FcImportState { available, alreadyImported, canComplete }

int? fcFixtureAffinity(
  Map<String, Object?> fixture,
  FcScoreMatch match,
  FcScoreLink link,
) {
  final local = DateTime.tryParse(fcId(fixture['date'])), remote = match.date;
  if (local == null || remote == null) return null;
  final days = DateTime(
    local.year,
    local.month,
    local.day,
  ).difference(DateTime(remote.year, remote.month, remote.day)).inDays.abs();
  if (days > 3) return null;
  final own = match.own(link), opponent = match.opponent(link);
  final opponentId = fcId(fcObject(opponent['team'])['id']);
  return (days == 0 ? 4 : 1) +
      (link.teams[opponentId] == fcId(fixture['oppositeTeamId']) ? 3 : 0) +
      (link.competitions[match.competitionId] == fcId(fixture['tournamentId'])
          ? 2
          : 0) +
      (fixture['location'] ==
              (match.homeId == link.remoteClubId ? 'home' : 'away')
          ? 1
          : 0) +
      (fcInt(own['goals']) == fcInt(fixture['playerTeamScore']) &&
              fcInt(opponent['goals']) == fcInt(fixture['oppositeTeamScore'])
          ? 2
          : 0);
}

FcScoreMatch? fcRecommendedMatch(
  Map<String, Object?> fixture,
  Iterable<FcScoreMatch> matches,
  FcScoreLink link,
) {
  final scored = [
    for (final match in matches)
      if (fcFixtureAffinity(fixture, match, link) case final score?
          when score >= 5)
        (match, score),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  if (scored.isEmpty || (scored.length > 1 && scored[0].$2 == scored[1].$2)) {
    return null;
  }
  return scored.first.$1;
}

ManagerFixturePlayerPerformance fcCompletePerformance(
  ManagerFixturePlayerPerformance user,
  ManagerFixturePlayerPerformance api, {
  int goalRoom = 1 << 20,
  int assistRoom = 1 << 20,
}) {
  bool none(List<Object> details, int? count) =>
      details.isEmpty && (count ?? 0) == 0;
  List<T> events<T>(List<T> mine, int? count, List<T> theirs, [int? room]) =>
      none(mine.cast<Object>(), count)
      ? theirs.take(math.max(0, room ?? theirs.length)).toList()
      : mine;
  int? total(List<Object> mine, int? count, List<Object> filled, int? theirs) =>
      none(mine, count) && theirs != null ? filled.length : count;
  final goals = events(
    user.goalDetails,
    user.goalsCount,
    api.goalDetails,
    goalRoom,
  );
  final assists = events(
    user.assistDetails,
    user.assistsCount,
    api.assistDetails,
    assistRoom,
  );
  final yellow = events(
    user.yellowCardDetails,
    user.yellowCards,
    api.yellowCardDetails,
  );
  final red = events(user.redCardDetails, user.redCards, api.redCardDetails);
  final timed = user.substitutionDetails.any((s) => s.type != null);
  return ManagerFixturePlayerPerformance(
    id: user.id,
    personId: user.personId,
    fixtureId: user.fixtureId,
    playerInstanceId: user.playerInstanceId,
    goalsCount: total(user.goalDetails, user.goalsCount, goals, api.goalsCount),
    assistsCount: total(
      user.assistDetails,
      user.assistsCount,
      assists,
      api.assistsCount,
    ),
    yellowCards: total(
      user.yellowCardDetails,
      user.yellowCards,
      yellow,
      api.yellowCards,
    ),
    redCards: total(user.redCardDetails, user.redCards, red, api.redCards),
    avgRating: user.avgRating ?? api.avgRating,
    shotsCount: user.shotsCount ?? api.shotsCount,
    shotAccuracy: user.shotAccuracy ?? api.shotAccuracy,
    passes: user.passes ?? api.passes,
    keyPasses: user.keyPasses ?? api.keyPasses,
    passAccuracy: user.passAccuracy ?? api.passAccuracy,
    tackles: user.tackles ?? api.tackles,
    tacklesAccuracy: user.tacklesAccuracy ?? api.tacklesAccuracy,
    dribbles: user.dribbles ?? api.dribbles,
    dribblesAccuracy: user.dribblesAccuracy ?? api.dribblesAccuracy,
    saves: user.saves ?? api.saves,
    penaltySaves: user.penaltySaves ?? api.penaltySaves,
    apiStats: {
      ...api.apiStats,
      for (final e in user.apiStats.entries)
        if (e.value != null) e.key: e.value,
    },
    recordedMinutes: timed
        ? user.recordedMinutes
        : user.recordedMinutes ?? api.recordedMinutes,
    recordedStarted: timed
        ? user.recordedStarted
        : user.recordedStarted ?? api.recordedStarted,
    goalDetails: goals,
    assistDetails: assists,
    yellowCardDetails: yellow,
    redCardDetails: red,
    ownGoalDetails: user.ownGoalDetails.isEmpty
        ? api.ownGoalDetails
        : user.ownGoalDetails,
    substitutionDetails: timed
        ? user.substitutionDetails
        : api.substitutionDetails,
    missedPenaltyDetails: user.missedPenaltyDetails,
    injuryDetails: user.injuryDetails,
  );
}

class FcImportResult {
  const FcImportResult(this.fixtureId, this.state);
  final String fixtureId;
  final FcImportState state;
}

class FcScoreRepository {
  FcScoreRepository({SqlService? sql}) : sql = sql ?? SqlService.instance;
  final SqlService sql;
  Future<List<String>> recentAddresses() async =>
      (await (await sql.database).query(
        'FcScoreEndpoint',
        orderBy: 'lastConnectedAt DESC, rowid DESC',
        limit: 8,
      )).map((r) => r['address'] as String).toList();
  Future<void> rememberAddress(Uri address) async {
    final db = await sql.database;
    await db.transaction((txn) async {
      await txn.insert('FcScoreEndpoint', {
        'address': address.toString(),
        'lastConnectedAt': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.rawDelete(
        'DELETE FROM FcScoreEndpoint WHERE address NOT IN '
        '(SELECT address FROM FcScoreEndpoint ORDER BY lastConnectedAt DESC, rowid DESC LIMIT 8)',
      );
    });
  }

  Future<FcScoreLink> rememberCareerAddress(
    FcScoreLink link,
    Uri address,
  ) async {
    final saved = (await linkFor(link.personId)) ?? link;
    saved.connectionAddress = address.toString();
    await _saveLink(await sql.database, saved);
    return saved;
  }

  Future<FcScoreLink?> linkFor(String personId) async {
    final rows = await (await sql.database).query(
      'FcScoreCareerLink',
      where: 'personId = ?',
      whereArgs: [personId],
    );
    return rows.isEmpty ? null : FcScoreLink.fromRow(rows.single);
  }

  Future<void> rememberUpdateOptions(
    String personId,
    FcScoreUpdateOptions options,
  ) async {
    final link = await linkFor(personId);
    if (link == null) {
      throw const FcScoreException('Conecte esta carreira primeiro.');
    }
    link.updateOptions = options;
    await _saveLink(await sql.database, link);
  }

  Future<List<FcScoreLink>> linksFor(String saveId) async =>
      (await (await sql.database).query(
        'FcScoreCareerLink',
        where: 'saveId = ?',
        whereArgs: [saveId],
      )).map(FcScoreLink.fromRow).toList();

  Future<FcScoreLink?> linkedCareerFor(
    FcScoreRemoteCareer remote, {
    Person? person,
  }) async {
    if (person != null) {
      final saved = await linkFor(person.id);
      return saved?.belongsTo(remote, person) == true ? saved : null;
    }
    final persons = {
      for (final p in await sql.getPersons(remote.category)) p.id: p,
    };
    final matches = <FcScoreLink>[];
    for (final row in await (await sql.database).query('FcScoreCareerLink')) {
      final link = FcScoreLink.fromRow(row),
          owner = persons[fcId(row['personId'])];
      if (owner != null &&
          link.belongsTo(remote, owner) &&
          (link.saveId == remote.saveId || link.saveName == remote.saveName)) {
        matches.add(link);
      }
    }
    final exact = matches.where((l) => l.saveId == remote.saveId).toList();
    return exact.length == 1
        ? exact.single
        : exact.isEmpty && matches.length == 1
        ? matches.single
        : null;
  }

  Future<FcScoreLink> moveLink(
    FcScoreLink link,
    String saveId, {
    String? saveName,
  }) async {
    final moved = FcScoreLink.fromMap({
      ...link.toMap(),
      'saveId': saveId,
      'saveName': ?saveName,
    });
    await _saveLink(await sql.database, moved);
    return moved;
  }

  FcJson? currentSave(List<FcJson> saves, FcScoreLink link, Person person) {
    final same = saves.where((s) => fcId(s['id']) == link.saveId).firstOrNull;
    if (same != null) return same;
    final type = person.category == PersonCategory.player
        ? 'player'
        : 'manager';
    final renamed = saves
        .where(
          (s) =>
              s['backupSlot'] == null &&
              fcId(s['inGameName']) == link.saveName &&
              (s['careerType'] ?? 'manager') == type,
        )
        .toList();
    return renamed.length == 1 ? renamed.single : null;
  }

  Future<void> _saveLink(DatabaseExecutor db, FcScoreLink link) async =>
      db.insert('FcScoreCareerLink', {
        'personId': link.personId,
        'saveId': link.saveId,
        'saveName': link.saveName,
        'gameVersion': link.gameVersion,
        'mappingJson': jsonEncode(link.toMap()),
        'updatedAt': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<String?> _existingEntityChoice(
    DatabaseExecutor db,
    String table,
    String choice,
    String version, {
    String? leagueId,
  }) async {
    if (!choice.startsWith('new:')) return choice.isEmpty ? null : choice;
    final field = table == 'Tournament' ? 'name' : 'label';
    final old = await db.query(
      table,
      where: '$field = ?',
      whereArgs: [choice.substring(4).trim()],
    );
    for (final row in old) {
      final versions = fcId(
        row[table == 'Tournament' ? 'fifaVersions' : 'fifaVersion'],
      ).split(',');
      if (versions.contains(version) &&
          (leagueId == null || row['leagueId'] == leagueId)) {
        return row['id'] as String;
      }
    }
    return null;
  }

  Future<String> _entity(
    DatabaseExecutor db,
    String table,
    String choice,
    String version, {
    String? leagueId,
  }) async {
    if (!choice.startsWith('new:')) {
      if (choice.isEmpty) {
        throw const FcScoreException(
          'Complete o vínculo dos times e competições.',
        );
      }
      return choice;
    }
    final name = choice.substring(4).trim();
    if (name.isEmpty) {
      throw const FcScoreException('Informe um nome para o novo cadastro.');
    }
    final existing = await _existingEntityChoice(
      db,
      table,
      choice,
      version,
      leagueId: leagueId,
    );
    if (existing != null) return existing;
    final id = _uuid(), now = DateTime.now().toIso8601String();
    await db.insert(
      table,
      table == 'Tournament'
          ? {
              'id': id,
              'name': name,
              'fifaVersions': version,
              'category': 'club',
              'sex': 'any',
              'type': 'custom',
              'leagueId': leagueId,
            }
          : {
              'id': id,
              'label': name,
              'fifaVersion': version,
              'createdAt': now,
              'updatedAt': now,
              if (table == 'CustomClub') ...{
                'personId': '',
                'leagueId': leagueId,
              } else
                'isWoman': 0,
            },
    );
    return id;
  }

  Future<String> _player(
    DatabaseExecutor db,
    String personId,
    FcJson remote,
    String? choice,
  ) async {
    if (!fcIsPlayerCreation(choice)) {
      final old = await db.query(
        'CustomCreatedPlayer',
        where: 'id = ? AND personId = ?',
        whereArgs: [choice, personId],
      );
      if (old.isEmpty) {
        throw const FcScoreException(
          'O jogador vinculado não pertence a esta carreira. Revise o vínculo.',
        );
      }
      return choice!;
    }
    remote = fcPlayerWithChoice(remote, choice);
    final name = fcName(remote['name'], '').trim();
    if (name.isEmpty) {
      throw const FcScoreException(
        'Um jogador está sem nome. Crie-o aqui, gere os dados faltantes ou escolha um cadastro existente.',
      );
    }
    final id = _uuid();
    final overall = fcInt(remote['overall']);
    if (overall == null || overall < 1 || overall > 99) {
      throw const FcScoreException(
        'Um jogador está sem overall válido. Crie-o aqui, gere os dados faltantes ou escolha um cadastro existente.',
      );
    }
    final birthDate = DateTime.tryParse(fcId(remote['birthDate']));
    await db.insert('CustomCreatedPlayer', {
      'id': id,
      'personId': personId,
      'realPlayerId': fcId(remote['id']),
      'name': name,
      'positionId': fcPositionId(remote['positions']),
      'overall': overall,
      'potential': fcInt(remote['potential']) ?? overall,
      'birthdate': birthDate?.millisecondsSinceEpoch,
      'firstSeasonAge': fcInt(remote['age']),
      'nationalityId': fcId(fcObject(remote['nationality'])['id']),
      'realFace': 1,
      'fromRealPlayer': 1,
      'foot': fcId(remote['preferredFoot']).toLowerCase() == 'left'
          ? 'Left'
          : 'Right',
    });
    return id;
  }

  Future<FcScoreLink> bind({
    required FcScoreLink link,
    required FcScoreRemoteCareer remote,
    required Season season,
    Person? newPerson,
    bool bringSquad = true,
    bool updateOveralls = true,
  }) async {
    final result = link.copy();
    final db = await sql.database;
    await db.transaction((txn) async {
      result.localLeagueId = await _entity(
        txn,
        'CustomLeague',
        result.localLeagueId,
        link.gameVersion,
      );
      result.localClubId = await _entity(
        txn,
        'CustomClub',
        result.localClubId,
        link.gameVersion,
        leagueId: result.localLeagueId,
      );
      result.teams[result.remoteClubId] = result.localClubId;
      final remoteLeague = fcId(remote.league['id']);
      if (remoteLeague.isNotEmpty) {
        result.leagues[remoteLeague] = result.localLeagueId;
      }
      if (newPerson != null) {
        await txn.insert('Persons', {
          ...newPerson.toMap(),
          'teamId': result.localClubId,
          'leagueId': result.localLeagueId,
        });
      }
      final persons = await txn.query(
        'Persons',
        where: 'id = ?',
        whereArgs: [link.personId],
      );
      if (persons.isEmpty ||
          fcVersion(persons.single['fifaVersion'] as String) !=
              link.gameVersion ||
          persons.single['category'] != remote.category.name) {
        throw const FcScoreException(
          'A carreira deve ser do mesmo FIFA e tipo do save.',
        );
      }
      final seasons = await txn.query(
        'Seasons',
        where: 'id = ?',
        whereArgs: [season.id],
      );
      if (seasons.isEmpty) {
        if (season.personId != link.personId ||
            !season.endDate.isAfter(season.startDate)) {
          throw const FcScoreException('Confira o período da temporada.');
        }
        await txn.insert('Seasons', season.toMap());
      } else if (seasons.single['personId'] != link.personId) {
        throw const FcScoreException('A temporada pertence a outra carreira.');
      }
      result.seasonId = season.id;
      await SqlService.ensureTransferReleaseSchema(txn);
      await SeasonRosterService.initialize(txn, season);
      for (final key in result.competitions.keys.toList()) {
        result.competitions[key] = await _entity(
          txn,
          'Tournament',
          result.competitions[key]!,
          link.gameVersion,
        );
      }
      if (remote.category == PersonCategory.manager && bringSquad) {
        final linkedPlayers = <String>{};
        final currentDate =
            DateTime.tryParse(fcId(remote.overview['currentDate'])) ??
            season.startDate;
        for (final player in remote.squad) {
          final remoteId = fcId(player['id']);
          final profile = fcPlayerWithChoice(player, result.players[remoteId]);
          final localId = await _player(
            txn,
            link.personId,
            player,
            result.players[remoteId],
          );
          result.players[remoteId] = localId;
          if (!linkedPlayers.add(localId)) {
            throw const FcScoreException(
              'Dois jogadores do elenco apontam para o mesmo cadastro. Revise os vínculos.',
            );
          }
          final roster = await txn.query(
            'TeamPlayer',
            where: 'personId = ? AND seasonId = ? AND playerId = ?',
            whereArgs: [link.personId, season.id, localId],
          );
          if (roster.isEmpty) {
            await txn.insert('TeamPlayer', {
              'id': _uuid(),
              'personId': link.personId,
              'seasonId': season.id,
              'playerId': localId,
              'overall': fcInt(profile['overall']),
              'shirtNumber': fcInt(player['jerseyNumber']),
              'isBench': 1,
              'wage': fcInt(fcObject(player['contract'])['wage']),
            });
          }
          if (updateOveralls && fcValidPlayerRating(profile['overall'])) {
            final date = currentDate.toIso8601String();
            final old = await txn.query(
              'Overall',
              where: 'personId = ? AND customPlayerId = ? AND date = ?',
              whereArgs: [link.personId, localId, date],
            );
            await txn.insert('Overall', {
              'id': old.firstOrNull?['id'] ?? _uuid(),
              'personId': link.personId,
              'customPlayerId': localId,
              'date': date,
              'createdAt': DateTime.now().toIso8601String(),
              'overall': fcInt(profile['overall']),
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      }
      await _saveLink(txn, result);
    });
    await GameCatalog.reloadCustomData();
    return result;
  }

  Future<Map<String, Object?>?> _existing(
    DatabaseExecutor db,
    Person person,
    FcScoreLink link,
    FcScoreMatch match,
  ) async {
    final table = person.category == PersonCategory.manager
        ? 'ManagerFixtures'
        : 'PlayerFixtures';
    final imports = await db.query(
      'FcScoreImport',
      where:
          'personId = ? AND (remoteKey = ?${match.reportId == null ? '' : ' OR reportId = ?'})',
      whereArgs: [
        person.id,
        match.remoteKey,
        if (match.reportId != null) match.reportId!,
      ],
    );
    for (final row in imports) {
      final fixture = await db.query(
        table,
        where: 'id = ? AND personId = ?',
        whereArgs: [row['fixtureId'], person.id],
      );
      if (fixture.isNotEmpty) {
        final performances = await db.query(
          'ManagerFixturePlayerPerformances',
          where: 'fixtureId = ?',
          whereArgs: [row['fixtureId']],
          limit: 1,
        );
        return {
          ...row,
          'manual':
              row['completedByUser'] == 1 ||
              (row['reportId'] == null && performances.isNotEmpty),
          'localFixture': fixture.first,
        };
      }
    }
    final opponentId = fcId(fcObject(match.opponent(link)['team'])['id']);
    Future<String?> existingChoice(
      String? choice,
      String table,
      String field,
    ) async {
      if (choice == null || !choice.startsWith('new:')) return choice;
      final rows = await db.query(
        table,
        where: '$field = ?',
        whereArgs: [choice.substring(4)],
      );
      return rows
              .where(
                (r) => fcId(
                  r[table == 'Tournament' ? 'fifaVersions' : 'fifaVersion'],
                ).split(',').contains(link.gameVersion),
              )
              .firstOrNull?['id']
          as String?;
    }

    final mapped = await existingChoice(
      link.teams[opponentId],
      'CustomClub',
      'label',
    );
    final competition = await existingChoice(
      link.competitions[match.competitionId],
      'Tournament',
      'name',
    );
    if (mapped == null || competition == null || match.date == null) {
      return null;
    }
    final fixtures = await db.query(
      table,
      where:
          'personId = ? AND substr(date,1,10) = ? '
          'AND playerTeamId = ? AND oppositeTeamId = ? AND tournamentId = ? AND location = ?',
      whereArgs: [
        person.id,
        match.date!.toIso8601String().substring(0, 10),
        link.localClubId,
        mapped,
        competition,
        match.homeId == link.remoteClubId ? 'home' : 'away',
      ],
    );
    return fixtures.isEmpty
        ? null
        : {
            'fixtureId': fixtures.first['id'],
            'manual': true,
            'localFixture': fixtures.first,
          };
  }

  Future<FcImportState> importState(
    Person person,
    FcScoreLink link,
    FcScoreMatch match,
  ) async {
    final old = await _existing(await sql.database, person, link, match);
    if (old == null) return FcImportState.available;
    return old['manual'] != true && old['reportId'] == null && match.detailed
        ? FcImportState.canComplete
        : FcImportState.alreadyImported;
  }

  void _validate(FcScoreLink link, FcScoreMatch match) {
    if (match.saveId != link.saveId) {
      throw const FcScoreException(
        'O relatório é de outro save. Selecione a carreira correta.',
      );
    }
    if (match.homeId != link.remoteClubId &&
        match.awayId != link.remoteClubId) {
      throw const FcScoreException('Este jogo não envolve o clube vinculado.');
    }
    if (match.homeId == match.awayId ||
        match.date == null ||
        match.competitionId.isEmpty ||
        match.homeGoals == null ||
        match.awayGoals == null ||
        match.homeGoals! < 0 ||
        match.awayGoals! < 0 ||
        match.homeGoals! >= 255 ||
        match.awayGoals! >= 255) {
      throw const FcScoreException(
        'Confira a data, a competição e o placar antes de importar.',
      );
    }
    if (!match.detailed && match.raw['played'] != true) {
      throw const FcScoreException('A partida ainda não foi realizada.');
    }
    if (match.detailed) {
      for (final side in [match.home, match.away]) {
        final seen = <String>{};
        for (final player in fcList(
          side['players'],
        ).where((p) => p['played'] == true || p['started'] == true)) {
          if ((fcInt(player['id']) ?? -1) < 0 ||
              !seen.add(fcId(player['id']))) {
            throw const FcScoreException(
              'O relatório tem jogadores sem identificação ou repetidos. Revise a exportação.',
            );
          }
        }
      }
      if ((fcInt(match.raw['exportVersion']) ?? 0) < 43 ||
          match.reportId!.isEmpty) {
        throw const FcScoreException(
          'Este relatório não é uma exportação de partida compatível.',
        );
      }
      final saved = fcObject(fcObject(match.raw['match'])['savedResult']);
      if (saved['played'] == true &&
          (fcInt(saved['home']) != match.homeGoals ||
              fcInt(saved['away']) != match.awayGoals)) {
        throw const FcScoreException(
          'O placar do relatório difere do save. Confira o arquivo ativo antes de importar.',
        );
      }
    }
  }

  Future<FcImportResult> importMatch({
    required Person person,
    required FcScoreLink link,
    required FcScoreMatch match,
    bool extraTime = false,
    String? formation,
    String? opponentFormation,
  }) async {
    if (person.id != link.personId ||
        fcVersion(person.fifaVersion) != link.gameVersion) {
      throw const FcScoreException('O vínculo não pertence a esta carreira.');
    }
    _validate(link, match);
    final resolved = link.copy();
    final db = await sql.database;
    final result = await db.transaction((txn) async {
      final old = await _existing(txn, person, resolved, match);
      if (old != null &&
          (old['manual'] == true ||
              old['reportId'] != null ||
              !match.detailed)) {
        return FcImportResult(
          old['fixtureId'] as String,
          FcImportState.alreadyImported,
        );
      }
      final seasons = await txn.query(
        'Seasons',
        where: 'id = ? AND personId = ?',
        whereArgs: [resolved.seasonId, person.id],
      );
      if (seasons.isEmpty) {
        throw const FcScoreException('Selecione uma temporada desta carreira.');
      }
      final season = Season.fromMap(seasons.single);
      final day = DateTime(
        match.date!.year,
        match.date!.month,
        match.date!.day,
      );
      if (day.isBefore(
            DateTime(
              season.startDate.year,
              season.startDate.month,
              season.startDate.day,
            ),
          ) ||
          day.isAfter(
            DateTime(
              season.endDate.year,
              season.endDate.month,
              season.endDate.day,
            ),
          )) {
        throw const FcScoreException(
          'A data do jogo está fora da temporada escolhida.',
        );
      }
      final opponent = match.opponent(resolved), own = match.own(resolved);
      final opponentRef = fcObject(opponent['team']),
          opponentId = fcId(opponentRef['id']);
      final opponentChoice = resolved.teams[opponentId];
      if (opponentChoice == null ||
          resolved.competitions[match.competitionId] == null) {
        throw const FcScoreException(
          'Vincule o adversário e a competição antes de importar.',
        );
      }
      resolved.teams[opponentId] = await _entity(
        txn,
        'CustomClub',
        opponentChoice,
        person.fifaVersion,
        leagueId: resolved.localLeagueId,
      );
      if (resolved.teams[opponentId] == resolved.localClubId) {
        throw const FcScoreException(
          'O adversário deve ser vinculado a outro clube.',
        );
      }
      resolved.competitions[match.competitionId] = await _entity(
        txn,
        'Tournament',
        resolved.competitions[match.competitionId]!,
        person.fifaVersion,
      );
      final fixtureId = old?['fixtureId'] as String? ?? _uuid();
      final now = DateTime.now().toIso8601String();
      final ownPlayers = fcList(own['players']);
      final oppositePlayers = fcList(opponent['players']);
      final ownIds = <String, String>{};
      if (person.category == PersonCategory.manager && match.detailed) {
        for (final player in ownPlayers.where(
          (p) =>
              p['started'] == true ||
              p['played'] == true ||
              (fcInt(p['id']) != null &&
                  fcInt(p['id'])! >= 0 &&
                  fcObject(p['profile'])['name'] != null),
        )) {
          final id = fcId(player['id']);
          if (id.isEmpty ||
              (fcInt(player['id']) ?? -1) < 0 ||
              ownIds.containsKey(id)) {
            throw const FcScoreException(
              'O relatório tem jogadores sem identificação ou repetidos. Revise a exportação.',
            );
          }
          final profile = {...fcObject(player['profile']), 'id': player['id']};
          final local = await _player(
            txn,
            person.id,
            profile,
            resolved.players[id],
          );
          if (ownIds.values.contains(local)) {
            throw const FcScoreException(
              'Dois jogadores foram vinculados ao mesmo cadastro. Revise os vínculos.',
            );
          }
          ownIds[id] = local;
          resolved.players[id] = local;
        }
      }
      final values = <String, Object?>{
        'id': fixtureId,
        'personId': person.id,
        'date': match.date!.toIso8601String(),
        'fifaVersion': person.fifaVersion,
        'playerTeamScore': fcInt(own['goals']),
        'oppositeTeamScore': fcInt(opponent['goals']),
        'playerTeamId': resolved.localClubId,
        'playerTeamLeagueId': resolved.localLeagueId,
        'oppositeTeamId': resolved.teams[opponentId],
        'tournamentId': resolved.competitions[match.competitionId],
        'seasonId': resolved.seasonId,
        'location': match.homeId == link.remoteClubId ? 'home' : 'away',
        'stage': [
          if (match.stage != null) match.stage,
          if (match.round != null) 'Rodada ${match.round}',
        ].join(' · '),
        'updatedAt': now,
        if (old == null) ...{
          'createdAt': now,
          'notes': 'Importado da API FC Score.',
        },
      };
      int? penalties(FcJson team) =>
          fcInt(team['penalties']) ??
          fcInt(fcObject(team['stats'])['shootoutGoals']);
      final ownPenalties = penalties(own), oppPenalties = penalties(opponent);
      if ((ownPenalties ?? 0) + (oppPenalties ?? 0) > 0) {
        values['playerTeamPenaltiesScore'] = ownPenalties;
        values['oppositeTeamPenaltiesScore'] = oppPenalties;
      }
      if (person.category == PersonCategory.manager) {
        final ownStats = fcObject(own['stats']),
            oppStats = fcObject(opponent['stats']);
        values.addAll({
          'extraTime': extraTime ? 1 : 0,
          'passAccuracy': _percentage(
            ownStats,
            'passAccuracyPctDerived',
            'passesCompleted',
            'passes',
          ),
          'playerTeamShoutsCount': fcInt(ownStats['shots']),
          'opponentTeamShotsCount': fcInt(oppStats['shots']),
        });
        if (match.detailed) {
          final opponentPlan = await _opponentCompletion(txn, {
            ...values,
            'id': fixtureId,
          }, oppositePlayers);
          final oppositeIds = {
            ...opponentPlan.ids,
            for (final p in opponentPlan.missing)
              fcId(p['id']): 'fc-opponent:${fcId(p['id'])}',
          };
          final ownPerfs = [
            for (final p in ownPlayers.where((p) => p['played'] == true))
              _performance(p, person.id, fixtureId, ownIds[fcId(p['id'])]!),
          ];
          final oppPerfs = [
            for (final p in oppositePlayers.where((p) => p['played'] == true))
              _performance(
                p,
                person.id,
                fixtureId,
                oppositeIds[fcId(p['id'])]!,
              ),
          ];
          fcApplySubstitutions(ownPlayers, ownPerfs, ownIds);
          fcApplySubstitutions(oppositePlayers, oppPerfs, oppositeIds);
          final ownFormation = await _ownPitchFormation(
            txn,
            {...values, 'id': fixtureId},
            ownPlayers,
            ownIds,
            formation,
          );
          for (final entry in ownFormation.players.entries) {
            final local = await txn.query(
              'CustomCreatedPlayer',
              where: 'id = ? AND personId = ?',
              whereArgs: [entry.key, person.id],
              limit: 1,
            );
            if (local.isNotEmpty) {
              entry.value['name'] = local.single['name'];
              entry.value['customAvatarFilePath'] =
                  local.single['customAvatarFilePath'];
              entry.value['realPlayerId'] =
                  local.single['realPlayerId'] ?? entry.value['realPlayerId'];
            }
          }
          values['matchLineup'] = ownFormation.encode();
          final opponentSnapshot = OpponentLineup(
            squad: _formation(
              oppositePlayers,
              oppositeIds,
              opponentFormation,
              known: opponentPlan.known,
              fallbackFormation: opponentPlan.rememberedFormation,
            ),
            performances: oppPerfs,
          ).resolved();
          values['opponentLineup'] = opponentSnapshot.encode();
          values['opponentGoalDetails'] = encodeOpponentGoals(
            opponentSnapshot.goals,
          );
          values['opponentStats'] = OpponentStats(
            passAccuracy: _percentage(
              oppStats,
              'passAccuracyPctDerived',
              'passesCompleted',
              'passes',
            ),
            yellowCards: fcInt(oppStats['yellowCardEvents']),
            redCards: fcInt(oppStats['redDismissals']),
            ownGoals: fcInt(oppStats['ownGoals']),
          ).encode();
          final motm = fcObject(match.raw['manOfTheMatch']);
          if (motm.isNotEmpty) {
            final ours =
                fcId(fcObject(motm['team'])['id']) == resolved.remoteClubId;
            values['isPotmFromMyTeam'] = ours ? 1 : 0;
            values['playerOfTheMatchId'] = ours
                ? ownIds[fcId(fcObject(motm['player'])['id'])]
                : fcName(fcObject(motm['player'])['name']);
          }
          for (final p in ownPerfs) {
            await txn.insert('ManagerFixturePlayerPerformances', p.toMap());
          }
        }
      } else {
        if (!match.detailed) {
          throw const FcScoreException(
            'Para importar na carreira de jogador, escolha um relatório com o desempenho individual.',
          );
        }
        final player = ownPlayers
            .where((p) => fcId(p['id']) == resolved.playerId)
            .firstOrNull;
        if (player == null || player['played'] != true) {
          throw const FcScoreException(
            'Selecione o seu jogador entre os que atuaram neste relatório.',
          );
        }
        final stats = fcObject(player['stats']);
        values.addAll({
          'rating': fcNumber(player['rating']),
          'goalsCount': fcInt(stats['goalsDerived']) ?? 0,
          'assistsCount': fcInt(stats['assists']) ?? 0,
          'savesCount': fcInt(stats['saves']) ?? 0,
          'yellowCards': fcInt(stats['yellowCardEvents']) ?? 0,
          'redCards': fcInt(stats['redDismissals']) ?? 0,
          'minsPlayed': fcInt(stats['minutesPlayed']),
          'goalsFromPenalty': fcInt(stats['pkGoals']),
          'shotsOnTarget': fcInt(stats['shotsOnTarget']),
          'apiStats': jsonEncode(stats),
          'isInjured': 0,
          'isDisqualified': 0,
          'playerOfTheMatch': player['manOfTheMatch'] == true ? 1 : 0,
        });
      }
      final table = person.category == PersonCategory.manager
          ? 'ManagerFixtures'
          : 'PlayerFixtures';
      if (old == null) {
        await txn.insert(table, values);
      } else {
        await txn.update(
          table,
          values,
          where: 'id = ? AND personId = ?',
          whereArgs: [fixtureId, person.id],
        );
      }
      await txn.delete(
        'FcScoreImport',
        where: 'personId = ? AND fixtureId = ?',
        whereArgs: [person.id, fixtureId],
      );
      await txn.insert('FcScoreImport', {
        'personId': person.id,
        'remoteKey': match.remoteKey,
        'fixtureId': fixtureId,
        'saveId': link.saveId,
        'reportId': match.reportId,
        'rawJson': jsonEncode(match.raw),
        'createdAt': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _saveLink(txn, resolved);
      return FcImportResult(
        fixtureId,
        old == null ? FcImportState.available : FcImportState.canComplete,
      );
    });
    link.players.addAll(resolved.players);
    link.teams.addAll(resolved.teams);
    link.competitions.addAll(resolved.competitions);
    await GameCatalog.reloadCustomData();
    return result;
  }

  Future<Map<String, String>> linkedFixtures(Person person) async {
    final table = person.category == PersonCategory.manager
        ? 'ManagerFixtures'
        : 'PlayerFixtures';
    return {
      for (final row in await (await sql.database).rawQuery(
        'SELECT i.remoteKey, i.fixtureId FROM FcScoreImport i '
        'JOIN $table f ON f.id = i.fixtureId AND f.personId = i.personId '
        'WHERE i.personId = ?',
        [person.id],
      ))
        fcId(row['remoteKey']): fcId(row['fixtureId']),
    };
  }

  Future<void> completeFixture({
    required Person person,
    required FcScoreLink link,
    required FcScoreMatch match,
    required String fixtureId,
    String? formation,
    String? opponentFormation,
    bool createOpponentPlayers = false,
  }) async {
    if (person.id != link.personId ||
        fcVersion(person.fifaVersion) != link.gameVersion) {
      throw const FcScoreException('O vínculo não pertence a esta carreira.');
    }
    _validate(link, match);
    final manager = person.category == PersonCategory.manager;
    if (!manager && !match.detailed) {
      throw const FcScoreException(
        'Para completar na carreira de jogador, escolha um relatório com o desempenho individual.',
      );
    }
    final table = manager ? 'ManagerFixtures' : 'PlayerFixtures';
    final resolved = link.copy();
    final db = await sql.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        table,
        where: 'id = ? AND personId = ?',
        whereArgs: [fixtureId, person.id],
      );
      if (rows.isEmpty) {
        throw const FcScoreException('Esta partida foi removida da carreira.');
      }
      final fixture = rows.single;
      for (final row in await txn.query(
        'FcScoreImport',
        where:
            'personId = ? AND fixtureId != ? AND (remoteKey = ?${match.reportId == null ? '' : ' OR reportId = ?'})',
        whereArgs: [
          person.id,
          fixtureId,
          match.remoteKey,
          if (match.reportId != null) match.reportId!,
        ],
      )) {
        final other = await txn.query(
          table,
          columns: ['id'],
          where: 'id = ? AND personId = ?',
          whereArgs: [row['fixtureId'], person.id],
        );
        if (other.isNotEmpty) {
          throw const FcScoreException(
            'Esta partida da API já está vinculada a outro jogo da carreira.',
          );
        }
      }
      final own = match.own(resolved), opponent = match.opponent(resolved);
      final ownPlayers = fcList(own['players']);
      final oppositePlayers = fcList(opponent['players']);
      final values = <String, Object?>{};
      void fill(String column, Object? value) {
        final current = fixture[column];
        if (value == null || (value is String && value.isEmpty)) return;
        if (current == null || (current is String && current.isEmpty)) {
          values[column] = value;
        }
      }

      fill(
        'stage',
        [
          if (match.stage != null) match.stage,
          if (match.round != null) 'Rodada ${match.round}',
        ].join(' · '),
      );
      int? penalties(FcJson team) =>
          fcInt(team['penalties']) ??
          fcInt(fcObject(team['stats'])['shootoutGoals']);
      final ownPenalties = penalties(own), oppPenalties = penalties(opponent);
      if ((ownPenalties ?? 0) + (oppPenalties ?? 0) > 0 &&
          fixture['playerTeamPenaltiesScore'] == null &&
          fixture['oppositeTeamPenaltiesScore'] == null) {
        values['playerTeamPenaltiesScore'] = ownPenalties;
        values['oppositeTeamPenaltiesScore'] = oppPenalties;
      }
      final score = fcInt(fixture['playerTeamScore']);
      final performances = [
        for (final row in await txn.query(
          'ManagerFixturePlayerPerformances',
          where: 'fixtureId = ?',
          whereArgs: [fixtureId],
        ))
          ManagerFixturePlayerPerformance.fromMap(row),
      ];
      if (manager) {
        final ownStats = fcObject(own['stats']),
            oppStats = fcObject(opponent['stats']);
        fill(
          'passAccuracy',
          _percentage(
            ownStats,
            'passAccuracyPctDerived',
            'passesCompleted',
            'passes',
          ),
        );
        fill('playerTeamShoutsCount', fcInt(ownStats['shots']));
        fill('opponentTeamShotsCount', fcInt(oppStats['shots']));
        if (match.detailed) {
          final lineup = FixtureFormation.decode(fixture['matchLineup']);
          final ownIds = <String, String>{};
          for (final player in ownPlayers.where(
            (p) =>
                p['played'] == true ||
                (lineup == null &&
                    (p['started'] == true ||
                        ((fcInt(p['id']) ?? -1) >= 0 &&
                            fcObject(p['profile'])['name'] != null))),
          )) {
            final id = fcId(player['id']);
            if (id.isEmpty ||
                (fcInt(player['id']) ?? -1) < 0 ||
                ownIds.containsKey(id)) {
              throw const FcScoreException(
                'O relatório tem jogadores sem identificação ou repetidos. Revise a exportação.',
              );
            }
            final local = await _player(txn, person.id, {
              ...fcObject(player['profile']),
              'id': player['id'],
            }, resolved.players[id]);
            if (ownIds.values.contains(local)) {
              throw const FcScoreException(
                'Dois jogadores foram vinculados ao mesmo cadastro. Revise os vínculos.',
              );
            }
            ownIds[id] = local;
            resolved.players[id] = local;
          }
          final incomingOwn = [
            for (final p in ownPlayers.where((p) => p['played'] == true))
              _performance(p, person.id, fixtureId, ownIds[fcId(p['id'])]!),
          ];
          fcApplySubstitutions(ownPlayers, incomingOwn, ownIds);
          final typed = {for (final p in performances) p.playerInstanceId: p};
          final recordedOpponentGoals = decodeOpponentGoals(
            fixture['opponentGoalDetails'],
          );
          final knownOpponentGoals =
              OpponentLineup.decode(fixture['opponentLineup'])
                  ?.mergeGoals(recordedOpponentGoals) ??
              recordedOpponentGoals;
          var goalRoom = score == null
              ? 1 << 20
              : score -
                    knownOpponentGoals.where((g) => g.isOwnGoal).length -
                    performances.fold<int>(
                      0,
                      (n, p) => n + p.goalDetails.length,
                    );
          var assistRoom = score == null
              ? 1 << 20
              : score -
                    performances.fold<int>(
                      0,
                      (n, p) => n + p.assistDetails.length,
                    );
          for (final p in ownPlayers.where((p) => p['played'] == true)) {
            final local = ownIds[fcId(p['id'])]!;
            final user =
                typed[local] ??
                ManagerFixturePlayerPerformance(
                  personId: person.id,
                  fixtureId: fixtureId,
                  playerInstanceId: local,
                );
            final merged = fcCompletePerformance(
              user,
              incomingOwn.firstWhere((p) => p.playerInstanceId == local),
              goalRoom: goalRoom,
              assistRoom: assistRoom,
            );
            goalRoom -= merged.goalDetails.length - user.goalDetails.length;
            assistRoom -=
                merged.assistDetails.length - user.assistDetails.length;
            await txn.insert(
              'ManagerFixturePlayerPerformances',
              merged.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          if (lineup == null) {
            final ownFormation = await _ownPitchFormation(
              txn,
              fixture,
              ownPlayers,
              ownIds,
              formation,
            );
            for (final entry in ownFormation.players.entries) {
              final local = await txn.query(
                'CustomCreatedPlayer',
                where: 'id = ? AND personId = ?',
                whereArgs: [entry.key, person.id],
                limit: 1,
              );
              if (local.isNotEmpty) {
                entry.value['name'] = local.single['name'];
                entry.value['customAvatarFilePath'] =
                    local.single['customAvatarFilePath'];
                entry.value['realPlayerId'] =
                    local.single['realPlayerId'] ?? entry.value['realPlayerId'];
              }
            }
            values['matchLineup'] = ownFormation.encode();
          }
          final opponentPlan = await _opponentCompletion(
            txn,
            fixture,
            oppositePlayers,
          );
          final completedOpponent = _mergeOpponentCompletion(
            opponentPlan,
            oppositePlayers,
            fixture,
            opponentFormation,
            createPlayers: createOpponentPlayers,
            ownPerformances: [
              for (final row in await txn.query(
                'ManagerFixturePlayerPerformances',
                where: 'personId = ? AND fixtureId = ?',
                whereArgs: [person.id, fixtureId],
              ))
                ManagerFixturePlayerPerformance.fromMap(row),
            ],
          );
          if (completedOpponent.hasNames) {
            values['opponentLineup'] = completedOpponent.encode();
            final recorded = decodeOpponentGoals(
              fixture['opponentGoalDetails'],
            );
            final mergedGoals = completedOpponent.mergeGoals(recorded);
            if (mergedGoals.isNotEmpty) {
              values['opponentGoalDetails'] = encodeOpponentGoals(mergedGoals);
            }
          }
          final typedStats = OpponentStats.decode(fixture['opponentStats']);
          final stats = OpponentStats(
            passAccuracy:
                typedStats.passAccuracy ??
                _percentage(
                  oppStats,
                  'passAccuracyPctDerived',
                  'passesCompleted',
                  'passes',
                ),
            yellowCards:
                typedStats.yellowCards ?? fcInt(oppStats['yellowCardEvents']),
            redCards: typedStats.redCards ?? fcInt(oppStats['redDismissals']),
            ownGoals: typedStats.ownGoals ?? fcInt(oppStats['ownGoals']),
            missedPenalties: typedStats.missedPenalties,
            injuries: typedStats.injuries,
            position: typedStats.position,
          );
          if (stats.encode() != typedStats.encode()) {
            values['opponentStats'] = stats.encode();
          }
          final motm = fcObject(match.raw['manOfTheMatch']);
          if (motm.isNotEmpty && fixture['playerOfTheMatchId'] == null) {
            final ours =
                fcId(fcObject(motm['team'])['id']) == resolved.remoteClubId;
            final id = ours
                ? ownIds[fcId(fcObject(motm['player'])['id'])]
                : fcName(fcObject(motm['player'])['name']);
            if (id != null) {
              values['isPotmFromMyTeam'] = ours ? 1 : 0;
              values['playerOfTheMatchId'] = id;
            }
          }
        }
      } else {
        final player = ownPlayers
            .where((p) => fcId(p['id']) == resolved.playerId)
            .firstOrNull;
        if (player == null || player['played'] != true) {
          throw const FcScoreException(
            'Selecione o seu jogador entre os que atuaram neste relatório.',
          );
        }
        final user = performances.firstOrNull ?? _typedCounters(fixture);
        final merged = fcCompletePerformance(
          user,
          _performance(player, person.id, fixtureId, user.playerInstanceId),
          goalRoom: score ?? 1 << 20,
          assistRoom: score ?? 1 << 20,
        );
        await txn.insert(
          'ManagerFixturePlayerPerformances',
          merged.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        values.addAll({
          'rating': merged.avgRating,
          'apiStats': jsonEncode(merged.apiStats),
          'goalsCount': merged.goalsCount ?? 0,
          'assistsCount': merged.assistsCount ?? 0,
          'savesCount': merged.saves ?? 0,
          'yellowCards': merged.yellowCards ?? 0,
          'redCards': merged.redCards ?? 0,
          'goalsFromPenalty': merged.goalDetails
              .where((goal) => goal.isPenalty)
              .length,
        });
        final stats = fcObject(player['stats']);
        fill('minsPlayed', fcInt(stats['minutesPlayed']));
        fill('shotsOnTarget', fcInt(stats['shotsOnTarget']));
        fill('playerOfTheMatch', player['manOfTheMatch'] == true ? 1 : 0);
      }
      values['updatedAt'] = DateTime.now().toIso8601String();
      await txn.update(
        table,
        values,
        where: 'id = ? AND personId = ?',
        whereArgs: [fixtureId, person.id],
      );
      await txn.delete(
        'FcScoreImport',
        where: 'personId = ? AND fixtureId = ?',
        whereArgs: [person.id, fixtureId],
      );
      await txn.insert('FcScoreImport', {
        'personId': person.id,
        'remoteKey': match.remoteKey,
        'fixtureId': fixtureId,
        'saveId': link.saveId,
        'reportId': match.reportId,
        'rawJson': jsonEncode(match.raw),
        'createdAt': DateTime.now().toIso8601String(),
        'completedByUser': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _saveLink(txn, resolved);
    });
    link.players.addAll(resolved.players);
    await GameCatalog.reloadCustomData();
  }
}

ManagerFixturePlayerPerformance _typedCounters(Map<String, Object?> fixture) {
  final performance = ManagerFixturePlayerPerformance.fromMap({
    'id': _uuid(),
    'personId': fixture['personId'],
    'fixtureId': fixture['id'],
    'playerInstanceId': fixture['personId'],
    'goalsCount': fixture['goalsCount'],
    'assistsCount': fixture['assistsCount'],
    'yellowCards': fixture['yellowCards'],
    'redCards': fixture['redCards'],
    'shotsCount': fixture['shotsOnTarget'],
    'avgRating': fixture['rating'],
    'saves': fixture['savesCount'],
  });
  for (final goal in performance.goalDetails.take(
    fcInt(fixture['goalsFromPenalty']) ?? 0,
  )) {
    goal.type = [GoalType.penalty];
  }
  return performance;
}

double? _percentage(
  FcJson stats,
  String derived,
  String numerator,
  String denominator,
) {
  final given = fcNumber(stats[derived]);
  if (given != null) return given;
  final n = fcNumber(stats[numerator]), d = fcNumber(stats[denominator]);
  return n == null || d == null || d <= 0 ? null : n * 100 / d;
}

ManagerFixturePlayerPerformance _performance(
  FcJson player,
  String person,
  String fixture,
  String localId,
) {
  final stats = fcObject(player['stats']);
  final minutes = fcInt(stats['minutesPlayed']);
  if (minutes == null || minutes < 0 || minutes > 180) {
    throw const FcScoreException('O relatório contém minutos inválidos.');
  }
  int count(String key) {
    final value = fcInt(stats[key]) ?? 0;
    if (value < 0 || value > 200) {
      throw const FcScoreException(
        'O relatório contém estatísticas inválidas.',
      );
    }
    return value;
  }

  final goals = count('goalsDerived'),
      penalties = math.min(count('pkGoals'), goals);
  return ManagerFixturePlayerPerformance(
    personId: person,
    fixtureId: fixture,
    playerInstanceId: localId,
    recordedMinutes: minutes,
    recordedStarted: player['started'] == true,
    apiStats: {
      ...stats,
      if (stats['savingShotsOnTarget'] is num && stats['goalsConceded'] is num)
        'shotsOnTargetAgainst':
            (stats['savingShotsOnTarget'] as num) +
            (stats['goalsConceded'] as num),
    },
    goalsCount: fcInt(stats['goalsDerived']),
    assistsCount: fcInt(stats['assists']),
    yellowCards: fcInt(stats['yellowCardEvents']),
    redCards: fcInt(stats['redDismissals']),
    avgRating: fcNumber(player['rating']),
    shotsCount: fcInt(stats['shots']),
    shotAccuracy: _percentage(
      stats,
      'shotAccuracyPctDerived',
      'shotsOnTarget',
      'shots',
    )?.round(),
    passes: fcInt(stats['passes']),
    keyPasses: fcInt(stats['keyPasses']),
    passAccuracy: _percentage(
      stats,
      'passAccuracyPctDerived',
      'passesCompleted',
      'passes',
    )?.round(),
    tackles: fcInt(stats['tackles']),
    tacklesAccuracy: (fcNumber(stats['tackles']) ?? 0) <= 0
        ? null
        : (((fcNumber(stats['standTacklesWon']) ?? 0) +
                      (fcNumber(stats['slideTacklesWon']) ?? 0)) *
                  100 /
                  fcNumber(stats['tackles'])!)
              .round(),
    saves: fcInt(stats['saves']),
    penaltySaves: fcInt(stats['penaltySaves']),
    dribbles: fcInt(stats['dribbles']),
    dribblesAccuracy: _percentage(
      stats,
      'dribbleSuccessPctDerived',
      'dribblesCompleted',
      'dribbles',
    )?.round(),
    goalDetails: List.generate(
      goals,
      (i) =>
          PerformanceGoalDetails(type: i < penalties ? [GoalType.penalty] : []),
    ),
    assistDetails: List.generate(
      count('assists'),
      (_) => PerformanceAssistDetails(),
    ),
    yellowCardDetails: List.generate(
      count('yellowCardEvents'),
      (_) => PerformanceTimeDetails(),
    ),
    redCardDetails: List.generate(
      count('redDismissals'),
      (_) => PerformanceTimeDetails(),
    ),
    ownGoalDetails: List.generate(
      count('ownGoals'),
      (_) => PerformanceTimeDetails(),
    ),
  );
}

FixtureFormation _formation(
  List<FcJson> players,
  Map<String, String> ids,
  String? formation, {
  Map<String, Map<String, Object?>> known = const {},
  String? fallbackFormation,
}) {
  final included = players
      .where((p) => ids.containsKey(fcId(p['id'])))
      .toList();
  final data = <String, Map<String, Object?>>{};
  for (final p in included) {
    final id = ids[fcId(p['id'])]!, profile = fcObject(p['profile']);
    final saved = known[id] ?? {};
    final remoteName = fcName(profile['name']);
    data[id] = {
      ...saved,
      'id': id,
      'name': hasFootballIdentity(saved)
          ? saved['name']
          : hasFootballPlayerName(remoteName)
          ? remoteName
          : '',
      'apiPlayerId': fcId(p['id']),
      'realPlayerId': saved['realPlayerId'] ?? fcId(p['id']),
      'shirtNumber': saved['shirtNumber'] ?? p['jerseyNumber'],
      'positionId': fcInt(p['lineupSlot']) == 0
          ? '0'
          : saved['positionId'] ?? fcKnownPositionId(profile['positions']),
      'apiStarted': p['started'],
      'apiLineupSlot': p['lineupSlot'],
    };
  }
  final starting = included
      .where((p) => p['started'] == true)
      .map((p) => ids[fcId(p['id'])]!)
      .toList();
  final resolved =
      formation ??
      inferFootballFormation(
        starting.map((id) => data[id]?['positionId'] as String?),
      ) ??
      fallbackFormation ??
      '4-3-3';
  return FixtureFormation(
    formation: resolved,
    players: data,
    starters: {},
    bench: included
        .where((p) => p['started'] != true)
        .map((p) => ids[fcId(p['id'])]!)
        .toList(),
    layoutSource: formation == null ? 'api' : 'manual',
  ).withFormation(
    resolved,
    starting: starting,
    source: formation == null ? 'api' : 'manual',
  );
}

String fcInferFormation(List<FcJson> players) =>
    inferFootballFormation(
      players
          .where((p) => p['started'] == true)
          .map(
            (p) => fcInt(p['lineupSlot']) == 0
                ? '0'
                : fcKnownPositionId(fcObject(p['profile'])['positions']),
          ),
    ) ??
    '4-3-3';
