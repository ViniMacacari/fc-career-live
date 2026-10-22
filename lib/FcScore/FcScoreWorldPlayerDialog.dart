import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/Components/CareerUiStyle.dart';
import '../utils/GameCatalog.dart';
import '../utils/PlayerClubLookup.dart';
import 'FcScoreApi.dart';
import 'FcScoreWidgets.dart';
import 'FcScoreWorldPlayerReview.dart';
import 'FcScorePlayerCreation.dart';

Future<Map<String, String>?> fcCorrectWorldPlayers(
  BuildContext context, {
  required FcWorldPlayerReview review,
  required Map<String, String> mapping,
  String? playerVersion,
  PlayerClubLookup? playerClubs,
}) => showDialog<Map<String, String>>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _WorldPlayerDialog(
    review: review,
    mapping: mapping,
    playerVersion: playerVersion,
    playerClubs: playerClubs,
  ),
);

class _WorldPlayerDialog extends StatefulWidget {
  const _WorldPlayerDialog({
    required this.review,
    required this.mapping,
    this.playerVersion,
    this.playerClubs,
  });
  final FcWorldPlayerReview review;
  final Map<String, String> mapping;
  final String? playerVersion;
  final PlayerClubLookup? playerClubs;
  @override
  State<_WorldPlayerDialog> createState() => _WorldPlayerDialogState();
}

