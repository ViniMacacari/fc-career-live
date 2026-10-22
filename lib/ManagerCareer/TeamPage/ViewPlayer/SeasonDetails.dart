import 'package:flutter/material.dart';

import '../../../models/Person.dart';

class SeasonDetails extends StatefulWidget {
  const SeasonDetails({
    super.key,
    required this.person,
    required this.playerId,
    this.seasonId,
  });
  final Person person;
  final String playerId;
  final String? seasonId;

  @override
  State<SeasonDetails> createState() => _SeasonDetailsState();
}

class _SeasonDetailsState extends State<SeasonDetails> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
