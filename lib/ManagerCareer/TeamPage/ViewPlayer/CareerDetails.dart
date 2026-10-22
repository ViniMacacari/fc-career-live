import 'package:flutter/material.dart';

import '../../../models/Person.dart';

class CareerDetails extends StatefulWidget {
  const CareerDetails({
    super.key,
    required this.person,
    required this.playerId,
    this.seasonId,
  });
  final Person person;
  final String playerId;
  final String? seasonId;

  @override
  State<CareerDetails> createState() => _CareerDetailsState();
}

class _CareerDetailsState extends State<CareerDetails> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
