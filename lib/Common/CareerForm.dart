import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/Person.dart';
import '../utils/Components/CareerPageWidgets.dart';
import '../utils/GameCatalog.dart';
import '../utils/SqlService.dart';

class CareerForm extends StatefulWidget {
  const CareerForm({
    super.key,
    required this.category,
    required this.onCreated,
  });
  final PersonCategory category;
  final ValueChanged<Person> onCreated;

  @override
  State<CareerForm> createState() => _CareerFormState();
}

class _CareerFormState extends State<CareerForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  late final Future<GameCatalog> _catalog = GameCatalog.load();
  String _version = 'FC26';
  CatalogItem? _team, _nationality, _position, _nationalTeam;
  DateTime? _birthdate;
  String? _foot;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_team == null ||
        _nationality == null ||
        (widget.category == PersonCategory.player && _position == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione clube, nacionalidade e posição.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final person = Person(
        id: const Uuid().v4(),
        name: _name.text.trim(),
        category: widget.category,
        fifaVersion: _version,
        teamId: _team!.id,
        leagueId: _team!.leagueId!,
        nationalityId: _nationality!.id,
        positionId: _position?.id,
        nationalCoachingTeamId: _nationalTeam?.id,
        createdAt: now,
        updatedAt: now,
        birthdate: _birthdate?.millisecondsSinceEpoch,
        foot: _foot,
        height: int.tryParse(_height.text),
        weight: int.tryParse(_weight.text),
      );
      await SqlService.instance.createPerson(person);
      if (mounted) widget.onCreated(person);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar carreira: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<GameCatalog>(
    future: _catalog,
    builder: (context, snapshot) {
      final isManager = widget.category == PersonCategory.manager;
      final title = isManager
          ? 'careers.startManagerCareer'.tr()
          : 'careers.startPlayerCareer'.tr();
      if (snapshot.hasError) {
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Center(
            child: Text('Erro ao carregar dados: ${snapshot.error}'),
          ),
        );
      }
      if (!snapshot.hasData) {
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      final catalog = snapshot.data!;
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              CareerPageHeader(
                title: 'O começo de uma história',
                subtitle: 'Escolha o clube e personalize os primeiros passos da carreira.',
                eyebrow: isManager ? 'Modo técnico' : 'Modo jogador',
                icon: isManager
                    ? Icons.manage_accounts_outlined
                    : Icons.sports_soccer_outlined,
              ),
              DropdownButtonFormField<String>(
                initialValue: _version,
                decoration: InputDecoration(
                  labelText: 'common.fifaVersion'.tr(),
                ),
                items: const ['FIFA23', 'FC24', 'FC25', 'FC26', 'FC27']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _version = v!;
                  _team = null;
                }),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: 'common.name'.tr()),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Informe o nome' : null,
              ),
              const SizedBox(height: 16),
              _CatalogPicker(
                label: 'common.nationality'.tr(),
                value: _nationality,
                items: catalog.nationalities,
                onChanged: (v) => setState(() => _nationality = v),
              ),
              const SizedBox(height: 16),
              _CatalogPicker(
                label: 'common.team'.tr(),
                value: _team,
                items: catalog.teams(_version),
                onChanged: (v) => setState(() => _team = v),
              ),
              if (isManager) ...[
                const SizedBox(height: 16),
                _CatalogPicker(
                  label: 'common.nationalTeamOpt'.tr(),
                  value: _nationalTeam,
                  items: catalog.nationalities,
                  onChanged: (v) => setState(() => _nationalTeam = v),
                ),
              ] else ...[
                const SizedBox(height: 16),
                _CatalogPicker(
                  label: 'positions.position'.tr(),
                  value: _position,
                  items: catalog.positions,
                  onChanged: (v) => setState(() => _position = v),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('players.birthday'.tr()),
                  subtitle: Text(
                    _birthdate == null
                        ? 'Selecionar'
                        : '${_birthdate!.day}/${_birthdate!.month}/${_birthdate!.year}',
                  ),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime(1940),
                      lastDate: DateTime.now(),
                      initialDate: _birthdate ?? DateTime(2000),
                    );
                    if (date != null) setState(() => _birthdate = date);
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: _foot,
                  decoration: InputDecoration(labelText: 'players.foot'.tr()),
                  items: const ['Right', 'Left']
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            v == 'Right'
                                ? 'players.right'.tr()
                                : 'players.left'.tr(),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _foot = v),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _height,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'players.heightOpt'.tr(),
                  ),
                  validator: (v) =>
                      v != null && v.isNotEmpty && int.tryParse(v) == null
                      ? 'Informe um número'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _weight,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'players.weightOpt'.tr(),
                  ),
                  validator: (v) =>
                      v != null && v.isNotEmpty && int.tryParse(v) == null
                      ? 'Informe um número'
                      : null,
                ),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving
                      ? 'common.inProgress'.tr()
                      : 'careers.startCareer'.tr(),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _CatalogPicker extends StatelessWidget {
  const _CatalogPicker({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final CatalogItem? value;
  final List<CatalogItem> items;
  final ValueChanged<CatalogItem> onChanged;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: () async {
      final selected = await showDialog<CatalogItem>(
        context: context,
        builder: (_) => _CatalogDialog(label: label, items: items),
      );
      if (selected != null) onChanged(selected);
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Text(
                  value?.label ?? 'Selecionar',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    ),
  );
}

class _CatalogDialog extends StatefulWidget {
  const _CatalogDialog({required this.label, required this.items});
  final String label;
  final List<CatalogItem> items;
  @override
  State<_CatalogDialog> createState() => _CatalogDialogState();
}

class _CatalogDialogState extends State<_CatalogDialog> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final filtered = widget.items
        .where((item) => item.label.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Dialog(
      child: SizedBox(
        width: 440,
        height: 540,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  labelText: widget.label,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) => ListTile(
                  title: Text(filtered[index].label),
                  onTap: () => Navigator.pop(context, filtered[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
