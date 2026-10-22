import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../utils/Components/CareerPageWidgets.dart';

import 'ClubCustomization/ClubCustomization.dart';
import 'CustomConfigurationComponents.dart';
import 'CustomPlayersPage.dart';
import 'CustomConfiguration_AddCustom/CustomConfigurationAddCustomPage.dart';

class ConfigurationHub extends StatelessWidget {
  const ConfigurationHub({super.key});

  @override
  Widget build(BuildContext context) => CustomConfigurationTheme(
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          'customConfiguration.configurationHub'.tr(),
          maxLines: 2,
          style: const TextStyle(fontSize: 18, height: 1.15),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: CareerPageHeader(
                title: 'Seu futebol, do seu jeito',
                subtitle: 'Gerencie clubes, competições e jogadores para usar nas suas carreiras.',
                icon: Icons.auto_awesome_outlined,
                eyebrow: 'Conteúdo do app',
              ),
            ),
            SettingsTile(
              icon: TablerIcons.library,
              title: 'customConfiguration.customContent'.tr(),
              subtitle: 'customConfiguration.customContentSubtitle'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CustomConfigurationAddCustomPage(),
                ),
              ),
            ),
            SettingsTile(
              icon: TablerIcons.users,
              title: 'Jogadores personalizados',
              subtitle: 'Seus jogadores em todos os FIFAs e carreiras',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CustomPlayersPage(),
                ),
              ),
            ),
            SettingsTile(
              icon: TablerIcons.edit,
              title: 'customConfiguration.clubCustomization'.tr(),
              subtitle: 'customConfiguration.clubCustomizationSubtitle'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ClubCustomization(),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: ListTile(
      leading: CareerIconBadge(icon: icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
