import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'utils/BackupService.dart';
import 'utils/themes.dart';
import 'utils/AppBrand.dart';

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppBrand.name,
    theme: managerLightTheme,
    darkTheme: managerDarkTheme,
    builder: (_, child) => ThemedSystemBars(child: child!),
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    home: StartupErrorScreen(error: error),
  );
}

class StartupErrorScreen extends StatefulWidget {
  const StartupErrorScreen({super.key, this.error});

  final Object? error;

  @override
  State<StartupErrorScreen> createState() => _StartupErrorScreenState();
}

class _StartupErrorScreenState extends State<StartupErrorScreen> {
  bool _busy = false;

  Future<void> _shareBackup() async {
    setState(() => _busy = true);
    try {
      final path = await BackupService().generateBackup(includeImages: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not create backup: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Unable to start the app',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                'Something went wrong while starting the app. '
                'The error has been reported.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _busy ? null : _shareBackup,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.backup_outlined),
                label: const Text('Get Backup File', maxLines: 1),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
