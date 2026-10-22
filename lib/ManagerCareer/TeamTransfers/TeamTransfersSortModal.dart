import '../../utils/AppColors.dart';

import 'package:flutter/material.dart';

enum TransfersSortField { date, player, value }

typedef TransfersSort = ({TransfersSortField field, bool descending});

Future<TransfersSort?> showTransfersSortModal(
  BuildContext context,
  TransfersSort current,
) => showModalBottomSheet<TransfersSort>(
  context: context,
  backgroundColor: AppColors.of(context).panel,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Ordenar transferências', style: TextStyle(fontSize: 18)),
        ),
        for (final option in const <(String, TransfersSort)>[
          (
            'Data: mais recentes primeiro',
            (field: TransfersSortField.date, descending: true),
          ),
          (
            'Data: mais antigas primeiro',
            (field: TransfersSortField.date, descending: false),
          ),
          (
            'Jogador: A–Z',
            (field: TransfersSortField.player, descending: false),
          ),
          (
            'Valor: maior primeiro',
            (field: TransfersSortField.value, descending: true),
          ),
        ])
          ListTile(
            title: Text(option.$1),
            trailing: current == option.$2
                ? Icon(Icons.check, color: AppColors.of(context).accent)
                : null,
            onTap: () => Navigator.pop(context, option.$2),
          ),
      ],
    ),
  ),
);
