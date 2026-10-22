import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../Common/SelectTeam/SelectLeague.dart';
import '../../../../models/CustomClub.dart';
import '../../../../utils/Components/TeamLogo.dart';
import '../../../../utils/GameCatalog.dart';
import '../../../../utils/databaseUtils.dart';
import '../../CustomConfigurationComponents.dart';

class CreateCustomTeamPage extends StatelessWidget {
  const CreateCustomTeamPage({super.key});
  @override
  Widget build(BuildContext context) => const CustomTeamForm();
}

class CustomTeamForm extends StatefulWidget {
  const CustomTeamForm({super.key, this.club});
  final CustomClub? club;
  @override
  State<CustomTeamForm> createState() => _CustomTeamFormState();
}

class _CustomTeamFormState extends State<CustomTeamForm> {
  late final _name = TextEditingController(text: widget.club?.label);
  late final _url = TextEditingController(text: widget.club?.imageUrl);
  final _leagueLabel = TextEditingController();
  late String? _image = widget.club?.imagePath;
  late String? _version = widget.club?.fifaVersions.firstOrNull;
  late Set<String> _versions = widget.club?.fifaVersions.toSet() ?? {};
  late String? _leagueId = widget.club?.leagueId;
  List<UsageError> _usage = const [];
  int _step = 0;
  bool _saving = false;

