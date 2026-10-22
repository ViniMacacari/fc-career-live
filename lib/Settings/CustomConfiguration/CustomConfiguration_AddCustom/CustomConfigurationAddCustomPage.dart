import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../utils/Components/CareerPageWidgets.dart';

import '../CustomConfiguration.dart';
import '../CustomConfigurationComponents.dart';
import 'Leagues/LeaguesConfigurationPage.dart';
import 'Teams/TeamsConfigurationPage.dart';
import 'Tournaments/TournamentsConfigurationPage.dart';

class CustomConfigurationAddCustomPage extends StatelessWidget {
  const CustomConfigurationAddCustomPage({super.key});

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) => CustomConfigurationTheme(
    child: Scaffold(
      appBar: AppBar(title: Text('customConfiguration.customContent'.tr())),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: CareerPageHeader(
                title: 'Monte o seu futebol',
                subtitle: 'Use seus clubes e competições em qualquer carreira. Nome, escudo e troféu ficam organizados no mesmo lugar.',
                icon: Icons.dashboard_customize_outlined,
                eyebrow: 'Conteúdo do app',
              ),
            ),
            SettingsTile(
              icon: TablerIcons.listNumbers,
              title: 'customConfiguration.leagues'.tr(),
              subtitle:
                  'Organize as ligas, seus clubes e a taça do campeonato.',
              onTap: () => _open(context, const LeaguesConfigurationPage()),
            ),
            SettingsTile(
              icon: TablerIcons.rosette,
              title: 'customConfiguration.teams'.tr(),
              subtitle: 'Cadastre clubes e configure nomes e escudos.',
              onTap: () => _open(context, const TeamsConfigurationPage()),
            ),
            SettingsTile(
              icon: TablerIcons.tournament,
              title: 'customConfiguration.tournaments'.tr(),
              subtitle: 'Defina formato, participantes, logo e troféu.',
              onTap: () => _open(context, const TournamentsConfigurationPage()),
            ),
          ],
        ),
      ),
    ),
  );
}
