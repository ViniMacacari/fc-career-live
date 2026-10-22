import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart' show FilePicker, PlatformFile;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../utils/BackupService.dart';
import '../utils/Components/CareerPageWidgets.dart';
import 'SettingsPage.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key, this.onDataRestored, this.backupService});

  final VoidCallback? onDataRestored;

  final BackupService? backupService;

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  bool _busy = false;

  BackupService get _service => widget.backupService ?? BackupService();

  void _showSnackbar(String message, {bool isError = false, IconData? icon}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    final color = isError
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                icon ?? (isError ? Icons.error_outline : Icons.check),
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message, style: TextStyle(color: color)),
              ),
            ],
          ),
        ),
      );
  }

  Future<void> _shareBackup() async {
    final includeImages = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var checked = true;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('settings.shareBackup'.tr()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'settings.includeImagesContent'.tr(),
                  textAlign: TextAlign.start,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Checkbox(
                      value: checked,
                      onChanged: (v) =>
                          setDialogState(() => checked = v ?? false),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setDialogState(() => checked = !checked),
                        child: Text('settings.includeImagesLabel'.tr()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('common.cancel'.tr()),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(checked),
                child: Text('common.continue'.tr()),
              ),
            ],
          ),
        );
      },
    );
    if (includeImages == null || !mounted) return;

    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    String? path;
    try {
      path = await _service.generateBackup(includeImages: includeImages);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], sharePositionOrigin: origin),
      );
      _showSnackbar(
        '${'settings.backupFileCreated'.tr()}: $path',
        icon: TablerIcons.databaseExport,
      );
    } catch (_) {
      if (path != null && File(path).existsSync()) {
        _showSnackbar(
          '${'settings.backupSavedLocally'.tr()}: $path',
          icon: TablerIcons.databaseExport,
        );
      } else {
        _showSnackbar('settings.backupNotCreated'.tr(), isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() => _restore(otherApp: false);

  Future<void> _importFromOtherApp() => _restore(otherApp: true);

  Future<void> _restore({required bool otherApp}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          otherApp ? 'Importar de outros apps' : 'settings.restoreBackup'.tr(),
        ),
        content: Text(
          otherApp
              ? 'Escolha o backup gerado por outro app de carreira. As carreiras deste aparelho serão substituídas pelas do arquivo.'
              : 'settings.restoreBackupConfirmation'.tr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('common.ok'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile();
    } catch (_) {
      _showSnackbar(
        'settings.restoreBackupError'.tr(),
        isError: true,
        icon: TablerIcons.databaseExclamation,
      );
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    File? tempCopy;
    try {
      var path = picked.path;
      if (path == null) {
        final dir = await getTemporaryDirectory();
        tempCopy = File(p.join(dir.path, p.basename(picked.name)));
        await tempCopy.writeAsBytes(await picked.readAsBytes(), flush: true);
        path = tempCopy.path;
      }
      final report = await _service.restoreBackup(
        path,
        allowOtherApps: otherApp,
      );
      debugPrint('Backup restaurado: $report');
      widget.onDataRestored?.call();
      _showSnackbar(
        otherApp
            ? 'Carreiras importadas com sucesso.'
            : 'settings.restoreBackupSuccess'.tr(),
        icon: TablerIcons.databaseExport,
      );
    } on OtherAppBackupException {
      _showSnackbar(
        'Este backup é de outro app. Use Importar de outros apps.',
        isError: true,
        icon: TablerIcons.databaseExclamation,
      );
    } catch (error) {
      debugPrint('Falha ao restaurar backup: $error');
      _showSnackbar(
        'settings.restoreBackupError'.tr(),
        isError: true,
        icon: TablerIcons.databaseExclamation,
      );
    } finally {
      if (tempCopy != null && tempCopy.existsSync()) tempCopy.deleteSync();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('settings.tools'.tr(), style: const TextStyle(fontSize: 18)),
      bottom: _busy
          ? const PreferredSize(
              preferredSize: Size.fromHeight(2),
              child: LinearProgressIndicator(minHeight: 2),
            )
          : null,
    ),
    body: SafeArea(
      child: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          physics: const ClampingScrollPhysics(),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: CareerPageHeader(
                title: 'Sua história guardada',
                subtitle: 'Exporte e importe suas carreiras em ZIP, com os dados e as imagens que escolher.',
                icon: Icons.space_dashboard_outlined,
                eyebrow: 'Controlador',
              ),
            ),
            settingsListTile(
              context,
              title: 'settings.shareBackup'.tr(),
              leadingIcon: TablerIcons.databaseExport,
              onTap: _shareBackup,
            ),
            settingsListTile(
              context,
              title: 'settings.restoreBackup'.tr(),
              leadingIcon: TablerIcons.databasePlus,
              onTap: _restoreBackup,
            ),
            settingsListTile(
              context,
              title: 'Importar de outros apps',
              subtitle: 'Traga suas carreiras de backups de outros apps.',
              leadingIcon: TablerIcons.fileImport,
              onTap: _importFromOtherApp,
            ),
          ],
        ),
      ),
    ),
  );
}
