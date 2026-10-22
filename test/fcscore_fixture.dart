import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/FcScore/FcScoreModels.dart';

FcJson apiPlayer(int id, String name, {int overall = 82}) => {
  'id': id,
  'name': {'displayName': name},
  'overall': overall,
  'potential': 90,
  'age': 24,
  'birthDate': '2004-05-01',
  'nationality': {'id': 54, 'name': 'Brasil'},
  'positions': ['ST'],
  'preferredFoot': 'right',
  'jerseyNumber': id,
  'contract': {'wage': 20000, 'signedAt': '2027-07-01', 'durationMonths': 36},
};
FcScoreRemoteCareer apiCareer({
  String category = 'manager',
  String saveId = 'save-A',
}) => FcScoreRemoteCareer(
  gameVersion: 'FC26',
  overview: {
    'save': {
      'id': saveId,
      'inGameName': 'Minha carreira',
      'careerType': category,
    },
    'currentDate': '2028-06-30',
    'season': 3,
    'club': {'id': 598, 'name': 'São Paulo'},
    'league': {'id': 80, 'name': 'Brasileirão'},
    'leagueStanding': {
      'position': 1,
      'points': 45,
      'wins': 14,
      'draws': 3,
      'losses': 2,
    },
    'budgets': {'transfer': 15000000, 'wage': 500000},
    'squad': {'players': 2, 'averageOverall': 80.5},
    'lastMatch': apiFixture(),
    'nextMatch': {
      ...apiFixture(),
      'id': 43,
      'played': false,
      'date': '2028-07-02',
    },
  },
  squad: [apiPlayer(10, 'Pedro Silva'), apiPlayer(11, 'Marcos Antônio')],
  competitions: [
    {'id': 1528, 'code': 'C80', 'name': 'Brasileirão'},
  ],
);
FcJson apiFixture({bool away = true}) => {
  'id': 42,
  'date': '2028-06-25',
  'time': '19:30',
  'competition': {'id': 1528, 'name': 'Brasileirão'},
  'stage': 'League',
  'round': 21,
  'played': true,
  'home': {
    'team': {'id': away ? 200 : 598, 'name': away ? 'Rival FC' : 'São Paulo'},
    'goals': away ? 1 : 2,
  },
  'away': {
    'team': {'id': away ? 598 : 200, 'name': away ? 'São Paulo' : 'Rival FC'},
    'goals': away ? 2 : 1,
  },
};
FcJson apiPerformance(
  int id,
  String name, {
  bool started = true,
  int minutes = 93,
  int goals = 1,
  bool played = true,
}) => {
  'id': id,
  'profile': apiPlayer(id, name),
  'started': started,
  'played': played,
  'jerseyNumber': id,
  'rating': 8.4,
  'manOfTheMatch': id == 10,
  'stats': {
    'minutesPlayed': minutes,
    'goalsDerived': goals,
    'pkGoals': 0,
    'npkGoals': goals,
    'assists': 1,
    'yellowCardEvents': 1,
    'redDismissals': 0,
    'ownGoals': 0,
    'shots': 4,
    'shotsOnTarget': 3,
    'passes': 20,
    'passesCompleted': 18,
    'dribbles': 3,
    'dribblesCompleted': 2,
    'saves': 0,
    'penaltySaves': 0,
    'keyPasses': 2,
  },
};
FcJson apiReport({
  String id = 'batch-A',
  String saveId = 'save-A',
  bool away = true,
}) {
  final fixture = apiFixture(away: away);
  final ours = {
    'team': {'id': 598, 'name': 'São Paulo'},
    'goals': 2,
    'stats': {
      'shots': 15,
      'shotsOnTarget': 8,
      'passes': 400,
      'passesCompleted': 340,
      'yellowCardEvents': 2,
      'redDismissals': 0,
    },
    'players': [
      apiPerformance(10, 'Pedro Silva'),
      apiPerformance(11, 'Marcos Antônio', started: false, minutes: 27),
      apiPerformance(
        12,
        'Lucas Alves',
        started: false,
        played: false,
        minutes: 0,
        goals: 0,
      ),
    ],
  };
  final opponent = {
    'team': {'id': 200, 'name': 'Rival FC'},
    'goals': 1,
    'stats': {'shots': 5, 'passes': 200, 'passesCompleted': 160},
    'players': [apiPerformance(20, 'João Souza')],
  };
  return {
    'id': id,
    'exportVersion': 43,
    'capturedAt': '2026-10-10T19:00:00Z',
    'activeSave': {'id': saveId},
    'warnings': <String>[],
    'match': {
      'fixtureId': 42,
      'date': fixture['date'],
      'time': fixture['time'],
      'competition': fixture['competition'],
      'stage': 'League',
      'round': 21,
      'savedResult': {
        'played': true,
        'home': away ? 1 : 2,
        'away': away ? 2 : 1,
      },
    },
    'home': away ? opponent : ours,
    'away': away ? ours : opponent,
    'manOfTheMatch': {
      'player': {'id': 10, 'name': 'Pedro Silva'},
      'team': {'id': 598, 'name': 'São Paulo'},
    },
  };
}

FcJson apiUnsavedReport() {
  final report = apiReport(id: 'batch-B', away: false);
  final match = report['match'] as Map;
  match['fixtureId'] = 46;
  match['date'] = '2028-06-29';
  match['savedResult'] = {'played': false, 'home': null, 'away': null};
  return report;
}

