import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/FcScore/FcScoreModels.dart';
import 'package:mcmanager/FcScore/FcScoreRepository.dart';
import 'package:mcmanager/models/Season.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final address = Platform.environment['FC_SCORE_LIVE_URL'];
  test(
    'Real API: all career views, de-para, import and repeat import',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => Directory('build/fcscore-live-docs').absolute.path,
          );
      final api = FcScoreApi(fcScoreAddress(address!));
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(() async {
        api.close();
        await db.close();
      });
      await SqlService.ensureCompatibleSchema(db);
      await SqlService.ensureSeasonClosureSchema(db);
      await SqlService.ensureFixtureFormationSchema(db);
      await SqlService.ensureOpponentLineupSchema(db);
      await db.execute(
        'ALTER TABLE ManagerFixtures ADD COLUMN opponentStats TEXT',
      );
      final meta = await api.connect();
      final careers = await api.list('careers');
      final save = careers.firstWhere((s) => s['careerType'] == 'manager');
      final remote = await FcScoreRemoteCareer.load(
        api,
        fcId(save['id']),
        fcId(meta['gameVersion']),
      );
      for (final endpoint in [
        'league',
        'fixtures',
        'history',
        'transfers',
        'youth',
        'tactics',
      ]) {
        final response = await api.request(
          api.careerPath(remote.saveId, endpoint),
        );
        expect(response, isNotNull, reason: endpoint);
      }
      expect(
        await api.object(
          api.careerPath(remote.saveId, 'players/${remote.squad.first['id']}'),
        ),
        contains('attributes'),
      );
      final raw = await api.report(remote.saveId);
      final match = FcScoreMatch.fromReport(raw);
      expect(match.date, isNotNull);
      final person = reviewPerson();
      await db.insert('Persons', person.toMap());
      final season = Season(
        id: 'live-season',
        personId: person.id,
        startDate: DateTime(match.date!.year),
        endDate: DateTime(match.date!.year, 12, 31),
        createdAt: DateTime.now(),
      );
      final repo = FcScoreRepository(sql: SqlService.withDatabase(db));
      final link = FcScoreLink(
        personId: person.id,
        saveId: remote.saveId,
        saveName: remote.saveName,
        gameVersion: remote.gameVersion,
        remoteClubId: fcId(remote.club['id']),
        localClubId: person.teamId,
        localLeagueId: person.leagueId,
        seasonId: season.id,
        competitions: {
          for (final c in remote.competitions)
            fcId(c['id']): 'new:${fcName(c['name'], fcId(c['code']))}',
        },
      );
      final bound = await repo.bind(link: link, remote: remote, season: season);
      final opponent = fcObject(match.opponent(bound)['team']);
      bound.teams[fcId(opponent['id'])] = 'new:${fcName(opponent['name'])}';
      bound.competitions.putIfAbsent(
        match.competitionId,
        () => 'new:${fcName(match.competition['name'])}',
      );
      final imported = await repo.importMatch(
        person: person,
        link: bound,
        match: match,
      );
      expect(imported.state, FcImportState.available);
      expect(
        (await repo.importMatch(
          person: person,
          link: bound,
          match: match,
        )).state,
        FcImportState.alreadyImported,
      );
      expect((await db.query('ManagerFixtures')).length, 1);
      expect(
        (await db.query('ManagerFixturePlayerPerformances')).length,
        fcList(match.own(bound)['players'])
            .where((p) => p['played'] == true)
            .length,
      );
    },
    skip: address == null
        ? 'Set FC_SCORE_LIVE_URL to run against a local developer API.'
        : false,
  );
}
