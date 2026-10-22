import 'package:flutter/material.dart';

import '../../Common/HeadToHeadPage.dart';
import '../../models/Person.dart';

class ManagerHeadToHeadResultsPage extends StatelessWidget {
  const ManagerHeadToHeadResultsPage({super.key, required this.person});
  final Person person;
  @override
  Widget build(BuildContext context) => HeadToHeadPage(person: person);
}
