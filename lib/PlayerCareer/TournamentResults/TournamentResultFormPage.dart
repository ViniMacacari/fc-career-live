import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../Common/SelectTournamentPage.dart';
import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../models/TournamentResult.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/SqlService.dart';
import '../../utils/competitions/TournamentAutomation.dart';

class TournamentResultFormPage extends StatefulWidget {
  const TournamentResultFormPage({
    super.key,
    required this.person,
    required this.season,
    this.existing,
    this.initialTournamentId,
    this.initialResult,
  });
  final Person person;
  final Season season;
  final TournamentResult? existing;

  final String? initialTournamentId, initialResult;

  @override
  State<TournamentResultFormPage> createState() =>
      _TournamentResultFormPageState();
}

class _TournamentResultFormPageState extends State<TournamentResultFormPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _result = TextEditingController(
    text: widget.existing?.result ?? widget.initialResult,
  );
  CatalogItem? _tournament;
  late bool _participated = widget.existing?.youParticipatedIn ?? true;
  late bool _winner = widget.existing?.isWinner ?? false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _resolveExistingTournament();
  }

  Future<void> _resolveExistingTournament() async {
    final id = widget.existing?.tournamentId ?? widget.initialTournamentId;
    if (id == null) return;
    final catalog = await GameCatalog.load();
    final builtIn = await catalog.tournaments(widget.person.fifaVersion);
    final custom = await SqlService.instance.getCustomTournaments(
      widget.person.fifaVersion,
    );
    final label =
        builtIn.where((item) => item.id == id).firstOrNull?.label ??
        custom.where((item) => item.id == id).firstOrNull?.name ??
        (id.startsWith('league:')
            ? catalog.leagueLabel(widget.person.fifaVersion, id.substring(7))
            : id);
    if (mounted) setState(() => _tournament = CatalogItem(id, label));
  }

  Future<void> _pickTournament() async {
    final selected = await Navigator.push<CatalogItem>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SelectTournamentPage(fifaVersion: widget.person.fifaVersion),
      ),
    );
    if (selected != null && mounted) setState(() => _tournament = selected);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_tournament == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('tournaments.selectTournament'.tr())),
      );
      return;
    }
    setState(() => _saving = true);
    final previous = widget.existing;
    final automatic =
        previous != null && TournamentAutomation.isAuto(previous.id);
    try {
      await SqlService.instance.saveTournamentResult(
        TournamentResult(
          id: previous == null || automatic ? const Uuid().v1() : previous.id,
          seasonId: widget.season.id,
          fifaVersion: widget.person.fifaVersion,
          tournamentId: _tournament!.id,
          result: _result.text.trim(),
          personId: widget.person.id,
          youParticipatedIn: _participated,
          isWinner: _participated && _winner,
          playerOfTheTournamentId: previous?.playerOfTheTournamentId,
          playerOfTheTournamentTeamId: previous?.playerOfTheTournamentTeamId,
          playerOfTheTournamentLeagueId:
              previous?.playerOfTheTournamentLeagueId,
        ),
      );
      if (automatic) {
        await SqlService.instance.deleteTournamentResult(
          widget.person.id,
          previous.id,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  void dispose() {
    _result.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.existing == null
            ? 'tournaments.createNewResult'.tr()
            : 'tournaments.editResult'.tr(),
      ),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _tournament?.label ?? 'tournaments.selectTournament'.tr(),
            ),
            subtitle: _tournament == null
                ? null
                : Text('tournaments.tournament'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickTournament,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _result,
            decoration: InputDecoration(labelText: 'tournaments.result'.tr()),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'common.invalidFieldsError'.tr()
                : null,
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('tournaments.isInTournamentQuestion'.tr()),
            value: _participated,
            onChanged: (value) => setState(() {
              _participated = value;
              if (!value) _winner = false;
            }),
          ),
          if (_participated)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('tournaments.isWinnerQuestion'.tr()),
              value: _winner,
              onChanged: (value) => setState(() => _winner = value),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save),
            label: Text('common.save'.tr()),
          ),
        ],
      ),
    ),
  );
}
