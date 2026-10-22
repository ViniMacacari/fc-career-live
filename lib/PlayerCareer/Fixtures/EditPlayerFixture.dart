import 'package:flutter/material.dart';

import '../../Common/FixtureForm.dart';
import '../../models/Person.dart';

class EditPlayerFixture extends StatelessWidget {
  const EditPlayerFixture({
    super.key,
    required this.person,
    required this.fixture,
  });
  final Person person;
  final Map<String, Object?> fixture;
  @override
  Widget build(BuildContext context) =>
      FixtureForm(person: person, existing: fixture);
}
