import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../models/Person.dart';
import '../../models/TeamTransferItem.dart';
import '../../utils/GameCatalog.dart';

class RosterDepartureChoice {
  const RosterDepartureChoice({this.transferId});
  final String? transferId;
}

Future<RosterDepartureChoice?> confirmRosterDeparture(
  BuildContext context, {
  required Person person,
  required String name,
  required List<Map<String, Object?>> pending,
}) {
  String? transferId;
  final theme = Theme.of(context);
  final font = TextStyle(fontFamily: theme.textTheme.bodyMedium?.fontFamily);
  return showDialog<RosterDepartureChoice>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        scrollable: true,
        title: Text('Remover jogador?', style: font),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Deseja remover $name do elenco desta temporada?\n\n'
                'As estatísticas e o histórico do jogador serão mantidos.',
                style: font,
              ),
              const SizedBox(height: 20),
              Text(
                'Vincular a uma transferência em aberto?',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              if (pending.isEmpty)
                Text(
                  'Nenhuma transferência com liberação pendente para este jogador. '
                  'A saída será registrada sem vínculo.',
                  style: font,
                )
              else ...[
                DropdownButtonFormField<String>(
                  key: const ValueKey('departure-transfer'),
                  initialValue: '',
                  isExpanded: true,
                  isDense: false,
                  itemHeight: null,
                  decoration: const InputDecoration(
                    labelText: 'Transferência (opcional)',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Sem vínculo'),
                    ),
                    for (final row in pending)
                      DropdownMenuItem(
                        value: row['id'] as String,
                        child: Text(
                          '${transferCardLabel(row)} · '
                          '${GameCatalog.current?.teamLabel(person.fifaVersion, row['toTeamId']?.toString() ?? '') ?? 'Destino registrado'} · '
                          '${DateFormat('dd/MM/yyyy').format(DateTime.parse(row['releaseDate'] as String))}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      update(() => transferId = value == '' ? null : value),
                ),
                const SizedBox(height: 12),
                Text(
                  'Se vincular, a transferência terá a saída registrada agora. '
                  'A data de liberação prevista ficará preservada.',
                  style: font,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(
              dialogContext,
              RosterDepartureChoice(transferId: transferId),
            ),
            child: Text('common.remove'.tr()),
          ),
        ],
      ),
    ),
  );
}
