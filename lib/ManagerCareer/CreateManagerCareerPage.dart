import 'package:flutter/material.dart';

import '../Common/CareerForm.dart';
import '../models/Person.dart';

class CreateManagerCareerPage extends StatelessWidget {
  const CreateManagerCareerPage({super.key, required this.onCreated});
  final ValueChanged<Person> onCreated;
  @override
  Widget build(BuildContext context) =>
      CareerForm(category: PersonCategory.manager, onCreated: onCreated);
}
