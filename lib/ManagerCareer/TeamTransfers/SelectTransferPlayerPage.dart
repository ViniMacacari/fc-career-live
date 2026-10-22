import '../../utils/AppColors.dart';

import 'package:flutter/material.dart';

import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../utils/GamePlayers.dart';
import '../../utils/SqlService.dart';
import '../../utils/PlayerClubLookup.dart';
import '../../utils/Components/PlayerSearchCard.dart';
import '../TeamPage/CustomPlayerActions.dart';
import '../TeamPage/ViewPlayer/PlayerProfileVisuals.dart' show ProfilePortrait;
import 'TransferStyle.dart';
import '../../Settings/CustomConfiguration/CustomPlayersPage.dart';

class TransferPlayerChoice {
  const TransferPlayerChoice({
    required this.id,
    required this.name,
    this.realPlayer,
    this.custom,
  });
  final String id, name;
  final GamePlayer? realPlayer;
  final Map<String, Object?>? custom;
  String? get realPlayerId =>
      custom?['realPlayerId']?.toString() ?? realPlayer?.id;
  String? get avatar => custom?['customAvatarFilePath']?.toString();
  int? get overall =>
      (custom?['overall'] as num?)?.toInt() ?? realPlayer?.overall;
}

class SelectTransferPlayerPage extends StatefulWidget {
  const SelectTransferPlayerPage({
    super.key,
    required this.person,
    required this.season,
    required this.rosterIds,
    this.onlyRoster = false,
    this.excludedIds = const {},
    this.optional = false,
    this.sql,
  });
  final Person person;
  final Season season;
  final Set<String> rosterIds, excludedIds;
  final bool onlyRoster, optional;
  final SqlService? sql;
  @override
  State<SelectTransferPlayerPage> createState() =>
      _SelectTransferPlayerPageState();
}

class _SelectTransferPlayerPageState extends State<SelectTransferPlayerPage> {
  late final _sql = widget.sql ?? SqlService.instance;
  late Map<String, GamePlayer> _realById;
  late final _data =
      Future.wait<Object>([
        _sql.getCustomPlayers(widget.person.id),
        GamePlayers.load(widget.person.fifaVersion),
        PlayerClubLookup.load(
          sql: _sql,
          person: widget.person,
          seasonId: widget.season.id,
        ),
      ]).then((data) {
        _realById = {
          for (final player in data[1] as List<GamePlayer>) player.id: player,
        };
        return data;
      });
  String _query = '';

  Future<void> _createCustom() async {
    final player = await openCustomPlayerCreator(
      context,
      person: widget.person,
      season: widget.season,
      addToRoster: widget.onlyRoster,
    );
    if (player == null || !mounted) return;
    Navigator.pop(
      context,
      TransferPlayerChoice(
        id: player['id'] as String,
        name: player['name'] as String,
        custom: player,
      ),
    );
  }

  Future<void> _useShared() async {
    final player = await Navigator.push<Map<String, Object?>>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomPlayersPage(
          person: widget.person,
          season: widget.season,
          addToRoster: widget.onlyRoster,
          excludedIds: widget.excludedIds,
        ),
      ),
    );
    if (player == null || !mounted) return;
    Navigator.pop(
      context,
      TransferPlayerChoice(
        id: player['id'] as String,
        name: player['name'] as String,
        custom: player,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => TransferTheme(
    child: Scaffold(
      appBar: AppBar(title: const Text('Selecionar Jogador')),
      body: Column(
        children: [
          if (MediaQuery.viewInsetsOf(context).bottom == 0)
            Padding(
              key: const ValueKey('shared-transfer-shortcut'),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: OutlinedButton.icon(
                onPressed: _useShared,
                icon: const Icon(Icons.groups_outlined),
                label: const Text('Jogadores personalizados já criados'),
              ),
            ),
          if (MediaQuery.viewInsetsOf(context).bottom == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: CreateCustomPlayerAction(
                onTap: _createCustom,
                subtitle: widget.onlyRoster
                    ? 'Crie um jogador no elenco e selecione para a transferência.'
                    : 'Crie um jogador e continue esta transferência.',
              ),
            ),
          Padding(
            key: const ValueKey('transfer-player-search'),
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar jogador',
                prefixIcon: Icon(Icons.search),
                contentPadding: EdgeInsets.all(16),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Object>>(
              future: _data,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Não foi possível carregar os jogadores: ${snapshot.error}',
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final custom = snapshot.data![0] as List<Map<String, Object?>>;
                final real = snapshot.data![1] as List<GamePlayer>;
                final clubs = snapshot.data![2] as PlayerClubLookup;
                final linkedRealIds = {
                  for (final row in custom) row['realPlayerId']?.toString(),
                };
                final choices =
                    <TransferPlayerChoice>[
                          for (final row in custom)
                            if (!widget.onlyRoster ||
                                widget.rosterIds.contains(row['id']))
                              TransferPlayerChoice(
                                id: row['id'] as String,
                                name: row['name']?.toString() ?? '',
                                custom: row,
                              ),
                          if (!widget.onlyRoster)
                            for (final player in real)
                              if (!linkedRealIds.contains(player.id))
                                TransferPlayerChoice(
                                  id: player.id,
                                  name: player.name,
                                  realPlayer: player,
                                ),
                        ]
                        .where(
                          (choice) =>
                              !widget.excludedIds.contains(choice.id) &&
                              (choice.name.toLowerCase().contains(_query) ||
                                  choice.id.contains(_query)),
                        )
                        .toList();
                choices.sort((a, b) {
                  final aRoster = widget.rosterIds.contains(a.id);
                  final bRoster = widget.rosterIds.contains(b.id);
                  if (aRoster != bRoster) return aRoster ? -1 : 1;
                  final aCareer = a.custom != null;
                  final bCareer = b.custom != null;
                  if (aCareer != bCareer) return aCareer ? -1 : 1;
                  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                });
                if (choices.isEmpty && !widget.optional) {
                  return const Center(
                    child: Text('Nenhum jogador encontrado.'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  itemCount: choices.length + (widget.optional ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (widget.optional && index == 0) {
                      return ListTile(
                        title: const Text('Não incluir outro jogador'),
                        leading: const Icon(Icons.clear),
                        onTap: () => Navigator.pop(
                          context,
                          const TransferPlayerChoice(id: '', name: ''),
                        ),
                      );
                    }
                    final choice = choices[index - (widget.optional ? 1 : 0)];
                    return Card(
                      color: AppColors.of(context).panel,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        leading: ProfilePortrait(
                          version: widget.person.fifaVersion,
                          realPlayerId: choice.realPlayerId,
                          customAvatarFilePath: choice.avatar,
                          width: 36,
                          height: 44,
                        ),
                        title: Text(choice.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                widget.rosterIds.contains(choice.id)
                                    ? 'Elenco da temporada'
                                    : choice.custom != null
                                    ? 'Jogador da carreira'
                                    : 'Jogador do catálogo',
                                if (choice.overall != null)
                                  'GER ${choice.overall}',
                              ].join(' • '),
                            ),
                            PlayerClubCaption(
                              club: clubs.club(
                                playerId: choice.id,
                                realPlayerId: choice.realPlayerId,
                                player:
                                    choice.realPlayer ??
                                    _realById[choice.realPlayerId],
                              ),
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.arrow_right),
                        onTap: () => Navigator.pop(context, choice),
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
}
