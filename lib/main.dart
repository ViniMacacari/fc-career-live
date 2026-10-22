import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:jiffy/jiffy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ManagerCareer/CreateManagerCareerPage.dart';
import 'ManagerCareer/SelectManagerCareerPage.dart';
import 'PlayerCareer/CreatePlayerCareer/index.dart';
import 'PlayerCareer/SelectPlayerCareer.dart';
import 'RootPage/RootPage.dart';
import 'Settings/CustomConfiguration/CustomConfiguration.dart';
import 'Settings/SettingsPage.dart';
import 'Settings/AISettingsPage.dart';
import 'Twitter/TwitterSettingsPage.dart';
import 'Twitter/TwitterGenerationService.dart';
import 'StartInitialCareerPage.dart';
import 'StartupErrorApp.dart';
import 'models/Person.dart';
import 'translations/translations.dart';
import 'utils/AppPaths.dart';
import 'utils/AppBrand.dart';
import 'utils/themes.dart';
import 'utils/Providers/StateProvider.dart';
import 'utils/GameCatalog.dart';
import 'utils/SqlService.dart';
import 'FcScore/FcScoreConnectionPage.dart';

const supportedLocalesStr = ['en', 'it', 'ru', 'fr', 'de', 'es', 'tr', 'id'];
const supportedLocalesWithCountryCode = ['pt_PT', 'pt_BR'];
final supportedLocales = [
  ...supportedLocalesStr,
  ...supportedLocalesWithCountryCode,
].map(localeFromString).toList();

Locale localeFromString(String value) {
  final parts = value.split('_');
  return parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
}

class CustomAssetsLoader extends AssetLoader {
  const CustomAssetsLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    return getTranslationsFromString(prefs.getString('appLang') ?? 'en');
  }
}

Future<String> resolveAppLanguage() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('appLang');
  if (saved != null) return saved;
  final device = WidgetsBinding.instance.platformDispatcher.locale;
  final withCountry = '${device.languageCode}_${device.countryCode ?? ''}';
  final language = supportedLocalesWithCountryCode.contains(withCountry)
      ? withCountry
      : supportedLocalesStr.contains(device.languageCode)
      ? device.languageCode
      : 'en';
  await prefs.setString('appLang', language);
  return language;
}

CareerMode careerModeOf(Person? person) =>
    person?.category == PersonCategory.player
    ? CareerMode.player
    : CareerMode.manager;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Manrope',
    ], await rootBundle.loadString('assets/fonts/OFL-Manrope.txt'));
  });
  try {
    await EasyLocalization.ensureInitialized();
    await AppPaths.init();
    final language = await resolveAppLanguage();
    try {
      await Jiffy.setLocale(language);
    } catch (_) {}
    final person = await SqlService.instance.getActivePerson();
    final appState = await AppStateNotifier.load(
      careerMode: careerModeOf(person),
    );
    runApp(
      EasyLocalization(
        supportedLocales: supportedLocales,
        path: 'assets/translations',
        assetLoader: const CustomAssetsLoader(),
        startLocale: localeFromString(language),
        fallbackLocale: const Locale('en'),
        child: ChangeNotifierProvider<AppStateNotifier>.value(
          value: appState,
          child: MainApp(initialPerson: person, appState: appState),
        ),
      ),
    );
  } catch (error) {
    runApp(StartupErrorApp(error: error));
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key, this.initialPerson, required this.appState});
  final Person? initialPerson;
  final AppStateNotifier appState;
  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late Person? _active = widget.initialPerson;
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    if (_active != null) {
      unawaited(TwitterGenerationService.instance.runPending(_active!));
    }
  }

  void _activate(Person person) {
    _navigator.currentState?.popUntil((route) => route.isFirst);
    widget.appState.setCareerMode(careerModeOf(person));
    setState(() => _active = person);
    unawaited(TwitterGenerationService.instance.runPending(person));
  }

  Future<void> _reloadActivePerson() async {
    await GameCatalog.reloadCustomData();
    final person = await SqlService.instance.getActivePerson();
    final prefs = await SharedPreferences.getInstance();
    final language = await resolveAppLanguage();
    if (!mounted) return;
    widget.appState.setThemeMode(
      AppStateNotifier.themeModeFromName(prefs.getString(themeModePrefsKey)),
    );
    final locale = localeFromString(language);
    if (supportedLocales.contains(locale) && context.locale != locale) {
      await context.setLocale(locale);
      try {
        await Jiffy.setLocale(language);
      } catch (_) {}
    }
    if (!mounted) return;
    _navigator.currentState?.popUntil((route) => route.isFirst);
    widget.appState.setCareerMode(careerModeOf(person));
    setState(() => _active = person);
  }

  void _openSettings() {
    _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          appState: widget.appState,
          configurationHubBuilder: (_) => const ConfigurationHub(),
          fcScoreBuilder: (_) => FcScoreConnectionPage(initialPerson: _active),
          aiSettingsBuilder: (_) => const AISettingsPage(),
          twitterSettingsBuilder: _active == null
              ? null
              : (_) => TwitterSettingsPage(person: _active!),
          onDataRestored: _reloadActivePerson,
        ),
      ),
    );
  }

  void _create(PersonCategory category) {
    _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => category == PersonCategory.manager
            ? CreateManagerCareerPage(onCreated: _activate)
            : CreatePlayerCareer(onCreated: _activate),
      ),
    );
  }

  void _select(PersonCategory category) {
    _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => category == PersonCategory.manager
            ? SelectManagerCareerPage(
                onSelected: _activate,
                onCreate: () => _create(PersonCategory.manager),
              )
            : SelectPlayerCareer(
                onSelected: _activate,
                onCreate: () => _create(PersonCategory.player),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.appState,
    builder: (context, _) => MaterialApp(
      navigatorKey: _navigator,
      title: AppBrand.name,
      builder: (_, child) => ThemedSystemBars(child: child!),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: widget.appState.lightTheme,
      darkTheme: widget.appState.darkTheme,
      themeMode: widget.appState.themeMode,
      home: _active == null
          ? StartInitialCareerPage(
              onCreateManager: () => _create(PersonCategory.manager),
              onCreatePlayer: () => _create(PersonCategory.player),
            )
          : RootPage(
              person: _active!,
              onCreateManager: () => _create(PersonCategory.manager),
              onCreatePlayer: () => _create(PersonCategory.player),
              onSelectManager: () => _select(PersonCategory.manager),
              onSelectPlayer: () => _select(PersonCategory.player),
              onActivate: _activate,
              onOpenSettings: _openSettings,
            ),
    ),
  );
}
