import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../models/CustomLeague.dart';
import '../../../../utils/GameCatalog.dart';
import '../../../../utils/databaseUtils.dart';
import '../../CustomConfigurationComponents.dart';
import '../../CompetitionTrophyEditor.dart';

class CreateCustomLeaguePage extends StatelessWidget {
  const CreateCustomLeaguePage({super.key});
  @override
  Widget build(BuildContext context) => const CustomLeagueForm();
}

class CustomLeagueForm extends StatefulWidget {
  const CustomLeagueForm({super.key, this.league});
  final CustomLeague? league;
  @override
  State<CustomLeagueForm> createState() => _CustomLeagueFormState();
}

class _CustomLeagueFormState extends State<CustomLeagueForm> {
  late final _name = TextEditingController(text: widget.league?.label);
  late final _url = TextEditingController(text: widget.league?.imageUrl);
  late String? _image = widget.league?.imagePath;
  late String? _version = widget.league?.fifaVersion;
  late final _trophy = CompetitionTrophyDraft(
    competitionId: widget.league == null ? null : 'league:${widget.league!.id}',
    version: widget.league?.fifaVersion,
  );
  int _step = 0;
  bool _saving = false;

  bool get _editing => widget.league != null;

  @override
  void dispose() {
    _trophy.dispose();
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  bool _isStepValid(int step) => switch (step) {
    0 => _name.text.trim().isNotEmpty,
    1 => _version != null,
    _ => false,
  };

  Future<void> _save() async {
    if (!_isStepValid(0) || !_isStepValid(1)) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final previous = widget.league;
      if (previous == null) {
        final id = const Uuid().v1();
        final imagePath = _image == null
            ? null
            : await CustomImageFiles.store(
                _image!,
                CustomImageFiles.leagues,
                id,
              );
        await CustomContentService.createCustomLeague(
          CustomLeague(
            id: id,
            label: _name.text.trim(),
            fifaVersion: _version!,
            isWoman: false,
            imageUrl: optionalText(_url),
            imagePath: imagePath,
            createdAt: now,
            updatedAt: now,
          ),
          trophy: await _trophy.prepare(
            'league:$id',
            _version!,
            _name.text.trim(),
          ),
        );
      } else {
        final imagePath = await CustomImageFiles.resolveForSave(
          previous: previous.imagePath,
          selected: _image,
          folder: CustomImageFiles.leagues,
          id: previous.id,
        );
        await CustomContentService.updateCustomLeague(
          CustomLeague(
            id: previous.id,
            label: _name.text.trim(),
            fifaVersion: previous.fifaVersion,
            isWoman: previous.isWoman,
            imageUrl: optionalText(_url),
            imagePath: imagePath,
            createdAt: previous.createdAt,
            updatedAt: now,
          ),
          trophy: await _trophy.prepare(
            'league:${previous.id}',
            previous.fifaVersion,
            _name.text.trim(),
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showCustomError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final league = widget.league!;
    final catalog = await GameCatalog.load();
    if (!mounted) return;
    final teams = catalog.customClubsOf(league.id).length;
    if (teams > 0) {
      await showCustomWarning(
        context,
        message: 'customConfiguration.leagueHasTeamsError'.tr(args: ['$teams']),
      );
      return;
    }
    final confirmed = await confirmCustomRemoval(
      context,
      titleKey: 'customConfiguration.removeLeague',
      messageKey: 'customConfiguration.removeLeagueConfirmation',
    );
    if (!confirmed || !mounted) return;
    try {
      await CustomContentService.removeCustomLeague(league.id);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showCustomError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => CustomConfigurationTheme(
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          (_editing
                  ? 'customConfiguration.editLeague'
                  : 'customConfiguration.createLeague')
              .tr(),
        ),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'customConfiguration.removeLeague'.tr(),
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: CustomFormStepper(
          currentStep: _step,
          saving: _saving,
          isStepValid: _isStepValid,
          onStepChanged: (step) => setState(() => _step = step),
          onSave: _save,
          steps: [
            (
              'customConfiguration.leagueInfo'.tr(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: 'common.name'.tr()),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  LogoInputs(
                    urlController: _url,
                    imagePath: _image,
                    onImageChanged: (path) => setState(() => _image = path),
                  ),
                  CompetitionTrophyEditor(draft: _trophy),
                ],
              ),
            ),
            (
              'customConfiguration.availability'.tr(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CustomHint(
                    (_editing
                            ? 'customConfiguration.youCantChangeLeagueAvailability'
                            : 'customConfiguration.availabilityCouldNotBeChangedHint')
                        .tr(),
                  ),
                  if (_editing && widget.league!.fifaVersions.length > 1)
                    VersionMultiSelect(
                      selected: widget.league!.fifaVersions.toSet(),
                      enabled: false,
                      onChanged: (_) {},
                    )
                  else
                    VersionRadioList(
                      selected: _version,
                      enabled: !_editing,
                      onSelected: (version) =>
                          setState(() => _version = version),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
