import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/Person.dart';
import '../models/ManagerProfile.dart';
import '../utils/GameCatalog.dart';
import '../utils/SqlService.dart';
import 'TwitterModels.dart';
import 'TwitterPublicationDate.dart';
import 'TwitterSchema.dart';

typedef SocialRow = Map<String, Object?>;

class TwitterStore extends ChangeNotifier {
  TwitterStore._() : _database = null;
  TwitterStore.withDatabase(Database database) : _database = database;
  static final instance = TwitterStore._();
  final Database? _database;
  final Map<String, Future<void>> _initializing = {};
  Future<Database> get db async =>
      _database ?? await SqlService.instance.database;

  void changed() => notifyListeners();

  Future<void> initialize(Person person) => _initializing.putIfAbsent(
    person.id,
    () => _initialize(person).whenComplete(() {
      _initializing.remove(person.id);
    }),
  );

  Future<void> _initialize(Person person) async {
    final database = await db;
    final catalog = await GameCatalog.load();
    final profile = person.category == PersonCategory.manager
        ? ManagerProfile.decode(
            (await database.query(
              'Persons',
              columns: ['managerProfile'],
              where: 'id = ?',
              whereArgs: [person.id],
            )).firstOrNull?['managerProfile'],
          )
        : null;
    await database.transaction((txn) async {
      final rows = await txn.query(
        'TwitterSettings',
        where: 'personId = ?',
        whereArgs: [person.id],
      );
      if (rows.isEmpty) {
        await txn.insert(
          'TwitterSettings',
          const TwitterPreferences().toMap(person.id),
        );
      }
      final previousAccounts = await txn.query(
        'TwitterAccounts',
        where: 'personId = ?',
        whereArgs: [person.id],
      );
      for (final row in previousAccounts) {
        if (isLegacyExample(TwitterAccount.fromMap(row))) {
          await txn.update(
            'TwitterAccounts',
            {'enabled': 0},
            where: 'id = ? AND personId = ?',
            whereArgs: [row['id'], person.id],
          );
        }
      }
      final userId = '${person.id}:user';
      final user = await txn.query(
        'TwitterAccounts',
        where: 'id = ?',
        whereArgs: [userId],
      );
      if (user.isEmpty) {
        await txn.insert(
          'TwitterAccounts',
          TwitterAccount(
            id: userId,
            personId: person.id,
            name: profile?.displayName ?? person.name,
            handle: await _uniqueHandle(
              txn,
              person.id,
              'MC_${profile?.displayName ?? person.name}',
              userId,
            ),
            kind: TwitterAccountKind.user,
            bio: 'Minha carreira no futebol.',
          ).toMap(),
        );
      }
      final fixtureTable = person.category == PersonCategory.manager
          ? 'ManagerFixtures'
          : 'PlayerFixtures';
      final transferTable = person.category == PersonCategory.manager
          ? 'TeamTransferItem'
          : 'PlayerTransferItem';
      final careerClubs = <SocialRow>[
        {'teamId': person.teamId, 'leagueId': person.leagueId},
        ...await txn.rawQuery('''
        SELECT playerTeamId AS teamId, playerTeamLeagueId AS leagueId
          FROM $fixtureTable WHERE personId = ?
        UNION SELECT oppositeTeamId, oppositeTeamLeagueId
          FROM $fixtureTable WHERE personId = ?
        UNION SELECT fromTeamId, fromLeagueId
          FROM $transferTable WHERE personId = ?
        UNION SELECT toTeamId, toLeagueId
          FROM $transferTable WHERE personId = ?
      ''', List.filled(4, person.id)),
      ];
      final seen = <String>{};
      for (final row in careerClubs) {
        final teamId = row['teamId'] as String?;
        final leagueId = row['leagueId'] as String?;
        if (teamId == null ||
            teamId.isEmpty ||
            !seen.add('${leagueId ?? ''}:$teamId')) {
          continue;
        }
        await _ensureClub(txn, person, teamId, leagueId, catalog);
      }
      await _recalibrateEngagement(txn, person);
    });
  }

