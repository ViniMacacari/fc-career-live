import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/ManagerCareerHistoryItem.dart';
import '../Twitter/TwitterGenerationService.dart';
import '../models/Person.dart';
import '../models/PlayerTransferItem.dart';
import '../utils/CareerDatePicker.dart';
import '../utils/GameCatalog.dart';
import '../utils/SqlService.dart';
import 'SelectNationalityPage.dart';
import 'SelectTeam/SelectTeamPage.dart';

Map<String, String> get playerHistoryLabels => <String, String>{
  'startCareer': 'Início da carreira',
  'startExistingPlayerCareer': 'Início de carreira existente',
  'transwer': 'teams.transfer'.tr(),
  'inloan': 'teams.inLoan'.tr(),
  'outloan': 'teams.outLoan'.tr(),
  'contractChange': 'history.contractChange'.tr(),
  'retired': 'history.retireFromFootball'.tr(),
};
Map<String, String> get managerHistoryLabels => <String, String>{
  'startCareer': 'Início da carreira',
  'changeTeam': 'history.changeTeam'.tr(),
  'contractChange': 'history.contractChange'.tr(),
  'startNationalTeam': 'history.joinNationalTeam'.tr(),
  'endNationalTeam': 'history.leaveNationalTeam'.tr(),
  'retired': 'history.retireFromFootball'.tr(),
};

class CareerHistoryForm extends StatefulWidget {
  const CareerHistoryForm({super.key, required this.person, this.existing});
  final Person person;
  final Map<String, Object?>? existing;
  @override
  State<CareerHistoryForm> createState() => _CareerHistoryFormState();
}

