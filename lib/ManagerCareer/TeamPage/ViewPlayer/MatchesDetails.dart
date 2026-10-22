import 'package:flutter/material.dart';

import '../../../models/Person.dart';

class MatchesDetails extends StatefulWidget {
  const MatchesDetails({
    super.key,
    required this.person,
    required this.playerId,
    this.seasonId,
  });
  final Person person;
  final String playerId;
  final String? seasonId;

  @override
  State<MatchesDetails> createState() => _MatchesDetailsState();
}

class _MatchesDetailsState extends State<MatchesDetails> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