  static Future<void> _recalibrateEngagement(
    DatabaseExecutor txn,
    Person person,
  ) async {
    final pending = await txn.query(
      'TwitterPosts',
      where: 'personId = ? AND deleted = 0 AND engagementVersion < 4',
      whereArgs: [person.id],
    );
    if (pending.isEmpty) return;
    final accounts = {
      for (final row in await txn.query(
        'TwitterAccounts',
        where: 'personId = ?',
        whereArgs: [person.id],
      ))
        row['id']: TwitterAccount.fromMap(row),
    };
    final table = person.category == PersonCategory.manager
        ? 'ManagerFixtures'
        : 'PlayerFixtures';
    final fixtures = {
      for (final row in await txn.query(
        table,
        where: 'personId = ?',
        whereArgs: [person.id],
      ))
        row['id']: row,
    };
    final used = {
      for (final row in await txn.rawQuery(
        '''SELECT p.parentId, COUNT(*) AS used
        FROM TwitterPosts p JOIN TwitterAccounts a ON a.id = p.accountId
        WHERE p.personId = ? AND a.category != 'user' AND p.parentId IS NOT NULL
        GROUP BY p.parentId''',
        [person.id],
      ))
        row['parentId']: row['used'] as int,
    };
    final reserved = <Object?, int>{...used};
    for (final draft in await txn.query(
      'TwitterDrafts',
      columns: ['parentId', 'snapshot', 'text'],
      where: 'personId = ? AND parentId IS NOT NULL AND consumed = 0',
      whereArgs: [person.id],
    )) {
      try {
        final snapshot = jsonDecode(draft['snapshot'] as String) as Map;
        final output = jsonDecode(draft['text'] as String);
        final received = output is Map && output['replies'] is List
            ? (output['replies'] as List).length
            : 0;
        final base =
            snapshot['alreadyGenerated'] as int? ??
            used[draft['parentId']] ??
            0;
        reserved[draft['parentId']] = max(
          reserved[draft['parentId']] ?? 0,
          base + max(snapshot['replies'] as int? ?? 0, received),
        );
      } catch (_) {
        try {
          final snapshot = jsonDecode(draft['snapshot'] as String) as Map;
          reserved[draft['parentId']] = max(
            reserved[draft['parentId']] ?? 0,
            (snapshot['alreadyGenerated'] as int? ??
                    used[draft['parentId']] ??
                    0) +
                (snapshot['replies'] as int? ?? 0),
          );
        } catch (_) {}
      }
    }
    for (final row in pending) {
      final account = accounts[row['accountId']];
      if (account == null) continue;
      final fixture = fixtures[row['fixtureId']];
      final transfer =
          row['eventType']?.toString().startsWith('transfer') == true;
      final outcome = transfer
          ? 'transfer'
          : fixture == null
          ? 'unknown'
          : fixtureOutcome(fixture);
      final intensity = transfer
          ? eventIntensity(row)
          : fixture == null
          ? 1.0
          : eventIntensity(fixture);
      final likes = row['likes'] as int? ?? 0;
      final reposts = row['reposts'] as int? ?? 0;
      final Map<String, int> values;
      if (account.kind == TwitterAccountKind.club) {
        values = engagement(
          account,
          row['id'] as String,
          intensity: intensity,
          outcome: outcome,
          reply: row['parentId'] != null,
        );
        values['likes'] = values['likes']! + (row['liked'] == 1 ? 1 : 0);
        values['reposts'] = values['reposts']! + (row['reposted'] == 1 ? 1 : 0);
      } else {
        values = {
          'replyTotal': commentTotal(
            account,
            row['id'] as String,
            likes,
            reposts,
            outcome: outcome,
            reply: row['parentId'] != null,
            intensity: intensity,
          ),
          'engagementVersion': 4,
        };
      }
      values['replyTotal'] = max(
        values['replyTotal']!,
        reserved[row['id']] ?? 0,
      );
      await txn.update(
        'TwitterPosts',
        values,
        where: 'id = ? AND personId = ?',
        whereArgs: [row['id'], person.id],
      );
    }
  }

