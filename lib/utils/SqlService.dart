import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'package:easy_localization/easy_localization.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/ManagerFixturePlayerPerformance.dart';
import '../models/Person.dart';
import '../models/ManagerProfile.dart';
import '../models/PressConference.dart';
import '../models/Season.dart';
import '../models/TeamTransferItem.dart';
import '../models/Tournament.dart';
import '../models/TournamentResult.dart';
import 'GamePlayers.dart';
import 'GameCatalog.dart';
import 'compatibleSchema.dart';
import 'FixtureTablePosition.dart';
import 'SeasonRosterService.dart';
import 'SquadLineup.dart';
import 'CompetitionTrophies.dart';
import '../ManagerCareer/OtherPlayers/WorldPlayers.dart';
import 'PlayerValueHistory.dart';
import 'BackgroundData.dart';
import '../models/FixtureFormation.dart';
import '../models/OpponentLineup.dart';
import '../models/Trophy.dart';
import '../Twitter/TwitterSchema.dart';
import 'databaseUtils.dart' show CustomImageFiles;
import '../FcScore/FcScoreSchema.dart';

class SqlService {
  SqlService._();
  SqlService.withDatabase(Database database) : _database = database;
  static final SqlService instance = SqlService._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dbPath = path.join(await getDatabasesPath(), 'mc_ea_rebuild.db');
    _database = await openCareerDatabase(dbPath);
    return _database!;
  }

  static Future<Database> openCareerDatabase(String dbPath) async {
    return openDatabase(
      dbPath,
      version: 46,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE Settings(activePersonId TEXT)');
        await db.execute(
          '''CREATE TABLE Persons(
        id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL,
        fifaVersion TEXT NOT NULL, positionId TEXT, leagueId TEXT NOT NULL,
        teamId TEXT NOT NULL, nationalityId TEXT NOT NULL,
        nationalCoachingTeamId TEXT, realPlayerId TEXT, createdAt TEXT,
        updatedAt TEXT, currency TEXT, avatarPathName TEXT, birthdate INTEGER,
        foot TEXT, height INTEGER, weight INTEGER,
        promotedYoungPlayersCount INTEGER, achievementsInitialized INTEGER, managerProfile TEXT)''',
        );
        await db.execute('''CREATE TABLE Seasons(
        id TEXT PRIMARY KEY, personId TEXT NOT NULL, startDate TEXT NOT NULL,
        endDate TEXT NOT NULL, createdAt TEXT)''');
        await _createMatchTables(db);
        await _createHistoryTables(db);
        await _createTrophiesTable(db);
        await _createTeamTables(db);
        await _createAcademyAndInjuryTables(db);
        await _createManagerPerformanceTable(db);
        await _createCustomConfigurationTables(db);
        await ensureCompatibleSchema(db);
        await ensureSeasonClosureSchema(db);
        await createTwitterSchema(db);
        await ensureTransferReleaseSchema(db);
        await _ensureOpponentStatsSchema(db);
        await _ensurePressConferenceSchema(db);
        await _ensureTournamentFormatSchema(db);
        await ensureFixtureFormationSchema(db);
        await ensureOpponentLineupSchema(db);
        await ensureTransferPreviousClubStatsSchema(db);
        await ensureSharedPlayerSchema(db);
        await SeasonRosterService.ensureSchema(db);
        await SquadLineup.ensureSchema(db);
        await CompetitionTrophies.ensureSchema(db);
        await WorldPlayers.ensureSchema(db);
        await db.insert('Settings', {'activePersonId': null});
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await _createMatchTables(db);
        if (oldVersion < 3) await _createHistoryTables(db);
        if (oldVersion < 4) await _createTrophiesTable(db);
        if (oldVersion < 5) await _createTeamTables(db);
        if (oldVersion < 6) await _createAcademyAndInjuryTables(db);
        if (oldVersion < 7) await _createManagerPerformanceTable(db);
        if (oldVersion < 8) await _createCustomConfigurationTables(db);
        if (oldVersion < 9) {
          await ensureCompatibleSchema(db);
          await _migratePlayerReferences(db);
        }
        if (oldVersion < 16) await ensureTransferReleaseSchema(db);
        if (oldVersion < 19) await createTwitterSchema(db);
        if (oldVersion < 20) await _ensureOpponentStatsSchema(db);
        if (oldVersion < 21) await createTwitterSchema(db);
        if (oldVersion < 22) await _ensurePressConferenceSchema(db);
        if (oldVersion < 23) await _ensureTournamentFormatSchema(db);
        if (oldVersion < 24) await ensureManagerProfileSchema(db);
        if (oldVersion < 25) await ensureSeasonClosureSchema(db);
        if (oldVersion < 26) await createTwitterSchema(db);
        if (oldVersion < 27) await createTwitterSchema(db);
        if (oldVersion < 28) await ensureFixtureFormationSchema(db);
        if (oldVersion < 29) await ensureOpponentLineupSchema(db);
        if (oldVersion < 30) await ensureRosterDepartureSchema(db);
        if (oldVersion < 31) await ensureTransferPreviousClubStatsSchema(db);
        if (oldVersion < 32) {
          await ensureSharedPlayerSchema(db);
          await seedSharedPlayers(db);
        }
        if (oldVersion < 33) await ensureFcScoreSchema(db);
        if (oldVersion < 34) await ensureFcScoreSchema(db);
        if (oldVersion < 35) await ensureFcScoreSchema(db);
        if (oldVersion < 36) await createTwitterSchema(db);
        if (oldVersion < 37) await ensureFixtureCaptaincySchema(db);
        if (oldVersion < 38) await ensurePerformanceStatsSchema(db);
        if (oldVersion < 39) await createTwitterSchema(db);
        if (oldVersion < 40) await SeasonRosterService.ensureSchema(db);
        if (oldVersion < 41) {
          await SeasonRosterService.ensureSchema(db);
          await SeasonRosterService.repairPendingValues(db);
        }
        if (oldVersion < 42) await ensureRosterLookupIndexes(db);
        if (oldVersion < 43) await SquadLineup.ensureSchema(db);
        if (oldVersion < 44) await CompetitionTrophies.ensureSchema(db);
        if (oldVersion < 46) await WorldPlayers.ensureSchema(db);
      },
      onOpen: ensureTwitterContextSchema,
    );
  }

  static Future<void> ensureFixtureCaptaincySchema(DatabaseExecutor db) async {
    for (final table in ['ManagerFixtures', 'PlayerFixtures']) {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      if (columns.isNotEmpty && !columns.any((r) => r['name'] == 'captaincy')) {
        await db.execute('ALTER TABLE $table ADD COLUMN captaincy TEXT');
      }
    }
  }

  static Future<void> ensurePerformanceStatsSchema(DatabaseExecutor db) async {
    for (final table in [
      'ManagerFixturePlayerPerformances',
      'PlayerFixtures',
    ]) {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      if (columns.isNotEmpty && !columns.any((r) => r['name'] == 'apiStats')) {
        await db.execute('ALTER TABLE $table ADD COLUMN apiStats TEXT');
      }
    }
  }

  static Future<void> ensureFixtureFormationSchema(DatabaseExecutor db) async {
    for (final table in ['ManagerFixtures', 'PlayerFixtures']) {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      if (!columns.any((row) => row['name'] == 'matchLineup')) {
        await db.execute('ALTER TABLE $table ADD COLUMN matchLineup TEXT');
      }
    }
  }

  Future<void> saveFixtureFormation(
    PersonCategory category,
    String personId,
    String fixtureId,
    FixtureFormation formation,
  ) => updateFixtureFields(category, personId, fixtureId, {
    'matchLineup': formation.encode(),
  });

  static Future<void> ensureOpponentLineupSchema(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(ManagerFixtures)');
    if (!columns.any((row) => row['name'] == 'opponentLineup')) {
      await db.execute(
        'ALTER TABLE ManagerFixtures ADD COLUMN opponentLineup TEXT',
      );
    }
  }

  static Future<void> ensureTransferPreviousClubStatsSchema(
    DatabaseExecutor db,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info(TeamTransferItem)');
    if (!columns.any((row) => row['name'] == 'previousClubStats')) {
      await db.execute(
        'ALTER TABLE TeamTransferItem ADD COLUMN previousClubStats TEXT',
      );
    }
  }

  static Future<void> ensureRosterDepartureSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS TeamPlayerDeparture(
      id TEXT PRIMARY KEY, rosterId TEXT NOT NULL, personId TEXT NOT NULL,
      playerId TEXT NOT NULL, seasonId TEXT NOT NULL, teamId TEXT NOT NULL,
      leagueId TEXT, departureDate TEXT NOT NULL, transferId TEXT,
      rosterJson TEXT NOT NULL, transferJson TEXT)''');
    final columns = await db.rawQuery('PRAGMA table_info(TeamTransferItem)');
    if (!columns.any((row) => row['name'] == 'actualReleaseDate')) {
      await db.execute(
        'ALTER TABLE TeamTransferItem ADD COLUMN actualReleaseDate TEXT',
      );
    }
  }

  Future<OpponentLineup?> getRememberedOpponentLineup({
    required String personId,
    required String fifaVersion,
    required String teamId,
    String? leagueId,
    DateTime? beforeDate,
    String? excludeFixtureId,
  }) async {
    final rows = await (await database).query(
      'ManagerFixtures',
      columns: ['opponentLineup'],
      where:
          'personId = ? AND fifaVersion = ? AND oppositeTeamId = ? '
          "AND COALESCE(oppositeTeamLeagueId, '') = ? AND opponentLineup IS NOT NULL "
          '${excludeFixtureId == null ? '' : 'AND id != ? '}'
          '${beforeDate == null ? '' : 'AND julianday(date) <= julianday(?)'}',
      whereArgs: [
        personId,
        fifaVersion,
        teamId,
        leagueId ?? '',
        ?excludeFixtureId,
        if (beforeDate != null) beforeDate.toIso8601String(),
      ],
      orderBy: 'julianday(date) DESC, createdAt DESC, rowid DESC',
    );
    for (final row in rows) {
      final lineup = OpponentLineup.decode(row['opponentLineup']);
      if (lineup?.hasNames == true) return lineup!.forNewMatch();
    }
    return null;
  }

  static Future<void> ensureSeasonClosureSchema(DatabaseExecutor db) async {
    for (final (table, column) in [
      ('Seasons', 'closedAt'),
      ('Seasons', 'recapJson'),
      ('TournamentResultTable', 'closedAt'),
      ('TournamentResultTable', 'ownTeamId'),
      ('TournamentResultTableItem', 'knownStats'),
    ]) {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      if (!columns.any((row) => row['name'] == column)) {
        await db.execute('ALTER TABLE $table ADD COLUMN $column TEXT');
      }
    }
  }

  static Future<void> ensureTransferReleaseSchema(DatabaseExecutor db) async {
    final columns = (await db.rawQuery('PRAGMA table_info(TeamTransferItem)'))
        .map((row) => row['name'])
        .toSet();
    for (final entry in {
      'releaseDate': 'TEXT',
      'movementApplied': 'INTEGER NOT NULL DEFAULT 1',
      'keepInSquad': 'INTEGER NOT NULL DEFAULT 0',
    }.entries) {
      if (!columns.contains(entry.key)) {
        await db.execute(
          'ALTER TABLE TeamTransferItem ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }
  }

  static Future<void> _ensureOpponentStatsSchema(DatabaseExecutor db) async {
    final columns = (await db.rawQuery('PRAGMA table_info(ManagerFixtures)'))
        .map((row) => row['name'])
        .toSet();
    if (!columns.contains('opponentStats')) {
      await db.execute(
        'ALTER TABLE ManagerFixtures ADD COLUMN opponentStats TEXT',
      );
    }
  }

  static Future<void> _ensurePressConferenceSchema(DatabaseExecutor db) async {
    final columns = (await db.rawQuery('PRAGMA table_info(ManagerFixtures)'))
        .map((row) => row['name'])
        .toSet();
    if (!columns.contains('pressConference')) {
      await db.execute(
        'ALTER TABLE ManagerFixtures ADD COLUMN pressConference TEXT',
      );
    }
  }

  static Future<void> _ensureTournamentFormatSchema(DatabaseExecutor db) async {
    final columns = (await db.rawQuery('PRAGMA table_info(Tournament)'))
        .map((row) => row['name'])
        .toSet();
    if (!columns.contains('format')) {
      await db.execute('ALTER TABLE Tournament ADD COLUMN format TEXT');
    }
  }

  static Future<void> ensureManagerProfileSchema(DatabaseExecutor db) async {
    final columns = (await db.rawQuery('PRAGMA table_info(Persons)'))
        .map((row) => row['name'])
        .toSet();
    if (!columns.contains('managerProfile')) {
      await db.execute('ALTER TABLE Persons ADD COLUMN managerProfile TEXT');
    }
  }

  Future<ManagerProfile> getManagerProfile(String personId) async {
    final rows = await (await database).query(
      'Persons',
      columns: ['managerProfile'],
      where: 'id = ? AND category = ?',
      whereArgs: [personId, 'manager'],
      limit: 1,
    );
    return ManagerProfile.decode(rows.firstOrNull?['managerProfile']);
  }

  Future<void> saveManagerProfile(
    String personId,
    ManagerProfile profile,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final count = await txn.update(
        'Persons',
        {
          'managerProfile': jsonEncode(profile.toMap()),
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND category = ?',
        whereArgs: [personId, 'manager'],
      );
      if (count != 1) throw StateError('Carreira de técnico não encontrada.');
      await txn.update(
        'TwitterAccounts',
        {'name': profile.displayName},
        where: 'id = ? AND personId = ?',
        whereArgs: ['$personId:user', personId],
      );
    });
  }

  Future<Person?> getActivePerson() async {
    final db = await database;
    final settings = await db.query('Settings', limit: 1);
    if (settings.isEmpty || settings.first['activePersonId'] == null) {
      return null;
    }
    final rows = await db.query(
      'Persons',
      where: 'id = ?',
      whereArgs: [settings.first['activePersonId']],
      limit: 1,
    );
    return rows.isEmpty ? null : Person.fromMap(rows.first);
  }

  Future<List<Person>> getPersons([PersonCategory? category]) async {
    final rows = await (await database).query(
      'Persons',
      where: category == null ? null : 'category = ?',
      whereArgs: category == null ? null : [category.name],
      orderBy: 'createdAt DESC',
    );
    return rows.map(Person.fromMap).toList();
  }

  Future<void> setActivePersonId(String? id) async {
    await (await database).update('Settings', {'activePersonId': id});
  }

  Future<void> createPerson(Person person) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('Persons', person.toMap());
      await txn.update('Settings', {'activePersonId': person.id});
    });
  }

  Future<List<Season>> getSeasons(String personId) async {
    final rows = await (await database).query(
      'Seasons',
      where: 'personId = ?',
      whereArgs: [personId],
      orderBy: 'startDate DESC',
    );
    return rows.map(Season.fromMap).toList();
  }

  Future<void> createSeason(Season season) async {
    final db = await database;
    await db.transaction((txn) async {
      await ensureTransferReleaseSchema(txn);
      await txn.insert('Seasons', season.toMap());
      await SeasonRosterService.initialize(txn, season);
    });
  }

  static Future<void> _createMatchTables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE Tournament(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, abbreviation TEXT,
      type TEXT, category TEXT, fifaVersions TEXT, sex TEXT,
      imageName TEXT, imagePath TEXT, leagueId TEXT)''');
    await db.execute('''CREATE TABLE PlayerFixtures(
      id TEXT PRIMARY KEY, personId TEXT NOT NULL, date TEXT NOT NULL,
      fifaVersion TEXT NOT NULL, playerTeamScore INTEGER NOT NULL,
      oppositeTeamScore INTEGER NOT NULL, rating REAL,
      goalsCount INTEGER NOT NULL, assistsCount INTEGER NOT NULL,
      savesCount INTEGER NOT NULL, minsPlayed INTEGER,
      yellowCards INTEGER NOT NULL, redCards INTEGER NOT NULL,
      oppositeTeamLeagueId TEXT, oppositeTeamId TEXT NOT NULL,
      playerTeamLeagueId TEXT, playerTeamId TEXT NOT NULL,
      playerOfTheMatch TEXT, tournamentId TEXT NOT NULL,
      seasonId TEXT NOT NULL, stage TEXT, goalsFromPenalty INTEGER,
      shotsOnTarget INTEGER, location TEXT NOT NULL,
      isInjured INTEGER NOT NULL, isDisqualified INTEGER,
      createdAt TEXT, updatedAt TEXT, isFavorite INTEGER,
      playerTeamPenaltiesScore INTEGER, oppositeTeamPenaltiesScore INTEGER,
      position INTEGER, notes TEXT)''');
    await db.execute('''CREATE TABLE ManagerFixtures(
      id TEXT PRIMARY KEY, personId TEXT NOT NULL, date TEXT NOT NULL,
      fifaVersion TEXT NOT NULL, playerTeamScore INTEGER NOT NULL,
      oppositeTeamScore INTEGER NOT NULL, oppositeTeamLeagueId TEXT,
      oppositeTeamId TEXT NOT NULL, playerTeamLeagueId TEXT,
      playerTeamId TEXT NOT NULL, playerOfTheMatchId TEXT,
      isPotmFromMyTeam INTEGER, tournamentId TEXT NOT NULL,
      seasonId TEXT NOT NULL, stage TEXT, teamPossession DOUBLE,
      passAccuracy DOUBLE, playerTeamShoutsCount INTEGER,
      opponentTeamShotsCount INTEGER, location TEXT NOT NULL,
      createdAt TEXT, updatedAt TEXT, isFavorite INTEGER,
      playerTeamPenaltiesScore INTEGER, oppositeTeamPenaltiesScore INTEGER,
      position INTEGER, notes TEXT, extraTime INTEGER,
      opponentGoalDetails TEXT)''');
  }

  static Future<void> _createHistoryTables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE PlayerTransferItem(
      id TEXT PRIMARY KEY, transferDate TEXT NOT NULL,
      personId TEXT NOT NULL, fifaVersion TEXT NOT NULL,
      fromTeamId TEXT, fromLeagueId TEXT, toTeamId TEXT, toLeagueId TEXT,
      weeklyWage INTEGER, yearlyWage INTEGER, overall INTEGER,
      transferValue INTEGER, taxRate DOUBLE, rules TEXT,
      type TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE ManagerCareerHistoryItem(
      id TEXT PRIMARY KEY, date TEXT NOT NULL, personId TEXT NOT NULL,
      fifaVersion TEXT NOT NULL, fromTeamId TEXT, fromLeagueId TEXT,
      toTeamId TEXT, toLeagueId TEXT, weeklyWage INTEGER,
      yearlyWage INTEGER, nationalTeamId TEXT, taxRate DOUBLE,
      rules TEXT, type TEXT NOT NULL)''');
  }

  static Future<void> _createTrophiesTable(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE Trophies(
      id TEXT PRIMARY KEY, date TEXT, teamId TEXT NOT NULL,
      leagueId TEXT, isNational INTEGER NOT NULL,
      description TEXT, awardId TEXT NOT NULL, count INTEGER NOT NULL,
      seasonId TEXT NOT NULL, fixtureId TEXT, personId TEXT NOT NULL)''');
  }

  static Future<void> _createTeamTables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE CustomCreatedPlayer(
      id TEXT PRIMARY KEY, personId TEXT NOT NULL, realPlayerId TEXT,
      name TEXT NOT NULL, positionId TEXT NOT NULL, overall INTEGER NOT NULL,
      potential INTEGER NOT NULL, birthdate INTEGER, firstSeasonAge INTEGER,
      height INTEGER, weight INTEGER, nationalityId TEXT,
      realFace INTEGER NOT NULL, fromRealPlayer INTEGER NOT NULL,
      customAvatarFilePath TEXT, foot STRING NOT NULL)''');
    await db.execute('''CREATE TABLE TeamPlayer(
      id TEXT PRIMARY KEY, personId TEXT NOT NULL, playerId TEXT,
      seasonId TEXT NOT NULL, x INTEGER, y INTEGER, overall INTEGER,
      shirtNumber INTEGER, loanStatus TEXT, wage INTEGER, yearlyWage INTEGER,
      marketValue INTEGER, isBench INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE TeamTransferItem(
      id TEXT PRIMARY KEY, personId TEXT NOT NULL, seasonId TEXT NOT NULL,
      playerInstanceId TEXT NOT NULL, fromTeamId TEXT, fromLeagueId TEXT,
      toTeamId TEXT, toLeagueId TEXT, wage INTEGER, yearlyWage INTEGER,
      transferValue INTEGER, endOfLoanDirection TEXT,
      type TEXT NOT NULL, date TEXT NOT NULL)''');
  }

  static Future<void> _createAcademyAndInjuryTables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE AcademyPlayer(
      id TEXT PRIMARY KEY, personId TEXT NOT NULL, name TEXT NOT NULL,
      positionId TEXT NOT NULL, overall INTEGER NOT NULL,
      potentialStart INTEGER NOT NULL, potentialEnd INTEGER NOT NULL,
      birthdate INTEGER, height INTEGER, weight INTEGER, nationalityId TEXT,
      teamId TEXT NOT NULL, isHistorical INTEGER, leagueId TEXT NOT NULL,
      customAvatarFilePath TEXT, foot STRING NOT NULL)''');
    await db.execute('''CREATE TABLE Injury(
      id TEXT PRIMARY KEY, personId TEXT NOT NULL, playerId TEXT NOT NULL,
      description TEXT, startDate TEXT NOT NULL, endDate TEXT,
      seasonId TEXT NOT NULL, teamId TEXT NOT NULL,
      expectedRecoveryDays INTEGER, leagueId TEXT NOT NULL,
      createdAt TEXT NOT NULL)''');
  }

  static Future<void> _createManagerPerformanceTable(
    DatabaseExecutor db,
  ) async {
    await db.execute('''CREATE TABLE ManagerFixturePlayerPerformances(
      id TEXT PRIMARY KEY, personId TEXT NOT NULL, fixtureId TEXT NOT NULL,
      playerInstanceId TEXT NOT NULL, goalsCount INTEGER, assistsCount INTEGER,
      yellowCards INTEGER, redCards INTEGER, avgRating REAL,
      goalDetails TEXT, assistDetails TEXT, yellowCardDetails TEXT,
      redCardDetails TEXT, substitutionDetails TEXT, shotsCount INTEGER,
      shotAccuracy INTEGER, passes INTEGER, keyPasses INTEGER,
      passAccuracy INTEGER, tackles INTEGER, tacklesAccuracy INTEGER,
      dribbles INTEGER, dribblesAccuracy INTEGER, saves INTEGER,
      penaltySaves INTEGER, ownGoalDetails TEXT, missedPenaltyDetails TEXT,
      injuryDetails TEXT)''');
  }

  static Future<void> ensureCompatibleSchema(DatabaseExecutor db) async {
    final existing = {
      for (final row in await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      ))
        row['name'] as String,
    };
    for (final entry in compatibleSchema.entries) {
      if (!existing.contains(entry.key)) {
        await db.execute(
          'CREATE TABLE ${entry.key}(${entry.value.join(', ')})',
        );
        continue;
      }
      final columns = {
        for (final row in await db.rawQuery('PRAGMA table_info(${entry.key})'))
          row['name'] as String,
      };
      for (final definition in entry.value) {
        final name = definition.split(' ').first;
        if (columns.contains(name)) continue;
        final relaxed = definition
            .replaceAll(' PRIMARY KEY', '')
            .replaceAll(RegExp(r' NOT NULL(?! DEFAULT)'), '');
        await db.execute('ALTER TABLE ${entry.key} ADD COLUMN $relaxed');
      }
    }
    await ensureRosterDepartureSchema(db);
    await SeasonRosterService.ensureSchema(db);
    await ensureFcScoreSchema(db);
    await ensureFixtureCaptaincySchema(db);
    await ensurePerformanceStatsSchema(db);
    await ensureRosterLookupIndexes(db);
  }

  static Future<void> ensureRosterLookupIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS roster_overall_player '
      'ON Overall(personId, customPlayerId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS roster_season_players '
      'ON TeamPlayer(personId, seasonId, isBench, shirtNumber)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS roster_player_seasons '
      'ON TeamPlayer(personId, playerId, seasonId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS roster_departed_player '
      'ON TeamPlayerDeparture(personId, playerId)',
    );
  }

  static Future<void> _migratePlayerReferences(DatabaseExecutor db) async {
    final orphans = await db.rawQuery('''
      SELECT DISTINCT tp.personId, tp.playerId, p.fifaVersion
      FROM TeamPlayer tp JOIN Persons p ON p.id = tp.personId
      WHERE tp.playerId IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM CustomCreatedPlayer cp
        WHERE cp.id = tp.playerId AND cp.personId = tp.personId)''');
    final players = <String, Map<String, GamePlayer>>{};
    for (final row in orphans) {
      final version = row['fifaVersion'] as String;
      final realId = row['playerId'] as String;
      final byId = players[version] ??= await GamePlayers.load(version)
          .then((list) => {for (final item in list) item.id: item})
          .catchError((_) => <String, GamePlayer>{});
      final id = const Uuid().v1();
      await db.insert(
        'CustomCreatedPlayer',
        _realPlayerRow(
          id,
          row['personId'] as String,
          byId[realId],
          realPlayerId: realId,
        ),
      );
      await db.update(
        'TeamPlayer',
        {'playerId': id},
        where: 'personId = ? AND playerId = ?',
        whereArgs: [row['personId'], realId],
      );
    }
    final teamPlayers = await db.query(
      'TeamPlayer',
      columns: ['id', 'playerId'],
    );
    final map = {
      for (final row in teamPlayers)
        if (row['playerId'] != null)
          row['id'] as String: row['playerId'] as String,
    };
    if (map.isEmpty) return;
    for (final (table, column) in [
      ('ManagerFixturePlayerPerformances', 'playerInstanceId'),
      ('TeamTransferItem', 'playerInstanceId'),
      ('Injury', 'playerId'),
      ('ManagerFixtures', 'playerOfTheMatchId'),
    ]) {
      for (final entry in map.entries) {
        await db.update(
          table,
          {column: entry.value},
          where: '$column = ?',
          whereArgs: [entry.key],
        );
      }
    }
    final performances = await db.query('ManagerFixturePlayerPerformances');
    for (final row in performances) {
      final changes = <String, Object?>{};
      for (final column in [
        'goalDetails',
        'assistDetails',
        'substitutionDetails',
      ]) {
        final value = row[column] as String?;
        if (value == null) continue;
        var next = value;
        for (final entry in map.entries) {
          next = next.replaceAll('"${entry.key}"', '"${entry.value}"');
        }
        if (next != value) changes[column] = next;
      }
      if (changes.isNotEmpty) {
        await db.update(
          'ManagerFixturePlayerPerformances',
          changes,
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  }

  static Future<void> _createCustomConfigurationTables(
    DatabaseExecutor db,
  ) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS CustomClub(
      id TEXT PRIMARY KEY, label TEXT NOT NULL, fifaVersion TEXT NOT NULL,
      personId TEXT NOT NULL, imageUrl TEXT, imagePath TEXT,
      leagueId TEXT NOT NULL, createdAt TEXT, updatedAt TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS CustomLeague(
      id TEXT PRIMARY KEY, label TEXT NOT NULL, fifaVersion TEXT NOT NULL,
      isWoman INTEGER, imageUrl TEXT, imagePath TEXT, createdAt TEXT,
      updatedAt TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS ClubCustomizationModel(
      id TEXT PRIMARY KEY, clubName TEXT NOT NULL,
      originalTeamId TEXT NOT NULL, originalLeagueId TEXT, imageUrl TEXT,
      imagePath TEXT, fifaVersion TEXT NOT NULL, createdAt TEXT,
      updatedAt TEXT)''');
    final columns = await db.rawQuery('PRAGMA table_info(Tournament)');
    if (!columns.any((column) => column['name'] == 'imagePath')) {
      await db.execute('ALTER TABLE Tournament ADD COLUMN imagePath TEXT');
    }
  }

  Future<List<Map<String, Object?>>> getManagerPerformances(
    String personId,
    String fixtureId,
  ) async => (await database).query(
    'ManagerFixturePlayerPerformances',
    where: 'personId = ? AND fixtureId = ?',
    whereArgs: [personId, fixtureId],
    orderBy: 'avgRating DESC',
  );

  Future<List<Map<String, Object?>>> getManagerPlayerStatistics(
    String personId, {
    String? seasonId,
  }) async => (await database).rawQuery(
    '''
    SELECT p.playerInstanceId AS playerId, cp.name, cp.realPlayerId,
      cp.customAvatarFilePath, cp.positionId,
      COUNT(DISTINCT p.fixtureId) AS matches,
      SUM(COALESCE(p.goalsCount, 0)) AS goals,
      SUM(COALESCE(p.assistsCount, 0)) AS assists,
      SUM(COALESCE(p.yellowCards, 0)) AS yellowCards,
      SUM(COALESCE(p.redCards, 0)) AS redCards,
      AVG(p.avgRating) AS rating
    FROM ManagerFixturePlayerPerformances p
    JOIN ManagerFixtures f ON f.id = p.fixtureId AND f.personId = p.personId
    LEFT JOIN CustomCreatedPlayer cp
      ON cp.id = p.playerInstanceId AND cp.personId = p.personId
    WHERE p.personId = ? AND (? IS NULL OR f.seasonId = ?)
    GROUP BY p.playerInstanceId
    ORDER BY goals DESC, assists DESC, matches DESC
  ''',
    [personId, seasonId, seasonId],
  );

  Future<List<Map<String, Object?>>> getHeadToHeadScorers(
    String personId,
    String opponentId,
  ) async => (await database).rawQuery(
    '''
    SELECT cp.name, SUM(COALESCE(p.goalsCount, 0)) AS goals,
      COUNT(DISTINCT p.fixtureId) AS games
    FROM ManagerFixturePlayerPerformances p
    JOIN ManagerFixtures f ON f.id = p.fixtureId AND f.personId = p.personId
    LEFT JOIN CustomCreatedPlayer cp
      ON cp.id = p.playerInstanceId AND cp.personId = p.personId
    WHERE p.personId = ? AND f.oppositeTeamId = ?
      AND p.rowid = (SELECT MAX(d.rowid) FROM ManagerFixturePlayerPerformances d
        WHERE d.personId = p.personId AND d.fixtureId = p.fixtureId
          AND d.playerInstanceId = p.playerInstanceId)
    GROUP BY p.playerInstanceId HAVING goals > 0
    ORDER BY goals DESC, games ASC LIMIT 5
  ''',
    [personId, opponentId],
  );

  Future<List<Map<String, Object?>>> getSummaryFixtures(
    String personId,
    List<String> seasonIds,
  ) async {
    if (seasonIds.isEmpty) return const [];
    final marks = List.filled(seasonIds.length, '?').join(', ');
    return (await database).rawQuery(
      '''
    SELECT id, date, seasonId, tournamentId, location, extraTime,
      playerTeamId, playerTeamLeagueId, oppositeTeamId, oppositeTeamLeagueId,
      playerTeamScore, oppositeTeamScore, playerTeamPenaltiesScore,
      oppositeTeamPenaltiesScore, opponentGoalDetails
    FROM ManagerFixtures
    WHERE personId = ? AND seasonId IN ($marks)
    ORDER BY date
  ''',
      [personId, ...seasonIds],
    );
  }

  Future<List<Map<String, Object?>>> getSummaryGoalRows(
    String personId,
    List<String> seasonIds,
  ) async {
    if (seasonIds.isEmpty) return const [];
    final marks = List.filled(seasonIds.length, '?').join(', ');
    return (await database).rawQuery(
      '''
    SELECT p.fixtureId, p.playerInstanceId, p.goalDetails, p.goalsCount
    FROM ManagerFixturePlayerPerformances p
    JOIN ManagerFixtures f ON f.id = p.fixtureId AND f.personId = p.personId
    WHERE p.personId = ? AND f.seasonId IN ($marks)
      AND p.rowid = (SELECT MAX(d.rowid) FROM ManagerFixturePlayerPerformances d
        WHERE d.personId = p.personId AND d.fixtureId = p.fixtureId
          AND d.playerInstanceId = p.playerInstanceId)
  ''',
      [personId, ...seasonIds],
    );
  }

  Future<List<Map<String, Object?>>> getPlayerMatchRows(
    String personId,
    String playerId, {
    String? seasonId,
  }) async => (await database).rawQuery(
    '''
    SELECT p.*, f.date, f.seasonId, f.oppositeTeamId,
      f.oppositeTeamLeagueId, f.playerTeamId, f.playerTeamLeagueId,
      f.playerTeamScore, f.oppositeTeamScore, f.location, f.tournamentId,
      f.stage, f.extraTime, f.captaincy, f.playerOfTheMatchId, f.isPotmFromMyTeam,
      f.playerTeamPenaltiesScore, f.oppositeTeamPenaltiesScore
    FROM ManagerFixturePlayerPerformances p
    JOIN ManagerFixtures f ON f.id = p.fixtureId AND f.personId = p.personId
    WHERE p.personId = ? AND p.playerInstanceId = ?
      AND (? IS NULL OR f.seasonId = ?)
    ORDER BY f.date DESC
  ''',
    [personId, playerId, seasonId, seasonId],
  );

  Future<List<Map<String, Object?>>> getManagerStatisticsMatchRows(
    String personId, {
    String? seasonId,
  }) async => (await database).rawQuery(
    '''
        SELECT p.*, f.date, f.seasonId, f.playerTeamId, f.playerTeamLeagueId,
          f.tournamentId, f.extraTime, f.captaincy, f.oppositeTeamScore,
          f.playerOfTheMatchId, f.isPotmFromMyTeam,
          f.oppositeTeamId, f.oppositeTeamLeagueId, f.playerTeamScore,
          f.location, f.stage
        FROM ManagerFixturePlayerPerformances p
        JOIN ManagerFixtures f ON f.id = p.fixtureId AND f.personId = p.personId
        WHERE p.personId = ? ${seasonId == null ? '' : 'AND f.seasonId = ?'}
        ORDER BY f.date DESC, p.rowid DESC
      ''',
    [personId, ?seasonId],
  );

  Future<DateTime?> getCareerDate(String personId) async {
    final rows = await (await database).rawQuery(
      '''
      SELECT MAX(julianday(day)) AS day FROM (
        SELECT date AS day FROM ManagerFixtures WHERE personId = ?
        UNION ALL SELECT date FROM PlayerFixtures WHERE personId = ?
        UNION ALL SELECT startDate FROM Seasons WHERE personId = ?
        UNION ALL SELECT currentDate FROM FcScoreCompetition WHERE personId = ?
      )
    ''',
      [personId, personId, personId, personId],
    );
    final julian = rows.firstOrNull?['day'] as num?;
    return julian == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            ((julian.toDouble() - 2440587.5) * Duration.millisecondsPerDay)
                .round(),
            isUtc: true,
          );
  }

  Future<List<Map<String, Object?>>> getManagerStatisticsRoster(
    String personId,
  ) async {
    final db = await database;
    final active = await db.rawQuery(
      '''
        SELECT tp.*, s.startDate AS seasonStartDate, s.endDate AS seasonEndDate,
          s.createdAt AS seasonCreatedAt
        FROM TeamPlayer tp JOIN Seasons s ON s.id = tp.seasonId AND s.personId = tp.personId
        WHERE tp.personId = ?
        ORDER BY s.startDate DESC, tp.isBench, tp.shirtNumber
      ''',
      [personId],
    );
    final rows = await _includeDepartedRoster(db, active, personId);
    return _withCurrentOveralls(db, rows, personId, seasonRows: rows);
  }

  static Future<List<Map<String, Object?>>> _withCurrentOveralls(
    DatabaseExecutor db,
    List<Map<String, Object?>> rows,
    String personId, {
    List<Map<String, Object?>>? seasonRows,
  }) async {
    if (rows.isEmpty) return rows;
    final ids = {
      for (final row in rows)
        if ((row['playerId'] ?? row['id']) case final String id)
          if (id.isNotEmpty) id,
    }.toList();
    final history = <Map<String, Object?>>[];
    final selectedSeasons = <Map<String, Object?>>[];
    final archivedSeasons = <Map<String, Object?>>[];
    for (var offset = 0; offset < ids.length; offset += 400) {
      final batch = ids.sublist(offset, min(offset + 400, ids.length));
      final marks = List.filled(batch.length, '?').join(',');
      history.addAll(
        await db.rawQuery(
          '''
          SELECT h.customPlayerId, h.overall, h.date, h.createdAt
          FROM Overall h
          WHERE h.personId = ? AND h.customPlayerId IN ($marks)
            AND h.overall IS NOT NULL
            AND (julianday(h.date) IS NULL OR julianday(h.date) >= (
              SELECT MAX(julianday(n.date)) FROM Overall n
              WHERE n.personId = h.personId AND n.customPlayerId = h.customPlayerId
                AND n.overall IS NOT NULL) - 1)
          ORDER BY h.rowid DESC
        ''',
          [personId, ...batch],
        ),
      );
      if (seasonRows != null) continue;
      final active = await db.rawQuery(
        '''
        SELECT tp.id, tp.playerId, tp.overall, s.startDate AS seasonStartDate,
          s.endDate AS seasonEndDate, s.createdAt AS seasonCreatedAt
        FROM TeamPlayer tp JOIN Seasons s
          ON s.id = tp.seasonId AND s.personId = tp.personId
        WHERE tp.personId = ? AND tp.playerId IN ($marks)
        ORDER BY s.startDate DESC, s.createdAt DESC, tp.rowid DESC
        ''',
        [personId, ...batch],
      );
      selectedSeasons.addAll(active);
      archivedSeasons.addAll(
        await db.rawQuery(
          '''
        SELECT d.rosterJson, s.startDate AS seasonStartDate,
          s.createdAt AS seasonCreatedAt
        FROM TeamPlayerDeparture d JOIN Seasons s
          ON s.id = d.seasonId AND s.personId = d.personId
        WHERE d.personId = ? AND d.playerId IN ($marks)
        ORDER BY s.startDate DESC, d.departureDate DESC, d.rowid DESC
      ''',
          [personId, ...batch],
        ),
      );
    }
    return BackgroundData.run(
      _applyCurrentOveralls,
      (
        rows: rows,
        history: history,
        seasons: seasonRows ?? selectedSeasons,
        archived: archivedSeasons,
      ),
      label: 'current player values',
      background:
          rows.length +
              history.length +
              (seasonRows ?? selectedSeasons).length +
              archivedSeasons.length >=
          128,
    );
  }

  static List<Map<String, Object?>> _applyCurrentOveralls(
    ({
      List<Map<String, Object?>> rows,
      List<Map<String, Object?>> history,
      List<Map<String, Object?>> seasons,
      List<Map<String, Object?>> archived,
    })
    request,
  ) {
    final seasons = <Map<String, Object?>>[
      ...request.seasons,
      for (final archive in request.archived)
        {
          ...Map<String, Object?>.from(
            jsonDecode(archive['rosterJson'] as String) as Map,
          ),
          'seasonStartDate': archive['seasonStartDate'],
          'seasonCreatedAt': archive['seasonCreatedAt'],
        },
    ];
    final latest = PlayerValueHistory.latest(
      request.history,
      seasons,
      'Overall',
    );
    return [
      for (final row in request.rows)
        {
          ...row,
          if (latest[row['playerId'] ?? row['id']]?['overall']
              case final num overall)
            'overall': overall.toInt(),
        },
    ];
  }

  static Future<List<Map<String, Object?>>> _includeDepartedRoster(
    DatabaseExecutor db,
    List<Map<String, Object?>> active,
    String personId, {
    String? playerId,
    List<String>? playerIds,
  }) async {
    final filter = playerId != null ? [playerId] : playerIds;
    if (filter != null && filter.isEmpty) return active;
    final archived = await db.rawQuery(
      '''
      SELECT d.*, s.startDate AS seasonStartDate, s.endDate AS seasonEndDate,
        s.createdAt AS seasonCreatedAt
      FROM TeamPlayerDeparture d JOIN Seasons s
        ON s.id = d.seasonId AND s.personId = d.personId
      WHERE d.personId = ? ${filter == null ? '' : 'AND d.playerId IN (${List.filled(filter.length, '?').join(',')})'}
      ORDER BY d.departureDate DESC, d.rowid DESC
    ''',
      [personId, ...?filter],
    );
    final rows = List<Map<String, Object?>>.of(active);
    final seen = {for (final row in active) row['id']};
    for (final entry in archived) {
      final snapshot = Map<String, Object?>.from(
        jsonDecode(entry['rosterJson'] as String) as Map,
      );
      if (!seen.add(snapshot['id'])) continue;
      final movement = entry['transferJson'] == null
          ? <String, Object?>{
              'manualDeparture': true,
              'personId': personId,
              'playerInstanceId': entry['playerId'],
              'seasonId': entry['seasonId'],
              'fromTeamId': entry['teamId'],
              'fromLeagueId': entry['leagueId'],
              'date': entry['departureDate'],
            }
          : Map<String, Object?>.from(
              jsonDecode(entry['transferJson'] as String) as Map,
            );
      rows.add({
        ...snapshot,
        'seasonStartDate': entry['seasonStartDate'],
        'seasonEndDate': entry['seasonEndDate'],
        'seasonCreatedAt': entry['seasonCreatedAt'],
        'departureDate': entry['departureDate'],
        'departureTransferId': entry['transferId'],
        'departureTeamId': entry['teamId'],
        'departureMovement': {...movement, 'rosterDepartureRecord': true},
      });
    }
    final order = {for (var i = 0; i < rows.length; i++) rows[i]['id']: i};
    rows.sort((a, b) {
      final season = '${b['seasonStartDate']}'.compareTo(
        '${a['seasonStartDate']}',
      );
      if (season != 0) return season;
      return order[a['id']]!.compareTo(order[b['id']]!);
    });
    return rows;
  }

  Future<Map<String, int>> getManagerFixtureRedCards(String personId) async {
    final rows = await (await database).rawQuery(
      '''
      SELECT fixtureId, SUM(COALESCE(redCards, 0)) AS total
      FROM ManagerFixturePlayerPerformances
      WHERE personId = ?
      GROUP BY fixtureId
      HAVING total > 0
    ''',
      [personId],
    );
    return {
      for (final row in rows)
        row['fixtureId'] as String: (row['total'] as num).toInt(),
    };
  }

  Future<List<Map<String, Object?>>> getPlayerHistory(
    String personId,
    String playerId,
    String table,
  ) async {
    if (!const {'Overall', 'MarketValue', 'ContractItem'}.contains(table)) {
      throw ArgumentError.value(table, 'table');
    }
    final records = await (await database).query(
      table,
      where: 'personId = ? AND customPlayerId = ?',
      whereArgs: [personId, playerId],
      orderBy: 'julianday(date) DESC, julianday(createdAt) DESC, rowid DESC',
    );
    if (table == 'ContractItem') return records;
    final seasons = await getPlayerSeasonRows(personId, playerId);
    return BackgroundData.run(
      _valueTimeline,
      (records: records, seasons: seasons, table: table),
      label: 'player value timeline',
      background: records.length + seasons.length >= 128,
    );
  }

  static List<Map<String, Object?>> _valueTimeline(
    ({
      List<Map<String, Object?>> records,
      List<Map<String, Object?>> seasons,
      String table,
    })
    request,
  ) => PlayerValueHistory.combine(
    request.records,
    request.seasons,
    request.table,
  );

  Future<void> addPlayerHistory(String table, Map<String, Object?> row) async {
    if (!const {'Overall', 'MarketValue', 'ContractItem'}.contains(table)) {
      throw ArgumentError.value(table, 'table');
    }
    await (await database).insert(table, row);
  }

  Future<void> updatePlayerHistory(
    String table,
    String personId,
    Map<String, Object?> row,
  ) async {
    if (row['isSeasonInitial'] == true ||
        row['id'].toString().startsWith('season-start:')) {
      throw ArgumentError(
        'Edite o valor inicial na configuração da temporada.',
      );
    }
    if (!const {'Overall', 'MarketValue', 'ContractItem'}.contains(table)) {
      throw ArgumentError.value(table, 'table');
    }
    await (await database).update(
      table,
      row,
      where: 'id = ? AND personId = ?',
      whereArgs: [row['id'], personId],
    );
  }

  Future<void> deletePlayerHistory(
    String table,
    String personId,
    String id,
  ) async {
    if (id.startsWith('season-start:')) {
      throw ArgumentError(
        'O valor inicial pertence à configuração da temporada.',
      );
    }
    if (!const {'Overall', 'MarketValue', 'ContractItem'}.contains(table)) {
      throw ArgumentError.value(table, 'table');
    }
    await (await database).delete(
      table,
      where: 'id = ? AND personId = ?',
      whereArgs: [id, personId],
    );
  }

  Future<Map<String, Object?>?> getManagerFixtureById(
    String personId,
    String fixtureId,
  ) async {
    final rows = await (await database).query(
      'ManagerFixtures',
      where: 'id = ? AND personId = ?',
      whereArgs: [fixtureId, personId],
      limit: 1,
    );
    return rows.firstOrNull;
  }

  Future<List<ManagerFixturePlayerPerformance>> getPerformanceModels(
    String personId,
    String fixtureId,
  ) async => (await getManagerPerformances(
    personId,
    fixtureId,
  )).map(ManagerFixturePlayerPerformance.fromMap).toList();

  Future<void> saveManagerPerformances(
    Iterable<ManagerFixturePlayerPerformance> performances, {
    Iterable<String> deletedIds = const [],
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final id in deletedIds) {
        batch.delete(
          'ManagerFixturePlayerPerformances',
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      for (final performance in performances) {
        batch.insert(
          'ManagerFixturePlayerPerformances',
          performance.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> updateFixtureFields(
    PersonCategory category,
    String personId,
    String fixtureId,
    Map<String, Object?> values,
  ) async {
    await (await database).update(
      category == PersonCategory.player ? 'PlayerFixtures' : 'ManagerFixtures',
      values,
      where: 'id = ? AND personId = ?',
      whereArgs: [fixtureId, personId],
    );
  }

  Future<void> saveManagerPerformance(
    Map<String, Object?> row, {
    bool update = false,
  }) async {
    final db = await database;
    if (update) {
      await db.update(
        'ManagerFixturePlayerPerformances',
        row,
        where: 'id = ? AND personId = ?',
        whereArgs: [row['id'], row['personId']],
      );
    } else {
      await db.insert('ManagerFixturePlayerPerformances', row);
    }
  }

  Future<void> deleteManagerPerformance(String personId, String id) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'ManagerFixturePlayerPerformances',
        where: 'id = ? AND personId = ?',
        whereArgs: [id, personId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      await txn.delete(
        'ManagerFixturePlayerPerformances',
        where: 'id = ? AND personId = ?',
        whereArgs: [id, personId],
      );
      await txn.update(
        'ManagerFixtures',
        {'playerOfTheMatchId': null, 'isPotmFromMyTeam': null},
        where: 'id = ? AND personId = ? AND playerOfTheMatchId = ?',
        whereArgs: [
          rows.first['fixtureId'],
          personId,
          rows.first['playerInstanceId'],
        ],
      );
    });
  }

  Future<void> setFixtureFavorite(
    PersonCategory category,
    String personId,
    String fixtureId,
    bool favorite,
  ) async {
    final table = category == PersonCategory.player
        ? 'PlayerFixtures'
        : 'ManagerFixtures';
    await (await database).update(
      table,
      {'isFavorite': favorite ? 1 : 0},
      where: 'id = ? AND personId = ?',
      whereArgs: [fixtureId, personId],
    );
  }

  Future<PressConference?> getPressConference(
    String personId,
    String fixtureId,
  ) async {
    final rows = await (await database).query(
      'ManagerFixtures',
      columns: ['pressConference'],
      where: 'id = ? AND personId = ?',
      whereArgs: [fixtureId, personId],
      limit: 1,
    );
    return PressConference.decode(rows.firstOrNull?['pressConference']);
  }

  Future<void> savePressConference(
    String personId,
    String fixtureId,
    PressConference conference,
  ) async {
    await (await database).update(
      'ManagerFixtures',
      {'pressConference': conference.encode()},
      where: 'id = ? AND personId = ?',
      whereArgs: [fixtureId, personId],
    );
  }

  Future<List<Map<String, Object?>>> getPreviousPressConferences(
    String personId, {
    required String date,
    required String excludeFixtureId,
    int limit = 3,
  }) async => (await database).rawQuery(
    '''
    SELECT id, date, playerTeamId, playerTeamLeagueId, oppositeTeamId,
      oppositeTeamLeagueId, playerTeamScore, oppositeTeamScore, pressConference
    FROM ManagerFixtures
    WHERE personId = ? AND id != ? AND pressConference LIKE '%"status":"done"%'
      AND julianday(date) <= julianday(?)
    ORDER BY julianday(date) DESC
    LIMIT ?
  ''',
    [personId, excludeFixtureId, date, limit],
  );

  Future<void> setManagerPlayerOfMatch(
    String personId,
    String fixtureId,
    String? playerInstanceId,
  ) async {
    await (await database).update(
      'ManagerFixtures',
      {
        'playerOfTheMatchId': playerInstanceId,
        'isPotmFromMyTeam': playerInstanceId == null ? null : 1,
      },
      where: 'id = ? AND personId = ?',
      whereArgs: [fixtureId, personId],
    );
  }

  Future<List<Map<String, Object?>>> getAcademyPlayers(String personId) async =>
      (await database).query(
        'AcademyPlayer',
        where: 'personId = ?',
        whereArgs: [personId],
        orderBy: 'name COLLATE NOCASE',
      );

  Future<void> saveAcademyPlayer(
    Map<String, Object?> row, {
    bool update = false,
  }) async {
    final db = await database;
    if (update) {
      await db.update(
        'AcademyPlayer',
        row,
        where: 'id = ? AND personId = ?',
        whereArgs: [row['id'], row['personId']],
      );
    } else {
      await db.insert('AcademyPlayer', row);
    }
  }

  Future<void> deleteAcademyPlayer(String personId, String id) async {
    await (await database).delete(
      'AcademyPlayer',
      where: 'id = ? AND personId = ?',
      whereArgs: [id, personId],
    );
  }

  Future<String> promoteAcademyPlayer(
    Person person,
    Map<String, Object?> academy,
  ) async {
    final seasons = await getSeasons(person.id);
    if (seasons.isEmpty) {
      throw StateError('common.noSeasonsMessage'.tr());
    }
    final season = seasons.first;
    final birthdate = academy['birthdate'] is int
        ? DateTime.fromMillisecondsSinceEpoch(academy['birthdate'] as int)
        : null;
    int? age;
    if (birthdate != null) {
      final start = season.startDate;
      age = start.year - birthdate.year;
      if (start.month < birthdate.month ||
          (start.month == birthdate.month && start.day < birthdate.day)) {
        age--;
      }
    }
    final playerId = const Uuid().v1();
    final teamPlayerId = const Uuid().v1();
    final transferId = const Uuid().v1();
    final transferDate =
        await getLatestFixtureDate(person.id) ?? season.startDate;
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('CustomCreatedPlayer', {
        'id': playerId,
        'personId': person.id,
        'realPlayerId': null,
        'name': academy['name'],
        'positionId': academy['positionId'],
        'overall': academy['overall'],
        'potential': academy['potentialEnd'],
        'birthdate': academy['birthdate'],
        'firstSeasonAge': age,
        'height': academy['height'],
        'weight': academy['weight'],
        'nationalityId': academy['nationalityId'],
        'realFace': 0,
        'fromRealPlayer': 0,
        'customAvatarFilePath': academy['customAvatarFilePath'],
        'foot': academy['foot'],
      });
      await txn.insert('TeamPlayer', {
        'id': teamPlayerId,
        'personId': person.id,
        'playerId': playerId,
        'seasonId': season.id,
        'overall': academy['overall'],
        'isBench': 1,
      });
      await txn.insert('TeamTransferItem', {
        'id': transferId,
        'personId': person.id,
        'seasonId': season.id,
        'playerInstanceId': playerId,
        'toTeamId': person.teamId,
        'toLeagueId': person.leagueId,
        'type': 'youthAcademy',
        'date': transferDate.toIso8601String(),
      });
      await txn.delete(
        'AcademyPlayer',
        where: 'id = ? AND personId = ?',
        whereArgs: [academy['id'], person.id],
      );
      await txn.rawUpdate(
        'UPDATE Persons SET promotedYoungPlayersCount = '
        'COALESCE(promotedYoungPlayersCount, 0) + 1 WHERE id = ?',
        [person.id],
      );
    });
    return transferId;
  }

  Future<List<Map<String, Object?>>> getInjuries(
    String personId, {
    String? seasonId,
  }) async => (await database).query(
    'Injury',
    where: seasonId == null ? 'personId = ?' : 'personId = ? AND seasonId = ?',
    whereArgs: seasonId == null ? [personId] : [personId, seasonId],
    orderBy: 'startDate DESC',
  );

  Future<void> saveInjury(
    Map<String, Object?> row, {
    bool update = false,
  }) async {
    final db = await database;
    if (update) {
      await db.update(
        'Injury',
        row,
        where: 'id = ? AND personId = ?',
        whereArgs: [row['id'], row['personId']],
      );
    } else {
      await db.insert('Injury', row);
    }
  }

  Future<void> deleteInjury(String personId, String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'Injury',
        where: 'id = ? AND personId = ?',
        whereArgs: [id, personId],
      );
      final match = matchInjuryKey(id);
      if (match != null) {
        await txn.update(
          'ManagerFixturePlayerPerformances',
          {'injuryDetails': '[]'},
          where: 'personId = ? AND fixtureId = ? AND playerInstanceId = ?',
          whereArgs: [personId, match.fixtureId, match.playerId],
        );
      }
    });
  }

  static ({String fixtureId, String playerId})? matchInjuryKey(String id) {
    final parts = id.split(':');
    return parts.length == 3 && parts.first == 'fixture'
        ? (fixtureId: parts[1], playerId: parts[2])
        : null;
  }

  Future<void> syncMatchInjuries(String personId, {String? fixtureId}) async {
    final db = await database;
    await db.transaction((txn) async {
      final fixtures = {
        for (final f in await txn.query(
          'ManagerFixtures',
          columns: [
            'id',
            'date',
            'seasonId',
            'playerTeamId',
            'playerTeamLeagueId',
          ],
          where: fixtureId == null ? 'personId = ?' : 'personId = ? AND id = ?',
          whereArgs: fixtureId == null ? [personId] : [personId, fixtureId],
        ))
          f['id']: f,
      };
      final wanted = <String, (Map<String, Object?>, String)>{};
      for (final p in await txn.query(
        'ManagerFixturePlayerPerformances',
        columns: ['fixtureId', 'playerInstanceId', 'injuryDetails'],
        where: fixtureId == null
            ? 'personId = ?'
            : 'personId = ? AND fixtureId = ?',
        whereArgs: fixtureId == null ? [personId] : [personId, fixtureId],
      )) {
        final fixture = fixtures[p['fixtureId']];
        final details = p['injuryDetails']?.toString() ?? '';
        if (fixture == null || details.isEmpty || details == '[]') continue;
        final playerId = p['playerInstanceId'] as String;
        wanted['fixture:${p['fixtureId']}:$playerId'] = (fixture, playerId);
      }
      final injuries = await txn.query(
        'Injury',
        where: 'personId = ?',
        whereArgs: [personId],
      );
      final created = {
        for (final i in injuries)
          if (matchInjuryKey(i['id'] as String) case final key?
              when fixtureId == null || key.fixtureId == fixtureId)
            i['id'] as String,
      };
      for (final id in created.difference(wanted.keys.toSet())) {
        await txn.delete(
          'Injury',
          where: 'id = ? AND personId = ?',
          whereArgs: [id, personId],
        );
      }
      final person = (await txn.query(
        'Persons',
        columns: ['leagueId'],
        where: 'id = ?',
        whereArgs: [personId],
      )).firstOrNull;
      for (final MapEntry(key: id, value: (fixture, playerId))
          in wanted.entries) {
        if (created.contains(id)) continue;
        final date = DateTime.parse(fixture['date'] as String);
        final day = DateTime(date.year, date.month, date.day);
        final registered = injuries.any((i) {
          if (i['playerId'] != playerId ||
              matchInjuryKey('${i['id']}') != null) {
            return false;
          }
          final start = DateTime.tryParse('${i['startDate']}');
          final end = DateTime.tryParse('${i['endDate']}');
          if (start == null) return false;
          final startDay = DateTime(start.year, start.month, start.day);
          return startDay.difference(day).inDays.abs() <= 1 ||
              (!startDay.isAfter(day) && (end == null || !end.isBefore(day)));
        });
        if (registered) continue;
        await txn.insert('Injury', {
          'id': id,
          'personId': personId,
          'playerId': playerId,
          'startDate': day.toIso8601String(),
          'seasonId': fixture['seasonId'],
          'teamId': fixture['playerTeamId'],
          'leagueId':
              fixture['playerTeamLeagueId'] ?? person?['leagueId'] ?? '',
          'createdAt': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<({List<Map<String, Object?>> fixtures, Set<String> played})>
  getInjuryMatchContext(String personId) async {
    final db = await database;
    final fixtures = await db.query(
      'ManagerFixtures',
      columns: [
        'id',
        'date',
        'playerTeamId',
        'playerTeamLeagueId',
        'oppositeTeamId',
        'oppositeTeamLeagueId',
      ],
      where: 'personId = ?',
      whereArgs: [personId],
    );
    final played = {
      for (final p in await db.query(
        'ManagerFixturePlayerPerformances',
        columns: ['fixtureId', 'playerInstanceId'],
        where: 'personId = ?',
        whereArgs: [personId],
      ))
        '${p['fixtureId']}:${p['playerInstanceId']}',
    };
    return (fixtures: fixtures, played: played);
  }

  Future<List<Map<String, Object?>>> getTeamPlayers(
    String personId,
    String seasonId, {
    bool prepareLineup = false,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await ensureTransferReleaseSchema(txn);
      final season = (await txn.query(
        'Seasons',
        where: 'id = ? AND personId = ?',
        whereArgs: [seasonId, personId],
      )).firstOrNull;
      if (season != null) {
        await SeasonRosterService.initialize(txn, Season.fromMap(season));
      }
      await SquadLineup.ensure(
        txn,
        personId,
        seasonId,
        materialize: prepareLineup,
      );
      await _applyDueTeamTransfers(txn, personId);
    });
    final rows = await db.rawQuery(
      '''
    SELECT tp.*, sl.formation AS lineupFormation, cp.name AS customName, cp.positionId AS customPositionId,
      cp.potential AS customPotential, cp.foot AS customFoot,
      cp.realPlayerId AS realPlayerId, cp.fromRealPlayer AS fromRealPlayer,
      cp.customAvatarFilePath AS customAvatarFilePath,
      cp.nationalityId AS nationalityId, cp.birthdate AS birthdate,
      cp.height AS playerHeight, cp.weight AS playerWeight,
      cp.firstSeasonAge AS firstSeasonAge
    FROM TeamPlayer tp LEFT JOIN CustomCreatedPlayer cp
      ON cp.id = tp.playerId AND cp.personId = tp.personId
    LEFT JOIN SquadLineup sl ON sl.personId = tp.personId AND sl.seasonId = tp.seasonId
    WHERE tp.personId = ? AND tp.seasonId = ?
    ORDER BY tp.isBench, tp.shirtNumber, cp.name
  ''',
      [personId, seasonId],
    );
    return _withCurrentOveralls(db, rows, personId);
  }

  Future<void> applyDueTeamTransfers(String personId) async {
    await (await database).transaction(
      (txn) => _applyDueTeamTransfers(txn, personId),
    );
  }

  Future<List<Map<String, Object?>>> getNationalTeamPlayers(
    String personId,
    String seasonId,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
    SELECT np.*, cp.name AS customName, cp.positionId AS customPositionId,
      cp.potential AS customPotential, cp.foot AS customFoot,
      cp.realPlayerId AS realPlayerId, cp.fromRealPlayer AS fromRealPlayer,
      cp.customAvatarFilePath AS customAvatarFilePath,
      cp.nationalityId AS nationalityId, cp.birthdate AS birthdate
    FROM NationalTeamPlayer np JOIN CustomCreatedPlayer cp
      ON cp.id = np.playerId AND cp.personId = np.personId
    WHERE np.personId = ? AND np.seasonId = ?
    ORDER BY np.isBench, np.shirtNumber, cp.name
  ''',
      [personId, seasonId],
    );
    return _withCurrentOveralls(db, rows, personId);
  }

  Future<void> trimStartingEleven(String personId, String seasonId) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = (await txn.rawQuery(
        '''
        SELECT tp.id, tp.x, tp.y, tp.overall, cp.positionId
        FROM TeamPlayer tp
        LEFT JOIN CustomCreatedPlayer cp
          ON cp.id = tp.playerId AND cp.personId = tp.personId
        WHERE tp.personId = ? AND tp.seasonId = ? AND tp.isBench = 0
      ''',
        [personId, seasonId],
      )).toList();
      if (rows.length <= 11) return;
      rows.sort((a, b) {
        final placedA = a['x'] != null && a['y'] != null;
        final placedB = b['x'] != null && b['y'] != null;
        if (placedA != placedB) return placedA ? -1 : 1;
        return ((b['overall'] as num?)?.toInt() ?? 0).compareTo(
          (a['overall'] as num?)?.toInt() ?? 0,
        );
      });
      final keep = <String>{};
      for (final row in rows.where((r) => r['x'] != null && r['y'] != null)) {
        if (keep.length < 11) keep.add(row['id'] as String);
      }
      const groups = <(Set<String>, int)>[
        ({'25', '21', '27', '23'}, 3),
        ({'18', '14', '16', '12', '10'}, 3),
        ({'5', '8', '7', '2', '3'}, 4),
        ({'0'}, 1),
      ];
      for (final (positions, quota) in groups) {
        var count = rows
            .where(
              (r) =>
                  keep.contains(r['id']) && positions.contains(r['positionId']),
            )
            .length;
        for (final row in rows.where(
          (r) => positions.contains(r['positionId']),
        )) {
          if (count >= quota || keep.length >= 11) break;
          if (keep.add(row['id'] as String)) count++;
        }
      }
      for (final row in rows) {
        if (keep.length >= 11) break;
        keep.add(row['id'] as String);
      }
      for (final row in rows.where((r) => !keep.contains(r['id']))) {
        await txn.update(
          'TeamPlayer',
          {'isBench': 1, 'x': null, 'y': null},
          where: 'id = ? AND personId = ?',
          whereArgs: [row['id'], personId],
        );
      }
    });
  }

  Future<void> createCustomTeamPlayer(
    Map<String, Object?> player,
    Map<String, Object?> teamPlayer,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('CustomCreatedPlayer', player);
      await txn.insert('TeamPlayer', teamPlayer);
      await _publishSharedPlayer(txn, player);
    });
  }

  Future<void> createCustomPlayer(Map<String, Object?> player) async {
    await (await database).transaction((txn) async {
      await txn.insert('CustomCreatedPlayer', player);
      await _publishSharedPlayer(txn, player);
    });
  }

  static const _sharedPlayerFields = [
    'name',
    'positionId',
    'overall',
    'potential',
    'birthdate',
    'firstSeasonAge',
    'height',
    'weight',
    'nationalityId',
    'customAvatarFilePath',
    'foot',
  ];

  static Future<void> ensureSharedPlayerSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS CustomPlayerTemplate(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, dataJson TEXT NOT NULL,
      createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL)''');
    final columns = await db.rawQuery('PRAGMA table_info(CustomCreatedPlayer)');
    if (!columns.any((r) => r['name'] == 'libraryPlayerId')) {
      await db.execute(
        'ALTER TABLE CustomCreatedPlayer ADD COLUMN libraryPlayerId TEXT',
      );
    }
  }

  static Future<void> seedSharedPlayers(DatabaseExecutor db) async {
    final rows = await db.rawQuery('''SELECT cp.* FROM CustomCreatedPlayer cp
      LEFT JOIN CustomPlayerTemplate lib ON lib.id = COALESCE(cp.libraryPlayerId, cp.id)
      WHERE cp.realPlayerId IS NULL AND cp.fromRealPlayer = 0
        AND (cp.libraryPlayerId IS NULL OR lib.id IS NULL)''');
    for (final personId in rows.map((r) => r['personId'] as String).toSet()) {
      final current = await _withCurrentOveralls(
        db,
        rows.where((r) => r['personId'] == personId).toList(),
        personId,
      );
      for (final player in current) {
        await _publishSharedPlayer(db, player);
      }
    }
  }

  static Future<Map<String, Object?>> _sharedData(
    Map<String, Object?> player,
  ) async {
    final data = <String, Object?>{
      for (final key in _sharedPlayerFields)
        if (player.containsKey(key)) key: player[key],
    };
    final avatar = data['customAvatarFilePath'] as String?;
    final id = (player['libraryPlayerId'] ?? player['id']) as String;
    if (avatar != null && !avatar.startsWith('/faces/library/$id/')) {
      await CustomImageFiles.docsDir();
      final absolute = CustomImageFiles.absolute(avatar);
      if (absolute != null && await File(absolute).exists()) {
        data['customAvatarFilePath'] = await CustomImageFiles.store(
          absolute,
          'faces',
          'library/$id',
        );
      }
    }
    return data;
  }

  static Future<void> _publishSharedPlayer(
    DatabaseExecutor db,
    Map<String, Object?> player,
  ) async {
    if (player['realPlayerId'] != null || player['fromRealPlayer'] == 1) return;
    final id = (player['libraryPlayerId'] ?? player['id']) as String;
    final now = DateTime.now().toIso8601String();
    final existing = await db.query(
      'CustomPlayerTemplate',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (existing.isEmpty) {
      await db.insert('CustomPlayerTemplate', {
        'id': id,
        'name': player['name'],
        'dataJson': jsonEncode(await _sharedData(player)),
        'createdAt': now,
        'updatedAt': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await db.update(
      'CustomCreatedPlayer',
      {'libraryPlayerId': id},
      where: 'id = ? AND personId = ?',
      whereArgs: [player['id'], player['personId']],
    );
  }

  Future<List<Map<String, Object?>>> getSharedPlayers() async {
    final db = await database;
    await db.transaction(seedSharedPlayers);
    return [
      for (final row in await db.query(
        'CustomPlayerTemplate',
        orderBy: 'name COLLATE NOCASE',
      ))
        {
          ...Map<String, Object?>.from(
            jsonDecode(row['dataJson'] as String) as Map,
          ),
          'id': row['id'],
          'name': row['name'],
        },
    ];
  }

  Future<void> saveSharedPlayer(Map<String, Object?> player) async {
    final data = await _sharedData(player);
    if ((data['name'] as String?)?.trim().isEmpty ?? true) {
      throw ArgumentError('Informe o nome do jogador.');
    }
    final db = await database;
    final id = player['id'] as String;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'CustomPlayerTemplate',
        where: 'id = ?',
        whereArgs: [id],
      );
      final values = {
        'id': id,
        'name': data['name'],
        'dataJson': jsonEncode(data),
        'createdAt': rows.firstOrNull?['createdAt'] ?? now,
        'updatedAt': now,
      };
      if (rows.isEmpty) {
        await txn.insert('CustomPlayerTemplate', values);
      } else {
        await txn.update(
          'CustomPlayerTemplate',
          values,
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  Future<Map<String, Object?>> useSharedPlayer({
    required String personId,
    required String templateId,
    String? seasonId,
  }) async {
    final db = await database;
    String? copiedAvatar;
    var saved = false;
    try {
      final result = await db.transaction((txn) async {
        final existing = await txn.query(
          'CustomCreatedPlayer',
          where: 'personId = ? AND (libraryPlayerId = ? OR id = ?)',
          whereArgs: [personId, templateId, templateId],
          limit: 1,
        );
        Map<String, Object?> player;
        if (existing.isNotEmpty) {
          player = (await _withCurrentOveralls(txn, existing, personId)).single;
        } else {
          final rows = await txn.query(
            'CustomPlayerTemplate',
            where: 'id = ?',
            whereArgs: [templateId],
          );
          if (rows.isEmpty) {
            throw StateError('Jogador personalizado não encontrado.');
          }
          final data = Map<String, Object?>.from(
            jsonDecode(rows.single['dataJson'] as String) as Map,
          );
          final id = const Uuid().v4();
          final avatar = data['customAvatarFilePath'] as String?;
          if (avatar != null) {
            await CustomImageFiles.docsDir();
            final absolute = CustomImageFiles.absolute(avatar);
            if (absolute != null && await File(absolute).exists()) {
              copiedAvatar = await CustomImageFiles.store(
                absolute,
                'faces',
                '$personId/$id',
              );
              data['customAvatarFilePath'] = copiedAvatar;
            }
          }
          player = {
            ...data,
            'id': id,
            'personId': personId,
            'libraryPlayerId': templateId,
            'realPlayerId': null,
            'realFace': 0,
            'fromRealPlayer': 0,
            'foot': data['foot'] ?? 'Right',
          };
          await txn.insert('CustomCreatedPlayer', player);
        }
        if (seasonId != null) {
          final seasons = await txn.query(
            'Seasons',
            columns: ['id'],
            where: 'id = ? AND personId = ?',
            whereArgs: [seasonId, personId],
          );
          if (seasons.isEmpty) {
            throw StateError('A temporada não pertence a esta carreira.');
          }
          final roster = await txn.query(
            'TeamPlayer',
            columns: ['id'],
            where: 'personId = ? AND seasonId = ? AND playerId = ?',
            whereArgs: [personId, seasonId, player['id']],
          );
          if (roster.isEmpty) {
            final count =
                Sqflite.firstIntValue(
                  await txn.rawQuery(
                    'SELECT COUNT(*) FROM TeamPlayer WHERE personId = ? AND seasonId = ? AND isBench = 0',
                    [personId, seasonId],
                  ),
                ) ??
                0;
            await txn.insert('TeamPlayer', {
              'id': const Uuid().v4(),
              'personId': personId,
              'seasonId': seasonId,
              'playerId': player['id'],
              'overall': player['overall'],
              'isBench': count >= 11 ? 1 : 0,
            });
          }
        }
        return player;
      });
      saved = true;
      return result;
    } finally {
      if (!saved && copiedAvatar != null) {
        await CustomImageFiles.deleteFile(copiedAvatar);
      }
    }
  }

  Future<List<Map<String, Object?>>> getCustomPlayers(
    String personId, {
    Set<String>? playerIds,
    bool includeCurrentOverall = true,
  }) async {
    if (playerIds != null && playerIds.isEmpty) return [];
    final db = await database;
    final rows = <Map<String, Object?>>[];
    if (playerIds == null) {
      rows.addAll(
        await db.query(
          'CustomCreatedPlayer',
          where: 'personId = ?',
          whereArgs: [personId],
        ),
      );
    } else {
      final ids = playerIds.toList();
      for (var i = 0; i < ids.length; i += 400) {
        final batch = ids.sublist(i, min(i + 400, ids.length));
        rows.addAll(
          await db.query(
            'CustomCreatedPlayer',
            where:
                'personId = ? AND id IN (${List.filled(batch.length, '?').join(',')})',
            whereArgs: [personId, ...batch],
          ),
        );
      }
    }
    return includeCurrentOverall
        ? _withCurrentOveralls(db, rows, personId)
        : rows;
  }

  Future<Map<String, Object?>?> getCustomPlayerById(
    String personId,
    String playerId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'CustomCreatedPlayer',
      where: 'id = ? AND personId = ?',
      whereArgs: [playerId, personId],
      limit: 1,
    );
    return (await _withCurrentOveralls(db, rows, personId)).firstOrNull;
  }

  Future<List<Map<String, Object?>>> getPlayerSeasonRows(
    String personId,
    String playerId,
  ) async {
    final db = await database;
    await db.transaction(
      (txn) => SeasonRosterService.repairPendingValues(txn, personId: personId),
    );
    final active = await db.rawQuery(
      '''
    SELECT tp.*, s.startDate AS seasonStartDate, s.endDate AS seasonEndDate,
      s.createdAt AS seasonCreatedAt
    FROM TeamPlayer tp JOIN Seasons s
      ON s.id = tp.seasonId AND s.personId = tp.personId
    WHERE tp.personId = ? AND tp.playerId = ?
    ORDER BY s.startDate DESC
    ''',
      [personId, playerId],
    );
    return _includeDepartedRoster(db, active, personId, playerId: playerId);
  }

  Future<void> updatePlayerConfiguration({
    required String personId,
    required String playerId,
    required Map<String, Object?> general,
    required List<Map<String, Object?>> seasons,
  }) async {
    await (await database).transaction((txn) async {
      final updated = await txn.update(
        'CustomCreatedPlayer',
        {
          for (final key in const [
            'name',
            'positionId',
            'potential',
            'height',
            'weight',
            'foot',
            'firstSeasonAge',
            'birthdate',
            'nationalityId',
            'customAvatarFilePath',
          ])
            if (general.containsKey(key)) key: general[key],
        },
        where: 'id = ? AND personId = ?',
        whereArgs: [playerId, personId],
      );
      if (updated != 1) {
        throw StateError('Jogador não encontrado nesta carreira.');
      }
      for (final season in seasons) {
        final count = await txn.update(
          'TeamPlayer',
          {
            for (final key in const [
              'overall',
              'shirtNumber',
              'marketValue',
              'loanStatus',
            ])
              if (season.containsKey(key)) key: season[key],
          },
          where: 'id = ? AND personId = ? AND playerId = ? AND seasonId = ?',
          whereArgs: [season['id'], personId, playerId, season['seasonId']],
        );
        if (count != 1) {
          final archived = await txn.query(
            'TeamPlayerDeparture',
            where: 'rosterId = ? AND personId = ? AND playerId = ? AND seasonId = ?',
            whereArgs: [season['id'], personId, playerId, season['seasonId']],
            orderBy: 'departureDate DESC, rowid DESC',
            limit: 1,
          );
          if (archived.isEmpty) {
            throw StateError('Elenco da temporada não encontrado.');
          }
          final snapshot = Map<String, Object?>.from(
            jsonDecode(archived.first['rosterJson'] as String) as Map,
          );
          for (final key in [
            'overall',
            'shirtNumber',
            'marketValue',
            'loanStatus',
          ]) {
            if (season.containsKey(key)) snapshot[key] = season[key];
          }
          await txn.update(
            'TeamPlayerDeparture',
            {'rosterJson': jsonEncode(snapshot)},
            where: 'id = ? AND personId = ?',
            whereArgs: [archived.first['id'], personId],
          );
        }
      }
    });
  }

  Future<List<Map<String, Object?>>> getComparisonPlayerRows(
    String personId,
  ) async {
    final db = await database;
    await db.transaction((txn) => _applyDueTeamTransfers(txn, personId));
    final active = await db.rawQuery(
      '''
    SELECT tp.*, s.startDate AS seasonStartDate, s.endDate AS seasonEndDate,
      s.createdAt AS seasonCreatedAt
    FROM TeamPlayer tp JOIN Seasons s
      ON s.id = tp.seasonId AND s.personId = tp.personId
    WHERE tp.personId = ?
    ORDER BY s.startDate DESC, tp.rowid DESC
    ''',
      [personId],
    );
    final roster = await _includeDepartedRoster(db, active, personId);
    final memberships = <(String, String), Map<String, Object?>>{};
    for (final row in roster) {
      if (row['playerId'] case final String id) {
        memberships.putIfAbsent((id, '${row['seasonId']}'), () => row);
      }
    }
    final played = await db.rawQuery(
      '''
      SELECT DISTINCT p.playerInstanceId AS playerId, f.seasonId,
        s.startDate AS seasonStartDate, s.endDate AS seasonEndDate,
        s.createdAt AS seasonCreatedAt
      FROM ManagerFixturePlayerPerformances p
      JOIN ManagerFixtures f ON f.id = p.fixtureId AND f.personId = p.personId
      JOIN Seasons s ON s.id = f.seasonId AND s.personId = f.personId
      WHERE p.personId = ?
    ''',
      [personId],
    );
    for (final row in played) {
      if (row['playerId'] case final String id) {
        memberships.putIfAbsent((
          id,
          '${row['seasonId']}',
        ), () => {...row, 'id': 'comparison:$id:${row['seasonId']}'});
      }
    }
    final identities = {
      for (final player in await getCustomPlayers(
        personId,
        playerIds: {for (final key in memberships.keys) key.$1},
        includeCurrentOverall: false,
      ))
        player['id']: player,
    };
    final rows = <Map<String, Object?>>[
      for (final row in memberships.values)
        if (identities[row['playerId']] case final player?)
          {
            ...row,
            'rosterId': row['id'],
            'customName': player['name'],
            'customPositionId': player['positionId'],
            'initialOverall': player['overall'],
            for (final field in [
              'realPlayerId',
              'customAvatarFilePath',
              'birthdate',
              'firstSeasonAge',
              'nationalityId',
              'foot',
            ])
              field: player[field],
            'playerHeight': player['height'],
            'playerWeight': player['weight'],
          },
    ];
    return _withCurrentOveralls(db, rows, personId, seasonRows: rows);
  }

  Future<String> addRealTeamPlayer({
    required String personId,
    required String seasonId,
    required GamePlayer player,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final existing = await txn.query(
        'CustomCreatedPlayer',
        columns: ['id'],
        where: 'personId = ? AND realPlayerId = ?',
        whereArgs: [personId, player.id],
        limit: 1,
      );
      final playerId = existing.isNotEmpty
          ? existing.first['id'] as String
          : const Uuid().v1();
      if (existing.isEmpty) {
        await txn.insert(
          'CustomCreatedPlayer',
          _realPlayerRow(playerId, personId, player),
        );
      }
      await txn.insert('TeamPlayer', {
        'id': const Uuid().v1(),
        'personId': personId,
        'playerId': playerId,
        'seasonId': seasonId,
        'overall': player.overall,
        'isBench':
            (Sqflite.firstIntValue(
                      await txn.rawQuery(
                        'SELECT COUNT(*) FROM TeamPlayer WHERE personId = ? AND seasonId = ? AND isBench = 0',
                        [personId, seasonId],
                      ),
                    ) ??
                    0) >=
                11
            ? 1
            : 0,
      });
      return playerId;
    });
  }

  static Map<String, Object?> _realPlayerRow(
    String id,
    String personId,
    GamePlayer? player, {
    String? realPlayerId,
  }) => {
    'id': id,
    'personId': personId,
    'realPlayerId': player?.id ?? realPlayerId,
    'name': player?.name ?? realPlayerId ?? '',
    'positionId': player?.mainPositionId ?? '14',
    'overall': player?.overall ?? 0,
    'potential': player?.potential ?? player?.overall ?? 0,
    'birthdate': player?.birthdate?.millisecondsSinceEpoch,
    'firstSeasonAge': player?.age,
    'height': player?.height,
    'weight': player?.weight,
    'nationalityId': null,
    'realFace': player?.realFace == false ? 0 : 1,
    'fromRealPlayer': 1,
    'customAvatarFilePath': null,
    'foot': player?.foot ?? 'Right',
  };

  Future<void> updateTeamPlayer(Map<String, Object?> row) async {
    await (await database).update(
      'TeamPlayer',
      row,
      where: 'id = ? AND personId = ?',
      whereArgs: [row['id'], row['personId']],
    );
  }

  Future<void> setTeamPlayerPlacement({
    required String personId,
    required String playerId,
    required bool reserve,
    String? replacePlayerId,
    ({int x, int y})? targetPosition,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final seasonId =
          (await txn.query(
                'TeamPlayer',
                columns: ['seasonId'],
                where: 'id = ? AND personId = ?',
                whereArgs: [playerId, personId],
                limit: 1,
              )).firstOrNull?['seasonId']
              as String?;
      if (seasonId == null) throw StateError('Jogador não encontrado');
      await SquadLineup.ensure(txn, personId, seasonId);
      int? replacementX;
      int? replacementY;
      if (!reserve) {
        final player = await txn.query(
          'TeamPlayer',
          columns: ['seasonId'],
          where: 'id = ? AND personId = ?',
          whereArgs: [playerId, personId],
          limit: 1,
        );
        if (player.isEmpty) throw StateError('Jogador não encontrado');
        final starters =
            Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COUNT(*) FROM TeamPlayer WHERE personId = ? AND seasonId = ? AND isBench = 0',
                [personId, player.first['seasonId']],
              ),
            ) ??
            0;
        if (starters >= 11 && replacePlayerId == null) {
          throw StateError('Escolha um titular para substituir');
        }
        if (replacePlayerId != null) {
          final replacement = await txn.query(
            'TeamPlayer',
            columns: ['x', 'y'],
            where: 'id = ? AND personId = ? AND seasonId = ? AND isBench = 0',
            whereArgs: [replacePlayerId, personId, player.first['seasonId']],
            limit: 1,
          );
          if (replacement.isEmpty) {
            throw StateError('Titular para substituir não encontrado');
          }
          replacementX = replacement.first['x'] as int?;
          replacementY = replacement.first['y'] as int?;
          await txn.update(
            'TeamPlayer',
            {'isBench': 1, 'x': null, 'y': null},
            where: 'id = ? AND personId = ? AND seasonId = ?',
            whereArgs: [replacePlayerId, personId, player.first['seasonId']],
          );
        }
      }
      await txn.update(
        'TeamPlayer',
        {
          'isBench': reserve ? 1 : 0,
          'x': reserve ? null : targetPosition?.x ?? replacementX,
          'y': reserve ? null : targetPosition?.y ?? replacementY,
        },
        where: 'id = ? AND personId = ?',
        whereArgs: [playerId, personId],
      );
    });
  }

  Future<void> setLineupPositions(
    String personId,
    Map<String, ({int x, int y})> positions, {
    String? seasonId,
    String? formation,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      if (formation != null && seasonId != null) {
        await SquadLineup.save(txn, personId, seasonId, formation);
      }
      for (final entry in positions.entries) {
        await txn.update(
          'TeamPlayer',
          {'x': entry.value.x, 'y': entry.value.y},
          where:
              'id = ? AND personId = ? AND isBench = 0${seasonId == null ? '' : ' AND seasonId = ?'}',
          whereArgs: [entry.key, personId, ?seasonId],
        );
      }
    });
  }

  Future<String> getSquadFormation(String personId, String seasonId) async {
    final db = await database;
    await SquadLineup.ensureSchema(db);
    final row = (await db.query(
      'SquadLineup',
      where: 'personId = ? AND seasonId = ?',
      whereArgs: [personId, seasonId],
      limit: 1,
    )).firstOrNull;
    return row?['formation'] as String? ??
        await db.transaction(
          (txn) =>
              SquadLineup.ensure(txn, personId, seasonId, materialize: false),
        );
  }

  Future<List<Map<String, Object?>>> getPendingPlayerTransfers(
    Person person,
    String playerId, {
    required String seasonId,
  }) async {
    final rows = await (await database).query(
      'TeamTransferItem',
      where:
          'personId = ? AND playerInstanceId = ? AND seasonId = ? '
          'AND fromTeamId = ? AND movementApplied = 0 AND releaseDate IS NOT NULL',
      whereArgs: [person.id, playerId, seasonId, person.teamId],
      orderBy: 'releaseDate, date',
    );
    return rows
        .where(
          (row) =>
              !isIncomingTeamTransfer(row, person.teamId) &&
              DateTime.tryParse('${row['releaseDate']}') != null,
        )
        .toList();
  }

  Future<Map<String, Object?>?> removeTeamPlayer(
    String personId,
    String id, {
    String? transferId,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'TeamPlayer',
        where: 'id = ? AND personId = ?',
        whereArgs: [id, personId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.first;
      await SquadLineup.ensure(txn, personId, row['seasonId'] as String);
      final persons = await txn.query(
        'Persons',
        where: 'id = ?',
        whereArgs: [personId],
        limit: 1,
      );
      if (persons.isEmpty) throw StateError('Carreira não encontrada.');
      final person = persons.first;
      final date = (await _transferGameDate(txn, personId) ?? DateTime.now())
          .toIso8601String();
      Map<String, Object?>? movement;
      if (transferId != null) {
        final transfers = await txn.query(
          'TeamTransferItem',
          where:
              'id = ? AND personId = ? AND playerInstanceId = ? AND seasonId = ? '
              'AND fromTeamId = ? AND movementApplied = 0 AND releaseDate IS NOT NULL',
          whereArgs: [
            transferId,
            personId,
            row['playerId'],
            row['seasonId'],
            person['teamId'],
          ],
          limit: 1,
        );
        if (transfers.isEmpty ||
            isIncomingTeamTransfer(
              transfers.first,
              person['teamId'] as String,
            ) ||
            DateTime.tryParse('${transfers.first['releaseDate']}') == null) {
          throw StateError(
            'Esta transferência não está mais disponível para a saída deste jogador.',
          );
        }
        movement = {
          ...transfers.first,
          'actualReleaseDate': date,
          'movementApplied': 1,
          'keepInSquad': 0,
        };
        await txn.update(
          'TeamTransferItem',
          {'actualReleaseDate': date, 'movementApplied': 1, 'keepInSquad': 0},
          where: 'id = ? AND personId = ?',
          whereArgs: [transferId, personId],
        );
      }
      final departure = await _archiveRosterRow(
        txn,
        row,
        teamId: person['teamId'] as String,
        leagueId: person['leagueId'] as String?,
        date: date,
        movement: movement,
      );
      await txn.delete(
        'TeamPlayer',
        where: 'id = ? AND personId = ?',
        whereArgs: [id, personId],
      );
      return departure;
    });
  }

  static Future<Map<String, Object?>> _archiveRosterRow(
    DatabaseExecutor db,
    Map<String, Object?> row, {
    required String teamId,
    String? leagueId,
    required String date,
    Map<String, Object?>? movement,
  }) async {
    final record = <String, Object?>{
      'id': const Uuid().v4(),
      'rosterId': row['id'],
      'personId': row['personId'],
      'playerId': row['playerId'],
      'seasonId': row['seasonId'],
      'teamId': teamId,
      'leagueId': leagueId,
      'departureDate': date,
      'transferId': movement?['id'],
      'rosterJson': jsonEncode(row),
      'transferJson': movement == null
          ? null
          : jsonEncode({...movement, 'actualReleaseDate': date}),
    };
    await db.insert('TeamPlayerDeparture', record);
    return record;
  }

  Future<List<Map<String, Object?>>> getTeamTransfers(
    String personId, {
    String? seasonId,
  }) async {
    final db = await database;
    await db.transaction((txn) => _applyDueTeamTransfers(txn, personId));
    return db.query(
      'TeamTransferItem',
      where: seasonId == null
          ? 'personId = ?'
          : 'personId = ? AND seasonId = ?',
      whereArgs: seasonId == null ? [personId] : [personId, seasonId],
      orderBy: 'date DESC, rowid DESC',
    );
  }

  static Future<DateTime?> _transferGameDate(
    DatabaseExecutor db,
    String personId,
  ) async {
    final dates = await db.rawQuery(
      '''
      SELECT date FROM (
        SELECT date FROM ManagerFixtures WHERE personId = ?
        UNION ALL SELECT date FROM PlayerFixtures WHERE personId = ?
      ) ORDER BY julianday(date) DESC LIMIT 1
    ''',
      [personId, personId],
    );
    final lastMatch = DateTime.tryParse(
      dates.firstOrNull?['date']?.toString() ?? '',
    );
    final seasons = await db.query(
      'Seasons',
      columns: ['startDate'],
      where: 'personId = ?',
      whereArgs: [personId],
      orderBy: 'startDate DESC',
      limit: 1,
    );
    final seasonStart = DateTime.tryParse(
      seasons.firstOrNull?['startDate']?.toString() ?? '',
    );
    if (lastMatch == null) return seasonStart;
    return seasonStart != null && seasonStart.isAfter(lastMatch)
        ? seasonStart
        : lastMatch;
  }

  static Future<void> _applyDueTeamTransfers(
    DatabaseExecutor db,
    String personId,
  ) async {
    final date = await _transferGameDate(db, personId);
    if (date == null) return;
    final pending = await db.query(
      'TeamTransferItem',
      where: 'personId = ? AND movementApplied = 0 AND date(releaseDate) <= date(?)',
      whereArgs: [personId, date.toIso8601String()],
      orderBy: 'releaseDate, date, rowid',
    );
    if (pending.isEmpty) return;
    final persons = await db.query(
      'Persons',
      columns: ['teamId'],
      where: 'id = ?',
      whereArgs: [personId],
      limit: 1,
    );
    if (persons.isEmpty) return;
    for (final row in pending) {
      final seasons = await db.query(
        'Seasons',
        columns: ['id'],
        where: 'personId = ? AND date(startDate) <= date(?) AND date(endDate) >= date(?)',
        whereArgs: [personId, row['releaseDate'], row['releaseDate']],
        orderBy: 'startDate DESC',
        limit: 1,
      );
      await _applyTeamTransfer(db, {
        ...row,
        'date': row['releaseDate'],
        'seasonId': seasons.firstOrNull?['id'] ?? row['seasonId'],
      }, persons.first['teamId'] as String);
      await db.update(
        'TeamTransferItem',
        {'movementApplied': 1},
        where: 'id = ? AND personId = ?',
        whereArgs: [row['id'], personId],
      );
    }
  }

  Future<void> saveTeamTransfer(
    Map<String, Object?> row, {
    bool update = false,
    GamePlayer? realPlayer,
    Map<String, Object?>? included,
    GamePlayer? includedRealPlayer,
    bool keepInSquad = false,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final personId = row['personId'] as String;
      final person = await txn.query(
        'Persons',
        columns: ['teamId'],
        where: 'id = ?',
        whereArgs: [personId],
        limit: 1,
      );
      final season = await txn.query(
        'Seasons',
        columns: ['id'],
        where: 'id = ? AND personId = ?',
        whereArgs: [row['seasonId'], personId],
        limit: 1,
      );
      if (person.isEmpty || season.isEmpty) {
        throw StateError('Carreira ou temporada não encontrada.');
      }

      Future<Map<String, Object?>> resolve(
        Map<String, Object?> item,
        GamePlayer? real,
      ) async {
        var playerId = item['playerInstanceId'] as String;
        if (real != null) {
          final existing = await txn.query(
            'CustomCreatedPlayer',
            columns: ['id'],
            where: 'personId = ? AND realPlayerId = ?',
            whereArgs: [personId, real.id],
            limit: 1,
          );
          playerId =
              existing.firstOrNull?['id'] as String? ?? const Uuid().v4();
          if (existing.isEmpty) {
            final nationality = GameCatalog.current?.nationalities
                .where(
                  (item) =>
                      item.id == real.nationalityCode ||
                      item.label.toLowerCase() ==
                          real.nationalityName?.toLowerCase(),
                )
                .firstOrNull;
            await txn.insert('CustomCreatedPlayer', {
              ..._realPlayerRow(playerId, personId, real),
              'nationalityId': nationality?.id ?? real.nationalityCode,
            });
          }
        }
        final player = await txn.query(
          'CustomCreatedPlayer',
          columns: ['id'],
          where: 'id = ? AND personId = ?',
          whereArgs: [playerId, personId],
          limit: 1,
        );
        if (player.isEmpty) {
          throw StateError('Jogador não encontrado nesta carreira.');
        }
        return {...item, 'playerInstanceId': playerId};
      }

      final saved = await resolve(row, realPlayer);
      final agreement = DateTime.tryParse(saved['date']?.toString() ?? '');
      final release = DateTime.tryParse(saved['releaseDate']?.toString() ?? '');
      if (saved['releaseDate'] != null &&
          (release == null ||
              agreement == null ||
              DateTime(release.year, release.month, release.day).isBefore(
                DateTime(agreement.year, agreement.month, agreement.day),
              ))) {
        throw StateError('A liberação não pode ser anterior ao acordo.');
      }
      final previous = update
          ? (await txn.query(
              'TeamTransferItem',
              where: 'id = ? AND personId = ?',
              whereArgs: [saved['id'], personId],
              limit: 1,
            )).firstOrNull
          : null;
      final gameDate = await _transferGameDate(txn, personId) ?? agreement!;
      if (previous?['actualReleaseDate'] != null &&
          previous?['playerInstanceId'] == saved['playerInstanceId'] &&
          previous?['fromTeamId'] == saved['fromTeamId']) {
        saved['actualReleaseDate'] = previous!['actualReleaseDate'];
      }
      final pending =
          saved['actualReleaseDate'] == null &&
          release != null &&
          DateTime(
            release.year,
            release.month,
            release.day,
          ).isAfter(DateTime(gameDate.year, gameDate.month, gameDate.day));
      saved['movementApplied'] = pending ? 0 : 1;
      saved['keepInSquad'] = release != null
          ? 0
          : (update ? (previous?['keepInSquad'] ?? 0) : (keepInSquad ? 1 : 0));
      final exchange = included == null
          ? null
          : await resolve(included, includedRealPlayer);
      if (exchange != null) {
        final previousExchange = update
            ? (await txn.query(
                'TeamTransferItem',
                where: 'id = ? AND personId = ? AND playerInstanceId = ?',
                whereArgs: [
                  exchange['id'],
                  personId,
                  exchange['playerInstanceId'],
                ],
                limit: 1,
              )).firstOrNull
            : null;
        if (previousExchange?['actualReleaseDate'] != null) {
          exchange['actualReleaseDate'] =
              previousExchange!['actualReleaseDate'];
        }
        exchange['movementApplied'] =
            pending && exchange['actualReleaseDate'] == null ? 0 : 1;
        exchange['keepInSquad'] = 0;
      }
      if (exchange != null &&
          exchange['playerInstanceId'] == saved['playerInstanceId']) {
        throw StateError(
          'O jogador incluído deve ser diferente do jogador transferido.',
        );
      }
      if (update) {
        final count = await txn.update(
          'TeamTransferItem',
          saved,
          where: 'id = ? AND personId = ?',
          whereArgs: [row['id'], personId],
        );
        if (count != 1) throw StateError('Transferência não encontrada.');
      } else {
        await txn.insert('TeamTransferItem', saved);
      }
      await txn.delete(
        'TeamTransferItem',
        where: 'id = ? AND personId = ?',
        whereArgs: ['${row['id']}:exchange', personId],
      );
      if (exchange != null) await txn.insert('TeamTransferItem', exchange);

      final teamId = person.first['teamId'] as String;
      if (pending) {
        if (previous != null &&
            previous['playerInstanceId'] == saved['playerInstanceId'] &&
            saved['fromTeamId'] == teamId &&
            !isIncomingTeamTransfer(previous, teamId) &&
            !isIncomingTeamTransfer(saved, teamId)) {
          final roster = await txn.query(
            'TeamPlayer',
            columns: ['id'],
            where: 'personId = ? AND seasonId = ? AND playerId = ?',
            whereArgs: [personId, saved['seasonId'], saved['playerInstanceId']],
            limit: 1,
          );
          if (roster.isEmpty) {
            await _applyTeamTransfer(txn, {
              ...saved,
              'type': TeamTransferType.buy.name,
              'toTeamId': teamId,
              'wage': null,
              'yearlyWage': null,
            }, teamId);
          } else if (transferTypeFromRow(previous) ==
              TeamTransferType.outLoan) {
            await txn.update(
              'TeamPlayer',
              {'loanStatus': null},
              where: 'id = ?',
              whereArgs: [roster.first['id']],
            );
          }
        }
      } else if (saved['actualReleaseDate'] == null &&
          (!update ||
              previous?['movementApplied'] == 0 ||
              (release != null &&
                  previous?['releaseDate'] != saved['releaseDate']))) {
        await _applyTeamTransfer(
          txn,
          {...saved, 'date': saved['releaseDate'] ?? saved['date']},
          teamId,
          keepInSquad: saved['keepInSquad'] == 1,
        );
        if (exchange != null && exchange['actualReleaseDate'] == null) {
          await _applyTeamTransfer(txn, {
            ...exchange,
            'date': exchange['releaseDate'] ?? exchange['date'],
          }, teamId);
        }
      }
      await _applyDueTeamTransfers(txn, personId);
    });
  }

  Future<Map<String, Object?>?> getTeamTransferExchange(
    String personId,
    String id,
  ) async {
    final rows = await (await database).query(
      'TeamTransferItem',
      where: 'id = ? AND personId = ?',
      whereArgs: ['$id:exchange', personId],
      limit: 1,
    );
    return rows.firstOrNull;
  }

  static Future<void> _applyTeamTransfer(
    DatabaseExecutor db,
    Map<String, Object?> row,
    String teamId, {
    bool keepInSquad = false,
  }) async {
    final personId = row['personId'] as String;
    final playerId = row['playerInstanceId'] as String;
    final seasonId = row['seasonId'] as String;
    const where = 'personId = ? AND seasonId = ? AND playerId = ?';
    final args = [personId, seasonId, playerId];
    final type = transferTypeFromRow(row);
    if (!isIncomingTeamTransfer(row, teamId)) {
      await SquadLineup.ensure(db, personId, seasonId);
    }
    if (type == TeamTransferType.outLoan) {
      await db.update(
        'TeamPlayer',
        {'loanStatus': 'outLoan', 'isBench': 1, 'x': null, 'y': null},
        where: where,
        whereArgs: args,
      );
      return;
    }
    final incoming = isIncomingTeamTransfer(row, teamId);
    if (!incoming) {
      if (!keepInSquad) {
        final leaving = await db.query(
          'TeamPlayer',
          where: where,
          whereArgs: args,
        );
        for (final player in leaving) {
          await _archiveRosterRow(
            db,
            player,
            teamId: teamId,
            leagueId: row['fromLeagueId'] as String?,
            date: row['date'] as String,
            movement: row,
          );
        }
        await db.delete('TeamPlayer', where: where, whereArgs: args);
      }
      return;
    }
    if (row['toTeamId'] != teamId && type != TeamTransferType.youthAcademy) {
      return;
    }
    final roster = await db.query(
      'TeamPlayer',
      where: where,
      whereArgs: args,
      limit: 1,
    );
    final changes = <String, Object?>{
      'loanStatus': type == TeamTransferType.inLoan ? 'inLoan' : null,
      if (row['wage'] != null) 'wage': row['wage'],
      if (row['yearlyWage'] != null) 'yearlyWage': row['yearlyWage'],
    };
    if (roster.isEmpty) {
      final player = await db.query(
        'CustomCreatedPlayer',
        where: 'id = ? AND personId = ?',
        whereArgs: [playerId, personId],
        limit: 1,
      );
      final previous = await db.rawQuery(
        '''SELECT tp.* FROM TeamPlayer tp
          JOIN Seasons s ON s.id = tp.seasonId AND s.personId = tp.personId
          WHERE tp.personId = ? AND tp.playerId = ? AND s.startDate <= ?
          ORDER BY s.startDate DESC LIMIT 1''',
        [personId, playerId, row['date']],
      );
      final overall = await db.query(
        'Overall',
        columns: ['overall'],
        where: 'personId = ? AND customPlayerId = ? AND date <= ?',
        whereArgs: [personId, playerId, row['date']],
        orderBy: 'date DESC, createdAt DESC',
        limit: 1,
      );
      await db.insert('TeamPlayer', {
        'id': const Uuid().v4(),
        'personId': personId,
        'playerId': playerId,
        'seasonId': seasonId,
        'overall':
            overall.firstOrNull?['overall'] ??
            previous.firstOrNull?['overall'] ??
            player.first['overall'],
        'marketValue': previous.firstOrNull?['marketValue'],
        'shirtNumber': previous.firstOrNull?['shirtNumber'],
        'wage': previous.firstOrNull?['wage'],
        'yearlyWage': previous.firstOrNull?['yearlyWage'],
        'isBench': 1,
        ...changes,
      });
    } else {
      await db.update('TeamPlayer', changes, where: where, whereArgs: args);
    }
    if (row['wage'] != null) {
      await db.insert('ContractItem', {
        'id': const Uuid().v4(),
        'personId': personId,
        'customPlayerId': playerId,
        'date': row['date'],
        'createdAt': DateTime.now().toIso8601String(),
        'wage': row['wage'],
      });
    }
  }

  Future<void> deleteTeamTransfer(String personId, String id) async {
    await (await database).delete(
      'TeamTransferItem',
      where: 'personId = ? AND (id = ? OR id = ?)',
      whereArgs: [personId, id, '$id:exchange'],
    );
  }

  Future<List<Tournament>> getCustomTournaments(String version) async {
    final rows = await (await database).query(
      'Tournament',
      where: 'fifaVersions IS NULL OR fifaVersions = ?',
      whereArgs: [version],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Tournament.fromMap).toList();
  }

  Future<void> createCustomTournament(Tournament tournament) async {
    await (await database).insert('Tournament', tournament.toMap());
  }

  Future<List<TournamentResult>> getTournamentResults(
    String personId, {
    String? seasonId,
  }) async {
    final rows = await (await database).query(
      'TournamentResult',
      where: seasonId == null
          ? 'personId = ?'
          : 'personId = ? AND seasonId = ?',
      whereArgs: seasonId == null ? [personId] : [personId, seasonId],
    );
    return rows.map(TournamentResult.fromMap).toList();
  }

  Future<void> saveTournamentResult(TournamentResult result) async {
    await (await database).insert(
      'TournamentResult',
      result.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteTournamentResult(String personId, String id) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final (parentTable, childTable, foreignKey) in [
        (
          'TournamentResultTable',
          'TournamentResultTableItem',
          'tournamentResultTableId',
        ),
        (
          'TournamentResultBracket',
          'TournamentResultBracketItem',
          'tournamentResultBracketId',
        ),
      ]) {
        final parents = await txn.query(
          parentTable,
          columns: ['id'],
          where: 'personId = ? AND tournamentResultId = ?',
          whereArgs: [personId, id],
        );
        for (final row in parents) {
          await txn.delete(
            childTable,
            where: 'personId = ? AND $foreignKey = ?',
            whereArgs: [personId, row['id']],
          );
        }
        await txn.delete(
          parentTable,
          where: 'personId = ? AND tournamentResultId = ?',
          whereArgs: [personId, id],
        );
      }
      await txn.delete(
        'TournamentResult',
        where: 'personId = ? AND id = ?',
        whereArgs: [personId, id],
      );
    });
  }

  Future<DateTime?> getLatestFixtureDate(String personId) async {
    final rows = await (await database).rawQuery(
      '''
      SELECT date FROM (
        SELECT date FROM ManagerFixtures WHERE personId = ?
        UNION ALL
        SELECT date FROM PlayerFixtures WHERE personId = ?
      )
      WHERE julianday(date) IS NOT NULL
      ORDER BY julianday(date) DESC
      LIMIT 1
      ''',
      [personId, personId],
    );
    return rows.isEmpty
        ? null
        : DateTime.tryParse(rows.first['date'].toString());
  }

  Future<List<Map<String, Object?>>> getFixtures(
    String personId,
    PersonCategory category, {
    String? seasonId,
  }) async {
    final table = category == PersonCategory.player
        ? 'PlayerFixtures'
        : 'ManagerFixtures';
    final rows = await (await database).query(
      table,
      where: seasonId == null
          ? 'personId = ?'
          : 'personId = ? AND seasonId = ?',
      whereArgs: seasonId == null ? [personId] : [personId, seasonId],
      orderBy: 'julianday(date) DESC, createdAt DESC, rowid DESC',
    );
    return FixtureTablePosition.carryForward(rows);
  }

  Future<Map<String, Object?>?> getFixture(
    PersonCategory category,
    String personId,
    String fixtureId,
  ) async {
    final table = category == PersonCategory.player
        ? 'PlayerFixtures'
        : 'ManagerFixtures';
    final rows = await (await database).query(
      table,
      where: 'id = ? AND personId = ?',
      whereArgs: [fixtureId, personId],
      limit: 1,
    );
    final row = rows.firstOrNull;
    if (row == null) return null;
    final position = await getFixtureTablePosition(category, row);
    return {...row, 'position': position.position};
  }

  Future<FixtureTablePosition> getFixtureTablePosition(
    PersonCategory category,
    Map<String, Object?> fixture,
  ) async {
    final rows = await (await database).query(
      category == PersonCategory.player ? 'PlayerFixtures' : 'ManagerFixtures',
      where: 'personId = ? AND seasonId = ? AND tournamentId = ? AND playerTeamId = ?',
      whereArgs: [
        fixture['personId'],
        fixture['seasonId'],
        fixture['tournamentId'],
        fixture['playerTeamId'],
      ],
      orderBy: 'julianday(date) DESC, createdAt DESC, rowid DESC',
    );
    return FixtureTablePosition.resolve(fixture, rows);
  }

  Future<void> createFixture(
    PersonCategory category,
    Map<String, Object?> fixture, {
    bool update = false,
  }) async {
    final table = category == PersonCategory.player
        ? 'PlayerFixtures'
        : 'ManagerFixtures';
    final db = await database;
    final position = await getFixtureTablePosition(category, fixture);
    final values = {...fixture, 'position': position.position};
    if (update) {
      await db.update(
        table,
        values,
        where: 'id = ?',
        whereArgs: [fixture['id']],
      );
    } else {
      await db.insert(table, values);
    }
    await db.transaction(
      (txn) => _applyDueTeamTransfers(txn, fixture['personId'] as String),
    );
  }

  Future<void> deleteFixture(PersonCategory category, String id) async {
    final table = category == PersonCategory.player
        ? 'PlayerFixtures'
        : 'ManagerFixtures';
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'ManagerFixturePlayerPerformances',
        where: 'fixtureId = ?',
        whereArgs: [id],
      );
      await txn.delete(table, where: 'id = ?', whereArgs: [id]);
      final apiTable = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE name = 'FcScoreImport'",
      );
      if (apiTable.isNotEmpty) {
        await txn.delete(
          'FcScoreImport',
          where: 'fixtureId = ?',
          whereArgs: [id],
        );
      }
      await txn.delete(
        'Injury',
        where: 'id LIKE ?',
        whereArgs: ['fixture:$id:%'],
      );
      await txn.delete('TwitterPosts', where: 'fixtureId = ?', whereArgs: [id]);
      await txn.delete(
        'TwitterDrafts',
        where: 'fixtureId = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'TwitterGenerations',
        where: 'fixtureId = ?',
        whereArgs: [id],
      );
    });
  }

  String _historyTable(PersonCategory category) =>
      category == PersonCategory.player
      ? 'PlayerTransferItem'
      : 'ManagerCareerHistoryItem';

  Future<List<Map<String, Object?>>> getCareerHistory(
    String personId,
    PersonCategory category,
  ) async {
    return (await database).query(
      _historyTable(category),
      where: 'personId = ?',
      whereArgs: [personId],
      orderBy: category == PersonCategory.player
          ? 'transferDate DESC'
          : 'date DESC',
    );
  }

  Future<void> saveCareerHistory(
    PersonCategory category,
    Map<String, Object?> row, {
    bool update = false,
  }) async {
    final db = await database;
    if (update) {
      await db.update(
        _historyTable(category),
        row,
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    } else {
      await db.insert(_historyTable(category), row);
    }
  }

  Future<void> deleteCareerHistory(PersonCategory category, String id) async {
    await (await database).delete(
      _historyTable(category),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, Object?>>> getTrophies(String personId) async =>
      (await database).query(
        'Trophies',
        where: 'personId = ?',
        whereArgs: [personId],
        orderBy: 'date DESC',
      );

  Future<void> saveTrophy(Trophy trophy, {bool update = false}) async {
    final db = await database;
    if (update) {
      await db.update(
        'Trophies',
        trophy.toMap(),
        where: 'id = ?',
        whereArgs: [trophy.id],
      );
    } else {
      await db.insert('Trophies', trophy.toMap());
    }
  }

  Future<void> deleteTrophy(String id) async {
    await (await database).delete('Trophies', where: 'id = ?', whereArgs: [id]);
  }
}
