enum TeamTransferType {
  buy,
  sell,
  inLoan,
  outLoan,
  endOfLoan,
  prematureEndOfLoan,
  freeTransfer,
  endOfContract,
  youthAcademy,
  retired,
  buyFromLoan,
  sellFromLoan,
}

String teamTransferTypeKey(TeamTransferType type) => 'teams.${type.name}';

DateTime? teamTransferEffectiveDate(Map<String, Object?> row) =>
    DateTime.tryParse(
      (row['actualReleaseDate'] ?? row['releaseDate'] ?? row['date'])
              ?.toString() ??
          '',
    );

String transferTypeLabel(TeamTransferType type) => switch (type) {
  TeamTransferType.buy => 'Comprar',
  TeamTransferType.sell => 'Vender',
  TeamTransferType.buyFromLoan => 'Contratar jogador emprestado',
  TeamTransferType.sellFromLoan => 'Vender jogador emprestado',
  TeamTransferType.inLoan => 'Contratar por empréstimo',
  TeamTransferType.outLoan => 'Emprestar',
  TeamTransferType.endOfLoan => 'Voltar de Empréstimo',
  TeamTransferType.prematureEndOfLoan => 'Encerrar empréstimo antes do prazo',
  TeamTransferType.freeTransfer => 'Transferência Gratuita',
  TeamTransferType.endOfContract => 'Fim de Contrato',
  TeamTransferType.youthAcademy => 'Academia de Jovens',
  TeamTransferType.retired => 'Aposentado',
};

TeamTransferType transferTypeFromRow(Map<String, Object?> row) =>
    TeamTransferType.values
        .where((type) => type.name == row['type'])
        .firstOrNull ??
    TeamTransferType.buy;

bool isIncomingTeamTransfer(Map<String, Object?> row, String teamId) {
  if (row['manualDeparture'] == true) return false;
  final type = transferTypeFromRow(row);
  return switch (type) {
    TeamTransferType.endOfLoan || TeamTransferType.prematureEndOfLoan =>
      row['endOfLoanDirection'] == 'toYouClub' ||
          (row['endOfLoanDirection'] == null && row['toTeamId'] == teamId),
    TeamTransferType.freeTransfer => row['fromTeamId'] != teamId,
    TeamTransferType.buy ||
    TeamTransferType.inLoan ||
    TeamTransferType.buyFromLoan ||
    TeamTransferType.youthAcademy => true,
    _ => false,
  };
}

String transferCardLabel(Map<String, Object?> row) =>
    row['manualDeparture'] == true
    ? 'Saída do elenco'
    : switch (transferTypeFromRow(row)) {
        TeamTransferType.buy ||
        TeamTransferType.sell ||
        TeamTransferType.buyFromLoan ||
        TeamTransferType.sellFromLoan => 'Transferência',
        TeamTransferType.youthAcademy => 'Veio da Academia de Jovens',
        TeamTransferType.inLoan => 'Chegou por empréstimo',
        TeamTransferType.outLoan => 'Emprestado',
        TeamTransferType.endOfLoan =>
          row['endOfLoanDirection'] == 'fromYourClub'
              ? 'Devolvido ao clube de origem'
              : 'Voltou de empréstimo',
        TeamTransferType.prematureEndOfLoan =>
          'Empréstimo encerrado antes do prazo',
        final type => transferTypeLabel(type),
      };
