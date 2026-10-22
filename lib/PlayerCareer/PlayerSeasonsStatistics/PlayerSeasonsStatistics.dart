import 'package:flutter/material.dart';

import '../../Common/CareerStatisticsPage.dart';
import '../../models/Person.dart';

class PlayerSeasonsStatistics extends StatelessWidget {
  const PlayerSeasonsStatistics({super.key, required this.person});
  final Person person;
  @override
  Widget build(BuildContext context) => CareerStatisticsPage(person: person);
}
