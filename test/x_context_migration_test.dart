import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Twitter/TwitterStore.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  for (final oldVersion in [38, 39, 40, 41]) {
    test(
      'Production open repairs missing X context in version $oldVersion and retains the career',
      () async {
        final directory = await Directory('build/test-databases')
            .create(recursive: true);
        final file = File(
          '${directory.absolute.path}/x-migration-$oldVersion-${DateTime.now().microsecondsSinceEpoch}.db',
        );
        Database? opened;
        try {
          var db = opened = await SqlService.openCareerDatabase(file.path);
          await db.insert('Persons', reviewPerson().toMap());
          await db.insert('Seasons', reviewSeason().toMap());
          await db.insert('ManagerFixtures', reviewFixture(0));
          await db.insert('TwitterSettings', {
            'personId': 'career',
            'postCount': 9,
            'enabled': 0,
          });
          await db.insert('TwitterPosts', {
            'id': 'saved-post',
            'personId': 'career',
            'accountId': 'club',
            'text': 'Meu post salvo',
            'postedAt': '2028-11-07',
            'createdAt': '2028-11-07',
          });
          await db.insert('TwitterGenerations', {
            'id': 'pending',
            'personId': 'career',
            'fixtureId': 'f0',
            'status': 'failed',
            'error': 'no such column: customContext',
            'createdAt': '2028-11-07',
            'updatedAt': '2028-11-07',
          });
          final originalFixture = (await db.query('ManagerFixtures')).single;
          await db.execute(
            'ALTER TABLE TwitterSettings DROP COLUMN customContext',
          );
          await db.setVersion(oldVersion);
          await db.close();
          db = opened = await SqlService.openCareerDatabase(file.path);
          expect(await db.getVersion(), 46);
          expect(
            (await db.query('Persons')).single['name'],
            reviewPerson().name,
          );
          expect((await db.query('Seasons')).single['id'], reviewSeason().id);
          expect((await db.query('ManagerFixtures')).single, originalFixture);
          expect(
            (await db.query('TwitterPosts')).single['text'],
            'Meu post salvo',
          );
          expect(
            (await db.query('TwitterGenerations')).single['status'],
            'failed',
          );
          final store = TwitterStore.withDatabase(db);
          expect(await store.customContext('career'), isEmpty);
          await store.saveCustomContext('career', 'Contexto recuperado');
          store.dispose();
          await db.close();
          db = opened = await SqlService.openCareerDatabase(file.path);
          final settings = (await db.query('TwitterSettings')).single;
          expect(settings['customContext'], 'Contexto recuperado');
          expect(settings['postCount'], 9);
          expect(settings['enabled'], 0);
        } finally {
          await opened?.close();
          if (await file.exists()) await file.delete();
        }
      },
    );
  }
}
