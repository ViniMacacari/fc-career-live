import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Twitter/TwitterAuthors.dart';
import 'package:mcmanager/Twitter/TwitterModels.dart';

void main() {
  TwitterAuthors authors({String? opponent}) => TwitterAuthors(
    'career',
    const [
      TwitterAccount(
        id: 'page',
        personId: 'career',
        name: 'Página Antiga',
        handle: 'paginaantiga',
        kind: TwitterAccountKind.fanPage,
      ),
    ],
    careerTeamId: 'club',
    opponentTeamId: opponent,
  );

  test('clube do torcedor ausente ou impossível não derruba o lote', () {
    final a = authors();
    expect(
      () => a.register(
        [
          {'name': 'Ana Tricolor', 'handle': 'anatricolor', 'kind': 'fan'},
          {
            'name': 'Zé Rival',
            'handle': 'zerival',
            'kind': 'rival',
            'supports': 'opponent',
          },
          {'name': 'torcedor 1', 'handle': 'torcedor1', 'kind': 'fan'},
          {'handle': 'semnome', 'kind': 'fan'},
          'lixo',
        ],
        affiliations: [
          {'handle': 'paginaantiga'},
          {'handle': 'naoexiste', 'supports': 'career'},
          42,
        ],
      ),
      returnsNormally,
    );
    expect(a.author({'author': 'anatricolor'}), isNotNull);
    expect(a.audience(a.author({'author': 'anatricolor'})!), 'career');
    expect(a.audience(a.author({'author': 'zerival'})!), 'rival');
    expect(a.audience(a.author({'author': 'paginaantiga'})!), 'career');
    expect(a.author({'author': 'torcedor1'}), isNull);
    expect(a.author({'author': 'semnome'}), isNull);
  });

  test('torcedor do adversário quando há adversário', () {
    final a = authors(opponent: 'cruzeiro')
      ..register([
        {
          'name': 'Raposa Doida',
          'handle': 'raposadoida',
          'kind': 'rival',
          'supports': 'opponent',
        },
      ]);
    expect(a.author({'author': 'raposadoida'})!.supportedTeamId, 'cruzeiro');
  });

  test('amostra por tipo do tamanho do lote e poucas contas novas', () {
    TwitterAccount account(TwitterAccountKind kind, int i) => TwitterAccount(
      id: '${kind.name}$i',
      personId: 'career',
      name: '${kind.name} $i',
      handle: '${kind.name}$i',
      kind: kind,
    );
    final authors = TwitterAuthors('career', [
      for (var i = 0; i < 30; i++) account(TwitterAccountKind.fan, i),
      for (var i = 0; i < 10; i++) account(TwitterAccountKind.rival, i),
      for (var i = 0; i < 8; i++) account(TwitterAccountKind.fanPage, i),
      for (var i = 0; i < 5; i++) account(TwitterAccountKind.journal, i),
    ], careerTeamId: 'club');
    final needed = TwitterAuthors.needs(
      postKinds: [
        ...List.filled(6, 'fan'),
        'fanPage',
        'fanPage',
        'journal',
        'rival',
      ],
      replies: 20,
    );
    final recent = {for (var i = 0; i < 25; i++) 'fan$i'};
    final offered = authors.forPrompt(
      Random(1),
      recentHandles: recent,
      needed: needed,
    );
    int count(TwitterAccountKind kind) =>
        offered.where((a) => a.kind == kind).length;
    expect(count(TwitterAccountKind.fan), 20);
    expect(count(TwitterAccountKind.rival), 8);
    expect(count(TwitterAccountKind.fanPage), 7);
    expect(count(TwitterAccountKind.journal), 4);
    expect(
      offered
          .where((a) => a.kind == TwitterAccountKind.fan)
          .take(5)
          .every((a) => !recent.contains(a.handle)),
      isTrue,
    );
    expect(TwitterAuthors.newAccountsAllowed(needed, offered), 6);

    final replies = TwitterAuthors.needs(replies: 3);
    final forReplies = authors.forPrompt(Random(2), needed: replies);
    expect(
      forReplies.any((a) => a.kind == TwitterAccountKind.journal),
      isFalse,
    );
    expect(TwitterAuthors.newAccountsAllowed(replies, forReplies), 2);
  });
}
