import 'dart:convert';

import '../models/Person.dart';
import '../utils/FootballFormations.dart';
import 'FcScoreApi.dart';
import 'FcScoreUpdateOptions.dart';

const fcPositions = [
  'GK',
  'SW',
  'RWB',
  'RB',
  'RCB',
  'CB',
  'LCB',
  'LB',
  'LWB',
  'RDM',
  'CDM',
  'LDM',
  'RM',
  'RCM',
  'CM',
  'LCM',
  'LM',
  'RAM',
  'CAM',
  'LAM',
  'RF',
  'CF',
  'LF',
  'RW',
  'RS',
  'ST',
  'LS',
  'LW',
  'SUB',
  'RES',
];
String fcPositionId(Object? positions) => fcKnownPositionId(positions) ?? '25';

String? fcKnownPositionId(Object? positions) {
  final code = positions is List ? positions.firstOrNull : positions;
  final index = fcPositions.indexOf('$code');
  return index >= 0 && index < 28 ? canonicalPositionId('$index') : null;
}

String fcNormalize(String value) {
  var text = value.toLowerCase().trim();
  const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const to = 'aaaaaeeeeiiiiooooouuuuc';
  for (var i = 0; i < from.length; i++) {
    text = text.replaceAll(from[i], to[i]);
  }
  return text.replaceAll(RegExp('[^a-z0-9]'), '');
}

String fcVersion(String value) => value.replaceAll(' ', '').toUpperCase();
String fcDate(Object? value) =>
    DateTime.tryParse(fcId(value))?.toIso8601String().substring(0, 10) ??
    'Data não informada';
String fcPlayerName(FcJson player) =>
    fcName(player['name'], 'Jogador ${fcId(player['id'])}');

class FcScoreLink {
  FcScoreLink({
    required this.personId,
    required this.saveId,
    required this.saveName,
    required this.gameVersion,
    required this.remoteClubId,
    required this.localClubId,
    required this.localLeagueId,
    required this.seasonId,
    this.playerId,
    this.connectionAddress,
    Map<String, String>? players,
    Map<String, String>? teams,
    Map<String, String>? competitions,
    Map<String, String>? leagues,
    Map<String, FcWorldSyncState>? worldSync,
    this.updateOptions,
  }) : players = players ?? {},
       teams = teams ?? {},
       competitions = competitions ?? {},
       leagues = leagues ?? {},
       worldSync = worldSync ?? {};
  final String personId, saveId, saveName, gameVersion, remoteClubId;
  String localClubId, localLeagueId, seasonId;
  String? playerId;
  String? connectionAddress;
  FcScoreUpdateOptions? updateOptions;
  final Map<String, String> players, teams, competitions, leagues;
  final Map<String, FcWorldSyncState> worldSync;
  bool belongsTo(FcScoreRemoteCareer remote, Person person) =>
      personId == person.id &&
      gameVersion == remote.gameVersion &&
      gameVersion == fcVersion(person.fifaVersion) &&
      remoteClubId == fcId(remote.club['id']) &&
      person.category == remote.category;

  FcScoreLink withSavedMappings(FcScoreLink saved) {
    if (personId != saved.personId ||
        gameVersion != saved.gameVersion ||
        remoteClubId != saved.remoteClubId ||
        localClubId != saved.localClubId) {
      return copy();
    }
    Map<String, String> merged(
      Map<String, String> current,
      Map<String, String> previous, {
      bool player = false,
    }) => {
      ...previous,
      ...current,
      for (final e in previous.entries)
        if (current[e.key] == null ||
            current[e.key] == 'new' ||
            (!player && current[e.key]!.startsWith('new:')))
          e.key: e.value,
    };
    return FcScoreLink.fromMap({
      ...toMap(),
      'connectionAddress': connectionAddress ?? saved.connectionAddress,
      'updateOptions': saved.updateOptions?.toMap() ?? updateOptions?.toMap(),
      'players': merged(players, saved.players, player: true),
      'teams': merged(teams, saved.teams),
      'competitions': merged(competitions, saved.competitions),
      'leagues': merged(leagues, saved.leagues),
      'worldSync': {
        ...worldSync.map((k, v) => MapEntry(k, v.toMap())),
        ...saved.worldSync.map((k, v) => MapEntry(k, v.toMap())),
      },
    });
  }

