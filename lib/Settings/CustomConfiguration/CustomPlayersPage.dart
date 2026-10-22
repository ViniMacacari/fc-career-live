import 'package:flutter/material.dart';

import '../../ManagerCareer/TeamPage/CreateCustomPlayerPage.dart';
import '../../ManagerCareer/TeamPage/ViewPlayer/PlayerProfileVisuals.dart'
    show ProfilePortrait;
import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../utils/Components/CareerPageWidgets.dart';
import '../../utils/Components/CareerUiStyle.dart';
import '../../utils/databaseUtils.dart' show positionShortName;
import '../../utils/Components/SelectionSearchField.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/SqlService.dart';
import 'CustomConfigurationComponents.dart';

class CustomPlayersPage extends StatefulWidget {
  const CustomPlayersPage({
    super.key,
    this.person,
    this.season,
    this.addToRoster = false,
    this.excludedIds = const {},
    this.service,
  });
  final Person? person;
  final Season? season;
  final bool addToRoster;
  final Set<String> excludedIds;
  final SqlService? service;
  @override
  State<CustomPlayersPage> createState() => _CustomPlayersPageState();
}

class _CustomPlayersPageState extends State<CustomPlayersPage> {
  final _search = TextEditingController();
  late Future<List<Map<String, Object?>>> _data = _load();
  String _query = '';
  String? _savingId;
  bool get _picking => widget.person != null;
  SqlService get _sql => widget.service ?? SqlService.instance;

  Future<List<Map<String, Object?>>> _load() async {
    final shared = await _sql.getSharedPlayers();
    if (!_picking) return shared;
    final career = await _sql.getCustomPlayers(widget.person!.id);
    final byTemplate = {
      for (final player in career)
        (player['libraryPlayerId'] ?? player['id']): player,
    };
    final roster = widget.addToRoster && widget.season != null
        ? await _sql.getTeamPlayers(widget.person!.id, widget.season!.id)
        : const <Map<String, Object?>>[];
    return [
      for (final player in shared)
        {
          ...player,
          if (byTemplate[player['id']]
              case final Map<String, Object?> existing) ...{
            'careerPlayerId': existing['id'],
            'overall': existing['overall'],
            'unavailable':
                widget.excludedIds.contains(existing['id']) ||
                roster.any((r) => r['playerId'] == existing['id']),
          },
        },
    ];
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _edit([Map<String, Object?>? player]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateCustomPlayerPage(
          addToRoster: false,
          template: player,
          service: widget.service,
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        _data = _load();
      });
    }
  }

  Future<void> _choose(Map<String, Object?> template) async {
    if (_savingId != null || template['unavailable'] == true) return;
    setState(() => _savingId = template['id'] as String);
    try {
      final player = await _sql.useSharedPlayer(
        personId: widget.person!.id,
        templateId: template['id'] as String,
        seasonId: widget.addToRoster ? widget.season?.id : null,
      );
      if (mounted) Navigator.pop(context, player);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível selecionar o jogador: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => CustomConfigurationTheme(
    child: Builder(
      builder: (context) {
        final c = CareerUiColors(context);
        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Jogadores personalizados',
              maxLines: 2,
              style: TextStyle(fontSize: 18, height: 1.15),
            ),
          ),
          floatingActionButton: _picking
              ? null
              : FloatingActionButton.extended(
                  onPressed: _edit,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Criar jogador'),
                ),
          body: SafeArea(
            child: Column(
              children: [
                if (MediaQuery.viewInsetsOf(context).bottom == 0)
                  Padding(
                    key: const ValueKey('shared-player-intro'),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: CareerPageHeader(
                      title: _picking
                          ? 'Escolha seu jogador'
                          : 'Seu catálogo de jogadores',
                      subtitle: _picking
                          ? 'Use um jogador já criado nesta carreira.'
                          : 'Crie e edite jogadores para usar em todos os FIFAs e em todas as carreiras.',
                      icon: Icons.groups_outlined,
                      eyebrow: 'Catálogo compartilhado',
                    ),
                  ),
                Padding(
                  key: const ValueKey('shared-player-search'),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SelectionSearchField(
                    controller: _search,
                    hint: 'Buscar jogador',
                    onChanged: (value) =>
                        setState(() => _query = selectionSearchKey(value)),
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<Map<String, Object?>>>(
                    future: _data,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const CareerEmptyState(
                          title: 'Não foi possível carregar os jogadores',
                          subtitle: 'Volte e tente novamente.',
                          icon: Icons.error_outline_rounded,
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final rows = snapshot.data!
                          .where(
                            (p) =>
                                selectionSearchKey(p['name'] as String)
                                    .contains(_query),
                          )
                          .toList();
                      if (rows.isEmpty) {
                        return CareerEmptyState(
                          title: _query.isEmpty
                              ? 'Seu catálogo está vazio'
                              : 'Nenhum jogador encontrado',
                          subtitle: _query.isEmpty
                              ? 'Os jogadores personalizados criados nas carreiras também aparecem aqui.'
                              : 'Tente outro nome.',
                          icon: Icons.person_search_outlined,
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final player = rows[index];
                          final unavailable = player['unavailable'] == true;
                          return Material(
                            key: ValueKey('shared-player-${player['id']}'),
                            color: c.panel,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(color: c.line),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              enabled: !unavailable && _savingId == null,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: ProfilePortrait(
                                  version:
                                      widget.person?.fifaVersion ??
                                      GameCatalog.fifaVersions.last,
                                  customAvatarFilePath:
                                      player['customAvatarFilePath'] as String?,
                                  width: 44,
                                  height: 52,
                                ),
                              ),
                              title: Text(
                                player['name'] as String,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                [
                                  positionShortName(
                                    player['positionId'] as String?,
                                  ),
                                  'GER ${player['overall']}',
                                  unavailable
                                      ? 'Já selecionado nesta carreira'
                                      : 'Todos os FIFAs',
                                ].join(' · '),
                              ),
                              trailing: _savingId == player['id']
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      unavailable
                                          ? Icons.check_circle_outline_rounded
                                          : _picking
                                          ? Icons.add_rounded
                                          : Icons.edit_outlined,
                                      color: unavailable ? c.muted : c.accent,
                                    ),
                              onTap: () =>
                                  _picking ? _choose(player) : _edit(player),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
