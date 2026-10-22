import '../utils/AppColors.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../utils/Components/CareerPageWidgets.dart';
import '../utils/Components/CareerUiStyle.dart';

import '../utils/Providers/StateProvider.dart';
import 'AppearancePage.dart';
import 'LanguagesPage.dart';
import 'ToolsPage.dart';
import '../FcScore/FcScoreConnectionPage.dart';

const Color settingsNewBadgeColor = AppColors.newBadge;

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.appState,
    this.configurationHubBuilder,
    this.dashboardBuilder,
    this.aiSettingsBuilder,
    this.twitterSettingsBuilder,
    this.fcScoreBuilder,
    this.onDataRestored,
  });

  final AppStateNotifier? appState;

  final WidgetBuilder? configurationHubBuilder;

  final WidgetBuilder? dashboardBuilder;

  final WidgetBuilder? aiSettingsBuilder;
  final WidgetBuilder? twitterSettingsBuilder;
  final WidgetBuilder? fcScoreBuilder;

  final VoidCallback? onDataRestored;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  void _open(WidgetBuilder builder) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
  }

  @override
  Widget build(BuildContext context) {
    final hub = widget.configurationHubBuilder;
    final dashboard = widget.dashboardBuilder;
    final ai = widget.aiSettingsBuilder;
    final twitter = widget.twitterSettingsBuilder;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'settings.settings'.tr(),
          style: const TextStyle(fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: ListView(
          physics: const ClampingScrollPhysics(),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: CareerPageHeader(
                title: 'Do seu jeito',
                subtitle: 'Personalize a aparência, os conteúdos e as opções da carreira.',
                icon: Icons.tune_rounded,
                eyebrow: 'Configurações',
              ),
            ),
            settingsSectionHeader('settings.common'.tr(), first: true),
            settingsListTile(
              context,
              title: 'FC Score API',
              leadingIcon: Icons.connected_tv_rounded,
              subtitle: 'Conectar ao PC, consultar o save e importar partidas',
              onTap: () => _open(
                widget.fcScoreBuilder ?? (_) => const FcScoreConnectionPage(),
              ),
            ),
            settingsListTile(
              context,
              title: 'settings.languages'.tr(),
              leadingIcon: TablerIcons.language,
              onTap: () => _open((_) => const LanguagesPage()),
            ),
            settingsListTile(
              context,
              title: 'settings.appearance'.tr(),
              leadingIcon: TablerIcons.paint,
              onTap: () => _open((_) => AppearancePage(state: widget.appState)),
            ),
            if (hub != null)
              settingsListTile(
                context,
                title: 'customConfiguration.configurationHub'.tr(),
                leadingIcon: TablerIcons.adjustmentsHorizontal,
                onTap: () => _open(hub),
              ),
            if (dashboard != null)
              settingsListTile(
                context,
                title: 'settings.dashboard'.tr(),
                leadingIcon: TablerIcons.chartColumn,
                onTap: () => _open(dashboard),
              ),
            if (ai != null)
              settingsListTile(
                context,
                title: 'settings.ai.title'.tr(),
                leadingIcon: TablerIcons.ai,
                onTap: () => _open(ai),
              ),
            if (twitter != null)
              settingsListTile(
                context,
                title: 'X (Rede Social)',
                leadingIcon: TablerIcons.brandX,
                subtitle: 'Geração de posts, respostas e contas',
                onTap: () => _open(twitter),
              ),
            settingsSectionHeader('other.other'.tr()),
            settingsListTile(
              context,
              title: 'settings.tools'.tr(),
              leadingIcon: Icons.space_dashboard_outlined,
              onTap: () => _open(
                (_) => ToolsPage(onDataRestored: widget.onDataRestored),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget settingsSectionHeader(String text, {bool first = false}) => Padding(
  padding: EdgeInsets.fromLTRB(20, first ? 0 : 18, 20, 10),
  child: Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.3,
    ),
  ),
);

Widget settingsListTile(
  BuildContext context, {
  required String title,
  VoidCallback? onTap,
  bool isActive = false,
  Widget? leading,
  IconData? leadingIcon,
  String? subtitle,
  Widget? trailing,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final c = CareerUiColors(context);
  final background = isActive
      ? Color.alphaBlend(c.accent.withValues(alpha: .12), c.panel)
      : c.panel;
  return Card(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    color: background,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: BorderSide(
        color: isActive ? c.accent.withValues(alpha: .5) : c.line,
      ),
    ),
    child: ListTile(
      onTap: onTap,
      leading: leadingIcon != null
          ? CareerIconBadge(icon: leadingIcon)
          : leading,
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: TextStyle(color: c.muted, fontSize: 12)),
      trailing:
          trailing ??
          (isActive
              ? Icon(Icons.check_circle_outline, color: c.accent)
              : onTap == null
              ? null
              : Icon(Icons.chevron_right_rounded, color: c.muted)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
  );
}