  FcScoreLink copy() => FcScoreLink.fromMap(toMap());
  FcJson toMap() => {
    'personId': personId,
    'saveId': saveId,
    'saveName': saveName,
    'gameVersion': gameVersion,
    'remoteClubId': remoteClubId,
    'localClubId': localClubId,
    'localLeagueId': localLeagueId,
    'seasonId': seasonId,
    'playerId': playerId,
    'connectionAddress': connectionAddress,
    'updateOptions': updateOptions?.toMap(),
    'players': players,
    'teams': teams,
    'competitions': competitions,
    'leagues': leagues,
    'worldSync': worldSync.map((key, value) => MapEntry(key, value.toMap())),
  };
  factory FcScoreLink.fromMap(FcJson map) {
    Map<String, String> ids(String key) =>
        fcObject(map[key]).map((k, v) => MapEntry(k, fcId(v)));
    return FcScoreLink(
      personId: fcId(map['personId']),
      saveId: fcId(map['saveId']),
      saveName: fcId(map['saveName']),
      gameVersion: fcId(map['gameVersion']),
      remoteClubId: fcId(map['remoteClubId']),
      localClubId: fcId(map['localClubId']),
      localLeagueId: fcId(map['localLeagueId']),
      seasonId: fcId(map['seasonId']),
      playerId: map['playerId'] as String?,
      connectionAddress: map['connectionAddress'] as String?,
      updateOptions: map['updateOptions'] is Map
          ? FcScoreUpdateOptions.fromMap(fcObject(map['updateOptions']))
          : null,
      players: ids('players'),
      teams: ids('teams'),
      competitions: ids('competitions'),
      leagues: ids('leagues'),
      worldSync: fcObject(map['worldSync']).map(
        (key, value) =>
            MapEntry(key, FcWorldSyncState.fromMap(fcObject(value))),
      ),
    );
  }
  factory FcScoreLink.fromRow(Map<String, Object?> row) =>
      FcScoreLink.fromMap(fcObject(jsonDecode(row['mappingJson'] as String)));
}

class FcWorldSyncState {
  FcWorldSyncState({
    required this.competitionIds,
    Set<String>? ignoredMatchKeys,
    this.preserveOwnPlayers = true,
    this.bringOwnSquad = false,
    this.updateOveralls = true,
    this.importedAt,
  }) : ignoredMatchKeys = ignoredMatchKeys ?? {};
  final Set<String> competitionIds, ignoredMatchKeys;
  final bool preserveOwnPlayers, bringOwnSquad, updateOveralls;
  final String? importedAt;
  FcJson toMap() => {
    'competitionIds': competitionIds.toList(),
    'ignoredMatchKeys': ignoredMatchKeys.toList(),
    'preserveOwnPlayers': preserveOwnPlayers,
    'bringOwnSquad': bringOwnSquad,
    'updateOveralls': updateOveralls,
    'importedAt': importedAt,
  };
  factory FcWorldSyncState.fromMap(FcJson map) => FcWorldSyncState(
    competitionIds:
        (map['competitionIds'] is List
                ? map['competitionIds'] as List
                : const [])
            .map(fcId)
            .toSet(),
    ignoredMatchKeys:
        (map['ignoredMatchKeys'] is List
                ? map['ignoredMatchKeys'] as List
                : const [])
            .map(fcId)
            .toSet(),
    preserveOwnPlayers: map['preserveOwnPlayers'] != false,
    bringOwnSquad: map['bringOwnSquad'] == true,
    updateOveralls: map['updateOveralls'] != false,
    importedAt: map['importedAt'] as String?,
  );
}

