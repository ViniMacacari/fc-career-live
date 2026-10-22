import 'package:flutter/material.dart';

import '../Common/TrophyForm.dart';
import '../models/Person.dart';

class EditSingleTrophy extends StatelessWidget {
  const EditSingleTrophy({
    super.key,
    required this.person,
    required this.trophy,
  });
  final Person person;
  final Map<String, Object?> trophy;
  @override
  Widget build(BuildContext context) =>
      TrophyForm(person: person, existing: trophy);
}
