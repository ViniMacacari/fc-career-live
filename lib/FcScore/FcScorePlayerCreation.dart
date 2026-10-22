import 'dart:convert';
import 'dart:math';

import 'FcScoreApi.dart';
import 'FcScoreModels.dart';

const _draftPrefix = 'new-player:';
bool fcIsPlayerDraft(String? choice) =>
    choice?.startsWith(_draftPrefix) == true;
bool fcIsPlayerCreation(String? choice) =>
    choice == null ||
    choice.isEmpty ||
    choice == 'new' ||
    fcIsPlayerDraft(choice);
bool fcValidPlayerRating(Object? value) {
  final number = fcInt(value);
  return number != null && number >= 1 && number <= 99;
}

bool fcCanCreatePlayer(FcJson source) =>
    fcName(source['name'], '').trim().isNotEmpty &&
    fcValidPlayerRating(source['overall']);

FcJson fcPlayerDraft(String choice) {
  try {
    final value = fcObject(jsonDecode(choice.substring(_draftPrefix.length)));
    if (fcId(value['sourceId']).isEmpty || fcObject(value['profile']).isEmpty) {
      throw const FormatException();
    }
    return value;
  } catch (_) {
    throw const FcScoreException(
      'Revise os dados do jogador criado nesta tela.',
    );
  }
}

String fcCreatePlayerChoice(
  FcJson source,
  FcJson profile, {
  bool generated = false,
}) {
  final positions = profile['positions'] is List
      ? profile['positions'] as List
      : const [];
  if (fcId(source['id']).isEmpty ||
      fcName(profile['name'], '').trim().isEmpty ||
      !fcValidPlayerRating(profile['overall']) ||
      !fcValidPlayerRating(profile['potential']) ||
      !fcPositions.take(28).contains(positions.firstOrNull)) {
    throw const FcScoreException(
      'Confira nome, posição, overall e potencial do jogador.',
    );
  }
  return '$_draftPrefix${jsonEncode({
    'sourceId': fcId(source['id']),
    'generated': generated,
    'profile': {
      for (final key in ['name', 'overall', 'potential', 'positions', 'age', 'birthDate', 'nationality', 'preferredFoot'])
        if (profile[key] != null) key: profile[key],
    },
  })}';
}

FcJson fcPlayerWithChoice(FcJson source, String? choice) {
  if (!fcIsPlayerDraft(choice)) return source;
  final draft = fcPlayerDraft(choice!);
  if (fcId(draft['sourceId']) != fcId(source['id'])) {
    throw const FcScoreException(
      'O jogador criado pertence a outro vínculo. Revise a seleção.',
    );
  }
  final profile = fcObject(draft['profile']);
  fcCreatePlayerChoice(source, profile);
  return {
    ...source,
    for (final key in [
      'name',
      'overall',
      'potential',
      'positions',
      'age',
      'birthDate',
      'nationality',
      'preferredFoot',
    ])
      if (profile[key] != null) key: profile[key],
  };
}

FcJson fcGeneratePlayerProfile(FcJson source, {Random? random}) {
  final rng = random ?? Random();
  const first = [
    'Gabriel',
    'Lucas',
    'Matheus',
    'Rafael',
    'João',
    'Pedro',
    'Samuel',
    'Daniel',
    'Bruno',
    'Diego',
    'Arthur',
    'Felipe',
    'André',
    'Caio',
    'Henrique',
    'Gustavo',
  ];
  const last = [
    'Silva',
    'Santos',
    'Oliveira',
    'Souza',
    'Costa',
    'Pereira',
    'Almeida',
    'Lima',
    'Rocha',
    'Martins',
    'Ribeiro',
    'Carvalho',
    'Barbosa',
    'Moreira',
    'Cardoso',
    'Mendes',
  ];
  final overall = fcValidPlayerRating(source['overall'])
      ? fcInt(source['overall'])!
      : 55 + rng.nextInt(26);
  final potential = fcValidPlayerRating(source['potential'])
      ? fcInt(source['potential'])!
      : min(99, overall + rng.nextInt(13));
  final positions = source['positions'] is List
      ? source['positions'] as List
      : const [];
  const generatedPositions = [
    'GK',
    'RB',
    'CB',
    'LB',
    'CDM',
    'CM',
    'CAM',
    'RW',
    'ST',
    'LW',
  ];
  return {
    ...source,
    'name': fcName(source['name'], '').trim().isNotEmpty
        ? source['name']
        : '${first[rng.nextInt(first.length)]} ${last[rng.nextInt(last.length)]}',
    'overall': overall,
    'potential': potential,
    'positions':
        positions.isNotEmpty && fcPositions.take(28).contains(positions.first)
        ? positions
        : [generatedPositions[rng.nextInt(generatedPositions.length)]],
    'age': (fcInt(source['age']) ?? 0) > 0
        ? source['age']
        : 18 + rng.nextInt(14),
    'preferredFoot':
        ['left', 'right'].contains(fcId(source['preferredFoot']).toLowerCase())
        ? source['preferredFoot']
        : (rng.nextInt(4) == 0 ? 'left' : 'right'),
  };
}
