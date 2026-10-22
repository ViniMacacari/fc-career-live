import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/TeamCenter/TeamCenterData.dart';
import 'package:mcmanager/ManagerCareer/PlayersStat/PlayersStatData.dart';
import 'package:mcmanager/ManagerCareer/PlayersStat/RecordedPlayerStats.dart';
import 'package:mcmanager/ManagerCareer/PlayersStat/PlayerActivityAnalysis.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileData.dart';
import 'package:mcmanager/Trophies/TrophyGalleryData.dart';
import 'package:mcmanager/utils/InjuryStatus.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:mcmanager/utils/SqlService.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'career_hub_fixture.dart';
import 'season_review_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late SqlService sql;
  final person = reviewPerson();
  test('Activity rates use matching samples and omit unknown denominators', () {
    PlayerMatchData appearance(String date, Map<String, Object?> fields) =>
        PlayerMatchData({
          'id': date,
          'fixtureId': date,
          'personId': 'career',
          'playerInstanceId': 'p1',
          'date': date,
          ...fields,
        });
    final analysis = PlayerActivityAnalysis([
      appearance('2028-06-01', {
        'goalsCount': 2,
        'assistsCount': 1,
        'playerTeamScore': 5,
        'shotsCount': 4,
        'recordedMinutes': 90,
        'recordedStarted': 1,
      }),
      appearance('2028-06-02', {
        'goalsCount': 1,
        'assistsCount': 0,
        'playerTeamScore': 2,
        'shotsCount': 2,
        'recordedMinutes': 30,
        'recordedStarted': 0,
      }),
      appearance('2028-06-03', {'goalsCount': 40}),
      appearance('2028-06-04', {'recordedMinutes': 90}),
    ]);
    final per90 = analysis.per90(PlayersStatMetric.goals)!;
    expect(per90.value, 2.25);
    expect(per90.games, 2);
    expect(per90.denominator, 120);
    expect(analysis.goalParticipation!.value, closeTo(4 * 100 / 7, .001));
    expect(analysis.conversion!.value, 50);
    expect(analysis.startRate!.value, 50);
    expect(
      PlayerActivityAnalysis([appearance('2028-06-01', {})])
          .per90(PlayersStatMetric.goals),
      isNull,
    );
    final form = PlayerActivityAnalysis([
      for (var day = 1; day <= 10; day++)
        appearance('2028-06-${day.toString().padLeft(2, '0')}', {
          'avgRating': day > 5 ? 8 : 6,
        }),
    ]);
    expect(form.ratingChange, 2);
    expect(form.averageRating(form.recent), 8);
  });
  setUpAll(() async {
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory('build/career-hub-docs').absolute.path,
        );
    await GameCatalog.load();
  });
  setUp(() async {
    db = await createHubFixture();
    sql = SqlService.withDatabase(db);
  });
  tearDown(() => db.close());

  test('Groups trophies by competition and preserves counts without inventing years', () async {
    final data = await TrophyGalleryData.load(person, sql: sql);
    expect(data.count, 4);
    final cup = data.groups.singleWhere((g) => g.id == 'cup');
    expect(cup.name, 'Copa da Carreira');
    expect(cup.count, 3);
    expect(cup.editions.map((e) => e.year), ['2028', '2027']);
    expect(
      data.groups
          .singleWhere((g) => g.name == 'Taça sem vínculo')
          .editions
          .single
          .year,
      'Ano não informado',
    );
  });
  test('Campaign stops at the conquest and excludes other clubs, competitions and seasons', () async {
    final trophy = (await sql.getTrophies(person.id))
        .singleWhere((t) => t['id'] == 'auto:s2028:cup');
    final campaign = await TrophyCampaignData.load(
      person,
      trophy,
      'cup',
      sql: sql,
    );
    expect(campaign.fixtures.map((f) => f['id']), ['round', 'final']);
    expect(campaign.sum('playerTeamScore'), 3);
    expect(campaign.scorers.single.player['name'], 'Arthur Silva');
    expect(campaign.scorers.single.goals, 3);
    expect(campaign.scorers.single.rating, 8.5);
    expect(campaign.assistants.single.assists, 2);
    expect(
      (await TrophyCampaignData.load(person, trophy, null, sql: sql)).fixtures,
      isEmpty,
    );
  });
  test('Availability uses career time, including cross-season injuries, excluding future/recovered/departed players', () async {
    final data = await TeamCenterData.load(person, sql: sql);
    expect(data.date!.year, 2028);
    expect(data.date!.day, 5);
    expect(data.roster, hasLength(2));
    expect(data.injuredPlayers, 1);
    expect(data.available, 1);
    expect(
      data.injuries.map((i) => i['id']),
      unorderedEquals(['active', 'older-active']),
    );
    expect(data.academy, hasLength(1));
    expect(data.averageOverall, 82);
    expect(data.fixtures, hasLength(4));
  });
  test('Recovery day is available and a future injury is inactive', () {
    expect(
      isActiveInjury({
        'startDate': '2028-06-02',
        'endDate': '2028-06-05',
      }, DateTime(2028, 6, 5)),
      isFalse,
    );
    expect(
      isActiveInjury({'startDate': '2028-06-06'}, DateTime(2028, 6, 5)),
      isFalse,
    );
  });

  test(
    'Duplicate legacy appearance rows are counted once in a campaign',
    () async {
      final performance = (await db.query(
        'ManagerFixturePlayerPerformances',
        where: 'id = ?',
        whereArgs: ['perf-round'],
      )).single;
      await db.insert('ManagerFixturePlayerPerformances', {
        ...performance,
        'id': 'duplicate',
      });
      final trophy = (await sql.getTrophies(person.id))
          .singleWhere((t) => t['id'] == 'auto:s2028:cup');
      final campaign = await TrophyCampaignData.load(
        person,
        trophy,
        'cup',
        sql: sql,
      );
      expect(campaign.scorers.single.goals, 3);
      expect(campaign.scorers.single.games, 2);
    },
  );
  test('Timed substitutions contribute minutes without assuming unknown full matches', () {
    PlayerMatchData appearance(Map<String, Object?> fields) => PlayerMatchData({
      'id': 'minutes',
      'personId': 'career',
      'fixtureId': 'minutes',
      'playerInstanceId': 'p1',
      ...fields,
    });
    expect(registeredPlayerMinutes(appearance({})), isNull);
    expect(
      registeredPlayerMinutes(
        appearance({'substitutionDetails': '[{"type":"inGame","minute":60}]'}),
      ),
      30,
    );
    expect(
      registeredPlayerMinutes(
        appearance({
          'recordedMinutes': 28,
          'substitutionDetails': '[{"type":"inGame","minute":60}]',
        }),
      ),
      28,
    );
    expect(
      registeredPlayerMinutes(
        appearance({
          'extraTime': 1,
          'substitutionDetails': '[{"type":"inGame","minute":100}]',
        }),
      ),
      20,
    );
  });
  test('Recorded metrics retain real zeros, leave missing fields unknown and weight API accuracy', () async {
    final rows = await sql.getManagerStatisticsMatchRows(
      person.id,
      seasonId: 's2028',
    );
    final matches = rows
        .where(
          (r) =>
              r['playerInstanceId'] == 'p1' &&
              ['round', 'final'].contains(r['fixtureId']),
        )
        .map(PlayerMatchData.new)
        .toList();
    final stats = RecordedPlayerStats(matches);
    expect(stats[PlayersStatMetric.goals], 3);
    expect(stats[PlayersStatMetric.minutes], 170);
    expect(stats[PlayersStatMetric.passAccuracy], 58);
    final unknown = RecordedPlayerStats([
      PlayerMatchData({
        'id': 'unknown',
        'personId': 'career',
        'fixtureId': 'unknown',
        'playerInstanceId': 'p1',
        'goalDetails': '[]',
        'assistDetails': '[]',
      }),
    ]);
    expect(unknown[PlayersStatMetric.goals], isNull);
    expect(unknown[PlayersStatMetric.minutes], isNull);
    expect(unknown[PlayersStatMetric.rating], isNull);
    final legacy = RecordedPlayerStats([
      PlayerMatchData({
        'id': 'legacy',
        'personId': 'career',
        'fixtureId': 'old',
        'playerInstanceId': 'p1',
        'goalsCount': 2,
      }),
    ]);
    expect(legacy[PlayersStatMetric.penalties], isNull);
    final zero = RecordedPlayerStats([
      PlayerMatchData(rows.singleWhere((r) => r['playerInstanceId'] == 'p2')),
    ]);
    expect(zero[PlayersStatMetric.goals], 0);
    expect(zero[PlayersStatMetric.saves], 4);
  });
}
