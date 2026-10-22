import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../Common/SelectTeam/SelectTeamPage.dart';
import '../../../models/ClubCustomizationModel.dart';
import '../../../utils/Components/TeamLogo.dart';
import '../../../utils/GameCatalog.dart';
import '../../../utils/databaseUtils.dart';
import '../CustomConfigurationComponents.dart';

class ClubCustomizationFormPage extends StatefulWidget {
  const ClubCustomizationFormPage({
    super.key,
    this.customization,
    this.initialFifaVersion,
  });
  final ClubCustomizationModel? customization;
  final String? initialFifaVersion;
  @override
  State<ClubCustomizationFormPage> createState() =>
      _ClubCustomizationFormPageState();
}

class _ClubCustomizationFormPageState extends State<ClubCustomizationFormPage> {
  late final _name = TextEditingController(
    text: widget.customization?.clubName,
  );
  late final _url = TextEditingController(text: widget.customization?.imageUrl);
  final _teamLabel = TextEditingController();
  late String? _image = widget.customization?.imagePath;
  late String? _version =
      widget.customization?.fifaVersion ?? widget.initialFifaVersion;
  CatalogItem? _team;
  int _step = 0;
  bool _saving = false;

  bool get _editing => widget.customization != null;

  @override
  void initState() {
    super.initState();
    final customization = widget.customization;
    if (customization == null) return;
    _team = CatalogItem(
      customization.originalTeamId,
      customization.originalTeamId,
      leagueId: customization.originalLeagueId,
    );
    GameCatalog.load().then((catalog) {
      if (!mounted) return;
      final team = catalog.team(
        customization.fifaVersion,
        customization.originalTeamId,
        leagueId: customization.originalLeagueId,
        ignoreCustomizations: true,
      );
      setState(() {
        if (team != null) _team = team;
        _teamLabel.text = _team!.label;
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _teamLabel.dispose();
    super.dispose();
  }

  bool get _alreadyExists {
    final team = _team;
    final version = _version;
    if (team == null || version == null) return false;
    final existing = GameCatalog.current?.customization(
      version,
      team.leagueId,
      team.id,
    );
    return existing != null && existing.id != widget.customization?.id;
  }

  bool _isStepValid(int step) => switch (step) {
    0 => _version != null,
    1 => _team != null && !_alreadyExists,
    2 => _name.text.trim().isNotEmpty,
    _ => false,
  };

  void _onSelectVersion(String version) => setState(() {
    if (version == _version) return;
    _version = version;
    _team = null;
    _teamLabel.text = '';
    _name.text = '';
    _url.text = '';
    _image = null;
  });

  Future<void> _selectTeam() async {
    final version = _version;
    if (version == null || _editing) return;
    FocusScope.of(context).unfocus();
    final team = await Navigator.of(context).push<CatalogItem>(
      MaterialPageRoute(
        builder: (_) =>
            SelectTeamPage(fifaVersion: version, realTeamsOnly: true),
      ),
    );
    if (team == null || !mounted) return;
    setState(() {
      _team = team;
      _teamLabel.text = team.label;
      _name.text = team.label;
      _url.text = '';
      _image = null;
    });
  }

  Future<void> _save() async {
    if (![0, 1, 2].every(_isStepValid)) return;
    setState(() => _saving = true);
    try {
      final team = _team!;
      final version = _version!;
      final now = DateTime.now();
      final previous = widget.customization;
      final id =
          previous?.id ??
          ClubCustomizationModel.buildId(version, team.leagueId, team.id);
      final imagePath = previous == null
          ? (_image == null
                ? null
                : await CustomImageFiles.store(
                    _image!,
                    CustomImageFiles.teamCustomizations,
                    id,
                  ))
          : await CustomImageFiles.resolveForSave(
              previous: previous.imagePath,
              selected: _image,
              folder: CustomImageFiles.teamCustomizations,
              id: id,
            );
      final model = ClubCustomizationModel(
        id: id,
        clubName: _name.text.trim(),
        originalTeamId: previous?.originalTeamId ?? team.id,
        originalLeagueId: previous == null
            ? team.leagueId
            : previous.originalLeagueId,
        imageUrl: optionalText(_url),
        imagePath: imagePath,
        fifaVersion: previous?.fifaVersion ?? version,
        createdAt: previous?.createdAt ?? now,
        updatedAt: now,
      );
      if (previous == null) {
        await CustomContentService.createClubCustomization(model);
      } else {
        await CustomContentService.updateClubCustomization(model);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showCustomError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await confirmCustomRemoval(
      context,
      titleKey: 'customConfiguration.removeCustomization',
      messageKey: 'customConfiguration.removeCustomizationConfirmation',
    );
    if (!confirmed || !mounted) return;
    try {
      await CustomContentService.removeClubCustomization(
        widget.customization!.id,
      );
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
          'customConfiguration.clubCustomization'.tr(),
          maxLines: 2,
          style: const TextStyle(fontSize: 18, height: 1.15),
        ),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'customConfiguration.removeCustomization'.tr(),
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
              'customConfiguration.availability'.tr(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CustomHint(
                    'customConfiguration.availabilityCouldNotBeChangedHint'
                        .tr(),
                  ),
                  VersionRadioList(
                    selected: _version,
                    enabled: !_editing,
                    onSelected: _onSelectVersion,
                  ),
                ],
              ),
            ),
            ('teams.selectTeam'.tr(), _teamStep()),
            (
              'customConfiguration.teamInfo'.tr(),
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
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _teamStep() {
    final team = _team;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        TextField(
          controller: _teamLabel,
          readOnly: true,
          enabled: !_editing && _version != null,
          onTap: _selectTeam,
          decoration: InputDecoration(
            labelText: 'teams.team'.tr(),

            prefixIcon: team == null
                ? null
                : Padding(
                    padding: const EdgeInsets.all(8),
                    child: TeamLogo.fromItem(team, size: 24),
                  ),
            suffixIcon: const Icon(Icons.chevron_right),
          ),
        ),
        if (_alreadyExists)
          CustomHint(
            'customConfiguration.customizationAlreadyExists'.tr(),
            color: Colors.redAccent,
          ),
      ],
    );
  }
}
