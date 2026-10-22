import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'utils/Components/CareerPageWidgets.dart';
import 'utils/Components/CareerUiStyle.dart';
import 'utils/AppBrand.dart';

class StartInitialCareerPage extends StatelessWidget {
  const StartInitialCareerPage({
    super.key,
    required this.onCreateManager,
    required this.onCreatePlayer,
  });
  final VoidCallback onCreateManager, onCreatePlayer;

  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                CareerPageHeader(
                  title: AppBrand.name,
                  eyebrow: 'EA FC',
                  subtitle: 'initialPage.subtitle'.tr(),
                  icon: Icons.sports_soccer_outlined,
                  leading: Image.asset(
                    AppBrand.iconAsset,
                    width: 48,
                    height: 48,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 14),
                  child: Text(
                    'Escolha sua próxima história',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _mode(
                  context,
                  Icons.manage_accounts_outlined,
                  'initialPage.startNewManagerCareer'.tr(),
                  'Monte o elenco, tome decisões e conduza o clube às conquistas.',
                  onCreateManager,
                ),
                _mode(
                  context,
                  Icons.sports_soccer_outlined,
                  'initialPage.startNewPlayerCareer'.tr(),
                  'Acompanhe suas atuações e construa a trajetória de um jogador.',
                  onCreatePlayer,
                ),
                const SizedBox(height: 10),
                Card(
                  child: ExpansionTile(
                    title: const Text('Como funciona'),
                    leading: const CareerIconBadge(
                      icon: Icons.info_outline_rounded,
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    children: [
                      Text(
                        'initialPage.description'.tr(),
                        style: TextStyle(
                          color: c.muted,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'initialPage.note'.tr(),
                        style: TextStyle(
                          color: c.muted,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mode(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => Card(
    child: ListTile(
      onTap: onTap,
      leading: CareerIconBadge(icon: icon, size: 48),
      title: Text(title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(subtitle),
      ),
      trailing: const Icon(Icons.arrow_forward_rounded, size: 20),
    ),
  );
}