class _WorldPlayerDialogState extends State<_WorldPlayerDialog> {
  late final _mapping = Map<String, String>.of(widget.mapping);
  late List<FcWorldPlayerIssue> _steps = widget.review.issues(_mapping);
  final _scroll = ScrollController();
  int _index = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _steps.length - 1) {
      setState(() => _index++);
    } else {
      final remaining = widget.review.issues(_mapping);
      if (remaining.isEmpty) {
        Navigator.pop(context, _mapping);
        return;
      }
      setState(() {
        _steps = remaining;
        _index = 0;
      });
    }
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _choose(FcWorldReviewPlayer player) async {
    final occupied = widget.review.occupiedByOthers(player.id, _mapping);
    final selected = await fcPick(
      context,
      title: 'Vínculo de ${player.name}',
      playerVersion: widget.playerVersion,
      playerRows: widget.review.local,
      playerClubs: widget.playerClubs,
      items: [
        for (final entry in widget.review.local.entries)
          if (!occupied.contains(entry.key))
            CatalogItem(entry.key, fcId(entry.value['name'])),
      ],
      newPlayer: player.canCreate,
      playerSource: player.remote,
      playerChoice: _mapping[player.id],
    );
    if (selected != null && mounted) {
      setState(() => _mapping[player.id] = selected);
    }
  }

  Future<void> _createHere(
    FcWorldReviewPlayer player, {
    bool generate = false,
  }) async {
    final choice = await fcCreatePlayerHere(
      context,
      source: player.remote,
      choice: _mapping[player.id],
      generate: generate,
    );
    if (choice != null && mounted) setState(() => _mapping[player.id] = choice);
  }

  void _generateMissing() {
    setState(() {
      for (final player in widget.review.players.values) {
        if (!widget.review.isProtected(player.id) &&
            fcIsPlayerCreation(_mapping[player.id]) &&
            !widget.review.valid(player, _mapping)) {
          _mapping[player.id] = fcCreatePlayerChoice(
            player.remote,
            fcGeneratePlayerProfile(player.remote),
            generated: true,
          );
        }
      }
      _steps = widget.review.issues(_mapping);
      _index = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final issue = _steps.isEmpty ? null : _steps[_index];
    final review = widget.review;
    final ready =
        issue == null || issue.players.every((p) => review.valid(p, _mapping));
    final missing = review.players.values
        .where(
          (p) =>
              fcIsPlayerCreation(_mapping[p.id]) && !review.valid(p, _mapping),
        )
        .length;
    final colors = CareerUiColors(context);
    final localName = fcId(review.local[issue?.localId]?['name']);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 560,
        height: math.min(760, MediaQuery.sizeOf(context).height * .86),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Corrigir vínculos',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                issue == null
                    ? 'Dados prontos para revisão'
                    : 'Etapa ${_index + 1} de ${_steps.length}',
                style: TextStyle(color: colors.muted),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: issue == null ? 1 : (_index + 1) / _steps.length,
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  children: [
                    if (missing > 1)
                      OutlinedButton.icon(
                        key: const Key('fc-generate-all-missing'),
                        onPressed: _generateMissing,
                        icon: const Icon(Icons.shuffle_rounded),
                        label: Text('Gerar dados faltantes · $missing'),
                      ),
                    if (issue == null) ...[
                      const FcSection(
                        'Dados faltantes preenchidos',
                        subtitle: 'Confira os jogadores gerados. Toque no cadastro para ajustar qualquer um.',
                      ),
                      for (final player in review.players.values.where(
                        (p) => fcIsPlayerDraft(_mapping[p.id]),
                      ))
                        FcChoice(
                          key: ValueKey('fc-generated-${player.id}'),
                          title: player.teams.join(' / '),
                          value: fcChoiceLabel(_mapping[player.id], const []),
                          onTap: () => _createHere(player),
                        ),
                    ] else ...[
                      FcSection(
                        switch (issue.kind) {
                          FcWorldPlayerIssueKind.duplicate =>
                            'Vínculo duplicado',
                          FcWorldPlayerIssueKind.missingLink =>
                            'Cadastro indisponível nesta carreira',
                          FcWorldPlayerIssueKind.missingData =>
                            'Dados insuficientes para criar o jogador',
                        },
                        subtitle: switch (issue.kind) {
                          FcWorldPlayerIssueKind.duplicate =>
                            '“$localName” foi escolhido para jogadores diferentes. Mantenha esse cadastro em um deles e altere os demais.',
                          FcWorldPlayerIssueKind.missingLink => 'O cadastro salvo não está mais disponível. Escolha outro jogador da carreira ou crie um cadastro com os dados da API.',
                          FcWorldPlayerIssueKind.missingData => 'Complete os dados aqui, gere os campos faltantes ou escolha um jogador já cadastrado.',
                        },
                      ),
                      if (issue.localId != null &&
                          fcId(review.local[issue.localId]?['realPlayerId'])
                              .isNotEmpty)
                        FcFact(
                          'ID API do cadastro',
                          review.local[issue.localId]!['realPlayerId'],
                        ),
                      for (final player in issue.players)
                        FcPanel(
                          key: ValueKey('fc-correct-${player.id}'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                player.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                player.teams.join(' / '),
                                style: TextStyle(color: colors.muted),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'ID API ${player.id} · OVR ${player.hasOverall ? player.remote['overall'] : 'não informado'}',
                                style: TextStyle(
                                  color: colors.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 16),
                              FcChoice(
                                title: 'Cadastro na carreira',
                                value: fcChoiceLabel(_mapping[player.id], [
                                  for (final p in review.local.entries)
                                    CatalogItem(p.key, fcId(p.value['name'])),
                                ]),
                                onTap: review.isProtected(player.id)
                                    ? null
                                    : () => _choose(player),
                              ),
                              if (review.isProtected(player.id))
                                const Text('Meu clube · cadastro preservado'),
                              if (!review.isProtected(player.id) &&
                                  player.canCreate &&
                                  _mapping[player.id] != 'new')
                                OutlinedButton.icon(
                                  key: ValueKey(
                                    'fc-create-separate-${player.id}',
                                  ),
                                  onPressed: () => setState(
                                    () => _mapping[player.id] = 'new',
                                  ),
                                  icon: const Icon(
                                    Icons.person_add_alt_1_outlined,
                                  ),
                                  label: const Text('Criar cadastro separado'),
                                ),
                              if (!review.isProtected(player.id) &&
                                  !player.canCreate) ...[
                                OutlinedButton.icon(
                                  key: ValueKey('fc-create-here-${player.id}'),
                                  onPressed: () => _createHere(player),
                                  icon: const Icon(
                                    Icons.person_add_alt_1_outlined,
                                  ),
                                  label: const Text('Criar jogador aqui'),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  key: ValueKey('fc-generate-${player.id}'),
                                  onPressed: () =>
                                      _createHere(player, generate: true),
                                  icon: const Icon(Icons.shuffle_rounded),
                                  label: const Text('Gerar aleatório'),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Text(
                                review.valid(player, _mapping)
                                    ? 'Vínculo pronto'
                                    : 'Este vínculo precisa de correção',
                                style: TextStyle(
                                  color: review.valid(player, _mapping)
                                      ? colors.accent
                                      : colors.red,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const Text(
                      'O histórico dos cadastros existentes será preservado. Nenhum dado é importado durante a revisão.',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('fc-correction-next'),
                onPressed: ready
                    ? (issue == null
                          ? () => Navigator.pop(context, _mapping)
                          : _next)
                    : null,
                child: Text(
                  issue == null || _index == _steps.length - 1
                      ? 'Concluir revisão'
                      : 'Próxima etapa',
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  if (_index > 0)
                    TextButton(
                      onPressed: () {
                        setState(() => _index--);
                        if (_scroll.hasClients) _scroll.jumpTo(0);
                      },
                      child: const Text('Voltar'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
