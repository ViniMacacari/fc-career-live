import 'package:flutter/material.dart';

import '../../Common/CareerHistoryForm.dart';
import '../../models/Person.dart';

class CreateManagerHistoryItem extends StatelessWidget {
  const CreateManagerHistoryItem({super.key, required this.person});
  final Person person;
  @override
  Widget build(BuildContext context) => CareerHistoryForm(person: person);
}
