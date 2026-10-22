import 'package:flutter/material.dart';

import '../Common/CareerSelector.dart';
import '../models/Person.dart';

class SelectManagerCareerPage extends StatelessWidget {
  const SelectManagerCareerPage({
    super.key,
    required this.onSelected,
    required this.onCreate,
  });
  final ValueChanged<Person> onSelected;
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => CareerSelector(
    category: PersonCategory.manager,
    onSelected: onSelected,
    onCreate: onCreate,
  );
}