  static bool isLegacyExample(TwitterAccount account) {
    if (!account.id.endsWith(':default:${account.kind.name}') ||
        account.avatarPath != null ||
        account.averageLikes != null) {
      return false;
    }
    return switch (account.kind) {
      TwitterAccountKind.journal =>
        account.name == 'Central do Futebol' &&
            account.handle.startsWith('CentralFutebol') &&
            account.bio == 'Resultados e análises do futebol.',
      TwitterAccountKind.fanPage =>
        account.name == 'Voz da Torcida' &&
            account.handle.startsWith('VozDaTorcida') &&
            account.bio.startsWith('Página de torcedores de '),
      TwitterAccountKind.fan =>
        account.name == 'Torcedor 01' &&
            account.handle.startsWith('Torcedor01') &&
            account.bio == 'Na arquibancada em todos os jogos.',
      TwitterAccountKind.rival =>
        account.name == 'Rival 01' &&
            account.handle.startsWith('Rival01') &&
            account.bio == 'Torcedor rival, sempre de olho no adversário.',
      _ => false,
    };
  }

  Future<TwitterAccount> ensureClub(
    Person person,
    String teamId,
    String? leagueId,
  ) async {
    final database = await db;
    final catalog = await GameCatalog.load();
    return database.transaction(
      (txn) => _ensureClub(txn, person, teamId, leagueId, catalog),
    );
  }

  Future<TwitterAccount> _ensureClub(
    DatabaseExecutor txn,
    Person person,
    String teamId,
    String? leagueId,
    GameCatalog catalog,
  ) async {
    final resolvedLeague =
        leagueId ?? catalog.team(person.fifaVersion, teamId)?.leagueId;
    final id = '${person.id}:club:${resolvedLeague ?? ''}:$teamId';
    final legacyId = '${person.id}:club:${leagueId ?? ''}:$teamId';
    final name = catalog.teamLabel(
      person.fifaVersion,
      teamId,
      leagueId: resolvedLeague,
    );
    final again = await txn.query(
      'TwitterAccounts',
      where: 'personId = ? AND id IN (?, ?)',
      whereArgs: [person.id, id, legacyId],
    );
    if (again.isNotEmpty) {
      final previous =
          again.where((row) => row['id'] == id).firstOrNull ?? again.first;
      if (previous['name'] != name || previous['leagueId'] != resolvedLeague) {
        await txn.update(
          'TwitterAccounts',
          {'name': name, 'leagueId': resolvedLeague},
          where: 'id = ? AND personId = ?',
          whereArgs: [previous['id'], person.id],
        );
      }
      return TwitterAccount.fromMap({
        ...previous,
        'name': name,
        'leagueId': resolvedLeague,
      });
    }
    final account = TwitterAccount(
      id: id,
      personId: person.id,
      name: name,
      handle: await _uniqueHandle(
        txn,
        person.id,
        normalizeTwitterHandle(name, club: true),
        id,
      ),
      kind: TwitterAccountKind.club,
      teamId: teamId,
      leagueId: resolvedLeague,
      bio: 'Perfil oficial de $name na sua carreira.',
      followers: 250000,
      following: teamId == person.teamId && resolvedLeague == person.leagueId,
    );
    await txn.insert('TwitterAccounts', account.toMap());
    return account;
  }

  static Future<String> _uniqueHandle(
    DatabaseExecutor database,
    String personId,
    String proposed,
    String id,
  ) async {
    final base = normalizeTwitterHandle(proposed);
    var candidate = base.isEmpty ? 'Futebol' : base;
    var suffix = 1;
    while ((await database.query(
      'TwitterAccounts',
      columns: ['id'],
      where: 'personId = ? AND handle = ? COLLATE NOCASE AND id != ?',
      whereArgs: [personId, candidate, id],
      limit: 1,
    )).isNotEmpty) {
      final tail = '${++suffix}';
      candidate =
          '${(base.isEmpty ? 'Futebol' : base).substring(0, min(base.isEmpty ? 7 : base.length, 15 - tail.length))}$tail';
    }
    return candidate;
  }

  Future<List<TwitterAccount>> accounts(String personId) async =>
      (await (await db).query(
        'TwitterAccounts',
        where: 'personId = ?',
        whereArgs: [personId],
        orderBy: 'category, name COLLATE NOCASE',
      )).map(TwitterAccount.fromMap).toList();

