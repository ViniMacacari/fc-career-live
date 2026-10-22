import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../models/Person.dart';
import '../../Twitter/TwitterGenerationService.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/SqlService.dart';

class AcademyPlayerInfoPage extends StatefulWidget {
  const AcademyPlayerInfoPage({super.key, required this.person, this.existing});
  final Person person;
  final Map<String, Object?>? existing;

  @override
  State<AcademyPlayerInfoPage> createState() => _AcademyPlayerInfoPageState();
}

class _AcademyPlayerInfoPageState extends State<AcademyPlayerInfoPage> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.existing?['name']?.toString(),
  );
  late final _overall = TextEditingController(
    text: widget.existing?['overall']?.toString(),
  );
  late final _potentialStart = TextEditingController(
    text: widget.existing?['potentialStart']?.toString(),
  );
  late final _potentialEnd = TextEditingController(
    text: widget.existing?['potentialEnd']?.toString(),
  );
  late final _height = TextEditingController(
    text: widget.existing?['height']?.toString(),
  );
  late final _weight = TextEditingController(
    text: widget.existing?['weight']?.toString(),
  );
  late String? _positionId = widget.existing?['positionId'] as String?;
  late String? _nationalityId = widget.existing?['nationalityId'] as String?;
  late String _foot = widget.existing?['foot'] as String? ?? 'Right';
  late DateTime? _birthdate = widget.existing?['birthdate'] is int
      ? DateTime.fromMillisecondsSinceEpoch(
          widget.existing!['birthdate'] as int,
        )
      : null;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _overall,
      _potentialStart,
      _potentialEnd,
      _height,
      _weight,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (int.parse(_potentialEnd.text) < int.parse(_potentialStart.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Potencial final deve ser igual ou maior que o inicial.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await SqlService.instance.saveAcademyPlayer({
        'id': widget.existing?['id'] ?? const Uuid().v4(),
        'personId': widget.person.id,
        'name': _name.text.trim(),
        'positionId': _positionId,
        'overall': int.parse(_overall.text),
        'potentialStart': int.parse(_potentialStart.text),
        'potentialEnd': int.parse(_potentialEnd.text),
        'birthdate': _birthdate?.millisecondsSinceEpoch,
        'height': int.tryParse(_height.text),
        'weight': int.tryParse(_weight.text),
        'nationalityId': _nationalityId,
        'teamId': widget.existing?['teamId'] ?? widget.person.teamId,
        'isHistorical': widget.existing?['isHistorical'] ?? 0,
        'leagueId': widget.existing?['leagueId'] ?? widget.person.leagueId,
        'customAvatarFilePath': widget.existing?['customAvatarFilePath'],
        'foot': _foot,
      }, update: widget.existing != null);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar jogador: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('academy.releaseAcademyConfirmation'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('academy.release'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SqlService.instance.deleteAcademyPlayer(
      widget.person.id,
      widget.existing!['id'] as String,
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _promote() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('academy.promoteToTheTeam'.tr()),
        content: Text('academy.promotePlayerConfirmation'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('academy.promote'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final transferId = await SqlService.instance.promoteAcademyPlayer(
        widget.person,
        widget.existing!,
      );
      await TwitterGenerationService.instance.onTransferSaved(
        widget.person,
        transferId,
      );
      if (mounted) Navigator.pop(context, true);
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _pickBirthdate() async {
    final value = await showDatePicker(
      context: context,
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      initialDate: _birthdate ?? DateTime(2005),
    );
    if (value != null) setState(() => _birthdate = value);
  }

  Widget _number(
    String label,
    TextEditingController controller, {
    bool required = false,
  }) => TextFormField(
    controller: controller,
    decoration: InputDecoration(labelText: label),
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    validator: (value) =>
        required && (value == null || value.isEmpty) ? 'Informe $label' : null,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.existing == null
            ? 'Novo jogador da academia'
            : 'academy.academyPlayer'.tr(),
      ),
      actions: [
        if (widget.existing != null) ...[
          IconButton(
            onPressed: _promote,
            tooltip: 'academy.promoteToTheTeam'.tr(),
            icon: const Icon(Icons.upgrade),
          ),
          IconButton(
            onPressed: _delete,
            tooltip: 'academy.releasePlayer'.tr(),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ],
    ),
    body: FutureBuilder<GameCatalog>(
      future: GameCatalog.load(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final catalog = snapshot.data!;
        return Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: 'common.name'.tr()),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe o nome'
                    : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _positionId,
                decoration: InputDecoration(
                  labelText: 'positions.position'.tr(),
                ),
                items: catalog.positions
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(item.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _positionId = value),
                validator: (value) =>
                    value == null ? 'Escolha uma posição' : null,
              ),
              _number('players.overall'.tr(), _overall, required: true),
              _number(
                'academy.startPotential'.tr(),
                _potentialStart,
                required: true,
              ),
              _number(
                'academy.finalPotential'.tr(),
                _potentialEnd,
                required: true,
              ),
              _number('players.heightOpt'.tr(), _height),
              _number('players.weightOpt'.tr(), _weight),
              DropdownButtonFormField<String>(
                initialValue: _nationalityId,
                decoration: InputDecoration(
                  labelText: 'players.nationalityOpt'.tr(),
                ),
                isExpanded: true,
                items: catalog.nationalities
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(item.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _nationalityId = value),
              ),
              DropdownButtonFormField<String>(
                initialValue: _foot,
                decoration: InputDecoration(labelText: 'players.foot'.tr()),
                items: [
                  DropdownMenuItem(
                    value: 'Right',
                    child: Text('players.right'.tr()),
                  ),
                  DropdownMenuItem(
                    value: 'Left',
                    child: Text('players.left'.tr()),
                  ),
                ],
                onChanged: (value) => setState(() => _foot = value ?? 'Right'),
              ),
              ListTile(
                title: Text('players.birthday'.tr()),
                subtitle: Text(
                  _birthdate == null
                      ? 'Opcional'
                      : '${_birthdate!.day}/${_birthdate!.month}/${_birthdate!.year}',
                ),
                onTap: _pickBirthdate,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Salvando...' : 'common.save'.tr()),
              ),
            ],
          ),
        );
      },
    ),
  );
}
