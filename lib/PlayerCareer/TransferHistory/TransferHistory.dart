import 'package:flutter/material.dart';

import '../../Common/CareerHistoryPage.dart';
import '../../models/Person.dart';

class TransferHistory extends StatelessWidget {
  const TransferHistory({super.key, required this.person});
  final Person person;
  @override
  Widget build(BuildContext context) => CareerHistoryPage(person: person);
}
