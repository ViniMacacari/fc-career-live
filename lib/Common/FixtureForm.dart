import '../utils/themes.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/ManagerFixture.dart';
import '../models/Person.dart';
import '../models/PlayerFixture.dart';
import '../models/Season.dart';
import '../utils/CareerDatePicker.dart';
import '../Twitter/TwitterGenerationService.dart';
import '../utils/GameCatalog.dart';
import '../utils/SqlService.dart';
import '../utils/competitions/CompetitionFormats.dart';
import '../utils/competitions/TournamentAutomation.dart';
import 'Seasons/CreateSeason.dart';
import 'SelectTeam/SelectTeamPage.dart';
import 'SelectTournamentPage.dart';
import 'StagePicker.dart';
import '../FcScore/FcScoreQuickImportPage.dart';

class FixtureForm extends StatefulWidget {
  const FixtureForm({super.key, required this.person, this.existing});
  final Person person;
  final Map<String, Object?>? existing;
  @override
  State<FixtureForm> createState() => _FixtureFormState();
}

class _FixtureFormState extends State<FixtureForm> {
  final _form = GlobalKey<FormState>();
  final _stage = TextEditingController();
  final _notes = TextEditingController();
  final Map<String, TextEditingController> _numbers = {
    'myScore': TextEditingController(text: '0'),
    'otherScore': TextEditingController(text: '0'),
    'goals': TextEditingController(text: '0'),
    'assists': TextEditingController(text: '0'),
    'saves': TextEditingController(text: '0'),
    'yellow': TextEditingController(text: '0'),
    'red': TextEditingController(text: '0'),
    'minutes': TextEditingController(),
    'rating': TextEditingController(),
    'shotsOnTarget': TextEditingController(),
    'goalsFromPenalty': TextEditingController(),
    'possession': TextEditingController(),
    'passAccuracy': TextEditingController(),
    'myShots': TextEditingController(),
    'otherShots': TextEditingController(),
    'myPenalties': TextEditingController(),
    'otherPenalties': TextEditingController(),
    'position': TextEditingController(),
  };
  late Future<List<Season>> _seasons = SqlService.instance.getSeasons(
    widget.person.id,
  );
  DateTime _date = DateTime.now();
  String? _seasonId;
  CatalogItem? _opponent, _tournament;
  GameLocation _location = GameLocation.home;
  bool _injured = false, _disqualified = false, _extraTime = false;
  bool _penalties = false;
  bool _saving = false;

  late final Future<CompetitionFormat Function(String)> _formats =
      TournamentAutomation.formats(widget.person);

  @override
  void initState() {
    super.initState();
    final row = widget.existing;
    if (row == null) return;
    _date = DateTime.tryParse(row['date'] as String? ?? '') ?? DateTime.now();
    _seasonId = row['seasonId'] as String?;
    _opponent = CatalogItem(
      row['oppositeTeamId'] as String,
      row['oppositeTeamId'] as String,
      leagueId: row['oppositeTeamLeagueId'] as String?,
    );
    _tournament = CatalogItem(
      row['tournamentId'] as String,
      row['tournamentId'] as String,
    );
    _resolveExistingLabels();
    _location = GameLocation.values.byName(row['location'] as String);
    _injured = row['isInjured'] == 1;
    _disqualified = row['isDisqualified'] == 1;
    _extraTime = row['extraTime'] == 1;
    _penalties =
        row['playerTeamPenaltiesScore'] != null ||
        row['oppositeTeamPenaltiesScore'] != null;
    _stage.text = row['stage'] as String? ?? '';
    _notes.text = row['notes'] as String? ?? '';
    for (final entry in <String, String>{
      'myScore': 'playerTeamScore',
      'otherScore': 'oppositeTeamScore',
      'goals': 'goalsCount',
      'assists': 'assistsCount',
      'saves': 'savesCount',
      'yellow': 'yellowCards',
      'red': 'redCards',
      'minutes': 'minsPlayed',
      'rating': 'rating',
      'shotsOnTarget': 'shotsOnTarget',
      'goalsFromPenalty': 'goalsFromPenalty',
      'possession': 'teamPossession',
      'passAccuracy': 'passAccuracy',
      'myShots': 'playerTeamShoutsCount',
      'otherShots': 'opponentTeamShotsCount',
      'myPenalties': 'playerTeamPenaltiesScore',
      'otherPenalties': 'oppositeTeamPenaltiesScore',
      'position': 'position',
    }.entries) {
      final value = row[entry.value];
      if (value != null) _numbers[entry.key]!.text = value.toString();
    }
  }

