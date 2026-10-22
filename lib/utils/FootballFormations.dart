const _sidedPositions = {
  '1': '5',
  '4': '5',
  '6': '5',
  '9': '10',
  '11': '10',
  '13': '14',
  '15': '14',
  '17': '18',
  '19': '18',
  '20': '21',
  '22': '21',
  '24': '25',
  '26': '25',
};

String? canonicalPositionId(String? id) => _sidedPositions[id] ?? id;

const footballPositionOrder = [
  '0',
  '3',
  '2',
  '5',
  '7',
  '8',
  '10',
  '14',
  '12',
  '16',
  '18',
  '23',
  '27',
  '21',
  '25',
];

int footballPositionRank(String? id) {
  final index = footballPositionOrder.indexOf(canonicalPositionId(id) ?? '');
  return index < 0 ? footballPositionOrder.length : index;
}

const footballFormations = <String, List<int>>{
  '4-3-3': [3, 3, 4, 1],
  '4-4-2': [2, 4, 4, 1],
  '3-5-2': [2, 5, 3, 1],
  '4-2-3-1': [1, 3, 2, 4, 1],
  '3-1-4-2': [2, 4, 1, 3, 1],
  '3-4-1-2': [2, 1, 4, 3, 1],
  '3-4-2-1': [1, 2, 4, 3, 1],
  '3-4-3': [3, 4, 3, 1],
  '3-4-3 (losango)': [3, 1, 2, 1, 3, 1],
  '3-2-4-1': [1, 4, 2, 3, 1],
  '3-3-1-3': [3, 1, 3, 3, 1],
  '4-1-2-1-2': [2, 1, 2, 1, 4, 1],
  '4-1-2-1-2 (aberto)': [2, 1, 2, 1, 4, 1],
  '4-1-3-2': [2, 3, 1, 4, 1],
  '4-1-4-1': [1, 4, 1, 4, 1],
  '4-2-1-3': [3, 1, 2, 4, 1],
  '4-2-2-2': [2, 2, 2, 4, 1],
  '4-2-3-1 (aberto)': [1, 3, 2, 4, 1],
  '4-2-4': [4, 2, 4, 1],
  '4-3-1-2': [2, 1, 3, 4, 1],
  '4-3-2-1': [1, 2, 3, 4, 1],
  '4-3-3 (volante)': [3, 2, 1, 4, 1],
  '4-3-3 (defensivo)': [3, 1, 2, 4, 1],
  '4-3-3 (ofensivo)': [3, 1, 2, 4, 1],
  '4-3-3 (falso 9)': [2, 1, 3, 4, 1],
  '4-4-1-1': [1, 1, 4, 4, 1],
  '4-4-1-1 (meia)': [1, 1, 4, 4, 1],
  '4-4-2 (volantes)': [2, 2, 2, 4, 1],
  '4-5-1': [1, 5, 4, 1],
  '4-5-1 (ofensivo)': [1, 2, 3, 4, 1],
  '5-2-1-2': [2, 1, 2, 5, 1],
  '5-2-2-1': [1, 2, 2, 5, 1],
  '5-2-3': [3, 2, 5, 1],
  '5-3-2': [2, 3, 5, 1],
  '5-4-1': [1, 4, 5, 1],
  '5-1-2-2': [2, 2, 1, 5, 1],
  '5-1-3-1': [1, 3, 1, 5, 1],
  '2-3-5': [5, 3, 2, 1],
};

List<int>? customFootballFormation(String text) {
  final parts = text.trim().split(RegExp(r'\s*[-–]\s*'));
  if (parts.length < 2 || parts.length > 5) return null;
  final lines = parts.map(int.tryParse).toList();
  if (lines.any((n) => n == null || n < 1 || n > 9)) return null;
  if (lines.cast<int>().fold<int>(0, (a, b) => a + b) != 10) return null;
  return [...lines.cast<int>().reversed, 1];
}

List<int> footballFormationShape(String label) =>
    footballFormations[label] ??
    customFootballFormation(label) ??
    footballFormations['4-3-3']!;

