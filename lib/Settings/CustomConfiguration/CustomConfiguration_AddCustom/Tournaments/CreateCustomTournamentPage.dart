import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../Common/SelectTeam/SelectLeague.dart';
import '../../../../models/Tournament.dart';
import '../../../../utils/Components/TeamLogo.dart';
import '../../../../utils/GameCatalog.dart';
import '../../../../utils/databaseUtils.dart';
import '../../CustomConfigurationComponents.dart';
import '../../CompetitionTrophyEditor.dart';

class CreateCustomTournamentPage extends StatelessWidget {
  const CreateCustomTournamentPage({super.key, this.fifaVersion});
  final String? fifaVersion;
  @override
  Widget build(BuildContext context) =>
      CustomTournamentForm(fifaVersion: fifaVersion);
}

class CustomTournamentForm extends StatefulWidget {
  const CustomTournamentForm({
    super.key,
    this.tournament,
    this.imagePath,
    this.fifaVersion,
  });
  final Tournament? tournament;
  final String? imagePath;
  final String? fifaVersion;
  @override
  State<CustomTournamentForm> createState() => _CustomTournamentFormState();
}

class _CustomTournamentFormState extends State<CustomTournamentForm> {
  late final _name = TextEditingController(text: widget.tournament?.name);
  late final _abbreviation = TextEditingController(
    text: widget.tournament?.abbreviation,
  );
  late final _url = TextEditingController(text: widget.tournament?.imageName);
  late String? _image = widget.imagePath;
  late String _category = widget.tournament?.category ?? 'club';
  late String? _version =
      widget.tournament?.fifaVersions?.split(',').first ?? widget.fifaVersion;

  late String _format = (widget.tournament?.format ?? '').split(':').first;
  late final _rounds = TextEditingController(
    text: () {
      final parts = (widget.tournament?.format ?? '').split(':');
      return parts.length > 1 ? parts[1] : '';
    }(),
  );
  late List<String> _leagueIds = [
    for (final id in (widget.tournament?.leagueId ?? '').split(','))
      if (id.isNotEmpty) id,
  ];
  late final _trophy = CompetitionTrophyDraft(
    competitionId: widget.tournament?.id,
    version: _version,
  );
  int _step = 0;
  bool _saving = false;

  bool get _editing => widget.tournament != null;
  bool get _versionLocked => _editing || widget.fifaVersion != null;

  @override
  void dispose() {
    _trophy.dispose();
    _name.dispose();
    _abbreviation.dispose();
    _url.dispose();
    _rounds.dispose();
    super.dispose();
  }

  bool _isStepValid(int step) => switch (step) {
    0 => _name.text.trim().isNotEmpty && _abbreviation.text.trim().isNotEmpty,
    1 => _version != null,
    2 => true,
    _ => false,
  };

  void _onSelectVersion(String version) => setState(() {
    if (version == _version) return;
    _version = version;
    _leagueIds = [];
  });

  Future<void> _selectLeagues() async {
    final version = _version;
    if (version == null) return;
    final leagues = await SelectLeaguePage.pickMany(
      context,
      fifaVersion: version,
      initialSelection: _leagueIds,
    );
    if (leagues == null || !mounted) return;
    setState(() => _leagueIds = leagues.map((league) => league.id).toList());
  }

