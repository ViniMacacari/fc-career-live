import 'package:flutter/material.dart';

import '../models/Person.dart';
import '../utils/SqlService.dart';
import '../utils/competitions/CompetitionFormats.dart';

Future<String?> suggestStage(
  Person person, {
  required String tournamentId,
  required String? seasonId,
  required CompetitionFormat format,
  DateTime? date,
  String? excludeFixtureId,
  SqlService? sql,
}) async {
  final fixtures = seasonId == null
      ? const <Map<String, Object?>>[]
      : await (sql ?? SqlService.instance).getFixtures(
          person.id,
          person.category,
          seasonId: seasonId,
        );
  final previous = [
    for (final fixture in fixtures)
      if (fixture['tournamentId'] == tournamentId &&
          fixture['id'] != excludeFixtureId &&
          (date == null ||
              (DateTime.tryParse('${fixture['date']}')?.isBefore(date) ??
                  false)))
        if ((format.structured
                    ? format
                    : CompetitionFormat.manualStagesFor(
                        fixture['stage']?.toString(),
                      ))
                .parse(fixture['stage']?.toString())
            case final stage?)
          (
            DateTime.tryParse('${fixture['date']}') ?? DateTime(0),
            stage,
            format.structured
                ? format
                : CompetitionFormat.manualStagesFor(
                    fixture['stage']?.toString(),
                  ),
          ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final effective =
      previous.lastOrNull?.$3 ??
      (format.structured
          ? format
          : CompetitionFormat.manualStages(CompetitionKind.league));
  final next = effective.next(previous.lastOrNull?.$2);
  return next == null ? null : effective.label(next);
}

Future<String?> showStagePicker(
  BuildContext context, {
  required CompetitionFormat format,
  required String current,
  required String competition,
  String? suggested,
}) => showDialog<String>(
  context: context,
  builder: (context) => _StageDialog(
    format: format,
    current: current,
    competition: competition,
    suggested: suggested,
  ),
);

class _StageDialog extends StatefulWidget {
  const _StageDialog({
    required this.format,
    required this.current,
    required this.competition,
    this.suggested,
  });
  final CompetitionFormat format;
  final String current, competition;
  final String? suggested;

  @override
  State<_StageDialog> createState() => _StageDialogState();
}

class _StageDialogState extends State<_StageDialog> {
  late CompetitionFormat _format = widget.format.structured
      ? widget.format
      : CompetitionFormat.manualStagesFor(
          widget.current.isEmpty ? widget.suggested : widget.current,
        );
  bool get _manual => !widget.format.structured;
  late final _text = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  MatchStage? get _stage => _format.parse(_text.text);
  bool get _final => _stage != null && _format.isFinal(_stage!);

  void _write(String value) => setState(() {
    if (_manual && _format.parse(value) == null) {
      final inferred = CompetitionFormat.manualStagesFor(value);
      if (inferred.parse(value) != null) _format = inferred;
    }
    _text.text = value;
    _text.selection = TextSelection.collapsed(offset: value.length);
  });

  void _setLeg(StageLeg leg) {
    final stage = _stage;
    if (stage == null) return;
    _write(
      _format.label(
        stage.finale
            ? MatchStage.finale(leg: leg)
            : MatchStage.phase(stage.phase!, leg: leg),
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: Theme.of(context).hintColor),
    ),
  );

  Widget _chip(String label, String value) => ChoiceChip(
    label: Text(label),
    showCheckmark: false,
    visualDensity: VisualDensity.compact,
    selected: _text.text.trim() == value,
    onSelected: (_) => _write(value),
  );

  Widget _roundButton(int round, String value) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _text.text.trim() == value;
    return Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _write(value),
        child: SizedBox(
          width: 38,
          height: 32,
          child: Center(
            child: Text(
              '$round',
              style: TextStyle(
                fontSize: 13,
                color: selected
                    ? scheme.onSecondaryContainer
                    : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _rounds() {
    final group = _format.kind == CompetitionKind.groups;
    if (_format.kind != CompetitionKind.league && !group) {
      return const [];
    }
    final selectedRound = _stage?.round ?? 1;
    final rounds = _format.rounds > 0
        ? _format.rounds
        : (selectedRound > 38 ? selectedRound + 5 : 38);
    return [
      _heading(group ? _format.groupLabel : 'Rodadas'),
      Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (var round = 1; round <= rounds; round++)
            _roundButton(
              round,
              _format.label(
                group ? MatchStage.groupRound(round) : MatchStage.round(round),
              ),
            ),
        ],
      ),
      if (_format.rounds == 0 && _stage?.round != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.skip_next),
            label: const Text('Próxima rodada'),
            onPressed: () => _write(_format.label(_format.next(_stage)!)),
          ),
        ),
    ];
  }

  List<Widget> _phases() {
    if (_manual && _format.kind != CompetitionKind.knockout) return const [];
    final phases = [
      for (final (index, phase) in _format.phases.indexed)
        if (index != _format.finaleIndex) (index, phase),
    ];
    if (phases.isEmpty && !_format.thirdPlace) return const [];
    return [
      _heading(
        _format.kind == CompetitionKind.league ? 'Playoffs' : 'Mata-mata',
      ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (index, phase) in phases)
            _chip(
              phase.label,
              _format.label(
                MatchStage.phase(
                  index,
                  leg: phase.twoLegs ? StageLeg.first : StageLeg.single,
                ),
              ),
            ),
          if (_format.thirdPlace) _chip(thirdPlaceLabel, thirdPlaceLabel),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final stage = _stage;
    final legs = stage != null && (stage.phase != null || stage.finale);
    return AlertDialog(
      title: const Text('Estágio da partida'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.competition,
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
              const SizedBox(height: 12),
              if (_manual) ...[
                DropdownButtonFormField<CompetitionKind>(
                  key: ValueKey(_format.kind),
                  initialValue: _format.kind,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de estágio',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: CompetitionKind.league,
                      child: Text('Liga'),
                    ),
                    DropdownMenuItem(
                      value: CompetitionKind.groups,
                      child: Text('Fase de Grupos'),
                    ),
                    DropdownMenuItem(
                      value: CompetitionKind.knockout,
                      child: Text('Mata-mata'),
                    ),
                  ],
                  onChanged: (kind) {
                    if (kind == null) return;
                    _format = CompetitionFormat.manualStages(kind);
                    final suggestion = _format.parse(widget.suggested);
                    _write(_format.label(suggestion ?? _format.next(null)!));
                  },
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _text,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Estágio',

                  suffixIcon: _text.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar',
                          icon: const Icon(Icons.close),
                          onPressed: () => _write(''),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(finaleLabel),
                subtitle: const Text('Esta partida é a final da competição.'),
                value: _final,
                onChanged: (value) {
                  if (value == true) {
                    _write(
                      _format.label(
                        _format.finale(stage?.leg ?? StageLeg.single),
                      ),
                    );
                  } else if (_final) {
                    _write('');
                  }
                },
              ),
              if (legs)
                SegmentedButton<StageLeg>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: StageLeg.single, label: Text('Único')),
                    ButtonSegment(value: StageLeg.first, label: Text('Ida')),
                    ButtonSegment(value: StageLeg.second, label: Text('Volta')),
                  ],
                  selected: {stage.leg},
                  onSelectionChanged: (value) => _setLeg(value.first),
                ),
              if (widget.suggested != null &&
                  widget.suggested != _text.text.trim()) ...[
                _heading('Sugestão'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    avatar: const Icon(Icons.auto_awesome, size: 16),
                    label: Text(widget.suggested!),
                    onPressed: () => _write(widget.suggested!),
                  ),
                ),
              ],
              ..._rounds(),
              ..._phases(),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _text.text.trim()),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
