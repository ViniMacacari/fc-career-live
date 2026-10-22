import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../utils/GameCatalog.dart';
import '../../utils/themes.dart';
import '../../utils/Components/CareerPageWidgets.dart';
import '../../utils/Components/CareerUiStyle.dart';
import '../../utils/databaseUtils.dart';

List<String> availableFifaVersions() => List.of(GameCatalog.fifaVersions);

ThemeData customConfigurationTheme([BuildContext? context]) =>
    context == null ? managerDarkTheme : careerDetailTheme(context);

class CustomConfigurationTheme extends StatelessWidget {
  const CustomConfigurationTheme({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Theme(data: customConfigurationTheme(context), child: child);
}

class CustomSearchField extends StatelessWidget {
  const CustomSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
  });
  final String hint;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: TextField(
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),

        isDense: true,
      ),
      onChanged: onChanged,
    ),
  );
}

class CustomEmptyState extends StatelessWidget {
  const CustomEmptyState({super.key, this.textKey});
  final String? textKey;
  @override
  Widget build(BuildContext context) => CareerEmptyState(
    title: (textKey ?? 'customConfiguration.noCreatedItemsYet').tr(),
    subtitle: 'Use o botão de adicionar para criar seu primeiro item.',
    icon: Icons.auto_awesome_outlined,
  );
}

class CustomHint extends StatelessWidget {
  const CustomHint(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: color ?? Theme.of(context).hintColor),
    ),
  );
}

class WomanLeagueIcon extends StatelessWidget {
  const WomanLeagueIcon({super.key, required this.visible});
  final bool visible;
  @override
  Widget build(BuildContext context) => Visibility(
    visible: visible,
    child: const Padding(
      padding: EdgeInsets.only(left: 6),
      child: Icon(Icons.female, size: 18, color: Colors.pinkAccent),
    ),
  );
}

class VersionRadioList extends StatelessWidget {
  const VersionRadioList({
    super.key,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });
  final String? selected;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final version in availableFifaVersions())
        ChoiceChip(
          label: Text(version),
          selected: selected == version,
          onSelected: enabled ? (_) => onSelected(version) : null,
        ),
    ],
  );
}

class VersionMultiSelect extends StatelessWidget {
  const VersionMultiSelect({
    super.key,
    required this.selected,
    required this.onChanged,
    this.requiredVersions = const {},
    this.enabled = true,
  });
  final Set<String> selected, requiredVersions;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final version in availableFifaVersions())
            FilterChip(
              key: ValueKey('available-version-$version'),
              label: Text(version),
              selected: selected.contains(version),
              onSelected: !enabled
                  ? null
                  : (value) {
                      if (!value && requiredVersions.contains(version)) return;
                      onChanged({...selected}..toggleVersion(version, value));
                    },
            ),
        ],
      ),
      const SizedBox(height: 10),
      if (enabled)
        TextButton.icon(
          onPressed: () => onChanged(availableFifaVersions().toSet()),
          icon: const Icon(Icons.done_all_rounded, size: 18),
          label: const Text('Selecionar todos'),
        ),
    ],
  );
}

extension on Set<String> {
  void toggleVersion(String version, bool selected) {
    if (selected) {
      add(version);
    } else {
      remove(version);
    }
  }
}

class CustomStepControls extends StatelessWidget {
  const CustomStepControls({
    super.key,
    required this.isLastStep,
    required this.canContinue,
    required this.onCancel,
    required this.onContinue,
    this.saving = false,
    this.hasPrevious = false,
  });
  final bool isLastStep, canContinue, saving;
  final bool hasPrevious;
  final VoidCallback onCancel, onContinue;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Row(
      children: [
        Flexible(
          fit: FlexFit.tight,
          child: OutlinedButton(
            onPressed: saving ? null : onCancel,
            child: Text(hasPrevious ? 'Voltar' : 'common.cancel'.tr()),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          fit: FlexFit.tight,
          child: FilledButton(
            onPressed: canContinue && !saving ? onContinue : null,
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    (isLastStep ? 'common.save' : 'customConfiguration.next')
                        .tr(),
                  ),
          ),
        ),
      ],
    ),
  );
}

class CustomFormStepper extends StatelessWidget {
  const CustomFormStepper({
    super.key,
    required this.steps,
    required this.currentStep,
    required this.isStepValid,
    required this.onStepChanged,
    required this.onSave,
    this.saving = false,
  });
  final List<(String, Widget)> steps;
  final int currentStep;
  final bool Function(int step) isStepValid;
  final ValueChanged<int> onStepChanged;
  final VoidCallback onSave;
  final bool saving;

  bool _canReach(int step) {
    for (var index = 0; index < step; index++) {
      if (!isStepValid(index)) return false;
    }
    return true;
  }