  Future<TwitterAccount?> account(String personId, String id) async {
    final rows = await (await db).query(
      'TwitterAccounts',
      where: 'personId = ? AND id = ?',
      whereArgs: [personId, id],
      limit: 1,
    );
    return rows.isEmpty ? null : TwitterAccount.fromMap(rows.first);
  }

  Future<void> saveAccount(TwitterAccount account) async {
    final handle = normalizeTwitterHandle(account.handle);
    if (account.name.trim().isEmpty || handle.isEmpty) {
      throw const FormatException('Informe o nome e um @ válido.');
    }
    final database = await db;
    await database.transaction((txn) async {
      final occupied = await txn.query(
        'TwitterAccounts',
        columns: ['id'],
        where: 'personId = ? AND handle = ? COLLATE NOCASE AND id != ?',
        whereArgs: [account.personId, handle, account.id],
        limit: 1,
      );
      if (occupied.isNotEmpty) {
        throw const FormatException(
          'Este @ já pertence a outra conta da carreira.',
        );
      }
      final exists = await txn.query(
        'TwitterAccounts',
        columns: ['id'],
        where: 'id = ? AND personId = ?',
        whereArgs: [account.id, account.personId],
      );
      if (exists.isEmpty) {
        await txn.insert('TwitterAccounts', account.toMap());
      } else {
        await txn.update(
          'TwitterAccounts',
          account.toMap(),
          where: 'id = ? AND personId = ?',
          whereArgs: [account.id, account.personId],
        );
      }
    });
    changed();
  }

  Future<TwitterPreferences> preferences(String personId) async {
    final rows = await (await db).query(
      'TwitterSettings',
      where: 'personId = ?',
      whereArgs: [personId],
      limit: 1,
    );
    return rows.isEmpty
        ? const TwitterPreferences()
        : TwitterPreferences.fromMap(rows.first);
  }