  Future<void> _resolveExistingLabels() async {
    final catalog = await GameCatalog.load();
    final opponentId = _opponent?.id;
    final tournamentId = _tournament?.id;
    if (tournamentId == null || !mounted) return;
    final builtIn = await catalog.tournaments(widget.person.fifaVersion);
    final custom = await SqlService.instance.getCustomTournaments(
      widget.person.fifaVersion,
    );
    final league = tournamentId.startsWith('league:')
        ? catalog
              .leagues(widget.person.fifaVersion)
              .where((item) => item.id == tournamentId.substring(7))
              .firstOrNull
        : null;
    final label =
        builtIn.where((item) => item.id == tournamentId).firstOrNull?.label ??
        custom.where((item) => item.id == tournamentId).firstOrNull?.name ??
        league?.label ??
        tournamentId;
    if (!mounted) return;
    setState(() {
      if (_opponent?.id == opponentId && opponentId != null) {
        _opponent = CatalogItem(
          opponentId,
          catalog.teamLabel(widget.person.fifaVersion, opponentId),
          leagueId: _opponent?.leagueId,
        );
      }
      if (_tournament?.id == tournamentId) {
        _tournament = CatalogItem(tournamentId, label);
      }
    });
  }

  @override
  void dispose() {
    _stage.dispose();
    _notes.dispose();
    for (final controller in _numbers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int? _optionalInt(String key) => int.tryParse(_numbers[key]!.text.trim());
  double? _optionalDouble(String key) =>
      double.tryParse(_numbers[key]!.text.trim().replaceAll(',', '.'));

  Widget _intField(String key, String label, {bool required = false}) =>
      TextFormField(
        controller: _numbers[key],
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          helperText: key == 'position'
              ? 'Em branco, mantém a posição do último jogo deste torneio.'
              : null,
          helperMaxLines: 2,
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return required ? 'common.invalidFieldsError'.tr() : null;
          }
          final number = int.tryParse(value);
          return number == null ||
                  number < 0 ||
                  (key == 'position' && number == 0)
              ? 'common.invalidFieldsError'.tr()
              : null;
        },
      );

  Widget _doubleField(String key, String label) => TextFormField(
    controller: _numbers[key],
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    validator: (value) =>
        value == null ||
            value.trim().isEmpty ||
            double.tryParse(value.replaceAll(',', '.')) != null
        ? null
        : 'common.invalidFieldsError'.tr(),
  );

  Future<void> _pickDate() async {
    final date = await showCareerDatePicker(
      context: context,
      personId: widget.person.id,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _date,
    );
    if (mounted && date != null) setState(() => _date = date);
  }

  Future<void> _pickStage() async {
    final tournament = _tournament;
    final format = tournament == null
        ? const CompetitionFormat.open()
        : (await _formats)(tournament.id);
    final suggested = tournament == null
        ? null
        : await suggestStage(
            widget.person,
            tournamentId: tournament.id,
            seasonId: _seasonId ?? (await _seasons).firstOrNull?.id,
            format: format,
            date: _date,
            excludeFixtureId: widget.existing?['id'] as String?,
          );
    if (!mounted) return;
    final stage = await showStagePicker(
      context,
      format: format,
      current: _stage.text.trim(),
      competition: tournament?.label ?? 'tournaments.selectTournament'.tr(),
      suggested: suggested,
    );
    if (stage != null && mounted) setState(() => _stage.text = stage);
  }

  Future<void> _pickOpponent() async {
    final selected = await Navigator.of(context).push<CatalogItem>(
      MaterialPageRoute(
        builder: (_) => SelectTeamPage(
          fifaVersion: widget.person.fifaVersion,
          selectedTeamId: _opponent?.id,
          selectedLeagueId: _opponent?.leagueId,
          initialLeagueId: _opponent?.leagueId ?? widget.person.leagueId,
        ),
      ),
    );
    if (selected != null) setState(() => _opponent = selected);
  }

  Future<void> _pickTournament() async {
    final selected = await Navigator.of(context).push<CatalogItem>(
      MaterialPageRoute(
        builder: (_) =>
            SelectTournamentPage(fifaVersion: widget.person.fifaVersion),
      ),
    );
    if (selected != null) setState(() => _tournament = selected);
  }

