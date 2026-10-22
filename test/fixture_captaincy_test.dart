import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/PlayersStat/PlayersStatData.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileData.dart';
import 'package:mcmanager/models/FixtureCaptaincy.dart';
import 'package:mcmanager/models/ManagerFixturePlayerPerformance.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  List<ManagerFixturePlayerPerformance> lineup() => [
    ManagerFixturePlayerPerformance(
      personId: 'career',
      fixtureId: 'f',
      playerInstanceId: 'a',
      substitutionDetails: [
        PerformanceSubstitutionDetails(
          id: 'out-a',
          minute: 65,
          type: SubstitutionType.outGame,
          anotherPlayerId: 'b',
        ),
      ],
    ),
    ManagerFixturePlayerPerformance(
      personId: 'career',
      fixtureId: 'f',
      playerInstanceId: 'b',
      substitutionDetails: [
        PerformanceSubstitutionDetails(
          id: 'in-b',
          minute: 65,
          type: SubstitutionType.inGame,
        ),
        PerformanceSubstitutionDetails(
          id: 'out-b',
          minute: 82,
          type: SubstitutionType.outGame,
        ),
      ],
    ),
    ManagerFixturePlayerPerformance(
      personId: 'career',
      fixtureId: 'f',
      playerInstanceId: 'c',
    ),
    ManagerFixturePlayerPerformance(
      personId: 'career',
      fixtureId: 'f',
      playerInstanceId: 'left',
      substitutionDetails: [
        PerformanceSubstitutionDetails(
          minute: 60,
          type: SubstitutionType.outGame,
        ),
      ],
    ),
    ManagerFixturePlayerPerformance(
      personId: 'career',
      fixtureId: 'f',
      playerInstanceId: 'later',
      substitutionDetails: [
        PerformanceSubstitutionDetails(
          minute: 80,
          type: SubstitutionType.inGame,
        ),
      ],
    ),
  ];
  test('Optional captaincy does not invent a captain for old matches', () {
    for (final raw in [null, '', 'not-json', '{}']) {
      final c = FixtureCaptaincy.decode(raw);
      expect(c.isRecorded, isFalse);
      expect(c.encode(), isNull);
      expect(c.pending(lineup()), isNull);
    }
  });
  test('Captain substitution supports a different teammate and subsequent handover', () {
    final all = lineup();
    var c = const FixtureCaptaincy(initialPlayerId: 'a');
    final first = c.pending(all)!;
    expect(first.substitution.minute, 65);
    expect(c.candidates(all, first), unorderedEquals(['b', 'c']));
    c = c.assign(first, 'b');
    final second = c.pending(all)!;
    expect(second.playerId, 'b');
    expect(c.candidates(all, second), unorderedEquals(['c', 'later']));
    c = c.assign(second, 'c');
    expect(c.pending(all), isNull);
    expect(c.players(all), {'a', 'b', 'c'});
    expect(FixtureCaptaincy.decode(c.encode()).players(all), {'a', 'b', 'c'});
  });
  test('Correcting substitution minutes keeps identities; deleting an event removes stale handovers', () {
    final all = lineup();
    var c = const FixtureCaptaincy(initialPlayerId: 'a');
    c = c.assign(c.pending(all)!, 'b');
    c = c.assign(c.pending(all)!, 'c');
    all.first.substitutionDetails.first.minute = 70;
    expect(c.departures(all).first.substitution.minute, 70);
    expect(c.reconciled(all).players(all), {'a', 'b', 'c'});
    all.first.substitutionDetails.clear();
    expect(c.reconciled(all).handovers, isEmpty);
    expect(c.reconciled(all).players(all), {'a'});
    expect(c.reconciled(all.skip(1)).encode(), isNull);
  });
  test('Leaving the next captain unknown is explicit, optional and survives reopening', () {
    final all = lineup();
    var c = const FixtureCaptaincy(initialPlayerId: 'a');
    c = c.assign(c.pending(all)!, null);
    final restored = FixtureCaptaincy.decode(c.encode());
    expect(restored.pending(all), isNull);
    expect(restored.departures(all).single.handover!.playerId, isNull);
    expect(restored.players(all), {'a'});
  });
  test('Stats count starts and handovers per game, preserving missing optional information', () {
    final c = FixtureCaptaincy(
      initialPlayerId: 'a',
      handovers: const [
        CaptainHandover(
          substitutionId: 'out-a',
          fromPlayerId: 'a',
          playerId: 'b',
        ),
      ],
    );
    PlayerMatchData match(String id, Object? captaincy) => PlayerMatchData({
      ...lineup().first.toMap(),
      'playerInstanceId': id,
      'captaincy': captaincy,
    });
    final a = PlayerTotals([match('a', c.encode()), match('a', null)]);
    expect(a.captainGames, 1);
    expect(a.captainStarts, 1);
    final b = PlayerTotals([match('b', c.encode())]);
    expect(b.captainInherited, 1);
    expect(b.captainStarts, 0);
    expect(
      PlayersStatTotals([
        match('b', c.encode()),
      ])[PlayersStatMetric.captainMatches],
      1,
    );
    expect(
      PlayersStatTotals([match('a', null)])[PlayersStatMetric.captainMatches],
      isNull,
    );
  });
  test('Schema migration is repeatable and captaincy is joined into player statistics', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    await SqlService.ensureCompatibleSchema(db);
    await SqlService.ensureFixtureCaptaincySchema(db);
    await SqlService.ensureFixtureCaptaincySchema(db);
    final c = const FixtureCaptaincy(initialPlayerId: 'a').encode();
    await db.insert('ManagerFixtures', {
      'id': 'f',
      'personId': 'career',
      'seasonId': 's',
      'fifaVersion': 'FC26',
      'playerTeamId': 'own',
      'oppositeTeamId': 'other',
      'tournamentId': 'league',
      'date': '2028-01-01',
      'location': 'home',
      'playerTeamScore': 1,
      'oppositeTeamScore': 0,
      'createdAt': '2028-01-01',
      'updatedAt': '2028-01-01',
      'captaincy': c,
    });
    await db.insert('ManagerFixturePlayerPerformances', lineup().first.toMap());
    final rows = await SqlService.withDatabase(db)
        .getPlayerMatchRows('career', 'a');
    expect(rows.single['captaincy'], c);
    expect(PlayerTotals(rows.map(PlayerMatchData.new)).captainStarts, 1);
  });
}
