import 'package:flutter/material.dart';

import '../../Common/HeadToHeadPage.dart';
import '../../models/Person.dart';

class PlayerHeadToHeadResultsPage extends StatelessWidget {
  const PlayerHeadToHeadResultsPage({super.key, required this.person});
  final Person person;
  @override
  Widget build(BuildContext context) => HeadToHeadPage(person: person);
}
