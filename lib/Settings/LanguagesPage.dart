import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:jiffy/jiffy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'SettingsPage.dart';
import '../utils/Components/CareerPageWidgets.dart';

class AppLanguageOption {
  const AppLanguageOption(this.code, this.nativeName, this.flagAsset);
  final String code;
  final String nativeName;
  final String flagAsset;
}

const List<AppLanguageOption> appLanguageOptions = [
  AppLanguageOption('en', 'English', 'assets/images/logos/flags/england.svg'),
  AppLanguageOption('it', 'Italiano', 'assets/images/logos/flags/italy.svg'),
  AppLanguageOption(
    'pt_PT',
    'Português',
    'assets/images/logos/flags/portugal.svg',
  ),
  AppLanguageOption(
    'pt_BR',
    'Português (BR)',
    'assets/images/logos/flags/brazil.svg',
  ),
  AppLanguageOption('ru', 'Русский', 'assets/images/logos/flags/russia.svg'),
  AppLanguageOption('fr', 'Français', 'assets/images/logos/flags/france.svg'),
  AppLanguageOption('de', 'Deutsch', 'assets/images/logos/flags/germany.svg'),
  AppLanguageOption('es', 'Español', 'assets/images/logos/flags/spain.svg'),
  AppLanguageOption('tr', 'Türkçe', 'assets/images/logos/flags/turkey.svg'),
  AppLanguageOption(
    'id',
    'Bahasa Indonesia',
    'assets/images/logos/flags/indonesia.svg',
  ),
];

Locale appLocaleFromCode(String code) {
  final parts = code.split('_');
  return parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
}

class LanguagesPage extends StatefulWidget {
  const LanguagesPage({super.key});

  @override
  State<LanguagesPage> createState() => _LanguagesPageState();
}

class _LanguagesPageState extends State<LanguagesPage> {
  bool isActiveLocale(String code) {
    final locale = context.locale;
    final parts = code.split('_');
    if (parts.length > 1) {
      return locale.languageCode == parts[0] && locale.countryCode == parts[1];
    }
    return locale.languageCode == code;
  }

  Future<void> changeLocale(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appLang', code);
    if (!mounted) return;
    await context.setLocale(appLocaleFromCode(code));
    try {
      await Jiffy.setLocale(code);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        'settings.languages'.tr(),
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
              title: 'O idioma da sua carreira',
              subtitle: 'Escolha o idioma dos menus e controles do aplicativo.',
              icon: Icons.language_rounded,
            ),
          ),
          for (final option in appLanguageOptions)
            settingsListTile(
              context,
              title: option.nativeName,
              isActive: isActiveLocale(option.code),
              leading: SvgPicture.asset(
                option.flagAsset,
                package: 'icons_plus',
                height: 35,
              ),
              onTap: () => changeLocale(option.code),
            ),
        ],
      ),
    ),
  );
}
