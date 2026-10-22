import 'package:flutter/material.dart';

import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../utils/Components/CareerUiStyle.dart';
import 'CreateCustomPlayerPage.dart';

Future<Map<String, Object?>?> openCustomPlayerCreator(
  BuildContext context, {
  required Person person,
  required Season season,
  bool addToRoster = true,
}) async {
  Map<String, Object?>? player;
  final saved = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => CreateCustomPlayerPage(
        person: person,
        season: season,
        addToRoster: addToRoster,
        onCreated: (created) => player = created,
      ),
    ),
  );
  return saved == true ? player : null;
}

class CreateCustomPlayerAction extends StatelessWidget {
  const CreateCustomPlayerAction({
    super.key,
    required this.onTap,
    required this.subtitle,
  });
  final VoidCallback onTap;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = CareerUiColors(context);
    return Material(
      color: colors.accent.withValues(alpha: .08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.accent.withValues(alpha: .25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(Icons.person_add_alt_1_rounded, color: colors.accent),
        title: Text(
          'Criar jogador personalizado',
          style: TextStyle(
            color: colors.text,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: colors.muted, fontSize: 12),
        ),
        trailing: Icon(
          Icons.arrow_forward_rounded,
          color: colors.accent,
          size: 20,
        ),
      ),
    );
  }
}