  Future<void> _save() async {
    if (![0, 1, 2].every(_isStepValid)) return;
    setState(() => _saving = true);
    try {
      final previous = widget.tournament;
      final id = previous?.id ?? const Uuid().v1();
      final leagues = _category == 'national' || _leagueIds.isEmpty
          ? null
          : _leagueIds.join(',');
      final tournament = Tournament(
        id: id,
        name: _name.text.trim(),
        abbreviation: _abbreviation.text.trim(),
        type: 'custom',
        category: _category,
        fifaVersions: previous?.fifaVersions ?? _version,
        sex: previous?.sex ?? 'any',
        imageName: optionalText(_url),
        leagueId: leagues,
        format: switch (_format) {
          'league' || 'groups' when int.tryParse(_rounds.text.trim()) != null =>
            '$_format:${int.parse(_rounds.text.trim())}',
          '' => null,
          final format => format,
        },
      );
      if (previous == null) {
        final imagePath = _image == null
            ? null
            : await CustomImageFiles.store(
                _image!,
                CustomImageFiles.tournaments,
                id,
              );
        await CustomContentService.createCustomTournament(
          tournament,
          imagePath,
          trophy: await _trophy.prepare(id, _version!, _name.text.trim()),
        );
        if (mounted) Navigator.pop(context, tournament);
      } else {
        final imagePath = await CustomImageFiles.resolveForSave(
          previous: widget.imagePath,
          selected: _image,
          folder: CustomImageFiles.tournaments,
          id: id,
        );
        await CustomContentService.updateCustomTournament(
          tournament,
          imagePath,
          trophy: await _trophy.prepare(id, _version!, _name.text.trim()),
        );
        if (mounted) Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) showCustomError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final tournament = widget.tournament!;
    final usage = await CustomContentService.isCustomTournamentInUse(
      tournament.id,
    );
    if (!mounted) return;
    if (usage.isNotEmpty) {
      await showUsageWarning(
        context,
        hintKey: 'customConfiguration.tournamentErrors.resolveErrorsHint',
        errors: usage,
      );
      return;
    }
    final confirmed = await confirmCustomRemoval(
      context,
      titleKey: 'customConfiguration.removeTournament',
      messageKey: 'customConfiguration.removeTournamentConfirmation',
    );
    if (!confirmed || !mounted) return;
    try {
      await CustomContentService.removeCustomTournament(tournament.id);
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
                  ? 'customConfiguration.editTournament'
                  : 'customConfiguration.createTournament')
              .tr(),
        ),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'customConfiguration.removeTournament'.tr(),
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
            ('customConfiguration.tournamentInfo'.tr(), _infoStep()),
            (
              'customConfiguration.availability'.tr(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CustomHint(
                    (_editing
                            ? 'customConfiguration.youCantChangeTournamentAvailability'
                            : 'customConfiguration.availabilityCouldNotBeChangedHint')
                        .tr(),
                  ),
                  VersionRadioList(
                    selected: _version,
                    enabled: !_versionLocked,
                    onSelected: _onSelectVersion,
                  ),
                ],
              ),
            ),
            ('customConfiguration.leagues'.tr(), _leaguesStep()),
          ],
        ),
      ),
    ),
  );

  Widget _infoStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 4),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: 'common.name'.tr()),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _abbreviation,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: 'customConfiguration.abbreviation'.tr(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      Text(
        'customConfiguration.tournamentCategory'.tr(),
        style: Theme.of(context).textTheme.labelMedium,
      ),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(
            value: 'club',
            label: Text('customConfiguration.clubCategory'.tr()),
          ),
          ButtonSegment(
            value: 'national',
            label: Text('customConfiguration.nationalCategory'.tr()),
          ),
        ],
        selected: {_category},
        onSelectionChanged: (selection) =>
            setState(() => _category = selection.first),
      ),
      const SizedBox(height: 16),
      Text('Formato', style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final (value, label) in const [
            ('league', 'Pontos corridos'),
            ('knockout', 'Mata-mata'),
            ('groups', 'Grupos + mata-mata'),
            ('single', 'Jogo único'),
            ('friendly', 'Amistoso'),
            ('', 'Livre'),
          ])
            ChoiceChip(
              label: Text(label),
              selected: _format == value,
              onSelected: (_) => setState(() => _format = value),
            ),
        ],
      ),
      if (_format == 'league' || _format == 'groups') ...[
        const SizedBox(height: 12),
        TextField(
          controller: _rounds,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: _format == 'league'
                ? 'Rodadas (opcional)'
                : 'Rodadas da fase de grupos',
          ),
        ),
      ],
      const SizedBox(height: 6),
      Text(
        _format.isEmpty
            ? 'O estágio de cada partida é texto livre e o resultado do torneio é preenchido à mão.'
            : 'As partidas escolhem o estágio deste formato e o resultado do torneio sai sozinho.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      LogoInputs(
        urlController: _url,
        imagePath: _image,
        onImageChanged: (path) => setState(() => _image = path),
      ),
      CompetitionTrophyEditor(draft: _trophy),
    ],
  );

  Widget _leaguesStep() {
    if (_category == 'national') {
      return CustomHint(
        'customConfiguration.noLeaguesRequiredForNationalTournamentHint'.tr(),
      );
    }
    final catalog = GameCatalog.current;
    final version = _version;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomHint('customConfiguration.tournamentAvailableInLeaguesHint'.tr()),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            _leagueIds.isEmpty
                ? 'customConfiguration.allLeagues'.tr()
                : 'customConfiguration.leaguesCount'.tr(
                    args: ['${_leagueIds.length}'],
                  ),
          ),
          trailing: IconButton(
            tooltip: 'customConfiguration.leagues'.tr(),
            icon: const Icon(Icons.playlist_add),
            onPressed: version == null ? null : _selectLeagues,
          ),
        ),
        for (final id in _leagueIds)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 3),
            child: ListTile(
              dense: true,
              leading: TeamLogo.fromItem(
                version == null ? null : catalog?.league(version, id),
                size: 26,
              ),
              title: Text(
                version == null ? id : catalog?.leagueLabel(version, id) ?? id,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _leagueIds.remove(id)),
              ),
            ),
          ),
      ],
    );
  }
}
