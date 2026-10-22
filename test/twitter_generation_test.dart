import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mcmanager/Twitter/TwitterPage.dart';
import 'package:mcmanager/Twitter/TwitterFeedContext.dart';
import 'package:mcmanager/Twitter/TwitterCareerSummary.dart';
import 'package:mcmanager/Twitter/TwitterGenerationService.dart';
import 'package:mcmanager/Twitter/TwitterModels.dart';
import 'package:mcmanager/Twitter/TwitterSchema.dart';
import 'package:mcmanager/Twitter/TwitterStore.dart';
import 'package:mcmanager/models/Person.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/models/TransferPreviousClubStats.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:mcmanager/utils/ai/AIModelService.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';
import 'ui_preview_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late TwitterStore store;
  late TwitterGenerationService service;
  late Person person;
  late List<Map<String, dynamic>> requests;
  late List<String> systems;
  Future<AIResponse> Function(Map<String, dynamic>)? respond;
  var ready = true;

  Map<String, dynamic> answer(Map<String, dynamic> request) {
    final plans = request['postPlan'] as List? ?? const [];
    final counts = request['exactCounts'] as Map? ?? const {};
    const handles = {
      'fan': 'MartaTricolor',
      'fanPage': 'VozDoMorumbi',
      'journal': 'JornalDaBola',
      'rival': 'BiaRival',
    };
    const names = {
      'fan': 'Marta Silva',
      'fanPage': 'Voz do Morumbi',
      'journal': 'Jornal da Bola',
      'rival': 'Bia Souza',
    };
    Map<String, String> reply() => {
      'author': 'MartaTricolor',
      'text': 'boa notícia para o clube',
    };
    return {
      'newAccounts': [
        for (final kind in handles.keys)
          {
            'name': names[kind],
            'handle': handles[kind],
            'kind': kind,
            'bio': 'Acompanho futebol e as notícias do clube.',
            'supports': kind == 'journal'
                ? 'neutral'
                : kind == 'rival'
                ? 'other'
                : 'career',
          },
      ],
      if (request['officialPostRequest'] != null)
        'officialPost': {
          'text': 'O capitão fica! Contrato renovado por mais duas temporadas.',
        },
      if (request['opponentOfficialPostRequest'] != null)
        'opponentOfficialPost': {
          'text': 'Não foi nosso dia. Seguimos trabalhando.',
        },
      'text': 'Nosso capitão segue com a gente por mais duas temporadas!',
      'posts': [
        for (var i = 0; i < plans.length; i++)
          {
            'author': handles[(plans[i] as Map)['kind']],
            'text':
                'Continuando a conversa ${i + 1}: ${(plans[i] as Map)['about'] ?? 'o momento do clube'}.',
            'replies': [
              for (var j = 0; j < (counts['repliesPerPost'] as int? ?? 0); j++)
                reply(),
            ],
          },
      ],
      'clubReplies': [
        for (var j = 0; j < (counts['clubReplies'] as int? ?? 0); j++) reply(),
      ],
      'replies': request['replyPlan'] == null ? [] : [reply(), reply()],
    };
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ready = true;
    respond = null;
    requests = [];
    systems = [];
    person = reviewPerson();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('CREATE TABLE Settings(activePersonId TEXT)');
    await SqlService.ensureCompatibleSchema(db);
    await SqlService.ensureManagerProfileSchema(db);
    await SqlService.ensureSeasonClosureSchema(db);
    await createTwitterSchema(db);
    await db.insert('Persons', {
      ...person.toMap(),
      'managerProfile': jsonEncode({'name': 'Lucas Silva'}),
    });
    await db.insert('Seasons', reviewSeason().toMap());
    store = TwitterStore.withDatabase(db);
    await store.initialize(person);
    await db.insert(
      'TwitterAccounts',
      const TwitterAccount(
        id: 'fan',
        personId: 'career',
        name: 'Luana',
        handle: 'LuaTricolor',
        kind: TwitterAccountKind.fan,
        supportedTeamId: '40-13',
      ).toMap(),
    );
    service = TwitterGenerationService(
      store: store,
      isReady: () async => ready,
      configuration: () async => const AIConfiguration(),
      complete:
          (
            system,
            content, {
            int? maxTokens,
            Duration timeout = const Duration(seconds: 90),
          }) async {
            final request = jsonDecode(content) as Map<String, dynamic>;
            systems.add(system);
            requests.add(request);
            if (respond != null) return respond!(request);
            return AIResponse(jsonEncode(answer(request)), 1500, 300);
          },
    );
  });
  tearDown(() async {
    store.dispose();
    await db.close();
  });

  Future<void> post(
    String id,
    String text, {
    String date = '2026-02-20T00:00:00.000',
    String account = 'fan',
    String type = 'topic',
    String? generation,
    String? fixture,
    String? transfer,
    String? parent,
    String? sourceDate,
    String? sourcePost,
    bool deleted = false,
    String career = 'career',
    int likes = 0,
  }) async {
    await db.insert('TwitterPosts', {
      'id': id,
      'personId': career,
      'accountId': account,
      'text': text,
      'postedAt': date,
      'createdAt': '2026-02-20T12:00:${id.hashCode.abs() % 60}',
      'eventType': type,
      'generationId': generation,
      'fixtureId': fixture,
      'transferId': transfer,
      'parentId': parent,
      'sourceDate': sourceDate,
      'sourcePostId': sourcePost,
      'deleted': deleted ? 1 : 0,
      'likes': likes,
      'engagementVersion': 4,
    });
  }

  test(
    'Generation repairs legacy settings and retry recovers a pending job',
    () async {
      await db.execute('ALTER TABLE TwitterSettings DROP COLUMN customContext');
      await service.generateClubPost(person, 'Novo contexto do clube.');
      expect(service.errors, isEmpty);
      expect(await store.customContext(person.id), isEmpty);
      respond = (_) async => throw const FormatException('Falha temporária');
      await expectLater(
        service.generateClubPost(person, 'Segunda notícia.'),
        throwsFormatException,
      );
      final pending = (await db.query(
        'TwitterGenerations',
        where: "status = 'failed'",
      )).single;
      await db.update(
        'TwitterGenerations',
        {'error': 'no such column: customContext'},
        where: 'id = ?',
        whereArgs: [pending['id']],
      );
      await db.execute('ALTER TABLE TwitterSettings DROP COLUMN customContext');
      respond = null;
      await service.retry(person, pending['id'] as String);
      expect(
        (await db.query(
          'TwitterGenerations',
          where: 'id = ?',
          whereArgs: [pending['id']],
        )).single['status'],
        'done',
        reason: service.errors.toString(),
      );
      expect(requests.length, 3);
    },
  );

  test(
    'A championship drives the official voice, fan posts and later replies',
    () async {
      await db.insert('Tournament', {'id': 'cup', 'name': 'Copa da Carreira'});
      await db.insert('ManagerFixtures', {
        ...reviewFixture(0),
        'tournamentId': 'cup',
        'stage': 'Finale',
        'playerTeamScore': 1,
        'oppositeTeamScore': 1,
        'playerTeamPenaltiesScore': 5,
        'oppositeTeamPenaltiesScore': 4,
      });
      await service.generateCustom(
        person,
        const TwitterGenerationSelection(
          clubPost: true,
          opponentPost: true,
          fans: 2,
          pages: 1,
          journals: 1,
          rivals: 1,
        ),
        fixtureId: 'f0',
        background: false,
      );
      expect(service.errors, isEmpty);
      final request = requests.single;
      expect(request['context']['matchOccasion']['careerChampion'], isTrue);
      expect(request['context']['matchOccasion']['lastMatchOfSeason'], isFalse);
      expect(request['officialPostRequest']['tone'], contains('É CAMPEÃO'));
      expect(
        request['opponentOfficialPostRequest']['tone'],
        contains('Vice-campeão'),
      );
      expect(request['clima']['momentoEspecial'], contains('ÊXTASE'));
      expect(
        (request['postPlan'] as List)
            .where((p) => p['kind'] == 'fan')
            .first['angle'],
        contains('CAMPEÃO'),
      );
      expect(
        (request['clubRepliesPlan'] as List).first['angle'],
        contains('campeão'),
      );
      final official = (await store.post(
        person.id,
        '${person.id}:official:f0',
      ))!;
      await service.generateReplies(person, official);
      expect(
        requests.last['context']['matchOccasion']['careerChampion'],
        isTrue,
      );
      expect(requests.last['replyPlan'].first['angle'], contains('título'));
      await service.regeneratePost(person, official);
      expect(
        requests.last['officialPostRequest']['tone'],
        contains('É CAMPEÃO'),
      );
    },
  );

  test('A two-legged title celebrates the aggregate even when the return match is lost; the first leg is not a title', () async {
    await db.insert('Tournament', {'id': 'cup', 'name': 'Copa da Carreira'});
    await db.insert('ManagerFixtures', {
      ...reviewFixture(0),
      'tournamentId': 'cup',
      'stage': 'Finale · Ida',
      'date': '2026-02-10T20:00:00',
      'playerTeamScore': 3,
      'oppositeTeamScore': 0,
    });
    await db.insert('ManagerFixtures', {
      ...reviewFixture(1),
      'tournamentId': 'cup',
      'stage': 'Finale · Volta',
      'date': '2026-02-17T20:00:00',
      'playerTeamScore': 0,
      'oppositeTeamScore': 1,
    });
    await service.generateCustom(
      person,
      const TwitterGenerationSelection(clubPost: true),
      fixtureId: 'f0',
      background: false,
    );
    expect(requests.last['context']['matchOccasion'], isEmpty);
    await service.generateCustom(
      person,
      const TwitterGenerationSelection(clubPost: true, opponentPost: true),
      fixtureId: 'f1',
      background: false,
    );
    expect(service.errors, isEmpty);
    expect(requests.last['context']['matchOccasion']['careerChampion'], isTrue);
    expect(requests.last['officialPostRequest']['tone'], contains('É CAMPEÃO'));
    expect(
      requests.last['opponentOfficialPostRequest']['tone'],
      contains('Vice-campeão'),
    );
    expect(requests.last['opponentOfficialPostRequest']['outcome'], 'win');
  });

  Future<void> finalBrazilianTable({
    int played = 38,
    int position = 1,
    int? runnerPlayed,
  }) async {
    await db.insert('TournamentResult', {
      'id': 'fcscore-result:career:s2026:brazil',
      'personId': person.id,
      'seasonId': 's2026',
      'fifaVersion': person.fifaVersion,
      'tournamentId': '86',
      'result': 'Dados importados · Em andamento',
    });
    await db.insert('TournamentResultTable', {
      'id': 'fcscore-table:brazil:league',
      'personId': person.id,
      'seasonId': 's2026',
      'fifaVersion': person.fifaVersion,
      'tournamentResultId': 'fcscore-result:career:s2026:brazil',
      'name': 'Brasileirão · League · G1',
      'position': 0,
    });
    for (var rank = 1; rank <= 20; rank++) {
      await db.insert('TournamentResultTableItem', {
        'id': 'table-team-$rank',
        'personId': person.id,
        'seasonId': 's2026',
        'fifaVersion': person.fifaVersion,
        'tournamentResultTableId': 'fcscore-table:brazil:league',
        'teamId': rank == position ? person.teamId : 'team-$rank',
        'position': rank,
        'points': 100 - rank,
        'wins': 20,
        'draws': 10,
        'loses': 8,
        'goalsFor': 60,
        'goalsAgainst': 30,
        'matchesPlayed': rank == 2 ? runnerPlayed ?? played : played,
      });
    }
  }

  for (final tournament in ['86', 'league:100']) {
    for (final score in [(5, 0), (1, 1), (0, 2)]) {
      test(
        'Imported Brasileiro final rank wins the title after $score with de-para $tournament',
        () async {
          await db.insert('ManagerFixtures', {
            ...reviewFixture(0),
            'tournamentId': tournament,
            'date': '2026-11-22T20:00:00',
            'stage': 'League · Rodada 37',
            'position': 2,
          });
          await db.insert('ManagerFixtures', {
            ...reviewFixture(1),
            'tournamentId': tournament,
            'date': '2026-11-29T20:00:00',
            'stage': 'League · Rodada 38',
            'position': 1,
            'playerTeamScore': score.$1,
            'oppositeTeamScore': score.$2,
          });
          await service.generateCustom(
            person,
            const TwitterGenerationSelection(
              clubPost: true,
              opponentPost: true,
              fans: 1,
              pages: 1,
              journals: 1,
              rivals: 1,
            ),
            fixtureId: 'f1',
            background: false,
          );
          expect(service.errors, isEmpty);
          final request = requests.single,
              occasion = request['context']['matchOccasion'];
          expect(occasion['careerChampion'], isTrue);
          expect(occasion['opponentChampion'], isFalse);
          expect(occasion['leagueRound'], 38);
          expect(occasion['leagueRounds'], 38);
          expect(occasion['finalPosition'], 1);
          expect(
            request['officialPostRequest']['requiredFacts']['titleConfirmed'],
            isTrue,
          );
          for (final plan in request['postPlan'] as List) {
            expect(
              '${plan['angle']}',
              matches(RegExp('campe|título|conquista', caseSensitive: false)),
            );
          }
          final official = (await store.post(
            person.id,
            '${person.id}:official:f1',
          ))!;
          expect(official['text'], startsWith('É CAMPEÃO!'));
          expect(official['text'], contains('Brasileiro Serie A'));
          final opponent = (await store.post(
            person.id,
            '${person.id}:opponentOfficial:f1',
          ))!;
          expect(opponent['text'], isNot(contains('É CAMPEÃO')));
          expect(
            (await db.query(
              'ManagerFixtures',
              where: 'id = ?',
              whereArgs: ['f1'],
            )).single['stage'],
            'League · Rodada 38',
          );
          await service.generateReplies(person, official);
          expect(
            requests.last['context']['matchOccasion']['careerChampion'],
            isTrue,
          );
          await service.regeneratePost(person, official);
          expect(
            (await store.post(person.id, official['id'] as String))!['text'],
            startsWith('É CAMPEÃO!'),
          );
        },
      );
    }
  }

  test('Finished imported standings supply a missing rank without rewriting the match', () async {
    await finalBrazilianTable();
    await db.insert('ManagerFixtures', {
      ...reviewFixture(0),
      'tournamentId': '86',
      'date': '2026-11-29T20:00:00',
      'stage': 'League · Rodada 38',
      'position': null,
    });
    await service.generateCustom(
      person,
      const TwitterGenerationSelection(clubPost: true),
      fixtureId: 'f0',
      background: false,
    );
    expect(service.errors, isEmpty);
    final occasion = requests.single['context']['matchOccasion'];
    expect(occasion['careerChampion'], isTrue);
    expect(occasion['finalPosition'], 1);
    expect(occasion['titleEvidence'], contains('classificação final completa'));
    expect((await db.query('ManagerFixtures')).single['position'], isNull);
  });

  for (final scenario in [
    'old lead',
    'round 37',
    'incomplete table',
    'runner has a game',
    'explicit second',
  ]) {
    test('A live lead is not a Brazilian championship: $scenario', () async {
      if (scenario != 'old lead') {
        await finalBrazilianTable(
          played: scenario == 'incomplete table' ? 37 : 38,
          runnerPlayed: scenario == 'runner has a game' ? 37 : null,
        );
      }
      await db.insert('ManagerFixtures', {
        ...reviewFixture(0),
        'tournamentId': '86',
        'date': '2026-11-22T20:00:00',
        'stage': 'League · Rodada 37',
        'position': 1,
      });
      if (scenario != 'round 37') {
        await db.insert('ManagerFixtures', {
          ...reviewFixture(1),
          'tournamentId': '86',
          'date': '2026-11-29T20:00:00',
          'stage': 'League · Rodada 38',
          'position': scenario == 'explicit second' ? 2 : null,
        });
      }
      await service.generateCustom(
        person,
        const TwitterGenerationSelection(clubPost: true),
        fixtureId: scenario == 'round 37' ? 'f0' : 'f1',
        background: false,
      );
      expect(service.errors, isEmpty);
      expect(
        requests.single['context']['matchOccasion']['careerChampion'],
        isNot(true),
      );
      expect(
        requests.single['officialPostRequest']['tone'],
        isNot(contains('É CAMPEÃO')),
      );
      if (scenario == 'old lead') {
        expect(
          requests.single['context']['matchOccasion']['finalPosition'],
          isNull,
        );
      }
    });
  }

  test(
    'An AI championship headline is kept without duplicating the celebration',
    () async {
      await db.insert('ManagerFixtures', {
        ...reviewFixture(0),
        'tournamentId': '86',
        'stage': 'League · Rodada 38',
        'position': 1,
      });
      const text = 'É CAMPEÃO DO BRASILEIRÃO! 🏆 A taça é nossa!';
      respond = (request) async => AIResponse(
        jsonEncode({
          ...answer(request),
          'officialPost': {'text': text},
        }),
        20,
        20,
      );
      await service.generateCustom(
        person,
        const TwitterGenerationSelection(clubPost: true),
        fixtureId: 'f0',
        background: false,
      );
      expect(
        (await store.post(person.id, '${person.id}:official:f0'))!['text'],
        text,
      );
      expect(requests, hasLength(1));
    },
  );

  test('A champion announcement survives a failed local save without another paid request', () async {
    await db.insert('ManagerFixtures', {
      ...reviewFixture(0),
      'tournamentId': '86',
      'stage': 'League · Rodada 38',
      'position': 1,
    });
    await db.execute(
      "CREATE TRIGGER block_title BEFORE INSERT ON TwitterPosts WHEN NEW.id = 'career:official:f0' BEGIN SELECT RAISE(ABORT, 'blocked'); END",
    );
    await service.generateCustom(
      person,
      const TwitterGenerationSelection(clubPost: true),
      fixtureId: 'f0',
      background: false,
    );
    final job = (await service.jobs(person.id)).single;
    expect(job['status'], 'failed');
    expect(requests, hasLength(1));
    await db.execute('DROP TRIGGER block_title');
    ready = false;
    await service.retry(person, job['id'] as String);
    expect(
      (await service.jobs(person.id)).single['status'],
      'done',
      reason: service.errors.toString(),
    );
    expect(
      (await store.post(person.id, '${person.id}:official:f0'))!['text'],
      startsWith('É CAMPEÃO!'),
    );
    expect(requests, hasLength(1));
  });

  test('Last league round brings a season farewell, but an ordinary latest game does not', () async {
    await db.insert('ManagerFixtures', {
      ...reviewFixture(0),
      'tournamentId': '21',
      'stage': 'Rodada 37',
      'position': 1,
    });
    await service.generateCustom(
      person,
      const TwitterGenerationSelection(clubPost: true),
      fixtureId: 'f0',
      background: false,
    );
    expect(requests.last['context']['matchOccasion'], isEmpty);
    await db.insert('ManagerFixtures', {
      ...reviewFixture(1),
      'tournamentId': '21',
      'stage': 'Rodada 38',
      'position': 1,
      'date': '2026-12-05T20:00:00',
      'playerTeamScore': 0,
      'oppositeTeamScore': 0,
    });
    await service.generateCustom(
      person,
      const TwitterGenerationSelection(clubPost: true, fans: 1),
      fixtureId: 'f1',
      background: false,
    );
    expect(service.errors, isEmpty);
    final occasion = requests.last['context']['matchOccasion'] as Map;
    expect(occasion['lastMatchOfSeason'], isTrue);
    expect(occasion['careerChampion'], isTrue);
    expect(occasion['competition'], isNot('league:1014'));
    expect(occasion['seasonRecord']['games'], 2);
    expect(occasion['seasonTitles'], hasLength(1));
  });

  test('Future club calendar prevents an early season farewell after the league finale', () async {
    await db.insert('FcScoreWorldFixture', {
      'personId': person.id,
      'seasonId': 's2026',
      'remoteKey': 'cup-final',
      'competitionId': 'cup',
      'tournamentId': 'cup',
      'played': 0,
      'rawJson': '{}',
      'homeTeamId': person.teamId,
      'awayTeamId': 'rival',
      'date': '2026-12-10T20:00:00',
    });
    await db.insert('ManagerFixtures', {
      ...reviewFixture(0),
      'date': '2026-12-05T20:00:00',
      'tournamentId': '21',
      'stage': 'Rodada 38',
      'position': 1,
    });
    await service.generateCustom(
      person,
      const TwitterGenerationSelection(clubPost: true),
      fixtureId: 'f0',
      background: false,
    );
    expect(
      requests.single['context']['matchOccasion']['careerChampion'],
      isTrue,
    );
    expect(
      requests.single['context']['matchOccasion']['lastMatchOfSeason'],
      isFalse,
    );
  });

  test('Closing a poor season yields a farewell without inventing a trophy or leaking it into older matches', () async {
    await db.update(
      'Seasons',
      {'closedAt': '2027-01-02T00:00:00'},
      where: 'id = ?',
      whereArgs: ['s2026'],
    );
    await db.insert('ManagerFixtures', {
      ...reviewFixture(0),
      'position': 12,
      'stage': 'Rodada 5',
    });
    await db.insert('ManagerFixtures', {
      ...reviewFixture(1),
      'date': '2026-12-05T20:00:00',
      'position': 12,
      'stage': 'Rodada 38',
      'playerTeamScore': 0,
      'oppositeTeamScore': 3,
    });
    await service.generateCustom(
      person,
      const TwitterGenerationSelection(clubPost: true),
      fixtureId: 'f0',
      background: false,
    );
    expect(requests.last['context']['matchOccasion'], isEmpty);
    await service.generateCustom(
      person,
      const TwitterGenerationSelection(clubPost: true, fans: 1),
      fixtureId: 'f1',
      background: false,
    );
    final occasion = requests.last['context']['matchOccasion'] as Map;
    expect(occasion['lastMatchOfSeason'], isTrue);
    expect(occasion['careerChampion'], isFalse);
    expect(occasion['seasonTitles'], isEmpty);
    expect(
      requests.last['officialPostRequest']['tone'],
      contains('Encerramento'),
    );
    expect(requests.last['postPlan'].first['angle'], contains('saldo do ano'));
  });

  test('Personal context survives preferences, reaches matches, replies and feed, and can be cleared independently per career', () async {
    const text = 'Última partida da temporada e despedida do nosso capitão.';
    await store.saveCustomContext(person.id, text);
    await store.saveCustomContext('other-career', 'Outro contexto');
    await store.savePreferences(
      person.id,
      const TwitterPreferences(pagePosts: 2),
    );
    expect(await store.customContext(person.id), text);
    await db.insert('ManagerFixtures', reviewFixture(0));
    await service.generateCustom(
      person,
      const TwitterGenerationSelection(clubPost: true),
      fixtureId: 'f0',
      background: false,
    );
    expect(requests.last['context']['userContext'], text);
    final official = (await store.post(person.id, '${person.id}:official:f0'))!;
    await service.generateReplies(person, official);
    expect(requests.last['context']['userContext'], text);
    await service.generateMore(person, background: false);
    expect(requests.last['context']['userContext'], text);
    await store.saveCustomContext(person.id, '');
    await service.regeneratePost(person, official);
    expect(
      (requests.last['context'] as Map).containsKey('userContext'),
      isFalse,
    );
    expect(await store.customContext('other-career'), 'Outro contexto');
    expect(await db.query('TwitterPosts'), isNotEmpty);
    expect((await store.preferences(person.id)).pagePosts, 2);
  });

  test('Manual competition results can confirm an early title and override an incorrect automatic title', () async {
    await db.insert('ManagerFixtures', {
      ...reviewFixture(0),
      'stage': 'Rodada 34',
      'position': 1,
    });
    await db.insert('TournamentResult', {
      'id': 'manual-result',
      'personId': person.id,
      'seasonId': 's2026',
      'fifaVersion': 'FC26',
      'tournamentId': 'league:1014',
      'result': 'Campeão antecipado',
      'isWinner': 1,
      'youParticipatedIn': 1,
    });
    await service.generateCustom(
      person,
      const TwitterGenerationSelection(clubPost: true),
      fixtureId: 'f0',
      background: false,
    );
    expect(requests.last['context']['matchOccasion']['careerChampion'], isTrue);
    expect(
      requests.last['context']['matchOccasion']['lastMatchOfSeason'],
      isFalse,
    );
    await db.update(
      'TournamentResult',
      {'isWinner': 0, 'result': 'Finalista'},
      where: 'id = ?',
      whereArgs: ['manual-result'],
    );
    await db.update(
      'ManagerFixtures',
      {'stage': 'Finale'},
      where: 'id = ?',
      whereArgs: ['f0'],
    );
    await service.regeneratePost(
      person,
      (await store.post(person.id, '${person.id}:official:f0'))!,
    );
    expect(requests.last['context']['matchOccasion'], isEmpty);
    expect(
      requests.last['officialPostRequest']['tone'],
      isNot(contains('É CAMPEÃO')),
    );
  });

  test(
    'Opponent preference persists and old settings keep the original behavior',
    () async {
      expect(
        (await store.preferences(person.id)).generateOpponentPost,
        isFalse,
      );
      await store.savePreferences(
        person.id,
        const TwitterPreferences(generateOpponentPost: true),
      );
      expect((await store.preferences(person.id)).generateOpponentPost, isTrue);
      await createTwitterSchema(db);
      expect((await store.preferences(person.id)).generateOpponentPost, isTrue);
    },
  );

  test('Custom match generation requests selected voices and the losing opponent only once', () async {
    await db.insert('ManagerFixtures', reviewFixture(0));
    const selection = TwitterGenerationSelection(
      journals: 2,
      rivals: 1,
      opponentPost: true,
    );
    await service.generateCustom(
      person,
      selection,
      fixtureId: 'f0',
      background: false,
    );
    expect(service.errors, isEmpty);
    final request = requests.single;
    expect(request['officialPostRequest'], isNull);
    expect(
      (request['postPlan'] as List).map((p) => p['kind']),
      unorderedEquals(['journal', 'journal', 'rival']),
    );
    final opponent = request['opponentOfficialPostRequest'] as Map;
    expect(opponent['goalsFor'], 1);
    expect(opponent['goalsAgainst'], 3);
    expect(opponent['tone'], contains('derrota'));
    expect(opponent['instruction'], contains('sem comemorar'));
    final posts = await db.query('TwitterPosts', where: 'parentId IS NULL');
    expect(posts, hasLength(4));
    final official = posts.singleWhere(
      (p) => p['id'] == '${person.id}:opponentOfficial:f0',
    );
    expect(
      (await store.account(person.id, official['accountId'] as String))!.teamId,
      reviewFixture(0)['oppositeTeamId'],
    );
    await service.generateCustom(
      person,
      const TwitterGenerationSelection(opponentPost: true),
      fixtureId: 'f0',
      background: false,
    );
    expect(service.errors, isEmpty);
    expect(requests, hasLength(1));
    expect(
      (await db.query('TwitterPosts', where: 'parentId IS NULL')),
      hasLength(4),
    );
    expect((await store.preferences(person.id)).postCount, 4);
  });

  test('More replies on an opponent post distinguish its angry fans from career banter, including nested targets', () async {
    await db.insert('ManagerFixtures', reviewFixture(0));
    final club = await store.ensureClub(person, 'fla', '1014');
    await post(
      'opponent-root',
      'Fim de jogo. Precisamos reagir.',
      account: club.id,
      fixture: 'f0',
      type: 'match',
    );
    await db.update(
      'TwitterPosts',
      {'replyTotal': 6},
      where: 'id = ?',
      whereArgs: ['opponent-root'],
    );
    await service.generateReplies(
      person,
      (await store.post(person.id, 'opponent-root'))!,
    );
    final request = requests.single;
    final plan = request['replyPlan'] as List;
    expect(plan.map((p) => p['audience']), ['opponent', 'career']);
    expect(plan.first['angle'], contains('próprio clube'));
    expect(plan.last['angle'], contains('Zoe o adversário'));
    expect(request['originalPost']['clubId'], 'fla');
    expect(systems.single, contains('a torcida dele cobra'));
    await post(
      'opponent-answer',
      'Vocês só ganharam por sorte.',
      parent: 'opponent-root',
      fixture: 'f0',
      type: 'match',
    );
    await db.update(
      'TwitterPosts',
      {'replyTotal': 2},
      where: 'id = ?',
      whereArgs: ['opponent-answer'],
    );
    await service.generateReplies(
      person,
      (await store.post(person.id, 'opponent-answer'))!,
    );
    expect(
      requests.last['replyTarget']['text'],
      'Vocês só ganharam por sorte.',
    );
    expect(requests.last['originalPost']['id'], 'opponent-root');
    expect(
      requests.last['replyPlan'].last['angle'],
      contains('argumento de replyTarget'),
    );
  });

  test('Custom feed preserves its choices across the saved job', () async {
    await db.insert('ManagerFixtures', reviewFixture(0));
    await post('fresh', 'Vitória importante.', fixture: 'f0', type: 'match');
    await service.generateCustom(
      person,
      const TwitterGenerationSelection(pages: 3),
      background: false,
    );
    expect(service.errors, isEmpty);
    expect(
      (requests.single['postPlan'] as List).map((p) => p['kind']),
      everyElement('fanPage'),
    );
    expect(requests.single['exactCounts']['posts'], 3);
  });

  for (final (ours, theirs, ownPen, otherPen, outcome, tone) in [
    (0, 2, null, null, 'win', 'vitória'),
    (1, 1, null, null, 'draw', 'empate'),
    (1, 1, 5, 4, 'lossOnPenalties', 'derrota'),
  ]) {
    test(
      'Opponent official post reflects $outcome including penalties',
      () async {
        await db.insert('ManagerFixtures', {
          ...reviewFixture(0),
          'playerTeamScore': ours,
          'oppositeTeamScore': theirs,
          'playerTeamPenaltiesScore': ownPen,
          'oppositeTeamPenaltiesScore': otherPen,
        });
        await service.generateCustom(
          person,
          const TwitterGenerationSelection(opponentPost: true),
          fixtureId: 'f0',
          background: false,
        );
        expect(service.errors, isEmpty);
        final request = requests.single['opponentOfficialPostRequest'] as Map;
        expect(request['outcome'], outcome);
        expect(request['tone'], contains(tone));
        expect(request['penaltiesFor'], otherPen);
        expect(request['penaltiesAgainst'], ownPen);
        expect(systems.single, contains('opponentOfficialPost.text'));
        if (outcome == 'lossOnPenalties') {
          final official = await store.post(
            person.id,
            '${person.id}:opponentOfficial:f0',
          );
          await service.regeneratePost(person, official!);
          final rewritten = requests.last['officialPostRequest'] as Map;
          expect(rewritten['outcome'], 'lossOnPenalties');
          expect(rewritten['tone'], contains('derrota'));
          expect(rewritten['penaltiesFor'], 4);
        }
      },
    );
  }

  test(
    'Automatic opponent setting adds an official post with inverse outcome',
    () async {
      await db.execute(
        'ALTER TABLE TeamTransferItem ADD COLUMN releaseDate TEXT',
      );
      await db.insert('ManagerFixtures', reviewFixture(0));
      await store.savePreferences(
        person.id,
        const TwitterPreferences(generateOpponentPost: true),
      );
      await service.onFixtureSaved(person, 'f0');
      for (
        var i = 0;
        i < 100 && (service.isBusy(person.id) || requests.isEmpty);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(service.errors, isEmpty);
      expect(
        requests.single['opponentOfficialPostRequest']['tone'],
        contains('derrota'),
      );
      expect(
        await store.post(person.id, '${person.id}:opponentOfficial:f0'),
        isNotNull,
      );
    },
  );

  Future<void> seedNews() async {
    await db.insert('ManagerFixtures', reviewFixture(0));
    await post(
      'match',
      'Ganhamos o jogo por 3 a 1.',
      type: 'match',
      fixture: 'f0',
    );
    await post(
      'transfer',
      'O ponta chegou ao clube.',
      type: 'transfer',
      transfer: 't1',
    );
    await post(
      'user',
      'O capitão vai renovar? Estou na torcida.',
      type: 'user',
      account: 'career:user',
    );
    await post(
      'news',
      'O capitão fica por mais duas temporadas.',
      type: 'clubTopic',
      account: 'career:club:1014:40-13',
      generation: 'club:previous',
    );
    await post(
      'reply',
      'Agora é hora de focar na temporada.',
      parent: 'news',
      likes: 100,
    );
  }

  Future<Map<String, Object?>> seedPlayerForm({
    required double strikerRating,
  }) async {
    for (final (id, name, position) in [
      ('star', 'Artilheiro', '25'),
      ('poor', 'Em má fase', '14'),
      ('defender', 'Defensor', '5'),
    ]) {
      await db.insert('CustomCreatedPlayer', {
        'id': id,
        'personId': person.id,
        'name': name,
        'positionId': position,
        'overall': 80,
        'potential': 85,
        'realFace': 0,
        'fromRealPlayer': 0,
        'foot': 'right',
      });
    }
    final matches = [
      for (var i = 0; i < 15; i++)
        {
          ...reviewFixture(i),
          'date': DateTime(2026, 1, i + 1).toIso8601String(),
          'playerTeamScore': i == 14 ? 0 : 2,
          'oppositeTeamScore': i == 14 ? 1 : 0,
          'position': i == 14 ? null : 3,
        },
    ];
    for (var i = 0; i < matches.length; i++) {
      await db.insert('ManagerFixtures', matches[i]);
      for (final (id, rating, goals) in [
        ('star', i == 14 ? strikerRating : 8.0, i == 14 ? 0 : 1),
        ('poor', i >= 10 ? 5.0 : 7.0, 0),
        ('defender', 8.0, 0),
      ]) {
        await db.insert(
          'ManagerFixturePlayerPerformances',
          ManagerFixturePlayerPerformance(
            personId: person.id,
            fixtureId: matches[i]['id'] as String,
            playerInstanceId: id,
            avgRating: rating,
            goalsCount: goals,
            goalDetails: [
              for (var j = 0; j < goals; j++)
                PerformanceGoalDetails(minute: 30),
            ],
          ).toMap(),
        );
      }
    }
    for (final (id, date, season, club) in [
      ('future', '2026-02-01', 's2026', '40-13'),
      ('old-season', '2025-12-01', 's2025', '40-13'),
      ('national', '2026-01-14', 's2026', 'national'),
    ]) {
      await db.insert('ManagerFixtures', {
        ...reviewFixture(0),
        'id': id,
        'date': date,
        'seasonId': season,
        'playerTeamId': club,
      });
      await db.insert(
        'ManagerFixturePlayerPerformances',
        ManagerFixturePlayerPerformance(
          personId: person.id,
          fixtureId: id,
          playerInstanceId: 'star',
          avgRating: 3,
          goalsCount: 10,
          goalDetails: [
            for (var i = 0; i < 10; i++) PerformanceGoalDetails(minute: 30),
          ],
        ).toMap(),
      );
    }
    return matches.last;
  }

  Future<Map<String, dynamic>> matchReactionRequest(
    Map<String, Object?> fixture,
  ) async {
    await store.savePreferences(
      person.id,
      const TwitterPreferences(
        postCount: 10,
        pagePosts: 0,
        journalPosts: 0,
        rivalPosts: 0,
      ),
    );
    await db.insert('TwitterGenerations', {
      'id': 'manual:form',
      'personId': person.id,
      'fixtureId': fixture['id'],
      'status': 'queued',
      'postCount': 10,
      'replyCount': 2,
      'createdAt': '2026-01-15',
      'updatedAt': '2026-01-15',
    });
    await service.runPending(person, onlyId: 'manual:form');
    expect(service.errors, isEmpty);
    expect(requests, isNotEmpty);
    return {
      ...requests.first,
      'postPlan': [for (final r in requests) ...(r['postPlan'] as List)],
    };
  }

  test('Match reaction targets bad recent form and spares a scorer who merely did not score', () async {
    final fixture = await seedPlayerForm(strikerRating: 6.8);
    final request = await matchReactionRequest(fixture);
    final climate = request['clima'] as Map;
    expect(climate['foramMal'], ['Em má fase']);
    final targets = climate['cobrancaIndividual'] as List;
    expect((targets.single as Map)['scope'], 'recentForm');
    final match = request['context']['match'] as Map;
    expect(match['position'], 3);
    expect(match['positionChange'], 0);
    expect(match['positionMovement'], 'Manteve a posição');
    final star = (match['lineup'] as List).cast<Map>().firstWhere(
      (p) => p['name'] == 'Artilheiro',
    );
    expect(star['assessment']['season']['matches'], 15);
    expect(star['assessment']['season']['goals'], 14);
    expect(star['assessment']['criticismScope'], 'none');
    final plan = jsonEncode(request['postPlan']);
    expect(plan, contains('má fase recente de Em má fase'));
    expect(plan, isNot(contains('de Artilheiro pelo nome')));
  });

  test('Reaction plans keep strong tone but limit a productive scorer to criticism of today', () async {
    final request = await matchReactionRequest(
      await seedPlayerForm(strikerRating: 5.4),
    );
    final targets = (request['clima']['cobrancaIndividual'] as List)
        .cast<Map>();
    final star = targets.firstWhere((p) => p['player'] == 'Artilheiro');
    expect(star['scope'], 'today');
    expect(star['strongSeason'], isTrue);
    expect(request['clima']['foramMal'], isNot(contains('Defensor')));
    final plan = jsonEncode(request['postPlan']);
    expect(plan, contains('atuação de hoje de Artilheiro'));
    expect(plan, contains('com palavrão'));
    expect(plan, contains('respeite a boa temporada dele'));
    expect(
      systems.first,
      contains('Zero gols, zero assistências ou nota ausente não provam'),
    );
  });

  test(
    'Feed context includes multiple stories, personal posts and replies',
    () async {
      await seedNews();
      final memory = await TwitterFeedContext.load(
        db,
        person,
        DateTime(2026, 2, 20),
      );
      expect(
        memory.map((r) => r['id']),
        containsAll(['match', 'transfer', 'user', 'news', 'reply']),
      );
      expect(
        memory.firstWhere((r) => r['id'] == 'reply')['inReplyTo'],
        contains('capitão fica'),
      );
    },
  );
  test(
    'Context excludes deleted, future, orphaned and other-career posts',
    () async {
      await seedNews();
      await post('deleted', 'Não incluir', deleted: true);
      await post('orphan', 'Não incluir', parent: 'deleted');
      await post('future', 'Não incluir', date: '2026-02-21');
      await post('foreign', 'Não incluir', career: 'other');
      final memory = await TwitterFeedContext.load(
        db,
        person,
        DateTime(2026, 2, 20),
      );
      expect(
        memory.map((r) => r['id']),
        isNot(
          anyOf(
            contains('deleted'),
            contains('orphan'),
            contains('future'),
            contains('foreign'),
          ),
        ),
      );
    },
  );
  test(
    'Chronological window does not rescue topics buried under newer posts',
    () async {
      await seedNews();
      for (var i = 0; i < 100; i++) {
        await post(
          'reaction$i',
          'Mais uma reação ao jogo',
          type: 'match',
          fixture: 'f0',
          date: '2026-02-21',
        );
      }
      final memory = await TwitterFeedContext.load(
        db,
        person,
        DateTime(2026, 2, 21),
      );
      expect(
        memory.map((r) => r['id']),
        isNot(anyOf(contains('news'), contains('user'))),
      );
      expect(
        memory.where((r) => '${r['id']}'.startsWith('reaction')).length,
        lessThanOrEqualTo(2),
      );
      expect(memory.length, lessThanOrEqualTo(14));
    },
  );
  test('Same freshness cutoff applies to matches, topics, users, clubs and transfers', () async {
    await post(
      'oldMatch',
      'Um jogo antigo',
      type: 'match',
      fixture: 'f0',
      date: '2026-02-10',
    );
    await post('oldTopic', 'Um boato antigo', date: '2026-02-17T23:59:59');
    await post(
      'oldUser',
      'Um assunto antigo do usuário',
      type: 'user',
      account: 'career:user',
      date: '2026-02-15',
    );
    await post(
      'oldClub',
      'Um anúncio antigo',
      type: 'clubTopic',
      account: 'career:club:1014:40-13',
      date: '2026-02-10',
    );
    await post(
      'oldTransfer',
      'Uma transferência antiga',
      type: 'transfer',
      transfer: 'oldTransfer',
      date: '2026-02-16',
    );
    await seedNews();
    await post(
      'boundary',
      'Assunto no começo da janela',
      date: '2026-02-18T00:00:00',
    );
    final memory = await TwitterFeedContext.load(
      db,
      person,
      DateTime(2026, 2, 20),
    );
    expect(
      memory.map((r) => r['id']),
      containsAll(['match', 'transfer', 'user', 'news', 'boundary']),
    );
    expect(memory.where((r) => '${r['id']}'.startsWith('old')), isEmpty);
  });
  test('Only ten newest root posts enter the context regardless of popularity or kind', () async {
    await post(
      'olderClub',
      'Anúncio fora das dez últimas postagens',
      account: 'career:club:1014:40-13',
      type: 'clubTopic',
      date: '2026-02-19',
      likes: 99999,
    );
    await post(
      'olderUser',
      'Assunto fora das dez últimas postagens',
      account: 'career:user',
      type: 'user',
      date: '2026-02-19',
    );
    for (var i = 0; i < 15; i++) {
      await post(
        'new$i',
        'Conversa recente $i',
        date: '2026-02-20T10:00:${i.toString().padLeft(2, '0')}',
      );
    }
    final memory = await TwitterFeedContext.load(
      db,
      person,
      DateTime(2026, 2, 20),
    );
    expect(memory.map((r) => r['id']).toSet(), {
      for (var i = 5; i < 15; i++) 'new$i',
    });
  });
  test(
    'New reactions do not revive old source dates or unproven legacy updates',
    () async {
      await post(
        'oldOrigin',
        'Notícia de cinco partidas atrás',
        date: '2026-02-10',
      );
      await post(
        'recycled',
        'A notícia antiga foi publicada de novo',
        type: 'feed',
        sourceDate: '2026-02-10',
        sourcePost: 'oldOrigin',
      );
      await post(
        'legacy',
        'A versão anterior retomou um assunto antigo',
        type: 'feed',
      );
      await post(
        'freshReaction',
        'Uma reação a um assunto ainda recente',
        type: 'feed',
        sourceDate: '2026-02-19',
        sourcePost: 'freshOrigin',
      );
      final memory = await TwitterFeedContext.load(
        db,
        person,
        DateTime(2026, 2, 20),
      );
      expect(memory, hasLength(1));
      expect(memory.single['id'], 'freshReaction');
      expect(memory.single['sourceDate'], '2026-02-19');
      expect(memory.single['sourcePostId'], 'freshOrigin');
    },
  );
  test('Refresh request contains fresh stories without five-game history or old announcements', () async {
    for (var i = 0; i < 6; i++) {
      await db.insert('ManagerFixtures', {
        ...reviewFixture(i),
        'date': DateTime(2026, 2, 10 + i * 2).toIso8601String(),
      });
    }
    await post(
      'oldGame',
      'Assunto de cinco jogos atrás',
      type: 'match',
      fixture: 'f0',
      date: '2026-02-10',
    );
    await post('oldRumor', 'Boato encerrado há dias', date: '2026-02-14');
    await post(
      'currentUser',
      'A torcida prepara uma homenagem',
      type: 'user',
      account: 'career:user',
    );
    await post(
      'currentClub',
      'O clube confirma o treino aberto',
      type: 'clubTopic',
      account: 'career:club:1014:40-13',
    );
    await post(
      'currentTransfer',
      'O reforço se apresentou hoje',
      type: 'transfer',
      transfer: 'newTransfer',
    );
    await service.generateMore(person, background: false);
    final context = requests.single['context'] as Map;
    expect(context.keys.toSet(), {'career', 'recentFeed', 'feedScope'});
    expect(context['recentFeed'], hasLength(3));
    expect(
      jsonEncode(requests.single),
      isNot(anyOf(contains('cinco jogos atrás'), contains('Boato encerrado'))),
    );
    expect((context['feedScope'] as Map)['from'], '2026-02-18');
  });
  test(
    'With no recent posts fallback contains only the latest fresh match',
    () async {
      for (var i = 0; i < 6; i++) {
        await db.insert('ManagerFixtures', {
          ...reviewFixture(i),
          'date': DateTime(2026, 2, 10 + i * 2).toIso8601String(),
        });
      }
      await service.generateMore(person, background: false);
      final context = requests.single['context'] as Map;
      expect(context['recentFeed'], isEmpty);
      expect((context['freshEvent'] as Map)['date'], '2026-02-20T00:00:00.000');
      expect(context.containsKey('recentMatches'), false);
      expect(context.containsKey('history'), false);
      final roots = await store.posts(person.id);
      expect(
        roots.every((p) => p['sourceDate'] == '2026-02-20T00:00:00.000'),
        true,
      );
    },
  );
  test('Refresh preserves story age across updates and drops it as the career advances', () async {
    await post(
      'origin',
      'O clube preparou uma homenagem ao capitão',
      type: 'user',
      account: 'career:user',
      date: '2026-02-19',
    );
    await db.insert('ManagerFixtures', {
      ...reviewFixture(0),
      'date': '2026-02-20T00:00:00.000',
    });
    await service.generateMore(person, background: false);
    final roots = (await store.posts(person.id))
        .where((p) => p['eventType'] == 'feed')
        .toList();
    expect(roots, isNotEmpty);
    expect(
      roots.every(
        (p) => p['sourceDate'] == '2026-02-19' && p['sourcePostId'] == 'origin',
      ),
      true,
    );
    await db.insert('ManagerFixtures', {
      ...reviewFixture(1),
      'date': '2026-02-23T00:00:00.000',
    });
    await service.generateMore(person, background: false);
    final context = requests.last['context'] as Map;
    expect(context['recentFeed'], isEmpty);
    expect((context['freshEvent'] as Map)['date'], '2026-02-23T00:00:00.000');
    expect(jsonEncode(requests.last), isNot(contains('homenagem ao capitão')));
  });
  test(
    'Fresh replies inherit the original topic date from their parent',
    () async {
      await post(
        'freshParent',
        'Reação a um anúncio recente',
        type: 'feed',
        sourceDate: '2026-02-19',
        sourcePost: 'recentAnnouncement',
      );
      await post(
        'manualReply',
        'O usuário comentou a notícia',
        type: 'feed',
        parent: 'freshParent',
        account: 'career:user',
      );
      await post(
        'staleParent',
        'Reação a um assunto antigo',
        type: 'feed',
        sourceDate: '2026-02-10',
        sourcePost: 'oldAnnouncement',
      );
      await post(
        'staleReply',
        'Comentário novo no assunto antigo',
        type: 'feed',
        parent: 'staleParent',
        account: 'career:user',
      );
      final memory = await TwitterFeedContext.load(
        db,
        person,
        DateTime(2026, 2, 20),
      );
      expect(
        memory.map((p) => p['id']),
        containsAll(['freshParent', 'manualReply']),
      );
      expect(
        memory.map((p) => p['id']),
        isNot(anyOf(contains('staleParent'), contains('staleReply'))),
      );
      expect(
        memory.firstWhere((p) => p['id'] == 'manualReply')['sourceDate'],
        '2026-02-19',
      );
    },
  );
  test(
    'Empty recent window stops before charging AI or creating a job',
    () async {
      await expectLater(
        service.generateMore(person, background: false),
        throwsFormatException,
      );
      expect(requests, isEmpty);
      expect(await service.jobs(person.id), isEmpty);
    },
  );
  test(
    'Publication day follows the latest post instead of the last fixture',
    () async {
      await seedNews();
      await post('future', 'Uma notícia em março', date: '2026-03-02T18:30:00');
      expect(
        await TwitterFeedContext.publicationDate(db, person),
        DateTime(2026, 3, 2),
      );
    },
  );
  test(
    'Refresh plans diverse recent subjects and saves posts with no fixture',
    () async {
      await seedNews();
      await service.generateMore(person, background: false);
      final job = (await service.jobs(person.id)).first;
      expect(job['status'], 'done', reason: '${job['error']}');
      final request = requests.single;
      expect(request['task'], contains('Continue a timeline'));
      expect((request['context'] as Map)['recentFeed'], isNotEmpty);
      expect(
        (request['postPlan'] as List)
            .map((p) => p['sourcePostId'])
            .toSet()
            .length,
        4,
      );
      expect(request['officialPostRequest'], isNull);
      final posts = await db.query(
        'TwitterPosts',
        where: 'generationId = ?',
        whereArgs: [job['id']],
      );
      expect(posts.where((p) => p['parentId'] == null).length, 4);
      expect(
        posts.every((p) => p['fixtureId'] == null && p['eventType'] == 'feed'),
        true,
      );
      expect(
        posts.every((p) => '${p['postedAt']}'.startsWith('2026-02-20')),
        true,
      );
    },
  );
  test(
    'Feed continuation works for an existing topic without a match',
    () async {
      await post('topicOnly', 'A torcida prepara uma homenagem ao capitão.');
      await service.generateMore(person, background: false);
      expect((await service.jobs(person.id)).first['status'], 'done');
      expect(
        jsonEncode(requests.single['context']),
        contains('homenagem ao capitão'),
      );
    },
  );
  test('Club brief publishes exactly one official post with selected date and replies', () async {
    const brief =
        'Renovamos com o capitão por duas temporadas. Faça um anúncio feliz.';
    await service.generateClubPost(person, brief, date: DateTime(2026, 3, 15));
    final job = (await service.jobs(person.id)).first;
    expect(job['status'], 'done');
    expect(job['generatedPostCount'], 1);
    final root = (await db.query(
      'TwitterPosts',
      where: 'generationId = ? AND parentId IS NULL',
      whereArgs: [job['id']],
    )).single;
    expect(root['accountId'], 'career:club:1014:40-13');
    expect(root['fixtureId'], isNull);
    expect(root['postedAt'], '2026-03-15T00:00:00.000');
    expect(root['eventType'], 'clubTopic');
    expect((requests.single['officialPostRequest'] as Map)['context'], brief);
    expect((requests.single['exactCounts'] as Map)['posts'], 0);
    expect(
      (requests.single['context'] as Map)['career']['name'],
      'Lucas Silva',
    );
    expect(
      await db.query(
        'TwitterPosts',
        where: 'parentId = ?',
        whereArgs: [root['id']],
      ),
      hasLength(2),
    );
  });
  test('Club generation preserves long brief and ignores unsolicited fan posts', () async {
    await db.update(
      'TwitterSettings',
      {'replyCount': 0},
      where: 'personId = ?',
      whereArgs: [person.id],
    );
    final brief =
        '${List.filled(50, 'Contexto da renovação. ').join()}Confirme a permanência.';
    respond = (r) async => AIResponse(
      jsonEncode({
        ...answer(r),
        'posts': [
          {'author': 'MartaTricolor', 'text': 'Não solicitado'},
        ],
        'clubReplies': [
          {'author': 'MartaTricolor', 'text': 'Não solicitado'},
        ],
      }),
      100,
      50,
    );
    await service.generateClubPost(person, brief);
    expect((requests.single['officialPostRequest'] as Map)['context'], brief);
    expect(await db.query('TwitterPosts'), hasLength(1));
  });
  test(
    'Failed request retries with original club, date and feed memory',
    () async {
      await seedNews();
      respond = (_) async => throw const FormatException('Falha simulada');
      await expectLater(
        service.generateClubPost(
          person,
          'Renovamos com o capitão.',
          date: DateTime(2026, 2, 20),
        ),
        throwsFormatException,
      );
      final job = (await service.jobs(person.id)).first;
      final original = requests.single;
      await post(
        'newNews',
        'Uma notícia posterior que não deve mudar a tentativa.',
        date: '2026-05-01',
      );
      final moved = Person.fromMap({...person.toMap(), 'teamId': '40-7'});
      respond = null;
      await service.retry(moved, job['id'] as String);
      expect(
        requests.last['officialPostRequest'],
        original['officialPostRequest'],
      );
      expect(
        (requests.last['context'] as Map)['recentFeed'],
        (original['context'] as Map)['recentFeed'],
      );
      final root = (await db.query(
        'TwitterPosts',
        where: 'generationId = ? AND parentId IS NULL',
        whereArgs: [job['id']],
      )).single;
      expect(root['accountId'], 'career:club:1014:40-13');
      expect(root['postedAt'], '2026-02-20T00:00:00.000');
      await service.retry(moved, job['id'] as String);
      expect(requests, hasLength(2));
      expect(
        await db.query(
          'TwitterPosts',
          where: 'generationId = ? AND parentId IS NULL',
          whereArgs: [job['id']],
        ),
        hasLength(1),
      );
    },
  );
  test(
    'Paid response survives failed local save and resumes without another call',
    () async {
      await db.execute(
        "CREATE TRIGGER block_club BEFORE INSERT ON TwitterPosts WHEN NEW.eventType = 'clubTopic' BEGIN SELECT RAISE(ABORT, 'blocked'); END",
      );
      await expectLater(
        service.generateClubPost(person, 'Renovamos com o capitão.'),
        throwsFormatException,
      );
      final job = (await service.jobs(person.id)).first;
      expect(job['savedResponseCount'], 1);
      expect(await db.query('TwitterPosts'), isEmpty);
      await db.execute('DROP TRIGGER block_club');
      ready = false;
      await service.retry(person, job['id'] as String);
      expect(requests, hasLength(1));
      expect((await service.jobs(person.id)).first['status'], 'done');
      expect((await db.query('TwitterDrafts')).single['consumed'], 1);
    },
  );
  test(
    'Malformed paid response is cached with no partial publication',
    () async {
      respond = (_) async => const AIResponse('invalid json', 10, 5);
      await expectLater(
        service.generateClubPost(person, 'Renovação.'),
        throwsFormatException,
      );
      final job = (await service.jobs(person.id)).first;
      await service.retry(person, job['id'] as String);
      expect(requests, hasLength(1));
      expect(await db.query('TwitterPosts'), isEmpty);
      expect((await service.jobs(person.id)).first['status'], 'failed');
    },
  );
  test(
    'Club rewrite preserves announcement context without latest-fixture bias',
    () async {
      await service.generateClubPost(person, 'Renovamos com o capitão.');
      final root = (await store.posts(person.id)).single;
      await service.regeneratePost(person, root);
      expect(
        (requests.last['officialPostRequest'] as Map)['context'],
        'Renovamos com o capitão.',
      );
      expect(
        (await store.posts(person.id)).single['text'],
        contains('Nosso capitão'),
      );
    },
  );
  test('Feed regeneration targets only its own generation', () async {
    await seedNews();
    await service.generateMore(person, background: false);
    final first = (await store.posts(person.id))
        .firstWhere((p) => p['eventType'] == 'feed');
    await service.regenerateEvent(person, first);
    if (service.isBusy(person.id)) {
      final idle = Completer<void>();
      void onChanged() {
        if (!service.isBusy(person.id) && !idle.isCompleted) idle.complete();
      }

      store.addListener(onChanged);
      await idle.future.timeout(const Duration(seconds: 10));
      store.removeListener(onChanged);
    }
    expect(
      (await store.posts(person.id)).where((p) => p['eventType'] == 'feed'),
      hasLength(4),
    );
    expect(await store.post(person.id, 'news'), isNotNull);
    expect(await store.post(person.id, 'user'), isNotNull);
    expect((await service.jobs(person.id)).first['status'], 'done');
  });
  test(
    'Club publication works in a player career without any fixtures',
    () async {
      final player = reviewPerson(
        category: PersonCategory.player,
        id: 'player',
      );
      await db.insert('Persons', player.toMap());
      await service.generateClubPost(
        player,
        'O clube anuncia uma ação com a torcida.',
        date: DateTime(2027, 1, 12),
      );
      final posts = await store.posts(player.id);
      expect(posts, hasLength(1));
      expect(posts.single['category'], 'club');
      expect(posts.single['accountId'], 'player:club:1014:40-13');
      expect((requests.single['context'] as Map)['career']['mode'], 'player');
    },
  );
  test(
    'Selected historical day excludes later feed stories and matches',
    () async {
      await seedNews();
      await db.insert('ManagerFixtures', reviewFixture(1));
      await service.generateClubPost(
        person,
        'Comunicado de janeiro.',
        date: DateTime(2026, 1, 20),
      );
      final context = requests.single['context'] as Map;
      expect(context['recentFeed'], isEmpty);
      expect(jsonEncode(context), isNot(contains('O capitão fica')));
      expect(context['career']['date'], '2026-01-20');
    },
  );
  Future<void> seedSigning({
    TransferPreviousClubStats? prior,
    String id = 'signing',
  }) async {
    await db.insert('CustomCreatedPlayer', {
      'id': 'new-player',
      'personId': person.id,
      'name': 'Novo atacante',
      'positionId': '25',
      'overall': 80,
      'potential': 85,
      'realFace': 0,
      'fromRealPlayer': 0,
      'foot': 'right',
    });
    await db.insert('TeamPlayer', {
      'id': 'new-roster',
      'personId': person.id,
      'seasonId': 's2026',
      'playerId': 'new-player',
      'isBench': 1,
    });
    await db.insert('TeamTransferItem', {
      'id': id,
      'personId': person.id,
      'seasonId': 's2026',
      'playerInstanceId': 'new-player',
      'type': 'buy',
      'fromTeamId': 'previous-club',
      'toTeamId': person.teamId,
      'toLeagueId': person.leagueId,
      'date': '2026-02-20',
      'previousClubStats': prior?.encode(),
    });
  }

  test(
    'Signing with no records tells AI unknown, never no games this season',
    () async {
      await seedSigning();
      await service.generateTransfer(person, 'signing');
      final context = requests.first['context'] as Map;
      final prior = context['transfer']['previousClubPerformance'] as Map;
      expect(prior['status'], 'unknown');
      expect(prior.containsKey('matches'), false);
      expect(context['recentPlayerPerformances'], isEmpty);
      expect(
        jsonEncode(context['squad']),
        contains('sem atuações registradas pelo clube nesta temporada'),
      );
      expect(jsonEncode(context), isNot(contains('não jogou na temporada')));
      expect(
        systems.first,
        contains(
          'Ausência de partidas registradas é falta de informação, não zero jogos.',
        ),
      );
    },
  );

  test('Previous-club numbers reach transfer and later match context without adding to current club', () async {
    final prior = TransferPreviousClubStats(
      asOfDate: DateTime(2026, 2, 20),
      matches: 15,
      goals: 14,
      assists: 5,
      averageRating: 7.8,
      notes: 'Titular em boa fase.',
    );
    await seedSigning(prior: prior);
    await service.generateTransfer(person, 'signing');
    final context = requests.first['context'] as Map;
    final performance = context['transfer']['previousClubPerformance'] as Map;
    expect(performance['status'], 'provided');
    expect(performance['clubId'], 'previous-club');
    expect(performance['scope'], 'previousClubOnly');
    expect(performance['matches'], 15);
    expect(performance['goals'], 14);
    expect(performance['averageRating'], 7.8);
    expect(performance['notes'], 'Titular em boa fase.');
    final fixture = {...reviewFixture(0), 'date': '2026-02-21'};
    await db.insert('ManagerFixtures', fixture);
    await db.insert(
      'ManagerFixturePlayerPerformances',
      ManagerFixturePlayerPerformance(
        personId: person.id,
        fixtureId: 'f0',
        playerInstanceId: 'new-player',
        avgRating: 6.8,
        goalsCount: 0,
      ).toMap(),
    );
    final summary = await TwitterCareerSummary.load(
      db,
      person,
      teamId: person.teamId,
      date: '2026-02-21',
      seasonId: 's2026',
    );
    final line = summary.squadLines().single;
    expect(
      line,
      contains('pelo clube nesta temporada: 1 jogos registrados, 0 gols'),
    );
    expect(line, contains('15 jogos, 14 gols, 5 assistências'));
    expect(line, contains('no clube anterior'));
    expect(await db.query('ManagerFixturePlayerPerformances'), hasLength(1));
  });

  test('A departing player carries the whole club history across seasons, separately from last-five form', () async {
    await seedSigning();
    await SqlService.ensurePerformanceStatsSchema(db);
    await db.insert('Seasons', reviewSeason(id: 's2027', year: 2027).toMap());
    for (var i = 0; i < 10; i++) {
      final season = i < 3 ? 's2026' : 's2027';
      await db.insert('ManagerFixtures', {
        ...reviewFixture(i, season: season),
        'date': i < 3 ? '2026-06-${10 + i}' : '2027-06-${10 + i}',
        'playerTeamId': i == 8 ? 'other-club' : person.teamId,
        if (i == 9) 'date': '2028-01-01',
      });
      await db.insert('ManagerFixturePlayerPerformances', {
        'id': 'full-$i',
        'personId': person.id,
        'fixtureId': 'f$i',
        'playerInstanceId': 'new-player',
        'goalsCount': i < 3
            ? 2
            : i >= 8
            ? 99
            : 0,
        'assistsCount': i < 3 ? 1 : 0,
        'avgRating': i < 3 ? 8.0 : 6.0,
        'recordedMinutes': 60,
        'recordedStarted': 1,
        'passes': 20,
        'passAccuracy': i < 3 ? 90 : 70,
        'apiStats': jsonEncode({
          'expectedAssists': 0.5,
          'passesUnderPressure': 10,
          'passesCompletedUnderPressure': 8,
        }),
      });
    }
    await db.insert('ManagerFixturePlayerPerformances', {
      'id': 'revised',
      'personId': person.id,
      'fixtureId': 'f0',
      'playerInstanceId': 'new-player',
      'goalsCount': 3,
      'assistsCount': 2,
      'avgRating': 9.0,
      'recordedMinutes': 90,
      'recordedStarted': 1,
      'passes': 40,
      'passAccuracy': 100,
      'apiStats': jsonEncode({
        'expectedAssists': 1.5,
        'passesUnderPressure': 20,
        'passesCompletedUnderPressure': 18,
      }),
    });
    await db.insert('TeamTransferItem', {
      'id': 'farewell',
      'personId': person.id,
      'seasonId': 's2027',
      'playerInstanceId': 'new-player',
      'type': 'endOfLoan',
      'endOfLoanDirection': 'fromYourClub',
      'fromTeamId': person.teamId,
      'fromLeagueId': person.leagueId,
      'toTeamId': 'parent',
      'toLeagueId': person.leagueId,
      'date': '2027-12-31',
    });
    await service.generateTransfer(person, 'farewell');
    final context = requests.first['context'] as Map;
    final history = context['playerClubHistory'] as Map;
    final totals = history['totals'] as Map;
    expect(totals['appearances'], 8);
    expect(totals['goals'], 7);
    expect(totals['assists'], 4);
    expect(totals['minutes'], 510);
    expect(totals['averageRating'], closeTo(55 / 8, 0.001));
    expect(
      totals['weightedAccuracies']['passAccuracy']['percentage'],
      closeTo(730 / 9, .001),
    );
    expect(totals['advancedStats']['expectedAssists']['value'], 5);
    expect(
      totals['advancedStats']['pressurePassAccuracy']['value'],
      closeTo(7400 / 90, .001),
    );
    expect(history['seasons'], hasLength(2));
    expect(history['competitions'], hasLength(1));
    final recent = context['recentPlayerPerformances'] as List;
    expect(recent, hasLength(5));
    expect(recent.every((p) => p['goalsCount'] == 0), isTrue);
    expect(systems.first, contains('playerClubHistory'));
  });

  test(
    'Future previous-club snapshot is excluded from an older transfer event',
    () async {
      await seedSigning(
        prior: TransferPreviousClubStats(
          asOfDate: DateTime(2026, 3),
          matches: 99,
          goals: 88,
        ),
      );
      await service.generateTransfer(person, 'signing');
      final context = requests.first['context'] as Map;
      expect(
        context['transfer']['previousClubPerformance']['status'],
        'unknown',
      );
      expect(jsonEncode(context), isNot(contains('99 jogos')));
      expect(jsonEncode(context), isNot(contains('88 gols')));
    },
  );

  test(
    'Incoming exchange player carries its own previous-club performance',
    () async {
      await seedSigning(
        prior: TransferPreviousClubStats(
          asOfDate: DateTime(2026, 2, 20),
          matches: 18,
          assists: 7,
        ),
        id: 'sale:exchange',
      );
      await db.insert('CustomCreatedPlayer', {
        'id': 'outgoing',
        'personId': person.id,
        'name': 'Jogador vendido',
        'positionId': '14',
        'overall': 78,
        'potential': 80,
        'realFace': 0,
        'fromRealPlayer': 0,
        'foot': 'right',
      });
      await db.insert('TeamTransferItem', {
        'id': 'sale',
        'personId': person.id,
        'seasonId': 's2026',
        'playerInstanceId': 'outgoing',
        'type': 'sell',
        'fromTeamId': person.teamId,
        'fromLeagueId': person.leagueId,
        'toTeamId': 'previous-club',
        'date': '2026-02-20',
      });
      await service.generateTransfer(person, 'sale');
      final transfer = requests.first['context']['transfer'] as Map;
      expect(transfer['exchangePlayer'], 'Novo atacante');
      expect(transfer.containsKey('previousClubPerformance'), false);
      final prior = transfer['exchangePreviousClubPerformance'] as Map;
      expect(prior['matches'], 18);
      expect(prior['assists'], 7);
      expect(prior.containsKey('goals'), false);
      expect(
        jsonEncode(requests.first['context']['squad']),
        contains('18 jogos, 7 assistências'),
      );
    },
  );

  test(
    'Legacy schema migration preserves jobs and remains repeatable',
    () async {
      await db.insert('TwitterGenerations', {
        'id': 'old',
        'personId': person.id,
        'fixtureId': 'f0',
        'createdAt': '2026-01-01',
        'updatedAt': '2026-01-01',
      });
      await db.execute(
        'ALTER TABLE TwitterGenerations DROP COLUMN contextJson',
      );
      await post('existingPost', 'Um post preservado');
      await db.execute('ALTER TABLE TwitterPosts DROP COLUMN sourceDate');
      await db.execute('ALTER TABLE TwitterPosts DROP COLUMN sourcePostId');
      await db.execute(
        'ALTER TABLE TwitterSettings DROP COLUMN generateOpponentPost',
      );
      await createTwitterSchema(db);
      await createTwitterSchema(db);
      expect((await db.query('TwitterGenerations')).single['id'], 'old');
      expect(
        (await db.query('TwitterPosts')).single['text'],
        'Um post preservado',
      );
      expect((await db.query('TwitterPosts')).single['sourceDate'], isNull);
      expect(
        (await store.preferences(person.id)).generateOpponentPost,
        isFalse,
      );
      expect(
        (await db.rawQuery('PRAGMA table_info(TwitterGenerations)'))
            .map((r) => r['name']),
        contains('contextJson'),
      );
    },
  );
  test('Nested replies receive the full target and original conversation', () async {
    final original =
        'Precisamos manter a base do clube. ${'Vamos com calma. ' * 8}';
    final target =
        'Discordo da venda: precisamos desse jogador no mata-mata. ${'Esse é meu argumento. ' * 5}';
    await post('root', original);
    await post('answer', 'A venda pode ajudar o orçamento.', parent: 'root');
    await post('target', target, parent: 'answer');
    await db.update(
      'TwitterPosts',
      {'replyTotal': 5},
      where: 'id = ?',
      whereArgs: ['target'],
    );
    await service.generateReplies(
      person,
      (await store.post(person.id, 'target'))!,
    );
    final request = requests.single;
    expect((request['originalPost'] as Map)['text'], original);
    expect((request['replyTarget'] as Map)['text'], target);
    expect((request['replyTarget'] as Map)['inReplyToId'], 'answer');
    expect((request['conversation'] as List).map((r) => r['id']), [
      'root',
      'answer',
      'target',
    ]);
    expect(request['task'], contains('Responda diretamente'));
    expect(
      request['task'],
      contains('não volte a comentar apenas o post original'),
    );
    expect((await store.posts(person.id, parentId: 'target')).length, 2);
    expect(await store.posts(person.id, parentId: 'answer'), hasLength(1));
  });

  test(
    'Deep conversations preserve the original post beyond six ancestors',
    () async {
      for (var i = 0; i < 10; i++) {
        await post(
          'chain$i',
          'Argumento $i',
          parent: i == 0 ? null : 'chain${i - 1}',
        );
      }
      await db.update(
        'TwitterPosts',
        {'replyTotal': 2},
        where: 'id = ?',
        whereArgs: ['chain9'],
      );
      await service.generateReplies(
        person,
        (await store.post(person.id, 'chain9'))!,
      );
      expect((requests.single['originalPost'] as Map)['id'], 'chain0');
      expect(requests.single['conversation'], hasLength(10));
      expect((requests.single['replyTarget'] as Map)['id'], 'chain9');
    },
  );

  testWidgets('Post tiles show each total even with only two saved replies', (
    tester,
  ) async {
    late List<SocialRow> rows;
    await tester.runAsync(() async {
      await post('root', 'Primeiro post');
      await post('other', 'Outro post');
      await post(
        'nested',
        'Uma resposta com sua própria conversa',
        parent: 'root',
      );
      for (final (id, total) in [('root', 9), ('other', 21), ('nested', 6)]) {
        await db.update(
          'TwitterPosts',
          {'replyTotal': total},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      await post('rootReply', 'Resposta já gerada', parent: 'root');
      for (final id in ['other', 'nested']) {
        for (var i = 0; i < 2; i++) {
          await post('$id$i', 'Resposta já gerada $i', parent: id);
        }
      }
      rows = [
        for (final id in ['root', 'other', 'nested'])
          (await store.post(person.id, id))!,
      ];
      expect(rows.map((row) => row['loadedRepliesCount']), [2, 2, 2]);
    });
    for (final expanded in [false, true]) {
      for (final row in rows) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TwitterPostTile(
                person: person,
                row: row,
                expanded: expanded,
              ),
            ),
          ),
        );
        expect(find.text('${row['repliesCount']}'), findsOneWidget);
        expect(find.text('2'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    }
    expect(requests, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Thread loads saved replies before requesting more from AI', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await post('root', 'Um post de conversa');
      await db.update(
        'TwitterPosts',
        {'replyTotal': 8},
        where: 'id = ?',
        whereArgs: ['root'],
      );
      for (var i = 0; i < 7; i++) {
        await post('saved$i', 'Resposta salva $i', parent: 'root');
      }
      expect((await store.post(person.id, 'root'))!['repliesCount'], 8);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TwitterThreadPage(
          person: person,
          postId: 'root',
          store: store,
          generator: service,
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
    }

    await settle();
    expect(requests, isEmpty);
    expect(find.text('Respostas · 8'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    final scroll = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Resposta salva 6'),
      300,
      scrollable: scroll,
    );
    expect(find.text('Resposta salva 6'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Carregar mais respostas'),
      300,
      scrollable: scroll,
    );
    await tester.runAsync(() async {
      await db.update(
        'TwitterPosts',
        {'replyTotal': 10},
        where: 'id = ?',
        whereArgs: ['root'],
      );
      await post('saved7', 'Resposta salva 7', parent: 'root');
      await post('saved8', 'Resposta salva 8', parent: 'root');
      await db.update(
        'TwitterPosts',
        {'createdAt': '2026-02-20T13:00:00.000'},
        where: 'id IN (?, ?)',
        whereArgs: ['saved7', 'saved8'],
      );
    });
    await tester.tap(find.text('Carregar mais respostas'));
    await settle();
    expect(requests, isEmpty);
    await tester.scrollUntilVisible(
      find.text('Resposta salva 8'),
      300,
      scrollable: scroll,
    );
    expect(find.text('Resposta salva 8'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Carregar mais respostas'),
      300,
      scrollable: scroll,
    );
    await tester.tap(find.text('Carregar mais respostas'));
    await settle();
    expect(requests, hasLength(1));
    expect(requests.single['exactCount'], 1);
    expect(
      (await tester.runAsync(
        () => store.posts(person.id, parentId: 'root', limit: null),
      )),
      hasLength(10),
    );
    expect(find.text('Carregar mais respostas'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Um post de conversa'),
      -300,
      scrollable: scroll,
    );
    expect(find.text('Respostas · 10'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Nested conversation stays linear on a narrow screen', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await loadPreviewFonts();
      await post('root', 'O clube vai manter a base para a próxima temporada.');
      await post(
        'answer',
        'E o atacante? A renovação dele também está confirmada?',
        parent: 'root',
      );
      await post(
        'answer2',
        'Ainda estamos negociando. A ideia é manter ele no elenco.',
        account: 'career:user',
        type: 'user',
        parent: 'answer',
      );
      await post(
        'answer3',
        'Boa! É disso que eu estava falando, ele precisa ficar.',
        parent: 'answer2',
      );
    });
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => RepaintBoundary(
          key: boundary,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.1)),
            child: child!,
          ),
        ),
        home: TwitterThreadPage(
          person: person,
          postId: 'answer2',
          store: store,
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    final tiles = tester
        .widgetList<TwitterPostTile>(find.byType(TwitterPostTile))
        .toList();
    expect(tiles.map((t) => t.row['id']), [
      'root',
      'answer',
      'answer2',
      'answer3',
    ]);
    expect(tiles.take(2).every((t) => t.connected), isTrue);
    expect(tiles[2].replyHandle, 'LuaTricolor');
    expect(tiles[3].replyHandle, isNotEmpty);
    expect(tester.takeException(), isNull);
    final output = Platform.environment['FC_SCORE_PREVIEW_DIR'];
    if (output != null) {
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$output/twitter-conversation.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'Reply count includes old generated batches and excludes deleted replies',
    () async {
      await post('root', 'Post antigo');
      await db.update(
        'TwitterPosts',
        {'replyTotal': 2},
        where: 'id = ?',
        whereArgs: ['root'],
      );
      for (var i = 0; i < 7; i++) {
        await post('old$i', 'Resposta $i', parent: 'root', deleted: i == 6);
      }
      await post(
        'userReply',
        'Resposta do usuário',
        account: 'career:user',
        parent: 'root',
      );
      final root = (await store.post(person.id, 'root'))!;
      expect(root['repliesCount'], 7);
      expect(root['loadedRepliesCount'], 7);
      expect(root['generatedRepliesCount'], 7);
      expect(
        await store.posts(person.id, parentId: 'root', limit: null),
        hasLength(7),
      );
    },
  );

  test('Rejects empty brief and unavailable AI before queueing', () async {
    await expectLater(
      service.generateClubPost(person, '   '),
      throwsFormatException,
    );
    ready = false;
    await expectLater(
      service.generateClubPost(person, 'Renovação'),
      throwsFormatException,
    );
    expect(await service.jobs(person.id), isEmpty);
    expect(requests, isEmpty);
  });
}
