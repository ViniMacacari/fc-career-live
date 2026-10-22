import 'package:flutter/material.dart';

import '../../Common/CareerHistoryForm.dart';
import '../../models/Person.dart';

class EditManagerHistoryItem extends StatelessWidget {
  const EditManagerHistoryItem({
    super.key,
    required this.person,
    required this.existing,
  });
  final Person person;
  final Map<String, Object?> existing;
  @override
  Widget build(BuildContext context) =>
      CareerHistoryForm(person: person, existing: existing);
}