class _CareerHistoryFormState extends State<CareerHistoryForm> {
  final _form = GlobalKey<FormState>();
  final _weeklyWage = TextEditingController();
  final _yearlyWage = TextEditingController();
  final _overall = TextEditingController();
  final _transferValue = TextEditingController();
  final _taxRate = TextEditingController();
  late String _type = widget.existing?['type'] as String? ?? 'startCareer';
  late DateTime _date =
      DateTime.tryParse(
        (widget.existing?['transferDate'] ?? widget.existing?['date'])
                as String? ??
            '',
      ) ??
      DateTime.now();
  CatalogItem? _fromTeam, _toTeam, _nationalTeam;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final row = widget.existing;
    if (row == null) return;
    if (row['fromTeamId'] != null) {
      _fromTeam = CatalogItem(
        row['fromTeamId'] as String,
        row['fromTeamId'] as String,
        leagueId: row['fromLeagueId'] as String?,
      );
    }
    if (row['toTeamId'] != null) {
      _toTeam = CatalogItem(
        row['toTeamId'] as String,
        row['toTeamId'] as String,
        leagueId: row['toLeagueId'] as String?,
      );
    }
    if (row['nationalTeamId'] != null) {
      _nationalTeam = CatalogItem(
        row['nationalTeamId'] as String,
        row['nationalTeamId'] as String,
      );
    }
    for (final entry in <TextEditingController, String>{
      _weeklyWage: 'weeklyWage',
      _yearlyWage: 'yearlyWage',
      _overall: 'overall',
      _transferValue: 'transferValue',
      _taxRate: 'taxRate',
    }.entries) {
      if (row[entry.value] != null) {
        entry.key.text = row[entry.value].toString();
      }
    }
  }

  @override
  void dispose() {
    _weeklyWage.dispose();
    _yearlyWage.dispose();
    _overall.dispose();
    _transferValue.dispose();
    _taxRate.dispose();
    super.dispose();
  }

  Future<void> _pickTeam(bool from) async {
    final selected = await Navigator.of(context).push<CatalogItem>(
      MaterialPageRoute(
        builder: (_) => SelectTeamPage(fifaVersion: widget.person.fifaVersion),
      ),
    );
    if (selected != null) {
      setState(() {
        if (from) {
          _fromTeam = selected;
        } else {
          _toTeam = selected;
        }
      });
    }
  }

  Future<void> _pickNationalTeam() async {
    final selected = await Navigator.of(context).push<CatalogItem>(
      MaterialPageRoute(
        builder: (_) => SelectNationalityPage(
          title: 'nationalities.selectNationalTeam'.tr(),
        ),
      ),
    );
    if (selected != null) setState(() => _nationalTeam = selected);
  }

  Future<void> _pickDate() async {
    final selected = await showCareerDatePicker(
      context: context,
      personId: widget.person.id,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _date,
    );
    if (mounted && selected != null) setState(() => _date = selected);
  }

  Widget _number(
    TextEditingController controller,
    String label, {
    bool decimal = false,
  }) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    validator: (text) {
      if (text == null || text.trim().isEmpty) return null;
      final valid = decimal
          ? double.tryParse(text.replaceAll(',', '.')) != null
          : int.tryParse(text) != null;
      return valid ? null : 'Informe um número válido';
    },
  );

  int? _int(TextEditingController controller) =>
      int.tryParse(controller.text.trim());
  double? _double(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final person = widget.person;
      final id = widget.existing?['id'] as String? ?? const Uuid().v4();
      final Map<String, Object?> row;
      if (person.category == PersonCategory.player) {
        row = PlayerTransferItem(
          id: id,
          transferDate: _date,
          personId: person.id,
          fifaVersion: person.fifaVersion,
          type: TransferType.values.byName(_type),
          fromTeamId: _fromTeam?.id,
          fromLeagueId: _fromTeam?.leagueId,
          toTeamId: _toTeam?.id,
          toLeagueId: _toTeam?.leagueId,
          weeklyWage: _int(_weeklyWage),
          yearlyWage: _int(_yearlyWage),
          overall: _int(_overall),
          transferValue: _int(_transferValue),
          taxRate: _double(_taxRate),
          rules: widget.existing?['rules'] as String?,
        ).toMap();
      } else {
        row = ManagerCareerHistoryItem(
          id: id,
          date: _date,
          personId: person.id,
          fifaVersion: person.fifaVersion,
          type: ManagerHistoryItemType.values.byName(_type),
          fromTeamId: _fromTeam?.id,
          fromLeagueId: _fromTeam?.leagueId,
          toTeamId: _toTeam?.id,
          toLeagueId: _toTeam?.leagueId,
          nationalTeamId: _nationalTeam?.id,
          weeklyWage: _int(_weeklyWage),
          yearlyWage: _int(_yearlyWage),
          taxRate: _double(_taxRate),
          rules: widget.existing?['rules'] as String?,
        ).toMap();
      }
      await SqlService.instance.saveCareerHistory(
        person.category,
        row,
        update: widget.existing != null,
      );
      if (person.category == PersonCategory.player) {
        await TwitterGenerationService.instance.onTransferSaved(person, id);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar histórico: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPlayer = widget.person.category == PersonCategory.player;
    final labels = isPlayer ? playerHistoryLabels : managerHistoryLabels;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null
              ? 'history.createHistoryItem'.tr()
              : 'history.updateHistoryItem'.tr(),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: InputDecoration(
                labelText: 'history.selectItemType'.tr(),
              ),
              items: labels.entries
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.key,
                      child: Text(item.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _type = value!),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('common.date'.tr()),
              subtitle: Text('${_date.day}/${_date.month}/${_date.year}'),
              trailing: const Icon(Icons.calendar_month),
              onTap: _pickDate,
            ),
            OutlinedButton(
              onPressed: () => _pickTeam(true),
              child: Text(
                _fromTeam?.label ??
                    (isPlayer
                        ? 'teams.transferredFrom'.tr()
                        : 'history.previousTeam'.tr()),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _pickTeam(false),
              child: Text(
                _toTeam?.label ??
                    (isPlayer
                        ? 'teams.transferredTo'.tr()
                        : 'history.newTeam'.tr()),
              ),
            ),
            if (!isPlayer) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _pickNationalTeam,
                child: Text(
                  _nationalTeam?.label ?? 'history.nationalTeam'.tr(),
                ),
              ),
            ],
            _number(_weeklyWage, 'common.weeklyWageOpt'.tr()),
            _number(_yearlyWage, 'common.annualWageOpt'.tr()),
            if (isPlayer) ...[
              _number(_overall, 'history.overallOpt'.tr()),
              _number(_transferValue, 'teams.transferValueOpt'.tr()),
            ],
            _number(_taxRate, 'wallet.taxRate'.tr(), decimal: true),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(
                _saving ? 'common.inProgress'.tr() : 'common.save'.tr(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
