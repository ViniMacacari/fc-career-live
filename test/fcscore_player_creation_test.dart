import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/FcScore/FcScorePlayerCreation.dart';

import 'fcscore_fixture.dart';

void main() {
  test('Generation fills missing identity without replacing valid API fields or statistics', () {
    final source = {
      ...apiPlayer(98511, ''),
      'overall': null,
      'leagueGoals': 14,
      'leagueAppearances': 15,
    };
    final generated = fcGeneratePlayerProfile(source, random: Random(5));
    expect(fcName(generated['name']), isNotEmpty);
    expect(fcValidPlayerRating(generated['overall']), isTrue);
    for (final field in [
      'id',
      'potential',
      'age',
      'birthDate',
      'nationality',
      'preferredFoot',
      'positions',
      'leagueGoals',
      'leagueAppearances',
    ]) {
      expect(generated[field], source[field], reason: field);
    }
    expect(source['overall'], isNull);
    expect(fcName(source['name'], ''), isEmpty);
    expect(
      fcGeneratePlayerProfile(apiPlayer(10, 'Pedro'), random: Random(1)),
      apiPlayer(10, 'Pedro'),
    );
  });
  test('Draft choices survive career mapping copies and cannot overwrite source IDs or goals', () {
    final source = {...apiPlayer(20, ''), 'overall': null, 'leagueGoals': 18};
    final choice = fcCreatePlayerChoice(source, {
      ...fcGeneratePlayerProfile(source, random: Random(2)),
      'id': 999,
      'leagueGoals': 999,
    }, generated: true);
    final link = apiLink()..players['20'] = choice;
    final effective = fcPlayerWithChoice(source, link.copy().players['20']);
    expect(effective['id'], 20);
    expect(effective['leagueGoals'], 18);
    expect(fcCanCreatePlayer(effective), isTrue);
    expect(fcPlayerDraft(choice)['generated'], isTrue);
    expect(fcIsPlayerCreation(choice), isTrue);
  });
  test('Malformed, incomplete and wrong-player drafts are rejected', () {
    final source = apiPlayer(20, 'João');
    final choice = fcCreatePlayerChoice(source, source);
    expect(
      () => fcPlayerWithChoice(apiPlayer(30, 'Lucas'), choice),
      throwsA(isA<FcScoreException>()),
    );
    expect(
      () => fcPlayerWithChoice(source, 'new-player:invalid'),
      throwsA(isA<FcScoreException>()),
    );
    for (final value in [0, 100, null, 'inválido']) {
      expect(
        () => fcCreatePlayerChoice(source, {...source, 'overall': value}),
        throwsA(isA<FcScoreException>()),
      );
    }
    expect(
      () => fcCreatePlayerChoice(source, {...source, 'positions': 'ST'}),
      throwsA(isA<FcScoreException>()),
    );
    expect(
      () => fcCreatePlayerChoice(source, {...source, 'name': ''}),
      throwsA(isA<FcScoreException>()),
    );
  });
}
