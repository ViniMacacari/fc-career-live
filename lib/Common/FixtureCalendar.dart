import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/Components/CareerUiStyle.dart';
import 'FixtureResultTile.dart';

class FixtureCalendar extends StatefulWidget {
  const FixtureCalendar({
    super.key,
    required this.rows,
    required this.locale,
    required this.matchBuilder,
  });
  final List<Map<String, Object?>> rows;
  final String locale;
  final Widget Function(Map<String, Object?>) matchBuilder;

  @override
  State<FixtureCalendar> createState() => _FixtureCalendarState();
}

class _FixtureCalendarState extends State<FixtureCalendar> {
  late DateTime _month, _selected;
  late String _signature;
  Map<DateTime, List<Map<String, Object?>>> _days = {};
  final _undated = <Map<String, Object?>>[];

  String get _rowsSignature =>
      widget.rows.map((r) => '${r['id']}|${r['date']}').join(';');
  DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);
  DateTime get _latest =>
      _days.keys.fold<DateTime?>(
        null,
        (latest, day) => latest == null || day.isAfter(latest) ? day : latest,
      ) ??
      _day(DateTime.now());

  @override
  void initState() {
    super.initState();
    _readRows();
    _selectLatest();
  }

  void _readRows() {
    _signature = _rowsSignature;
    _days = {};
    _undated.clear();
    for (final row in widget.rows) {
      final date = DateTime.tryParse('${row['date']}');
      if (date == null) {
        _undated.add(row);
      } else {
        (_days[_day(date)] ??= []).add(row);
      }
    }
    for (final games in _days.values) {
      games.sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    }
  }

  void _selectLatest() {
    _selected = _latest;
    _month = DateTime(_selected.year, _selected.month);
  }

  @override
  void didUpdateWidget(covariant FixtureCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = _signature != _rowsSignature;
    _readRows();
    if (changed) _selectLatest();
  }

  void _move(int delta) => setState(() {
    _month = DateTime(_month.year, _month.month + delta);
    _selected = _month;
  });

  Color _resultColor(CareerUiColors c, FixtureResult result) =>
      switch (result) {
        FixtureResult.win => c.green,
        FixtureResult.draw => c.amber,
        FixtureResult.lose => c.red,
      };

  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    final offset = _month.weekday - 1;
    final dayCount = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = ((offset + dayCount + 6) ~/ 7) * 7;
    final selectedGames = _days[_selected] ?? const <Map<String, Object?>>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const ValueKey('fixture-month-calendar'),
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: c.surface(),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('calendar-previous-month'),
                    tooltip: 'Mês anterior',
                    onPressed: () => _move(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Text(
                      DateFormat('MMMM yyyy', widget.locale).format(_month),
                      key: const ValueKey('calendar-month-label'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('calendar-next-month'),
                    tooltip: 'Próximo mês',
                    onPressed: () => _move(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('calendar-latest-match'),
                  onPressed: _days.isEmpty
                      ? null
                      : () => setState(_selectLatest),
                  icon: const Icon(Icons.today_outlined, size: 16),
                  label: const Text('Último jogo'),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          DateFormat(
                            'EE',
                            widget.locale,
                          ).format(DateTime(2024, 1, i + 1)),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              GridView.builder(
                shrinkWrap: true,
                primary: false,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent:
                      54 +
                      (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(
                        0,
                        20,
                      ),
                ),
                itemCount: cells,
                itemBuilder: (_, index) {
                  final dayNumber = index - offset + 1;
                  if (dayNumber < 1 || dayNumber > dayCount) {
                    return const SizedBox.shrink();
                  }
                  final day = DateTime(_month.year, _month.month, dayNumber);
                  final games = _days[day] ?? const <Map<String, Object?>>[];
                  final active = day == _selected;
                  return Semantics(
                    label:
                        '${DateFormat('dd/MM/yyyy').format(day)}, ${games.length} partidas',
                    button: true,
                    selected: active,
                    child: Material(
                      color: active
                          ? c.accent.withValues(alpha: .16)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        key: ValueKey(
                          'calendar-day-${DateFormat('yyyy-MM-dd').format(day)}',
                        ),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _selected = day),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '$dayNumber',
                                maxLines: 1,
                                style: TextStyle(
                                  color: active ? c.accent : c.text,
                                  fontSize: 14,
                                  height: 1.2,
                                  fontWeight: active || games.isNotEmpty
                                      ? FontWeight.w800
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            SizedBox(
                              height: 6,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (final game in games.take(3))
                                    Container(
                                      width: 5,
                                      height: 5,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _resultColor(
                                          c,
                                          fixtureResult(game),
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                children: [
                  for (final (result, label) in [
                    (FixtureResult.win, 'Vitória'),
                    (FixtureResult.draw, 'Empate'),
                    (FixtureResult.lose, 'Derrota'),
                  ])
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 7,
                          color: _resultColor(c, result),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: TextStyle(color: c.muted, fontSize: 10),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 12),
          child: Text(
            DateFormat('dd/MM/yyyy').format(_selected),
            key: const ValueKey('calendar-selected-date'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        if (selectedGames.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
            child: Text(
              'Nenhuma partida registrada neste dia.',
              style: TextStyle(color: c.muted),
            ),
          ),
        for (final game in selectedGames) widget.matchBuilder(game),
        if (_undated.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Partidas sem data válida'),
          ),
          for (final game in _undated) widget.matchBuilder(game),
        ],
      ],
    );
  }
}
