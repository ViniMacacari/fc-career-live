import 'package:flutter/material.dart';

import '../../Common/FixtureDetailsPage.dart';
import '../../models/Person.dart';

class ViewPlayerFixturePage extends StatelessWidget {
  const ViewPlayerFixturePage({
    super.key,
    required this.person,
    required this.fixture,
    required this.opponent,
    required this.tournament,
    this.tournamentLogo,
  });
  final Person person;
  final Map<String, Object?> fixture;
  final String opponent, tournament;
  final String? tournamentLogo;
  @override
  Widget build(BuildContext context) => FixtureDetailsPage(
    person: person,
    fixture: fixture,
    opponent: opponent,
    tournament: tournament,
    tournamentLogo: tournamentLogo,
  );
}
