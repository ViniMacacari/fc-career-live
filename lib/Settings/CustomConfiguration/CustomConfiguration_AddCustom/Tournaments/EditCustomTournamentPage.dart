import 'package:flutter/material.dart';

import '../../../../models/Tournament.dart';
import 'CreateCustomTournamentPage.dart';

class EditCustomTournamentPage extends StatelessWidget {
  const EditCustomTournamentPage({
    super.key,
    required this.tournament,
    this.imagePath,
  });
  final Tournament tournament;
  final String? imagePath;
  @override
  Widget build(BuildContext context) =>
      CustomTournamentForm(tournament: tournament, imagePath: imagePath);
}
