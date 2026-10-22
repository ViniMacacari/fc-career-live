import 'package:flutter/material.dart';

import '../../../../models/CustomClub.dart';
import 'CreateCustomTeamPage.dart';

class EditCustomTeamPage extends StatelessWidget {
  const EditCustomTeamPage({super.key, required this.club});
  final CustomClub club;
  @override
  Widget build(BuildContext context) => CustomTeamForm(club: club);
}