String footballSlotPosition(List<int> shape, int x, int y) {
  if (y == shape.length - 1) return '0';
  if (y == shape.length - 2) {
    if (shape[y] >= 4 && x == 0) return '7';
    if (shape[y] >= 4 && x == shape[y] - 1) return '3';
    return '5';
  }
  if (y == 0) {
    if (shape[y] >= 3 && x == 0) return '27';
    if (shape[y] >= 3 && x == shape[y] - 1) return '23';
    return '25';
  }
  if (shape[y] >= 3) {
    if (x == 0) return shape[shape.length - 2] == 3 ? '8' : '16';
    if (x == shape[y] - 1) return shape[shape.length - 2] == 3 ? '2' : '12';
  }
  if (shape.length >= 5 && y == shape.length - 3 && shape[y] <= 2) return '10';
  return shape.length >= 5 && y == 1 ? '18' : '14';
}

String? inferFootballFormation(Iterable<String?> input) {
  final positions = input
      .map(canonicalPositionId)
      .whereType<String>()
      .where((p) => p.isNotEmpty)
      .toList();
  if (positions.length != 11 || positions.where((p) => p == '0').length != 1) {
    return null;
  }
  int count(Set<String> ids) => positions.where(ids.contains).length;
  final backs = count({'2', '3', '4', '5', '6', '7', '8'});
  final attack = count({'20', '21', '22', '23', '24', '25', '26', '27'});
  final mids = 10 - backs - attack;
  if (backs < 2 || backs > 5 || attack < 1 || attack > 5 || mids < 1) {
    return null;
  }
  final holding = count({'10'}), advanced = count({'18'});
  if (attack >= 2 && advanced > 0 && advanced < mids) {
    if (holding == 1 && advanced == 1 && mids == 4 && attack == 2) {
      return '$backs-1-2-1-2';
    }
    return '$backs-${mids - advanced}-$advanced-$attack';
  }
  if (holding > 0 && holding < mids) {
    final middle = mids - holding;
    return '$backs-$holding-$middle-$attack';
  }
  if (advanced > 0 && advanced < mids) {
    return '$backs-${mids - advanced}-$advanced-$attack';
  }
  return '$backs-$mids-$attack';
}

bool hasFootballPlayerName(Object? value) {
  final name = value?.toString().trim() ?? '';
  return name.isNotEmpty && name != '?' && name != '—';
}

bool hasFootballIdentity(Map<String, Object?> player) {
  if (!hasFootballPlayerName(player['name'])) return false;
  final remote =
      player['apiPlayerId'] ??
      player['realPlayerId'] ??
      ('${player['id']}'.startsWith('fc-opponent:')
          ? '${player['id']}'.substring(12)
          : null);
  return remote == null || player['name'] != 'Jogador $remote';
}

int footballPositionCost(String? rawPosition, String rawSlot) {
  final position = canonicalPositionId(rawPosition);
  final slot = canonicalPositionId(rawSlot)!;
  if (position == slot) return 0;
  if (position == null || position.isEmpty) return 50;
  int line(String p) => p == '0'
      ? 3
      : {'2', '3', '4', '5', '6', '7', '8'}.contains(p)
      ? 2
      : {'10', '12', '14', '16', '18'}.contains(p)
      ? 1
      : 0;
  int side(String p) => {'7', '8', '16', '27'}.contains(p)
      ? -1
      : {'2', '3', '12', '23'}.contains(p)
      ? 1
      : 0;
  if (position == '0' || slot == '0') return 10000;
  return (line(position) - line(slot)).abs() * 100 +
      (side(position) - side(slot)).abs() * 10 +
      1;
}

double footballRowWidth(String formation, int row, int rows) {
  if (formation == '4-1-2-1-2' && row == 2) return .62;
  if (formation == '4-2-2-2' && row <= 1) return .65;
  if (formation == '4-2-3-1' && row == 1) return .72;
  if (formation == '4-3-3 (falso 9)' && row == 0) return .85;
  return 1;
}
