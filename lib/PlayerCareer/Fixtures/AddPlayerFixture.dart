import 'package:flutter/material.dart';

import '../../Common/FixtureForm.dart';
import '../../models/Person.dart';

class AddPlayerFixture extends StatelessWidget {
  const AddPlayerFixture({super.key, required this.person});
  final Person person;
  @override
  Widget build(BuildContext context) => FixtureForm(person: person);
}
