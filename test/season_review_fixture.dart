import 'package:mcmanager/models/Person.dart';
import 'package:mcmanager/models/Season.dart';
import 'package:mcmanager/models/SeasonReview.dart';

Person reviewPerson({
  PersonCategory category = PersonCategory.manager,
  String id = 'career',
}) => Person(
  id: id,
  name: 'Minha carreira no São Paulo',
  category: category,
  fifaVersion: 'FC26',
  leagueId: '1014',
  teamId: '40-13',
  nationalityId: '54',
  createdAt: DateTime(2025),
  updatedAt: DateTime(2026),
);
Season reviewSeason({
  String id = 's2026',
  int year = 2026,
  bool closed = false,
}) => Season(
  id: id,
  personId: 'career',
  startDate: DateTime(year),
  endDate: DateTime(year, 12, 31),
  createdAt: DateTime(year),
  closedAt: closed ? DateTime(year + 1, 1, 2) : null,
);
Map<String, Object?> reviewFixture(
  int i, {
  String season = 's2026',
  String person = 'career',
  String tournament = 'league:1014',
}) => {
  'id': 'f$i',
  'personId': person,
  'seasonId': season,
  'date': DateTime(2026, i % 12 + 1, 10).toIso8601String(),
  'fifaVersion': 'FC26',
  'playerTeamId': '40-13',
  'playerTeamLeagueId': '1014',
  'oppositeTeamId': 'fla',
  'oppositeTeamLeagueId': '1014',
  'tournamentId': tournament,
  'playerTeamScore': i % 5 == 4 ? 0 : 3,
  'oppositeTeamScore': i % 5 == 4
      ? 1
      : i % 5 == 3
      ? 3
      : 1,
  'location': i.isEven ? 'home' : 'away',
  'stage': 'Rodada ${i + 1}',
  'position': 1,
  'teamPossession': 54.0 + i % 7,
  'passAccuracy': 82.0 + i % 5,
};
SeasonReview exampleReview({bool closed = true}) => SeasonReview(
  season: reviewSeason(closed: closed),
  savedAt: DateTime(2027, 1, 2),
  careerName: 'Minha carreira no São Paulo',
  teamId: '40-13',
  teamNames: const {
    '40-13': 'São Paulo',
    'fla': 'Flamengo',
    'pal': 'Palmeiras',
  },
  fixtures: [for (var i = 0; i < 12; i++) reviewFixture(i)],
  players: const [
    {
      'name': 'Lucas Moura',
      'matches': 12,
      'goals': 16,
      'assists': 7,
      'rating': 8.42,
      'ratings': 11,
      'shots': 42,
      'keyPasses': 19,
      'saves': 0,
      'tackles': 9,
    },
    {
      'name': 'Luciano',
      'matches': 10,
      'goals': 9,
      'assists': 4,
      'rating': 7.88,
      'ratings': 10,
      'shots': 23,
      'keyPasses': 11,
      'saves': 0,
      'tackles': 4,
    },
    {
      'name': 'Calleri',
      'matches': 9,
      'goals': 5,
      'assists': 2,
      'rating': 7.63,
      'ratings': 8,
      'shots': 25,
      'keyPasses': 7,
      'saves': 0,
      'tackles': 4,
    },
  ],
  competitions: const [
    {
      'id': 'league:1014',
      'name': 'Brasileirão Série A',
      'kind': 'league',
      'won': true,
      'position': 1,
      'result': 'Campeão · 1º lugar',
      'games': 12,
      'goalsFor': 30,
      'goalsAgainst': 15,
      'path': ['Rodada 1', 'Rodada 12'],
    },
    {
      'id': 'cup',
      'name': 'Copa do Brasil',
      'kind': 'knockout',
      'won': true,
      'result': 'Campeão',
      'games': 6,
      'goalsFor': 15,
      'goalsAgainst': 5,
      'path': ['Quartas de final', 'Semifinal', 'Final'],
    },
  ],
  tables: [
    SeasonFinalTable(
      id: 'table',
      tournamentId: 'league:1014',
      name: 'Brasileirão Série A',
      ownTeamId: '40-13',
      closedAt: DateTime(2027, 1, 2),
      rows: const [
        SeasonStanding(
          teamId: '40-13',
          name: 'São Paulo',
          position: 1,
          stats: {
            'points': 83,
            'matchesPlayed': 38,
            'wins': 25,
            'draws': 8,
            'loses': 5,
            'goalsFor': 74,
            'goalsAgainst': 28,
          },
        ),
        SeasonStanding(
          teamId: 'pal',
          name: 'Palmeiras',
          position: 2,
          stats: {
            'points': 78,
            'matchesPlayed': 38,
            'wins': 23,
            'draws': 9,
            'loses': 6,
            'goalsFor': 65,
            'goalsAgainst': 30,
          },
        ),
        SeasonStanding(
          teamId: 'fla',
          name: 'Flamengo',
          position: 3,
          stats: {
            'points': 72,
            'matchesPlayed': 38,
            'wins': 21,
            'draws': 9,
            'loses': 8,
            'goalsFor': 61,
            'goalsAgainst': 33,
          },
        ),
      ],
    ),
  ],
  events: const [
    {
      'type': 'transfer',
      'date': '2026-03-12',
      'name': 'Lucas Moura',
      'from': 'fla',
      'to': '40-13',
      'value': 15000000,
    },
    {
      'type': 'injury',
      'date': '2026-07-14',
      'name': 'Calleri',
      'description': 'Lesão muscular',
      'days': 21,
    },
  ],
);
