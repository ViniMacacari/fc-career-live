import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ManagerRosterView.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/PlayerWidget.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/TeamPage.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  testWidgets(
    'Cold squad opening needs no catalog and resolves saved custom photos',
    (tester) async {
      await tester.runAsync(() async {
        final assets = <String>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMessageHandler('flutter/assets', (message) async {
          assets.add(
            utf8.decode(
              message!.buffer.asUint8List(
                message.offsetInBytes,
                message.lengthInBytes,
              ),
            ),
          );
          return null;
        });
        addTearDown(
          () => messenger.setMockMessageHandler('flutter/assets', null),
        );
        final directory = await Directory('build/cold-squad-docs')
            .create(recursive: true);
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.absolute.path,
        );
        addTearDown(
          () => messenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          ),
        );
        final photo = File('${directory.path}/faces/p/photo.png');
        await photo.parent.create(recursive: true);
        await photo.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aR1cAAAAASUVORK5CYII=',
          ),
        );
        final db = await SqlService.openCareerDatabase(inMemoryDatabasePath);
        addTearDown(db.close);
        await db.insert('Persons', reviewPerson().toMap());
        await db.insert('Seasons', reviewSeason().toMap());
        await db.insert('CustomCreatedPlayer', {
          'id': 'p',
          'personId': 'career',
          'name': 'Meu jogador',
          'positionId': '25',
          'overall': 70,
          'potential': 90,
          'realFace': 0,
          'foot': 'Right',
          'fromRealPlayer': 0,
          'customAvatarFilePath': '/faces/p/photo.png',
        });
        await db.insert('TeamPlayer', {
          'id': 'r',
          'playerId': 'p',
          'personId': 'career',
          'seasonId': 's2026',
          'isBench': 1,
          'overall': 70,
        });
        expect(GameCatalog.current, isNull);
        await tester.pumpWidget(
          MaterialApp(
            home: TeamPage(
              person: reviewPerson(),
              sql: SqlService.withDatabase(db),
            ),
          ),
        );
        for (
          var i = 0;
          i < 50 && find.byType(ManagerRosterView).evaluate().isEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
        expect(find.byType(ManagerRosterView), findsOneWidget);
        expect(
          tester
              .widget<ManagerRosterView>(find.byType(ManagerRosterView))
              .gamePlayers,
          isEmpty,
        );
        expect(
          tester.widget<PlayerWidget>(find.byType(PlayerWidget)).name,
          'Meu jogador',
        );
        final image = tester.widget<Image>(find.byType(Image));
        final provider = image.image as ResizeImage;
        expect(
          (provider.imageProvider as FileImage).file.path,
          '${directory.absolute.path}/faces/p/photo.png',
        );
        expect(
          assets.where(
            (name) =>
                name.contains('_players.json') || name.contains('game_catalog'),
          ),
          isEmpty,
        );
        expect(GameCatalog.current, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );
}
