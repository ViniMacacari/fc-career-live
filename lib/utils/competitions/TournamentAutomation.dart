import 'package:shared_preferences/shared_preferences.dart';

import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../models/TournamentResult.dart';
import '../../models/Trophy.dart';
import '../GameCatalog.dart';
import '../CompetitionTrophies.dart';
import '../SqlService.dart';
import 'CompetitionFormats.dart';
import 'TournamentOutcomes.dart';

class TournamentAutomation {
  TournamentAutomation._();

  static String autoId(String seasonId, String tournamentId) =>
      'auto:$seasonId:$tournamentId';
  static bool isAuto(String id) => id.startsWith('auto:');

  static String _dismissedResults(String personId) =>
      'auto_results_dismissed_$personId';
  static String _dismissedTrophies(String personId) =>
      'auto_trophies_dismissed_$personId';

  static Future<void> dismiss(
    String personId,
    String id, {
    bool trophy = false,
  }) async {
    if (!isAuto(id)) return;
    final prefs = await SharedPreferences.getInstance();
    final key = trophy
        ? _dismissedTrophies(personId)
        : _dismissedResults(personId);
    await prefs.setStringList(
      key,
      <String>{...prefs.getStringList(key) ?? const <String>[], id}.toList(),
    );
  }

  static Future<CompetitionFormat Function(String)> formats(
    Person person,
  ) async {
    final custom = {
      for (final t in await SqlService.instance.getCustomTournaments(
        person.fifaVersion,
      ))
        t.id: t.format,
    };
    return (id) =>
        CompetitionFormat.of(id, person.fifaVersion, customFormat: custom[id]);
  }

  static const otherTrophy = '-1';

  static Future<Map<String, String>> competitionNames(Person person) async {
    final catalog = await GameCatalog.load();
    return {
      for (final item in await catalog.tournaments(person.fifaVersion))
        item.id: item.label,
      for (final item in await SqlService.instance.getCustomTournaments(
        person.fifaVersion,
      ))
        item.id: item.name,
      for (final item in catalog.leagues(person.fifaVersion))
        'league:${item.id}': item.label,
    };
  }

  static Future<List<TournamentOutcome>> outcomes(
    Person person,
    Season season, {
    List<Map<String, Object?>>? careerFixtures,
    CompetitionFormat Function(String)? formatOf,
  }) async {
    final fixtures =
        careerFixtures ??
        await SqlService.instance.getFixtures(person.id, person.category);
    return TournamentOutcome.compute(
      fixtures.where((f) => f['seasonId'] == season.id),
      formatOf: formatOf ?? await formats(person),
      seasonOver: _over(season, fixtures),
    );
  }

  static bool _over(Season season, List<Map<String, Object?>> fixtures) {
    if (season.isClosed) return true;
    final end = DateTime(
      season.endDate.year,
      season.endDate.month,
      season.endDate.day + 1,
    );
    return fixtures.any(
      (f) => DateTime.tryParse('${f['date']}')?.isAfter(end) ?? false,
    );
  }

  static Future<void> sync(Person person) async {
    final db = SqlService.instance;
    final seasons = await db.getSeasons(person.id);
    final fixtures = await db.getFixtures(person.id, person.category);
    final formatOf = await formats(person);
    final names = await competitionNames(person);
    final results = await db.getTournamentResults(person.id);
    final trophies = await db.getTrophies(person.id);
    final linkedAwards = {
      for (final t in await CompetitionTrophies.all())
        if (t.version == person.fifaVersion) t.competitionId: t.awardId,
    };
    final prefs = await SharedPreferences.getInstance();
    final dismissedResults = {
      ...prefs.getStringList(_dismissedResults(person.id)) ?? const [],
    };
    final dismissedTrophies = {
      ...prefs.getStringList(_dismissedTrophies(person.id)) ?? const [],
    };
    final keptResults = <String>{}, keptTrophies = <String>{};
    for (final season in seasons) {
      final outcomes = await TournamentAutomation.outcomes(
        person,
        season,
        careerFixtures: fixtures,
        formatOf: formatOf,
      );
      for (final outcome in outcomes) {
        if (!outcome.recognized) continue;
        final id = autoId(season.id, outcome.tournamentId);
        final manualResult = results
            .where(
              (r) =>
                  r.seasonId == season.id &&
                  r.tournamentId == outcome.tournamentId &&
                  !isAuto(r.id),
            )
            .firstOrNull;
        if (outcome.definitive &&
            manualResult == null &&
            !dismissedResults.contains(id)) {
          keptResults.add(id);
          final current = results.where((r) => r.id == id).firstOrNull;
          if (current?.result != outcome.resultText ||
              current?.isWinner != outcome.won) {
            await db.saveTournamentResult(
              TournamentResult(
                id: id,
                seasonId: season.id,
                fifaVersion: person.fifaVersion,
                tournamentId: outcome.tournamentId,
                result: outcome.resultText,
                personId: person.id,
                youParticipatedIn: true,
                isWinner: outcome.won,
              ),
            );
          }
        }
        final award =
            linkedAwards[outcome.tournamentId] ??
            outcome.format.awardId ??
            otherTrophy;
        final description = award == otherTrophy
            ? names[outcome.tournamentId] ?? outcome.tournamentId
            : null;
        final decisive = outcome.decisive ?? outcome.fixtures.last;
        final competitionName =
            names[outcome.tournamentId] ?? outcome.tournamentId;
        final manualTrophy = trophies.any(
          (t) =>
              t['seasonId'] == season.id &&
              ((t['awardId'] == award &&
                      (award != otherTrophy ||
                          t['description'] == description)) ||
                  (t['awardId'] == otherTrophy &&
                      t['description'] == competitionName)) &&
              !isAuto('${t['id']}'),
        );
        if ((manualResult?.isWinner ?? outcome.won) &&
            !manualTrophy &&
            !dismissedTrophies.contains(id)) {
          keptTrophies.add(id);
          final national =
              outcome.format.national ||
              decisive['playerTeamLeagueId'] == GameCatalog.nationalLeagueId;
          final currentTrophy = trophies
              .where((t) => t['id'] == id)
              .firstOrNull;
          if (currentTrophy != null) {
            if (linkedAwards.containsKey(outcome.tournamentId) &&
                currentTrophy['awardId'] == otherTrophy &&
                currentTrophy['description'] == competitionName) {
              await (await db.database).update(
                'Trophies',
                {'awardId': award},
                where: 'id = ? AND personId = ?',
                whereArgs: [id, person.id],
              );
            }
            continue;
          }
          await db.saveTrophy(
            Trophy(
              id: id,
              teamId: '${decisive['playerTeamId'] ?? person.teamId}',
              isNational: national,
              awardId: award,
              count: 1,
              seasonId: season.id,
              personId: person.id,
              date: DateTime.tryParse('${decisive['date']}'),
              leagueId: decisive['playerTeamLeagueId']?.toString(),
              fixtureId: decisive['id']?.toString(),
              description: description,
            ),
          );
        }
      }
    }
    for (final result in results) {
      if (isAuto(result.id) && !keptResults.contains(result.id)) {
        await db.deleteTournamentResult(person.id, result.id);
      }
    }
    for (final trophy in trophies) {
      final id = '${trophy['id']}';
      if (isAuto(id) && !keptTrophies.contains(id)) {
        await db.deleteTrophy(id);
      }
    }
  }

  static Future<void> trySync(Person person) async {
    try {
      await sync(person);
    } catch (_) {}
  }
}
