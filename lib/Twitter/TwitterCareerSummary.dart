import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../models/ManagerFixture.dart' show OpponentStats;
import '../models/Person.dart';
import '../models/ManagerProfile.dart';
import '../models/PressConference.dart';
import '../models/Season.dart';
import '../models/TeamTransferItem.dart';
import '../models/TransferPreviousClubStats.dart';
import '../utils/GameCatalog.dart';
import '../utils/GamePlayers.dart';
import '../utils/FixtureTablePosition.dart';
import 'TwitterStore.dart';
import 'TwitterPlayerAssessment.dart';

class TwitterCareerSummary {
  TwitterCareerSummary({
    required this.manager,
    required this.currency,
    required this.teamId,
    required this.eventDate,
    required this.seasonId,
    required this.teamName,
    required this.fixtures,
    this.coachName,
    this.coachProfile,
    this.seasons = const [],
    this.tournaments = const {},
    this.trophies = const [],
    this.awards = const {},
    this.performances = const [],
    this.transfers = const [],
    this.squad = const [],
    this.injuries = const [],
    this.playerTransfers = const [],
  });

  final bool manager;
  final String currency, teamId;
  final DateTime eventDate;
  final String? seasonId;
  final String Function(Object? id, Object? league) teamName;

  final String? coachName;
  final ManagerProfile? coachProfile;

  final List<SocialRow> fixtures;
  final List<Season> seasons;
  final Map<Object?, String> tournaments;
  final List<SocialRow> trophies;
  final Map<Object?, String> awards;

  final List<SocialRow> performances;

  final List<SocialRow> transfers;

  final List<SocialRow> squad;
  final List<SocialRow> injuries;

  final List<SocialRow> playerTransfers;

  static Future<TwitterCareerSummary> load(
    Database database,
    Person person, {
    required String teamId,
    required String date,
    String? seasonId,
    bool throughDay = false,
  }) async {
    final manager = person.category == PersonCategory.manager;
    final profile = manager
        ? ManagerProfile.decode(
            (await database.query(
              'Persons',
              columns: ['managerProfile'],
              where: 'id = ?',
              whereArgs: [person.id],
            )).firstOrNull?['managerProfile'],
          )
        : null;
    final catalog = await GameCatalog.load();
    final selectedDate = DateTime.parse(date);
    final eventDate = throughDay
        ? DateTime(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day + 1,
          ).subtract(const Duration(milliseconds: 1))
        : selectedDate;
    if (throughDay) date = eventDate.toIso8601String();
    final seasons = (await database.query(
      'Seasons',
      where: 'personId = ?',
      whereArgs: [person.id],
      orderBy: 'startDate DESC',
    )).map(Season.fromMap).toList();
    seasonId ??= seasons
        .where(
          (s) =>
              !s.startDate.isAfter(selectedDate) &&
              !s.endDate.isBefore(selectedDate),
        )
        .firstOrNull
        ?.id;
    final fixtures = await database.query(
      manager ? 'ManagerFixtures' : 'PlayerFixtures',
      where: 'personId = ? AND julianday(date) <= julianday(?)',
      whereArgs: [person.id, date],
      orderBy: 'julianday(date) DESC, createdAt DESC',
    );
    final tournaments = <Object?, String>{
      for (final league in catalog.leagues(person.fifaVersion))
        'league:${league.id}': league.label,
      for (final t in await catalog.tournaments(person.fifaVersion))
        t.id: t.label,
      for (final t in await database.query(
        'Tournament',
        columns: ['id', 'name'],
      ))
        t['id']: t['name'].toString(),
    };
    final trophies = await database.query(
      'Trophies',
      where: 'personId = ?',
      whereArgs: [person.id],
    );
    final awards = {for (final a in await catalog.awards()) a.id: a.label};
    final injuries = await database.query(
      'Injury',
      where: 'personId = ? AND julianday(startDate) <= julianday(?)',
      whereArgs: [person.id, date],
      orderBy: 'julianday(startDate) DESC',
    );
    var performances = <SocialRow>[], transfers = <SocialRow>[];
    var squad = <SocialRow>[], playerTransfers = <SocialRow>[];
    if (manager) {
      final latest = <String, SocialRow>{};
      for (final row in await database.rawQuery(
        '''SELECT p.rowid AS rid, p.playerInstanceId, p.fixtureId, p.goalsCount,
          p.assistsCount, p.avgRating, p.redCards, f.date, f.seasonId,
          f.playerTeamId, f.playerOfTheMatchId, cp.name, cp.positionId, cp.birthdate
        FROM ManagerFixturePlayerPerformances p
        JOIN ManagerFixtures f ON f.id = p.fixtureId AND f.personId = p.personId
        LEFT JOIN CustomCreatedPlayer cp
          ON cp.id = p.playerInstanceId AND cp.personId = p.personId
        WHERE p.personId = ? AND julianday(f.date) <= julianday(?)''',
        [person.id, date],
      )) {
        final key = '${row['fixtureId']}:${row['playerInstanceId']}';
        if ((latest[key]?['rid'] as int? ?? -1) < (row['rid'] as int)) {
          latest[key] = row;
        }
      }
      performances = latest.values.toList()
        ..sort(
          (a, b) =>
              DateTime.parse(b['date'] as String)
                  .compareTo(DateTime.parse(a['date'] as String)),
        );
      transfers = await database.rawQuery(
        '''SELECT t.*, cp.name AS playerName FROM TeamTransferItem t
        LEFT JOIN CustomCreatedPlayer cp
          ON cp.id = t.playerInstanceId AND cp.personId = t.personId
        WHERE t.personId = ?
          AND julianday(t.date) <= julianday(?)
        ORDER BY julianday(t.date) DESC, t.rowid DESC''',
        [person.id, date],
      );
      if (seasonId != null) {
        squad = await database.rawQuery(
          '''SELECT tp.*, cp.name, cp.positionId, cp.birthdate,
            cp.overall AS baseOverall
          FROM TeamPlayer tp JOIN CustomCreatedPlayer cp
            ON cp.id = tp.playerId AND cp.personId = tp.personId
          WHERE tp.personId = ? AND tp.seasonId = ?''',
          [person.id, seasonId],
        );
      }
    } else {
      playerTransfers = await database.query(
        'PlayerTransferItem',
        where: 'personId = ? AND julianday(transferDate) <= julianday(?)',
        whereArgs: [person.id, date],
        orderBy: 'julianday(transferDate) DESC',
      );
    }
    return TwitterCareerSummary(
      manager: manager,
      coachName: profile?.displayName,
      coachProfile: profile,
      currency: person.currency ?? 'EUR',
      teamId: teamId,
      eventDate: eventDate,
      seasonId: seasonId,
      teamName: (id, league) => id == null || id.toString().isEmpty
          ? '?'
          : catalog.teamLabel(
              person.fifaVersion,
              id.toString(),
              leagueId: league?.toString(),
            ),
      fixtures: FixtureTablePosition.carryForward(fixtures),
      seasons: seasons,
      tournaments: tournaments,
      trophies: trophies,
      awards: awards,
      performances: performances,
      transfers: transfers,
      squad: squad,
      injuries: injuries,
      playerTransfers: playerTransfers,
    );
  }

