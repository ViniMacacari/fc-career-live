import 'package:sqflite/sqflite.dart';

import '../models/Person.dart';
import 'TwitterStore.dart';

class TwitterFeedContext {
  static const recentRootLimit = 10;
  static const recentDaySpan = 3;

  static DateTime windowStart(DateTime date) =>
      DateTime(date.year, date.month, date.day - recentDaySpan + 1);
  static Future<DateTime> publicationDate(Database db, Person person) async {
    final table = person.category == PersonCategory.manager
        ? 'ManagerFixtures'
        : 'PlayerFixtures';
    final rows = await db.rawQuery(
      '''
      SELECT date FROM (
        SELECT postedAt AS date FROM TwitterPosts
          WHERE personId = ? AND deleted = 0 AND parentId IS NULL
        UNION ALL SELECT date FROM $table WHERE personId = ?
      ) ORDER BY julianday(date) DESC LIMIT 1''',
      [person.id, person.id],
    );
    final date =
        DateTime.tryParse(rows.firstOrNull?['date']?.toString() ?? '') ??
        DateTime.now();
    return DateTime(date.year, date.month, date.day);
  }

  static Future<List<SocialRow>> load(
    Database db,
    Person person,
    DateTime date,
  ) async {
    final cutoff = DateTime(
      date.year,
      date.month,
      date.day + 1,
    ).subtract(const Duration(milliseconds: 1)).toIso8601String();
    final since = windowStart(date).toIso8601String();
    const select = '''SELECT p.*, a.handle, a.category, g.topic,
      g.eventType AS sourceType, parent.text AS parentText,
      parent.sourceDate AS parentSourceDate, parent.sourcePostId AS parentSourceId
      FROM TwitterPosts p
      JOIN TwitterAccounts a ON a.id = p.accountId AND a.personId = p.personId
      LEFT JOIN TwitterGenerations g ON g.id = p.generationId AND g.personId = p.personId
      LEFT JOIN TwitterPosts parent ON parent.id = p.parentId
        AND parent.personId = p.personId AND parent.deleted = 0
      WHERE p.personId = ? AND p.deleted = 0
        AND julianday(p.postedAt) <= julianday(?)
        AND julianday(p.postedAt) >= julianday(?)
        AND julianday(COALESCE(p.sourceDate, parent.sourceDate, p.postedAt)) >= julianday(?)
        AND julianday(COALESCE(p.sourceDate, parent.sourceDate, p.postedAt)) <= julianday(?)
        AND (p.eventType != 'feed' OR COALESCE(p.sourceDate, parent.sourceDate) IS NOT NULL)''';
    final args = [person.id, cutoff, since, since, cutoff];
    final roots = await db.rawQuery('''$select AND p.parentId IS NULL
      ORDER BY julianday(p.postedAt) DESC, p.createdAt DESC, p.id DESC
      LIMIT $recentRootLimit''', args);
    String story(SocialRow row) =>
        row['eventType'] == 'feed' && row['sourcePostId'] != null
        ? 'source:${row['sourcePostId']}'
        : '${row['eventType']}:'
              '${row['transferId'] ?? row['fixtureId'] ?? row['generationId'] ?? row['id']}';
    final selected = <SocialRow>[];
    final perStory = <String, int>{};
    for (var round = 0; round < 2; round++) {
      for (final row in roots) {
        final key = story(row);
        if ((perStory[key] ?? 0) != round ||
            selected.any((p) => p['id'] == row['id'])) {
          continue;
        }
        selected.add(row);
        perStory[key] = round + 1;
      }
    }
    final ids = selected.map((r) => r['id']).toList();
    final replies = ids.isEmpty
        ? <SocialRow>[]
        : await db.rawQuery(
            '''$select
      AND p.parentId IN (${List.filled(ids.length, '?').join(',')})
      AND parent.id IS NOT NULL AND julianday(parent.postedAt) <= julianday(?)
      ORDER BY julianday(p.postedAt) DESC, p.createdAt DESC LIMIT 4''',
            [...args, ...ids, cutoff],
          );
    return [...selected, ...replies]
        .map(
          (row) => <String, Object?>{
            'id': row['id'],
            'author': row['handle'],
            'kind': row['category'],
            'date': row['postedAt'],
            'sourceDate':
                row['sourceDate'] ?? row['parentSourceDate'] ?? row['postedAt'],
            'sourcePostId':
                row['sourcePostId'] ?? row['parentSourceId'] ?? row['id'],
            'eventType': row['eventType'],
            'text': row['text'],
            if (row['sourceType'] != 'feed' && row['topic'] is String)
              'topic': (row['topic'] as String).length > 500
                  ? (row['topic'] as String).substring(0, 500)
                  : row['topic'],
            if (row['parentText'] != null) 'inReplyTo': row['parentText'],
            if (row['liked'] == 1) 'userLiked': true,
          },
        )
        .toList();
  }
}
