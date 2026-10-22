import 'package:flutter/material.dart';

import '../../models/Person.dart';
import 'ManagerFixtureForm.dart';

class EditManagerFixturePage extends StatelessWidget {
  const EditManagerFixturePage({
    super.key,
    required this.person,
    required this.fixture,
  });
  final Person person;
  final Map<String, Object?> fixture;
  @override
  Widget build(BuildContext context) =>
      ManagerFixtureForm(person: person, existing: fixture);
}
