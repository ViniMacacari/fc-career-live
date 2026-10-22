import 'package:flutter/material.dart';

import '../Common/TrophyForm.dart';
import '../models/Person.dart';

class AddTrophyPage extends StatelessWidget {
  const AddTrophyPage({super.key, required this.person});
  final Person person;
  @override
  Widget build(BuildContext context) => TrophyForm(person: person);
}
