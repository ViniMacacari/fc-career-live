import 'package:flutter/material.dart';

import '../../Common/FixturesPage.dart';
import '../../models/Person.dart';

class PlayerFixturesPage extends StatelessWidget {
  const PlayerFixturesPage({super.key, required this.person});
  final Person person;
  @override
  Widget build(BuildContext context) => FixturesPage(person: person);
}
