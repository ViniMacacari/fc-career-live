import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../utils/Providers/StateProvider.dart';
import '../utils/Components/CareerPageWidgets.dart';
import 'SettingsPage.dart';

class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key, this.state});

  final AppStateNotifier? state;

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  ThemeMode? _fallbackMode;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _fallbackMode = AppStateNotifier.themeModeFromName(
          prefs.getString(themeModePrefsKey),
        );
      });
    });
  }

  AppStateNotifier? _notifier(BuildContext context, {bool listen = true}) =>
      widget.state ?? Provider.of<AppStateNotifier?>(context, listen: listen);

  Future<void> changeTheme(ThemeMode mode) async {
    final notifier = _notifier(context, listen: false);
    setState(() => _fallbackMode = mode);
    if (notifier != null) {
      await notifier.setThemeModeAndPersist(mode);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(themeModePrefsKey, mode.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = _notifier(context);
    final body = notifier == null
        ? _buildList(context, _fallbackMode ?? ThemeMode.system)
        : ListenableBuilder(
            listenable: notifier,
            builder: (context, _) => _buildList(context, notifier.themeMode),
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'settings.appearance'.tr(),
          style: const TextStyle(fontSize: 18),
        ),
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _buildList(BuildContext context, ThemeMode current) => ListView(
    physics: const ClampingScrollPhysics(),
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: CareerPageHeader(
          title: 'Seu estilo de jogo',
          subtitle: 'Escolha como a carreira aparece no seu aparelho.',
          icon: Icons.palette_outlined,
        ),
      ),
      settingsListTile(
        context,
        title: 'settings.system'.tr(),
        isActive: current == ThemeMode.system,
        leadingIcon: TablerIcons.brandAndroid,
        onTap: () => changeTheme(ThemeMode.system),
      ),
      settingsListTile(
        context,
        title: 'settings.light'.tr(),
        isActive: current == ThemeMode.light,
        leadingIcon: TablerIcons.sun,
        onTap: () => changeTheme(ThemeMode.light),
      ),
      settingsListTile(
        context,
        title: 'settings.dark'.tr(),
        isActive: current == ThemeMode.dark,
        leadingIcon: TablerIcons.moon,
        onTap: () => changeTheme(ThemeMode.dark),
      ),
    ],
  );
}
