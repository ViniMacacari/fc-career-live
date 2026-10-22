import 'package:flutter/material.dart';

import '../../Common/CareerForm.dart';
import '../../models/Person.dart';

class CreatePlayerCareer extends StatelessWidget {
  const CreatePlayerCareer({super.key, required this.onCreated});
  final ValueChanged<Person> onCreated;
  @override
  Widget build(BuildContext context) =>
      CareerForm(category: PersonCategory.player, onCreated: onCreated);
}
