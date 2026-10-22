import 'FcScoreApi.dart';
import 'FcScoreModels.dart';

Future<FcScoreMatch> fcDetailedMatch(
  FcScoreApi api,
  FcScoreMatch match, {
  List<FcJson>? reports,
}) async {
  if (match.detailed || match.fixtureId.isEmpty) return match;
  List<FcJson> available;
  try {
    available = reports ?? await api.list('matches');
  } on FcScoreException {
    return match;
  }
  final summary = available
      .where((report) => fcId(report['fixtureId']) == match.fixtureId)
      .firstOrNull;
  if (summary == null) return match;
  try {
    final detailed = FcScoreMatch.fromReport(
      await api.report(match.saveId, fcId(summary['id'])),
    );
    if (detailed.homeId == match.homeId && detailed.awayId == match.awayId) {
      return detailed;
    }
  } on FcScoreException catch (error) {
    match.warnings.add(
      'O relatório com o desempenho dos jogadores não pôde ser carregado: $error',
    );
  }
  return match;
}

Future<Map<String, FcJson>> fcReportsByFixture(
  FcScoreApi api, {
  List<FcJson>? reports,
}) async {
  try {
    return {
      for (final report in (reports ?? await api.list('matches')).reversed)
        if (fcId(report['fixtureId']).isNotEmpty)
          fcId(report['fixtureId']): report,
    };
  } on FcScoreException {
    return {};
  }
}

Future<List<FcScoreMatch>> fcUnsavedReports(
  FcScoreApi api, {
  required String saveId,
  required String savedAt,
  required String clubId,
  required Set<String> playedFixtures,
  required List<FcJson> reports,
}) async {
  if (savedAt.isEmpty) return [];
  final result = <FcScoreMatch>[];
  for (final summary in reports) {
    final teams = [summary['homeTeamId'], summary['awayTeamId']].map(fcId);
    if (fcId(summary['capturedAt']).compareTo(savedAt) <= 0 ||
        playedFixtures.contains(fcId(summary['fixtureId'])) ||
        (teams.any((id) => id.isNotEmpty) && !teams.contains(clubId))) {
      continue;
    }
    try {
      final match = FcScoreMatch.fromReport(
        await api.report(saveId, fcId(summary['id'])),
      );
      if ((match.homeId == clubId || match.awayId == clubId) &&
          match.date != null &&
          match.fixtureId.isNotEmpty &&
          !playedFixtures.contains(match.fixtureId)) {
        result.add(match);
      }
    } on FcScoreException {
      continue;
    }
  }
  return result;
}

FcJson fcFixtureOf(FcScoreMatch match) => {
  'id': fcInt(match.fixtureId) ?? match.fixtureId,
  'date': match.date?.toIso8601String().substring(0, 10),
  'time': match.time,
  'competition': match.competition,
  'stage': match.stage,
  'round': match.round,
  'played': true,
  'home': {'team': fcObject(match.home['team']), 'goals': match.homeGoals},
  'away': {'team': fcObject(match.away['team']), 'goals': match.awayGoals},
};
