import 'package:flutter/material.dart';

import '../../Common/FixturesPage.dart';
import '../../models/Person.dart';

class ManagerFixturesPage extends StatelessWidget {
  const ManagerFixturesPage({super.key, required this.person});
  final Person person;
  @override
  Widget build(BuildContext context) => FixturesPage(person: person);
}
