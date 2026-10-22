import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/Season.dart';
import '../../models/Person.dart';
import '../../utils/Components/CareerPageWidgets.dart';
import '../../utils/CareerDatePicker.dart';
import '../../utils/SqlService.dart';
import '../../utils/SeasonClosureService.dart';
import 'SeasonClosingPage.dart';
import 'SeasonArchivePage.dart';

class CreateSeasonPage extends StatefulWidget {
  const CreateSeasonPage({
    super.key,
    required this.personId,
    this.person,
    this.seasonLoader,
    this.onCreate,
    this.service,
  });
  final String personId;
  final Person? person;
  final Future<List<Season>> Function()? seasonLoader;
  final Future<void> Function(Season)? onCreate;
  final SeasonClosureService? service;
  @override
  State<CreateSeasonPage> createState() => _CreateSeasonPageState();
}

class _CreateSeasonPageState extends State<CreateSeasonPage> {
  DateTime? _start, _end;
  bool _saving = false;
  bool _loading = true, _skipClosure = false;
  List<Season> _seasons = [];
  Person? _person;
  String? _loadError;
  Season? get _current => _seasons.firstOrNull;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final seasons = [
        ...await (widget.seasonLoader?.call() ??
            SqlService.instance.getSeasons(widget.personId)),
      ]..sort((a, b) => b.startDate.compareTo(a.startDate));
      final person =
          widget.person ??
          (await SqlService.instance.getPersons())
              .where((p) => p.id == widget.personId)
              .firstOrNull;
      if (!mounted) return;
      setState(() {
        _seasons = seasons;
        _person = person;
        _loading = false;
        _loadError = null;
        if (_start == null && seasons.isNotEmpty) {
          _start = DateTime(
            seasons.first.endDate.year,
            seasons.first.endDate.month,
            seasons.first.endDate.day + 1,
          );
          _end = DateTime(_start!.year + 1, _start!.month, _start!.day - 1);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = 'Não foi possível carregar as temporadas. $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _closeCurrent() async {
    if (_person == null || _current == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SeasonClosingPage(
          person: _person!,
          season: _current!,
          service: widget.service,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _archive() async {
    if (_person == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SeasonArchivePage(person: _person!, service: widget.service),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _pick(bool isStart) async {
    final date = await showCareerDatePicker(
      context: context,
      personId: widget.personId,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: isStart
          ? (_start ?? DateTime.now())
          : (_end ?? DateTime.now().add(const Duration(days: 365))),
    );
    if (mounted && date != null) {
      setState(() {
        if (isStart) {
          _start = date;
        } else {
          _end = date;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_loading || _loadError != null) return;
    if (_current != null && !_current!.isClosed && !_skipClosure) {
      await _closeCurrent();
      return;
    }
    if (_start == null || _end == null || !_end!.isAfter(_start!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escolha datas de início e término válidas.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await (widget.onCreate ?? SqlService.instance.createSeason)(
        Season(
          id: const Uuid().v4(),
          personId: widget.personId,
          startDate: _start!,
          endDate: _end!,
          createdAt: DateTime.now(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar temporada: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _date(DateTime? value) => value == null
      ? 'Selecionar'
      : '${value.day}/${value.month}/${value.year}';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('seasons.createSeason'.tr())),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const CareerPageHeader(
          title: 'Um novo capítulo',
          subtitle: 'Defina o período da temporada para organizar jogos, resultados e estatísticas.',
          icon: Icons.calendar_month_outlined,
          eyebrow: 'Nova temporada',
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_loadError != null)
          Card(
            child: ListTile(
              title: Text(_loadError!),
              trailing: const Icon(Icons.refresh),
              onTap: _load,
            ),
          )
        else if (_current != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _current!.isClosed
                            ? Icons.check_circle_outline
                            : Icons.auto_awesome_outlined,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _current!.isClosed
                              ? 'Temporada anterior encerrada'
                              : 'Antes de começar a próxima',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _current!.isClosed
                        ? 'Sua retrospectiva está guardada em Temporadas. Pronto para o próximo capítulo.'
                        : 'Encerre ${_current!.startDate.year}/${_current!.endDate.year} para registrar a tabela final e guardar os melhores momentos.',
                    style: const TextStyle(fontSize: 12, height: 1.6),
                  ),
                  if (!_current!.isClosed) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _closeCurrent,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Encerrar temporada atual'),
                      ),
                    ),
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _skipClosure = !_skipClosure),
                      child: Text(
                        _skipClosure
                            ? 'Encerrar antes de criar'
                            : 'Criar sem encerrar agora',
                      ),
                    ),
                  ],
                  TextButton.icon(
                    onPressed: _archive,
                    icon: const Icon(Icons.history),
                    label: const Text('Ver temporadas anteriores'),
                  ),
                ],
              ),
            ),
          ),
        Card(
          child: ListTile(
            title: Text('seasons.startSeasonDate'.tr()),
            subtitle: Text(_date(_start)),
            trailing: const Icon(Icons.calendar_month),
            onTap: () => _pick(true),
          ),
        ),
        Card(
          child: ListTile(
            title: Text('seasons.endSeasonDate'.tr()),
            subtitle: Text(_date(_end)),
            trailing: const Icon(Icons.calendar_month),
            onTap: () => _pick(false),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _saving || _loading || _loadError != null ? null : _save,
          child: Text(
            _saving
                ? 'common.inProgress'.tr()
                : _current != null && !_current!.isClosed && !_skipClosure
                ? 'Encerrar antes de continuar'
                : 'Criar temporada',
          ),
        ),
      ],
    ),
  );
}
