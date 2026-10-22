import 'package:flutter/material.dart';

import '../ManagerCareer/Fixtures/ViewManagerFixturePage.dart';
import '../PlayerCareer/Fixtures/ViewPlayerFixturePage.dart';
import '../models/Person.dart';
import '../utils/GameCatalog.dart';
import '../utils/SqlService.dart';

Future<void> openFixtureDetails(
  BuildContext context,
  Person person,
  String fixtureId, {
  bool replace = false,
  SqlService? sql,
}) async {
  final service = sql ?? SqlService.instance;
  final row = await service.getFixture(person.category, person.id, fixtureId);
  final catalog = await GameCatalog.load();
  final tournaments = await catalog.tournaments(person.fifaVersion);
  final custom = await service.getCustomTournaments(person.fifaVersion);
  if (row == null || !context.mounted) return;
  final tournamentId = '${row['tournamentId']}';
  final tournament =
      {
        for (final t in tournaments) t.id: t.label,
        for (final t in custom) t.id: t.name,
        for (final league in catalog.leagues(person.fifaVersion))
          'league:${league.id}': league.label,
      }[tournamentId] ??
      tournamentId;
  final logo = tournaments
      .where((t) => t.id == tournamentId)
      .firstOrNull
      ?.assetPath;
  final opponent = catalog.teamLabel(
    person.fifaVersion,
    '${row['oppositeTeamId']}',
    leagueId: row['oppositeTeamLeagueId']?.toString(),
  );
  final route = MaterialPageRoute<bool>(
    builder: (_) => person.category == PersonCategory.player
        ? ViewPlayerFixturePage(
            person: person,
            fixture: row,
            opponent: opponent,
            tournament: tournament,
            tournamentLogo: logo,
          )
        : ViewManagerFixturePage(
            person: person,
            fixture: row,
            opponent: opponent,
            tournament: tournament,
            tournamentLogo: logo,
          ),
  );
  if (replace) {
    await Navigator.pushReplacement<bool, bool>(context, route, result: true);
  } else {
    await Navigator.push<bool>(context, route);
  }
}