class FcScoreRemoteCareer {
  FcScoreRemoteCareer({
    required this.overview,
    required this.squad,
    required this.competitions,
    required this.gameVersion,
  });
  final FcJson overview;
  final List<FcJson> squad, competitions;
  final String gameVersion;
  String get saveId => fcId(fcObject(overview['save'])['id']);
  String get saveName =>
      fcName(fcObject(overview['save'])['inGameName'], saveId);
  FcJson get club => fcObject(overview['club']);
  FcJson get league => fcObject(overview['league']);
  PersonCategory get category =>
      fcObject(overview['save'])['careerType'] == 'player'
      ? PersonCategory.player
      : PersonCategory.manager;
  static Future<FcScoreRemoteCareer> load(
    FcScoreApi api,
    String saveId,
    String version,
  ) async {
    final overview = await api.object(api.careerPath(saveId));
    final squad = await api.object(api.careerPath(saveId, 'squad'));
    final progress = await api.list(api.careerPath(saveId, 'competitions'));
    final byId = <String, FcJson>{};
    for (final row in progress) {
      final competition = fcObject(row['competition']);
      if (fcId(competition['id']).isNotEmpty) {
        byId[fcId(competition['id'])] = competition;
      }
    }
    for (final key in ['lastMatch', 'nextMatch']) {
      final c = fcObject(fcObject(overview[key])['competition']);
      if (fcId(c['id']).isNotEmpty) byId[fcId(c['id'])] = c;
    }
    return FcScoreRemoteCareer(
      overview: overview,
      squad: fcList(squad['players']),
      competitions: byId.values.toList(),
      gameVersion: fcVersion(version),
    );
  }
}

class FcScoreMatch {
  FcScoreMatch({
    required this.raw,
    required this.saveId,
    required this.reportId,
    required this.fixtureId,
    required this.date,
    required this.time,
    required this.competition,
    required this.home,
    required this.away,
    required this.stage,
    required this.round,
    required this.warnings,
  });
  final FcJson raw, competition, home, away;
  final String saveId, fixtureId, time;
  final String? reportId, stage;
  final int? round;
  DateTime? date;
  final List<String> warnings;
  String get homeId => fcId(fcObject(home['team'])['id']);
  String get awayId => fcId(fcObject(away['team'])['id']);
  String get competitionId => fcId(competition['id']);
  int? get homeGoals => fcInt(home['goals']);
  int? get awayGoals => fcInt(away['goals']);
  bool get detailed => reportId != null;
  String get remoteKey => fixtureId.isNotEmpty
      ? 'fixture:${date?.toIso8601String().substring(0, 10)}:$competitionId:$fixtureId:$homeId:$awayId'
      : 'report:$reportId';
  factory FcScoreMatch.fromFixture(FcJson fixture, String saveId) =>
      FcScoreMatch(
        raw: fixture,
        saveId: saveId,
        reportId: null,
        fixtureId: fcId(fixture['id']),
        date: DateTime.tryParse(fcId(fixture['date'])),
        time: fcId(fixture['time']),
        competition: fcObject(fixture['competition']),
        home: fcObject(fixture['home']),
        away: fcObject(fixture['away']),
        stage: fixture['stage'] as String?,
        round: fcInt(fixture['round']),
        warnings: [],
      );
  factory FcScoreMatch.fromReport(FcJson report) {
    final match = fcObject(report['match']);
    return FcScoreMatch(
      raw: report,
      saveId: fcId(fcObject(report['activeSave'])['id']),
      reportId: fcId(report['id']),
      fixtureId: fcId(match['fixtureId']),
      date: DateTime.tryParse(fcId(match['date'])),
      time: fcId(match['time']),
      competition: fcObject(match['competition']),
      home: fcObject(report['home']),
      away: fcObject(report['away']),
      stage: match['stage'] as String?,
      round: fcInt(match['round']),
      warnings: (report['warnings'] as List? ?? []).map((v) => '$v').toList(),
    );
  }
  FcJson own(FcScoreLink link) => homeId == link.remoteClubId ? home : away;
  FcJson opponent(FcScoreLink link) =>
      homeId == link.remoteClubId ? away : home;
}
