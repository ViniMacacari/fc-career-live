import 'package:sqflite/sqflite.dart';

Future<void> ensureFcScoreSchema(DatabaseExecutor db) async {
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS FcScoreCareerLink(
    personId TEXT PRIMARY KEY, saveId TEXT NOT NULL, saveName TEXT,
    gameVersion TEXT NOT NULL, mappingJson TEXT NOT NULL, updatedAt TEXT NOT NULL)''',
  );
  await db.execute('''CREATE TABLE IF NOT EXISTS FcScoreImport(
    personId TEXT NOT NULL, remoteKey TEXT NOT NULL, fixtureId TEXT NOT NULL,
    saveId TEXT NOT NULL, reportId TEXT, rawJson TEXT NOT NULL, createdAt TEXT NOT NULL,
    PRIMARY KEY(personId, remoteKey))''');
  await db.execute('''CREATE TABLE IF NOT EXISTS FcScoreEndpoint(
    address TEXT PRIMARY KEY, lastConnectedAt TEXT NOT NULL)''');
  await db.execute('''CREATE TABLE IF NOT EXISTS FcScoreCompetition(
    personId TEXT NOT NULL, seasonId TEXT NOT NULL, remoteId TEXT NOT NULL,
    tournamentId TEXT NOT NULL, saveId TEXT NOT NULL, name TEXT NOT NULL,
    code TEXT, currentDate TEXT NOT NULL, importedAt TEXT NOT NULL, rawJson TEXT NOT NULL,
    PRIMARY KEY(personId, seasonId, remoteId))''');
  await db.execute('''CREATE TABLE IF NOT EXISTS FcScoreWorldTeam(
    personId TEXT NOT NULL, seasonId TEXT NOT NULL, remoteId TEXT NOT NULL,
    teamId TEXT NOT NULL, leagueId TEXT, rawJson TEXT NOT NULL,
    PRIMARY KEY(personId, seasonId, remoteId))''');
  await db.execute('''CREATE TABLE IF NOT EXISTS FcScoreWorldPlayer(
    personId TEXT NOT NULL, seasonId TEXT NOT NULL, remoteTeamId TEXT NOT NULL,
    remotePlayerId TEXT NOT NULL, playerId TEXT NOT NULL, rawJson TEXT NOT NULL,
    PRIMARY KEY(personId, seasonId, remoteTeamId, remotePlayerId))''');
  await db.execute('''CREATE TABLE IF NOT EXISTS FcScoreWorldFixture(
    personId TEXT NOT NULL, seasonId TEXT NOT NULL, remoteKey TEXT NOT NULL,
    competitionId TEXT NOT NULL, tournamentId TEXT NOT NULL,
    homeTeamId TEXT NOT NULL, awayTeamId TEXT NOT NULL, date TEXT NOT NULL,
    played INTEGER NOT NULL, rawJson TEXT NOT NULL,
    PRIMARY KEY(personId, seasonId, remoteKey))''');
  final imports = await db.rawQuery('PRAGMA table_info(FcScoreImport)');
  if (!imports.any((row) => row['name'] == 'completedByUser')) {
    await db.execute(
      'ALTER TABLE FcScoreImport ADD COLUMN completedByUser INTEGER NOT NULL DEFAULT 0',
    );
  }
  final columns = await db.rawQuery(
    'PRAGMA table_info(ManagerFixturePlayerPerformances)',
  );
  if (columns.isEmpty) return;
  final names = columns.map((row) => row['name']).toSet();
  for (final definition in [
    'recordedMinutes INTEGER',
    'recordedStarted INTEGER',
  ]) {
    if (!names.contains(definition.split(' ').first)) {
      await db.execute(
        'ALTER TABLE ManagerFixturePlayerPerformances ADD COLUMN $definition',
      );
    }
  }
}