  static const _goalTypes = {
    'penalty': 'pênalti',
    'directfreekick': 'falta',
    'indirectfreekick': 'falta indireta',
    'cornercick': 'escanteio',
    'counterattack': 'contra-ataque',
    'header': 'cabeça',
    'longshot': 'de fora da área',
    'cross': 'cruzamento',
    'deflected': 'desviado',
    'solo': 'jogada individual',
    'bicyclekick': 'bicicleta',
    'volley': 'voleio',
    'chip': 'cavadinha',
    'rebound': 'rebote',
  };

  static List<String> goalTypes(Object? value) {
    try {
      final decoded = value is String ? jsonDecode(value) : value;
      if (decoded is! List) return const [];
      return [for (final type in decoded) ?_goalTypes[type.toString()]];
    } catch (_) {
      return const [];
    }
  }

  static List<Map<dynamic, dynamic>> events(Object? value) {
    try {
      final decoded = value is String ? jsonDecode(value) : value;
      return decoded is List ? decoded.whereType<Map>().toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  static String? minute(Map<dynamic, dynamic> event) => event['minute'] == null
      ? null
      : "${event['minute']}${event['addedMinute'] == null ? '' : '+${event['addedMinute']}'}'";

  static String day(Object? date) => date.toString().split('T').first;

  static String month(Object? date) {
    final parsed = DateTime.tryParse(date?.toString() ?? '');
    return parsed == null
        ? '?'
        : '${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  static String _number(num value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);

  String money(num value) {
    final text = value >= 1e6
        ? '${_number(value / 1e6)} mi'
        : value >= 1e3
        ? '${_number(value / 1e3)} mil'
        : _number(value);
    return '$text $currency';
  }

  static String letter(SocialRow f) => switch (TwitterStore.fixtureOutcome(f)) {
    'win' || 'winOnPenalties' => 'V',
    'draw' => 'E',
    _ => 'D',
  };

  static bool eliminated(SocialRow f) {
    final outcome = TwitterStore.fixtureOutcome(f);
    if (outcome == 'lossOnPenalties') return true;
    if (outcome != 'loss') return false;
    final stage = f['stage']?.toString().trim().toLowerCase() ?? '';
    return f['extraTime'] == 1 ||
        f['extraTime'] == true ||
        RegExp(r'^(grande )?final$').hasMatch(stage);
  }

  String competition(SocialRow f) {
    final name =
        tournaments[f['tournamentId']] ?? f['tournamentId']?.toString() ?? '?';
    final stage = f['stage']?.toString().trim() ?? '';
    return stage.isEmpty ? name : '$name, $stage';
  }

  String seasonLabel(Object? id) {
    final s = seasons.where((s) => s.id == id).firstOrNull;
    if (s == null) return '?';
    return s.startDate.year == s.endDate.year
        ? '${s.startDate.year}'
        : '${s.startDate.year}/${s.endDate.year % 100}';
  }

  String result(SocialRow f, {bool date = false, bool where = true}) {
    final penalties = f['playerTeamPenaltiesScore'] == null
        ? ''
        : ' (pên. ${f['playerTeamPenaltiesScore']}x${f['oppositeTeamPenaltiesScore']})';
    final place = switch (f['location']) {
      'home' => 'casa',
      'away' => 'fora',
      _ => 'neutro',
    };
    return [
      if (date) day(f['date']),
      '${letter(f)} ${f['playerTeamScore']}x${f['oppositeTeamScore']}$penalties',
      'vs ${teamName(f['oppositeTeamId'], f['oppositeTeamLeagueId'])}',
      if (where) '(${competition(f)}, $place)',
    ].join(' ');
  }

  static String record(Iterable<SocialRow> list) {
    var games = 0, w = 0, d = 0, l = 0, goalsFor = 0, goalsAgainst = 0;
    for (final f in list) {
      final a = (f['playerTeamScore'] as num?)?.toInt() ?? 0;
      final b = (f['oppositeTeamScore'] as num?)?.toInt() ?? 0;
      games++;
      if (a > b) {
        w++;
      } else if (a < b) {
        l++;
      } else {
        d++;
      }
      goalsFor += a;
      goalsAgainst += b;
    }
    return '$games jogos: ${w}V ${d}E ${l}D, $goalsFor gols pró e $goalsAgainst contra';
  }

  String _rating(num value) => value.toStringAsFixed(1);

  List<SocialRow> get _club =>
      fixtures.where((f) => f['playerTeamId'] == teamId).toList();

  Map<String, Object?> momentum() {
    final club = _club;
    if (club.isEmpty) return const {};
    var winless = 0, losing = 0, winning = 0;
    for (final f in club) {
      if (letter(f) == 'V') break;
      winless++;
    }
    for (final f in club) {
      if (letter(f) != 'D') break;
      losing++;
    }
    for (final f in club) {
      if (letter(f) != 'V') break;
      winning++;
    }
    final season = club.where((f) => f['seasonId'] == seasonId).toList();
    final last10 = club.take(10).map(letter).toList();
    final seasonLosses = season.where((f) => letter(f) == 'D').length;
    final lossRate = season.length < 5 ? null : seasonLosses / season.length;
    final recentSeasons =
        ([...seasons.where((s) => !s.startDate.isAfter(eventDate))]
              ..sort((a, b) => b.startDate.compareTo(a.startDate)))
            .take(2)
            .map((s) => s.id)
            .toSet();
    int titles(Iterable<SocialRow> list) => list.fold(
      0,
      (total, t) => total + ((t['count'] as num?)?.toInt() ?? 1),
    );
    final recentTitles = titles(
      trophies.where((t) => recentSeasons.contains(t['seasonId'])),
    );
    var pressure = 0;
    pressure += winless >= 8
        ? 3
        : winless >= 5
        ? 2
        : winless >= 3
        ? 1
        : 0;
    pressure += losing >= 3
        ? 2
        : losing >= 2
        ? 1
        : 0;
    final losses10 = last10.where((r) => r == 'D').length;
    pressure += losses10 >= 6
        ? 2
        : losses10 >= 4
        ? 1
        : 0;
    if (lossRate != null && lossRate >= 0.4) pressure += 1;
    if (club.take(3).any(eliminated)) pressure += 1;
    if (season.where(eliminated).length >= 2) pressure += 1;
    if (last10.where((r) => r == 'V').length >= 7) pressure -= 2;
    if (lossRate != null && lossRate <= 0.15) pressure -= 2;
    pressure -= min(3, recentTitles);
    final streaks = [
      if (winning >= 2) '$winning vitórias seguidas',
      if (losing >= 2) '$losing derrotas seguidas',
      if (winless >= 3 && winless > losing) '$winless jogos sem vencer',
    ];
    final streak = streaks.isEmpty ? null : streaks.join(', ');
    final otherClubs = <Object?, List<SocialRow>>{};
    for (final f in fixtures) {
      if (f['playerTeamId'] != teamId) {
        otherClubs.putIfAbsent(f['playerTeamId'], () => []).add(f);
      }
    }
    return {
      'coach': ?coachName,
      if (manager) 'coachAtClubSince': month(club.last['date']),
      if (manager) 'coachRecordAtClub': record(club),
      if (manager && trophies.isNotEmpty)
        'coachTitles':
            '${titles(trophies.where((t) => t['teamId'] == teamId))} no clube, '
            '${titles(trophies)} na carreira, $recentTitles nesta temporada e na anterior',
      'seasonRecord': record(season),
      'lastResults': [for (final f in club.take(10)) result(f, date: true)],
      'streak': ?streak,
      if (season.any(eliminated))
        'seasonEliminations': [
          for (final f in season.where(eliminated))
            '${competition(f)}: ${result(f, where: false)}',
        ],
      'coachPressure': pressure >= 5
          ? 'muito alta: boa parte da torcida pede a saída do técnico'
          : pressure >= 3
          ? 'alta: cobrança forte no técnico, parte da torcida pede a saída'
          : pressure <= -2
          ? 'baixa: técnico prestigiado; a torcida confia nele e cobra os jogadores'
          : 'normal: cobranças pontuais; ninguém pede a saída do técnico',
      if (manager && otherClubs.isNotEmpty)
        'coachPreviousClubs': [
          for (final MapEntry(key: id, value: list) in otherClubs.entries)
            '${teamName(id, list.first['playerTeamLeagueId'])} '
                '(${month(list.last['date'])} a ${month(list.first['date'])}, '
                '${record(list)})',
        ],
    };
  }

  SocialRow? _arrival(Object? playerId) => transfers
      .where(
        (t) =>
            t['playerInstanceId'] == playerId &&
            t['toTeamId'] == teamId &&
            isIncomingTeamTransfer(t, teamId),
      )
      .firstOrNull;

  SocialRow? _departure(Object? playerId) => transfers
      .where(
        (t) =>
            t['playerInstanceId'] == playerId &&
            t['fromTeamId'] == teamId &&
            !isIncomingTeamTransfer(t, teamId),
      )
      .firstOrNull;

  String _arrivalText(SocialRow t) {
    final from = teamName(t['fromTeamId'], t['fromLeagueId']);
    final fee = t['transferValue'] as num? ?? 0;
    final when = month(t['date']);
    return switch (transferTypeFromRow(t)) {
      TeamTransferType.youthAcademy => 'promovido da base em $when',
      TeamTransferType.inLoan => 'emprestado pelo $from em $when',
      TeamTransferType.freeTransfer =>
        'chegou sem custo em $when, vindo de $from',
      TeamTransferType.endOfLoan ||
      TeamTransferType.prematureEndOfLoan => 'voltou de empréstimo em $when',
      _ =>
        'contratado em $when, vindo de $from${fee > 0 ? ', por ${money(fee)}' : ''}',
    };
  }

  String _departureText(SocialRow t) {
    final to = teamName(t['toTeamId'], t['toLeagueId']);
    final fee = t['transferValue'] as num? ?? 0;
    final release = DateTime.tryParse(t['releaseDate']?.toString() ?? '');
    final pending = release != null && release.isAfter(eventDate);
    return '${pending ? 'negociado' : 'saiu'} em ${month(t['date'])} para $to'
        '${fee > 0 ? ' por ${money(fee)}' : ''}'
        '${pending ? ', ainda no clube até ${day(t['releaseDate'])}' : ''}';
  }

  List<String> squadLines() {
    final byPlayer = <Object?, List<SocialRow>>{};
    for (final p in performances) {
      if (p['playerTeamId'] == teamId) {
        byPlayer.putIfAbsent(p['playerInstanceId'], () => []).add(p);
      }
    }
    final members = {
      for (final s in squad)
        if (s['loanStatus'] != 'outLoan') s['playerId']: s,
    };
    final ids = {
      ...members.keys,
      for (final MapEntry(:key, :value) in byPlayer.entries)
        if (value.any((p) => p['seasonId'] == seasonId)) key,
    };
    final fees =
        transfers
            .where(
              (t) =>
                  t['toTeamId'] == teamId &&
                  isIncomingTeamTransfer(t, teamId) &&
                  (t['transferValue'] as num? ?? 0) > 0,
            )
            .map((t) => t['transferValue'] as num)
            .toList()
          ..sort((a, b) => b.compareTo(a));
    final expensive = fees.length < 3 ? (fees.lastOrNull ?? 0) : fees[2];
    final lines = <(int, num, String)>[];
    for (final id in ids) {
      final rows = byPlayer[id] ?? const <SocialRow>[];
      final member = members[id];
      final name = member?['name'] ?? rows.firstOrNull?['name'];
      if (name == null) continue;
      final season = rows.where((p) => p['seasonId'] == seasonId).toList();
      final position =
          positionShortLabels[(member?['positionId'] ??
                  rows.firstOrNull?['positionId'])
              ?.toString()];
      final birth = member?['birthdate'] ?? rows.firstOrNull?['birthdate'];
      final age = birth is int
          ? (eventDate
                        .difference(DateTime.fromMillisecondsSinceEpoch(birth))
                        .inDays /
                    365.25)
                .floor()
          : null;
      final overall = member?['overall'] ?? member?['baseOverall'];
      final value = member?['marketValue'] as num?;
      num sum(List<SocialRow> list, String key) =>
          list.fold<num>(0, (total, p) => total + (p[key] as num? ?? 0));
      List<num> ratings(List<SocialRow> list) => [
        for (final p in list)
          if (p['avgRating'] case final num r when r > 0) r,
      ];
      final seasonRatings = ratings(season);
      final recent = ratings(season.take(5).toList());
      final assessment = TwitterPlayerAssessment(
        performance: {'rating': season.firstOrNull?['avgRating']},
        history: [
          for (final p in season)
            {
              'rating': p['avgRating'],
              'goals': p['goalsCount'],
              'assists': p['assistsCount'],
            },
        ],
      );
      final motm = season.where((p) => p['playerOfTheMatchId'] == id).length;
      final arrival = _arrival(id);
      final previousStats = TransferPreviousClubStats.decode(
        arrival?['previousClubStats'],
      );
      final knownPreviousStats = previousStats?.availableAt(eventDate) == true
          ? previousStats
          : null;
      final departure = _departure(id);
      final fee = arrival?['transferValue'] as num? ?? 0;
      final injury = injuries
          .where(
            (i) =>
                i['playerId'] == id &&
                (DateTime.tryParse(i['endDate']?.toString() ?? '')
                        ?.isAfter(eventDate) ??
                    true),
          )
          .firstOrNull;
      final recentAverage = recent.length >= 3
          ? recent.reduce((a, b) => a + b) / recent.length
          : null;
      final profile = [
        ?position,
        if (age != null) '$age anos',
        if (overall != null) 'overall $overall',
        if (value != null && value > 0) 'valor ${money(value)}',
        if (member?['loanStatus'] == 'inLoan') 'emprestado ao clube',
      ].join(', ');
      final parts = [
        profile.isEmpty ? '$name' : '$name ($profile)',
        season.isEmpty
            ? 'sem atuações registradas pelo clube nesta temporada'
            : 'pelo clube nesta temporada: ${season.length} jogos registrados, ${_number(sum(season, 'goalsCount'))} gols, '
                  '${_number(sum(season, 'assistsCount'))} assist.'
                  '${seasonRatings.isEmpty ? '' : ', nota ${_rating(seasonRatings.reduce((a, b) => a + b) / seasonRatings.length)}'}'
                  '${motm > 0 ? ', $motm× craque do jogo' : ''}'
                  '${sum(season, 'redCards') > 0 ? ', ${_number(sum(season, 'redCards'))} expulsão(ões)' : ''}',
        if (recent.isNotEmpty)
          'últimas notas: ${recent.map(_rating).join(' ')}',
        if (rows.length > season.length)
          'pelo clube: ${rows.length} jogos, ${_number(sum(rows, 'goalsCount'))} gols, '
              '${_number(sum(rows, 'assistsCount'))} assist.',
        if (arrival != null) _arrivalText(arrival),
        if (knownPreviousStats != null)
          knownPreviousStats.summary(
            teamName(arrival?['fromTeamId'], arrival?['fromLeagueId']),
          )
        else if (arrival != null &&
            const {
              TeamTransferType.buy,
              TeamTransferType.buyFromLoan,
              TeamTransferType.inLoan,
              TeamTransferType.freeTransfer,
            }.contains(transferTypeFromRow(arrival)))
          'desempenho no clube anterior não informado',
        if (departure != null) _departureText(departure),
        if (injury != null)
          [
            'lesionado',
            if (injury['description']?.toString().trim() case final d?
                when d.isNotEmpty)
              ': $d',
            if (injury['expectedRecoveryDays'] case final num days
                when days > 0)
              ', previsão de ${days.round()} dias fora',
          ].join(),
        if (fee > 0 && fee >= expensive) 'uma das contratações mais caras',
        if (assessment.poorRecentForm) 'má fase recente',
        if (assessment.strongSeason) 'boa temporada',
        if (recentAverage != null && recentAverage >= 7.8) 'grande fase',
      ];
      lines.add((season.length, overall as num? ?? 0, parts.join('; ')));
    }
    lines.sort(
      (a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : b.$2.compareTo(a.$2),
    );
    return [for (final line in lines) line.$3];
  }

  List<String> formerPlayers() {
    final current = {
      for (final s in squad)
        if (s['loanStatus'] != 'outLoan') s['playerId'],
    };
    final totals = <Object?, (String, int, num, num, String, String)>{};
    for (final p in performances.where((p) => p['playerTeamId'] == teamId)) {
      final id = p['playerInstanceId'];
      final previous = totals[id];
      totals[id] = (
        p['name']?.toString() ?? '?',
        (previous?.$2 ?? 0) + 1,
        (previous?.$3 ?? 0) + (p['goalsCount'] as num? ?? 0),
        (previous?.$4 ?? 0) + (p['assistsCount'] as num? ?? 0),
        p['date'].toString(),
        previous?.$6 ?? p['date'].toString(),
      );
    }
    final gone = totals.entries
        .where((e) => !current.contains(e.key) && e.value.$2 >= 10)
        .toList();
    final byGoals = [...gone]..sort((a, b) => b.value.$3.compareTo(a.value.$3));
    final byGames = [...gone]..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    final picked = {...byGoals.take(5), ...byGames.take(3)};
    return [
      for (final MapEntry(key: id, value: t) in picked)
        [
          '${t.$1}: ${t.$2} jogos, ${_number(t.$3)} gols, ${_number(t.$4)} assist. '
              '(${month(t.$5)} a ${month(t.$6)})',
          if (_departure(id) case final departure?) _departureText(departure),
        ].join('; '),
    ];
  }

  Map<String, Object?> playerForm() {
    String stats(List<SocialRow> list) {
      final ratings = [
        for (final f in list)
          if (f['rating'] case final num r when r > 0) r,
      ];
      num sum(String key) =>
          list.fold<num>(0, (total, f) => total + (f[key] as num? ?? 0));
      final motm = list
          .where(
            (f) => f['playerOfTheMatch'] == '1' || f['playerOfTheMatch'] == 1,
          )
          .length;
      return '${list.length} jogos, ${_number(sum('goalsCount'))} gols, '
          '${_number(sum('assistsCount'))} assist.'
          '${ratings.isEmpty ? '' : ', nota ${_rating(ratings.reduce((a, b) => a + b) / ratings.length)}'}'
          '${motm > 0 ? ', $motm× craque do jogo' : ''}';
    }

    final club = _club;
    final season = club.where((f) => f['seasonId'] == seasonId).toList();
    return {
      'season': stats(season),
      'lastRatings': [
        for (final f in club.take(5))
          if (f['rating'] case final num r when r > 0) _rating(r),
      ],
      'atClub': stats(club),
      'career': stats(fixtures),
      if (playerTransfers.isNotEmpty)
        'moves': [
          for (final t in playerTransfers.take(10))
            '${month(t['transferDate'])}: ${teamName(t['fromTeamId'], t['fromLeagueId'])} '
                '→ ${teamName(t['toTeamId'], t['toLeagueId'])}'
                '${(t['transferValue'] as num? ?? 0) > 0 ? ', ${money(t['transferValue'] as num)}' : ''}'
                ' (${t['type']})',
        ],
    };
  }

  Map<String, Object?> history({Object? opponentId, Object? fixtureId}) {
    final seasonLines = <String>[];
    final ordered = [...seasons]
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    for (final s in ordered) {
      if (s.id == seasonId) continue;
      final list = fixtures.where((f) => f['seasonId'] == s.id).toList();
      if (list.isEmpty) continue;
      final teams = <Object?, int>{};
      for (final f in list) {
        teams[f['playerTeamId']] = (teams[f['playerTeamId']] ?? 0) + 1;
      }
      final main = teams.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final titles = [
        for (final t in trophies.where((t) => t['seasonId'] == s.id))
          awards[t['awardId']] ?? t['description'] ?? t['awardId'],
      ];
      final falls = [
        for (final f in list.where(eliminated))
          '${competition(f)} (${result(f, where: false)})',
      ];
      String? best;
      if (manager) {
        final goals = <Object?, (String, num)>{};
        for (final p in performances.where((p) => p['seasonId'] == s.id)) {
          final previous = goals[p['playerInstanceId']];
          goals[p['playerInstanceId']] = (
            p['name']?.toString() ?? '?',
            (previous?.$2 ?? 0) + (p['goalsCount'] as num? ?? 0),
          );
        }
        final top = goals.values.fold<(String, num)?>(
          null,
          (a, b) => a == null || b.$2 > a.$2 ? b : a,
        );
        if (top != null && top.$2 > 0) {
          best = 'artilheiro: ${top.$1} (${_number(top.$2)} gols)';
        }
      } else {
        num sum(String key) =>
            list.fold<num>(0, (total, f) => total + (f[key] as num? ?? 0));
        best =
            'você: ${_number(sum('goalsCount'))} gols, ${_number(sum('assistsCount'))} assist.';
      }
      seasonLines.add(
        [
          '${seasonLabel(s.id)}, ${teamName(main.key, list.first['playerTeamLeagueId'])}: ${record(list)}',
          if (titles.isNotEmpty) 'títulos: ${titles.join(', ')}',
          if (falls.isNotEmpty) 'caiu: ${falls.join('; ')}',
          ?best,
        ].join('; '),
      );
    }
    final versus = opponentId == null
        ? const <SocialRow>[]
        : fixtures
              .where(
                (f) =>
                    f['oppositeTeamId'] == opponentId && f['id'] != fixtureId,
              )
              .toList();
    final incoming =
        transfers
            .where(
              (t) =>
                  t['toTeamId'] == teamId &&
                  isIncomingTeamTransfer(t, teamId) &&
                  (t['transferValue'] as num? ?? 0) > 0,
            )
            .toList()
          ..sort(
            (a, b) => (b['transferValue'] as num).compareTo(
              a['transferValue'] as num,
            ),
          );
    final outgoing =
        transfers
            .where(
              (t) =>
                  t['fromTeamId'] == teamId &&
                  !isIncomingTeamTransfer(t, teamId) &&
                  (t['transferValue'] as num? ?? 0) > 0,
            )
            .toList()
          ..sort(
            (a, b) => (b['transferValue'] as num).compareTo(
              a['transferValue'] as num,
            ),
          );
    final former = manager ? formerPlayers() : const <String>[];
    return {
      if (seasonLines.isNotEmpty)
        'previousSeasons': seasonLines.take(10).toList(),
      if (trophies.isNotEmpty)
        'titles': [
          for (final t in trophies)
            '${(t['count'] as num? ?? 1) > 1 ? '${t['count']}× ' : ''}'
                '${awards[t['awardId']] ?? t['description'] ?? t['awardId']} '
                '(${seasonLabel(t['seasonId'])}, ${teamName(t['teamId'], t['leagueId'])})',
        ],
      if (versus.isNotEmpty)
        'headToHead': {
          'record': record(versus),
          'last': [for (final f in versus.take(5)) result(f, date: true)],
          if (versus.any(eliminated))
            'eliminations': [
              for (final f in versus.where(eliminated))
                '${seasonLabel(f['seasonId'])} ${competition(f)}: ${result(f, where: false)}',
            ],
          if (!manager)
            'yourGoals': _number(
              versus.fold<num>(0, (t, f) => t + (f['goalsCount'] as num? ?? 0)),
            ),
        },
      if (incoming.isNotEmpty)
        'biggestSignings': [
          for (final t in incoming.take(5))
            '${t['playerName'] ?? '?'}: ${money(t['transferValue'] as num)} '
                '(${month(t['date'])}, vindo de ${teamName(t['fromTeamId'], t['fromLeagueId'])})',
        ],
      if (outgoing.isNotEmpty)
        'biggestSales': [
          for (final t in outgoing.take(3))
            '${t['playerName'] ?? '?'}: ${money(t['transferValue'] as num)} '
                '(${month(t['date'])}, para ${teamName(t['toTeamId'], t['toLeagueId'])})',
        ],
      if (former.isNotEmpty) 'formerPlayers': former,
    };
  }

  List<Map<String, Object?>> recentTransfers() {
    final picked = {
      for (final t in transfers.where((t) {
        final release = DateTime.tryParse(t['releaseDate']?.toString() ?? '');
        return release != null && release.isAfter(eventDate);
      }))
        t['id']: t,
      for (final t in transfers.take(8)) t['id']: t,
    }.values;
    return [
      for (final t in picked)
        {
          'player': t['playerName'],
          'type': t['type'],
          'from': teamName(t['fromTeamId'], t['fromLeagueId']),
          'to': teamName(t['toTeamId'], t['toLeagueId']),
          if ((t['transferValue'] as num? ?? 0) > 0)
            'fee': money(t['transferValue'] as num),
          'agreementDate': day(t['date']),
          if (t['releaseDate'] != null) 'releaseDate': day(t['releaseDate']),
          'status': switch (DateTime.tryParse(
            t['releaseDate']?.toString() ?? '',
          )) {
            null => 'releaseUnknown',
            final release when release.isAfter(eventDate) => 'pendingRelease',
            _ => 'released',
          },
        },
    ];
  }

  Map<String, Object?> brief({Object? opponentId, Object? fixtureId}) {
    final history = this.history(opponentId: opponentId, fixtureId: fixtureId);
    final squadLines = manager ? this.squadLines() : const <String>[];
    final transfers = manager ? recentTransfers() : const [];
    return {
      'clubMomentum': momentum(),
      if (squadLines.isNotEmpty) 'squad': squadLines,
      if (!manager) 'playerForm': playerForm(),
      if (transfers.isNotEmpty) 'recentTransfers': transfers,
      if (history.isNotEmpty) 'history': history,
    };
  }

  Map<String, Object?> match(SocialRow fixture, List<SocialRow> lineup) {
    final tablePosition = FixtureTablePosition.resolve(fixture, fixtures);
    final notes = fixture['notes']?.toString().trim() ?? '';
    String score(Object? a, Object? b) => '${a ?? 0}x${b ?? 0}';
    final facts = <String, Object?>{
      'date': day(fixture['date']),
      'team': teamName(fixture['playerTeamId'], fixture['playerTeamLeagueId']),
      'opponent': teamName(
        fixture['oppositeTeamId'],
        fixture['oppositeTeamLeagueId'],
      ),
      'competition':
          tournaments[fixture['tournamentId']] ?? fixture['tournamentId'],
      if (fixture['stage']?.toString().trim().isNotEmpty == true)
        'stage': fixture['stage'],
      'location': fixture['location'],
      'score': score(fixture['playerTeamScore'], fixture['oppositeTeamScore']),
      if (fixture['playerTeamPenaltiesScore'] != null)
        'penalties': score(
          fixture['playerTeamPenaltiesScore'],
          fixture['oppositeTeamPenaltiesScore'],
        ),
      if (fixture['extraTime'] == 1 || fixture['extraTime'] == true)
        'extraTime': true,
      'outcome': TwitterStore.fixtureOutcome(fixture),
      if (fixture['teamPossession'] case final num possession)
        'possession': '${possession.round()}%',
      if (fixture['passAccuracy'] case final num accuracy)
        'passAccuracy': '${accuracy.round()}%',
      if (fixture['playerTeamShoutsCount'] != null ||
          fixture['opponentTeamShotsCount'] != null)
        'shots': score(
          fixture['playerTeamShoutsCount'],
          fixture['opponentTeamShotsCount'],
        ),
      ...tablePosition.context,
      if (notes.isNotEmpty) 'notes': notes,
      if (PressConference.decode(fixture['pressConference']) case final press?
          when press.done && press.shared)
        'pressConference': press.transcript(),
    };
    final opponentGoals = [
      for (final g in events(fixture['opponentGoalDetails']))
        [
          if (g['scorerName']?.toString().trim().isNotEmpty == true)
            g['scorerName'],
          ?minute(g),
          ...goalTypes(g['type']),
          if (g['isOwnGoal'] == true) 'gol contra',
        ].join(' '),
    ];
    if (opponentGoals.isNotEmpty) facts['opponentGoals'] = opponentGoals;
    final opponentStats = OpponentStats.decode(fixture['opponentStats']);
    if (!opponentStats.isEmpty) facts['opponentStats'] = opponentStats.toMap();
    if (!manager) {
      facts['yourPerformance'] = {
        for (final key in [
          'rating',
          'goalsCount',
          'assistsCount',
          'savesCount',
          'minsPlayed',
          'yellowCards',
          'redCards',
          'goalsFromPenalty',
          'shotsOnTarget',
          'playerOfTheMatch',
          'isInjured',
          'isDisqualified',
        ])
          if (fixture[key] != null) key: fixture[key],
        'assessment': TwitterPlayerAssessment(
          performance: {
            'rating': fixture['rating'],
            'missedPenalties': events(
              lineup.firstOrNull?['missedPenaltyDetails'],
            ).length,
            'ownGoals': events(lineup.firstOrNull?['ownGoalDetails']).length,
          },
          history: [
            for (final f in fixtures.where(
              (f) =>
                  f['seasonId'] == fixture['seasonId'] &&
                  f['playerTeamId'] == fixture['playerTeamId'],
            ))
              {
                'rating': f['rating'],
                'goals': f['goalsCount'],
                'assists': f['assistsCount'],
              },
          ],
        ).context,
      };
      return facts;
    }
    String? motm;
    final players = <Map<String, Object?>>[];
    for (final p in lineup) {
      final name = (p['name'] ?? p['playerInstanceId']).toString();
      if (fixture['playerOfTheMatchId'] == p['playerInstanceId']) motm = name;
      final timeline = [
        for (final g in events(p['goalDetails']))
          [
            'gol',
            ?minute(g),
            ...goalTypes(g['type']),
            if (g['assistantName'] != null) 'assist. ${g['assistantName']}',
          ].join(' '),
        for (final a in events(p['assistDetails']))
          [
            'assistência',
            ?minute(a),
            if (a['goalscorerName'] != null) 'para ${a['goalscorerName']}',
          ].join(' '),
        for (final c in events(p['yellowCardDetails']))
          ['amarelo', ?minute(c)].join(' '),
        for (final c in events(p['redCardDetails']))
          ['vermelho', ?minute(c)].join(' '),
        for (final s in events(p['substitutionDetails']))
          [
            s['type'] == 'inGame' ? 'entrou' : 'saiu',
            ?minute(s),
            if (s['anotherPlayerName'] != null)
              s['type'] == 'inGame'
                  ? 'no lugar de ${s['anotherPlayerName']}'
                  : 'para entrar ${s['anotherPlayerName']}',
          ].join(' '),
        for (final o in events(p['ownGoalDetails']))
          ['gol contra', ?minute(o)].join(' '),
        for (final m in events(p['missedPenaltyDetails']))
          ['perdeu pênalti', ?minute(m)].join(' '),
        for (final i in events(p['injuryDetails']))
          ['lesão', ?minute(i)].join(' '),
      ];
      players.add({
        'name': name,
        'assessment': TwitterPlayerAssessment(
          performance: {
            'rating': p['avgRating'],
            'missedPenalties': events(p['missedPenaltyDetails']).length,
            'ownGoals': events(p['ownGoalDetails']).length,
          },
          history: [
            for (final row in performances.where(
              (row) =>
                  row['playerInstanceId'] == p['playerInstanceId'] &&
                  row['seasonId'] == fixture['seasonId'] &&
                  row['playerTeamId'] == fixture['playerTeamId'],
            ))
              {
                'rating': row['avgRating'],
                'goals': row['goalsCount'],
                'assists': row['assistsCount'],
              },
          ],
        ).context,
        'position': ?positionShortLabels[p['positionId']?.toString()],
        for (final (key, label) in const [
          ('avgRating', 'rating'),
          ('goalsCount', 'goals'),
          ('assistsCount', 'assists'),
          ('shotsCount', 'shots'),
          ('shotAccuracy', 'shotAccuracy'),
          ('passes', 'passes'),
          ('keyPasses', 'keyPasses'),
          ('passAccuracy', 'passAccuracy'),
          ('tackles', 'tackles'),
          ('tacklesAccuracy', 'tacklesAccuracy'),
          ('dribbles', 'dribbles'),
          ('dribblesAccuracy', 'dribblesAccuracy'),
          ('saves', 'saves'),
          ('penaltySaves', 'penaltySaves'),
          ('yellowCards', 'yellowCards'),
          ('redCards', 'redCards'),
        ])
          if (p[key] case final num v when v != 0) label: v,
        if (timeline.isNotEmpty) 'events': timeline,
      });
    }
    if (motm != null) facts['manOfTheMatch'] = motm;
    if (players.isNotEmpty) facts['lineup'] = players;
    return facts;
  }
}
