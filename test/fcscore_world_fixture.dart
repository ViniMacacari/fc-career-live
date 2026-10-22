import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/FcScore/FcScoreWorldData.dart';

import 'fcscore_fixture.dart';

FcScoreWorldData worldData({String date = '2028-06-30', bool cup = false}) {
  final ref = {
    'id': 1528,
    'code': cup ? 'CUP80' : 'C80',
    'name': 'Brasileirão',
  };
  final table = {...apiTable(), 'competition': ref};
  final fixture = {...apiFixture(), 'competition': ref};
  final other = {
    ...fixture,
    'id': 44,
    'home': {
      'team': {'id': 200, 'name': 'Rival FC'},
      'goals': 3,
    },
    'away': {
      'team': {'id': 300, 'name': 'Terceiro FC'},
      'goals': 2,
    },
  };
  final next = {
    ...other,
    'id': 45,
    'date': '2028-07-15',
    'played': false,
    'home': {
      'team': {'id': 300, 'name': 'Terceiro FC'},
      'goals': null,
    },
    'away': {
      'team': {'id': 598, 'name': 'São Paulo'},
      'goals': null,
    },
  };
  return FcScoreWorldData(
    saveId: 'save-A',
    currentDate: date,
    competitions: [table],
    fixtures: [fixture, other, next],
    teams: [
      for (final (id, name, pid, pname, goals) in [
        (598, 'São Paulo', 10, 'Pedro Silva', 14),
        (200, 'Rival FC', 20, 'João Souza', 18),
        (300, 'Terceiro FC', 30, 'Lucas Paiva', 9),
      ])
        {
          'id': id,
          'name': name,
          'league': {'id': 80, 'name': 'Brasileirão'},
          'overall': 82,
          'roster': [
            {
              ...apiPlayer(pid, pname),
              'leagueGoals': goals,
              'leagueAppearances': 19,
              'yellowCards': 2,
              'redCards': 0,
              'lineupPosition': 'ST',
            },
          ],
        },
    ],
  );
}

FcScoreWorldData worldStatistics({bool cup = false, bool endpoint = true}) {
  final data = worldData(cup: cup);
  final competition = data.competitions.single['competition'];
  final records = <Map<String, dynamic>>[];
  for (final (i, team) in data.teams.indexed) {
    final p = (team['roster'] as List).first as Map<String, dynamic>;
    final stats = <String, dynamic>{
      'competition': competition,
      'team': {'id': team['id'], 'name': team['name']},
      'position': i == 2 ? 'GK' : 'ST',
      'appearances': 15,
      'minutes': 1200,
      'goals': [2, 11, 0][i],
      'assists': [5, 1, 6][i],
      'averageRating': [8.1, 7.2, 9.0][i],
      'manOfTheMatch': 3,
      'yellowCards': 2,
      'redCards': 0,
      'cleanSheets': i == 2 ? 5 : 9,
      'saves': i == 2 ? 40 : 0,
      'goalsConceded': 3,
      'recentMatches': [
        {'date': '2028-06-25', 'minutes': 90, 'goals': 1, 'rating': 8.0},
      ],
    };
    p['leagueGoals'] = 99;
    p['seasonStats'] = {
      'totals': stats,
      'competitions': [stats],
    };
    records.add({
      ...stats,
      'player': {'id': p['id'], 'name': p['name']},
    });
  }
  if (endpoint) {
    records.add({
      ...records.first,
      'player': {'id': 99, 'name': 'Jogador fora do elenco'},
      'goals': 14,
    });
    data.competitions.single['playerStats'] = records;
    data.competitions.single['playerStatsComplete'] = true;
  }
  return data;
}

FcScoreApi worldApi({
  List<http.Request>? requests,
  int pageSize = 500,
  bool changeSave = false,
  FcScoreWorldData? snapshot,
}) => FcScoreApi(
  Uri.parse('http://localhost:38291/api'),
  client: MockClient((r) async {
    requests?.add(r);
    final data = snapshot ?? worldData();
    Object? value;
    if (r.url.path.endsWith('/stats')) {
      final c = data.competitions.firstWhere(
        (c) =>
            '${(c['competition'] as Map)['id']}' ==
            r.url.queryParameters['competitionId'],
      );
      if (c['playerStatsComplete'] != true) return http.Response('{}', 404);
      final stats = c['playerStats'] as List;
      final offset = int.parse(r.url.queryParameters['offset'] ?? '0');
      value = {
        'total': stats.length,
        'items': stats.skip(offset).take(pageSize).toList(),
      };
    } else if (r.url.path.endsWith('/fixtures')) {
      final offset = int.parse(r.url.queryParameters['offset'] ?? '0');
      value = {
        'total': data.fixtures.length,
        'offset': offset,
        'limit': pageSize,
        'items': data.fixtures.skip(offset).take(pageSize).toList(),
      };
    } else if (r.url.path.contains('/teams/')) {
      final id = r.url.path.split('/').last;
      value = data.teams.singleWhere((t) => '${t['id']}' == id);
    } else if (r.url.path.contains('/competitions/')) {
      value = data.competitions.singleWhere(
        (c) =>
            '${(c['competition'] as Map)['id']}' == r.url.path.split('/').last,
      );
    } else {
      value = {
        ...apiCareer().overview,
        'currentDate': data.currentDate,
        if (changeSave) 'currentDate': '2028-07-01',
      };
    }
    return http.Response(
      jsonEncode(value),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);
