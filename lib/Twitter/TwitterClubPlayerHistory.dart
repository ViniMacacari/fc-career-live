import '../ManagerCareer/TeamPage/ViewPlayer/PlayerProfileData.dart';
import '../models/MatchPerformanceStats.dart';
import 'TwitterCareerSummary.dart';
import 'TwitterStore.dart';

class TwitterClubPlayerHistory {
  static SocialRow build(List<SocialRow> rows, TwitterCareerSummary summary) {
    final matches = rows.map(PlayerMatchData.new).toList();
    for (final match in matches) {
      if (match.performance.goalDetails.isNotEmpty) {
        match.performance.goalsCount ??= match.performance.goalDetails.length;
      }
      if (match.performance.assistDetails.isNotEmpty) {
        match.performance.assistsCount ??=
            match.performance.assistDetails.length;
      }
    }
    final seasons = <String, List<PlayerMatchData>>{};
    for (final match in matches) {
      (seasons[match.seasonId] ??= []).add(match);
    }
    return {
      'status': rows.isEmpty ? 'unknown' : 'recorded',
      'scope': 'allRecordedSeasonsAtThisClubThroughEventDate',
      'clubId': summary.teamId,
      'asOf': summary.eventDate.toIso8601String(),
      'totals': _totals(matches),
      if (matches.isNotEmpty) ...{
        'firstAppearance': '${matches.last.row['date']}',
        'lastAppearance': '${matches.first.row['date']}',
        'seasons': [
          for (final entry in seasons.entries)
            {
              'seasonId': entry.key,
              'season': summary.seasonLabel(entry.key),
              ..._totals(entry.value),
              'competitions': _competitions(entry.value, summary),
            },
        ],
        'competitions': _competitions(matches, summary),
      },
      'interpretation': 'Estes são os números de toda a passagem registrada pelo clube, não apenas os últimos cinco jogos. Campos ausentes não são zero. Não somar estatísticas de outros clubes nem posteriores à saída.',
    };
  }

  static List<SocialRow> _competitions(
    List<PlayerMatchData> matches,
    TwitterCareerSummary summary,
  ) {
    final groups = <String, List<PlayerMatchData>>{};
    for (final match in matches) {
      (groups[match.tournamentId] ??= []).add(match);
    }
    return [
      for (final entry in groups.entries)
        {
          'tournamentId': entry.key,
          'competition': summary.tournaments[entry.key] ?? entry.key,
          ..._totals(entry.value),
        },
    ];
  }

  static SocialRow _totals(List<PlayerMatchData> matches) {
    final totals = PlayerTotals(matches);
    final native = matches.map((m) => m.performance.toMap()).toList();
    final known = <String, int>{};
    final numbers = <String, num>{};
    for (final (key, label) in [
      ('goalsCount', 'goals'),
      ('assistsCount', 'assists'),
      ('yellowCards', 'yellowCards'),
      ('redCards', 'redCards'),
      ('shotsCount', 'shots'),
      ('passes', 'passes'),
      ('keyPasses', 'keyPasses'),
      ('tackles', 'tackles'),
      ('dribbles', 'dribbles'),
      ('saves', 'saves'),
      ('penaltySaves', 'penaltySaves'),
    ]) {
      final values = native
          .map((r) => r[key])
          .whereType<num>()
          .where((n) => n.isFinite && n >= 0)
          .toList();
      if (values.isNotEmpty) {
        numbers[label] = values.fold<num>(0, (a, b) => a + b);
        known[label] = values.length;
      }
    }
    final advanced = matches.map((m) => m.performance.apiStats).toList();
    final accuracies = <String, Object?>{};
    for (final (key, attemptsKey) in [
      ('shotAccuracy', 'shotsCount'),
      ('passAccuracy', 'passes'),
      ('tacklesAccuracy', 'tackles'),
      ('dribblesAccuracy', 'dribbles'),
    ]) {
      num weighted = 0, attempts = 0;
      var recorded = 0;
      for (final row in native) {
        final accuracy = row[key], count = row[attemptsKey];
        if (accuracy is num &&
            accuracy.isFinite &&
            accuracy >= 0 &&
            accuracy <= 100 &&
            count is num &&
            count.isFinite &&
            count > 0) {
          weighted += accuracy * count;
          attempts += count;
          recorded++;
        }
      }
      if (attempts > 0) {
        accuracies[key] = {
          'percentage': weighted / attempts,
          'attempts': attempts,
          'recordedMatches': recorded,
        };
      }
    }
    final api = <String, Object?>{};
    for (final stat in performanceStats) {
      final value = stat.total(advanced);
      if (value != null) {
        api[stat.key] = {
          'label': stat.label,
          'value': value,
          'recordedMatches': advanced
              .where(
                (r) => r[stat.percentage ? stat.numerator : stat.key] is num,
              )
              .length,
        };
      }
    }
    final goalTypes = <String, int>{};
    for (final match in matches) {
      for (final goal in match.performance.goalDetails) {
        for (final type in goal.type) {
          goalTypes.update(type.name, (n) => n + 1, ifAbsent: () => 1);
        }
      }
    }
    return {
      'appearances': totals.matches,
      'starts': totals.starts,
      'minutes': totals.minutes,
      ...numbers,
      'recordedMatchesByStat': known,
      'partialStats': [
        for (final entry in known.entries)
          if (entry.value < matches.length) entry.key,
      ],
      if (accuracies.isNotEmpty) 'weightedAccuracies': accuracies,
      if (totals.rating != null) 'averageRating': totals.rating,
      'ratedMatches': totals.ratedMatches,
      'matchesWithRecordedMinutes': matches
          .where((m) => m.performance.recordedMinutes != null)
          .length,
      'matchesWithGoalDetails': matches
          .where((m) => m.row['goalDetails'] != null)
          .length,
      'manOfTheMatch': totals.motm,
      'penaltyGoalsRecorded': totals.penalties,
      'missedPenaltiesRecorded': matches.fold<int>(
        0,
        (n, m) => n + m.performance.missedPenaltyDetails.length,
      ),
      'ownGoalsRecorded': matches.fold<int>(
        0,
        (n, m) => n + m.performance.ownGoalDetails.length,
      ),
      if (totals.hasCaptaincy) 'captainGames': totals.captainGames,
      if (goalTypes.isNotEmpty) 'goalsByType': goalTypes,
      if (api.isNotEmpty) 'advancedStats': api,
    };
  }
}
