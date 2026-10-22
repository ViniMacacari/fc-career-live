import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../models/Person.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/SqlService.dart';
import '../../utils/Components/CareerPageWidgets.dart';
import 'AcademyPlayerInfoPage.dart';

class AcademyPage extends StatefulWidget {
  const AcademyPage({super.key, required this.person});
  final Person person;

  @override
  State<AcademyPage> createState() => _AcademyPageState();
}

class _AcademyPageState extends State<AcademyPage> {
  late Future<List<Map<String, Object?>>> _players = SqlService.instance
      .getAcademyPlayers(widget.person.id);

  Future<void> _open(Map<String, Object?>? row) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AcademyPlayerInfoPage(person: widget.person, existing: row),
      ),
    );
    if (changed == true) {
      setState(
        () =>
            _players = SqlService.instance.getAcademyPlayers(widget.person.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('academy.academy'.tr())),
    floatingActionButton: FloatingActionButton(
      onPressed: () => _open(null),
      child: const Icon(Icons.add),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _players,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return CareerEmptyState(
            title: 'academy.noAcademyPlayers'.tr(),
            subtitle: 'Cadastre os talentos da base e acompanhe o caminho até o time principal.',
            icon: Icons.school_outlined,
            action: FilledButton.icon(
              onPressed: () => _open(null),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar jogador'),
            ),
          );
        }
        return FutureBuilder<GameCatalog>(
          future: GameCatalog.load(),
          builder: (context, catalogSnapshot) {
            if (!catalogSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final positions = {
              for (final item in catalogSnapshot.data!.positions)
                item.id: item.label,
            };
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return CareerPageHeader(
                    title: 'Formação do futuro',
                    subtitle:
                        '${rows.length} jogadores acompanhados na academia.',
                    icon: Icons.school_outlined,
                    eyebrow: 'Categorias de base',
                  );
                }
                final row = rows[index - 1];
                return Card(
                  child: ListTile(
                    leading: const CareerIconBadge(
                      icon: Icons.person_outline_rounded,
                    ),
                    title: Text(row['name'] as String),
                    subtitle: Text(
                      [
                        positions[row['positionId']] ??
                            row['positionId'].toString(),
                        '${'history.overallShort'.tr()} ${row['overall']}',
                        '${'players.potShort'.tr()} ${row['potentialStart']}–${row['potentialEnd']}',
                      ].join(' • '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(row),
                  ),
                );
              },
            );
          },
        );
      },
    ),
  );
}
