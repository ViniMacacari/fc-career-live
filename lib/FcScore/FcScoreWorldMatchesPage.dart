import 'package:flutter/material.dart';

import '../utils/Components/CareerUiStyle.dart';
import 'FcScoreApi.dart';
import 'FcScoreModels.dart';
import 'FcScoreRepository.dart';
import 'FcScoreWidgets.dart';

class FcScoreWorldMatchesPage extends StatefulWidget {
  const FcScoreWorldMatchesPage({
    super.key,
    required this.matches,
    required this.selectedKeys,
  });
  final List<FcWorldMatchPreview> matches;
  final Set<String> selectedKeys;

  @override
  State<FcScoreWorldMatchesPage> createState() =>
      _FcScoreWorldMatchesPageState();
}

class _FcScoreWorldMatchesPageState extends State<FcScoreWorldMatchesPage> {
  late final _selected = widget.selectedKeys
      .where(
        (key) => widget.matches.any(
          (item) => !item.exists && item.match.remoteKey == key,
        ),
      )
      .toSet();
  String _query = '';
  int _filter = 0;

  @override
  Widget build(BuildContext context) {
    final colors = CareerUiColors(context);
    final existing = widget.matches.where((item) => item.exists).length;
    final rows = widget.matches.where((item) {
      if (_filter == 1 && (item.exists || item.ignored) ||
          _filter == 2 && !item.exists ||
          _filter == 3 && (!item.ignored || item.exists)) {
        return false;
      }
      final m = item.match;
      return fcNormalize(
        '${fcName(fcObject(m.home['team'])['name'])} '
        '${fcName(fcObject(m.away['team'])['name'])} '
        '${fcName(m.competition['name'])} ${fcDay(m.date)}',
      ).contains(fcNormalize(_query));
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Selecionar partidas')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_selected.length} selecionadas · $existing já cadastradas · ${widget.matches.where((m) => m.ignored && !m.exists).length} ignoradas',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          const FcNotice(
                            'Escolha os jogos que entram em Partidas e nas suas estatísticas. Os já cadastrados serão preservados. O calendário das competições continua completo.',
                          ),
                          TextField(
                            decoration: fcInput(
                              'Buscar time, competição ou data',
                              icon: Icons.search,
                            ),
                            onChanged: (value) =>
                                setState(() => _query = value),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final (index, label) in [
                                (0, 'Todos'),
                                (1, 'Novos'),
                                (2, 'Cadastrados'),
                                (3, 'Ignoradas'),
                              ])
                                ChoiceChip(
                                  label: Text(label),
                                  selected: _filter == index,
                                  onSelected: (_) =>
                                      setState(() => _filter = index),
                                ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => setState(
                                  () => _selected.addAll(
                                    widget.matches
                                        .where(
                                          (item) =>
                                              !item.exists && !item.ignored,
                                        )
                                        .map((item) => item.match.remoteKey),
                                  ),
                                ),
                                child: const Text('Selecionar novos'),
                              ),
                              TextButton(
                                onPressed: _selected.isEmpty
                                    ? null
                                    : () => setState(_selected.clear),
                                child: const Text('Desmarcar todos'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (rows.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('Nenhuma partida neste filtro.'),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      sliver: SliverList.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final item = rows[index], m = item.match;
                          return FcPanel(
                            child: CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _selected.contains(m.remoteKey),
                              onChanged: item.exists
                                  ? null
                                  : (value) => setState(() {
                                      value == true
                                          ? _selected.add(m.remoteKey)
                                          : _selected.remove(m.remoteKey);
                                    }),
                              title: Text(
                                '${fcName(fcObject(m.home['team'])['name'])} '
                                '${m.homeGoals} × ${m.awayGoals} '
                                '${fcName(fcObject(m.away['team'])['name'])}',
                                style: TextStyle(
                                  color: colors.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${fcDay(m.date)} · ${fcName(m.competition['name'])}',
                                      style: TextStyle(color: colors.muted),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      item.exists
                                          ? item.manual
                                                ? 'Já configurada · preservar'
                                                : 'Já importada · preservar'
                                          : _selected.contains(m.remoteKey)
                                          ? 'Importar partida'
                                          : item.ignored
                                          ? 'Ignorada anteriormente'
                                          : 'Não importar partida',
                                      style: TextStyle(
                                        color: item.exists
                                            ? colors.muted
                                            : colors.accent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (item.scoreDiffers) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'Placar no aplicativo: ${item.localHomeGoals} × ${item.localAwayGoals}. Será mantido.',
                                        style: TextStyle(color: colors.amber),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, Set<String>.of(_selected)),
                  icon: const Icon(Icons.check_rounded),
                  label: Text('Confirmar seleção · ${_selected.length}'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
