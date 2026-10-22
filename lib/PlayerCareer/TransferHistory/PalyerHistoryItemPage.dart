import 'package:flutter/material.dart';

import '../../Common/CareerHistoryForm.dart';
import '../../models/Person.dart';

class PalyerHistoryItemPage extends StatelessWidget {
  const PalyerHistoryItemPage({super.key, required this.person, this.existing});
  final Person person;
  final Map<String, Object?>? existing;
  @override
  Widget build(BuildContext context) =>
      CareerHistoryForm(person: person, existing: existing);
}
