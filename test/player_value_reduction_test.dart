import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/utils/PlayerValueHistory.dart';

void main() {
  test('Linear current values equal full timelines with season starts, timezone dates and stable ties', () {
    final records = <Map<String, Object?>>[
      {
        'customPlayerId': 'a',
        'date': '2029-01-01',
        'createdAt': '2029-01-02',
        'overall': 79,
      },
      {'customPlayerId': 'a', 'date': '2028-12-31', 'overall': 77},
      {
        'customPlayerId': 'b',
        'date': '2029-01-01T03:00:00Z',
        'createdAt': '2029-02-01T01:00:00.000002Z',
        'overall': 85,
      },
      {
        'customPlayerId': 'b',
        'date': '2029-01-01T00:00:00-03:00',
        'createdAt': '2029-02-01T01:00:00.000001Z',
        'overall': 84,
      },
      {'customPlayerId': 'c', 'date': 'invalid', 'overall': 60},
      {'customPlayerId': 'c', 'date': 'invalid', 'overall': 59},
      {'customPlayerId': 'd', 'date': '2028-11-01', 'overall': 73},
    ];
    final seasons = <Map<String, Object?>>[
      {
        'id': 'sa',
        'playerId': 'a',
        'seasonStartDate': '2029-01-01',
        'overall': 78,
      },
      {
        'id': 'sd',
        'playerId': 'd',
        'seasonStartDate': '2029-01-01',
        'overall': 76,
      },
    ];
    final expected = <String, Object?>{};
    for (final row in PlayerValueHistory.combine(records, seasons, 'Overall')) {
      expected.putIfAbsent(
        row['customPlayerId'] as String,
        () => row['overall'],
      );
    }
    final actual = PlayerValueHistory.latest(records, seasons, 'Overall');
    expect({
      for (final e in actual.entries) e.key: e.value['overall'],
    }, expected);
    expect(expected, {'a': 79, 'b': 85, 'c': 60, 'd': 76});
  });
}
