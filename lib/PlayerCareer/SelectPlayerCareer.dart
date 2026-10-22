import 'package:flutter/material.dart';

import '../Common/CareerSelector.dart';
import '../models/Person.dart';

class SelectPlayerCareer extends StatelessWidget {
  const SelectPlayerCareer({
    super.key,
    required this.onSelected,
    required this.onCreate,
  });
  final ValueChanged<Person> onSelected;
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => CareerSelector(
    category: PersonCategory.player,
    onSelected: onSelected,
    onCreate: onCreate,
  );
}