  Future<void> savePreferences(
    String personId,
    TwitterPreferences preferences,
  ) async {
    await (await db).transaction((txn) async {
      await txn.insert(
        'TwitterSettings',
        preferences.toMap(personId),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.update(
        'TwitterSettings',
        preferences.toMap(personId),
        where: 'personId = ?',
        whereArgs: [personId],
      );
    });
    changed();
  }

  Future<String> customContext(String personId) async =>
      (await (await db).transaction((txn) async {
            await ensureTwitterContextSchema(txn);
            return txn.query(
              'TwitterSettings',
              columns: ['customContext'],
              where: 'personId = ?',
              whereArgs: [personId],
              limit: 1,
            );
          })).firstOrNull?['customContext']
          as String? ??
      '';

  Future<void> saveCustomContext(String personId, String text) async {
    final value = text.trim();
    if (value.length > 4000) {
      throw const FormatException('O contexto pode ter até 4.000 caracteres.');
    }
    await (await db).transaction((txn) async {
      await ensureTwitterContextSchema(txn);
      await txn.insert(
        'TwitterSettings',
        const TwitterPreferences().toMap(personId),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.update(
        'TwitterSettings',
        {'customContext': value},
        where: 'personId = ?',
        whereArgs: [personId],
      );
    });
    changed();
  }

  Future<void> follow(TwitterAccount account) async {
    if (account.kind == TwitterAccountKind.user) return;
    await (await db).update(
      'TwitterAccounts',
      {'following': account.following ? 0 : 1},
      where: 'id = ? AND personId = ?',
      whereArgs: [account.id, account.personId],
    );
    changed();
  }

  static const _selectPosts = '''
    SELECT p.*, a.name, a.handle, a.category, a.bio, a.avatarPath,
      a.teamId, a.leagueId, a.supportedTeamId, a.followers, a.following, a.enabled, a.averageLikes,
      (SELECT COUNT(*) FROM TwitterPosts c
        WHERE c.parentId = p.id AND c.personId = p.personId AND c.deleted = 0) AS loadedRepliesCount,
      (SELECT COUNT(*) FROM TwitterPosts c JOIN TwitterAccounts ca ON ca.id = c.accountId
        WHERE c.parentId = p.id AND c.personId = p.personId AND ca.category != 'user') AS generatedRepliesCount,
      MAX(p.replyTotal, (SELECT COUNT(*) FROM TwitterPosts c JOIN TwitterAccounts ca ON ca.id = c.accountId
        WHERE c.parentId = p.id AND c.personId = p.personId AND ca.category != 'user'))
        - (SELECT COUNT(*) FROM TwitterPosts c JOIN TwitterAccounts ca ON ca.id = c.accountId
          WHERE c.parentId = p.id AND c.personId = p.personId AND c.deleted = 1 AND ca.category != 'user')
        + (SELECT COUNT(*) FROM TwitterPosts c JOIN TwitterAccounts ca ON ca.id = c.accountId
          WHERE c.parentId = p.id AND c.personId = p.personId AND c.deleted = 0 AND ca.category = 'user') AS repliesCount
    FROM TwitterPosts p JOIN TwitterAccounts a ON a.id = p.accountId AND a.personId = p.personId
  ''';

  Future<List<SocialRow>> posts(
    String personId, {
    String? accountId,
    String? parentId,
    bool followingOnly = false,
    bool repliesOnly = false,
    bool latestReplies = false,
    String search = '',
    int? limit = 40,
    int offset = 0,
  }) async {
    final where = <String>[
      'p.personId = ?',
      'p.deleted = 0',
      "(a.category != 'club' OR p.aiGenerated = 1)",
    ];
    final args = <Object?>[personId];
    if (parentId != null) {
      where.add('p.parentId = ?');
      args.add(parentId);
    } else if (repliesOnly) {
      where.add('p.parentId IS NOT NULL');
    } else {
      where.add('p.parentId IS NULL');
    }
    if (accountId != null) {
      where.add('p.accountId = ?');
      args.add(accountId);
    }
    if (followingOnly) {
      where.add("(a.following = 1 OR a.category = 'user' OR p.reposted = 1)");
    }
    if (search.isNotEmpty) {
      where.add('(p.text LIKE ? OR a.name LIKE ? OR a.handle LIKE ?)');
      args.addAll(List.filled(3, '%$search%'));
    }
    return (await db).rawQuery(
      '$_selectPosts WHERE ${where.join(' AND ')} '
      'ORDER BY p.postedAt ${parentId == null || latestReplies ? 'DESC' : 'ASC'}, '
      '${parentId == null && !repliesOnly ? "CASE WHEN a.category = 'club' THEN 0 ELSE 1 END, " : ""}'
      'p.createdAt ${parentId == null || latestReplies ? 'DESC' : 'ASC'}, p.rowid ${parentId == null || latestReplies ? 'DESC' : 'ASC'} LIMIT ? OFFSET ?',
      [...args, limit ?? -1, offset],
    );
  }

  Future<SocialRow?> post(
    String personId,
    String id, {
    bool includeDeleted = false,
  }) async {
    final rows = await (await db).rawQuery(
      '$_selectPosts WHERE p.personId = ? AND p.id = ?'
      '${includeDeleted ? '' : " AND p.deleted = 0 AND (a.category != 'club' OR p.aiGenerated = 1)"}',
      [personId, id],
    );
    return rows.firstOrNull;
  }

  Future<List<SocialRow>> notifications(
    String personId, {
    int limit = 40,
  }) async => (await db).rawQuery(
    '''$_selectPosts
      WHERE p.personId = ? AND p.deleted = 0 AND a.category != 'user'
      AND (a.category != 'club' OR p.aiGenerated = 1) AND (
        p.parentId IN (SELECT id FROM TwitterPosts WHERE personId = ? AND accountId = ? AND deleted = 0)
        OR p.text LIKE '%' || (SELECT '@' || handle FROM TwitterAccounts WHERE id = ? AND personId = ?) || '%')
      ORDER BY p.createdAt DESC LIMIT ?''',
    [personId, personId, '$personId:user', '$personId:user', personId, limit],
  );

  Future<List<SocialRow>> likedPosts(String personId, {int limit = 40}) async =>
      (await db).rawQuery(
        '$_selectPosts WHERE p.personId = ? AND p.deleted = 0 AND p.liked = 1 '
        "AND (a.category != 'club' OR p.aiGenerated = 1) "
        'ORDER BY p.postedAt DESC, p.createdAt DESC LIMIT ?',
        [personId, limit],
      );

  Future<int> postCount(String personId, String accountId) async =>
      Sqflite.firstIntValue(
        await (await db).rawQuery(
          '''SELECT COUNT(*) FROM TwitterPosts p JOIN TwitterAccounts a ON a.id = p.accountId
          WHERE p.personId = ? AND p.accountId = ? AND p.deleted = 0
          AND (a.category != 'club' OR p.aiGenerated = 1)''',
          [personId, accountId],
        ),
      ) ??
      0;

  Future<void> toggleReaction(
    String personId,
    String id, {
    bool repost = false,
  }) async {
    final flag = repost ? 'reposted' : 'liked';
    final count = repost ? 'reposts' : 'likes';
    await (await db).rawUpdate(
      'UPDATE TwitterPosts SET $count = MAX(0, $count + '
      'CASE WHEN $flag = 1 THEN -1 ELSE 1 END), $flag = 1 - $flag '
      'WHERE personId = ? AND id = ? AND deleted = 0',
      [personId, id],
    );
    changed();
  }

  Future<String> publish(
    Person person,
    String text, {
    SocialRow? parent,
    DateTime? publicationDate,
  }) async {
    await initialize(person);
    final clean = text.trim();
    if (clean.isEmpty || clean.runes.length > 280) {
      throw const FormatException('Escreva entre 1 e 280 caracteres.');
    }
    final id = const Uuid().v4();
    final date = resolveTwitterPublicationDate(
      selected: publicationDate,
      parent: DateTime.tryParse(parent?['postedAt']?.toString() ?? ''),
      latestFixture: await SqlService.instance.getLatestFixtureDate(person.id),
    ).toIso8601String();
    final database = await db;
    final account = (await accounts(person.id))
        .firstWhere((account) => account.id == '${person.id}:user');
    await database.transaction((txn) async {
      if (parent != null &&
          (await txn.query(
            'TwitterPosts',
            columns: ['id'],
            where: 'id = ? AND personId = ? AND deleted = 0',
            whereArgs: [parent['id'], person.id],
          )).isEmpty) {
        throw const FormatException('O post foi removido.');
      }
      await txn.insert('TwitterPosts', {
        'id': id,
        'personId': person.id,
        'accountId': '${person.id}:user',
        'text': clean,
        'parentId': parent?['id'],
        'fixtureId': parent?['fixtureId'],
        'transferId': parent?['transferId'],
        'eventType': parent?['eventType'] ?? 'user',
        'postedAt': date,
        'createdAt': DateTime.now().toIso8601String(),
        ...engagement(account, id, reply: parent != null),
      });
    });
    changed();
    return id;
  }

  Future<void> deletePost(Person person, String id) async {
    final database = await db;
    await database.transaction((txn) async {
      final found = await txn.query(
        'TwitterPosts',
        columns: ['id'],
        where: 'personId = ? AND id = ? AND deleted = 0',
        whereArgs: [person.id, id],
      );
      if (found.isEmpty) return;
      await txn.rawUpdate(
        '''WITH RECURSIVE thread(id) AS (
        SELECT id FROM TwitterPosts WHERE personId = ? AND id = ?
        UNION SELECT p.id FROM TwitterPosts p JOIN thread t ON p.parentId = t.id
        WHERE p.personId = ?
      ) UPDATE TwitterPosts SET deleted = 1, text = '', likes = 0, reposts = 0,
        liked = 0, reposted = 0
        WHERE id IN (SELECT id FROM thread) AND personId = ?''',
        [person.id, id, person.id, person.id],
      );
    });
    changed();
  }

  static String fixtureOutcome(SocialRow fixture) {
    final a = fixture['playerTeamScore'] as num? ?? 0;
    final b = fixture['oppositeTeamScore'] as num? ?? 0;
    if (a != b) return a > b ? 'win' : 'loss';
    final pa = fixture['playerTeamPenaltiesScore'] as num?;
    final pb = fixture['oppositeTeamPenaltiesScore'] as num?;
    if (pa != null && pb != null && pa != pb) {
      return pa > pb ? 'winOnPenalties' : 'lossOnPenalties';
    }
    return 'draw';
  }

  static Random _postRandom(String id, String purpose) => Random(
    '$id:$purpose'.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff),
  );

  static bool isKnockout(SocialRow fixture) =>
      fixture['playerTeamPenaltiesScore'] != null ||
      fixture['extraTime'] == 1 ||
      fixture['extraTime'] == true ||
      RegExp(
        r'final|semi|quartas|oitavas|mata|playoff|play-off|knockout|eliminat',
        caseSensitive: false,
      ).hasMatch(fixture['stage']?.toString() ?? '');

  static double eventIntensity(SocialRow event) {
    if (event['eventType']?.toString().startsWith('transfer') == true) {
      return 1.15;
    }
    final margin =
        ((event['playerTeamScore'] as num? ?? 0) -
                (event['oppositeTeamScore'] as num? ?? 0))
            .abs();
    return 1 +
        min(margin, 6) * 0.18 +
        (event['playerTeamPenaltiesScore'] != null ? 0.35 : 0) +
        (isKnockout(event) ? 0.3 : 0);
  }

  static int commentTotal(
    TwitterAccount account,
    String id,
    int likes,
    int reposts, {
    String outcome = 'unknown',
    bool reply = false,
    double intensity = 1,
  }) {
    final random = _postRandom(id, 'comments-v2');
    final loss = outcome.startsWith('loss');
    final club = account.kind == TwitterAccountKind.club;
    final rate = switch (account.kind) {
      TwitterAccountKind.club =>
        loss
            ? (0.35, 0.3)
            : outcome.startsWith('win')
            ? (0.025, 0.04)
            : (0.08, 0.12),
      TwitterAccountKind.journal => (0.006, 0.018),
      TwitterAccountKind.fanPage => (0.012, 0.028),
      _ => (0.015, 0.04),
    };
    final intensityWeight = intensity.clamp(0.75, 2.0);
    final heat = !loss
        ? intensityWeight
        : club
        ? intensityWeight * intensityWeight
        : intensityWeight * 2;
    final count =
        ((likes * (rate.$1 + random.nextDouble() * rate.$2) * heat +
                    reposts * 0.035) *
                (reply ? 0.7 : 1))
            .round();
    return max(switch (account.kind) {
      TwitterAccountKind.club => 5,
      TwitterAccountKind.user => 2,
      _ => 0,
    }, count);
  }

  static Map<String, int> engagement(
    TwitterAccount account,
    String postId, {
    double intensity = 1,
    bool reply = false,
    String outcome = 'unknown',
  }) {
    final random = _postRandom(postId, 'engagement-v2');
    final followers = max(100, account.followers);
    final club = account.kind == TwitterAccountKind.club;
    final loss = outcome.startsWith('loss'), win = outcome.startsWith('win');
    final scale = switch (account.kind) {
      TwitterAccountKind.club =>
        followers *
            (loss
                ? (0.002 + random.nextDouble() * 0.006)
                : win
                ? (0.01 + random.nextDouble() * 0.025)
                : (0.004 + random.nextDouble() * 0.012)),
      TwitterAccountKind.journal =>
        (followers * 0.012).clamp(250, 5000) * (0.2 + random.nextDouble()),
      TwitterAccountKind.fanPage =>
        (followers * 0.02).clamp(100, 2500) * (0.15 + random.nextDouble()),
      _ => (followers * 0.03).clamp(15, 240) * (0.08 + random.nextDouble()),
    };
    final base = account.averageLikes ?? scale;
    final likes =
        (base *
                (club && loss ? 1 : intensity.clamp(0.75, 1.6)) *
                (reply ? 0.18 : 1))
            .round();
    final rtRate = switch (account.kind) {
      TwitterAccountKind.club =>
        loss
            ? 0.02 + random.nextDouble() * 0.05
            : win
            ? 0.1 + random.nextDouble() * 0.18
            : 0.05 + random.nextDouble() * 0.1,
      TwitterAccountKind.journal => 0.05 + random.nextDouble() * 0.18,
      TwitterAccountKind.fanPage => 0.025 + random.nextDouble() * 0.12,
      _ => random.nextDouble() * 0.075,
    };
    final reposts = (likes * rtRate).round();
    return {
      'likes': likes,
      'reposts': reposts,
      'engagementVersion': 4,
      'replyTotal': commentTotal(
        account,
        postId,
        likes,
        reposts,
        outcome: outcome,
        reply: reply,
        intensity: intensity,
      ),
    };
  }
}
