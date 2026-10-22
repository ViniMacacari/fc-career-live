import 'package:sqflite/sqflite.dart';

Future<void> ensureTwitterContextSchema(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(TwitterSettings)');
  if (columns.isNotEmpty && !columns.any((r) => r['name'] == 'customContext')) {
    await db.execute(
      "ALTER TABLE TwitterSettings ADD COLUMN customContext TEXT NOT NULL DEFAULT ''",
    );
  }
}

Future<void> createTwitterSchema(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS TwitterAccounts(
    id TEXT PRIMARY KEY, personId TEXT NOT NULL, name TEXT NOT NULL,
    handle TEXT NOT NULL COLLATE NOCASE, category TEXT NOT NULL,
    bio TEXT NOT NULL DEFAULT '', avatarPath TEXT, teamId TEXT, leagueId TEXT,
    supportedTeamId TEXT,
    averageLikes INTEGER, followers INTEGER NOT NULL DEFAULT 0,
    following INTEGER NOT NULL DEFAULT 0, enabled INTEGER NOT NULL DEFAULT 1,
    UNIQUE(personId, handle))''');
  final accountColumns = (await db.rawQuery(
    'PRAGMA table_info(TwitterAccounts)',
  )).map((row) => row['name']).toSet();
  if (!accountColumns.contains('supportedTeamId')) {
    await db.execute(
      'ALTER TABLE TwitterAccounts ADD COLUMN supportedTeamId TEXT',
    );
  }
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS TwitterSettings(
    personId TEXT PRIMARY KEY, enabled INTEGER NOT NULL DEFAULT 1,
    triggerMode TEXT NOT NULL DEFAULT 'everyMatch', matchInterval INTEGER NOT NULL DEFAULT 3,
    postCount INTEGER NOT NULL DEFAULT 4, replyCount INTEGER NOT NULL DEFAULT 2,
    allowProfanity INTEGER NOT NULL DEFAULT 1,
    generateTransfers INTEGER NOT NULL DEFAULT 1,
    pagePosts INTEGER NOT NULL DEFAULT 1, journalPosts INTEGER NOT NULL DEFAULT 1,
    rivalPosts INTEGER NOT NULL DEFAULT 1, createPages INTEGER NOT NULL DEFAULT 1)''',
  );
  final settingColumns = (await db.rawQuery(
    'PRAGMA table_info(TwitterSettings)',
  )).map((row) => row['name']).toSet();
  for (final column in [
    'generateTransfers',
    'pagePosts',
    'journalPosts',
    'rivalPosts',
    'createPages',
  ]) {
    if (!settingColumns.contains(column)) {
      await db.execute(
        'ALTER TABLE TwitterSettings ADD COLUMN $column INTEGER NOT NULL DEFAULT 1',
      );
    }
  }
  if (!settingColumns.contains('generateOpponentPost')) {
    await db.execute(
      'ALTER TABLE TwitterSettings ADD COLUMN generateOpponentPost INTEGER NOT NULL DEFAULT 0',
    );
  }
  await ensureTwitterContextSchema(db);
  await db.execute('''CREATE TABLE IF NOT EXISTS TwitterPosts(
    id TEXT PRIMARY KEY, personId TEXT NOT NULL, accountId TEXT NOT NULL,
    parentId TEXT, fixtureId TEXT, generationId TEXT, text TEXT NOT NULL,
    postedAt TEXT NOT NULL, createdAt TEXT NOT NULL,
    likes INTEGER NOT NULL DEFAULT 0, reposts INTEGER NOT NULL DEFAULT 0,
    liked INTEGER NOT NULL DEFAULT 0, reposted INTEGER NOT NULL DEFAULT 0,
    deleted INTEGER NOT NULL DEFAULT 0, replyTotal INTEGER NOT NULL DEFAULT 0,
    aiGenerated INTEGER NOT NULL DEFAULT 1, engagementVersion INTEGER NOT NULL DEFAULT 0,
    transferId TEXT, eventType TEXT NOT NULL DEFAULT 'match',
    sourcePostId TEXT, sourceDate TEXT)''');
  final postColumns = (await db.rawQuery('PRAGMA table_info(TwitterPosts)'))
      .map((row) => row['name'])
      .toSet();
  if (!postColumns.contains('deleted')) {
    await db.execute(
      'ALTER TABLE TwitterPosts ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
    );
  }
  if (!postColumns.contains('aiGenerated')) {
    await db.execute(
      'ALTER TABLE TwitterPosts ADD COLUMN aiGenerated INTEGER NOT NULL DEFAULT 1',
    );
    await db.execute(
      '''UPDATE TwitterPosts SET aiGenerated = 0
      WHERE id = personId || ':official:' || fixtureId
      AND accountId IN (SELECT id FROM TwitterAccounts WHERE category = 'club')''',
    );
  }
  if (!postColumns.contains('replyTotal')) {
    await db.execute(
      'ALTER TABLE TwitterPosts ADD COLUMN replyTotal INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute('''UPDATE TwitterPosts SET replyTotal = MAX(
      CASE WHEN accountId IN (SELECT id FROM TwitterAccounts WHERE category = 'club')
        THEN 5 ELSE 2 END,
      CAST((likes + reposts * 2) * (0.035 + (rowid % 17) * 0.009) AS INTEGER),
      (SELECT COUNT(*) FROM TwitterPosts c JOIN TwitterAccounts a ON a.id = c.accountId
        WHERE c.parentId = TwitterPosts.id AND c.personId = TwitterPosts.personId
        AND a.category != 'user'))''');
  }
  for (final entry in {
    'engagementVersion': 'INTEGER NOT NULL DEFAULT 0',
    'transferId': 'TEXT',
    'eventType': "TEXT NOT NULL DEFAULT 'match'",
    'sourcePostId': 'TEXT',
    'sourceDate': 'TEXT',
  }.entries) {
    if (!postColumns.contains(entry.key)) {
      await db.execute(
        'ALTER TABLE TwitterPosts ADD COLUMN ${entry.key} ${entry.value}',
      );
    }
  }
  await db.execute('''CREATE TABLE IF NOT EXISTS TwitterGenerations(
    id TEXT PRIMARY KEY, personId TEXT NOT NULL, fixtureId TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'queued', error TEXT,
    promptTokens INTEGER, completionTokens INTEGER,
    postCount INTEGER, replyCount INTEGER,
    createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL,
    transferId TEXT, eventType TEXT NOT NULL DEFAULT 'match', topic TEXT,
    eventDate TEXT, contextJson TEXT)''');
  final generationColumns = (await db.rawQuery(
    'PRAGMA table_info(TwitterGenerations)',
  )).map((row) => row['name']).toSet();
  for (final column in ['postCount', 'replyCount']) {
    if (!generationColumns.contains(column)) {
      await db.execute(
        'ALTER TABLE TwitterGenerations ADD COLUMN $column INTEGER',
      );
    }
  }
  for (final entry in {
    'transferId': 'TEXT',
    'eventType': "TEXT NOT NULL DEFAULT 'match'",
    'topic': 'TEXT',
    'eventDate': 'TEXT',
    'contextJson': 'TEXT',
  }.entries) {
    if (!generationColumns.contains(entry.key)) {
      await db.execute(
        'ALTER TABLE TwitterGenerations ADD COLUMN ${entry.key} ${entry.value}',
      );
    }
  }
  await db.execute(
    'CREATE INDEX IF NOT EXISTS twitter_transfer_events ON TwitterGenerations(personId, transferId, eventType)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS twitter_feed ON TwitterPosts(personId, parentId, postedAt DESC, createdAt DESC)',
  );
  await db.execute('''CREATE TABLE IF NOT EXISTS TwitterDrafts(
    requestId TEXT PRIMARY KEY, personId TEXT NOT NULL, fixtureId TEXT,
    generationId TEXT, parentId TEXT, snapshot TEXT NOT NULL,
    text TEXT NOT NULL, promptTokens INTEGER NOT NULL, completionTokens INTEGER NOT NULL,
    createdAt TEXT NOT NULL, consumed INTEGER NOT NULL DEFAULT 0)''');
  final draftColumns = (await db.rawQuery('PRAGMA table_info(TwitterDrafts)'))
      .map((row) => row['name'])
      .toSet();
  if (!draftColumns.contains('consumed')) {
    await db.execute(
      'ALTER TABLE TwitterDrafts ADD COLUMN consumed INTEGER NOT NULL DEFAULT 0',
    );
  }
  await db.execute(
    'CREATE INDEX IF NOT EXISTS twitter_profile ON TwitterPosts(personId, accountId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS twitter_fixture ON TwitterPosts(personId, fixtureId)',
  );
}
