import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Twitter/TwitterPlayerAssessment.dart';

void main() {
  List<Map<String, Object?>> strikerSeason({num? today}) => [
    {'rating': today, 'goals': 0, 'assists': 0},
    for (var i = 0; i < 14; i++) {'rating': 8.0, 'goals': 1, 'assists': 0},
  ];

  test(
    '14 goals in 15 matches and no goal today do not create a criticism target',
    () {
      final player = TwitterPlayerAssessment(
        performance: {'rating': 6.8, 'goals': 0},
        history: strikerSeason(today: 6.8),
      );
      expect(player.context['season'], containsPair('goals', 14));
      expect(player.strongSeason, isTrue);
      expect(player.poorRecentForm, isFalse);
      expect(player.criticism('Artilheiro'), isNull);
      expect(player.context['criticismScope'], 'none');
    },
  );

  test('A bad day for a productive striker gets punctual criticism with strong tone', () {
    final player = TwitterPlayerAssessment(
      performance: {'rating': 5.4},
      history: strikerSeason(today: 5.4),
    );
    final target = player.criticism('Artilheiro')!;
    expect(target.scope, 'today');
    expect(target.strongSeason, isTrue);
    expect(
      target.angle(true),
      contains('xinga a atuação de hoje de Artilheiro'),
    );
    expect(target.angle(true), contains('com palavrão'));
    expect(target.angle(true), contains('respeite a boa temporada'));
    expect(
      TwitterPlayerAssessment.fromContext('Artilheiro', {
        'assessment': player.context,
      })?.scope,
      'today',
    );
  });

  test('Several recorded bad performances allow criticism of recent form', () {
    final player = TwitterPlayerAssessment(
      performance: {'rating': 5.2},
      history: [
        for (final rating in [5.2, 5.4, 5.7, 6.0, 6.1])
          {'rating': rating, 'goals': 0},
      ],
    );
    expect(player.criticism('Em má fase')?.scope, 'recentForm');
    expect(player.strongSeason, isFalse);
  });

  test(
    'Two bad games or missing recent ratings do not manufacture a slump',
    () {
      final player = TwitterPlayerAssessment(
        performance: {'rating': 5.4},
        history: [
          {'rating': 5.4},
          {'rating': 5.6},
          {},
          {},
          {},
          {'rating': 5.0},
          {'rating': 5.1},
          {'rating': 5.2},
        ],
      );
      expect(player.poorRecentForm, isFalse);
      expect(player.criticism('Jogador')?.scope, 'today');
    },
  );

  test(
    'Unknown ratings and zero goals do not blame a defender or goalkeeper',
    () {
      for (final rating in [null, 0, 6.5, 8.5]) {
        final player = TwitterPlayerAssessment(
          performance: {'rating': rating, 'goals': 0, 'assists': 0},
          history: [],
        );
        expect(player.criticism('Defensor'), isNull);
      }
    },
  );

  test('A missed penalty or own goal can be criticized without erasing a good game', () {
    final player = TwitterPlayerAssessment(
      performance: {'rating': 8.0, 'missedPenalties': 1},
      history: strikerSeason(today: 8.0),
    );
    final target = player.criticism('Artilheiro')!;
    expect(target.reasons, ['pênalti perdido registrado']);
    expect(target.scope, 'today');
    expect(target.strongSeason, isTrue);
    final ownGoal = TwitterPlayerAssessment(
      performance: {'ownGoals': 1},
      history: [],
    );
    expect(ownGoal.criticism('Zagueiro')?.reasons, ['gol contra registrado']);
  });
}