  Future<void> _createSeason() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateSeasonPage(personId: widget.person.id),
      ),
    );
    if (created == true) {
      setState(() {
        _seasons = SqlService.instance.getSeasons(widget.person.id);
        _seasonId = null;
      });
    }
  }

  Future<void> _save(List<Season> seasons) async {
    if (!_form.currentState!.validate()) return;
    if (_penalties &&
        (_optionalInt('myPenalties') == null ||
            _optionalInt('otherPenalties') == null)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('common.invalidFieldsError'.tr())));
      return;
    }
    if (_opponent == null || _tournament == null || seasons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione temporada, adversário e torneio.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final id = widget.existing?['id'] as String? ?? const Uuid().v4();
      final now = DateTime.now();
      final createdAt =
          DateTime.tryParse(widget.existing?['createdAt'] as String? ?? '') ??
          now;
      final person = widget.person;
      final seasonId = _seasonId ?? seasons.first.id;
      if (person.category == PersonCategory.player) {
        await SqlService.instance.createFixture(
          person.category,
          PlayerFixture(
            id: id,
            personId: person.id,
            date: _date,
            fifaVersion: person.fifaVersion,
            playerTeamScore: _optionalInt('myScore')!,
            oppositeTeamScore: _optionalInt('otherScore')!,
            goalsCount: _optionalInt('goals')!,
            assistsCount: _optionalInt('assists')!,
            savesCount: _optionalInt('saves')!,
            yellowCards: _optionalInt('yellow')!,
            redCards: _optionalInt('red')!,
            oppositeTeamId: _opponent!.id,
            oppositeTeamLeagueId: _opponent!.leagueId,
            playerTeamId: person.teamId,
            playerTeamLeagueId: person.leagueId,
            tournamentId: _tournament!.id,
            seasonId: seasonId,
            location: _location,
            createdAt: createdAt,
            updatedAt: now,
            rating: _optionalDouble('rating'),
            minsPlayed: _optionalInt('minutes'),
            shotsOnTarget: _optionalInt('shotsOnTarget'),
            goalsFromPenalty: _optionalInt('goalsFromPenalty'),
            isInjured: _injured,
            isDisqualified: _disqualified,
            playerTeamPenaltiesScore: _penalties
                ? _optionalInt('myPenalties')
                : null,
            oppositeTeamPenaltiesScore: _penalties
                ? _optionalInt('otherPenalties')
                : null,
            position: _optionalInt('position'),
            stage: _stage.text.trim().isEmpty ? null : _stage.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          ).toMap(),
          update: widget.existing != null,
        );
      } else {
        await SqlService.instance.createFixture(
          person.category,
          ManagerFixture(
            id: id,
            personId: person.id,
            date: _date,
            fifaVersion: person.fifaVersion,
            playerTeamScore: _optionalInt('myScore')!,
            oppositeTeamScore: _optionalInt('otherScore')!,
            oppositeTeamId: _opponent!.id,
            oppositeTeamLeagueId: _opponent!.leagueId,
            playerTeamId: person.teamId,
            playerTeamLeagueId: person.leagueId,
            tournamentId: _tournament!.id,
            seasonId: seasonId,
            location: _location,
            createdAt: createdAt,
            updatedAt: now,
            teamPossession: _optionalDouble('possession'),
            passAccuracy: _optionalDouble('passAccuracy'),
            playerTeamShotsCount: _optionalInt('myShots'),
            opponentTeamShotsCount: _optionalInt('otherShots'),
            extraTime: _extraTime,
            playerTeamPenaltiesScore: _penalties
                ? _optionalInt('myPenalties')
                : null,
            oppositeTeamPenaltiesScore: _penalties
                ? _optionalInt('otherPenalties')
                : null,
            position: _optionalInt('position'),
            stage: _stage.text.trim().isEmpty ? null : _stage.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          ).toMap(),
          update: widget.existing != null,
        );
      }
      await TournamentAutomation.trySync(person);
      await TwitterGenerationService.instance.onFixtureSaved(
        person,
        id,
        update: widget.existing != null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar partida: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: careerDetailTheme(context),
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null
              ? 'fixtures.addFixture'.tr()
              : 'fixtures.editFixture'.tr(),
        ),
      ),
      body: FutureBuilder<List<Season>>(
        future: _seasons,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final seasons = snapshot.data!;
          if (seasons.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('common.noSeasonsMessage'.tr()),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _createSeason,
                    child: Text('seasons.createSeason'.tr()),
                  ),
                ],
              ),
            );
          }
          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (widget.existing == null)
                  FcScoreImportShortcut(person: widget.person),
                DropdownButtonFormField<String>(
                  initialValue: _seasonId ?? seasons.first.id,
                  decoration: InputDecoration(labelText: 'seasons.season'.tr()),
                  items: seasons
                      .map(
                        (season) => DropdownMenuItem(
                          value: season.id,
                          child: Text(
                            '${season.startDate.year}/${season.endDate.year}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _seasonId = v),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('common.date'.tr()),
                  subtitle: Text('${_date.day}/${_date.month}/${_date.year}'),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: _pickDate,
                ),
                OutlinedButton(
                  onPressed: _pickTournament,
                  child: Text(
                    _tournament?.label ?? 'tournaments.selectTournament'.tr(),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _pickOpponent,
                  child: Text(_opponent?.label ?? 'teams.selectTeam'.tr()),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<GameLocation>(
                  initialValue: _location,
                  decoration: InputDecoration(
                    labelText: 'fixtures.location'.tr(),
                  ),
                  items: [
                    for (final location in GameLocation.values)
                      DropdownMenuItem(
                        value: location,
                        child: Text('fixtures.${location.name}'.tr()),
                      ),
                  ],
                  onChanged: (v) => setState(() => _location = v!),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _intField(
                        'myScore',
                        'fixtures.myTeam'.tr(),
                        required: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _intField(
                        'otherScore',
                        'fixtures.opponent'.tr(),
                        required: true,
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('fixtures.penaltyShootout'.tr()),
                  value: _penalties,
                  onChanged: (value) => setState(() => _penalties = value),
                ),
                if (_penalties)
                  Row(
                    children: [
                      Expanded(
                        child: _intField(
                          'myPenalties',
                          '${'fixtures.myTeam'.tr()} '
                              '(${'fixtures.penaltyMedium'.tr()})',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _intField(
                          'otherPenalties',
                          '${'fixtures.opponent'.tr()} '
                              '(${'fixtures.penaltyMedium'.tr()})',
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _stage.text.trim().isEmpty
                        ? 'fixtures.stageInfo'.tr()
                        : _stage.text.trim(),
                  ),
                  subtitle: _stage.text.trim().isEmpty
                      ? null
                      : Text('fixtures.stageInfo'.tr()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickStage,
                ),
                _intField('position', 'fixtures.position'.tr()),
                const SizedBox(height: 16),
                if (widget.person.category == PersonCategory.player) ...[
                  _intField('goals', 'fixtures.goals'.tr(), required: true),
                  _intField('assists', 'fixtures.assists'.tr(), required: true),
                  _intField('saves', 'fixtures.saves'.tr(), required: true),
                  _intField('minutes', 'fixtures.minutesPlayed'.tr()),
                  _doubleField('rating', 'fixtures.rating'.tr()),
                  _intField('shotsOnTarget', 'Chutes no alvo'),
                  _intField(
                    'goalsFromPenalty',
                    'stats.goalsFromPenalties'.tr(),
                  ),
                  _intField(
                    'yellow',
                    'fixtures.yellowCards'.tr(),
                    required: true,
                  ),
                  _intField('red', 'fixtures.redCards'.tr(), required: true),
                  SwitchListTile(
                    title: Text('fixtures.missedMatchDueToInjure'.tr()),
                    value: _injured,
                    onChanged: (v) => setState(() => _injured = v),
                  ),
                  SwitchListTile(
                    title: Text('fixtures.missedMatchDueToSentOff'.tr()),
                    value: _disqualified,
                    onChanged: (v) => setState(() => _disqualified = v),
                  ),
                ] else ...[
                  _doubleField('possession', 'fixtures.possession'.tr()),
                  _doubleField('passAccuracy', 'fixtures.passAccuracy'.tr()),
                  _intField('myShots', 'fixtures.myTeamShots'.tr()),
                  _intField('otherShots', 'fixtures.opponentShots'.tr()),
                  SwitchListTile(
                    title: Text('fixtures.extraTime'.tr()),
                    value: _extraTime,
                    onChanged: (v) => setState(() => _extraTime = v),
                  ),
                ],
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'fixtures.notesOpt'.tr(),
                    helperText: 'fixtures.notesAiHelper'.tr(),
                    helperMaxLines: 3,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : () => _save(seasons),
                  child: Text(
                    _saving ? 'common.inProgress'.tr() : 'common.save'.tr(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