  bool get _editing => widget.club != null;
  bool get _leagueLocked => _editing && _usage.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final club = widget.club;
    if (club == null) return;
    GameCatalog.load().then((catalog) {
      if (mounted) {
        _leagueLabel.text = catalog.leagueLabel(
          club.fifaVersions.first,
          club.leagueId,
        );
      }
    });
    CustomContentService.isCustomTeamInUse(club.id).then((usage) {
      if (mounted) setState(() => _usage = usage);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _leagueLabel.dispose();
    super.dispose();
  }

  bool _isStepValid(int step) => switch (step) {
    0 => _name.text.trim().isNotEmpty,
    1 => _version != null && _versions.isNotEmpty,
    2 => _leagueId != null,
    _ => false,
  };

  void _onSelectVersion(String version) => setState(() {
    if (version == _version) return;
    _version = version;
    _leagueId = null;
    _leagueLabel.text = '';
  });

  void _onVersionsChanged(Set<String> versions) => setState(() {
    _versions = versions;
    if (!_versions.contains(_version)) {
      _version = versions.firstOrNull;
      if (!_editing) {
        _leagueId = null;
        _leagueLabel.clear();
      }
    }
  });

  Future<void> _selectLeague() async {
    final version = _version;
    if (version == null || _leagueLocked) return;
    FocusScope.of(context).unfocus();
    final league = await SelectLeaguePage.pickOne(
      context,
      fifaVersion: version,
    );
    if (league == null || !mounted) return;
    setState(() {
      _leagueId = league.id;
      _leagueLabel.text = league.label;
    });
  }

  Future<void> _save() async {
    if (![0, 1, 2].every(_isStepValid)) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final previous = widget.club;
      if (previous == null) {
        final id = const Uuid().v1();
        final imagePath = _image == null
            ? null
            : await CustomImageFiles.store(_image!, CustomImageFiles.teams, id);
        await CustomContentService.saveSharedCustomClub(
          CustomClub(
            id: id,
            label: _name.text.trim(),
            leagueId: _leagueId!,
            fifaVersion: _versions.join(','),
            personId: '',
            imageUrl: optionalText(_url),
            imagePath: imagePath,
            createdAt: now,
            updatedAt: now,
          ),
          _version!,
        );
      } else {
        final imagePath = await CustomImageFiles.resolveForSave(
          previous: previous.imagePath,
          selected: _image,
          folder: CustomImageFiles.teams,
          id: previous.id,
        );
        await CustomContentService.saveSharedCustomClub(
          CustomClub(
            id: previous.id,
            label: _name.text.trim(),
            leagueId: _leagueLocked ? previous.leagueId : _leagueId!,
            fifaVersion: _versions.join(','),
            personId: '',
            imageUrl: optionalText(_url),
            imagePath: imagePath,
            createdAt: previous.createdAt,
            updatedAt: now,
          ),
          _version!,
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
    final club = widget.club!;
    final usage = await CustomContentService.isCustomTeamInUse(club.id);
    if (!mounted) return;
    if (usage.isNotEmpty) {
      setState(() => _usage = usage);
      await _showUsage();
      return;
    }
    final confirmed = await confirmCustomRemoval(
      context,
      titleKey: 'customConfiguration.removeTeam',
      messageKey: 'customConfiguration.removeTeamConfirmation',
    );
    if (!confirmed || !mounted) return;
    try {
      await CustomContentService.removeCustomTeam(club.id);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showCustomError(context, error);
    }
  }

  Future<void> _showUsage() => showUsageWarning(
    context,
    hintKey: 'customConfiguration.teamErrors.resolveErrorsHint',
    errors: _usage,
  );

  @override
  Widget build(BuildContext context) => CustomConfigurationTheme(
    child: Scaffold(
      appBar: AppBar(
        title: Text((_editing ? 'teams.editTeam' : 'teams.createTeam').tr()),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'customConfiguration.removeTeam'.tr(),
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
            (
              'customConfiguration.availability'.tr(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CustomHint(
                    _editing
                        ? 'Adicione outras versões. As versões já cadastradas serão mantidas.'
                        : 'Selecione um ou mais FIFAs para usar este time em todas as carreiras dessas versões.',
                  ),
                  VersionMultiSelect(
                    selected: _versions,
                    requiredVersions: widget.club?.fifaVersions.toSet() ?? {},
                    onChanged: _onVersionsChanged,
                  ),
                  if (_versions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      key: ValueKey('source-version-$_version'),
                      initialValue: _version,
                      decoration: const InputDecoration(
                        labelText: 'Versão de origem da competição',
                      ),
                      items: [
                        for (final version in _versions)
                          DropdownMenuItem(
                            value: version,
                            child: Text(version),
                          ),
                      ],
                      onChanged: _editing
                          ? null
                          : (version) {
                              if (version != null) _onSelectVersion(version);
                            },
                    ),
                  ],
                ],
              ),
            ),
            ('teams.league'.tr(), _leagueStep()),
          ],
        ),
      ),
    ),
  );

  Widget _leagueStep() {
    final catalog = GameCatalog.current;
    final league = _leagueId == null || _version == null
        ? null
        : catalog?.league(_version!, _leagueId!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_leagueLocked)
          Row(
            children: [
              Expanded(
                child: CustomHint(
                  'customConfiguration.youCantChangeTeamLeagueInUse'.tr(),
                  color: Colors.orangeAccent,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: _showUsage,
              ),
            ],
          )
        else
          CustomHint(
            'customConfiguration.youCantChangeTeamLeagueInUseHint'.tr(),
          ),
        const SizedBox(height: 4),
        TextField(
          controller: _leagueLabel,
          readOnly: true,
          enabled: !_leagueLocked && _version != null,
          onTap: _selectLeague,
          decoration: InputDecoration(
            labelText: 'teams.league'.tr(),

            prefixIcon: league == null
                ? null
                : Padding(
                    padding: const EdgeInsets.all(8),
                    child: TeamLogo.fromItem(league, size: 24),
                  ),
            suffixIcon: const Icon(Icons.chevron_right),
          ),
        ),
        if (league != null) ...[
          const SizedBox(height: 20),
          for (final version in _versions)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    catalog!
                            .getAllLeagues(version)
                            .any((l) => l.id == _leagueId)
                        ? Icons.check_circle_outline_rounded
                        : Icons.download_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      catalog
                              .getAllLeagues(version)
                              .any((l) => l.id == _leagueId)
                          ? '$version · Competição disponível'
                          : '$version · Será criada com ${catalog.getAllLeagues(_version!).where((l) => l.id == _leagueId).firstOrNull?.teams.length ?? 0} times da origem.',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
