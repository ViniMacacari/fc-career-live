import '../utils/AppColors.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/Person.dart';
import '../utils/Components/TeamLogo.dart';
import '../utils/GameCatalog.dart';
import '../utils/Components/CareerUiStyle.dart';

class DrawerHat extends StatelessWidget {
  const DrawerHat({
    super.key,
    required this.person,
    required this.onChangeCareer,
  });
  final Person person;
  final VoidCallback onChangeCareer;

  @override
  Widget build(BuildContext context) => FutureBuilder<GameCatalog>(
    future: GameCatalog.load(),
    builder: (context, snapshot) {
      final item = snapshot.data?.team(
        person.fifaVersion,
        person.teamId,
        leagueId: person.leagueId,
      );
      final team = item?.label ?? '';
      final manager = person.category == PersonCategory.manager;
      final c = CareerUiColors(context);
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: manager
                ? [
                    AppColors.of(context).headerStart,
                    AppColors.of(context).panel,
                  ]
                : [
                    AppColors.of(context).headerStart,
                    AppColors.of(context).panel,
                  ],
          ),
          border: Border.all(color: c.accent.withValues(alpha: .28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SUA CARREIRA',
              style: TextStyle(
                color: AppColors.of(context).accent,
                fontSize: 10,
                letterSpacing: 1.7,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.of(context).text.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: TeamLogo.fromItem(item, size: 42),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.of(context).text,
                          fontSize: 18,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        team,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.of(context).muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final label in [
                  person.fifaVersion,
                  manager ? 'Técnico' : 'Jogador',
                ])
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).text.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: AppColors.of(context).muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.of(context).text,
                  backgroundColor: AppColors.of(context).text
                      .withValues(alpha: .05),
                  side: BorderSide(
                    color: AppColors.of(context).text.withValues(alpha: .22),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                ),
                onPressed: onChangeCareer,
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: Text(
                  manager
                      ? 'rootPage.changeManager'.tr()
                      : 'rootPage.changePlayer'.tr(),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
