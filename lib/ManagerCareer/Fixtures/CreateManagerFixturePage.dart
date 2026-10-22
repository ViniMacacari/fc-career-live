import 'package:flutter/material.dart';

import '../../models/Person.dart';
import 'ManagerFixtureForm.dart';

class CreateManagerFixturePage extends StatelessWidget {
  const CreateManagerFixturePage({
    super.key,
    required this.person,
    this.seasonId,
  });
  final Person person;
  final String? seasonId;
  @override
  Widget build(BuildContext context) =>
      ManagerFixtureForm(person: person, seasonId: seasonId);
}
