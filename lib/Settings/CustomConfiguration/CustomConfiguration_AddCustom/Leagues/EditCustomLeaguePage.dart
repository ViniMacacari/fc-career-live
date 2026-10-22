import 'package:flutter/material.dart';

import '../../../../models/CustomLeague.dart';
import 'CreateCustomLeaguePage.dart';

class EditCustomLeaguePage extends StatelessWidget {
  const EditCustomLeaguePage({super.key, required this.league});
  final CustomLeague league;
  @override
  Widget build(BuildContext context) => CustomLeagueForm(league: league);
}