  (String, IconData) _tab(int index) {
    final title = steps[index].$1;
    if (title == 'customConfiguration.availability'.tr()) {
      return ('FIFAs', Icons.videogame_asset_outlined);
    }
    if (title == 'teams.league'.tr()) {
      return ('Liga', Icons.emoji_events_outlined);
    }
    if (title == 'customConfiguration.leagues'.tr()) {
      return ('Ligas', Icons.emoji_events_outlined);
    }
    if (title == 'teams.selectTeam'.tr()) {
      return ('Clube', Icons.shield_outlined);
    }
    return ('Dados', Icons.badge_outlined);
  }

  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    void change(int step) {
      FocusScope.of(context).unfocus();
      onStepChanged(step);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: c.surface(radius: 18),
            child: Row(
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: Semantics(
                      key: ValueKey('custom-form-step-$i'),
                      selected: i == currentStep,
                      button: true,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          color: i == currentStep
                              ? c.accent.withValues(alpha: .15)
                              : Colors.transparent,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(13),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: saving || (i > currentStep && !_canReach(i))
                                ? null
                                : () => change(i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 12,
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    i < currentStep
                                        ? Icons.check_rounded
                                        : _tab(i).$2,
                                    size: 20,
                                    color: i == currentStep
                                        ? c.accent
                                        : c.muted,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _tab(i).$1,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: i == currentStep
                                          ? c.accent
                                          : c.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: ListView(
              key: ValueKey(currentStep),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: c.surface(radius: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        steps[currentStep].$1,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: c.text,
                        ),
                      ),
                      const SizedBox(height: 20),
                      AbsorbPointer(
                        absorbing: saving,
                        child: steps[currentStep].$2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: CustomStepControls(
            isLastStep: currentStep == steps.length - 1,
            canContinue: isStepValid(currentStep),
            saving: saving,
            hasPrevious: currentStep > 0,
            onCancel: () => currentStep == 0
                ? Navigator.of(context).maybePop()
                : change(currentStep - 1),
            onContinue: () => currentStep == steps.length - 1
                ? onSave()
                : change(currentStep + 1),
          ),
        ),
      ],
    );
  }
}

class LogoInputs extends StatelessWidget {
  const LogoInputs({
    super.key,
    required this.urlController,
    required this.imagePath,
    required this.onImageChanged,
    this.onUrlChanged,
  });
  final TextEditingController urlController;
  final String? imagePath;
  final ValueChanged<String?> onImageChanged;
  final ValueChanged<String>? onUrlChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CustomHint('customConfiguration.urlLogoHint'.tr()),
      TextField(
        controller: urlController,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(labelText: 'teams.logoUrlOpt'.tr()),
        onChanged: onUrlChanged,
      ),
      const SizedBox(height: 8),
      CustomHint('customConfiguration.realLogoHint'.tr()),
      Center(
        child: CustomImagePicker(path: imagePath, onChanged: onImageChanged),
      ),
    ],
  );
}

class CustomImagePicker extends StatelessWidget {
  const CustomImagePicker({
    super.key,
    required this.path,
    required this.onChanged,
    this.size = 140,
  });

  final String? path;
  final ValueChanged<String?> onChanged;
  final double size;

  Future<void> _pick() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file != null) onChanged(file.path);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final absolute = CustomImageFiles.absolute(path);
    final exists = absolute != null && File(absolute).existsSync();
    return GestureDetector(
      onTap: _pick,
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outline, width: 1.5),
        ),
        child: path == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    color: scheme.outline,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'memories.selectImage'.tr(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: exists
                        ? Image.file(File(absolute), fit: BoxFit.contain)
                        : Center(
                            child: Text(
                              'customConfiguration.imageError'.tr(),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close),
                      onPressed: () => onChanged(null),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

String? optionalText(TextEditingController controller) {
  final value = controller.text.trim();
  return value.isEmpty ? null : value;
}

Future<void> showCustomWarning(
  BuildContext context, {
  required String message,
  List<String> details = const [],
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('customConfiguration.warning'.tr()),
    content: SizedBox(
      width: double.maxFinite,
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(message),
          for (final detail in details)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('• $detail'),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('common.ok'.tr()),
      ),
    ],
  ),
);

Future<void> showUsageWarning(
  BuildContext context, {
  required String hintKey,
  required List<UsageError> errors,
}) => showCustomWarning(
  context,
  message: hintKey.tr(),
  details: [
    for (final error in errors) error.key.tr(args: ['${error.count}']),
  ],
);

Future<bool> confirmCustomRemoval(
  BuildContext context, {
  required String titleKey,
  required String messageKey,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titleKey.tr()),
        content: Text(messageKey.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'common.remove'.tr(),
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    ) ??
    false;

void showCustomError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
}

class CustomListCard extends StatelessWidget {
  const CustomListCard({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: onTap, child: child),
  );
}