FcScoreLink apiLink({
  String personId = 'career',
  String category = 'manager',
}) => FcScoreLink(
  personId: personId,
  saveId: 'save-A',
  saveName: 'Minha carreira',
  gameVersion: 'FC26',
  remoteClubId: '598',
  localClubId: '40-13',
  localLeagueId: '1014',
  seasonId: 's2028',
  playerId: category == 'player' ? '10' : null,
  teams: {'598': '40-13', '200': 'rival'},
  competitions: {'1528': 'league:1014'},
);
FcJson apiTable() => {
  'competition': {'id': 1528, 'name': 'Brasileirão'},
  'fixtures': {'played': 19, 'total': 38},
  'stages': [
    {
      'id': 1,
      'name': 'Liga',
      'groups': [
        {
          'code': 'A',
          'rows': [
            {
              'position': 1,
              'team': {'id': 598, 'name': 'São Paulo'},
              'points': 45,
              'played': 19,
              'wins': 14,
              'draws': 3,
              'losses': 2,
              'goalsFor': 41,
              'goalsAgainst': 12,
              'goalDifference': 29,
              'isUserClub': true,
              'form': ['W', 'D', 'W'],
            },
            {
              'position': 2,
              'team': {'id': 200, 'name': 'Rival FC'},
              'points': 40,
              'played': 19,
              'wins': 13,
              'draws': 1,
              'losses': 5,
              'goalsFor': 30,
              'goalsAgainst': 20,
              'goalDifference': 10,
              'isUserClub': false,
              'form': ['L', 'W', 'W'],
            },
          ],
        },
      ],
    },
  ],
};
FcScoreApi fakeApi(
  Uri uri, {
  List<http.Request>? requests,
  int fixturesTotal = 1,
  bool failHealth = false,
  bool unsaved = false,
  bool failStandings = false,
}) => FcScoreApi(
  uri,
  client: MockClient((request) async {
    requests?.add(request);
    final path = request.url.path;
    Object? value;
    if (failHealth && path.endsWith('/health')) {
      return http.Response('{"error":{"message":"Indisponível"}}', 503);
    }
    if (path.endsWith('/health')) {
      value = {'status': 'ok'};
    } else if (path.endsWith('/meta')) {
      value = {'gameVersion': 'FC 26'};
    } else if (path.endsWith('/careers')) {
      value = [
        {
          ...(apiCareer().overview['save'] as Map),
          'savedAt': '2026-10-10T18:00:00.000',
        },
      ];
    } else if (path.endsWith('/set-file')) {
      value = {'id': 'save-A'};
    } else if (path.endsWith('/matches/latest') ||
        path.endsWith('/matches/batch-A')) {
      value = apiReport();
    } else if (path.endsWith('/matches/batch-B')) {
      value = apiUnsavedReport();
    } else if (path.endsWith('/matches')) {
      value = [
        if (unsaved)
          {
            'id': 'batch-B',
            'exportVersion': 43,
            'capturedAt': '2026-10-10T19:00:00',
            'fixtureId': 46,
            'home': 'São Paulo',
            'homeTeamId': 598,
            'away': 'Rival FC',
            'awayTeamId': 200,
          },
        {
          'id': 'batch-A',
          'exportVersion': 43,
          'fixtureId': 42,
          'home': 'Rival FC',
          'away': 'São Paulo',
          'competition': 'Brasileirão',
          'score': {'home': 1, 'away': 2},
        },
      ];
    } else if (path.endsWith('/squad')) {
      value = {'players': apiCareer().squad};
    } else if (path.endsWith('/competitions')) {
      value = [
        {
          'season': 3,
          'competition': apiCareer().competitions.single,
          'team': apiCareer().club,
          'won': false,
        },
      ];
    } else if (path.endsWith('/league') || path.contains('/competitions/')) {
      if (failStandings) {
        return http.Response(
          '{"error":{"message":"Classificação indisponível"}}',
          503,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      value = apiTable();
    } else if (path.endsWith('/fixtures')) {
      value = {
        'total': fixturesTotal,
        'limit': 50,
        'offset': 0,
        'items': [apiFixture()],
      };
    } else if (path.endsWith('/history')) {
      value = [
        {
          'season': 2,
          'team': apiCareer().club,
          'league': apiCareer().league,
          'gamesPlayed': 50,
          'wins': 30,
          'draws': 10,
          'losses': 10,
          'goalsFor': 100,
          'goalsAgainst': 50,
          'points': 80,
          'leaguePosition': 1,
          'trophies': {'league': 1, 'domesticCup': 1, 'continental': 0},
        },
      ];
    } else if (path.contains('/players/')) {
      value = {
        ...apiPlayer(10, 'Pedro Silva'),
        'height': 180,
        'weight': 75,
        'attributes': {
          'pace': {'acceleration': 85, 'sprintspeed': 82},
        },
        'matchRatings': [
          {'date': '2028-06-25', 'rating': 84},
        ],
      };
    } else if (path.endsWith('/transfers')) {
      value = {
        'involvingClub': [],
        'world': [],
        'loans': [],
        'transferList': [],
      };
    } else if (path.endsWith('/youth')) {
      value = {
        'academy': [apiPlayer(30, 'Rafael Santos')],
        'graduates': [],
        'scouts': [],
        'missions': [],
      };
    } else if (path.endsWith('/tactics')) {
      value = {
        'tactics': [
          {
            'name': 'Principal',
            'active': true,
            'defensiveDepth': 60,
            'lineup': [
              {
                'position': 'ST',
                'player': {'id': 10, 'name': 'Pedro Silva'},
              },
            ],
          },
        ],
        'teamSheets': [],
      };
    } else {
      value = apiCareer().overview;
    }
    return http.Response(
      jsonEncode(value),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);
