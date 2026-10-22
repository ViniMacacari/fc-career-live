import '../../utils/AppColors.dart';

import 'package:flutter/material.dart';

import '../../models/TeamTransferItem.dart';
import 'TransferStyle.dart';

class SelectTransferTypePage extends StatelessWidget {
  const SelectTransferTypePage({super.key, required this.selected});
  final TeamTransferType selected;

  @override
  Widget build(BuildContext context) => TransferTheme(
    child: Scaffold(
      appBar: AppBar(title: const Text('Tipo de transferência')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          _group(context, 'Transferência definitiva', const [
            TeamTransferType.buy,
            TeamTransferType.sell,
            TeamTransferType.buyFromLoan,
            TeamTransferType.sellFromLoan,
          ]),
          _group(context, 'Empréstimo', const [
            TeamTransferType.outLoan,
            TeamTransferType.endOfLoan,
            TeamTransferType.inLoan,
            TeamTransferType.prematureEndOfLoan,
          ]),
          _group(context, 'Outro', const [
            TeamTransferType.freeTransfer,
            TeamTransferType.endOfContract,
            TeamTransferType.youthAcademy,
            TeamTransferType.retired,
          ]),
        ],
      ),
    ),
  );

  Widget _group(
    BuildContext context,
    String title,
    List<TeamTransferType> types,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 0, 5),
        child: Text(title),
      ),
      for (final type in types)
        Card(
          color: AppColors.of(context).panel,
          margin: const EdgeInsets.only(bottom: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 5,
            ),
            title: Text(
              transferTypeLabel(type),
              style: const TextStyle(fontSize: 16),
            ),
            subtitle: switch (type) {
              TeamTransferType.outLoan => const Text(
                'Enviar um jogador para outro clube.',
              ),
              TeamTransferType.endOfLoan => const Text(
                'Trazer de volta um jogador emprestado.',
              ),
              TeamTransferType.inLoan => const Text(
                'Receber um jogador de outro clube por empréstimo.',
              ),
              _ => null,
            },
            trailing: selected == type
                ? Icon(Icons.check, color: AppColors.of(context).accent)
                : null,
            onTap: () => Navigator.pop(context, type),
          ),
        ),
      const SizedBox(height: 4),
    ],
  );
}
