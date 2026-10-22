import 'dart:math';

import 'package:flutter/material.dart';

import '../models/Person.dart';
import '../utils/GameCatalog.dart';
import '../utils/SqlService.dart';
import 'TwitterModels.dart';
import 'TwitterStore.dart';
import 'TwitterStyle.dart';

typedef XGenerationRequest = ({
  String? fixtureId,
  TwitterGenerationSelection selection,
});

Future<XGenerationRequest?> showXGenerationDialog(
  BuildContext context,
  Person person,
) async {
  final settings = await TwitterStore.instance.preferences(person.id);
  final fixtures = await SqlService.instance.getFixtures(
    person.id,
    person.category,
  );
  final catalog = await GameCatalog.load();
  if (!context.mounted) return null;
  return showDialog<XGenerationRequest>(
    context: context,
    builder: (_) => XTheme(
      builder: (_) => XGenerationDialog(
        person: person,
        settings: settings,
        fixtures: fixtures,
        catalog: catalog,
      ),
    ),
  );
}

class XGenerationDialog extends StatefulWidget {
  const XGenerationDialog({
    super.key,
    this.store,
    required this.person,
    required this.settings,
    required this.fixtures,
    required this.catalog,
  });
  final TwitterStore? store;
  final Person person;
  final TwitterPreferences settings;
  final List<Map<String, Object?>> fixtures;
  final GameCatalog catalog;
  @override
  State<XGenerationDialog> createState() => _XGenerationDialogState();
}

class _XGenerationDialogState extends State<XGenerationDialog> {
  late final counts = <int>[
    max(
      0,
      widget.settings.postCount -
          widget.settings.pagePosts -
          widget.settings.journalPosts -
          widget.settings.rivalPosts,
    ),
    widget.settings.pagePosts,
    widget.settings.journalPosts,
    widget.settings.rivalPosts,
  ];
  String fixtureId = '';
  bool club = false,
      opponent = false,
      clubExists = false,
      opponentExists = false,
      loading = false;
  Future<void> _fixture(String id) async {
    setState(() {
      fixtureId = id;
      club = false;
      opponent = false;
      loading = true;
    });
    final own = await (widget.store ?? TwitterStore.instance).post(
      widget.person.id,
      '${widget.person.id}:official:$id',
      includeDeleted: true,
    );
    final other = await (widget.store ?? TwitterStore.instance).post(
      widget.person.id,
      '${widget.person.id}:opponentOfficial:$id',
      includeDeleted: true,
    );
    if (mounted && fixtureId == id) {
      setState(() {
        clubExists = own != null;
        opponentExists = other != null;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = TwitterGenerationSelection(
      fans: counts[0],
      pages: counts[1],
      journals: counts[2],
      rivals: counts[3],
      clubPost: club,
      opponentPost: opponent,
    );
    return XAlertDialog(
      title: const Text('Gerar personalizado'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Escolha o assunto e as publicações. O padrão salvo continua o mesmo.',
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                key: const ValueKey('x-generation-match'),
                initialValue: fixtureId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Assunto'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Conversas recentes do feed'),
                  ),
                  for (final f in widget.fixtures)
                    DropdownMenuItem(
                      value: f['id'] as String,
                      child: Text(
                        '${(f['date'] as String).substring(0, 10)} · '
                        '${widget.catalog.teamLabel(widget.person.fifaVersion, f['oppositeTeamId'] as String, leagueId: f['oppositeTeamLeagueId'] as String?)} '
                        '(${f['playerTeamScore']} × ${f['oppositeTeamScore']})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) _fixture(id);
                },
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < counts.length; i++)
                Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Checkbox(
                        value: counts[i] > 0,
                        onChanged: (v) =>
                            setState(() => counts[i] = v == true ? 1 : 0),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () =>
                            setState(() => counts[i] = counts[i] > 0 ? 0 : 1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            const [
                              'Torcedores',
                              'Páginas',
                              'Jornais',
                              'Rivais',
                            ][i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 44,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: counts[i] == 0
                          ? null
                          : () => setState(() => counts[i]--),
                      icon: const Icon(Icons.remove, size: 18),
                    ),
                    SizedBox(
                      width: 22,
                      child: Text('${counts[i]}', textAlign: TextAlign.center),
                    ),
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 44,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: selection.total >= 100
                          ? null
                          : () => setState(() => counts[i]++),
                      icon: const Icon(Icons.add, size: 18),
                    ),
                  ],
                ),
              if (fixtureId.isNotEmpty) ...[
                const Divider(),
                if (loading) const LinearProgressIndicator(),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Post oficial do meu clube',
                    style: TextStyle(color: xColors(context).text),
                  ),
                  subtitle: clubExists
                      ? const Text('Já publicado nesta partida')
                      : null,
                  value: club,
                  onChanged: loading || clubExists
                      ? null
                      : (v) => setState(() => club = v!),
                ),
                CheckboxListTile(
                  key: const ValueKey('x-generation-opponent'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Post oficial do adversário',
                    style: TextStyle(color: xColors(context).text),
                  ),
                  subtitle: Text(
                    opponentExists
                        ? 'Já publicado nesta partida'
                        : 'Com o resultado na perspectiva dele',
                    style: TextStyle(color: xColors(context).muted),
                  ),
                  value: opponent,
                  onChanged: loading || opponentExists
                      ? null
                      : (v) => setState(() => opponent = v!),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                '${selection.total} posts de repercussão${club || opponent ? ' + oficiais selecionados' : ''}. Usa a IA configurada.',
              ),
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
          onPressed: !selection.valid || loading
              ? null
              : () => Navigator.pop(context, (
                  fixtureId: fixtureId.isEmpty ? null : fixtureId,
                  selection: selection,
                )),
          child: const Text('Gerar'),
        ),
      ],
    );
  }
}
