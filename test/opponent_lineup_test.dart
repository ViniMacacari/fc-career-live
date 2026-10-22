import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/models/ManagerFixture.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/models/OpponentLineup.dart';
import 'package:mcmanager/utils/FixtureTimeline.dart';
import 'package:mcmanager/utils/FootballFormations.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'season_review_fixture.dart';

OpponentLineup namedTeam() {
  var lineup = OpponentLineup.empty();
  for (var i = 0; i < 11; i++) {
    lineup = lineup.rename(lineup.startingIds[i], 'Adversário $i');
  }
  return lineup.addReserve('Reserva');
}

ManagerFixturePlayerPerformance perf(
  String id, {
  List<PerformanceGoalDetails>? goals,
  List<PerformanceSubstitutionDetails>? subs,
  List<PerformanceTimeDetails>? cards,
}) => ManagerFixturePlayerPerformance(
  personId: 'career',
  fixtureId: 'match',
  playerInstanceId: id,
  avgRating: 7.5,
  goalDetails: goals,
  substitutionDetails: subs,
  yellowCardDetails: cards,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('Each opponent formation prepares 11 named slots with a goalkeeper', () {
    for (final label in footballFormations.keys) {
      final lineup = OpponentLineup.empty(formation: label);
      expect(lineup.squad.starters, hasLength(11), reason: label);
      expect(lineup.names.values.every((name) => name.isEmpty), isTrue);
      expect(
        lineup.squad.players[lineup.startingIds.first]?['positionId'],
        '0',
      );
      expect(lineup.performances, isEmpty);
      expect(lineup.hasNames, isFalse);
    }
  });

  test(
    'Changing formation preserves identities, keeper and the related bench',
    () {
      var lineup = namedTeam();
      final ids = lineup.squad.starters.keys.toSet(),
          keeper = lineup.startingIds.first;
      for (final label in footballFormations.keys) {
        lineup = lineup.withFormation(label);
        expect(lineup.squad.starters.keys.toSet(), ids, reason: label);
        expect(lineup.startingIds.first, keeper, reason: label);
        expect(lineup.names[keeper], 'Adversário 0');
        expect(lineup.squad.bench, hasLength(1));
      }
    },
  );

  test(
    'The next match remembers names and shape while resetting performances',
    () {
      var saved = namedTeam().withFormation('3-4-1-2');
      final id = saved.startingIds.last;
      saved = saved.editPerformance(
        perf(
          id,
          goals: [PerformanceGoalDetails(minute: 15)],
          cards: [PerformanceTimeDetails(minute: 70)],
        ),
      );
      final next = saved.forNewMatch();
      expect(next.names, saved.names);
      expect(next.squad.formation, '3-4-1-2');
      expect(next.squad.bench, saved.squad.bench);
      expect(next.performances, isEmpty);
      final changed = next.rename(id, 'Nome corrigido');
      expect(changed.names[id], 'Nome corrigido');
      expect(saved.names[id], isNot('Nome corrigido'));
      expect(saved.performances.single.goalDetails, hasLength(1));
    },
  );

  test('Substitution edits mirror entry and exit and remove deleted links', () {
    var lineup = namedTeam();
    final outgoing = lineup.startingIds.last,
        incoming = lineup.squad.bench.single;
    lineup = lineup.editPerformance(
      perf(
        outgoing,
        subs: [
          PerformanceSubstitutionDetails(
            minute: 69,
            addedMinute: 1,
            type: SubstitutionType.outGame,
            anotherPlayerId: incoming,
            anotherPlayerName: 'Reserva',
          ),
        ],
      ),
    );
    expect(lineup.performances, hasLength(2));
    final entering = lineup.performances
        .where((p) => p.playerInstanceId == incoming)
        .single;
    expect(entering.substitutionDetails.single.type, SubstitutionType.inGame);
    expect(entering.substitutionDetails.single.minute, 69);
    expect(
      entering.substitutionDetails.single.anotherPlayerName,
      lineup.names[outgoing],
    );
    final corrected = lineup.rename(outgoing, 'Atacante novo');
    expect(
      corrected.performances
          .where((p) => p.playerInstanceId == incoming)
          .single
          .substitutionDetails
          .single
          .anotherPlayerName,
      'Atacante novo',
    );
    final p = corrected.performances
        .where((p) => p.playerInstanceId == outgoing)
        .single
        .copy();
    p.substitutionDetails.clear();
    final without = corrected.editPerformance(p);
    expect(
      without.performances.every((p) => p.substitutionDetails.isEmpty),
      isTrue,
    );
    expect(without.squad.bench, [incoming]);
  });

  test('Photos survive new matches and formation changes without changing older snapshots', () {
    final older = namedTeam();
    final id = older.startingIds.last;
    final saved = older
        .withIdentity(
          id,
          name: 'Atacante',
          photo: '/faces/career/opponents/photo.png',
        )
        .editPerformance(perf(id, goals: [PerformanceGoalDetails(minute: 68)]));
    final next = OpponentLineup.decode(saved.encode())!
        .forNewMatch()
        .withFormation('4-2-3-1');
    expect(
      next.squad.players[id]?['customAvatarFilePath'],
      '/faces/career/opponents/photo.png',
    );
    expect(next.names[id], 'Atacante');
    expect(next.performances, isEmpty);
    final changed = next.withIdentity(id, name: 'Novo nome', photo: null);
    expect(changed.squad.players[id]?['customAvatarFilePath'], isNull);
    expect(
      saved.squad.players[id]?['customAvatarFilePath'],
      '/faces/career/opponents/photo.png',
    );
    expect(older.squad.players[id]?['customAvatarFilePath'], isNull);
  });

  test(
    'Renaming a scorer updates generated goals and both sides of assists',
    () {
      var lineup = namedTeam();
      final scorer = lineup.startingIds.last, assistant = lineup.startingIds[8];
      lineup = lineup.editPerformance(
        perf(
          scorer,
          goals: [
            PerformanceGoalDetails(
              id: 'goal',
              minute: 36,
              assistantId: assistant,
              assistantName: lineup.names[assistant],
            ),
          ],
        ),
      );
      final renamed = lineup.rename(scorer, 'Artilheiro');
      expect(renamed.goals.single.scorerName, 'Artilheiro');
      expect(
        renamed.performances
            .where((p) => p.playerInstanceId == assistant)
            .single
            .assistDetails
            .single
            .goalscorerName,
        'Artilheiro',
      );
      expect(lineup.goals.single.scorerName, isNot('Artilheiro'));
    },
  );

  test(
    'Named legacy goals are linked without duplicating the recorded goal',
    () {
      var lineup = namedTeam();
      final id = lineup.startingIds.last;
      final recorded = [
        OpponentGoalDetails(
          id: 'legacy-goal',
          scorerName: lineup.names[id]!,
          minute: 49,
        ),
      ];
      lineup = lineup.withRecordedGoals(recorded);
      expect(lineup.performances, hasLength(1));
      expect(lineup.performances.single.goalDetails.single.id, 'legacy-goal');
      final edited = lineup.performances.single.copy();
      edited.goalDetails.single.minute = 50;
      final after = lineup.editPerformance(edited);
      final merged = after.mergeGoals(recorded, before: lineup);
      expect(merged, hasLength(1));
      expect(merged.single.minute, 50);
      edited.goalDetails.clear();
      expect(
        lineup.editPerformance(edited).mergeGoals(recorded, before: lineup),
        isEmpty,
      );
    },
  );

  test('Opponent timeline includes cards and one substitution without duplicated goals', () {
    var lineup = namedTeam();
    final id = lineup.startingIds.last, sub = lineup.squad.bench.single;
    lineup = lineup.editPerformance(
      perf(
        id,
        goals: [PerformanceGoalDetails(id: 'g', minute: 30)],
        cards: [PerformanceTimeDetails(id: 'c', minute: 60)],
        subs: [
          PerformanceSubstitutionDetails(
            id: 's',
            minute: 70,
            type: SubstitutionType.outGame,
            anotherPlayerId: sub,
            anotherPlayerName: 'Reserva',
          ),
        ],
      ),
    );
    final events = fixtureTimeline(
      fixture: {
        'location': 'home',
        'playerTeamScore': 0,
        'oppositeTeamScore': 1,
        'opponentLineup': lineup.encode(),
        'opponentGoalDetails': encodeOpponentGoals(lineup.goals),
      },
      performances: [],
      names: {},
    );
    expect(events.map((e) => e.kind), [
      FixtureEventKind.goal,
      FixtureEventKind.yellowCard,
      FixtureEventKind.substitution,
    ]);
    expect(events.every((e) => !e.ownTeam), isTrue);
    expect(events.first.homeScore, 0);
    expect(events.first.awayScore, 1);
  });

  test(
    'Opponent lineup and events round trip; malformed snapshots are ignored',
    () {
      var lineup = namedTeam();
      lineup = lineup.editPerformance(
        perf(
          lineup.startingIds.last,
          goals: [PerformanceGoalDetails(minute: 40)],
        ),
      );
      final restored = OpponentLineup.decode(lineup.encode())!;
      expect(restored.names, lineup.names);
      expect(restored.performances.single.avgRating, 7.5);
      expect(restored.goals.single.minute, 40);
      expect(OpponentLineup.decode('broken'), isNull);
      final raw = jsonDecode(lineup.encode());
      raw['squad']['starters'].remove(lineup.startingIds.first);
      expect(OpponentLineup.decode(raw)!.squad.starters, hasLength(10));
      raw['squad']['players'] = 'broken';
      expect(OpponentLineup.decode(raw), isNull);
    },
  );

  test(
    'SQLite memory stays within the career, team, league, edition and past',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(db.close);
      await SqlService.ensureCompatibleSchema(db);
      await db.insert('ManagerFixtures', {
        ...reviewFixture(1),
        'id': 'old-no-lineup',
      });
      await SqlService.ensureOpponentLineupSchema(db);
      await SqlService.ensureOpponentLineupSchema(db);
      expect(
        (await db.query('ManagerFixtures')).single['opponentLineup'],
        isNull,
      );
      final service = SqlService.withDatabase(db), team = namedTeam();
      final identity = team.startingIds.last;
      Future<void> add(
        String id,
        int day,
        String name, {
        String person = 'career',
        String opponent = 'fla',
        String? league = '1014',
        String edition = 'FC26',
        String? raw,
      }) async {
        await db.insert('ManagerFixtures', {
          ...reviewFixture(day),
          'id': id,
          'date': DateTime(2026, 10, day).toIso8601String(),
          'personId': person,
          'fifaVersion': edition,
          'oppositeTeamId': opponent,
          'oppositeTeamLeagueId': league,
          'seasonId': day < 2 ? 'old-season' : 'new-season',
          'opponentLineup': raw ?? team.rename(identity, name).encode(),
        });
      }

      await add('first', 1, 'Primeiro');
      await add('second', 2, 'Segundo');
      await add('future', 20, 'Futuro');
      await add('another-person', 3, 'Outra carreira', person: 'other');
      await add('another-team', 3, 'Outro time', opponent: 'pal');
      await add('another-league', 3, 'Outra liga', league: '111');
      await add('another-edition', 3, 'Outra edição', edition: 'FC27');
      await add('broken', 4, 'Inválido', raw: 'broken');
      final remembered = await service.getRememberedOpponentLineup(
        personId: 'career',
        fifaVersion: 'FC26',
        teamId: 'fla',
        leagueId: '1014',
        beforeDate: DateTime(2026, 10, 9),
      );
      expect(remembered?.names[identity], 'Segundo');
      expect(remembered?.performances, isEmpty);
      final earlier = await service.getRememberedOpponentLineup(
        personId: 'career',
        fifaVersion: 'FC26',
        teamId: 'fla',
        leagueId: '1014',
        beforeDate: DateTime(2026, 10, 2),
        excludeFixtureId: 'second',
      );
      expect(earlier?.names[identity], 'Primeiro');
      final none = await service.getRememberedOpponentLineup(
        personId: 'career',
        fifaVersion: 'FC26',
        teamId: 'fla',
        leagueId: null,
        beforeDate: DateTime(2026, 10, 9),
      );
      expect(none, isNull);
      expect(await db.query('TeamPlayer'), isEmpty);
      expect(await db.query('ManagerFixturePlayerPerformances'), isEmpty);
    },
  );
}
