class PlayerValueHistory {
  static List<Map<String, Object?>> combine(
    List<Map<String, Object?>> records,
    List<Map<String, Object?>> seasons,
    String table,
  ) {
    final field = table == 'Overall' ? 'overall' : 'value';
    final source = table == 'Overall' ? 'overall' : 'marketValue';
    final rows = <Map<String, Object?>>[
      ...records,
      for (final season in seasons)
        if (season[source] is num)
          {
            'id': 'season-start:$table:${season['id']}',
            'personId': season['personId'],
            'customPlayerId': season['playerId'],
            'seasonId': season['seasonId'],
            'date': season['seasonStartDate'],
            'createdAt': season['seasonCreatedAt'],
            field: season[source],
            'isSeasonInitial': true,
          },
    ];
    final order = {for (var i = 0; i < rows.length; i++) rows[i]: i};
    final chronology = _ValueChronology();
    rows.sort((a, b) {
      final result = chronology.compare(a, b);
      return result != 0 ? result : order[a]!.compareTo(order[b]!);
    });
    return rows;
  }

  static Map<String, Map<String, Object?>> latest(
    List<Map<String, Object?>> records,
    List<Map<String, Object?>> seasons,
    String table,
  ) {
    final field = table == 'Overall' ? 'overall' : 'value';
    final source = table == 'Overall' ? 'overall' : 'marketValue';
    final result = <String, Map<String, Object?>>{};
    final chronology = _ValueChronology();
    void add(Map<String, Object?> row) {
      final id = row['customPlayerId'];
      if (id is! String || row[field] is! num) return;
      final previous = result[id];
      if (previous == null || chronology.compare(row, previous) < 0) {
        result[id] = row;
      }
    }

    for (final row in records) {
      add(row);
    }
    for (final season in seasons) {
      if (season[source] is! num) continue;
      add({
        'customPlayerId': season['playerId'],
        'date': season['seasonStartDate'],
        'createdAt': season['seasonCreatedAt'],
        field: season[source],
        'isSeasonInitial': true,
      });
    }
    return result;
  }
}

class _ValueChronology {
  final _dates = <String, DateTime?>{};
  DateTime? date(Object? value) {
    final text = value?.toString() ?? '';
    return _dates.putIfAbsent(text, () => DateTime.tryParse(text));
  }

  int compareDate(Object? a, Object? b) {
    final first = date(a), second = date(b);
    if (first == null) return second == null ? 0 : 1;
    return second == null ? -1 : second.compareTo(first);
  }

  int compare(Map<String, Object?> a, Map<String, Object?> b) {
    final byDate = compareDate(a['date'], b['date']);
    if (byDate != 0) return byDate;
    if ((a['isSeasonInitial'] == true) != (b['isSeasonInitial'] == true)) {
      return a['isSeasonInitial'] == true ? 1 : -1;
    }
    return compareDate(a['createdAt'], b['createdAt']);
  }
}
