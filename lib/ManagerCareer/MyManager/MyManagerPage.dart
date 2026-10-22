import '../../utils/AppColors.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../RootPage/DrawerWidget.dart';
import '../../Twitter/TwitterStore.dart';
import '../../models/ManagerProfile.dart';
import '../../models/Person.dart';
import '../../utils/SqlService.dart';
import '../../utils/Components/ManagerFormStyle.dart';

class MyManagerPage extends StatefulWidget {
  const MyManagerPage({super.key, required this.person});
  final Person person;

  @override
  State<MyManagerPage> createState() => _MyManagerPageState();
}

class _MyManagerPageState extends State<MyManagerPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _nationality = TextEditingController();
  final _birthdate = TextEditingController();
  final _style = TextEditingController();
  final _biography = TextEditingController();
  bool _loading = true, _saving = false;
  String? _error;
  DateTime _careerDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await SqlService.instance.getManagerProfile(
        widget.person.id,
      );
      final careerDate = await SqlService.instance.getLatestFixtureDate(
        widget.person.id,
      );
      if (!mounted) return;
      _name.text = profile.name;
      _nationality.text = profile.nationality;
      _birthdate.text = profile.birthdate;
      _style.text = profile.style;
      _biography.text = profile.biography;
      _careerDate = careerDate ?? DateTime.now();
      setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar seus dados.';
          _loading = false;
        });
      }
    }
  }

  DateTime? get _birthday {
    try {
      return DateFormat('dd/MM/yyyy').parseStrict(_birthdate.text);
    } catch (_) {
      return null;
    }
  }

  String? get _ageLabel {
    final birth = _birthday;
    if (birth == null || birth.isAfter(_careerDate)) return null;
    final age =
        _careerDate.year -
        birth.year -
        ((_careerDate.month < birth.month ||
                (_careerDate.month == birth.month &&
                    _careerDate.day < birth.day))
            ? 1
            : 0);
    return '$age anos em ${DateFormat('dd/MM/yyyy').format(_careerDate)}';
  }

  Future<void> _pickBirthday() async {
    FocusScope.of(context).unfocus();
    final chosen = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(1985, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200, 12, 31),
      helpText: 'Nascimento do técnico',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (chosen != null && mounted) {
      setState(() => _birthdate.text = DateFormat('dd/MM/yyyy').format(chosen));
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await SqlService.instance.saveManagerProfile(
        widget.person.id,
        ManagerProfile(
          name: _name.text,
          nationality: _nationality.text,
          birthdate: _birthdate.text,
          style: _style.text,
          biography: _biography.text,
        ),
      );
      TwitterStore.instance.changed();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dados do técnico salvos.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível salvar. Tente novamente.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _nationality,
      _birthdate,
      _style,
      _biography,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _section(String title, String subtitle, List<Widget> fields) =>
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant
                .withValues(alpha: .35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).hintColor,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < fields.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              fields[i],
            ],
          ],
        ),
      );

  Widget _header() => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.of(context).headerStart,
          AppColors.of(context).panel,
        ],
      ),
      border: Border.all(color: AppColors.of(context).line),
    ),
    child: Row(
      children: [
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            color: AppColors.of(context).accent.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(
            Icons.person_outline_rounded,
            size: 38,
            color: AppColors.of(context).accent,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SUA IDENTIDADE',
                style: TextStyle(
                  color: AppColors.of(context).accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.7,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'À frente do time',
                style: TextStyle(
                  color: AppColors.of(context).text,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Seu perfil nas notícias e nas coletivas.',
                style: TextStyle(
                  color: AppColors.of(context).muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: RootDrawerScope.leading(context),
      title: const Text('Meu técnico'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _load();
                  },
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          )
        : Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _header(),
                const SizedBox(height: 18),
                _section(
                  'Dados pessoais',
                  'Um perfil próprio para esta carreira.',
                  [
                    TextFormField(
                      controller: _name,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.words,
                      decoration: managerFieldDecoration(
                        context,
                        'Nome do técnico',
                        icon: Icons.badge_outlined,
                      ),
                      maxLength: 80,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Informe seu nome.'
                          : null,
                    ),
                    TextFormField(
                      controller: _nationality,
                      enabled: !_saving,
                      maxLength: 80,
                      decoration: managerFieldDecoration(
                        context,
                        'Nacionalidade',
                        icon: Icons.public_rounded,
                        hint: 'Ex.: Brasileiro',
                      ),
                    ),
                    TextFormField(
                      controller: _birthdate,
                      enabled: !_saving,
                      readOnly: true,
                      onTap: _saving ? null : _pickBirthday,
                      decoration: managerFieldDecoration(
                        context,
                        'Nascimento',
                        icon: Icons.cake_outlined,
                        hint: 'Escolher no calendário',
                        helper: _ageLabel,
                        suffix: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_birthdate.text.isNotEmpty)
                              IconButton(
                                tooltip: 'Limpar nascimento',
                                onPressed: _saving
                                    ? null
                                    : () => setState(() => _birthdate.clear()),
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            const Padding(
                              padding: EdgeInsets.only(right: 16),
                              child: Icon(
                                Icons.calendar_month_rounded,
                                size: 21,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _section(
                  'Sua filosofia',
                  'Conte como você pensa o futebol. Os campos abaixo são opcionais.',
                  [
                    TextFormField(
                      controller: _style,
                      enabled: !_saving,
                      maxLength: 200,
                      decoration: managerFieldDecoration(
                        context,
                        'Estilo de jogo',
                        icon: Icons.sports_soccer_rounded,
                        hint: 'Ex.: posse de bola e pressão alta',
                      ),
                    ),
                    TextFormField(
                      controller: _biography,
                      enabled: !_saving,
                      maxLength: 1000,
                      minLines: 3,
                      maxLines: 5,
                      decoration: managerFieldDecoration(
                        context,
                        'Sobre mim',
                        hint: 'Sua história, personalidade e objetivos…',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
    bottomNavigationBar: _loading || _error != null
        ? null
        : SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(_saving ? 'Salvando…' : 'Salvar perfil'),
                ),
              ),
            ),
          ),
  );
}
