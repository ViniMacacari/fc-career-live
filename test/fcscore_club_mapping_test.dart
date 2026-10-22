import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/FcScore/FcScoreRepository.dart';
import 'package:mcmanager/utils/GameCatalog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameCatalog catalog;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory('build/fcscore-club-test-docs').absolute.path,
        );
    catalog = await GameCatalog.load();
  });

  for (final version in GameCatalog.fifaVersions) {
    test('Real catalog links Brazilian clubs by name in $version', () {
      final teams = catalog.teams(version);
      for (final name in [
        'Botafogo',
        'Flamengo',
        'Palmeiras',
        'Corinthians',
        'Santos',
        'Sao Paulo',
      ]) {
        final matches = teams.where((t) => t.label == name).toList();
        expect(matches, isNotEmpty, reason: '$version $name');
        final chosen = fcSuggestReference({
          'id': 'different-api-id',
          'name': name,
        }, teams);
        expect(chosen, isNotNull, reason: '$version $name');
        final primary = matches.where((t) => !t.isSupplementalClub).toList();
        expect(chosen, primary.isEmpty ? matches.single.id : primary.single.id);
        for (final entry in matches) {
          expect(
            fcSuggestReference(
              {'id': 'different-api-id', 'name': name},
              teams,
              leagueId: entry.leagueId,
            ),
            entry.id,
          );
        }
      }
      if (version != 'FIFA23') {
        expect(
          fcSuggestReference({
            'id': 'different-api-id',
            'name': 'Botafogo-SP',
          }, teams),
          '101-7',
        );
      }
      expect(
        fcSuggestReference({
          'id': 'different-api-id',
          'name': 'Botafogo-PB',
        }, teams),
        isNull,
      );
    });
  }

  test('Ambiguous distinct clubs require identity or league, not the first name match', () {
    final teams = [
      const CatalogItem('a', 'United', leagueId: 'one', clubIdentity: 'club-a'),
      const CatalogItem('b', 'United', leagueId: 'two', clubIdentity: 'club-b'),
      const CatalogItem('collision', 'Different'),
    ];
    expect(
      fcSuggestReference({'id': 'unknown', 'name': 'United'}, teams),
      isNull,
    );
    expect(
      fcSuggestReference({'id': 'collision', 'name': 'United'}, teams),
      isNull,
    );
    expect(fcSuggestReference({'id': 'a', 'name': 'United'}, teams), 'a');
    expect(
      fcSuggestReference(
        {'id': 'unknown', 'name': 'United'},
        teams,
        leagueId: 'two',
      ),
      'b',
    );
    expect(
      fcSuggestReference(
        {'id': 'unknown', 'name': 'Botafogo'},
        [
          const CatalogItem('custom-a', 'Botafogo', isCustom: true),
          const CatalogItem('custom-b', 'Botafogo', isCustom: true),
        ],
      ),
      isNull,
    );
  });
}
