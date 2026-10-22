import 'package:flutter/material.dart';

import '../../Common/StreaksPage.dart';
import '../../models/Person.dart';

class ManagerStreaks extends StatelessWidget {
  const ManagerStreaks({super.key, required this.person});
  final Person person;
  @override
  Widget build(BuildContext context) => StreaksPage(person: person);
}
