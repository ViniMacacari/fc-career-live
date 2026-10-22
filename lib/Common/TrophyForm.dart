import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/Person.dart';
import '../utils/Components/CareerPageWidgets.dart';
import '../models/Season.dart';
import '../models/Trophy.dart';
import '../utils/CareerDatePicker.dart';
import '../utils/GameCatalog.dart';
import '../utils/SqlService.dart';
import 'Seasons/CreateSeason.dart';
import 'SelectNationalityPage.dart';
import 'SelectTeam/SelectTeamPage.dart';
import '../Trophies/SelectTrophy.dart';

class TrophyForm extends StatefulWidget {
  const TrophyForm({super.key, required this.person, this.existing});
  final Person person;
  final Map<String, Object?>? existing;
  @override
  State<TrophyForm> createState() => _TrophyFormState();
}

class _TrophyFormState extends State<TrophyForm> {
  final _form = GlobalKey<FormState>();
  final _count = TextEditingController(text: '1');
  final _description = TextEditingController();
  late Future<List<Season>> _seasons = SqlService.instance.getSeasons(
    widget.person.id,
  );
  String? _seasonId;
  DateTime? _date;
  AwardCatalogItem? _award;
  CatalogItem? _team;
  bool _isNational = false, _saving = false;

  @override
  void initState() {
    super.initState();
    final row = widget.existing;
    if (row == null) return;
    _seasonId = row['seasonId'] as String?;
    _date = DateTime.tryParse(row['date'] as String? ?? '');
    _award = AwardCatalogItem(
      row['awardId'] as String,
      row['awardId'] as String,
    );
    _team = CatalogItem(
      row['teamId'] as String,
      row['teamId'] as String,
      leagueId: row['leagueId'] as String?,
    );
    _isNational = row['isNational'] == 1;
    _count.text = row['count'].toString();
    _description.text = row['description'] as String? ?? '';
  }

  @override
  void dispose() {
    _count.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickAward() async {
    final selected = await Navigator.of(context).push<AwardCatalogItem>(
      MaterialPageRoute(builder: (_) => const SelectTrophy()),
    );
    if (selected != null) setState(() => _award = selected);
  }

  Future<void> _pickTeam() async {
    final selected = await Navigator.of(context).push<CatalogItem>(
      MaterialPageRoute(
        builder: (_) => _isNational
            ? SelectNationalityPage(
                title: 'nationalities.selectNationalTeam'.tr(),
              )
            : SelectTeamPage(fifaVersion: widget.person.fifaVersion),
      ),
    );
    if (selected != null) setState(() => _team = selected);
  }

  Future<void> _pickDate() async {
    final selected = await showCareerDatePicker(
      context: context,
      personId: widget.person.id,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _date ?? DateTime.now(),
    );
    if (mounted && selected != null) setState(() => _date = selected);
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
    if (_award == null || _team == null || seasons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione troféu, equipe e temporada.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final trophy = Trophy(
        id: widget.existing?['id'] as String? ?? const Uuid().v4(),
        date: _date,
        teamId: _team!.id,
        leagueId: _isNational ? null : _team!.leagueId,
        isNational: _isNational,
        awardId: _award!.id,
        count: int.parse(_count.text),
        seasonId: _seasonId ?? seasons.first.id,
        personId: widget.person.id,
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        fixtureId: widget.existing?['fixtureId'] as String?,
      );
      await SqlService.instance.saveTrophy(
        trophy,
        update: widget.existing != null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar troféu: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.existing == null
            ? 'trophies.addTrophy'.tr()
            : 'trophies.trophy'.tr(),
      ),
    ),
    body: FutureBuilder<List<Season>>(
      future: _seasons,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final seasons = snapshot.data!;
        if (seasons.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Crie uma temporada antes de adicionar troféus.'),
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
              const CareerPageHeader(
                title: 'Registre sua conquista',
                subtitle:
                    'Guarde o clube, a temporada e os detalhes deste momento.',
                icon: Icons.emoji_events_outlined,
                eyebrow: 'Sala de troféus',
              ),
              OutlinedButton(
                onPressed: _pickAward,
                child: Text(_award?.label ?? 'trophies.selectTrophy'.tr()),
              ),
              const SizedBox(height: 16),
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
                onChanged: (value) => setState(() => _seasonId = value),
              ),
              SwitchListTile(
                title: const Text('Troféu de seleção nacional'),
                value: _isNational,
                onChanged: (value) => setState(() {
                  _isNational = value;
                  _team = null;
                }),
              ),
              OutlinedButton(
                onPressed: _pickTeam,
                child: Text(_team?.label ?? 'teams.selectTeam'.tr()),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('trophies.dateOpt'.tr()),
                subtitle: Text(
                  _date == null
                      ? 'Selecionar'
                      : '${_date!.day}/${_date!.month}/${_date!.year}',
                ),
                trailing: const Icon(Icons.calendar_month),
                onTap: _pickDate,
              ),
              TextFormField(
                controller: _count,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantidade'),
                validator: (value) {
                  final count = int.tryParse(value ?? '');
                  return count == null || count < 1
                      ? 'Informe uma quantidade válida'
                      : null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'trophies.descriptionOpt'.tr(),
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
  );
}
